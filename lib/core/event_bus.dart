import 'dart:async';

/// 🔔 AppEventBus nâng cấp — hỗ trợ emit, on, off từng loại sự kiện
class AppEventBus {
  static final AppEventBus _instance = AppEventBus._internal();
  factory AppEventBus() => _instance;
  AppEventBus._internal();

  /// Map lưu danh sách listener theo từng event
  final Map<String, List<StreamSubscription>> _listeners = {};

  /// Controller gốc để phát broadcast toàn cục
  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();

  /// Emit (phát) một event
  void emit(String event, [dynamic data]) {
    _controller.add({'event': event, 'data': data});
  }

  /// Lắng nghe sự kiện theo key (ví dụ: 'news_update')
  void on(String event, void Function(dynamic data) callback) {
    final sub = _controller.stream
        .where((e) => e['event'] == event)
        .listen((e) => callback(e['data']));
    _listeners.putIfAbsent(event, () => []).add(sub);
  }

  /// Hủy lắng nghe sự kiện
  void off(String event) {
    if (_listeners.containsKey(event)) {
      for (var sub in _listeners[event]!) {
        sub.cancel();
      }
      _listeners.remove(event);
    }
  }

  /// Hủy tất cả lắng nghe
  void clear() {
    for (var list in _listeners.values) {
      for (var sub in list) {
        sub.cancel();
      }
    }
    _listeners.clear();
  }

  /// Giải phóng toàn bộ (ít khi dùng)
  void dispose() {
    clear();
    _controller.close();
  }
}
