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
  
  // Store all notifications (unfiltered) for client-side pagination after filtering
  List<ResidentNotification> _allNotifications = [];
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

  /// Get filtered notifications for current page
  List<ResidentNotification> get _filteredNotifications {
    List<ResidentNotification> filtered = List.from(_allNotifications);

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((notification) {
        return notification.title.toLowerCase().contains(query);
      }).toList();
    }

    if (_readStatusFilter != NotificationReadStatusFilter.all) {
      filtered = filtered.where((notification) {
        if (_readStatusFilter == NotificationReadStatusFilter.read) {
          return notification.isRead;
        } else {
          return !notification.isRead;
        }
      }).toList();
    }

    if (_typeFilter != NotificationTypeFilter.all) {
      filtered = filtered.where((notification) {
        if (_typeFilter == NotificationTypeFilter.cardApproved) {
          return notification.type.toUpperCase() == 'CARD_APPROVED';
        }
        return true;
      }).toList();
    }

    return filtered;
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

    // If readStatusFilter is active, load all notifications and paginate client-side
    final shouldLoadAll = _readStatusFilter != NotificationReadStatusFilter.all;
    
    if (shouldLoadAll) {
      await _loadAllAndPaginateClientSide(refresh: refresh, page: page);
      return;
    }

    // Otherwise, use server-side pagination
    if (refresh) {
      _currentPage = 0;
      _notifications.clear();
      _allNotifications.clear();
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
        size: _pageSize ?? 7, // Use default if not set yet
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      _notifications = pagedResponse.content;
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

  /// Load all notifications and paginate client-side after filtering
  Future<void> _loadAllAndPaginateClientSide({bool refresh = false, int? page}) async {
    // Always show loading when refreshing or when allNotifications is empty
    if (refresh || _allNotifications.isEmpty) {
      _isLoading = true;
      _error = null;
      _currentPage = 0;
      notifyListeners();

      try {
        final dateFrom = _filterDateFrom;
        final dateTo = _filterDateTo;

        // Load first page to get pageSize from response
        final firstPageResponse = await _residentService.getResidentNotificationsPaged(
          _residentId!,
          _buildingId!,
          page: 0,
          size: 7, // Default size, will be overridden by response
          dateFrom: dateFrom,
          dateTo: dateTo,
        );
        _pageSize = firstPageResponse.pageSize; // Get page size from response

        // Load all notifications with pageSize from first response
        _allNotifications = await _residentService.getAllResidentNotifications(
          _residentId!,
          _buildingId!,
          dateFrom: dateFrom,
          dateTo: dateTo,
          pageSize: _pageSize, // Will be set from firstPageResponse above
        );
      } catch (e) {
        _error = 'Lỗi tải thông báo: ${e.toString()}';
        debugPrint('❌ Error loading all notifications: $e');
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
    final filtered = _filteredNotifications;
    
    // Ensure pageSize is set (should be set from first page response)
    if (_pageSize == null) {
      debugPrint('⚠️ [NotificationViewModel] pageSize is null, cannot paginate');
      _notifications = [];
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
    
    // Get notifications for current page
    final startIndex = _currentPage * _pageSize!;
    final endIndex = (startIndex + _pageSize!).clamp(0, filtered.length);
    _notifications = filtered.sublist(
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
    if (onNotificationsLoaded != null) {
      await onNotificationsLoaded!();
    }
    
    // Now paginate with correct read status
    _rePaginateClientSide();
    
    _isLoading = false;
    _error = null;
    notifyListeners();
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
    // Clear cached all notifications to force reload
    _allNotifications.clear();
    notifyListeners();
  }

  void clearFilters() {
    _filterDateFrom = null;
    _filterDateTo = null;
    _typeFilter = NotificationTypeFilter.all;
    _readStatusFilter = NotificationReadStatusFilter.all;
    _currentPage = 0;
    // Clear cached all notifications to force reload
    _allNotifications.clear();
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
    // Clear cached all notifications to force reload
    _allNotifications.clear();
    notifyListeners();
  }

  void setTypeFilter(NotificationTypeFilter filter) {
    _typeFilter = filter;
    notifyListeners();
  }

  bool get hasActiveFilters => _filterDateFrom != null || _filterDateTo != null || _typeFilter != NotificationTypeFilter.all;

  void updateNotifications(List<ResidentNotification> notifications) {
    _notifications = notifications;
    // Also update _allNotifications if we have client-side pagination active
    if (_readStatusFilter != NotificationReadStatusFilter.all && _allNotifications.isNotEmpty) {
      // Update read status in _allNotifications based on current page notifications
      final notificationMap = {for (var n in notifications) n.id: n};
      for (int i = 0; i < _allNotifications.length; i++) {
        final updated = notificationMap[_allNotifications[i].id];
        if (updated != null) {
          _allNotifications[i] = updated;
        }
      }
      // Re-paginate after updating read status
      _rePaginateClientSide();
    }
    notifyListeners();
  }
  
  /// Update read status of a specific notification in _allNotifications
  void updateNotificationReadStatus(String notificationId, bool isRead) {
    if (_allNotifications.isNotEmpty) {
      final index = _allNotifications.indexWhere((n) => n.id == notificationId);
      if (index != -1) {
        final currentReadAt = _allNotifications[index].readAt;
        _allNotifications[index] = _allNotifications[index].copyWith(
          isRead: isRead,
          readAt: isRead ? (currentReadAt ?? DateTime.now()) : null,
        );
        debugPrint('✅ [NotificationViewModel] Updated read status for notification $notificationId: $isRead');
      }
    }
  }
  
  /// Update read status for all notifications in _allNotifications based on read IDs
  void updateAllNotificationsReadStatus(Set<String> readIds) {
    if (_allNotifications.isEmpty) return;
    
    bool updated = false;
    for (int i = 0; i < _allNotifications.length; i++) {
      final notification = _allNotifications[i];
      final shouldBeRead = readIds.contains(notification.id);
      
      if (shouldBeRead != notification.isRead) {
        _allNotifications[i] = _allNotifications[i].copyWith(
          isRead: shouldBeRead,
          readAt: shouldBeRead ? (_allNotifications[i].readAt ?? DateTime.now()) : null,
        );
        updated = true;
      }
    }
    
    if (updated) {
      debugPrint('✅ [NotificationViewModel] Updated read status for ${_allNotifications.where((n) => readIds.contains(n.id)).length} notifications in _allNotifications');
      // Re-paginate if using client-side pagination
      if (_readStatusFilter != NotificationReadStatusFilter.all) {
        _rePaginateClientSide();
      }
      notifyListeners();
    }
  }
  
  /// Re-paginate client-side after updating notifications
  void _rePaginateClientSide() {
    final filtered = _filteredNotifications;
    
    // Ensure pageSize is set
    if (_pageSize == null) {
      debugPrint('⚠️ [NotificationViewModel] pageSize is null, cannot re-paginate');
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
    
    // Get notifications for current page
    final startIndex = _currentPage * _pageSize!;
    final endIndex = (startIndex + _pageSize!).clamp(0, filtered.length);
    _notifications = filtered.sublist(
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


