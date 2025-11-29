import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/resident_notification.dart';
import '../../theme/app_colors.dart';
import '../notification_detail_screen.dart';

class NotificationCard extends StatefulWidget {
  final ResidentNotification notification;
  final String? residentId;
  final VoidCallback? onMarkedAsRead;

  const NotificationCard({
    super.key,
    required this.notification,
    this.residentId,
    this.onMarkedAsRead,
  });

  @override
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    final curve = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(curve);

    final delaySeed = (widget.notification.id.hashCode & 0x7fffffff) % 5; // 0-4
    Future.delayed(Duration(milliseconds: 40 * delaySeed), () {
      if (mounted) _entryController.forward();
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final notification = widget.notification;
    final color = _getTypeColor(notification.type);
    final icon = _getTypeIcon(notification.type);
    final dateText =
        DateFormat('HH:mm').format(notification.createdAt.toLocal());
    final isUnread = !notification.isRead;

    final backgroundColor = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.surface;

    final boxShadow = (!isDark && isUnread)
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 12),
              spreadRadius: -4,
            ),
          ]
        : <BoxShadow>[];

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.25)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.25);

    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: OpenContainer<bool>(
          transitionDuration: const Duration(milliseconds: 320),
          transitionType: ContainerTransitionType.fadeThrough,
          closedColor: Colors.transparent,
          openColor: theme.colorScheme.surface,
          closedElevation: 0,
          openElevation: 0,
          closedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          openBuilder: (context, _) => NotificationDetailScreen(
            notificationId: notification.id,
            residentId: widget.residentId,
            onMarkedAsRead: widget.onMarkedAsRead,
          ),
          closedBuilder: (context, openContainer) {
            return TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 1, end: _isPressed ? 0.97 : 1),
              builder: (context, scale, child) => Transform.scale(
                scale: scale,
                child: child,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: openContainer,
                  onHighlightChanged: (value) {
                    if (_isPressed != value) {
                      setState(() => _isPressed = value);
                    }
                  },
                  child: Stack(
                children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: borderColor,
                            width: isDark ? 1.2 : 1,
                          ),
                          boxShadow: boxShadow,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                icon,
                                color: color,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          notification.title,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            fontWeight: isUnread
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            fontSize: 15.5,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.access_time,
                                        size: 13,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.45),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        dateText,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.45),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    notification.message,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: isUnread ? 0.78 : 0.6),
                                      fontSize: 13.2,
                                      height: 1.35,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 
                                              isDark ? 0.22 : 0.14),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Text(
                                          _getTypeDisplayName(notification.type),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: color,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isUnread)
                        Positioned(
                          top: 10,
                          right: 16,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: isDark ? 0.6 : 0.4),
                                  blurRadius: 6,
                                  spreadRadius: 0.2,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
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
        return AppColors.warning;
      case 'SYSTEM':
        return AppColors.primaryEmerald;
      case 'NEWS':
        return AppColors.primaryBlue;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'SYSTEM':
        return Icons.info_outline_rounded;
      case 'PAYMENT':
        return Icons.payment_rounded;
      case 'SERVICE':
        return Icons.room_service_rounded;
      case 'CARD_APPROVED':
      case 'CARD_REJECTED':
      case 'CARD_PENDING':
      case 'CARD_FEE_REMINDER':
        return Icons.credit_card_rounded;
      case 'REQUEST':
        return Icons.request_quote_rounded;
      case 'BILL':
        return Icons.receipt_long_rounded;
      case 'ELECTRICITY':
        return Icons.bolt_rounded;
      case 'WATER':
        return Icons.water_drop_rounded;
      case 'CONTRACT':
        return Icons.description_rounded;
      case 'NEWS':
        return Icons.newspaper_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }

  /// Map notification type to Vietnamese display name (no accents, no underscores)
  String _getTypeDisplayName(String type) {
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
        // Fallback: convert to Vietnamese without accents and replace underscores with spaces
        return type
            .toUpperCase()
            .replaceAll('_', ' ')
            .replaceAll('A', 'A')
            .replaceAll('E', 'E')
            .replaceAll('I', 'I')
            .replaceAll('O', 'O')
            .replaceAll('U', 'U')
            .toLowerCase()
            .replaceAll(' ', '');
    }
  }
}
