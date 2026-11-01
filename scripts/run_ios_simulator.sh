#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not on PATH. Install Flutter or add its bin directory to PATH." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Xcode command line tools are required to run an iOS Simulator." >&2
  exit 1
fi

device_id="$(xcrun simctl list devices available --json | python3 -c '
import json
import sys

devices = json.load(sys.stdin).get("devices", {})
iphones = [
    device
    for runtime_devices in devices.values()
    for device in runtime_devices
    if device.get("isAvailable", True) and device.get("name", "").startswith("iPhone")
]
target = next((device for device in iphones if device.get("state") == "Booted"), None)
target = target or next((device for device in iphones if device.get("name") == "iPhone 17 Pro"), None)
target = target or (iphones[0] if iphones else None)
if target:
    print(target["udid"])
')"

if [[ -z "$device_id" ]]; then
  echo "No available iPhone simulator was found. Install an iOS Simulator runtime in Xcode." >&2
  exit 1
fi

open -a Simulator
exec flutter run -d "$device_id"
