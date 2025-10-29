import 'dart:convert';

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
  late final AnimationController _bellController;
  late final Animation<double> _bellAnimation;
  final ApiClient _api = ApiClient();
  final AppEventBus _bus = AppEventBus();

  List<dynamic> items = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _bellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _bellAnimation = Tween<double>(begin: -0.15, end: 0.15)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_bellController);
    _bellController.repeat(reverse: true);
    _fetch();
    _bus.on('news_update', (data) {
      try {
        if (data is String) {
          final parsed = jsonDecode(data);
          debugPrint('📨 Parsed event data: $parsed');
        } else if (data is Map) {
          debugPrint('📨 Event data (Map): $data');
        }
      } catch (e) {
        debugPrint('⚠️ Parse error: $e');
      }

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
  void didUpdateWidget(covariant NewsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool hasUnread = items.any((n) => n['isRead'] != true && n['read'] != true);
    if (hasUnread) {
      _bellController.repeat(reverse: true);
    } else {
      _bellController.stop();
    }
  }

  @override
  void dispose() {
    _bus.off('news_update');
    _bellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: const Text('Thông báo'),
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

                        // Lấy URL ảnh đầy đủ từ ApiClient
                        final String? coverImageUrl = n['coverImageUrl'] != null
                            ? ApiClient.fileUrl(n['coverImageUrl'])
                            : null;

                        final String? uuid =
                            n['news_uuid']?.toString() ?? n['id']?.toString();

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color:
                                isRead ? Colors.white : const Color(0xFFE0F2F1),
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
                            contentPadding: const EdgeInsets.only(
                                left: 16, top: 10, right: 16, bottom: 10),
                            leading: Hero(
                              tag: 'news_${n['id'] ?? n['newsUuid']}',
                              child: Stack(
                                alignment: Alignment.topRight,
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    backgroundColor: Colors.white,
                                    child: AnimatedBuilder(
                                      animation: _bellController,
                                      builder: (context, child) {
                                        return Transform.rotate(
                                          angle:
                                              isRead ? 0 : _bellAnimation.value,
                                          child: Icon(
                                            isRead
                                                ? Icons.notifications_none
                                                : Icons.notifications_active,
                                            color: const Color(0xFF26A69A),
                                            size: 28,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  if (!isRead)
                                    Positioned(
                                      right: 2,
                                      top: 2,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
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
                            onTap: uuid == null
                                ? null
                                : () async {
                                    _markRead(uuid);

                                    // Cập nhật lại trạng thái isRead ngay lập tức (tùy chọn)
                                    setState(() {
                                      n['isRead'] = true;
                                      n['read'] = true;
                                    });

                                    Navigator.of(context).push(PageRouteBuilder(
                                      transitionDuration:
                                          const Duration(milliseconds: 500),
                                      pageBuilder: (_, animation, __) =>
                                          FadeTransition(
                                        opacity: animation,
                                        child: NewsDetailScreen(news: n),
                                      ),
                                    ));
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
