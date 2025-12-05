import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// Utility class for smooth, modern animations throughout the app
/// Provides consistent animation patterns similar to Messenger/Zalo
class SmoothAnimations {
  // Animation durations
  static const Duration _fastDuration = Duration(milliseconds: 200);
  static const Duration _normalDuration = Duration(milliseconds: 300);

  // Animation curves
  static const Curve _defaultCurve = Curves.easeOutCubic;
  static const Curve _bounceCurve = Curves.easeOutBack;

  /// Fade in animation - smooth opacity transition
  static Widget fadeIn({
    required Widget child,
    Duration duration = _normalDuration,
    Curve curve = _defaultCurve,
    double begin = 0.0,
    double end = 1.0,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: begin, end: end),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: child,
        );
      },
      child: child,
    );
  }

  /// Slide in animation - smooth position transition
  static Widget slideIn({
    required Widget child,
    Offset slideOffset = const Offset(0, 20),
    Duration duration = _normalDuration,
    Curve curve = _defaultCurve,
  }) {
    return TweenAnimationBuilder<Offset>(
      tween: Tween(begin: slideOffset, end: Offset.zero),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Transform.translate(
          offset: value,
          child: child,
        );
      },
      child: child,
    );
  }

  /// Scale animation - smooth size transition
  static Widget scaleIn({
    required Widget child,
    double begin = 0.8,
    double end = 1.0,
    Duration duration = _normalDuration,
    Curve curve = _bounceCurve,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: begin, end: end),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: child,
    );
  }

  /// Staggered item animation - for list items appearing one by one
  static Widget staggeredItem({
    required int index,
    required Widget child,
    Duration baseDuration = _fastDuration,
    Duration staggerDelay = const Duration(milliseconds: 50),
    Curve curve = _defaultCurve,
    Offset slideOffset = const Offset(0, 20),
  }) {
    final delay = Duration(milliseconds: (index * staggerDelay.inMilliseconds).clamp(0, 200));
    final totalDuration = baseDuration + delay;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: totalDuration,
      curve: curve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(slideOffset.dx * (1 - value), slideOffset.dy * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  /// Combined fade + slide animation
  static Widget fadeSlideIn({
    required Widget child,
    Offset slideOffset = const Offset(0, 20),
    Duration duration = _normalDuration,
    Curve curve = _defaultCurve,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(slideOffset.dx * (1 - value), slideOffset.dy * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  /// Hero-like animation wrapper for smooth transitions
  static Widget hero({
    required String tag,
    required Widget child,
  }) {
    return Hero(
      tag: tag,
      child: child,
      flightShuttleBuilder: (
        BuildContext flightContext,
        Animation<double> animation,
        HeroFlightDirection flightDirection,
        BuildContext fromHeroContext,
        BuildContext toHeroContext,
      ) {
        final hero = flightDirection == HeroFlightDirection.push
            ? fromHeroContext.widget
            : toHeroContext.widget;
        return FadeTransition(
          opacity: animation,
          child: hero,
        );
      },
    );
  }
}

/// Smooth page route with fade transition
class SmoothPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SmoothPageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Fade + slight scale for modern feel
            final fadeAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            final scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(fadeAnimation);

            return FadeTransition(
              opacity: fadeAnimation,
              child: ScaleTransition(
                scale: scaleAnimation,
                child: child,
              ),
            );
          },
        );
}

/// Smooth bottom sheet with slide up animation
Future<T?> showSmoothBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool enableDrag = true,
  Color? backgroundColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.surface,
    elevation: elevation ?? 8,
    shape: shape ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
    clipBehavior: clipBehavior ?? Clip.antiAlias,
    constraints: constraints,
    barrierColor: barrierColor ?? Colors.black54,
    transitionAnimationController: AnimationController(
      vsync: Navigator.of(context),
      duration: const Duration(milliseconds: 250),
    ),
  );
}

/// Smooth dialog with scale animation
Future<T?> showSmoothDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  RouteSettings? routeSettings,
}) {
  return showGeneralDialog<T>(
    context: context,
    pageBuilder: (context, animation, secondaryAnimation) {
      return Builder(builder: builder);
    },
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor ?? Colors.black54,
    barrierLabel: barrierLabel,
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final scaleAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      
      return ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1.0).animate(scaleAnimation),
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      );
    },
    routeSettings: routeSettings,
  );
}

/// Animated container for smooth state changes
class SmoothContainer extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final Duration duration;

  const SmoothContainer({
    super.key,
    required this.child,
    this.color,
    this.padding,
    this.margin,
    this.borderRadius,
    this.border,
    this.boxShadow,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: border,
        boxShadow: boxShadow,
      ),
      child: child,
    );
  }
}

/// Animated opacity for smooth fade transitions
class SmoothOpacity extends StatelessWidget {
  final Widget child;
  final bool visible;
  final Duration duration;

  const SmoothOpacity({
    super.key,
    required this.child,
    required this.visible,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

/// Loading shimmer effect (placeholder for shimmer package)
class ShimmerLoading extends StatelessWidget {
  final Widget child;
  final bool isLoading;

  const ShimmerLoading({
    super.key,
    required this.child,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return child;
    
    // Simple placeholder - can be enhanced with shimmer package if needed
    return Opacity(
      opacity: 0.6,
      child: child,
    );
  }
}
