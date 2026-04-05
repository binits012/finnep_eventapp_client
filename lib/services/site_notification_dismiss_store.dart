import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _kDismissedKey = 'finnep_site_notification_dismissed_v1';

/// Persists dismissed notice ids (mobile-friendly; survives app restarts).
class SiteNotificationDismissStore {
  SiteNotificationDismissStore._();

  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDismissedKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> dismiss(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final set = await load();
    set.add(id);
    await prefs.setString(_kDismissedKey, jsonEncode(set.toList()));
  }
}
