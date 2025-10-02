import 'package:flutter/material.dart';
import '../models/news.dart';
import '../services/news_service.dart';

class NotificationPage extends StatelessWidget {
  final List<News> newsList;
  final NewsService _newsService = NewsService();

  NotificationPage({super.key, required this.newsList});

  void _markAsRead(BuildContext context, News news) async {
    if (!news.isRead) {
      try {
        await _newsService.markNewsAsRead(news.id);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã đánh dấu là đã đọc')));
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedNews = [...newsList]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Thông báo')),
      body: ListView.builder(
        itemCount: sortedNews.length,
        itemBuilder: (context, index) {
          final news = sortedNews[index];
          return ListTile(
            leading: Icon(news.isRead ? Icons.drafts : Icons.markunread),
            title: Text(news.title),
            subtitle: Text(news.content),
            trailing: Text(news.author),
            onTap: () => _markAsRead(context, news),
          );
        },
      ),
    );
  }
}
