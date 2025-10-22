import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import '../core/event_bus.dart'; // 👈 thêm import này
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
  late final AppEventBus _bus; // 👈 để lắng nghe sự kiện real-time

  @override
  void initState() {
    super.initState();
    _bus = AppEventBus();
    _fetch();

    // 👇 Lắng nghe sự kiện "news_update" từ MainShell
    _bus.on('news_update', (_) {
      debugPrint('🔔 Nhận sự kiện news_update → reload NewsScreen');
      _fetch();
    });
  }

  Future<void> _fetch() async {
    setState(() => loading = true);
    try {
      final res = await _api.dio.get('/news?page=0&size=50');
      if (res.data is Map && res.data['content'] != null) {
        items = List.from(res.data['content']);
      } else if (res.data is List) {
        items = List.from(res.data);
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi tải tin tức: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _markRead(int id) async {
    try {
      await _api.dio.post('/news/$id/read');
      final index = items.indexWhere((e) => e['id'] == id);
      if (index != -1) {
        final updated = [...items];
        updated[index] = {...updated[index], 'isRead': true};
        if (mounted) setState(() => items = updated);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    // 👇 Hủy lắng nghe khi screen bị dispose
    _bus.off('news_update');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tin tức & Thông báo')),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? const Center(child: Text('Không có thông báo nào'))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final n = items[i];
                      final bool isRead =
                          n['isRead'] == true || n['read'] == true;

                      return Card(
                        color: isRead ? Colors.grey[100] : Colors.white,
                        elevation: isRead ? 0 : 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: Icon(
                            isRead
                                ? Icons.notifications_none
                                : Icons.notifications_active,
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
                            n['summary'] ?? n['content'] ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () async {
                            await _markRead(n['id']);
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NewsDetailScreen(id: n['id']),
                              ),
                            );
                            _fetch();
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
