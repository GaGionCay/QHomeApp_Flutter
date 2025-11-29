import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/notification_detail_response.dart';
import '../news/resident_service.dart';
import '../theme/app_colors.dart';
import '../contracts/contract_service.dart';
import '../models/unit_info.dart';
import 'notification_read_store.dart';
import 'package:provider/provider.dart';
import '../auth/auth_provider.dart';

class NotificationDetailScreen extends StatefulWidget {
  final String notificationId;
  final String? residentId;
  final VoidCallback? onMarkedAsRead;

  const NotificationDetailScreen({
    super.key,
    required this.notificationId,
    this.residentId,
    this.onMarkedAsRead,
  });

  @override
  State<NotificationDetailScreen> createState() =>
      _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  final ResidentService _residentService = ResidentService();
  ContractService? _contractService;
  NotificationDetailResponse? _notification;
  bool _loading = true;
  String? _error;
  bool _isMarking = false;
  bool _marked = false;
  List<UnitInfo>? _units;

  @override
  void initState() {
    super.initState();
    _initContractService();
    _markAsRead();
    _loadNotificationDetail();
    _loadUnits();
  }

  void _initContractService() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final apiClient = authProvider.apiClient;
    _contractService = ContractService(apiClient);
  }

  Future<void> _loadUnits() async {
    final contractService = _contractService;
    if (contractService == null) return;
    try {
      final units = await contractService.getMyUnits();
      setState(() {
        _units = units;
      });
    } catch (e) {
      debugPrint('⚠️ Không thể tải danh sách căn hộ: $e');
    }
  }

  String? _getBuildingName(String? targetBuildingId) {
    if (targetBuildingId == null || _units == null) {
      return null;
    }
    
    // Try to find building name from user's units
    for (final unit in _units!) {
      final unitBuildingId = unit.buildingId?.toString().toLowerCase();
      if (unitBuildingId == targetBuildingId.toLowerCase()) {
        return unit.buildingName ?? unit.buildingCode;
      }
    }
    
    // If not found, return null (will display UUID as fallback)
    return null;
  }

  Future<void> _loadNotificationDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await _residentService
          .getNotificationDetailById(widget.notificationId);
      setState(() {
        _notification = detail;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tải chi tiết thông báo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markAsRead() async {
    if (_marked || _isMarking || widget.residentId == null) {
      return;
    }
    _isMarking = true;
    try {
      final added = await NotificationReadStore.markRead(
        widget.residentId!,
        widget.notificationId,
      );
      _marked = true;
      if (added) {
        widget.onMarkedAsRead?.call();
      }
    } catch (e) {
      debugPrint('⚠️ Không thể đánh dấu thông báo đã đọc: $e');
    } finally {
      _isMarking = false;
    }
  }

  Color _getTypeColor(String type) {
    switch (type.toUpperCase()) {
      case 'CARD_APPROVED':
        return AppColors.success;
      case 'CARD_REJECTED':
        return AppColors.danger;
      case 'CARD_PENDING':
        return AppColors.warning;
      case 'CARD_FEE_REMINDER':
        return AppColors.primaryBlue;
      case 'REQUEST':
        return AppColors.primaryEmerald;
      case 'BILL':
        return AppColors.primaryBlue;
      case 'PAYMENT':
        return AppColors.success;
      case 'ELECTRICITY':
        return AppColors.warning;
      case 'WATER':
        return const Color(0xFF2196F3);
      case 'CONTRACT':
        return AppColors.primaryEmerald;
      case 'SERVICE':
        return Colors.orange;
      case 'SYSTEM':
        return const Color(0xFF26A69A);
      case 'NEWS':
        return AppColors.primaryBlue;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'CARD_APPROVED':
        return Icons.check_circle_outline;
      case 'CARD_REJECTED':
        return Icons.cancel_outlined;
      case 'CARD_PENDING':
        return Icons.pending_outlined;
      case 'CARD_FEE_REMINDER':
        return Icons.credit_card;
      case 'REQUEST':
        return Icons.request_quote;
      case 'BILL':
        return Icons.receipt_long;
      case 'PAYMENT':
        return Icons.payment;
      case 'ELECTRICITY':
        return Icons.bolt;
      case 'WATER':
        return Icons.water_drop;
      case 'CONTRACT':
        return Icons.description;
      case 'SERVICE':
        return Icons.room_service;
      case 'SYSTEM':
        return Icons.info_outline;
      case 'NEWS':
        return Icons.newspaper;
      default:
        return Icons.notifications_outlined;
    }
  }

  String _getScopeText(NotificationDetailResponse notification) {
    // If notification has targetResidentId, it's PRIVATE (Riêng tư)
    if (notification.targetResidentId != null && notification.targetResidentId!.isNotEmpty) {
      return 'Riêng tư';
    }
    
    // Otherwise, check scope
    switch (notification.scope.toUpperCase()) {
      case 'EXTERNAL':
        // If has targetBuildingId, it's public to that building
        // If no targetBuildingId, it's public to all buildings
        return 'Công khai';
      case 'INTERNAL':
        return 'Nội bộ';
      default:
        return notification.scope;
    }
  }

  String _getTypeText(String type) {
    switch (type.toUpperCase()) {
      case 'CARD_APPROVED':
        return 'The cu dan da duyet';
      case 'CARD_REJECTED':
        return 'The cu dan bi tu choi';
      case 'CARD_PENDING':
        return 'The cu dan dang cho';
      case 'CARD_FEE_REMINDER':
        return 'Nhac nho phi the';
      case 'REQUEST':
        return 'Yeu cau';
      case 'BILL':
        return 'Hoa don';
      case 'PAYMENT':
        return 'Thanh toan';
      case 'ELECTRICITY':
        return 'Tien dien';
      case 'WATER':
        return 'Tien nuoc';
      case 'CONTRACT':
        return 'Hop dong';
      case 'SERVICE':
        return 'Dich vu';
      case 'SYSTEM':
        return 'He thong';
      case 'NEWS':
        return 'Tin tuc';
      default:
        // Fallback: convert to Vietnamese without accents and replace underscores
        return type
            .toUpperCase()
            .replaceAll('_', ' ')
            .toLowerCase()
            .replaceAll(' ', '');
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Chưa có';
    try {
      return DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
    } catch (_) {
      return 'Không hợp lệ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF04101F),
              Color(0xFF0A1D34),
              Color(0xFF071225),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEFF6FF),
              Color(0xFFF8FBFF),
              Colors.white,
            ],
          );

    if (_loading) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: theme.colorScheme.onSurface,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: theme.appBarTheme.systemOverlayStyle,
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: backgroundGradient),
          ),
          title: const Text('Chi tiết thông báo'),
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: backgroundGradient),
          child: const Center(
            child: CupertinoActivityIndicator(radius: 16),
          ),
        ),
      );
    }

    if (_error != null || _notification == null) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: theme.colorScheme.onSurface,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: theme.appBarTheme.systemOverlayStyle,
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: backgroundGradient),
          ),
          title: const Text('Chi tiết thông báo'),
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: backgroundGradient),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Không tìm thấy thông báo',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loadNotificationDetail,
                    child: const Text('Thử lại'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final notification = _notification!;
    final typeColor = _getTypeColor(notification.type);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: theme.colorScheme.onSurface,
              elevation: 0,
              scrolledUnderElevation: 0,
              pinned: true,
              stretch: true,
              leadingWidth: 66,
              expandedHeight: 160,
              title: const Text(
                'Chi tiết thông báo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              centerTitle: true,
              leading: Padding(
                padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
                child: _buildFrostedIconButton(
                  icon: CupertinoIcons.chevron_left,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: Container(
                  padding: const EdgeInsets.fromLTRB(24, 100, 24, 36),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      notification.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            letterSpacing: -0.3,
                          ) ??
                          TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            letterSpacing: -0.3,
                          ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _glassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 
                                      isDark ? 0.28 : 0.16),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _getTypeIcon(notification.type),
                                  size: 24,
                                  color: typeColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildStatusChip(
                                      context,
                                      _getTypeText(notification.type),
                                      typeColor,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildStatusChip(
                                      context,
                                      _getScopeText(notification),
                                      theme.colorScheme.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            notification.message.isNotEmpty
                                ? notification.message
                                : 'Không có nội dung cho thông báo này.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                                  height: 1.6,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.82)
                                      : AppColors.textPrimary,
                                ) ??
                                TextStyle(
                                  height: 1.6,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.82)
                                      : AppColors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: 20),
                          _buildMetaRow(
                            icon: CupertinoIcons.time,
                            label: 'Thời gian tạo',
                            value: _formatDate(notification.createdAt),
                          ),
                          if (notification.targetBuildingId != null) ...[
                            const SizedBox(height: 16),
                            _buildMetaRow(
                              icon: CupertinoIcons.building_2_fill,
                              label: 'Tòa nhà',
                              value: _getBuildingName(notification.targetBuildingId) ?? 
                                     notification.targetBuildingId!,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (notification.actionUrl != null) ...[
                      const SizedBox(height: 20),
                      _glassPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Liên kết',
                              style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ) ??
                                  TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            _buildActionUrlRow(
                              theme,
                              notification.actionUrl!,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(24),
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gradient = isDark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();
    final borderColor = (isDark ? AppColors.navyOutline : AppColors.neutralOutline)
        .withValues(alpha: 0.45);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(
      BuildContext context, String status, Color color) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.28 : 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.6 : 0.4),
        ),
      ),
      child: Text(
        status,
        style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
              fontSize: 11,
            ) ??
            TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
              fontSize: 11,
            ),
      ),
    );
  }

  Widget _buildMetaRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : AppColors.textSecondary,
              ) ??
              TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : AppColors.textSecondary,
              ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ) ??
                TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionUrlRow(ThemeData theme, String url) {
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: () => _launchUrl(url),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.link,
              size: 20,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                url,
                style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ) ??
                    TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.open_in_new,
              size: 16,
              color: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    try {
      String url = urlString;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://$url';
      }

      final Uri uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể mở URL này'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi mở URL: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildFrostedIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.75),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                icon,
                size: 20,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
