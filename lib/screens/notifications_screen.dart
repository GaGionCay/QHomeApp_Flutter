import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/news_service.dart';
import 'news_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final AuthService authService;

  const NotificationsScreen({super.key, required this.authService});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NewsService newsService;
  List<dynamic> newsList = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    newsService = NewsService(apiClient: widget.authService.apiClient);
    _loadNews();
  }

  void _loadNews() async {
    setState(() => loading = true);
    try {
      final list = await newsService.listNews();
      setState(() {
        newsList = list;
        loading = false;
      });
    } catch (e) {
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load notifications')),
      );
    }
  }

  void _markRead(int id) async {
    try {
      await newsService.markRead(id);
      _loadNews();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to mark as read')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : newsList.isEmpty
          ? const Center(child: Text('No notifications'))
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
                  trailing: IconButton(
                    icon: Icon(
                      read ? Icons.check : Icons.mark_email_unread,
                      color: read ? Colors.green : null,
                    ),
                    onPressed: read ? null : () => _markRead(news['id']),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NewsDetailScreen(
                          newsService: newsService,
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
