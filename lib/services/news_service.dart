import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/news.dart';

class NewsService {
  final String baseUrl = 'http://192.168.100.46:8080/api/news';

  Future<List<News>> fetchNews() async {
    final response = await http.get(Uri.parse(baseUrl));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => News.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load news');
    }
  }

  Future<void> markNewsAsRead(int newsId) async {
    final url = Uri.parse('http://192.168.100.46:8080/api/news/$newsId/read');
    final response = await http.put(url);
    if (response.statusCode != 200) {
      throw Exception('Không thể đánh dấu đã đọc');
    }
  }
}
