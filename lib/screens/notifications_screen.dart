import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/news_service.dart';

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
    final list = await newsService.listNews();
    setState(() {
      newsList = list;
      loading = false;
    });
  }

void _markRead(int id) async {
  try {
    await newsService.markRead(id); // đã đánh dấu là đọc
    _loadNews(); // refresh list
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to mark as read')),
    );
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
                      subtitle: Text(news['summary'] ?? ''),
                      trailing: IconButton(
                        icon: Icon(
                          read ? Icons.check : Icons.mark_email_unread,
                          color: read ? Colors.green : null,
                        ),
                        onPressed: read ? null : () => _markRead(news['id']),
                      ),
                    );
                  },
                ),
    );
  }
}
