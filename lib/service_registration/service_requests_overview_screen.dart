import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/api_client.dart';
import '../models/service_requests.dart';
import '../theme/app_colors.dart';
import 'cleaning_request_service.dart';
import 'maintenance_request_service.dart';

class ServiceRequestsOverviewScreen extends StatefulWidget {
  const ServiceRequestsOverviewScreen({super.key});

  @override
  State<ServiceRequestsOverviewScreen> createState() => _ServiceRequestsOverviewScreenState();
}

class _ServiceRequestsOverviewScreenState extends State<ServiceRequestsOverviewScreen> {
  late final ApiClient _apiClient;
  late final CleaningRequestService _cleaningService;
  late final MaintenanceRequestService _maintenanceService;

  List<CleaningRequestSummary> _cleaningRequests = const [];
  List<MaintenanceRequestSummary> _maintenanceRequests = const [];
  bool _loading = true;
  String? _error;

  final _dateFormatter = DateFormat('dd/MM/yyyy');
  final _timeFormatter = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _cleaningService = CleaningRequestService(_apiClient);
    _maintenanceService = MaintenanceRequestService(_apiClient);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cleaningFuture = _cleaningService.getMyRequests();
      final maintenanceFuture = _maintenanceService.getMyRequests();
      final cleaning = await cleaningFuture;
      final maintenance = await maintenanceFuture;
      if (!mounted) return;
      setState(() {
        _cleaningRequests = cleaning;
        _maintenanceRequests = maintenance;
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
              itemCount: _cleaningRequests.length,
              itemBuilder: (context, index) {
                final request = _cleaningRequests[index];
                final scheduleText = request.scheduledAt != null
                    ? '${_dateFormatter.format(request.scheduledAt!)} • ${_timeFormatter.format(request.scheduledAt!)}'
                    : 'Chưa xác định thời gian';
                final extra = request.extraServices.isEmpty
                    ? null
                    : 'Bao gồm: ${request.extraServices.join(', ')}';
                return _RequestCard(
                  icon: Icons.cleaning_services_outlined,
                  accent: AppColors.primaryAqua,
                  title: request.cleaningType,
                  subtitle: '$scheduleText • ${request.location}',
                  note: extra ?? request.note,
                  status: request.status,
                  createdAt: request.createdAt,
                );
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
              itemCount: _maintenanceRequests.length,
              itemBuilder: (context, index) {
                final request = _maintenanceRequests[index];
                final preferred = request.preferredDatetime != null
                    ? '${_dateFormatter.format(request.preferredDatetime!)} • ${_timeFormatter.format(request.preferredDatetime!)}'
                    : 'Chưa xác định thời gian';
                return _RequestCard(
                  icon: Icons.handyman_outlined,
                  accent: AppColors.primaryBlue,
                  title: request.title,
                  subtitle: '${request.category} • ${request.location}\n$preferred',
                  note: request.note,
                  status: request.status,
                  createdAt: request.createdAt,
                );
              },
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
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String status;
  final DateTime createdAt;
  final String? note;

  Color _statusColor(BuildContext context) {
    final normalized = status.toUpperCase();
    if (normalized.contains('APPROVED') || normalized.contains('COMPLETED')) {
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
                  color: accent.withOpacity(0.15),
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
                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColor(context).withOpacity(0.1),
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
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Tạo lúc $createdAtText',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
            ),
          ),
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
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
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
              style: theme.textTheme.titleMedium?.copyWith(color: AppColors.danger),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
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
            color: theme.colorScheme.outline.withOpacity(0.08),
          ),
          boxShadow: AppColors.subtleShadow,
        ),
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

