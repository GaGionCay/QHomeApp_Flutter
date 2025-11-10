import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RealtimeNotificationBanner {
  RealtimeNotificationBanner._();

  static OverlayEntry? _currentEntry;

  static bool get isShowing => _currentEntry != null;

  static void show({
    required BuildContext context,
    required String title,
    String? subtitle,
    String? body,
    Widget? leading,
    Duration displayDuration = const Duration(seconds: 4),
    VoidCallback? onTap,
    VoidCallback? onDismissed,
    bool enableHapticFeedback = true,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _currentEntry?.remove();
    _currentEntry = null;

    final entry = OverlayEntry(
      builder: (context) => _RealtimeNotificationBanner(
        title: title,
        subtitle: subtitle,
        body: body,
        leading: leading,
        displayDuration: displayDuration,
        onTap: onTap,
        onDismissed: () {
          dismiss();
          onDismissed?.call();
        },
        enableHapticFeedback: enableHapticFeedback,
      ),
    );

    overlay.insert(entry);
    _currentEntry = entry;
  }

  static void dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _RealtimeNotificationBanner extends StatefulWidget {
  const _RealtimeNotificationBanner({
    required this.title,
    this.subtitle,
    this.body,
    this.leading,
    required this.displayDuration,
    this.onTap,
    required this.onDismissed,
    required this.enableHapticFeedback,
  });

  final String title;
  final String? subtitle;
  final String? body;
  final Widget? leading;
  final Duration displayDuration;
  final VoidCallback? onTap;
  final VoidCallback onDismissed;
  final bool enableHapticFeedback;

  @override
  State<_RealtimeNotificationBanner> createState() =>
      _RealtimeNotificationBannerState();
}

class _RealtimeNotificationBannerState
    extends State<_RealtimeNotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _opacity;
  Timer? _autoHideTimer;
  double _dragOffset = 0;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 1, curve: Curves.easeOut),
      ),
    );

    if (widget.enableHapticFeedback) {
      HapticFeedback.lightImpact();
    }

    _controller.forward();
    final clampedDuration = _clampDuration(
      widget.displayDuration,
      const Duration(seconds: 2),
      const Duration(seconds: 10),
    );
    _autoHideTimer = Timer(clampedDuration, _dismiss);
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_isDismissing) return;
    _isDismissing = true;
    _autoHideTimer?.cancel();
    _controller.reverse().whenComplete(() {
      widget.onDismissed();
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta ?? 0;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (_dragOffset < -20 || velocity < -500) {
      _dismiss();
    } else {
      setState(() {
        _dragOffset = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF101012).withOpacity(0.85) : Colors.white.withOpacity(0.92);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.12)
        : Colors.black.withOpacity(0.08);
    final subtitleStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.72),
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
    );
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.3,
    );

    return IgnorePointer(
      ignoring: _isDismissing,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _dragOffset),
                child: child,
              );
            },
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _opacity,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: GestureDetector(
                    onTap: () {
                      _dismiss();
                      widget.onTap?.call();
                    },
                    onVerticalDragUpdate: _onVerticalDragUpdate,
                    onVerticalDragEnd: _onVerticalDragEnd,
                    behavior: HitTestBehavior.translucent,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: baseColor,
                            border: Border.all(color: borderColor),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                    isDark ? 0.35 : 0.12),
                                blurRadius: 24,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 360),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                widget.leading ??
                                    _DefaultLeadingIcon(
                                      isDarkMode: isDark,
                                      color: theme.colorScheme.primary,
                                    ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.subtitle != null &&
                                          widget.subtitle!.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            widget.subtitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: subtitleStyle,
                                          ),
                                        ),
                                      Text(
                                        widget.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      if (widget.body != null &&
                                          widget.body!.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            widget.body!,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: bodyStyle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  iconSize: 18,
                                  splashRadius: 20,
                                  onPressed: _dismiss,
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Duration _clampDuration(
  Duration value,
  Duration min,
  Duration max,
) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

class _DefaultLeadingIcon extends StatelessWidget {
  const _DefaultLeadingIcon({
    required this.isDarkMode,
    required this.color,
  });

  final bool isDarkMode;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final background = isDarkMode ? Colors.white.withOpacity(0.14) : color.withOpacity(0.12);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
      ),
      padding: const EdgeInsets.all(10),
      child: Icon(
        Icons.notifications_active_outlined,
        color: color,
        size: 22,
      ),
    );
  }
}

