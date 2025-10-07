import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/news_service.dart';

String formatDateTime(String? isoString) {
  if (isoString == null || isoString.isEmpty) return '';
  try {
    final dateTime = DateTime.parse(isoString).toLocal();
    return DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
  } catch (e) {
    return isoString;
  }
}

class NewsDetailScreen extends StatefulWidget {
  final NewsService newsService;
  final int newsId;

  const NewsDetailScreen({
    super.key,
    required this.newsService,
    required this.newsId,
  });

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  Map<String, dynamic>? news;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadNewsDetail();
  }

  void _loadNewsDetail() async {
    setState(() => loading = true);
    try {
      final detail = await widget.newsService.getNews(widget.newsId);
      setState(() => news = detail);
      if (news != null && !(news!['read'] ?? false)) {
        await widget.newsService.markRead(widget.newsId);
        setState(() => news!['read'] = true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load news detail')),
      );
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('News Detail')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : news == null
          ? const Center(child: Text('News not found'))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      news!['title'] ?? '',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'By ${news!['author'] ?? 'Unknown'} - ${formatDateTime(news!['createdAt'])}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      news!['summary'] ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      news!['content'] ?? '',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
