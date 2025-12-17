import 'dart:async';

class AppEventBus {
  static final AppEventBus _instance = AppEventBus._internal();
  factory AppEventBus() => _instance;
  AppEventBus._internal();
  final Map<String, List<StreamSubscription>> _listeners = {};

  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();

  void emit(String event, [dynamic data]) {
    if (!_controller.isClosed) {
      _controller.add({'event': event, 'data': data});
    }
  }

  StreamSubscription on(String event, void Function(dynamic data) callback) {
    // Prevent duplicate listener registrations
    // Check if a listener for this event already exists
    final existingListeners = _listeners[event];
    if (existingListeners != null && existingListeners.isNotEmpty) {
      // Cancel existing listeners to prevent duplicates
      for (var sub in existingListeners) {
        sub.cancel();
      }
      _listeners[event] = [];
    }
    
    final sub = _controller.stream
        .where((e) => e['event'] == event)
        .listen((e) => callback(e['data']));
    
    _listeners.putIfAbsent(event, () => []).add(sub);
    return sub;
  }

  void off(String event) {
    if (_listeners.containsKey(event)) {
      for (var sub in _listeners[event]!) {
        sub.cancel();
      }
      _listeners.remove(event);
    }
  }

  void clear() {
    for (var list in _listeners.values) {
      for (var sub in list) {
        sub.cancel();
      }
    }
    _listeners.clear();
  }

  void dispose() {
    clear();
    _controller.close();
  }

  void once(String event, void Function(dynamic data) callback) {
    late StreamSubscription sub;
    sub = _controller.stream.where((e) => e['event'] == event).listen((e) {
      callback(e['data']);
      sub.cancel();
    });
  }
}

