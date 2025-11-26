import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/resident_notification.dart';
import '../news/resident_service.dart';
import 'widgets/notification_read_status_filter.dart';
import 'widgets/notification_type_filter.dart';

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
  String? _buildingId;

  DateTime? _filterDateFrom;
  DateTime? get filterDateFrom => _filterDateFrom;

  DateTime? _filterDateTo;
  DateTime? get filterDateTo => _filterDateTo;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  NotificationReadStatusFilter _readStatusFilter = NotificationReadStatusFilter.all;
  NotificationReadStatusFilter get readStatusFilter => _readStatusFilter;

  NotificationTypeFilter _typeFilter = NotificationTypeFilter.all;
  NotificationTypeFilter get typeFilter => _typeFilter;

  void setResidentAndBuilding(String? residentId, String? buildingId) {
    _residentId = residentId;
    _buildingId = buildingId;
  }

  Map<String, List<ResidentNotification>> get groupedNotifications {
    List<ResidentNotification> filteredNotifications = _notifications;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filteredNotifications = filteredNotifications.where((notification) {
        return notification.title.toLowerCase().contains(query);
      }).toList();
    }

    if (_readStatusFilter != NotificationReadStatusFilter.all) {
      filteredNotifications = filteredNotifications.where((notification) {
        if (_readStatusFilter == NotificationReadStatusFilter.read) {
          return notification.isRead;
        } else {
          return !notification.isRead;
        }
      }).toList();
    }

    // Filter by type (CARD_APPROVED)
    if (_typeFilter != NotificationTypeFilter.all) {
      filteredNotifications = filteredNotifications.where((notification) {
        if (_typeFilter == NotificationTypeFilter.cardApproved) {
          return notification.type.toUpperCase() == 'CARD_APPROVED';
        }
        return true;
      }).toList();
    }
    final Map<String, List<ResidentNotification>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final notification in filteredNotifications) {
      // Convert to local time before grouping by date
      final localCreatedAt = notification.createdAt.toLocal();
      final notificationDate = DateTime(
        localCreatedAt.year,
        localCreatedAt.month,
        localCreatedAt.day,
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

  Future<void> loadNotifications({bool refresh = false, int? page}) async {
    if (_residentId == null || _buildingId == null) {
      _error = 'Chưa có thông tin residentId hoặc buildingId';
      notifyListeners();
      return;
    }

    if (refresh) {
      _currentPage = 0;
      _notifications.clear();
    } else if (page != null) {
      _currentPage = page;
    }

    _isLoading = refresh;
    _isLoadingMore = !refresh;
    _error = null;
    notifyListeners();

    try {
      final dateFrom = _filterDateFrom;
      final dateTo = _filterDateTo;

      final pagedResponse = await _residentService.getResidentNotificationsPaged(
        _residentId!,
        _buildingId!,
        page: _currentPage,
        size: 7, // Fixed size as per requirement
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      _notifications = pagedResponse.content;
      _currentPage = pagedResponse.currentPage;
      _totalPages = pagedResponse.totalPages;
      _totalElements = pagedResponse.totalElements;
      _hasNext = pagedResponse.hasNext;
      _hasPrevious = pagedResponse.hasPrevious;
      _isFirst = pagedResponse.isFirst;
      _isLast = pagedResponse.isLast;

      _error = null;
    } catch (e) {
      _error = 'Lỗi tải thông báo: ${e.toString()}';
      debugPrint('❌ Error loading notifications: $e');
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
      // Call callback after notifications are loaded to update read status
      if (onNotificationsLoaded != null) {
        onNotificationsLoaded!();
      }
    }
  }

  // Callback to be called after loadNotifications completes
  // This allows the screen to update read status from local storage
  Function()? onNotificationsLoaded;

  Future<void> goToPage(int page) async {
    if (page < 0 || page >= _totalPages) return;
    await loadNotifications(page: page);
  }

  Future<void> nextPage() async {
    if (_hasNext && !_isLoading) {
      await loadNotifications(page: _currentPage + 1);
    }
  }

  Future<void> previousPage() async {
    if (_hasPrevious && !_isLoading) {
      await loadNotifications(page: _currentPage - 1);
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
    _typeFilter = NotificationTypeFilter.all;
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

  void setTypeFilter(NotificationTypeFilter filter) {
    _typeFilter = filter;
    notifyListeners();
  }

  bool get hasActiveFilters => _filterDateFrom != null || _filterDateTo != null || _typeFilter != NotificationTypeFilter.all;

  void updateNotifications(List<ResidentNotification> notifications) {
    _notifications = notifications;
    notifyListeners();
  }
}

