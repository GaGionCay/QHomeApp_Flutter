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
      if (mounted) {
        setState(() => _loadingMoreCleaning = false);
      }
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
      if (mounted) {
        setState(() => _loadingMoreMaintenance = false);
      }
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
                    onCancel: canCancel
                        ? () => _cancelMaintenanceRequest(request.id)
                        : null,
                  isCanceling: _cancellingRequestIds.contains(request.id),
                    onResend: canResend
                        ? () => _resendMaintenanceRequest(request.id)
                        : null,
                    isResending: _resendingMaintenanceRequestIds.contains(request.id),
                    onCall: canCall
                        ? () => _callAdmin(adminPhone)
                        : null,
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
    return _HomeGlassContainer(
      child: Column(
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
          if (onResend != null || onCall != null || onCancel != null) ...[
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
      ),
    );
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
