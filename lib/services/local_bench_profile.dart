import 'package:shared_preferences/shared_preferences.dart';

/// Local development opt-in. Never enable this in a distribution artifact.
abstract final class LocalBenchProfile {
  static const enabled = bool.fromEnvironment('CALCAI_BENCH_C62E');
  static const targetName = 'CALCAI-C62E';
  static const storagePrefix = enabled ? '__calcai_bench_c62e_20261111__' : '';
}

/// Uses real persistent preferences while keeping the bench account separate.
/// There is deliberately no fallback, migration, or global clear operation.
class AppPreferences {
  AppPreferences(this._prefs, {this.prefix = LocalBenchProfile.storagePrefix});
  final SharedPreferences _prefs;
  final String prefix;

  static Future<AppPreferences> getInstance() async =>
      AppPreferences(await SharedPreferences.getInstance());

  String? getString(String key) => _prefs.getString('$prefix$key');
  bool? getBool(String key) => _prefs.getBool('$prefix$key');
  Future<bool> setString(String key, String value) =>
      _prefs.setString('$prefix$key', value);
  Future<bool> setBool(String key, bool value) =>
      _prefs.setBool('$prefix$key', value);
  Future<bool> remove(String key) => _prefs.remove('$prefix$key');
  Set<String> getKeys() => _prefs
      .getKeys()
      .where((key) => key.startsWith(prefix))
      .map((key) => key.substring(prefix.length))
      .toSet();
}
