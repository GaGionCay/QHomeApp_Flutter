import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/notification_detail_response.dart';
import '../news/resident_service.dart';
import '../theme/app_colors.dart';
import 'notification_read_store.dart';

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
  NotificationDetailResponse? _notification;
  bool _loading = true;
  String? _error;
  bool _isMarking = false;
  bool _marked = false;

  @override
  void initState() {
    super.initState();
    _markAsRead();
    _loadNotificationDetail();
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
      case 'SYSTEM':
        return const Color(0xFF26A69A);
      case 'PAYMENT':
        return Colors.blue;
      case 'SERVICE':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'SYSTEM':
        return Icons.info_outline;
      case 'PAYMENT':
        return Icons.payment;
      case 'SERVICE':
        return Icons.room_service;
      default:
        return Icons.notifications_outlined;
    }
  }

  String _getScopeText(String scope) {
    switch (scope.toUpperCase()) {
      case 'EXTERNAL':
        return 'Công khai';
      case 'INTERNAL':
        return 'Nội bộ';
      default:
        return scope;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Chi tiết thông báo'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                )
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'Lỗi: $_error',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loadNotificationDetail,
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    )
                  : _notification == null
                      ? Center(
                          child: Text(
                            'Không tìm thấy thông báo',
                            style: theme.textTheme.titleMedium,
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final media = MediaQuery.of(context);
                            final availableWidth = constraints.maxWidth;
                            final availableHeight = constraints.maxHeight;

                            double targetWidth = availableWidth;
                            if (availableWidth > 860) {
                              targetWidth = availableWidth * 0.72;
                            }
                            if (targetWidth > 980) {
                              targetWidth = 980;
                            }

                            double horizontalPadding =
                                (availableWidth - targetWidth) / 2;
                            if (horizontalPadding < 20) {
                              horizontalPadding = 20;
                              targetWidth =
                                  availableWidth - horizontalPadding * 2;
                            }

                            final bottomPadding =
                                32 + media.padding.bottom.clamp(0.0, 40.0);

                            return SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(
                                horizontalPadding,
                                24,
                                horizontalPadding,
                                bottomPadding,
                              ),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: targetWidth,
                                    minWidth: targetWidth,
                                    minHeight:
                                        (availableHeight - bottomPadding - 24)
                                            .clamp(0.0, double.infinity),
                                  ),
                                  child: IntrinsicHeight(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildHeaderCard(theme),
                                        const SizedBox(height: 20),
                                        _buildMessageCard(theme),
                                        const SizedBox(height: 20),
                                        Expanded(
                                          child: _buildInfoCard(theme),
                                        ),
                                        const SizedBox(height: 24),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme) {
    final notification = _notification!;
    final colorScheme = theme.colorScheme;
    final typeColor = _getTypeColor(notification.type);

    return _DetailGlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _getTypeIcon(notification.type),
              color: typeColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildChip(
                      label: notification.type,
                      background: typeColor.withValues(alpha: 0.14),
                      textColor: typeColor,
                    ),
                    _buildChip(
                      label: _getScopeText(notification.scope),
                      background: colorScheme.primary.withValues(alpha: 0.1),
                      textColor: colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return _DetailGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nội dung',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _notification!.message,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              color: colorScheme.onSurface.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return _DetailGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thông tin',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          _buildInfoRow(
            theme,
            'Thời gian tạo',
            DateFormat('dd/MM/yyyy HH:mm').format(_notification!.createdAt),
            Icons.access_time,
          ),
          if (_notification!.targetBuildingId != null) ...[
            const SizedBox(height: 16),
            _buildInfoRow(
              theme,
              'Tòa nhà',
              _notification!.targetBuildingId!,
              Icons.business,
            ),
          ],
          if (_notification!.actionUrl != null) ...[
            const SizedBox(height: 16),
            _buildActionUrlRow(
              theme,
              'URL hành động',
              _notification!.actionUrl!,
              Icons.link,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
  ) {
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionUrlRow(
    ThemeData theme,
    String label,
    String url,
    IconData icon,
  ) {
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: () => _launchUrl(url),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          url,
                          style: theme.textTheme.bodyMedium?.copyWith(
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    try {
      // Nếu URL không có protocol, thêm http://
      String url = urlString;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://$url';
      }

      final Uri uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode:
              LaunchMode.externalApplication, // Mở trong trình duyệt bên ngoài
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

  Widget _buildChip({
    required String label,
    required Color background,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _DetailGlassCard extends StatelessWidget {
  const _DetailGlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppColors.darkGlassLayerGradient()
                : AppColors.glassLayerGradient(),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.08),
            ),
            boxShadow: AppColors.subtleShadow,
          ),
          padding: const EdgeInsets.all(22),
          child: child,
        ),
      ),
    );
  }
}
