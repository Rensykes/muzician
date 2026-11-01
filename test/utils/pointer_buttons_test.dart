import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/utils/pointer_buttons.dart';

PointerDownEvent _down(int buttons) => PointerDownEvent(buttons: buttons);

void main() {
  test('treats events without a button mask as primary', () {
    expect(isPrimaryPointerButton(_down(0)), isTrue);
  });

  test('accepts the primary button', () {
    expect(isPrimaryPointerButton(_down(kPrimaryButton)), isTrue);
  });

  test('rejects secondary and tertiary buttons', () {
    expect(isPrimaryPointerButton(_down(kSecondaryButton)), isFalse);
    expect(isPrimaryPointerButton(_down(kTertiaryButton)), isFalse);
  });

  test('rejects button chords without the primary button', () {
    expect(
      isPrimaryPointerButton(_down(kSecondaryButton | kTertiaryButton)),
      isFalse,
    );
  });
}
