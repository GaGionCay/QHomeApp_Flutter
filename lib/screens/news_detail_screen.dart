import 'package:flutter/material.dart';
import '../services/news_service.dart';

class NewsDetailScreen extends StatefulWidget {
  final NewsService newsService;
  final int newsId;

  const NewsDetailScreen({super.key, required this.newsService, required this.newsId});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  Map<String, dynamic>? news;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  void _loadNews() async {
    setState(() => loading = true);
    final detail = await widget.newsService.getNews(widget.newsId);
    setState(() {
      news = detail;
      loading = false;
    });
    // Mark as read
    await widget.newsService.markRead(widget.newsId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('News Detail')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(news?['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(news?['summary'] ?? ''),
                  const SizedBox(height: 10),
                  Text(news?['content'] ?? ''),
                ],
              ),
            ),
    );
  }
}
