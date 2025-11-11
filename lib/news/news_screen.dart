import 'dart:convert';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../core/event_bus.dart';
import '../profile/profile_service.dart';
import '../models/resident_news.dart';
import 'resident_service.dart';
import 'news_detail_screen.dart';
import 'news_read_store.dart';
import '../theme/app_colors.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

enum InfoListFilter { all, unread, read }

class _NewsScreenState extends State<NewsScreen> {
  final ApiClient _api = ApiClient();
  late final ContractService _contractService;
  final ResidentService _residentService = ResidentService();
  final AppEventBus _bus = AppEventBus();
  final List<Map<String, dynamic>> _pendingRealtime = [];

  List<ResidentNews> items = [];
  bool loading = false;
  String? _residentId;
  Set<String> _readNewsIds = <String>{};
  InfoListFilter _filter = InfoListFilter.all;

  // Pagination state
  int _currentPage = 0;
  int _pageSize = 10;
  int? _totalItems;
  List<ResidentNews>? _allCachedItems; // Cache toàn bộ items để tránh load lại

  @override
  void initState() {
    super.initState();
    _contractService = ContractService(_api);
    _loadResidentIdAndFetch();
    _bus.on('news_update', (data) async {
      final payload = _normalizeEventPayload(data);
      if (payload == null) {
        debugPrint('⚠️ Không thể parse news_update payload: $data');
        await _refreshFromServer(silent: true);
        return;
      }

      final eventType =
          (payload['type'] ?? payload['eventType'] ?? '').toString();
      debugPrint('🔔 Nhận sự kiện news_update với type=$eventType');

      if (eventType.endsWith('_CREATED')) {
        _handleIncomingRealtime(payload);
      } else if (eventType.endsWith('_UPDATED') ||
          eventType.endsWith('_DELETED')) {
        await _refreshFromServer(silent: true);
      } else {
        await _refreshFromServer(silent: true);
      }
    });
    _bus.on('news_read_status_updated', (_) {
      if (_residentId != null) {
        _loadReadState();
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
        await _loadReadState();
        await _fetch();
        _flushPendingRealtime();
        return;
      }

      // Nếu chưa có residentId, thử lấy từ danh sách căn hộ
      if (_residentId == null || _residentId!.isEmpty) {
        await _tryPopulateResidentFromUnits();
      }

      debugPrint('🔍 Profile data: ${profile.keys.toList()}');
      debugPrint('🔍 ResidentId found: $_residentId');

      if (_residentId == null || _residentId!.isEmpty) {
        debugPrint(
            '⚠️ Không tìm thấy residentId. Profile keys: ${profile.keys}');
        if (mounted) {
          setState(() => loading = false);
        }
        return;
      }

      await _loadReadState();
      await _fetch();
      _flushPendingRealtime();
    } catch (e) {
      debugPrint('⚠️ Lỗi lấy residentId: $e');
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _tryPopulateResidentFromUnits() async {
    try {
      final units = await _contractService.getMyUnits();
      if (units.isEmpty) {
        debugPrint('ℹ️ [NewsScreen] Người dùng chưa có căn hộ gán.');
        return;
      }

      for (final unit in units) {
        final candidate = unit.primaryResidentId?.toString();
        if (candidate != null && candidate.isNotEmpty) {
          _residentId = candidate;
          break;
        }
      }

      // Nếu vẫn null, lấy tạm residentId đầu tiên có dữ liệu trong danh sách
      if (_residentId == null || _residentId!.isEmpty) {
        final fallback = units.firstWhere(
          (unit) => (unit.primaryResidentId ?? '').isNotEmpty,
          orElse: () => units.first,
        );
        if ((fallback.primaryResidentId ?? '').isNotEmpty) {
          _residentId = fallback.primaryResidentId;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [NewsScreen] Lỗi lấy dữ liệu căn hộ: $e');
    }
  }

  Future<void> _loadReadState() async {
    if (_residentId == null || _residentId!.isEmpty) return;
    final stored = await NewsReadStore.load(_residentId!);
    if (!mounted) return;
    setState(() {
      _readNewsIds = stored;
    });
  }

  Future<void> _fetch({int? targetPage, bool silent = false}) async {
    if (_residentId == null) return;

    final page = targetPage ?? _currentPage;

    // Validate page number
    if (page < 0) {
      debugPrint('⚠️ Page number cannot be negative: $page');
      return;
    }
    if (!silent) {
      setState(() {
        loading = true;
      });
    }
    _currentPage = page;

    try {
      // Load total items and cache all items if not already done
      if (_totalItems == null || _allCachedItems == null) {
        await _loadAndCacheAllItems();
      }

      // Validate page against total pages
      final totalPages = _getTotalPages();
      if (page >= totalPages) {
        debugPrint(
            '⚠️ Page $page vượt quá tổng số trang ($totalPages), chuyển về trang ${totalPages - 1}');
        _currentPage = totalPages > 0 ? totalPages - 1 : 0;
      }
      final effectivePage = _currentPage;

      // Get items for current page from cache
      if (_allCachedItems != null && _allCachedItems!.isNotEmpty) {
        final startIndex = effectivePage * _pageSize;
        final endIndex =
            (startIndex + _pageSize).clamp(0, _allCachedItems!.length);

        if (startIndex < _allCachedItems!.length) {
          final pageItems = _allCachedItems!.sublist(
            startIndex,
            endIndex,
          );

          if (mounted) {
            setState(() {
              items = pageItems;
              if (!silent) loading = false;
            });
          } else {
            items = pageItems;
          }

          debugPrint(
              '✅ Loaded ${pageItems.length} resident news items (page ${effectivePage + 1}/$totalPages, items $startIndex-$endIndex)');
        } else {
          debugPrint(
              '⚠️ Start index $startIndex vượt quá tổng số items ${_allCachedItems!.length}');
          if (mounted) {
            setState(() {
              items = [];
              if (!silent) loading = false;
            });
          } else {
            items = [];
          }
        }
      } else {
        if (mounted) {
          setState(() {
            items = [];
            if (!silent) loading = false;
          });
        } else {
          items = [];
        }
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi tải tin tức: $e');
      if (mounted) {
        setState(() {
          items = [];
          if (!silent) loading = false;
        });
      } else {
        items = [];
      }
    } finally {
      if (!silent && mounted) {
        if (loading) {
          setState(() {
            loading = false;
          });
        }
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
      _allCachedItems!.sort((a, b) {
        final aDate = a.publishAt ?? a.createdAt;
        final bDate = b.publishAt ?? b.createdAt;
        return bDate.compareTo(aDate);
      });
      debugPrint('📌 Items đã được sắp xếp theo thời gian mới nhất trước');

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

  Future<void> _refreshFromServer({bool silent = false}) async {
    final targetPage = _currentPage;
    _totalItems = null;
    _allCachedItems = null;
    await _fetch(targetPage: targetPage, silent: silent);
    _flushPendingRealtime();
  }

  Map<String, dynamic>? _normalizeEventPayload(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(data);
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (e) {
        debugPrint('⚠️ Không thể decode JSON từ payload: $e');
      }
    }
    return null;
  }

  void _handleIncomingRealtime(Map<String, dynamic> payload,
      {bool queueIfNotReady = true}) {
    if (_residentId == null) {
      if (queueIfNotReady) {
        _pendingRealtime.add(Map<String, dynamic>.from(payload));
      }
      return;
    }

    final news = _parseRealtimeNews(payload);
    if (news == null) return;

    _insertNewsIntoCache(news);

    if (_currentPage == 0) {
      final latestItems = _buildPageItems(0);
      if (mounted) {
        setState(() {
          items = latestItems;
        });
      } else {
        items = latestItems;
      }
    }
  }

  void _flushPendingRealtime() {
    if (_pendingRealtime.isEmpty) return;
    final pending = List<Map<String, dynamic>>.from(_pendingRealtime);
    _pendingRealtime.clear();
    for (final payload in pending) {
      _handleIncomingRealtime(payload, queueIfNotReady: false);
    }
  }

  ResidentNews? _parseRealtimeNews(Map<String, dynamic> payload) {
    final id = payload['newsId']?.toString() ?? payload['id']?.toString() ?? '';
    if (id.isEmpty) return null;

    final summary =
        payload['summary']?.toString() ?? payload['message']?.toString() ?? '';
    final title = payload['title']?.toString() ?? 'Tin tức mới';
    final cover = payload['coverImageUrl']?.toString();
    final timestampStr = payload['timestamp']?.toString();
    DateTime timestamp;
    if (timestampStr != null) {
      timestamp = DateTime.tryParse(timestampStr)?.toLocal() ??
          DateTime.now().toLocal();
    } else {
      timestamp = DateTime.now().toLocal();
    }

    return ResidentNews(
      id: id,
      title: title,
      summary: summary,
      bodyHtml: '',
      coverImageUrl: cover,
      status: 'PUBLISHED',
      publishAt: timestamp,
      expireAt: null,
      displayOrder: 0,
      viewCount: 0,
      images: const [],
      createdBy: null,
      createdAt: timestamp,
      updatedBy: null,
      updatedAt: timestamp,
    );
  }

  void _insertNewsIntoCache(ResidentNews news) {
    _allCachedItems ??= [];
    _allCachedItems!.removeWhere((element) => element.id == news.id);
    _allCachedItems!.insert(0, news);
    _allCachedItems!.sort((a, b) {
      final aDate = a.publishAt ?? a.createdAt;
      final bDate = b.publishAt ?? b.createdAt;
      return bDate.compareTo(aDate);
    });
    _totalItems = _allCachedItems!.length;
  }

  List<ResidentNews> _buildPageItems(int page) {
    if (_allCachedItems == null || _allCachedItems!.isEmpty) return [];
    final startIndex = page * _pageSize;
    final endIndex = (startIndex + _pageSize).clamp(0, _allCachedItems!.length);
    if (startIndex >= _allCachedItems!.length) return [];
    return _allCachedItems!.sublist(startIndex, endIndex);
  }

  void _goToPage(int page) {
    if (page == _currentPage || loading || page < 0) return;
    final totalPages = _getTotalPages();
    if (page >= totalPages) {
      debugPrint(
          '⚠️ Không thể chuyển đến trang $page, tổng số trang là $totalPages');
      return;
    }
    _fetch(targetPage: page);
  }

  Future<void> _markAsRead(ResidentNews news) async {
    if (_residentId == null || _residentId!.isEmpty) return;
    final updated = await NewsReadStore.markRead(_residentId!, news.id);
    if (!mounted) return;
    if (updated) {
      setState(() {
        _readNewsIds = {..._readNewsIds, news.id};
      });
      _bus.emit('news_read_status_updated', news.id);
    }
  }

  Future<void> _openNewsDetail(ResidentNews news) async {
    await _markAsRead(news);
    if (!mounted) return;

    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: NewsDetailScreen(
              residentNews: news,
            ),
          );
        },
      ),
    );

    if (!mounted) return;
    setState(() {
      // Trigger rebuild to refresh read state visuals when returning.
    });
  }

  String _formatCardDate(ResidentNews news) {
    final date = news.publishAt ?? news.createdAt;
    try {
      return DateFormat('EEE, dd MMM yyyy • HH:mm', 'vi_VN').format(date);
    } catch (_) {
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    }
  }

  @override
  void dispose() {
    _bus.off('news_update');
    _bus.off('news_read_status_updated');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalItems = _allCachedItems?.length ?? items.length;
    final unreadTotal = _allCachedItems != null
        ? _allCachedItems!
            .where((news) => !_readNewsIds.contains(news.id))
            .length
        : items.where((news) => !_readNewsIds.contains(news.id)).length;
    final hasAnyItems = totalItems > 0;
    final readTotal = hasAnyItems
        ? (_allCachedItems != null
            ? _allCachedItems!
                .where((news) => _readNewsIds.contains(news.id))
                .length
            : items.where((news) => _readNewsIds.contains(news.id)).length)
        : 0;

    final visibleItems = _filter == InfoListFilter.all
        ? items
        : items.where((news) {
            final isRead = _readNewsIds.contains(news.id);
            if (_filter == InfoListFilter.unread) {
              return !isRead;
            }
            return isRead;
          }).toList();

    final gradient = theme.brightness == Brightness.dark
        ? const LinearGradient(
            colors: [Color(0xFF050F1F), Color(0xFF0D2036)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : const LinearGradient(
            colors: [Color(0xFFF4F7FE), Color(0xFFFFFFFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Thông tin'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: gradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, unreadTotal, totalItems),
              const SizedBox(height: 12),
              Expanded(
                child: RefreshIndicator(
                  color: theme.colorScheme.primary,
                  edgeOffset: 20,
                  onRefresh: () => _fetch(targetPage: _currentPage),
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: loading
                            ? SliverFillRemaining(
                                hasScrollBody: false,
                                child: _buildLoadingState(),
                              )
                            : visibleItems.isEmpty
                                ? SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _buildEmptyState(
                                      filter: _filter,
                                      hasAnyItems: hasAnyItems,
                                      unreadTotal: unreadTotal,
                                      readTotal: readTotal,
                                    ),
                                  )
                                : SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final news = visibleItems[index];
                                        final isRead =
                                            _readNewsIds.contains(news.id);
                                        return _buildInfoCard(
                                            context, news, isRead);
                                      },
                                      childCount: visibleItems.length,
                                    ),
                                  ),
                      ),
                      if (!loading && items.isNotEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                          sliver: SliverToBoxAdapter(
                            child: _buildPaginationControls(context),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int unreadCount, int totalCount) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gradient = isDark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();
    final borderColor =
        (isDark ? AppColors.navyOutline : AppColors.neutralOutline)
            .withOpacity(0.45);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: borderColor),
              boxShadow: AppColors.subtleShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thông tin cư dân',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatChip(
                        context,
                        label: 'Chưa đọc',
                        value: unreadCount,
                        isAccent: true,
                      ),
                      const SizedBox(width: 12),
                      _buildStatChip(
                        context,
                        label: 'Tổng số',
                        value: totalCount,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Làm mới',
                        onPressed: loading
                            ? null
                            : () => _fetch(targetPage: _currentPage),
                        icon: const Icon(CupertinoIcons.refresh),
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildFilterControl(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(
    BuildContext context, {
    required String label,
    required int value,
    bool isAccent = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color badgeColor = isAccent
        ? theme.colorScheme.primary
        : (isDark
            ? Colors.white.withOpacity(0.4)
            : AppColors.primaryBlue.withOpacity(0.85));
    final Color chipColor = isAccent
        ? badgeColor.withOpacity(isDark ? 0.28 : 0.18)
        : (isDark
            ? Colors.white.withOpacity(0.08)
            : Colors.white.withOpacity(0.72));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAccent
              ? badgeColor.withOpacity(isDark ? 0.9 : 0.45)
              : (isDark ? AppColors.navyOutline : AppColors.neutralOutline)
                  .withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: badgeColor.withOpacity(0.32),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              '$value',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterControl(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final thumbColor =
        theme.colorScheme.primary.withOpacity(isDark ? 0.4 : 0.9);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.white.withOpacity(0.7),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: CupertinoSlidingSegmentedControl<InfoListFilter>(
        groupValue: _filter,
        backgroundColor: Colors.transparent,
        thumbColor: thumbColor,
        onValueChanged: (value) {
          if (value == null) return;
          setState(() => _filter = value);
        },
        children: {
          InfoListFilter.all:
              _buildSegmentLabel(theme, InfoListFilter.all, 'Tất cả'),
          InfoListFilter.unread:
              _buildSegmentLabel(theme, InfoListFilter.unread, 'Chưa đọc'),
          InfoListFilter.read:
              _buildSegmentLabel(theme, InfoListFilter.read, 'Đã đọc'),
        },
      ),
    );
  }

  Widget _buildSegmentLabel(
    ThemeData theme,
    InfoListFilter filter,
    String label,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _filter == filter;
    final Color color = isSelected
        ? Colors.white
        : (isDark ? Colors.white70 : AppColors.textSecondary);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ) ??
            TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
        child: Text(label),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    ResidentNews news,
    bool isRead,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final gradient = isDark
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isRead
                ? [
                    const Color(0xAA0E1B33),
                    const Color(0x66102238),
                  ]
                : [
                    const Color(0xFF1C3C87),
                    const Color(0xFF0F1E36),
                  ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isRead
                ? [
                    Colors.white.withOpacity(0.95),
                    Colors.white.withOpacity(0.88),
                  ]
                : [
                    const Color(0xFFE6F1FF),
                    const Color(0xFFF3FBFF),
                  ],
          );

    final borderColor = isRead
        ? (isDark ? AppColors.navyOutline : AppColors.neutralOutline)
            .withOpacity(0.42)
        : theme.colorScheme.primary.withOpacity(isDark ? 0.6 : 0.35);

    return Hero(
      tag: 'news_${news.id}',
      child: GestureDetector(
        onTap: () => _openNewsDetail(news),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppColors.subtleShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: borderColor),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isRead) ...[
                            _buildUnreadDot(theme),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  news.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _formatCardDate(news),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: isDark
                                        ? Colors.white70
                                        : AppColors.textSecondary,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            CupertinoIcons.chevron_right,
                            size: 18,
                            color: isDark
                                ? Colors.white54
                                : AppColors.textSecondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        news.summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                          color: isDark
                              ? Colors.white.withOpacity(0.78)
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadDot(ThemeData theme) {
    final color = theme.colorScheme.primary;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required InfoListFilter filter,
    required bool hasAnyItems,
    required int unreadTotal,
    required int readTotal,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    late final IconData icon;
    late final String title;
    late final String subtitle;

    if (!hasAnyItems) {
      icon = CupertinoIcons.bell_slash;
      title = 'Chưa có thông tin';
      subtitle = 'Chúng tôi sẽ cập nhật khi có thông tin mới cho cư dân.';
    } else if (filter == InfoListFilter.unread && unreadTotal == 0) {
      icon = CupertinoIcons.check_mark_circled_solid;
      title = 'Bạn đã đọc hết thông tin';
      subtitle = 'Thông tin mới sẽ hiển thị ngay khi được cập nhật.';
    } else if (filter == InfoListFilter.read && readTotal == 0) {
      icon = CupertinoIcons.doc_text;
      title = 'Chưa có thông tin đã đọc';
      subtitle = 'Mở một thông tin bất kỳ để đánh dấu là đã xem.';
    } else {
      icon = CupertinoIcons.search;
      title = 'Không có mục phù hợp';
      subtitle = 'Thử chuyển sang trang khác hoặc thay đổi bộ lọc.';
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 72,
            color: isDark
                ? Colors.white24
                : AppColors.textSecondary.withOpacity(0.35),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 280,
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white70 : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoActivityIndicator(
            radius: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Đang tải thông tin mới...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls(BuildContext context) {
    if (items.isEmpty || loading) return const SizedBox.shrink();

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gradient = isDark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();
    final borderColor =
        (isDark ? AppColors.navyOutline : AppColors.neutralOutline)
            .withOpacity(0.45);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              children: [
                Text(
                  'Trang $currentPageNumber / $totalPages',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildPageNavigationButton(
                      context,
                      icon: CupertinoIcons.chevron_left,
                      enabled: _currentPage > 0,
                      onTap: () => _goToPage(_currentPage - 1),
                    ),
                    const SizedBox(width: 6),
                    ...pageNumbers.map((pageIndex) {
                      if (pageIndex == -1) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '•••',
                            style: TextStyle(
                              letterSpacing: 6,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      }

                      final pageNumber = pageIndex + 1;
                      final isCurrentPage = pageIndex == _currentPage;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isCurrentPage
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCurrentPage
                                  ? theme.colorScheme.primary
                                  : borderColor,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: isCurrentPage
                                ? null
                                : () => _goToPage(pageIndex),
                            child: Center(
                              child: Text(
                                '$pageNumber',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: isCurrentPage
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isCurrentPage
                                      ? Colors.white
                                      : (isDark
                                          ? Colors.white70
                                          : AppColors.textPrimary),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(width: 6),
                    _buildPageNavigationButton(
                      context,
                      icon: CupertinoIcons.chevron_right,
                      enabled: _currentPage < totalPages - 1,
                      onTap: () => _goToPage(_currentPage + 1),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageNavigationButton(
    BuildContext context, {
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color color = theme.colorScheme.primary;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.35,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: enabled
                ? color.withOpacity(isDark ? 0.3 : 0.18)
                : Colors.transparent,
            border: Border.all(
              color: enabled
                  ? color.withOpacity(isDark ? 0.8 : 0.5)
                  : (isDark ? AppColors.navyOutline : AppColors.neutralOutline)
                      .withOpacity(0.35),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? color
                : (isDark ? Colors.white54 : AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
