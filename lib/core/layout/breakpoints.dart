import 'package:flutter/widgets.dart';

/// Single source of truth for responsive layout thresholds.
///
/// Every widget that switches between the desktop (sidebar) and mobile
/// (bottom navigation) presentation must use these helpers instead of
/// comparing `MediaQuery` widths against literals.
abstract final class Breakpoints {
  /// Minimum window width (logical pixels) for the desktop layout.
  static const double desktop = 850;

  /// True when the window is wide enough for the desktop layout.
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;

  /// True when the window should use the mobile layout.
  static bool isMobile(BuildContext context) => !isDesktop(context);
}
