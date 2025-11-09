import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppPrimaryButton extends StatefulWidget {
  const AppPrimaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
    this.enabled = true,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool loading;
  final bool enabled;

  @override
  State<AppPrimaryButton> createState() => _AppPrimaryButtonState();
}

class _AppPrimaryButtonState extends State<AppPrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      lowerBound: 0.98,
      upperBound: 1.02,
      duration: const Duration(milliseconds: 220),
    );
    _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (!widget.enabled || widget.loading) return;
    try {
      await _controller.forward();
      await _controller.reverse();
      widget.onPressed?.call();
    } finally {
      if (mounted) {
        _controller.value = 1.0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.titleMedium?.copyWith(
      color: Colors.white,
      letterSpacing: 0.3,
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: widget.enabled ? 1.0 : 0.6,
      child: GestureDetector(
        onTap: _handleTap,
        child: Center(
          child: ScaleTransition(
            scale: widget.loading
                ? Tween<double>(begin: 0.99, end: 0.99).animate(_controller)
                : _controller,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient(),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x331A73E8),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: animation.drive(Tween(begin: 0.98, end: 1.0)),
                          child: child,
                        ),
                      );
                    },
                    child: widget.loading
                        ? SizedBox(
                            key: const ValueKey('loading'),
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withValues(alpha: 0.95),
                              ),
                            ),
                          )
                        : Row(
                            key: const ValueKey('label'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icon != null) ...[
                                Icon(widget.icon, size: 18, color: Colors.white),
                                const SizedBox(width: 10),
                              ],
                              Text(widget.label, style: labelStyle),
                            ],
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

