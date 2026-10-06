import 'package:shared_preferences/shared_preferences.dart';

const _key = 'guest_token';

class GuestTokenStore {
  static SharedPreferences? _prefs;

  /// Warm SharedPreferences on home screen so My Tickets opens smoothly.
  static Future<void> warmUp() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<void> set(String token) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(_key, token);
  }

  static Future<String?> get() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    return prefs.getString(_key);
  }

  static Future<void> clear() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.remove(_key);
  }
}
