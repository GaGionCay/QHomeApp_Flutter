import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../auth/api_client.dart';

class WebSocketService {
  StompClient? client;
  bool _connected = false;

  /// Build WebSocket URL from base URL
  /// Converts HTTP -> WS, HTTPS -> WSS
  /// Removes port for ngrok URLs (ngrok handles routing)
  String _buildWebSocketUrl() {
    final baseUrl = ApiClient.buildServiceBase(path: '/ws');
    
    // Convert HTTP/HTTPS to WS/WSS
    String wsUrl = baseUrl;
    if (baseUrl.startsWith('https://')) {
      wsUrl = baseUrl.replaceFirst('https://', 'wss://');
    } else if (baseUrl.startsWith('http://')) {
      wsUrl = baseUrl.replaceFirst('http://', 'ws://');
    }
    
    // For ngrok URLs, remove port (ngrok handles routing automatically)
    final isNgrokUrl = wsUrl.contains('ngrok') || 
                      wsUrl.contains('ngrok-free.app') ||
                      wsUrl.contains('ngrok.io');
    
    if (isNgrokUrl) {
      // Remove port from ngrok URL (e.g., wss://xxx.ngrok-free.app:8989/ws -> wss://xxx.ngrok-free.app/ws)
      wsUrl = wsUrl.replaceAll(RegExp(r':\d+/'), '/');
    }
    
    if (kDebugMode) {
      print('🔌 WebSocket URL: $wsUrl');
    }
    
    return wsUrl;
  }

  void connect({
    required String token,
    required String userId,
    required void Function(dynamic) onNotification,
  }) {
    if (_connected) return;

    final wsUrl = _buildWebSocketUrl();
    
    // Check if this is an ngrok URL - ngrok free plan may not support WebSocket well
    final isNgrokUrl = wsUrl.contains('ngrok') || wsUrl.contains('ngrok-free.app');
    
    if (isNgrokUrl && kDebugMode) {
      print('⚠️ WebSocket over ngrok may not work with free plan');
      print('   Consider using ngrok paid plan or alternative tunnel for WebSocket');
    }

    // Try native WebSocket first (better for ngrok), fallback to SockJS if needed
    // Note: base-service doesn't have .withSockJS(), so use native WebSocket
    client = StompClient(
      config: StompConfig(
        url: wsUrl,
        // Use native WebSocket instead of SockJS for better ngrok compatibility
        // If backend has SockJS, change to StompConfig.sockJS()
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
        },
        onDisconnect: (frame) {
          _connected = false;
          print('🔌 WebSocket disconnected.');
        },
        onStompError: (frame) =>
            print('⚠️ STOMP error: ${frame.body ?? 'Unknown'}'),
        onWebSocketError: (error) {
          print('❌ WS error: $error');
          if (kDebugMode) {
            print('   WebSocket URL: $wsUrl');
            print('   Error type: ${error.runtimeType}');
            if (error.toString().contains('HandshakeException') || 
                error.toString().contains('Connection terminated')) {
              print('   ⚠️ Handshake failed - possible causes:');
              print('      1. Ngrok free plan may not support WebSocket');
              print('      2. Backend WebSocket endpoint not accessible');
              print('      3. CORS or security configuration issue');
              print('   💡 Solutions:');
              print('      - Use ngrok paid plan for WebSocket support');
              print('      - Or disable WebSocket and use polling/SSE instead');
              print('      - Or use alternative tunnel (Cloudflare Tunnel, localtunnel)');
              print('      - Or test with localhost first to verify WebSocket works');
            }
          }
        },
        stompConnectHeaders: {
          'Authorization': 'Bearer $token',
          // Add ngrok-skip-browser-warning header for ngrok URLs
          if (wsUrl.contains('ngrok') || wsUrl.contains('ngrok-free.app'))
            'ngrok-skip-browser-warning': 'true',
        },
        webSocketConnectHeaders: {
          'Authorization': 'Bearer $token',
          // Add ngrok-skip-browser-warning header for ngrok URLs
          if (wsUrl.contains('ngrok') || wsUrl.contains('ngrok-free.app'))
            'ngrok-skip-browser-warning': 'true',
        },
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

