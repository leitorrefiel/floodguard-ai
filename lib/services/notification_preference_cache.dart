import 'package:shared_preferences/shared_preferences.dart';

class NotificationPreferenceCache {
  NotificationPreferenceCache({
    required SharedPreferences preferences,
    required String? userId,
  }) : _preferences = preferences,
       _scope = userId?.trim().isNotEmpty == true
           ? userId!.trim()
           : 'anonymous';

  static const _prefix = 'floodguard_alert_pref';

  final SharedPreferences _preferences;
  final String _scope;

  bool? read(String name) => _preferences.getBool(_key(name));

  Future<bool> write(String name, bool enabled) =>
      _preferences.setBool(_key(name), enabled);

  String _key(String name) => '$_prefix.$_scope.$name';
}
