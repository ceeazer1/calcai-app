import 'package:url_launcher/url_launcher.dart';

import 'log.dart';

/// Opens this app's page in the iOS Settings app.
///
/// Once Bluetooth permission has been refused, iOS will never ask again — the
/// only way back is this page, so an error message that just says "allow
/// Bluetooth" leaves the user hunting for it.
///
/// `app-settings:` is the only scheme Apple sanctions. Deep links to a specific
/// pane (`prefs:root=Bluetooth`) are a private API and get apps rejected, which
/// is why turning the radio on is handled by the system power alert instead —
/// see `showPowerAlert` in BleService.
Future<bool> openAppSettings() async {
  try {
    return await launchUrl(Uri.parse('app-settings:'));
  } catch (e) {
    logDebug('CalcAI: could not open Settings — $e');
    return false;
  }
}
