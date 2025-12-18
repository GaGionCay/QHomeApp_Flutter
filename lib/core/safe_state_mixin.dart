import 'package:flutter/material.dart';
import 'dart:async';

/// Mixin to handle lifecycle-safe operations in StatefulWidget
/// 
/// This mixin provides utilities to:
/// - Safely call setState() only when widget is mounted
/// - Safely update TextEditingController only when not disposed
/// - Safely navigate only when widget is mounted
/// - Automatically cancel ongoing operations on dispose
/// 
/// Usage:
/// ```dart
/// class MyScreen extends StatefulWidget {
///   @override
///   State<MyScreen> createState() => _MyScreenState();
/// }
/// 
/// class _MyScreenState extends State<MyScreen> with SafeStateMixin<MyScreen> {
///   // Your state and methods here
/// }
/// ```
mixin SafeStateMixin<T extends StatefulWidget> on State<T> {
  final List<StreamSubscription> _subscriptions = [];
  final List<Timer> _timers = [];
  final Set<TextEditingController> _controllers = {};
  
  /// Safely call setState only if widget is still mounted
  /// Returns true if setState was called, false if widget was already disposed
  bool safeSetState(VoidCallback fn) {
    if (!mounted) {
      return false;
    }
    
    // Use try-catch to handle edge cases where mounted check passes
    // but widget gets disposed before setState completes
    try {
      setState(fn);
      return true;
    } catch (e) {
      // Widget was disposed between mounted check and setState call
      debugPrint('⚠️ [SafeStateMixin] setState failed (widget disposed): $e');
      return false;
    }
  }
  
  /// Safely update TextEditingController text only if not disposed
  /// Returns true if update was successful
  bool safeUpdateController(TextEditingController controller, String text) {
    if (!mounted) {
      return false;
    }
    
    try {
      controller.text = text;
      return true;
    } catch (e) {
      // Controller was disposed
      debugPrint('⚠️ [SafeStateMixin] Controller update failed: $e');
      return false;
    }
  }
  
  /// Register a TextEditingController for automatic disposal
  /// Call this in initState() for each controller
  void registerController(TextEditingController controller) {
    _controllers.add(controller);
  }
  
  /// Register multiple controllers at once
  void registerControllers(List<TextEditingController> controllers) {
    _controllers.addAll(controllers);
  }
  
  /// Safely navigate only if widget is mounted
  /// Returns Future that completes with navigation result, or null if widget disposed
  Future<U?> safeNavigate<U>(Future<U?> Function() navigationFn) async {
    if (!mounted) {
      return null;
    }
    
    try {
      return await navigationFn();
    } catch (e) {
      if (mounted) {
        debugPrint('⚠️ [SafeStateMixin] Navigation failed: $e');
      }
      return null;
    }
  }
  
  /// Execute an async operation safely with automatic mounted checks
  /// 
  /// Usage:
  /// ```dart
  /// await safeAsync(() async {
  ///   final data = await apiCall();
  ///   // Automatically checks mounted before continuing
  ///   safeSetState(() => _data = data);
  /// });
  /// ```
  Future<void> safeAsync(Future<void> Function() operation) async {
    if (!mounted) {
      return;
    }
    
    try {
      await operation();
    } catch (e) {
      if (mounted) {
        // Only log if widget is still mounted (error is relevant)
        debugPrint('⚠️ [SafeStateMixin] Async operation failed: $e');
      }
      // Rethrow to allow caller to handle if needed
      rethrow;
    }
  }
  
  /// Register a StreamSubscription for automatic cancellation on dispose
  void addSubscription(StreamSubscription subscription) {
    _subscriptions.add(subscription);
  }
  
  /// Register a Timer for automatic cancellation on dispose
  void addTimer(Timer timer) {
    _timers.add(timer);
  }
  
  /// Show SnackBar safely (only if widget is mounted and context is valid)
  void safeShowSnackBar(String message, {Color? backgroundColor, Duration? duration}) {
    if (!mounted) return;
    
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: duration ?? const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // Context might be invalid
      debugPrint('⚠️ [SafeStateMixin] SnackBar failed: $e');
    }
  }
  
  /// Show Dialog safely (only if widget is mounted and context is valid)
  Future<U?> safeShowDialog<U>({
    required Widget Function(BuildContext) builder,
    bool barrierDismissible = true,
  }) async {
    if (!mounted) return null;
    
    try {
      return await showDialog<U>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
    } catch (e) {
      debugPrint('⚠️ [SafeStateMixin] Dialog failed: $e');
      return null;
    }
  }
  
  /// Pop navigation safely
  void safePop<U>([U? result]) {
    if (!mounted) return;
    
    try {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      debugPrint('⚠️ [SafeStateMixin] Pop failed: $e');
    }
  }
  
  @override
  void dispose() {
    // Cancel all subscriptions
    for (final subscription in _subscriptions) {
      try {
        subscription.cancel();
      } catch (e) {
        // Ignore errors when cancelling
      }
    }
    _subscriptions.clear();
    
    // Cancel all timers
    for (final timer in _timers) {
      try {
        timer.cancel();
      } catch (e) {
        // Ignore errors when cancelling
      }
    }
    _timers.clear();
    
    // Dispose all registered controllers
    for (final controller in _controllers) {
      try {
        controller.dispose();
      } catch (e) {
        // Ignore errors when disposing
      }
    }
    _controllers.clear();
    
    super.dispose();
  }
}

/// Extension to make Future operations lifecycle-aware
extension SafeFutureExtension<T> on Future<T> {
  /// Execute future and check mounted before processing result
  /// 
  /// Usage:
  /// ```dart
  /// apiCall().thenIfMounted(this, (data) {
  ///   setState(() => _data = data);
  /// });
  /// ```
  Future<void> thenIfMounted(
    State state,
    void Function(T value) onValue, {
    void Function(Object error)? onError,
  }) async {
    try {
      final value = await this;
      if (state.mounted) {
        onValue(value);
      }
    } catch (e) {
      if (state.mounted && onError != null) {
        onError(e);
      }
    }
  }
}

