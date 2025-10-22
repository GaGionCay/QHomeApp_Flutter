import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../auth/api_client.dart';
import '../news/news_detail_screen.dart';
import '../news/notification_item.dart';

class NotificationService {
  final ApiClient api;
final BuildContext context; // thêm context

  NotificationService({required this.api, required this.context});

  void subscribe() async {
    final token = await api.dio.options.headers['Authorization'];

    final uri = Uri.parse('${ApiClient.BASE_URL}/news/subscribe');
    final request = http.Request('GET', uri);
    if (token != null) request.headers['Authorization'] = token;

    final response = await request.send();
    response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty) return;
      final data = jsonDecode(line);
      _showPopup(data);
    });
  }

  void _showPopup(Map<String, dynamic> data) {
    final title = data['title'] ?? '';
    final summary = data['summary'] ?? '';
    final newsId = data['newsId'];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(summary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          if (newsId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => NewsDetailScreen(id: newsId)),
                );
              },
              child: const Text('Xem chi tiết'),
            ),
        ],
      ),
    );
  }

  Future<List<NotificationItem>> getUnreadNotifications() async {
    try {
      final res = await api.dio.get('/news/unread');
      final data = res.data as List<dynamic>? ?? [];
      return data.map((json) => NotificationItem.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }
}
