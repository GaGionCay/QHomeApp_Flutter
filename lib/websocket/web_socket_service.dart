import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../auth/api_client.dart';
import '../core/app_config.dart';

class WebSocketService {
  StompClient? client;
  bool _connected = false;

  /// Build WebSocket URL from base URL
  /// Converts HTTP -> WS, HTTPS -> WSS
  /// IMPORTANT: Use apiBaseUrl (without /api) and add /ws path manually
  String _buildWebSocketUrl() {
    // Use apiBaseUrl directly (without /api) and add /ws path
    final baseUrl = '${AppConfig.apiBaseUrl}/ws';
    
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
    
    return wsUrl;
  }

  void connect({
    required String token,
    required String userId,
    required void Function(dynamic) onNotification,
  }) {
    if (_connected) return;

    final wsUrl = _buildWebSocketUrl();
    

    // Try native WebSocket first (better for ngrok), fallback to SockJS if needed
    // Note: base-service doesn't have .withSockJS(), so use native WebSocket
    client = StompClient(
      config: StompConfig(
        url: wsUrl,
        // Use native WebSocket instead of SockJS for better ngrok compatibility
        // If backend has SockJS, change to StompConfig.sockJS()
        onConnect: (StompFrame frame) {
          _connected = true;
          client?.subscribe(
            destination: '/topic/notifications/$userId',
            callback: (frame) {
              if (frame.body != null) {
                onNotification(frame.body);
              }
            },
          );
        },
        onDisconnect: (frame) {
          _connected = false;
        },
        onStompError: (frame) {
          // Only log critical STOMP errors
        },
        onWebSocketError: (error) {
          // Only log critical WebSocket errors (connection failures)
          final errorStr = error.toString();
          if (errorStr.contains('Connection timed out') || 
              errorStr.contains('Connection refused') ||
              errorStr.contains('HandshakeException')) {
            print('❌ [WebSocket] Connection failed: $errorStr');
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
        // DEV LOCAL mode: Disable auto-reconnect to prevent reconnect loops
        // WebSocket should only connect after successful health check
        reconnectDelay: const Duration(seconds: 0), // 0 = disable auto-reconnect
        heartbeatIncoming: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 10),
      ),
    );

    try {
      client?.activate();
    } catch (e) {
      print('❌ [WebSocket] Failed to activate: $e');
    }
  }

  void disconnect() {
    try {
      client?.deactivate();
      _connected = false;
    } catch (e) {
      // Silent disconnect error
    }
  }
}

