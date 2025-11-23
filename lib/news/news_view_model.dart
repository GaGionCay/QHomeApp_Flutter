import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/resident_news.dart';
import '../news/resident_service.dart';
import '../notifications/widgets/notification_read_status_filter.dart';

class NewsViewModel extends ChangeNotifier {
  final ResidentService _residentService = ResidentService();

  List<ResidentNews> _news = [];
  List<ResidentNews> get news => List.unmodifiable(_news);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  String? _error;
  String? get error => _error;

  int _currentPage = 0;
  int get currentPage => _currentPage;

  final int _pageSize = 7; // Fixed page size as per requirement
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

    debugPrint('🔍 [NewsViewModel] loadNews: residentId=$_residentId, page=$page, refresh=$refresh');

    if (refresh || page != null) {
      _currentPage = page ?? 0;
      _news.clear();
    }

    _isLoading = refresh || page != null;
    _isLoadingMore = !refresh && page == null;
    _error = null;
    notifyListeners();

    try {
      final dateFrom = _filterDateFrom;
      final dateTo = _filterDateTo;

      debugPrint('🔍 [NewsViewModel] Calling getResidentNewsPaged with residentId=$_residentId, page=$_currentPage, size=$_pageSize');
      final pagedResponse = await _residentService.getResidentNewsPaged(
        _residentId!,
        page: _currentPage,
        size: _pageSize,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      
      debugPrint('✅ [NewsViewModel] Received ${pagedResponse.content.length} news items, totalElements=${pagedResponse.totalElements}');

      _news = pagedResponse.content;
      _currentPage = pagedResponse.currentPage;
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
    notifyListeners();
  }

  void clearFilters() {
    _filterDateFrom = null;
    _filterDateTo = null;
    _currentPage = 0;
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
    notifyListeners();
  }

  bool get hasActiveFilters => _filterDateFrom != null || _filterDateTo != null;

  void updateNews(List<ResidentNews> news) {
    _news = news;
    notifyListeners();
  }
}

