import 'package:flutter/gestures.dart';

/// True when [event] comes from the primary mouse button, or from an input
/// device that reports no button mask (touch, some styluses).
bool isPrimaryPointerButton(PointerEvent event) =>
    event.buttons == 0 || (event.buttons & kPrimaryButton) != 0;
