import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../auth/api_client.dart';
import '../core/event_bus.dart';
import '../models/service_requests.dart';
import '../theme/app_colors.dart';
import 'cleaning_request_service.dart';
import 'maintenance_request_service.dart';

class ServiceRequestsOverviewScreen extends StatefulWidget {
  const ServiceRequestsOverviewScreen({super.key});

  @override
  State<ServiceRequestsOverviewScreen> createState() =>
      _ServiceRequestsOverviewScreenState();
}

class _ServiceRequestsOverviewScreenState
    extends State<ServiceRequestsOverviewScreen> {
  late final ApiClient _apiClient;
  late final CleaningRequestService _cleaningService;
  late final MaintenanceRequestService _maintenanceService;
  late final AppEventBus _eventBus;

  List<CleaningRequestSummary> _cleaningRequests = const [];
  List<MaintenanceRequestSummary> _maintenanceRequests = const [];
  bool _loading = true;
  String? _error;
  int? _cleaningTotal;
  int? _maintenanceTotal;
  bool _loadingMoreCleaning = false;
  bool _loadingMoreMaintenance = false;

  final _dateFormatter = DateFormat('dd/MM/yyyy');
  final _timeFormatter = DateFormat('HH:mm');
  final Set<String> _cancellingRequestIds = {};
  final Set<String> _resendingRequestIds = {};
  final Set<String> _resendingMaintenanceRequestIds = {};
  final Set<String> _approvingResponseIds = {};
  final Set<String> _rejectingResponseIds = {};
  Timer? _cleaningRequestRefreshTimer;
  MaintenanceRequestConfig? _maintenanceConfig;
  static const int _pageSize = 6;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _cleaningService = CleaningRequestService(_apiClient);
    _maintenanceService = MaintenanceRequestService(_apiClient);
    _eventBus = AppEventBus();
    _loadData();
    _loadMaintenanceConfig();
    _setupNotificationListeners();
    _schedulePeriodicRefresh();
  }

  void _setupNotificationListeners() {
    _eventBus.on('notifications_update', (_) async {
      await _loadData();
    });
    _eventBus.on('notifications_incoming', (_) {
      unawaited(_loadData());
    });
  }

  void _schedulePeriodicRefresh() {
    // Refresh every 1 minute to check for resendAlertSent updates
    _cleaningRequestRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        unawaited(_loadData());
      },
    );
  }

  Future<void> _loadMaintenanceConfig() async {
    try {
      final config = await _maintenanceService.getConfig();
      if (mounted) {
        setState(() {
          _maintenanceConfig = config;
        });
      }
    } catch (e) {
      // Use default config on error
      if (mounted) {
        setState(() {
          _maintenanceConfig = MaintenanceRequestConfig.defaultConfig();
        });
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
      _cleaningRequests = [];
      _maintenanceRequests = [];
      _cleaningTotal = null;
      _maintenanceTotal = null;
      _loadingMoreCleaning = false;
      _loadingMoreMaintenance = false;
    });

    try {
      final cleaningFuture = _cleaningService.getMyRequests(
        limit: _pageSize,
        offset: 0,
      );
      final maintenanceFuture = _maintenanceService.getMyRequests(
        limit: _pageSize,
        offset: 0,
      );
      final cleaningPage = await cleaningFuture;
      final maintenancePage = await maintenanceFuture;
      if (!mounted) return;
      setState(() {
        _cleaningRequests = cleaningPage.requests;
        _maintenanceRequests = maintenancePage.requests;
        _cleaningTotal = cleaningPage.total;
        _maintenanceTotal = maintenancePage.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMoreCleaningRequests() async {
    if (_loadingMoreCleaning || !_hasMoreCleaningRequests) return;
    setState(() => _loadingMoreCleaning = true);
    try {
      final nextOffset = _cleaningRequests.length;
      final page = await _cleaningService.getMyRequests(
        limit: _pageSize,
        offset: nextOffset,
      );
      if (!mounted) return;
      setState(() {
        _cleaningRequests = [..._cleaningRequests, ...page.requests];
        _cleaningTotal = page.total;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể tải thêm yêu cầu dọn dẹp: $e'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loadingMoreCleaning = false);
    }
  }

  Future<void> _loadMoreMaintenanceRequests() async {
    if (_loadingMoreMaintenance || !_hasMoreMaintenanceRequests) return;
    setState(() => _loadingMoreMaintenance = true);
    try {
      final nextOffset = _maintenanceRequests.length;
      final page = await _maintenanceService.getMyRequests(
        limit: _pageSize,
        offset: nextOffset,
      );
      if (!mounted) return;
      setState(() {
        _maintenanceRequests = [..._maintenanceRequests, ...page.requests];
        _maintenanceTotal = page.total;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể tải thêm yêu cầu sửa chữa: $e'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loadingMoreMaintenance = false);
    }
  }

  bool _isCancelable(String status) {
    final normalized = status.toUpperCase();
    return normalized.contains('PENDING') ||
        normalized.contains('IN_PROGRESS') ||
        normalized.contains('PROCESSING');
  }

  Future<void> _cancelCleaningRequest(String requestId) async {
    if (_cancellingRequestIds.contains(requestId)) return;
    setState(() => _cancellingRequestIds.add(requestId));
    try {
      await _cleaningService.cancelRequest(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hủy yêu cầu dọn dẹp.'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể hủy yêu cầu dọn dẹp: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cancellingRequestIds.remove(requestId));
      }
    }
  }

  Future<void> _cancelMaintenanceRequest(String requestId) async {
    if (_cancellingRequestIds.contains(requestId)) return;
    setState(() => _cancellingRequestIds.add(requestId));
    try {
      await _maintenanceService.cancelRequest(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hủy yêu cầu sửa chữa.'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể hủy yêu cầu sửa chữa: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cancellingRequestIds.remove(requestId));
      }
    }
  }

  bool _shouldShowResendButton(CleaningRequestSummary request) {
    final normalizedStatus = request.status.toUpperCase();
    if (!normalizedStatus.contains('PENDING')) return false;
    if (request.resendAlertSent != true) return false;
    return true;
  }

  bool _shouldShowResendButtonMaintenance(MaintenanceRequestSummary request) {
    final normalizedStatus = request.status.toUpperCase();
    if (!normalizedStatus.contains('PENDING')) return false;
    if (request.resendAlertSent != true) return false;
    if (request.callAlertSent == true) return false; // Show call button instead
    return true;
  }

  bool _shouldShowCallButtonMaintenance(MaintenanceRequestSummary request) {
    final normalizedStatus = request.status.toUpperCase();
    if (!normalizedStatus.contains('PENDING')) return false;
    if (request.callAlertSent != true) return false;
    return true;
  }

  Future<void> _resendCleaningRequest(String requestId) async {
    if (_resendingRequestIds.contains(requestId)) return;
    setState(() => _resendingRequestIds.add(requestId));
    try {
      await _cleaningService.resendRequest(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yêu cầu dọn dẹp đã được gửi lại.'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể gửi lại yêu cầu dọn dẹp: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _resendingRequestIds.remove(requestId));
      }
    }
  }

  Future<void> _resendMaintenanceRequest(String requestId) async {
    if (_resendingMaintenanceRequestIds.contains(requestId)) return;
    setState(() => _resendingMaintenanceRequestIds.add(requestId));
    try {
      await _maintenanceService.resendRequest(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yêu cầu sửa chữa đã được gửi lại.'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể gửi lại yêu cầu sửa chữa: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _resendingMaintenanceRequestIds.remove(requestId));
      }
    }
  }

  Future<void> _approveMaintenanceResponse(String requestId) async {
    if (_approvingResponseIds.contains(requestId)) return;
    setState(() => _approvingResponseIds.add(requestId));
    try {
      await _maintenanceService.approveResponse(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã xác nhận phản hồi từ admin. Yêu cầu đang được xử lý.'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể xác nhận phản hồi: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _approvingResponseIds.remove(requestId));
      }
    }
  }

  Future<void> _rejectMaintenanceResponse(String requestId) async {
    if (_rejectingResponseIds.contains(requestId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận từ chối'),
        content: const Text('Bạn có chắc chắn muốn từ chối phản hồi từ admin? Yêu cầu sẽ bị hủy.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('Từ chối'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    
    setState(() => _rejectingResponseIds.add(requestId));
    try {
      await _maintenanceService.rejectResponse(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã từ chối phản hồi từ admin. Yêu cầu đã được hủy.'),
          backgroundColor: AppColors.danger,
        ),
      );
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể từ chối phản hồi: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _rejectingResponseIds.remove(requestId));
      }
    }
  }

  void _showMaintenanceRequestDetail(
      BuildContext context, MaintenanceRequestSummary request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {},
                  child: _MaintenanceRequestDetailSheet(
                    request: request,
                    onRefresh: _loadData,
                    onApproveResponse: request.hasPendingResponse
                        ? () => _approveMaintenanceResponse(request.id)
                        : null,
                    onRejectResponse: request.hasPendingResponse
                        ? () => _rejectMaintenanceResponse(request.id)
                        : null,
                    onCancel: _isCancelable(request.status) && !request.hasPendingResponse
                        ? () => _cancelMaintenanceRequest(request.id)
                        : null,
                    isApprovingResponse: _approvingResponseIds.contains(request.id),
                    isRejectingResponse: _rejectingResponseIds.contains(request.id),
                    isCanceling: _cancellingRequestIds.contains(request.id),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _callAdmin(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể gọi số điện thoại: $phoneNumber'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _cleaningRequestRefreshTimer?.cancel();
    super.dispose();
  }

  bool get _hasMoreCleaningRequests =>
      _cleaningTotal != null && _cleaningRequests.length < _cleaningTotal!;

  bool get _hasMoreMaintenanceRequests =>
      _maintenanceTotal != null &&
      _maintenanceRequests.length < _maintenanceTotal!;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Yêu cầu dịch vụ'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Dọn dẹp'),
              Tab(text: 'Sửa chữa'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(
                    message: _error!,
                    onRetry: _loadData,
                  )
                : TabBarView(
                    children: [
                      _buildCleaningTab(),
                      _buildMaintenanceTab(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildCleaningTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _cleaningRequests.isEmpty
          ? const _EmptyState(
              icon: Icons.cleaning_services_outlined,
              message: 'Bạn chưa có yêu cầu dọn dẹp nào.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount:
                  _cleaningRequests.length + (_hasMoreCleaningRequests ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < _cleaningRequests.length) {
                final request = _cleaningRequests[index];
                final scheduleText = request.scheduledAt != null
                    ? '${_dateFormatter.format(request.scheduledAt!)} • ${_timeFormatter.format(request.scheduledAt!)}'
                    : 'Chưa xác định thời gian';
                final extra = request.extraServices.isEmpty
                    ? null
                    : 'Bao gồm: ${request.extraServices.join(', ')}';
                final canCancel = _isCancelable(request.status);
                  final canResend = _shouldShowResendButton(request);
                return _RequestCard(
                  icon: Icons.cleaning_services_outlined,
                  accent: AppColors.primaryAqua,
                  title: request.cleaningType,
                  subtitle: '$scheduleText • ${request.location}',
                  note: extra ?? request.note,
                  status: request.status,
                  createdAt: request.createdAt,
                    lastResentAt: request.lastResentAt,
                    onCancel: canCancel
                        ? () => _cancelCleaningRequest(request.id)
                        : null,
                  isCanceling: _cancellingRequestIds.contains(request.id),
                    onResend: canResend
                        ? () => _resendCleaningRequest(request.id)
                        : null,
                    isResending: _resendingRequestIds.contains(request.id),
                );
                }
                return _buildLoadMoreTile(isCleaning: true);
              },
            ),
    );
  }

  Widget _buildMaintenanceTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _maintenanceRequests.isEmpty
          ? const _EmptyState(
              icon: Icons.build_outlined,
              message: 'Bạn chưa có yêu cầu sửa chữa nào.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: _maintenanceRequests.length +
                  (_hasMoreMaintenanceRequests ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < _maintenanceRequests.length) {
                final request = _maintenanceRequests[index];
                final preferred = request.preferredDatetime != null
                    ? '${_dateFormatter.format(request.preferredDatetime!)} • ${_timeFormatter.format(request.preferredDatetime!)}'
                    : 'Chưa xác định thời gian';
                final canCancel = _isCancelable(request.status);
                final canResend = _shouldShowResendButtonMaintenance(request);
                final canCall = _shouldShowCallButtonMaintenance(request);
                final adminPhone = _maintenanceConfig?.adminPhone ?? '0984000036';
                final hasPendingResponse = request.hasPendingResponse;
                return _RequestCard(
                  icon: Icons.handyman_outlined,
                  accent: AppColors.primaryBlue,
                  title: request.title,
                    subtitle:
                        '${request.category} • ${request.location}\n$preferred',
                  note: request.note,
                  status: request.status,
                  createdAt: request.createdAt,
                    lastResentAt: request.lastResentAt,
                    onCancel: canCancel && !hasPendingResponse
                        ? () => _cancelMaintenanceRequest(request.id)
                        : null,
                  isCanceling: _cancellingRequestIds.contains(request.id),
                    onResend: canResend && !hasPendingResponse
                        ? () => _resendMaintenanceRequest(request.id)
                        : null,
                    isResending: _resendingMaintenanceRequestIds.contains(request.id),
                    onCall: canCall && !hasPendingResponse
                        ? () => _callAdmin(adminPhone)
                        : null,
                  adminResponse: request.adminResponse,
                  estimatedCost: request.estimatedCost,
                  respondedAt: request.respondedAt,
                  hasPendingResponse: hasPendingResponse,
                  onApproveResponse: hasPendingResponse
                      ? () => _approveMaintenanceResponse(request.id)
                      : null,
                  onRejectResponse: hasPendingResponse
                      ? () => _rejectMaintenanceResponse(request.id)
                      : null,
                  isApprovingResponse: _approvingResponseIds.contains(request.id),
                  isRejectingResponse: _rejectingResponseIds.contains(request.id),
                  onTap: () => _showMaintenanceRequestDetail(context, request),
                );
                }
                return _buildLoadMoreTile(isCleaning: false);
              },
            ),
    );
  }

  Widget _buildLoadMoreTile({required bool isCleaning}) {
    final isLoading =
        isCleaning ? _loadingMoreCleaning : _loadingMoreMaintenance;
    final label =
        isCleaning ? 'Xem thêm yêu cầu dọn dẹp' : 'Xem thêm yêu cầu sửa chữa';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: FilledButton.icon(
          onPressed: isLoading
              ? null
              : () => isCleaning
                  ? _loadMoreCleaningRequests()
                  : _loadMoreMaintenanceRequests(),
          icon: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.more_horiz),
          label: Text(isLoading ? 'Đang tải...' : label),
        ),
            ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.createdAt,
    this.note,
    this.lastResentAt,
    this.onCancel,
    this.isCanceling = false,
    this.onResend,
    this.isResending = false,
    this.onCall,
    this.adminResponse,
    this.estimatedCost,
    this.respondedAt,
    this.hasPendingResponse = false,
    this.onApproveResponse,
    this.onRejectResponse,
    this.isApprovingResponse = false,
    this.isRejectingResponse = false,
    this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String status;
  final DateTime createdAt;
  final String? note;
  final DateTime? lastResentAt;
  final VoidCallback? onCancel;
  final bool isCanceling;
  final VoidCallback? onResend;
  final bool isResending;
  final VoidCallback? onCall;
  final String? adminResponse;
  final double? estimatedCost;
  final DateTime? respondedAt;
  final bool hasPendingResponse;
  final VoidCallback? onApproveResponse;
  final VoidCallback? onRejectResponse;
  final bool isApprovingResponse;
  final bool isRejectingResponse;
  final VoidCallback? onTap;

  Color _statusColor(BuildContext context) {
    final normalized = status.toUpperCase();
    if (normalized.contains('APPROVED') ||
        normalized.contains('COMPLETED') ||
        normalized.contains('DONE')) {
      return AppColors.success;
    }
    if (normalized.contains('PENDING') ||
        normalized.contains('PROCESSING') ||
        normalized.contains('IN_PROGRESS')) {
      return AppColors.primaryBlue;
    }
    if (normalized.contains('CANCEL') || normalized.contains('REJECT')) {
      return AppColors.danger;
    }
    return Theme.of(context).colorScheme.outline;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAtText = DateFormat('dd/MM/yyyy HH:mm').format(createdAt);
    final cardContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColor(context).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _friendlyStatus(status),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _statusColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        if (note != null && note!.isNotEmpty) ...[
            Text(
              note!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (hasPendingResponse && adminResponse != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppColors.primaryBlue,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Phản hồi từ admin',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (respondedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Ngày phản hồi: ${DateFormat('dd/MM/yyyy HH:mm').format(respondedAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    adminResponse!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.9),
                    ),
                  ),
                  if (estimatedCost != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Chi phí ước tính: ${NumberFormat.currency(locale: 'vi_VN', symbol: '').format(estimatedCost).replaceAll(',', '.')} VNĐ',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
            'Tạo lúc $createdAtText',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
          ),
        ),
        if (lastResentAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Gửi lại lúc: ${DateFormat('dd/MM/yyyy HH:mm').format(lastResentAt!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
              ),
          ),
        ],
        if (hasPendingResponse && (onApproveResponse != null || onRejectResponse != null)) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onApproveResponse != null)
                  FilledButton.icon(
                    onPressed: (isApprovingResponse || isRejectingResponse) ? null : onApproveResponse,
                    icon: isApprovingResponse
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      isApprovingResponse ? 'Đang xác nhận...' : 'Xác nhận',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                  ),
                if (onRejectResponse != null)
                  OutlinedButton.icon(
                    onPressed: (isApprovingResponse || isRejectingResponse) ? null : onRejectResponse,
                    icon: isRejectingResponse
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cancel_outlined, size: 18),
                    label: Text(
                      isRejectingResponse ? 'Đang từ chối...' : 'Từ chối',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: BorderSide(color: AppColors.danger),
                    ),
                  ),
              ],
            ),
        ],
        if (!hasPendingResponse && (onResend != null || onCall != null || onCancel != null)) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onCall != null)
                  FilledButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.phone, size: 18),
                    label: const Text('Gọi ADMIN'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                  ),
                if (onResend != null)
                  FilledButton.icon(
                    onPressed: isResending ? null : onResend,
                    icon: isResending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(
                      isResending ? 'Đang gửi lại...' : 'Gửi lại',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryAqua,
                    ),
                  ),
                if (onCancel != null)
                  TextButton.icon(
                onPressed: isCanceling ? null : onCancel,
                icon: isCanceling
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cancel_outlined, size: 18),
                    label: Text(isCanceling ? 'Đang hủy...' : 'Hủy'),
              ),
              ],
            ),
        ],
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: _HomeGlassContainer(child: cardContent),
      );
    }

    return _HomeGlassContainer(child: cardContent);
  }

  String _friendlyStatus(String raw) {
    switch (raw.toUpperCase()) {
      case 'PENDING':
        return 'Chờ xử lý';
      case 'APPROVED':
        return 'Đã duyệt';
      case 'IN_PROGRESS':
      case 'PROCESSING':
        return 'Đang xử lý';
      case 'COMPLETED':
      case 'DONE':
        return 'Hoàn tất';
      case 'CANCELLED':
        return 'Đã hủy';
      case 'REJECTED':
        return 'Từ chối';
      default:
        return raw;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.35,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: theme.colorScheme.outline),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(
              'Không thể tải dữ liệu',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: AppColors.danger),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceRequestDetailSheet extends StatelessWidget {
  _MaintenanceRequestDetailSheet({
    required this.request,
    required this.onRefresh,
    this.onApproveResponse,
    this.onRejectResponse,
    this.onCancel,
    this.isApprovingResponse = false,
    this.isRejectingResponse = false,
    this.isCanceling = false,
  });

  final MaintenanceRequestSummary request;
  final VoidCallback onRefresh;
  final VoidCallback? onApproveResponse;
  final VoidCallback? onRejectResponse;
  final VoidCallback? onCancel;
  final bool isApprovingResponse;
  final bool isRejectingResponse;
  final bool isCanceling;

  late final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
  late final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');
  late final DateFormat _timeFmt = DateFormat('HH:mm');

  Color _statusColor(BuildContext context) {
    final normalized = request.status.toUpperCase();
    if (normalized.contains('APPROVED') ||
        normalized.contains('COMPLETED') ||
        normalized.contains('DONE')) {
      return AppColors.success;
    }
    if (normalized.contains('PENDING') ||
        normalized.contains('PROCESSING') ||
        normalized.contains('IN_PROGRESS')) {
      return AppColors.primaryBlue;
    }
    if (normalized.contains('CANCEL') || normalized.contains('REJECT')) {
      return AppColors.danger;
    }
    return Theme.of(context).colorScheme.outline;
  }

  String _friendlyStatus(String status) {
    final normalized = status.toUpperCase();
    if (normalized.contains('PENDING')) return 'Chờ xử lý';
    if (normalized.contains('IN_PROGRESS')) return 'Đang xử lý';
    if (normalized.contains('DONE') || normalized.contains('COMPLETED')) return 'Hoàn thành';
    if (normalized.contains('CANCEL')) return 'Đã hủy';
    if (normalized.contains('REJECT')) return 'Bị từ chối';
    return status;
  }

  Widget _buildDetailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPendingResponse = request.hasPendingResponse;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  // Title
                  Text(
                    request.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _statusColor(context).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _friendlyStatus(request.status),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _statusColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Details
                  _buildDetailRow(theme, 'Mã yêu cầu', request.id),
                  _buildDetailRow(theme, 'Danh mục', request.category),
                  _buildDetailRow(theme, 'Vị trí', request.location),
                  if (request.preferredDatetime != null)
                    _buildDetailRow(
                      theme,
                      'Thời gian mong muốn',
                      '${_dateFmt.format(request.preferredDatetime!)} • ${_timeFmt.format(request.preferredDatetime!)}',
                    ),
                  _buildDetailRow(
                    theme,
                    'Ngày tạo',
                    _dateTimeFmt.format(request.createdAt.toLocal()),
                  ),
                  if (request.lastResentAt != null)
                    _buildDetailRow(
                      theme,
                      'Gửi lại lúc',
                      _dateTimeFmt.format(request.lastResentAt!.toLocal()),
                    ),

                  // Admin Response Section
                  if (request.adminResponse != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primaryBlue.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 20,
                                color: AppColors.primaryBlue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Phản hồi từ admin',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (request.respondedAt != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Ngày phản hồi: ${_dateTimeFmt.format(request.respondedAt!.toLocal())}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            request.adminResponse!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                            ),
                          ),
                          if (request.estimatedCost != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primaryBlue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.attach_money,
                                    size: 20,
                                    color: AppColors.primaryBlue,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Chi phí ước tính: ${NumberFormat.currency(locale: 'vi_VN', symbol: '').format(request.estimatedCost).replaceAll(',', '.')} VNĐ',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: AppColors.primaryBlue,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  if (request.note != null && request.note!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildDetailRow(theme, 'Ghi chú', request.note!),
                  ],

                  const SizedBox(height: 24),

                  // Action buttons
                  if (hasPendingResponse && (onApproveResponse != null || onRejectResponse != null)) ...[
                    if (onApproveResponse != null)
                      FilledButton.icon(
                        onPressed: (isApprovingResponse || isRejectingResponse) ? null : onApproveResponse,
                        icon: isApprovingResponse
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          isApprovingResponse ? 'Đang xác nhận...' : 'Xác nhận phản hồi',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: AppColors.success,
                        ),
                      ),
                    if (onApproveResponse != null && onRejectResponse != null)
                      const SizedBox(height: 12),
                    if (onRejectResponse != null)
                      OutlinedButton.icon(
                        onPressed: (isApprovingResponse || isRejectingResponse) ? null : onRejectResponse,
                        icon: isRejectingResponse
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cancel_outlined),
                        label: Text(
                          isRejectingResponse ? 'Đang từ chối...' : 'Từ chối phản hồi',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                      ),
                    if (onRejectResponse != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 20,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Nếu bạn từ chối phản hồi, yêu cầu sẽ bị hủy và không thể tiếp tục xử lý.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],

                  if (onCancel != null && !hasPendingResponse) ...[
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: isCanceling ? null : onCancel,
                      icon: isCanceling
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cancel_outlined, color: Colors.red),
                      label: Text(
                        isCanceling ? 'Đang hủy...' : 'Hủy yêu cầu',
                        style: const TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 20,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Sau khi hủy, yêu cầu này sẽ không thể tiếp tục xử lý.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeGlassContainer extends StatelessWidget {
  const _HomeGlassContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(22);
    final gradient = theme.brightness == Brightness.dark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: borderRadius,
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.08),
          ),
          boxShadow: AppColors.subtleShadow,
        ),
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}
