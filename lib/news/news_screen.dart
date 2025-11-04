import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import '../core/event_bus.dart';
import '../profile/profile_service.dart';
import '../models/resident_news.dart';
import 'resident_service.dart';
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
  final ResidentService _residentService = ResidentService();
  final AppEventBus _bus = AppEventBus();

  List<ResidentNews> items = [];
  bool loading = false;
  String? _residentId;

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
    _loadResidentIdAndFetch();
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
      if (_residentId != null) {
        _fetch();
      }
    });
  }

  Future<void> _loadResidentIdAndFetch() async {
    try {
      final profileService = ProfileService(_api.dio);
      final profile = await profileService.getProfile();
      
      // Try multiple possible field names for residentId
      _residentId = profile['residentId']?.toString();
      
      // If found in profile, use it directly
      if (_residentId != null && _residentId!.isNotEmpty) {
        debugPrint('✅ Tìm thấy residentId trong profile: $_residentId');
        await _fetch();
        return;
      }
      
      // If not found in profile, try to get from backend API
      if (_residentId == null || _residentId!.isEmpty) {
        try {
          debugPrint('🔍 Không tìm thấy residentId trong profile, gọi API để lấy...');
          final response = await _api.dio.get('/residents/me/uuid');
          final data = response.data as Map<String, dynamic>;
          
          if (data['success'] == true && data['residentId'] != null && data['residentId'].toString().isNotEmpty) {
            _residentId = data['residentId']?.toString();
            debugPrint('✅ Lấy được residentId từ API: $_residentId');
          } else {
            debugPrint('⚠️ API trả về success=false hoặc residentId rỗng: ${data['message']}');
            debugPrint('⚠️ Có thể endpoint admin API chưa tồn tại hoặc user chưa được gán vào căn hộ');
          }
        } catch (e) {
          debugPrint('⚠️ Lỗi gọi API lấy residentId: $e');
          // Không throw để app vẫn hoạt động, chỉ không load news
        }
      }
      
      debugPrint('🔍 Profile data: ${profile.keys.toList()}');
      debugPrint('🔍 ResidentId found: $_residentId');
      
      if (_residentId == null || _residentId!.isEmpty) {
        debugPrint('⚠️ Không tìm thấy residentId. Profile keys: ${profile.keys}');
        if (mounted) {
          setState(() => loading = false);
        }
        return;
      }
      
      await _fetch();
    } catch (e) {
      debugPrint('⚠️ Lỗi lấy residentId: $e');
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _fetch() async {
    if (_residentId == null) return;
    
    setState(() => loading = true);
    try {
      items = await _residentService.getResidentNews(_residentId!);
      debugPrint('✅ Loaded ${items.length} resident news items');
    } catch (e) {
      debugPrint('⚠️ Lỗi tải tin tức: $e');
      items = [];
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void didUpdateWidget(covariant NewsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool hasUnread = items.isNotEmpty;
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
                        final news = items[i];
                        final bool isRead = false;

                        final String date = news.publishAt != null
                            ? DateFormat('dd/MM/yyyy').format(news.publishAt!)
                            : DateFormat('dd/MM/yyyy').format(news.createdAt);

                        final String? coverImageUrl = news.coverImageUrl;

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
                              tag: 'news_${news.id}',
                              child: Stack(
                                alignment: Alignment.topRight,
                                children: [
                                  if (coverImageUrl != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(26),
                                      child: Image.network(
                                        coverImageUrl,
                                        width: 52,
                                        height: 52,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return CircleAvatar(
                                            radius: 26,
                                            backgroundColor: Colors.white,
                                            child: Icon(
                                              Icons.article,
                                              color: const Color(0xFF26A69A),
                                              size: 28,
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                  else
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: Colors.white,
                                      child: Icon(
                                        Icons.article,
                                        color: const Color(0xFF26A69A),
                                        size: 28,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            title: Text(
                              news.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF004D40),
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  news.summary,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  date,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.of(context).push(PageRouteBuilder(
                                transitionDuration:
                                    const Duration(milliseconds: 500),
                                pageBuilder: (_, animation, __) =>
                                    FadeTransition(
                                  opacity: animation,
                                  child: NewsDetailScreen(
                                    news: {
                                      'id': news.id,
                                      'title': news.title,
                                      'summary': news.summary,
                                      'bodyHtml': news.bodyHtml,
                                      'coverImageUrl': news.coverImageUrl,
                                      'publishAt': news.publishAt?.toIso8601String(),
                                      'createdAt': news.createdAt.toIso8601String(),
                                      'images': news.images.map((img) => {
                                        'id': img.id,
                                        'url': img.url,
                                        'caption': img.caption,
                                      }).toList(),
                                    },
                                  ),
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
