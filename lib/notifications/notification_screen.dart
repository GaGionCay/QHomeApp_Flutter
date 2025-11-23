import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../core/event_bus.dart';
import '../models/resident_notification.dart';
import '../profile/profile_service.dart';
import 'notification_read_store.dart';
import 'notification_view_model.dart';
import 'widgets/notification_card.dart';
import 'widgets/notification_date_filter.dart';
import 'widgets/notification_group_header.dart';
import 'widgets/notification_list_skeleton.dart';
import 'widgets/notification_search_bar.dart';
import 'widgets/notification_read_status_filter.dart';
import 'widgets/notification_type_filter.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({
    super.key,
    this.initialResidentId,
    this.initialBuildingId,
  });

  final String? initialResidentId;
  final String? initialBuildingId;

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with TickerProviderStateMixin {
  late final NotificationViewModel _viewModel;
  final ScrollController _scrollController = ScrollController();
  final ApiClient _api = ApiClient();
  late final ContractService _contractService;
  late final AppEventBus _bus;
  String? _residentId;
  String? _buildingId;
  Set<String> _readIds = {};
  bool _filtersCollapsed = true;
  double _lastScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _contractService = ContractService(_api);
    _bus = AppEventBus();
    _viewModel = NotificationViewModel();
    _residentId = widget.initialResidentId;
    _buildingId = widget.initialBuildingId;

    _scrollController.addListener(_onScroll);
    _bus.on('notifications_refetch', (_) async {
      if (!mounted) return;
      if (_residentId != null && _buildingId != null) {
        await _viewModel.loadNotifications(refresh: true);
        await _updateReadStatus();
      }
    });
    _bus.on('notifications_incoming', (payload) {
      if (!mounted) return;
      if (payload is Map<String, dynamic>) {
        _handleIncomingRealtime(payload);
      }
    });

    _loadIdsAndFetch();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _bus.off('notifications_refetch');
    _bus.off('notifications_incoming');
    _viewModel.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Simplified scroll handler - only for collapsing filters
    final offset = _scrollController.position.pixels;
    final delta = offset - _lastScrollOffset;
    const threshold = 12;
    if (delta > threshold &&
        offset > 24 &&
        !_filtersCollapsed &&
        _viewModel.notifications.isNotEmpty) {
      setState(() => _filtersCollapsed = true);
    }
    _lastScrollOffset = offset;
  }

  Future<void> _loadIdsAndFetch() async {
    try {
      if ((_residentId?.isNotEmpty ?? false) &&
          (_buildingId?.isNotEmpty ?? false)) {
        _readIds = await NotificationReadStore.load(_residentId!);
        _viewModel.setResidentAndBuilding(_residentId!, _buildingId!);
        await _viewModel.loadNotifications(refresh: true);
        await _updateReadStatus();
        return;
      }

      final profileService = ProfileService(_api.dio);
      final profile = await profileService.getProfile();

      _residentId = profile['residentId']?.toString();
      _buildingId = profile['buildingId']?.toString();

      if (_residentId != null &&
          _residentId!.isNotEmpty &&
          _buildingId != null &&
          _buildingId!.isNotEmpty) {
        _readIds = await NotificationReadStore.load(_residentId!);
        _viewModel.setResidentAndBuilding(_residentId!, _buildingId!);
        await _viewModel.loadNotifications(refresh: true);
        await _updateReadStatus();
        return;
      }

      if (_residentId == null ||
          _residentId!.isEmpty ||
          _buildingId == null ||
          _buildingId!.isEmpty) {
        await _tryPopulateFromUnits();
      }

      if (_residentId == null || _residentId!.isEmpty) {
        if (mounted) {
          setState(() {});
        }
        return;
      }

      if (_buildingId == null || _buildingId!.isEmpty) {
        if (mounted) {
          setState(() {});
        }
        return;
      }

      _readIds = await NotificationReadStore.load(_residentId!);
      _viewModel.setResidentAndBuilding(_residentId!, _buildingId!);
      await _viewModel.loadNotifications(refresh: true);
      _updateReadStatus();
    } catch (e) {
      debugPrint('⚠️ Lỗi lấy residentId/buildingId: $e');
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _updateReadStatus() async {
    if (_residentId == null || _residentId!.isEmpty) {
      debugPrint(
          '⚠️ [NotificationScreen] Cannot update read status: residentId is null');
      return;
    }

    // Reload read IDs from local storage to ensure we have the latest data
    _readIds = await NotificationReadStore.load(_residentId!);

    final notifications =
        List<ResidentNotification>.from(_viewModel.notifications);
    bool updated = false;
    for (var i = 0; i < notifications.length; i++) {
      if (_readIds.contains(notifications[i].id) && !notifications[i].isRead) {
        notifications[i] = notifications[i].copyWith(isRead: true);
        updated = true;
      }
    }
    if (updated) {
      _viewModel.updateNotifications(notifications);
      debugPrint(
          '✅ [NotificationScreen] Updated read status for ${notifications.where((n) => _readIds.contains(n.id)).length} notifications');
    }
  }

  Future<void> _tryPopulateFromUnits() async {
    try {
      final units = await _contractService.getMyUnits();
      if (units.isEmpty) {
        return;
      }

      for (final unit in units) {
        final candidateResidentId = unit.primaryResidentId?.toString();
        final candidateBuildingId = unit.buildingId?.toString();

        if ((_residentId == null || _residentId!.isEmpty) &&
            candidateResidentId != null &&
            candidateResidentId.isNotEmpty) {
          _residentId = candidateResidentId;
        }

        if ((_buildingId == null || _buildingId!.isEmpty) &&
            candidateBuildingId != null &&
            candidateBuildingId.isNotEmpty) {
          _buildingId = candidateBuildingId;
        }

        if ((_residentId?.isNotEmpty ?? false) &&
            (_buildingId?.isNotEmpty ?? false)) {
          break;
        }
      }

      if ((_buildingId == null || _buildingId!.isEmpty)) {
        final fallback = units.firstWhere(
          (unit) => (unit.buildingId ?? '').isNotEmpty,
          orElse: () => units.first,
        );
        if ((fallback.buildingId ?? '').isNotEmpty) {
          _buildingId = fallback.buildingId;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi lấy dữ liệu căn hộ: $e');
    }
  }

  void _handleIncomingRealtime(Map<String, dynamic> payload) {
    if (_residentId == null || _buildingId == null) {
      return;
    }

    if (!_shouldAcceptRealtimeNotification(payload)) {
      return;
    }

    final notification = _parseRealtimeNotification(payload);
    if (notification == null) return;

    final notifications =
        List<ResidentNotification>.from(_viewModel.notifications);
    final alreadyExists =
        notifications.any((element) => element.id == notification.id);
    if (alreadyExists) return;

    notifications.insert(0, notification);
    _viewModel.updateNotifications(notifications);
  }

  bool _shouldAcceptRealtimeNotification(Map<String, dynamic> payload) {
    final scope = (payload['scope'] ??
            payload['notificationScope'] ??
            payload['notification_scope'])
        ?.toString()
        .toUpperCase();
    final targetBuildingId =
        payload['targetBuildingId']?.toString().toLowerCase();

    if (scope == 'EXTERNAL' || scope == null) {
      if (targetBuildingId == null || targetBuildingId.isEmpty) {
        return true;
      }
      if (_buildingId == null) return false;
      return targetBuildingId == _buildingId!.toLowerCase();
    }
    return false;
  }

  ResidentNotification? _parseRealtimeNotification(
      Map<String, dynamic> payload) {
    final id =
        payload['notificationId']?.toString() ?? payload['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final createdAt = payload['createdAt']?.toString() ??
        DateTime.now().toUtc().toIso8601String();
    final updatedAt = payload['updatedAt']?.toString() ?? createdAt;

    final normalized = {
      'id': id,
      'type': (payload['notificationType'] ?? payload['type'] ?? 'SYSTEM')
          .toString(),
      'title': payload['title']?.toString() ?? 'Thông báo hệ thống',
      'message':
          payload['message']?.toString() ?? payload['body']?.toString() ?? '',
      'scope': (payload['scope'] ?? 'EXTERNAL').toString(),
      'targetRole': payload['targetRole']?.toString(),
      'targetBuildingId': payload['targetBuildingId']?.toString(),
      'referenceId': payload['referenceId']?.toString(),
      'referenceType': payload['referenceType']?.toString(),
      'actionUrl': payload['actionUrl']?.toString(),
      'iconUrl': payload['iconUrl']?.toString(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'read': false,
      'readAt': null,
    };

    try {
      return ResidentNotification.fromJson(normalized);
    } catch (e) {
      debugPrint('⚠️ Không thể parse realtime notification: $e');
      return null;
    }
  }

  void _handleNotificationMarkedRead(String notificationId) {
    final notifications =
        List<ResidentNotification>.from(_viewModel.notifications);
    final index =
        notifications.indexWhere((element) => element.id == notificationId);
    if (index == -1) return;
    final alreadyRead = _readIds.contains(notificationId);
    _readIds = {..._readIds, notificationId};
    notifications[index] = notifications[index].copyWith(
      isRead: true,
      readAt: DateTime.now(),
    );
    _viewModel.updateNotifications(notifications);
    if (!alreadyRead && _residentId != null) {
      NotificationReadStore.markRead(_residentId!, notificationId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Consumer<NotificationViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            extendBody: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: AppBar(
              title: const Text('Thông báo'),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
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
                    onRefresh: () async {
                      await viewModel.loadNotifications(refresh: true);
                      await _updateReadStatus();
                    },
                    child: Column(
                      children: [
                        Expanded(child: _buildBody(context, viewModel)),
                        _buildPaginationControls(context, viewModel),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, NotificationViewModel viewModel) {
    if (viewModel.isLoading && viewModel.notifications.isEmpty) {
      return NotificationListSkeleton(controller: _scrollController);
    }

    if (viewModel.error != null && viewModel.notifications.isEmpty) {
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
              onPressed: () async {
                await viewModel.loadNotifications(refresh: true);
                await _updateReadStatus();
              },
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }

    final grouped = viewModel.groupedNotifications;

    if (grouped.isEmpty) {
      return _buildEmptyState(context);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: ListView.builder(
        key: ValueKey(viewModel.notifications.length),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: grouped.length * 2,
        itemBuilder: (context, index) {
          if (index.isOdd) {
            final groupIndex = (index - 1) ~/ 2;
            final groupKey = grouped.keys.elementAt(groupIndex);
            final notifications = grouped[groupKey]!;

            return Column(
              children: [
                for (final notification in notifications)
                  NotificationCard(
                    key: ValueKey(notification.id),
                    notification: notification,
                    residentId: _residentId,
                    onMarkedAsRead: () =>
                        _handleNotificationMarkedRead(notification.id),
                  ),
              ],
            );
          } else {
            final groupIndex = index ~/ 2;
            final groupKey = grouped.keys.elementAt(groupIndex);
            return NotificationGroupHeader(title: groupKey);
          }
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 80,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'Không có thông báo nào',
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

  Widget _buildFilterSection(
      BuildContext context, NotificationViewModel viewModel) {
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
                    key: const ValueKey('notification-filters-open'),
                    children: [
                      NotificationSearchBar(
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
                      NotificationTypeFilterWidget(
                        currentFilter: viewModel.typeFilter,
                        onFilterChanged: (filter) {
                          viewModel.setTypeFilter(filter);
                        },
                      ),
                      NotificationDateFilter(
                        dateFrom: viewModel.filterDateFrom,
                        dateTo: viewModel.filterDateTo,
                        hasActiveFilters: viewModel.hasActiveFilters,
                        onDateFilterChanged: (from, to) async {
                          viewModel.setDateFilter(from, to);
                          await viewModel.loadNotifications(refresh: true);
                          await _updateReadStatus();
                        },
                        onClearFilters: () async {
                          viewModel.clearFilters();
                          await viewModel.loadNotifications(refresh: true);
                          await _updateReadStatus();
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

  Widget _buildPaginationControls(BuildContext context, NotificationViewModel viewModel) {
    if (viewModel.totalPages <= 1) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final currentPage = viewModel.currentPage;
    final totalPages = viewModel.totalPages;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous button
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: viewModel.hasPrevious && !viewModel.isLoading
                ? () => viewModel.previousPage()
                : null,
            tooltip: 'Trang trước',
          ),
          const SizedBox(width: 8),
          
          // Page numbers - centered
          Flexible(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(totalPages, (index) {
                    final pageNumber = index;
                    final isCurrentPage = pageNumber == currentPage;
                    
                    // Show first page, last page, current page, and pages around current
                    final shouldShow = 
                        pageNumber == 0 ||
                        pageNumber == totalPages - 1 ||
                        (pageNumber >= currentPage - 1 && pageNumber <= currentPage + 1);
                    
                    if (!shouldShow) {
                      // Show ellipsis
                      if (pageNumber == currentPage - 2 || pageNumber == currentPage + 2) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '...',
                            style: theme.textTheme.bodyMedium,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: viewModel.isLoading
                            ? null
                            : () => viewModel.goToPage(pageNumber),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isCurrentPage
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${pageNumber + 1}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isCurrentPage
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                              fontWeight: isCurrentPage
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // Next button
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: viewModel.hasNext && !viewModel.isLoading
                ? () => viewModel.nextPage()
                : null,
            tooltip: 'Trang sau',
          ),
        ],
      ),
    );
  }
}
