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

  final int _limit = 20;
  bool _hasMore = true;
  bool get hasMore => _hasMore;

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

  Future<void> loadNews({bool refresh = false}) async {
    if (_residentId == null) {
      _error = 'Chưa có thông tin residentId';
      notifyListeners();
      return;
    }

    if (refresh) {
      _currentPage = 0;
      _hasMore = true;
      _news.clear();
    }

    if (!_hasMore && !refresh) {
      return;
    }

    _isLoading = refresh;
    _isLoadingMore = !refresh;
    _error = null;
    notifyListeners();

    try {
      final dateFrom = _filterDateFrom;
      final dateTo = _filterDateTo;

      final fetched = await _residentService.getResidentNews(
        _residentId!,
        page: _currentPage,
        size: _limit,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      if (refresh) {
        _news = fetched;
      } else {
        _news.addAll(fetched);
      }

      _hasMore = fetched.length == _limit;
      if (_hasMore) {
        _currentPage++;
      }

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

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) {
      return;
    }
    await loadNews(refresh: false);
  }

  void setDateFilter(DateTime? dateFrom, DateTime? dateTo) {
    _filterDateFrom = dateFrom;
    _filterDateTo = dateTo;
    _currentPage = 0;
    _hasMore = true;
    notifyListeners();
  }

  void clearFilters() {
    _filterDateFrom = null;
    _filterDateTo = null;
    _currentPage = 0;
    _hasMore = true;
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

