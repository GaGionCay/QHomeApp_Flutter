import 'package:flutter/material.dart';
import '../services/news_service.dart';
import 'news_detail_screen.dart';

class NewsListScreen extends StatefulWidget {
  final NewsService newsService;

  const NewsListScreen({super.key, required this.newsService});

  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> {
  List<dynamic> newsList = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  void _loadNews() async {
    setState(() => loading = true);
    try {
      final list = await widget.newsService.listNews();
      setState(() {
        newsList = list;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to load news')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: newsList.length,
              itemBuilder: (context, index) {
                final news = newsList[index];
                final read = news['read'] ?? false;
                return ListTile(
                  title: Text(news['title'] ?? ''),
                  subtitle: Text(
                    'By ${news['author'] ?? 'Unknown'} - ${formatDateTime(news['createdAt'])}',
                  ),
                  trailing: Icon(
                    read ? Icons.check : Icons.mark_email_unread,
                    color: read ? Colors.green : null,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NewsDetailScreen(
                          newsService: widget.newsService,
                          newsId: news['id'],
                        ),
                      ),
                    ).then((_) => _loadNews());
                  },
                );
              },
            ),
    );
  }
}
