import 'package:flutter/foundation.dart';

/// Utility class for logging that only logs in debug mode
/// This helps improve performance in production builds
class AppLogger {
  /// Log info message (only in debug mode)
  static void info(String message) {
    if (kDebugMode) {
      debugPrint('ℹ️ $message');
    }
  }

  /// Log warning message (only in debug mode)
  static void warning(String message) {
    if (kDebugMode) {
      debugPrint('⚠️ $message');
    }
  }

  /// Log error message (only in debug mode)
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('❌ $message');
      if (error != null) {
        debugPrint('   Error: $error');
      }
      if (stackTrace != null) {
        debugPrint('   Stack: $stackTrace');
      }
    }
  }

  /// Log success message (only in debug mode)
  static void success(String message) {
    if (kDebugMode) {
      debugPrint('✅ $message');
    }
  }

  /// Log debug message (only in debug mode)
  static void debug(String message) {
    if (kDebugMode) {
      debugPrint('🔍 $message');
    }
  }
}

