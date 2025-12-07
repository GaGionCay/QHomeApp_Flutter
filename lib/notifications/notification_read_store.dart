import 'package:shared_preferences/shared_preferences.dart';

class NotificationReadStore {
  static String _key(String residentId) => 'notification_read_ids_$residentId';

  static Future<Set<String>> load(String residentId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key(residentId));
    if (list == null) return <String>{};
    return list.toSet();
  }

  static Future<bool> markRead(String residentId, String notificationId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(residentId);
    final current = prefs.getStringList(key)?.toSet() ?? <String>{};
    if (current.contains(notificationId)) {
      return false;
    }
    current.add(notificationId);
    await prefs.setStringList(key, current.toList());
    return true;
  }
}

