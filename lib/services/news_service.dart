import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/news.dart';

class NewsService {
  final String baseUrl = 'http://localhost:8080/api/news';

  Future<List<News>> fetchNews({
    int page = 0,
    int size = 20,
    String? category,
    int? userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt') ?? '';

      final uri = Uri.parse(
        '$baseUrl?page=$page&size=$size'
        '${category != null ? '&category=$category' : ''}'
        '${userId != null ? '&userId=$userId' : ''}',
      );

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonBody = jsonDecode(response.body);
        final List<dynamic> content = jsonBody['content'] ?? [];
        return content.map((e) => News.fromJson(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<News?> getNews(int id, {int? userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt') ?? '';

      final uri =
          Uri.parse('$baseUrl/$id${userId != null ? '?userId=$userId' : ''}');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return News.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> markNewsAsRead(int newsId, int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt') ?? '';

      final url = Uri.parse('$baseUrl/$newsId/read?userId=$userId');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<int> fetchUnreadCount(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt') ?? '';

      final url = Uri.parse('$baseUrl/unread-count?userId=$userId');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final body = response.body;
        try {
          return int.parse(body);
        } catch (_) {
          final data = jsonDecode(body);
          return data is Map && data['count'] != null
              ? data['count'] as int
              : 0;
        }
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
