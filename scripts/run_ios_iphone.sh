#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not on PATH. Install Flutter or add its bin directory to PATH." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Xcode command line tools are required to deploy to an iPhone." >&2
  exit 1
fi

# A newer Xcode may be installed without being selected globally. Use the newest
# full Xcode in /Applications so devicectl and the iOS SDK match the connected phone.
export DEVELOPER_DIR="$(python3 - <<'PY'
import glob
import os
import re
import subprocess
import sys

active = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True)
candidates = set(glob.glob("/Applications/Xcode*.app/Contents/Developer"))
if active.returncode == 0:
    candidates.add(active.stdout.strip())

installed = []
for developer_dir in candidates:
    xcodebuild = os.path.join(developer_dir, "usr", "bin", "xcodebuild")
    if not os.path.isfile(xcodebuild):
        continue
    try:
        result = subprocess.run(
            [xcodebuild, "-version"],
            capture_output=True,
            text=True,
            check=True,
            env={**os.environ, "DEVELOPER_DIR": developer_dir},
        )
    except (OSError, subprocess.CalledProcessError):
        continue
    match = re.search(r"^Xcode ([0-9]+(?:\.[0-9]+)*)", result.stdout, re.MULTILINE)
    if match:
        version = tuple(int(part) for part in match.group(1).split("."))
        installed.append((version, developer_dir))

if not installed:
    print("No usable Xcode installation was found.", file=sys.stderr)
    sys.exit(1)

print(max(installed)[1])
PY
)"
echo "Using Xcode at ${DEVELOPER_DIR}"

# Some native-asset build hooks (objective_c) shell out to `xcrun` from Xcode's
# build phase, where DEVELOPER_DIR may not survive. Put a wrapper early on PATH
# so those hooks resolve the iOS SDK from the Xcode selected above.
xcode_tools_dir="${TMPDIR:-/tmp}/muzician-xcode-tools"
mkdir -p "$xcode_tools_dir"
cat > "${xcode_tools_dir}/xcrun" <<'WRAPPER'
#!/bin/sh
if [ -z "${DEVELOPER_DIR:-}" ]; then
  for candidate in /Applications/Xcode*.app/Contents/Developer; do
    [ -d "$candidate" ] && DEVELOPER_DIR="$candidate"
  done
  export DEVELOPER_DIR
fi
exec /usr/bin/xcrun "$@"
WRAPPER
chmod +x "${xcode_tools_dir}/xcrun"
export PATH="${xcode_tools_dir}:${PATH}"

devices_json="$(flutter devices --machine)"
selection="$(MUZICIAN_IOS_DEVICE_ID="${MUZICIAN_IOS_DEVICE_ID:-}" python3 -c '
import json
import os
import sys

devices = json.load(sys.stdin)
iphones = [
    device
    for device in devices
    if device.get("targetPlatform") == "ios"
    and device.get("isSupported", True)
    and not device.get("emulator", False)
]
requested_id = os.environ["MUZICIAN_IOS_DEVICE_ID"]

if requested_id:
    selected = next((device for device in iphones if device.get("id") == requested_id), None)
    if selected is None:
        print(f"No connected physical iPhone matches MUZICIAN_IOS_DEVICE_ID={requested_id}.", file=sys.stderr)
        sys.exit(2)
elif len(iphones) == 1:
    selected = iphones[0]
elif not iphones:
    print("No physical iPhone is available. Connect and unlock it, then run `flutter devices`.", file=sys.stderr)
    sys.exit(2)
else:
    print("More than one physical iPhone is connected. Choose one with MUZICIAN_IOS_DEVICE_ID:", file=sys.stderr)
    for device in iphones:
        device_name = device.get("name", "iPhone")
        device_id = device.get("id", "")
        print(f"  {device_name}: {device_id}", file=sys.stderr)
    sys.exit(2)

selected_id = selected["id"]
selected_name = selected.get("name", "iPhone")
print(f"{selected_id}\t{selected_name}")
' <<<"$devices_json")"

device_id="${selection%%$'\t'*}"
device_name="${selection#*$'\t'}"
app_path="$repo_root/build/ios/iphoneos/Runner.app"

echo "Building Muzician Release for ${device_name} (${device_id})."
flutter build ios --release

# Flutter gives native-asset frameworks such as objective_c an ad-hoc signature.
# Device installs reject ad-hoc code, so re-sign those frameworks with the app's
# identity and re-seal the app, which covers the embedded code.
codesign_identity="$(codesign -dv --verbose=4 "$app_path" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"
if [ -n "$codesign_identity" ]; then
  resigned_framework=false
  for framework in "$app_path"/Frameworks/*.framework; do
    [ -d "$framework" ] || continue
    framework_signature="$(codesign -dv "$framework" 2>&1 || true)"
    if [[ "$framework_signature" == *$'\nSignature=adhoc'* ]]; then
      echo "Re-signing $(basename "$framework") with ${codesign_identity}."
      codesign --force --sign "$codesign_identity" --timestamp=none "$framework"
      resigned_framework=true
    fi
  done
  if [ "$resigned_framework" = true ]; then
    codesign --force --sign "$codesign_identity" --preserve-metadata=entitlements,flags --timestamp=none "$app_path"
    codesign --verify --deep --strict "$app_path"
  fi
else
  echo "Could not determine the app signing identity; install may fail code signature checks." >&2
fi

echo "Installing the standalone app on ${device_name}."
xcrun devicectl device install app --device "$device_id" "$app_path"

echo "Launching Muzician on ${device_name}."
xcrun devicectl device process launch --device "$device_id" io.francescolacriola.muzician
