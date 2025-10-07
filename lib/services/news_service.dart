import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class NewsService {
  final ApiClient apiClient;

  NewsService({required this.apiClient});

  /// Lấy danh sách thông báo (có thể filter theo category)
  Future<List<dynamic>> listNews({String? category, int page = 0, int size = 20}) async {
    final query = {
      if (category != null) 'category': category,
      'page': '$page',
      'size': '$size',
    };
    final queryString = Uri(queryParameters: query).query;
    final path = '/news${queryString.isNotEmpty ? '?$queryString' : ''}';

    final response = await apiClient.get(path);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['content'] as List<dynamic>;
    } else {
      throw Exception('Failed to load news: ${response.statusCode}');
    }
  }

  /// Lấy chi tiết một thông báo theo ID
  Future<Map<String, dynamic>> getNews(int id) async {
    final response = await apiClient.get('/news/$id');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to get news: ${response.statusCode}');
    }
  }

  /// Đánh dấu thông báo là đã đọc
  Future<void> markRead(int id) async {
    final response = await apiClient.post('/news/$id/read');
    if (response.statusCode != 200) {
      throw Exception('Failed to mark news as read: ${response.statusCode}');
    }
  }

  /// Lấy số lượng thông báo chưa đọc
  Future<int> unreadCount() async {
    final response = await apiClient.get('/news/unread-count');
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as num).toInt();
    } else {
      throw Exception('Failed to fetch unread count: ${response.statusCode}');
    }
  }
}
