import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/resident_news.dart';
import '../news/resident_service.dart';
import '../notifications/widgets/notification_read_status_filter.dart';

class NewsViewModel extends ChangeNotifier {
  final ResidentService _residentService = ResidentService();

  List<ResidentNews> _news = [];
  List<ResidentNews> get news => List.unmodifiable(_news);
  
  // Store all news (unfiltered) for client-side pagination after filtering
  List<ResidentNews> _allNews = [];
  int? _pageSize; // Set from API response

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  String? _error;
  String? get error => _error;

  int _currentPage = 0;
  int get currentPage => _currentPage;

  int _totalPages = 0;
  int get totalPages => _totalPages;
  int _totalElements = 0;
  int get totalElements => _totalElements;
  bool _hasNext = false;
  bool get hasNext => _hasNext;
  bool _hasPrevious = false;
  bool get hasPrevious => _hasPrevious;
  bool _isFirst = true;
  bool get isFirst => _isFirst;
  bool _isLast = true;
  bool get isLast => _isLast;

  String? _residentId;
  Set<String> _readIds = {};

  DateTime? _filterDateFrom;
  DateTime? get filterDateFrom => _filterDateFrom;

  DateTime? _filterDateTo;
  DateTime? get filterDateTo => _filterDateTo;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  NotificationReadStatusFilter _readStatusFilter = NotificationReadStatusFilter.all;
  NotificationReadStatusFilter get readStatusFilter => _readStatusFilter;

  void setResidentId(String? residentId) {
    _residentId = residentId;
  }

  void setReadIds(Set<String> readIds) {
    _readIds = readIds;
    notifyListeners();
  }

  void markAsRead(String newsId) {
    _readIds = {..._readIds, newsId};
    notifyListeners();
  }

  bool isNewsRead(String newsId) {
    return _readIds.contains(newsId);
  }

  /// Get filtered news for current page
  List<ResidentNews> get _filteredNews {
    List<ResidentNews> filtered = List.from(_allNews);

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((news) {
        return news.title.toLowerCase().contains(query);
      }).toList();
    }

    if (_readStatusFilter != NotificationReadStatusFilter.all) {
      filtered = filtered.where((news) {
        final isRead = _readIds.contains(news.id);
        if (_readStatusFilter == NotificationReadStatusFilter.read) {
          return isRead;
        } else {
          return !isRead;
        }
      }).toList();
    }

    return filtered;
  }

  Map<String, List<ResidentNews>> get groupedNews {
    List<ResidentNews> filteredNews = _news;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filteredNews = filteredNews.where((news) {
        return news.title.toLowerCase().contains(query);
      }).toList();
    }

    if (_readStatusFilter != NotificationReadStatusFilter.all) {
      filteredNews = filteredNews.where((news) {
        final isRead = _readIds.contains(news.id);
        if (_readStatusFilter == NotificationReadStatusFilter.read) {
          return isRead;
        } else {
          return !isRead;
        }
      }).toList();
    }

    final Map<String, List<ResidentNews>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final newsItem in filteredNews) {
      final newsDate = newsItem.publishAt ?? newsItem.createdAt;
      final newsDateOnly = DateTime(
        newsDate.year,
        newsDate.month,
        newsDate.day,
      );

      String groupKey;
      if (newsDateOnly.isAtSameMomentAs(today)) {
        groupKey = 'Hôm nay';
      } else if (newsDateOnly.isAtSameMomentAs(yesterday)) {
        groupKey = 'Hôm qua';
      } else {
        groupKey = DateFormat('dd/MM/yyyy').format(newsDateOnly);
      }

      if (!grouped.containsKey(groupKey)) {
        grouped[groupKey] = [];
      }
      grouped[groupKey]!.add(newsItem);
    }

    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'Hôm nay') return -1;
        if (b == 'Hôm nay') return 1;
        if (a == 'Hôm qua') {
          if (b == 'Hôm nay') return 1;
          return -1;
        }
        if (b == 'Hôm qua') return 1;

        try {
          final dateA = DateFormat('dd/MM/yyyy').parse(a);
          final dateB = DateFormat('dd/MM/yyyy').parse(b);
          return dateB.compareTo(dateA);
        } catch (e) {
          return a.compareTo(b);
        }
      });

    final Map<String, List<ResidentNews>> sortedGrouped = {};
    for (final key in sortedKeys) {
      sortedGrouped[key] = grouped[key]!
        ..sort((a, b) {
          final aDate = a.publishAt ?? a.createdAt;
          final bDate = b.publishAt ?? b.createdAt;
          return bDate.compareTo(aDate);
        });
    }

    return sortedGrouped;
  }

  Future<void> loadNews({bool refresh = false, int? page}) async {
    if (_residentId == null) {
      _error = 'Chưa có thông tin residentId';
      debugPrint('❌ [NewsViewModel] loadNews: residentId is null');
      notifyListeners();
      return;
    }

    // If readStatusFilter is active, load all news and paginate client-side
    final shouldLoadAll = _readStatusFilter != NotificationReadStatusFilter.all;
    
    if (shouldLoadAll) {
      await _loadAllAndPaginateClientSide(refresh: refresh, page: page);
      return;
    }

    // Otherwise, use server-side pagination
    debugPrint('🔍 [NewsViewModel] loadNews: residentId=$_residentId, page=$page, refresh=$refresh');

    if (refresh || page != null) {
      _currentPage = page ?? 0;
      _news.clear();
      _allNews.clear();
    }

    _isLoading = refresh || page != null;
    _isLoadingMore = !refresh && page == null;
    _error = null;
    notifyListeners();

    try {
      final dateFrom = _filterDateFrom;
      final dateTo = _filterDateTo;

      debugPrint('🔍 [NewsViewModel] Calling getResidentNewsPaged with residentId=$_residentId, page=$_currentPage, size=${_pageSize ?? 7}');
      final pagedResponse = await _residentService.getResidentNewsPaged(
        _residentId!,
        page: _currentPage,
        size: _pageSize ?? 7, // Use default if not set yet
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      
      debugPrint('✅ [NewsViewModel] Received ${pagedResponse.content.length} news items, totalElements=${pagedResponse.totalElements}');

      _news = pagedResponse.content;
      _currentPage = pagedResponse.currentPage;
      _pageSize = pagedResponse.pageSize; // Get page size from response
      _totalPages = pagedResponse.totalPages;
      _totalElements = pagedResponse.totalElements;
      _hasNext = pagedResponse.hasNext;
      _hasPrevious = pagedResponse.hasPrevious;
      _isFirst = pagedResponse.isFirst;
      _isLast = pagedResponse.isLast;

      _error = null;
    } catch (e) {
      _error = 'Lỗi tải tin tức: ${e.toString()}';
      debugPrint('❌ Error loading news: $e');
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Load all news and paginate client-side after filtering
  Future<void> _loadAllAndPaginateClientSide({bool refresh = false, int? page}) async {
    if (refresh || _allNews.isEmpty) {
      _isLoading = true;
      _error = null;
      _currentPage = 0;
      notifyListeners();

      try {
        final dateFrom = _filterDateFrom;
        final dateTo = _filterDateTo;

        // Load first page to get pageSize from response
        final firstPageResponse = await _residentService.getResidentNewsPaged(
          _residentId!,
          page: 0,
          size: 7, // Default size, will be overridden by response
          dateFrom: dateFrom,
          dateTo: dateTo,
        );
        _pageSize = firstPageResponse.pageSize; // Get page size from response

        // Load all news with pageSize from first response
        _allNews = await _residentService.getAllResidentNews(
          _residentId!,
          dateFrom: dateFrom,
          dateTo: dateTo,
          pageSize: _pageSize, // Will be set from firstPageResponse above
        );
      } catch (e) {
        _error = 'Lỗi tải tin tức: ${e.toString()}';
        debugPrint('❌ Error loading all news: $e');
        _isLoading = false;
        notifyListeners();
        return;
      }
    }

    if (page != null) {
      _currentPage = page;
    }

    // If refreshing, show loading while filtering and paginating
    if (refresh) {
      _isLoading = true;
      notifyListeners();
    }

    // Apply filters and paginate client-side
    final filtered = _filteredNews;
    
    // Ensure pageSize is set (should be set from first page response)
    if (_pageSize == null) {
      debugPrint('⚠️ [NewsViewModel] pageSize is null, cannot paginate');
      _news = [];
      _totalPages = 1;
      _totalElements = 0;
      _hasNext = false;
      _hasPrevious = false;
      _isFirst = true;
      _isLast = true;
      _isLoading = false;
      notifyListeners();
      return;
    }
    
    // Calculate pagination
    _totalElements = filtered.length;
    _totalPages = (_totalElements / _pageSize!).ceil();
    if (_totalPages == 0) _totalPages = 1; // At least 1 page even if empty
    
    // Ensure current page is valid
    if (_currentPage >= _totalPages) {
      _currentPage = _totalPages > 0 ? _totalPages - 1 : 0;
    }
    
    // Get news for current page
    final startIndex = _currentPage * _pageSize!;
    final endIndex = (startIndex + _pageSize!).clamp(0, filtered.length);
    _news = filtered.sublist(
      startIndex.clamp(0, filtered.length),
      endIndex,
    );
    
    // Update pagination flags
    _hasNext = _currentPage < _totalPages - 1;
    _hasPrevious = _currentPage > 0;
    _isFirst = _currentPage == 0;
    _isLast = _currentPage >= _totalPages - 1;

    // Call callback to update read status BEFORE pagination
    // This ensures read status is correct when filtering
    if (onNewsLoaded != null) {
      await onNewsLoaded!();
    }
    
    // Now paginate with correct read status
    _rePaginateClientSide();
    
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  // Callback to be called after loadNews completes
  // This allows the screen to update read status from local storage
  Function()? onNewsLoaded;

  Future<void> goToPage(int page) async {
    if (page < 0 || page >= _totalPages) {
      return;
    }
    await loadNews(page: page);
  }

  Future<void> nextPage() async {
    if (_hasNext) {
      await loadNews(page: _currentPage + 1);
    }
  }

  Future<void> previousPage() async {
    if (_hasPrevious) {
      await loadNews(page: _currentPage - 1);
    }
  }

  void setDateFilter(DateTime? dateFrom, DateTime? dateTo) {
    _filterDateFrom = dateFrom;
    _filterDateTo = dateTo;
    _currentPage = 0;
    // Clear cached all news to force reload
    _allNews.clear();
    notifyListeners();
  }

  void clearFilters() {
    _filterDateFrom = null;
    _filterDateTo = null;
    _readStatusFilter = NotificationReadStatusFilter.all;
    _currentPage = 0;
    // Clear cached all news to force reload
    _allNews.clear();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  void setReadStatusFilter(NotificationReadStatusFilter filter) {
    _readStatusFilter = filter;
    _currentPage = 0; // Reset to first page when filter changes
    // Clear cached all news to force reload
    _allNews.clear();
    notifyListeners();
  }

  bool get hasActiveFilters => _filterDateFrom != null || _filterDateTo != null;

  void updateNews(List<ResidentNews> news) {
    _news = news;
    // Also update _allNews if we have client-side pagination active
    if (_readStatusFilter != NotificationReadStatusFilter.all && _allNews.isNotEmpty) {
      // Update read status in _allNews
      final newsMap = {for (var n in news) n.id: n};
      for (int i = 0; i < _allNews.length; i++) {
        final updated = newsMap[_allNews[i].id];
        if (updated != null) {
          _allNews[i] = updated;
        }
      }
      // Re-paginate after updating read status
      _rePaginateClientSide();
    }
    notifyListeners();
  }
  
  /// Update read status of a specific news in _allNews
  void updateNewsReadStatus(String newsId, bool isRead) {
    if (_allNews.isNotEmpty) {
      final index = _allNews.indexWhere((n) => n.id == newsId);
      if (index != -1) {
        _allNews[index] = _allNews[index]; // News doesn't have isRead field, we use _readIds
        debugPrint('✅ [NewsViewModel] Updated read status for news $newsId: $isRead');
      }
    }
  }
  
  /// Update read status for all news in _allNews based on read IDs
  void updateAllNewsReadStatus(Set<String> readIds) {
    if (_allNews.isEmpty) return;
    
    // Read status is stored in _readIds, not in news objects
    // Update _readIds and re-paginate
    _readIds = readIds;
    
    debugPrint('✅ [NewsViewModel] Updated read status for ${_allNews.where((n) => readIds.contains(n.id)).length} news in _allNews');
    // Re-paginate if using client-side pagination
    if (_readStatusFilter != NotificationReadStatusFilter.all) {
      _rePaginateClientSide();
    }
    notifyListeners();
  }
  
  /// Re-paginate client-side after updating news
  void _rePaginateClientSide() {
    final filtered = _filteredNews;
    
    // Ensure pageSize is set
    if (_pageSize == null) {
      debugPrint('⚠️ [NewsViewModel] pageSize is null, cannot re-paginate');
      return;
    }
    
    // Calculate pagination
    _totalElements = filtered.length;
    _totalPages = (_totalElements / _pageSize!).ceil();
    if (_totalPages == 0) _totalPages = 1;
    
    // Ensure current page is valid
    if (_currentPage >= _totalPages) {
      _currentPage = _totalPages > 0 ? _totalPages - 1 : 0;
    }
    
    // Get news for current page
    final startIndex = _currentPage * _pageSize!;
    final endIndex = (startIndex + _pageSize!).clamp(0, filtered.length);
    _news = filtered.sublist(
      startIndex.clamp(0, filtered.length),
      endIndex,
    );
    
    // Update pagination flags
    _hasNext = _currentPage < _totalPages - 1;
    _hasPrevious = _currentPage > 0;
    _isFirst = _currentPage == 0;
    _isLast = _currentPage >= _totalPages - 1;
  }
}

