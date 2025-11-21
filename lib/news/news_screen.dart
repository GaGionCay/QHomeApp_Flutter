import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../core/event_bus.dart';
import '../models/resident_news.dart';
import '../profile/profile_service.dart';
import '../notifications/widgets/notification_date_filter.dart';
import '../notifications/widgets/notification_read_status_filter.dart';
import 'news_read_store.dart';
import 'news_view_model.dart';
import 'widgets/news_card.dart';
import 'widgets/news_group_header.dart';
import 'widgets/news_list_skeleton.dart';
import 'widgets/news_search_bar.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> with TickerProviderStateMixin {
  late final NewsViewModel _viewModel;
  final ScrollController _scrollController = ScrollController();
  final ApiClient _api = ApiClient();
  late final ContractService _contractService;
  late final AppEventBus _bus;
  String? _residentId;
  Set<String> _readIds = {};
  bool _filtersCollapsed = true;
  double _lastScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _contractService = ContractService(_api);
    _bus = AppEventBus();
    _viewModel = NewsViewModel();
    _residentId = null;

    _scrollController.addListener(_onScroll);
    _bus.on('news_update', (data) async {
      if (!mounted) return;
      if (_residentId != null) {
        await _viewModel.loadNews(refresh: true);
      }
    });
    _bus.on('news_read_status_updated', (_) {
      if (_residentId != null) {
        _loadReadState();
      }
    });

    _loadResidentIdAndFetch();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _bus.off('news_update');
    _bus.off('news_read_status_updated');
    _viewModel.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (_viewModel.hasMore && !_viewModel.isLoadingMore) {
        _viewModel.loadMore();
      }
    }

    final currentOffset = _scrollController.position.pixels;
    final delta = currentOffset - _lastScrollOffset;
    const threshold = 12;
    if (delta > threshold &&
        currentOffset > 24 &&
        !_filtersCollapsed &&
        _viewModel.news.isNotEmpty) {
      setState(() => _filtersCollapsed = true);
    }
    _lastScrollOffset = currentOffset;
  }

  Future<void> _loadResidentIdAndFetch() async {
    try {
      final profileService = ProfileService(_api.dio);
      final profile = await profileService.getProfile();

      _residentId = profile['residentId']?.toString();

      if (_residentId != null && _residentId!.isNotEmpty) {
        await _loadReadState();
        _viewModel.setResidentId(_residentId!);
        await _viewModel.loadNews(refresh: true);
        _updateReadStatus();
        return;
      }

      if (_residentId == null || _residentId!.isEmpty) {
        await _tryPopulateResidentFromUnits();
      }

      if (_residentId == null || _residentId!.isEmpty) {
        if (mounted) {
          setState(() {});
        }
        return;
      }

      await _loadReadState();
      _viewModel.setResidentId(_residentId!);
      await _viewModel.loadNews(refresh: true);
      _updateReadStatus();
    } catch (e) {
      debugPrint('⚠️ Lỗi lấy residentId: $e');
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadReadState() async {
    if (_residentId == null || _residentId!.isEmpty) return;
    final stored = await NewsReadStore.load(_residentId!);
    if (!mounted) return;
    _readIds = stored;
    _viewModel.setReadIds(_readIds);
  }

  void _updateReadStatus() {
    final news = List<ResidentNews>.from(_viewModel.news);
    for (var i = 0; i < news.length; i++) {
      if (_readIds.contains(news[i].id)) {
        if (!_viewModel.isNewsRead(news[i].id)) {
          _viewModel.markAsRead(news[i].id);
        }
      }
    }
  }

  Future<void> _tryPopulateResidentFromUnits() async {
    try {
      final units = await _contractService.getMyUnits();
      if (units.isEmpty) {
        return;
      }

      for (final unit in units) {
        final candidate = unit.primaryResidentId?.toString();
        if (candidate != null && candidate.isNotEmpty) {
          _residentId = candidate;
          break;
        }
      }

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
      debugPrint('⚠️ Lỗi lấy dữ liệu căn hộ: $e');
    }
  }

  void _handleNewsMarkedRead(String newsId) {
    if (_residentId == null || _residentId!.isEmpty) return;
    // Defer markAsRead to avoid calling setState/notifyListeners during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readIds = {..._readIds, newsId};
      _viewModel.markAsRead(newsId);
      NewsReadStore.markRead(_residentId!, newsId);
      _bus.emit('news_read_status_updated', newsId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Consumer<NewsViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            extendBody: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: AppBar(
              title: const Text('Thông tin'),
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            body: Column(
              children: [
                _buildFilterSection(context, viewModel),
                Expanded(
                  child: RefreshIndicator(
                    color: Theme.of(context).colorScheme.primary,
                    onRefresh: () => viewModel.loadNews(refresh: true),
                    child: _buildBody(context, viewModel),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, NewsViewModel viewModel) {
    if (viewModel.isLoading && viewModel.news.isEmpty) {
      return NewsListSkeleton(controller: _scrollController);
    }

    if (viewModel.error != null && viewModel.news.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              viewModel.error!,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => viewModel.loadNews(refresh: true),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }

    final grouped = viewModel.groupedNews;

    if (grouped.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: grouped.length * 2 + (viewModel.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == grouped.length * 2 && viewModel.isLoadingMore) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (index.isOdd) {
          final groupIndex = (index - 1) ~/ 2;
          final groupKey = grouped.keys.elementAt(groupIndex);
          final newsList = grouped[groupKey]!;

          return Column(
            children: [
              for (final news in newsList)
                Builder(
                  builder: (context) {
                    final isRead = _viewModel.isNewsRead(news.id);
                    return NewsCard(
                      key: ValueKey(news.id),
                      news: news,
                      isRead: isRead,
                      onMarkedAsRead: () => _handleNewsMarkedRead(news.id),
                    );
                  },
                ),
            ],
          );
        } else {
          final groupIndex = index ~/ 2;
          final groupKey = grouped.keys.elementAt(groupIndex);
          return NewsGroupHeader(title: groupKey);
        }
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.article_outlined,
            size: 80,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'Không có tin tức nào',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Kéo xuống để làm mới danh sách',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(BuildContext context, NewsViewModel viewModel) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: GestureDetector(
            onTap: _toggleFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bộ lọc',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _filtersCollapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) {
              final slideAnimation = Tween<Offset>(
                begin: const Offset(0, -0.05),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ));
              return ClipRect(
                child: FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: slideAnimation,
                    child: child,
                  ),
                ),
              );
            },
            child: _filtersCollapsed
                ? const SizedBox.shrink()
                : Column(
                    key: const ValueKey('news-filters-open'),
                    children: [
                      NewsSearchBar(
                        searchQuery: viewModel.searchQuery,
                        onSearchChanged: (query) {
                          viewModel.setSearchQuery(query);
                        },
                        onClear: () {
                          viewModel.clearSearch();
                        },
                      ),
                      NotificationReadStatusFilterWidget(
                        currentFilter: viewModel.readStatusFilter,
                        onFilterChanged: (filter) {
                          viewModel.setReadStatusFilter(filter);
                        },
                      ),
                      NotificationDateFilter(
                        dateFrom: viewModel.filterDateFrom,
                        dateTo: viewModel.filterDateTo,
                        hasActiveFilters: viewModel.hasActiveFilters,
                        onDateFilterChanged: (from, to) {
                          viewModel.setDateFilter(from, to);
                          viewModel.loadNews(refresh: true);
                        },
                        onClearFilters: () {
                          viewModel.clearFilters();
                          viewModel.loadNews(refresh: true);
                        },
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  void _toggleFilters() {
    setState(() => _filtersCollapsed = !_filtersCollapsed);
  }
}
