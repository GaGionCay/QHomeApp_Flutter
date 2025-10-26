import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import '../core/event_bus.dart';
import 'news_detail_screen.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen>
    with SingleTickerProviderStateMixin {
  final ApiClient _api = ApiClient();
  final AppEventBus _bus = AppEventBus();

  List<dynamic> items = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
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
      } else {
        items = [];
      }
      debugPrint('✅ Loaded ${items.length} news items');
    } catch (e) {
      debugPrint('⚠️ Lỗi tải tin tức: $e');
      items = [];
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _markRead(String? uuid) async {
    if (uuid == null) return;
    try {
      debugPrint('🔔 Marking news $uuid as read');
      await _api.dio.post('/news/$uuid/read');
    } catch (e) {
      debugPrint('⚠️ Lỗi markRead: $e');
    }
  }

  @override
  void dispose() {
    _bus.off('news_update');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: const Text('Tin tức & Thông báo'),
        elevation: 2,
        backgroundColor: const Color(0xFF26A69A),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        color: const Color(0xFF26A69A),
        onRefresh: _fetch,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final n = items[i];
                        final bool isRead =
                            n['isRead'] == true || n['read'] == true;

                        final String date = n['publishAt'] != null
                            ? DateFormat('dd/MM/yyyy')
                                .format(DateTime.parse(n['publishAt']))
                            : (n['createdAt'] != null
                                ? DateFormat('dd/MM/yyyy')
                                    .format(DateTime.parse(n['createdAt']))
                                : '');

                        final String? uuid =
                            n['news_uuid']?.toString() ?? n['id']?.toString();

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              if (!isRead)
                                BoxShadow(
                                  color: Colors.teal.withOpacity(0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: isRead
                                  ? Colors.grey[300]
                                  : const Color(0xFF26A69A).withOpacity(0.15),
                              child: Icon(
                                isRead
                                    ? Icons.notifications_none
                                    : Icons.notifications_active,
                                color: isRead
                                    ? Colors.grey[700]
                                    : const Color(0xFF26A69A),
                              ),
                            ),
                            title: Text(
                              n['title'] ?? '',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight:
                                    isRead ? FontWeight.w500 : FontWeight.bold,
                                color: isRead
                                    ? Colors.grey[800]
                                    : const Color(0xFF004D40),
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  n['summary'] ?? n['content'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  date,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                            onTap: uuid == null
                                ? null
                                : () async {
                                    // Cập nhật trạng thái đọc ngay trên UI
                                    final index = items.indexWhere((e) =>
                                        e['news_uuid']?.toString() == uuid);
                                    if (index != -1) {
                                      final updated = [...items];
                                      updated[index] = {
                                        ...updated[index],
                                        'isRead': true
                                      };
                                      if (mounted) setState(() => items = updated);
                                    }

                                    // Gọi backend đánh dấu đã đọc (real-time)
                                    _markRead(uuid);

                                    // Mở detail
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            NewsDetailScreen(id: uuid),
                                      ),
                                    );
                                  },
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_outlined, size: 80, color: Color(0xFFB0BEC5)),
          const SizedBox(height: 16),
          Text(
            'Không có thông báo nào',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Kéo xuống để làm mới danh sách',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
