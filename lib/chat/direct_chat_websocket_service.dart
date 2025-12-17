import 'dart:convert';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../auth/api_client.dart';
import '../core/app_config.dart';
import '../models/chat/direct_message.dart';
import '../models/chat/web_socket_message.dart';

/// Service to manage WebSocket subscriptions for direct chat conversations
/// Handles real-time message notifications when user is in app
class DirectChatWebSocketService {
  StompClient? _client;
  final Map<String, dynamic> _subscriptions = {};
  final Map<String, Function(DirectMessage)> _messageHandlers = {};
  final Map<String, Function(DirectMessage)> _globalMessageHandlers = {}; // For notifications when not in chat screen
  bool _isConnected = false;
  String? _currentToken;
  String? _currentUserId;
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 5;
  DateTime? _lastConnectionAttempt;

  /// Connect to WebSocket and subscribe to a conversation
  /// This should be called when user enters a chat screen
  Future<void> subscribeToConversation({
    required String conversationId,
    required String token,
    required String userId,
    required Function(DirectMessage) onMessage,
  }) async {
    if (kDebugMode) {
      print('📡 [DirectChatWebSocket] Subscribing to conversation: $conversationId');
    }

    // Store handlers
    _messageHandlers[conversationId] = onMessage;
    _currentToken = token;
    _currentUserId = userId;

    // If already connected, just add subscription
    if (_isConnected && _client != null) {
      _addSubscription(conversationId);
      return;
    }

    // Connect to WebSocket
    await _connect(token, userId);
  }

  /// Subscribe to all conversations for global notifications
  /// This should be called when app starts to receive notifications when user is on home screen
  Future<void> subscribeToAllConversations({
    required List<String> conversationIds,
    required String token,
    required String userId,
    required Function(DirectMessage) onGlobalMessage,
  }) async {
    if (kDebugMode) {
      print('📡 [DirectChatWebSocket] Subscribing to ${conversationIds.length} conversations for global notifications');
    }

    // Store global handler
    for (final conversationId in conversationIds) {
      _globalMessageHandlers[conversationId] = onGlobalMessage;
    }
    
    _currentToken = token;
    _currentUserId = userId;

    // If already connected, add subscriptions
    if (_isConnected && _client != null) {
      for (final conversationId in conversationIds) {
        if (!_subscriptions.containsKey(conversationId)) {
          _addSubscription(conversationId);
        }
      }
      return;
    }

    // Connect to WebSocket
    await _connect(token, userId);
  }

  /// Update subscriptions when conversations list changes
  void updateConversationSubscriptions(List<String> conversationIds) {
    if (!_isConnected || _client == null) return;

    // Remove subscriptions for conversations that no longer exist
    final currentSubscriptions = _subscriptions.keys.toSet();
    final newConversationIds = conversationIds.toSet();
    
    for (final conversationId in currentSubscriptions) {
      if (!newConversationIds.contains(conversationId) && 
          !_messageHandlers.containsKey(conversationId)) {
        // Only unsubscribe if not in chat screen (no message handler)
        unsubscribeFromConversation(conversationId);
        _globalMessageHandlers.remove(conversationId);
      }
    }

    // Add subscriptions for new conversations
    for (final conversationId in conversationIds) {
      if (!_subscriptions.containsKey(conversationId)) {
        _addSubscription(conversationId);
      }
    }
  }

  /// Unsubscribe from a conversation
  /// This should be called when user leaves a chat screen
  /// Note: StompClient doesn't have direct unsubscribe method, but we track it and remove handlers
  void unsubscribeFromConversation(String conversationId) {
    if (kDebugMode) {
      print('📡 [DirectChatWebSocket] Unsubscribing from conversation: $conversationId');
    }

    // Remove subscription from tracking map
    // Note: StompClient manages subscriptions internally, we just track them
    _subscriptions.remove(conversationId);
    _messageHandlers.remove(conversationId);
  }

  /// Disconnect from WebSocket
  void disconnect() {
    if (kDebugMode) {
      print('📡 [DirectChatWebSocket] Disconnecting...');
    }

    // Clear all subscriptions tracking
    // Note: StompClient will handle unsubscribing when deactivated
    _subscriptions.clear();
    _messageHandlers.clear();
    _globalMessageHandlers.clear();

    // Disconnect client (this will automatically unsubscribe all subscriptions)
    _client?.deactivate();
    _client = null;
    _isConnected = false;
    _consecutiveFailures = 0; // Reset on manual disconnect
    _lastConnectionAttempt = null;
  }

  /// Reset connection failure count to allow reconnection attempts
  /// Call this if you want to retry after connection has been disabled due to failures
  void resetConnectionFailures() {
    if (kDebugMode) {
      print('🔄 [DirectChatWebSocket] Resetting connection failure count');
    }
    _consecutiveFailures = 0;
    _lastConnectionAttempt = null;
  }

  int _calculateReconnectDelay() {
    // Exponential backoff: 5s, 10s, 20s, 30s, max 30s
    if (_consecutiveFailures == 0) return 5;
    if (_consecutiveFailures == 1) return 10;
    if (_consecutiveFailures == 2) return 20;
    return 30; // Max 30 seconds
  }

  Future<void> _connect(String token, String userId) async {
    // Prevent too frequent connection attempts
    if (_lastConnectionAttempt != null) {
      final timeSinceLastAttempt = DateTime.now().difference(_lastConnectionAttempt!);
      if (timeSinceLastAttempt.inSeconds < 2) {
        if (kDebugMode) {
          print('⏸️ [DirectChatWebSocket] Skipping connection attempt (too soon after last attempt)');
        }
        return;
      }
    }
    
    // Stop if we've had too many failures
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      if (kDebugMode) {
        print('🛑 [DirectChatWebSocket] Connection disabled due to too many failures. Call resetConnectionFailures() to retry.');
      }
      return;
    }
    
    _lastConnectionAttempt = DateTime.now();
    final wsUrl = _buildWebSocketUrl();
    
    if (kDebugMode) {
      print('🔌 [DirectChatWebSocket] Connecting to: $wsUrl');
      print('   Consecutive failures: $_consecutiveFailures');
    }

    _client = StompClient(
      config: StompConfig(
        url: wsUrl,
        onConnect: (StompFrame frame) {
          _isConnected = true;
          _consecutiveFailures = 0; // Reset failure count on successful connection
          if (kDebugMode) {
            print('✅ [DirectChatWebSocket] Connected');
          }

          // Subscribe to all active conversations
          for (final conversationId in _messageHandlers.keys) {
            _addSubscription(conversationId);
          }
        },
        onDisconnect: (frame) {
          _isConnected = false;
          if (kDebugMode) {
            print('🔌 [DirectChatWebSocket] Disconnected');
          }
        },
        onStompError: (frame) {
          _consecutiveFailures++;
          if (kDebugMode) {
            print('⚠️ [DirectChatWebSocket] STOMP error: ${frame.body ?? 'Unknown'}');
            print('   Consecutive failures: $_consecutiveFailures/$_maxConsecutiveFailures');
          }
          
          // Stop reconnecting after too many failures
          if (_consecutiveFailures >= _maxConsecutiveFailures) {
            if (kDebugMode) {
              print('🛑 [DirectChatWebSocket] Too many STOMP errors, stopping reconnection attempts');
            }
            _client?.deactivate();
            _client = null;
            _isConnected = false;
          }
        },
        onWebSocketError: (error) {
          _consecutiveFailures++;
          if (kDebugMode) {
            print('❌ [DirectChatWebSocket] WebSocket error: $error');
            print('   Error type: ${error.runtimeType}');
            print('   Consecutive failures: $_consecutiveFailures/$_maxConsecutiveFailures');
            print('   URL: $wsUrl');
            
            // Provide helpful error messages
            if (error.toString().contains('HandshakeException')) {
              print('   💡 Tip: HandshakeException usually means:');
              print('      - Server WebSocket endpoint not available');
              print('      - Wrong URL or port');
              print('      - Server not running');
              print('      - Network/firewall blocking connection');
              print('      - SSL/TLS certificate issue');
            }
          }
          
          // Stop reconnecting after too many failures
          if (_consecutiveFailures >= _maxConsecutiveFailures) {
            if (kDebugMode) {
              print('🛑 [DirectChatWebSocket] Too many WebSocket errors, stopping reconnection attempts');
              print('   Last error: $error');
              print('   URL: $wsUrl');
              print('   💡 To retry, call: directChatWebSocketService.resetConnectionFailures()');
            }
            _client?.deactivate();
            _client = null;
            _isConnected = false;
          }
        },
        stompConnectHeaders: {
          'Authorization': 'Bearer $token',
          if (wsUrl.contains('ngrok') || wsUrl.contains('ngrok-free.app'))
            'ngrok-skip-browser-warning': 'true',
        },
        webSocketConnectHeaders: {
          'Authorization': 'Bearer $token',
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
      _client?.activate();
    } catch (e) {
      if (kDebugMode) {
        print('❗ [DirectChatWebSocket] Failed to activate: $e');
      }
    }
  }

  void _addSubscription(String conversationId) {
    if (_client == null || !_isConnected) {
      if (kDebugMode) {
        print('⚠️ [DirectChatWebSocket] Cannot subscribe - not connected');
      }
      return;
    }

    final destination = '/topic/direct-chat/$conversationId';
    
    if (kDebugMode) {
      print('📡 [DirectChatWebSocket] Subscribing to: $destination');
    }

    final subscription = _client!.subscribe(
      destination: destination,
      callback: (frame) {
        if (frame.body == null) return;

        try {
          if (kDebugMode) {
            print('📩 [DirectChatWebSocket] Received message for conversation $conversationId');
          }

          final jsonData = jsonDecode(frame.body!);
          final wsMessage = WebSocketMessage.fromJson(jsonData);

          // Handle different message types
          if (wsMessage.type == 'DIRECT_MESSAGE' && wsMessage.directMessage != null) {
            // New message received
            final message = wsMessage.directMessage!;
            
            // Call handler if user is in chat screen
            final handler = _messageHandlers[conversationId];
            if (handler != null) {
              handler(message);
            }
            
            // Call global handler for notifications when user is on home screen
            final globalHandler = _globalMessageHandlers[conversationId];
            if (globalHandler != null) {
              globalHandler(message);
            }
          } else if (wsMessage.type == 'DIRECT_MESSAGE_UPDATED' && wsMessage.directMessage != null) {
            // Message updated - call handler to update message in list
            final message = wsMessage.directMessage!;
            final handler = _messageHandlers[conversationId];
            if (handler != null) {
              handler(message);
            }
          } else if (wsMessage.type == 'DIRECT_MESSAGE_DELETED' && wsMessage.directMessage != null) {
            // Message deleted - call handler to mark message as deleted
            final message = wsMessage.directMessage!;
            final handler = _messageHandlers[conversationId];
            if (handler != null) {
              handler(message);
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ [DirectChatWebSocket] Error parsing message: $e');
            print('   Raw message: ${frame.body}');
          }
        }
      },
    );

    _subscriptions[conversationId] = subscription;
  }

  String _buildWebSocketUrl() {
    // Build WebSocket URL - use apiBaseUrl (without /api) and add /ws path
    // IMPORTANT: Use AppConfig.apiBaseUrl directly to avoid double /api issue
    final baseUrl = '${AppConfig.apiBaseUrl}/ws';
    
    // Convert HTTP/HTTPS to WS/WSS
    String wsUrl = baseUrl;
    if (baseUrl.startsWith('https://')) {
      wsUrl = baseUrl.replaceFirst('https://', 'wss://');
    } else if (baseUrl.startsWith('http://')) {
      wsUrl = baseUrl.replaceFirst('http://', 'ws://');
    }
    
    // For ngrok URLs, remove port
    final isNgrokUrl = wsUrl.contains('ngrok') || 
                      wsUrl.contains('ngrok-free.app') ||
                      wsUrl.contains('ngrok.io');
    
    if (isNgrokUrl) {
      wsUrl = wsUrl.replaceAll(RegExp(r':\d+/'), '/');
    }
    
    if (kDebugMode) {
      print('🔍 [DirectChatWebSocket] Built WebSocket URL: $wsUrl');
      print('   Base URL: $baseUrl');
      print('   Is ngrok: $isNgrokUrl');
    }
    
    return wsUrl;
  }

  /// Check if user is currently viewing a conversation in chat screen
  /// Returns true if there's an active message handler for this conversation
  bool isViewingConversation(String conversationId) {
    return _messageHandlers.containsKey(conversationId);
  }
}

// Singleton instance
final directChatWebSocketService = DirectChatWebSocketService();
