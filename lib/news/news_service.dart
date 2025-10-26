import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../auth/api_client.dart';
import 'news_detail_screen.dart';
import 'news_item.dart';

class NewsService {
  final ApiClient api;
  final BuildContext context;
  StompClient? _stompClient;

  NewsService({required this.api, required this.context});

  Future<void> connect() async {
    final token = await api.dio.options.headers['Authorization'];
    if (token == null) return;

    _stompClient = StompClient(
      config: StompConfig(
        url: '${ApiClient.BASE_URL.replaceFirst("http", "ws")}/ws',
        onConnect: _onConnect,
        onWebSocketError: (dynamic error) => print('❌ WS error: $error'),
        stompConnectHeaders: {'Authorization': token},
        webSocketConnectHeaders: {'Authorization': token},
        reconnectDelay: const Duration(seconds: 5),
        heartbeatIncoming: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 10),
      ),
    );

    _stompClient?.activate();
  }

  void _onConnect(StompFrame frame) {
    print('✅ WebSocket connected');

    _stompClient?.subscribe(
      destination: '/topic/news',
      callback: (StompFrame frame) {
        if (frame.body != null) {
          final data = json.decode(frame.body!);
          _showPopup(data);
        }
      },
    );
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
                    builder: (_) => NewsDetailScreen(id: newsId.toString()),
                  ),
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

  void disconnect() {
    _stompClient?.deactivate();
  }
}
