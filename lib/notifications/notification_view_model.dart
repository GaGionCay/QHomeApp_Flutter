import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/resident_notification.dart';
import '../news/resident_service.dart';

class NotificationViewModel extends ChangeNotifier {
  final ResidentService _residentService = ResidentService();

  List<ResidentNotification> _notifications = [];
  List<ResidentNotification> get notifications => _notifications;

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
  String? _buildingId;

  DateTime? _filterDateFrom;
  DateTime? get filterDateFrom => _filterDateFrom;

  DateTime? _filterDateTo;
  DateTime? get filterDateTo => _filterDateTo;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  void setResidentAndBuilding(String? residentId, String? buildingId) {
    _residentId = residentId;
    _buildingId = buildingId;
  }

  Map<String, List<ResidentNotification>> get groupedNotifications {
    List<ResidentNotification> filteredNotifications = _notifications;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filteredNotifications = _notifications.where((notification) {
        return notification.title.toLowerCase().contains(query);
      }).toList();
    }
    final Map<String, List<ResidentNotification>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final notification in filteredNotifications) {
      final notificationDate = DateTime(
        notification.createdAt.year,
        notification.createdAt.month,
        notification.createdAt.day,
      );

      String groupKey;
      if (notificationDate.isAtSameMomentAs(today)) {
        groupKey = 'Hôm nay';
      } else if (notificationDate.isAtSameMomentAs(yesterday)) {
        groupKey = 'Hôm qua';
      } else {
        groupKey = DateFormat('dd/MM/yyyy').format(notificationDate);
      }

      if (!grouped.containsKey(groupKey)) {
        grouped[groupKey] = [];
      }
      grouped[groupKey]!.add(notification);
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

    final Map<String, List<ResidentNotification>> sortedGrouped = {};
    for (final key in sortedKeys) {
      sortedGrouped[key] = grouped[key]!..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return sortedGrouped;
  }

  Future<void> loadNotifications({bool refresh = false}) async {
    if (_residentId == null || _buildingId == null) {
      _error = 'Chưa có thông tin residentId hoặc buildingId';
      notifyListeners();
      return;
    }

    if (refresh) {
      _currentPage = 0;
      _hasMore = true;
      _notifications.clear();
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

      final fetched = await _residentService.getResidentNotifications(
        _residentId!,
        _buildingId!,
        page: _currentPage,
        limit: _limit,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      if (refresh) {
        _notifications = fetched;
      } else {
        _notifications.addAll(fetched);
      }

      _hasMore = fetched.length == _limit;
      if (_hasMore) {
        _currentPage++;
      }

      _error = null;
    } catch (e) {
      _error = 'Lỗi tải thông báo: ${e.toString()}';
      debugPrint('❌ Error loading notifications: $e');
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
    await loadNotifications(refresh: false);
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

  bool get hasActiveFilters => _filterDateFrom != null || _filterDateTo != null;

  void updateNotifications(List<ResidentNotification> notifications) {
    _notifications = notifications;
    notifyListeners();
  }
}

