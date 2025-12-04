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
      final listenerCount = _listeners[event]?.length ?? 0;
      print('📢 [AppEventBus] Emitting event: $event, data: $data');
      print('📢 [AppEventBus] Active listeners for $event: $listenerCount');
      if (listenerCount == 0) {
        print('⚠️ [AppEventBus] WARNING: No listeners registered for event: $event');
        print('⚠️ [AppEventBus] All registered events: ${_listeners.keys.toList()}');
      }
      _controller.add({'event': event, 'data': data});
    } else {
      print('⚠️ [AppEventBus] Cannot emit event: $event - controller is closed');
    }
  }

  StreamSubscription on(String event, void Function(dynamic data) callback) {
    print('🔧 [AppEventBus] Registering listener for event: $event');
    final sub = _controller.stream
        .where((e) {
          final matches = e['event'] == event;
          if (matches) {
            print('📡 [AppEventBus] Event matched: $event, data: ${e['data']}');
          }
          return matches;
        })
        .listen((e) {
          print('📡 [AppEventBus] Calling callback for event: $event');
          callback(e['data']);
        });
    _listeners.putIfAbsent(event, () => []).add(sub);
    print('✅ [AppEventBus] Listener registered. Total listeners for $event: ${_listeners[event]?.length ?? 0}');
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
