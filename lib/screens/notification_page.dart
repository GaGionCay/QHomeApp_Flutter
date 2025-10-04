import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/news.dart';
import 'package:flutter_application_1/screens/login_page.dart';
import 'package:flutter_application_1/services/news_service.dart';

class NotificationPage extends StatefulWidget {
  final int userId;
  final String email;
  final String username; // thêm username để hiển thị header

  const NotificationPage({
    super.key,
    required this.userId,
    required this.email,
    required this.username,
  });

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
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

      setState(() {
        _newsList = news;
        _loadingNews = false;
      });
    } catch (e) {
      setState(() {
        _loadingNews = false;
        _errorMsg = 'Lỗi khi tải thông báo: $e';
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
      backgroundColor: const Color(0xFF2C3E50),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: _loadingNews
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMsg != null
                        ? Center(
                            child: Text(
                              _errorMsg!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () async {
                              await _loadNews();
                              await _loadUnreadCount();
                            },
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: sortedNews.length,
                              itemBuilder: (context, index) {
                                final news = sortedNews[index];
                                return Card(
                                  color: news.read
                                      ? Colors.white
                                      : Colors.blue.shade50,
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 12),
                                  child: ListTile(
                                    leading: Icon(
                                      news.read
                                          ? Icons.drafts
                                          : Icons.notifications_active,
                                      color:
                                          news.read ? Colors.grey : Colors.blue,
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
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white24,
            child: Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Xin chào, ${widget.username}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'King C - Cộng đồng',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.logout),
                color: Colors.white,
                onPressed: _logout,
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 12,
                  top: 12,
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
    );
  }
}
