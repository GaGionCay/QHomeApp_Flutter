import 'package:flutter/widgets.dart';

/// Shared layout constants for coordinating content spacing with the
/// frosted bottom navigation shell.
class LayoutInsets {
  LayoutInsets._();

  /// Height of the glass navigation bar (including NavigationBar widget).
  static const double navBarHeight = 72;

  /// Vertical padding applied around the navigation bar container.
  static const double navBarVerticalPadding = 18;

  /// Default breathing space between page content and the nav container.
  static const double defaultTrailingGap = 12;

  /// Computes the trailing padding required so that scrollable content
  /// does not feel detached from the navigation bar while still preventing
  /// overlap when `Scaffold.extendBody` is true.
  ///
  /// By default, the safe-bottom inset is handled by the navigation shell,
  /// so we omit it here unless `includeSafeArea` is set to true.
  static double bottomNavContentPadding(
    BuildContext context, {
    double extra = 0,
    bool includeSafeArea = false,
    double minimumGap = 12,
  }) {
    final safePadding =
        includeSafeArea ? MediaQuery.of(context).padding.bottom : 0.0;

    final base = navBarHeight +
        navBarVerticalPadding +
        defaultTrailingGap +
        safePadding +
        extra;

    final minAllowed = (safePadding + minimumGap).clamp(0.0, double.infinity);
    return base < minAllowed ? minAllowed : base;
  }
}
