import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import 'news_detail_screen.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final ApiClient _api = ApiClient();
  List<dynamic> items = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => loading = true);
    try {
      final res = await _api.dio.get('/news');
      if (res.data is Map && res.data['content'] != null) {
        items = List.from(res.data['content']);
      } else if (res.data is List) {
        items = List.from(res.data);
      }
    } catch (e) {
      // ignore
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _markRead(int id) async {
    try {
      await _api.dio.post('/news/$id/read');
      final index = items.indexWhere((e) => e['id'] == id);
      if (index != -1) {
        final updated = [...items];
        updated[index] = {...updated[index], 'isRead': true};
        setState(() => items = updated);
      }
    } catch (e) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _fetch,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('Không có tin nào'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final n = items[i];
                    final bool isRead = n['isRead'] == true;

                    return Card(
                      color: isRead ? Colors.grey[200] : Colors.white,
                      elevation: isRead ? 0 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: Icon(
                          isRead
                              ? Icons.mark_email_read
                              : Icons.mark_email_unread,
                          color: isRead ? Colors.grey : Colors.blue,
                        ),
                        title: Text(
                          n['title'] ?? '',
                          style: TextStyle(
                            fontWeight:
                                isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          n['summary'] ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          // 🔹 Đánh dấu đọc ngay lập tức
                          await _markRead(n['id']);

                          // 🔹 Mở chi tiết và refresh sau khi quay lại
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NewsDetailScreen(id: n['id']),
                            ),
                          );

                          _fetch(); // Cập nhật lại danh sách sau khi quay về
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
