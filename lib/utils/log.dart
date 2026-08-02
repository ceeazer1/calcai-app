import 'package:flutter/foundation.dart';

/// Debug-only logging.
///
/// Flutter's own `debugPrint` is **not** compiled out of release builds — it
/// keeps writing to the device log, where anyone with the phone plugged into a
/// Mac can read it in Console.app. None of our messages carry secrets, but
/// they do narrate a user's activity (device MACs, network names, how many
/// notes they have), which has no business leaving a shipped build.
///
/// [kDebugMode] is a compile-time constant, so in release the call and its
/// arguments are tree-shaken away entirely — including any string
/// interpolation, which also makes this marginally cheaper than `debugPrint`.
void logDebug(String message) {
  if (kDebugMode) debugPrint(message);
}
