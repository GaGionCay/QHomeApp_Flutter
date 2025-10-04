import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/news.dart';
import 'package:flutter_application_1/screens/login_page.dart';
import 'package:flutter_application_1/services/news_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  final int userId;
  final String email;

  const HomePage({super.key, required this.userId, required this.email});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final NewsService _newsService = NewsService();

  List<News> _newsList = [];
  int _unreadCount = 0;
  bool _loadingNews = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadNews();
    _loadUnreadCount();
  }

  Future<void> _loadNews() async {
    setState(() {
      _loadingNews = true;
      _errorMsg = null;
    });

    try {
      final news = await _newsService.fetchNews(
        userId: widget.userId,
        page: 0,
        size: 20,
      );

      debugPrint('Fetched ${news.length} news'); // log số lượng
      for (var n in news) {
        debugPrint('News: ${n.title}, read: ${n.read}');
      }

      setState(() {
        _newsList = news;
        _loadingNews = false;
      });
    } catch (e) {
      setState(() {
        _loadingNews = false;
        _errorMsg = 'Lỗi khi tải news: $e';
      });
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await _newsService.fetchUnreadCount(widget.userId);
      setState(() => _unreadCount = count);
    } catch (e) {
      debugPrint('Failed to fetch unread count: $e');
    }
  }

  Future<void> _markAsRead(News news) async {
    if (!news.read) {
      final success = await _newsService.markNewsAsRead(news.id, widget.userId);
      if (!mounted) return;
      if (success) {
        setState(() {
          news.read = true;
          _unreadCount = (_unreadCount - 1).clamp(0, 9999);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Đã đánh dấu là đã đọc')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Không thể đánh dấu đã đọc')),
        );
      }
    }
  }

  void _openNewsDetail(News news) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(news.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(news.content),
              const SizedBox(height: 12),
              Text(
                "✍️ ${news.author ?? 'Unknown'} | 🕒 ${news.createdAt != null ? news.createdAt!.toLocal() : 'N/A'}",
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Đóng"),
          ),
        ],
      ),
    );
    _markAsRead(news);
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedNews = [..._newsList]
      ..sort(
        (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );

    return Scaffold(
      appBar: AppBar(
        title: Text('Xin chào, ${widget.email}'),
        actions: [
          Stack(
            children: [
              IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
              if (_unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _loadingNews
          ? const Center(child: CircularProgressIndicator())
          : _errorMsg != null
          ? Center(
              child: Text(
                _errorMsg!,
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: sortedNews.length,
              itemBuilder: (context, index) {
                final news = sortedNews[index];
                return Card(
                  color: news.read ? Colors.white : Colors.blue.shade50,
                  margin: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 8,
                  ),
                  child: ListTile(
                    leading: Icon(
                      news.read ? Icons.drafts : Icons.markunread,
                      color: news.read ? Colors.grey : Colors.blue,
                    ),
                    title: Text(
                      news.title,
                      style: TextStyle(
                        fontWeight: news.read
                            ? FontWeight.normal
                            : FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      news.summary?.isNotEmpty == true
                          ? news.summary!
                          : news.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _openNewsDetail(news),
                  ),
                );
              },
            ),
    );
  }
}
