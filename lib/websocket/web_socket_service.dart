import 'package:stomp_dart_client/stomp_dart_client.dart';

class WebSocketService {
  StompClient? client;
  bool _connected = false;

  void connect({
    required String token,
    required String userId,
    required void Function(dynamic) onNotification,
    required void Function(dynamic) onBill,
  }) {
    if (_connected) return;

    client = StompClient(
      config: StompConfig.sockJS(
        url: 'http://192.168.100.33:8080/ws',
        onConnect: (StompFrame frame) {
          _connected = true;
          print('✅ WebSocket connected: $frame');

          client?.subscribe(
            destination: '/topic/notifications/$userId',
            callback: (frame) {
              if (frame.body != null) {
                print('📩 Notification: ${frame.body}');
                onNotification(frame.body);
              }
            },
          );

          client?.subscribe(
            destination: '/topic/bills/$userId',
            callback: (frame) {
              if (frame.body != null) {
                print('💰 Bill update: ${frame.body}');
                onBill(frame.body);
              }
            },
          );
        },
        onDisconnect: (frame) {
          _connected = false;
          print('🔌 WebSocket disconnected.');
        },
        onStompError: (frame) =>
            print('⚠️ STOMP error: ${frame.body ?? 'Unknown'}'),
        onWebSocketError: (error) => print('❌ WebSocket error: $error'),
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        reconnectDelay: const Duration(seconds: 5),
        heartbeatIncoming: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 10),
      ),
    );

    try {
      client?.activate();
    } catch (e) {
      print('❗ Failed to activate WebSocket: $e');
    }
  }

  void disconnect() {
    try {
      client?.deactivate();
      _connected = false;
      print('🔌 WebSocket manually disconnected.');
    } catch (e) {
      print('⚠️ Error on disconnect: $e');
    }
  }
}
