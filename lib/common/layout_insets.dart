import 'package:flutter/widgets.dart';

class LayoutInsets {
  LayoutInsets._();

  static const double navBarHeight = 72;

  static const double navBarVerticalPadding = 18;

  static const double defaultTrailingGap = 12;
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

