import 'dart:convert';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../auth/api_client.dart';
import '../models/chat/direct_message.dart';
import '../models/chat/web_socket_message.dart';

/// Service to manage WebSocket subscriptions for direct chat conversations
/// Handles real-time message notifications when user is in app
class DirectChatWebSocketService {
  StompClient? _client;
  final Map<String, StompSubscription> _subscriptions = {};
  final Map<String, Function(DirectMessage)> _messageHandlers = {};
  final Map<String, Function(DirectMessage)> _globalMessageHandlers = {}; // For notifications when not in chat screen
  bool _isConnected = false;
  String? _currentToken;
  String? _currentUserId;

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
  void unsubscribeFromConversation(String conversationId) {
    if (kDebugMode) {
      print('📡 [DirectChatWebSocket] Unsubscribing from conversation: $conversationId');
    }

    final subscription = _subscriptions.remove(conversationId);
    subscription?.cancel();
    _messageHandlers.remove(conversationId);
  }

  /// Disconnect from WebSocket
  void disconnect() {
    if (kDebugMode) {
      print('📡 [DirectChatWebSocket] Disconnecting...');
    }

    // Cancel all subscriptions
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _messageHandlers.clear();

    // Disconnect client
    _client?.deactivate();
    _client = null;
    _isConnected = false;
  }

  Future<void> _connect(String token, String userId) async {
    final wsUrl = _buildWebSocketUrl();
    
    if (kDebugMode) {
      print('🔌 [DirectChatWebSocket] Connecting to: $wsUrl');
    }

    _client = StompClient(
      config: StompConfig(
        url: wsUrl,
        onConnect: (StompFrame frame) {
          _isConnected = true;
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
          if (kDebugMode) {
            print('⚠️ [DirectChatWebSocket] STOMP error: ${frame.body ?? 'Unknown'}');
          }
        },
        onWebSocketError: (error) {
          if (kDebugMode) {
            print('❌ [DirectChatWebSocket] WebSocket error: $error');
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
        reconnectDelay: const Duration(seconds: 5),
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
    final baseUrl = ApiClient.buildServiceBase(path: '/ws');
    
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
