import 'package:shared_preferences/shared_preferences.dart';

class NewsReadStore {
  NewsReadStore._();

  static String _key(String residentId) => 'news_read_ids_$residentId';

  static Future<Set<String>> load(String residentId) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_key(residentId));
    if (values == null) return <String>{};
    return values.toSet();
  }

  static Future<bool> markRead(String residentId, String newsId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(residentId);
    final current = prefs.getStringList(key)?.toSet() ?? <String>{};
    if (current.contains(newsId)) {
      return false;
    }
    current.add(newsId);
    await prefs.setStringList(key, current.toList());
    return true;
  }

  static Future<void> markAllRead(String residentId, Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(residentId);
    final updated = ids.toSet();
    await prefs.setStringList(key, updated.toList());
  }
}


