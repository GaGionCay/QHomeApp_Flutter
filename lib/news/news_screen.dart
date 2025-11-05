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
  
  // Pagination state
  int _currentPage = 0;
  int _pageSize = 10;
  int? _totalItems;
  List<ResidentNews>? _allCachedItems; // Cache toàn bộ items để tránh load lại

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

  Future<void> _fetch({int? targetPage}) async {
    if (_residentId == null) return;
    
    final page = targetPage ?? _currentPage;
    
    // Validate page number
    if (page < 0) {
      debugPrint('⚠️ Page number cannot be negative: $page');
      return;
    }
    
    setState(() {
      loading = true;
      _currentPage = page;
    });
    
    try {
      // Load total items and cache all items if not already done
      if (_totalItems == null || _allCachedItems == null) {
        await _loadAndCacheAllItems();
      }
      
      // Validate page against total pages
      final totalPages = _getTotalPages();
      if (page >= totalPages) {
        debugPrint('⚠️ Page $page vượt quá tổng số trang ($totalPages), chuyển về trang ${totalPages - 1}');
        setState(() {
          _currentPage = totalPages > 0 ? totalPages - 1 : 0;
          loading = false;
        });
        return;
      }
      
      // Get items for current page from cache
      if (_allCachedItems != null && _allCachedItems!.isNotEmpty) {
        final startIndex = page * _pageSize;
        final endIndex = (startIndex + _pageSize).clamp(0, _allCachedItems!.length);
        
        if (startIndex < _allCachedItems!.length) {
          final pageItems = _allCachedItems!.sublist(
            startIndex,
            endIndex,
          );
          
          setState(() {
            items = pageItems;
          });
          
          debugPrint('✅ Loaded ${pageItems.length} resident news items (page ${page + 1}/$totalPages, items $startIndex-$endIndex)');
        } else {
          debugPrint('⚠️ Start index $startIndex vượt quá tổng số items ${_allCachedItems!.length}');
          setState(() {
            items = [];
          });
        }
      } else {
        setState(() {
          items = [];
        });
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi tải tin tức: $e');
      setState(() {
        items = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }
  
  Future<void> _loadAndCacheAllItems() async {
    if (_residentId == null) return;
    
    try {
      // Try to get total from API first
      _totalItems = await _residentService.getResidentNewsCount(_residentId!);
      
      if (_totalItems != null && _totalItems! > 0) {
        debugPrint('📊 Total news items from API: $_totalItems');
      }
    } catch (e) {
      debugPrint('⚠️ Không thể lấy total count từ API: $e');
    }
    
    // Load all items from API (API trả về toàn bộ list)
    try {
      debugPrint('🔍 Đang load toàn bộ items từ API...');
      
      // Load page 0 with a large size to get all items (or load without pagination)
      final allItems = await _residentService.getResidentNews(
        _residentId!,
        page: 0,
        size: 1000, // Request large size to get all items
      );
      
      // If API returns paginated response, we need to load all pages
      // But since API returns full list, we should get all items in one call
      if (allItems.length >= 1000) {
        // API might have more items, need to load all pages
        debugPrint('⚠️ Có thể có nhiều hơn 1000 items, cần load thêm...');
        // For now, just use what we got
        _allCachedItems = allItems;
        _totalItems = allItems.length;
      } else {
        _allCachedItems = allItems;
        _totalItems = allItems.length;
      }
      
      debugPrint('✅ Đã cache ${_allCachedItems!.length} items');
      
      // Verify total pages calculation
      final totalPages = _getTotalPages();
      debugPrint('📊 Tổng số items: $_totalItems, Tổng số trang: $totalPages');
    } catch (e) {
      debugPrint('⚠️ Lỗi khi load toàn bộ items: $e');
      _allCachedItems = [];
      _totalItems = 0;
    }
  }
  
  int _getTotalPages() {
    if (_totalItems == null || _totalItems == 0) return 1;
    // Calculate: ceil(totalItems / pageSize)
    // Example: 97 items / 10 per page = 9.7 → 10 pages
    final pages = (_totalItems! / _pageSize).ceil();
    return pages > 0 ? pages : 1;
  }
  
  void _goToPage(int page) {
    if (page == _currentPage || loading || page < 0) return;
    final totalPages = _getTotalPages();
    if (page >= totalPages) {
      debugPrint('⚠️ Không thể chuyển đến trang $page, tổng số trang là $totalPages');
      return;
    }
    _fetch(targetPage: page);
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
                  : Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
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
                                              'images': news.images.map((img) => <String, dynamic>{
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
                        _buildPaginationControls(),
                      ],
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

  Widget _buildPaginationControls() {
    if (items.isEmpty && !loading) return const SizedBox.shrink();
    
    final totalPages = _getTotalPages();
    final currentPageNumber = _currentPage + 1;
    
    List<int> pageNumbers = [];
    if (totalPages <= 7) {
      for (int i = 0; i < totalPages; i++) {
        pageNumbers.add(i);
      }
    } else {
      pageNumbers.add(0); 
      
      if (_currentPage > 2) {
        pageNumbers.add(-1);
      }
      
      int start = (_currentPage - 1).clamp(1, totalPages - 2);
      int end = (_currentPage + 1).clamp(1, totalPages - 2);
      
      for (int i = start; i <= end; i++) {
        if (!pageNumbers.contains(i)) {
          pageNumbers.add(i);
        }
      }
      
      if (_currentPage < totalPages - 3) {
        pageNumbers.add(-1); // Ellipsis
      }
      
      pageNumbers.add(totalPages - 1); // Last page
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Page info
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Trang $currentPageNumber / $totalPages',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF004D40),
              ),
            ),
          ),
          // Page numbers
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous button
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 0 && !loading
                    ? () => _goToPage(_currentPage - 1)
                    : null,
                color: _currentPage > 0 && !loading
                    ? const Color(0xFF26A69A)
                    : Colors.grey,
                iconSize: 24,
              ),
              
              // Page number buttons
              ...pageNumbers.map((pageIndex) {
                if (pageIndex == -1) {
                  // Ellipsis
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('...', style: TextStyle(color: Colors.grey)),
                  );
                }
                
                final pageNumber = pageIndex + 1;
                final isCurrentPage = pageIndex == _currentPage;
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Material(
                    color: isCurrentPage
                        ? const Color(0xFF26A69A)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: !loading && pageIndex != _currentPage
                          ? () => _goToPage(pageIndex)
                          : null,
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        child: Text(
                          '$pageNumber',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isCurrentPage
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isCurrentPage
                                ? Colors.white
                                : const Color(0xFF004D40),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
              
              // Next button
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < totalPages - 1 && !loading
                    ? () => _goToPage(_currentPage + 1)
                    : null,
                color: _currentPage < totalPages - 1 && !loading
                    ? const Color(0xFF26A69A)
                    : Colors.grey,
                iconSize: 24,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
