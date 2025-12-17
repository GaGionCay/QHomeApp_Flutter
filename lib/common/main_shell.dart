import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../core/event_bus.dart';
import '../core/app_config.dart';
import '../home/home_screen.dart';
import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../news/news_detail_screen.dart';
import '../notifications/realtime_notification_banner.dart';
import '../notifications/notification_screen.dart';
import '../notifications/notification_router.dart';
import '../models/resident_notification.dart';
import '../core/push_notification_service.dart';
import '../profile/profile_service.dart';
import 'service_category_screen.dart';
import '../theme/app_colors.dart';
import 'menu_screen.dart';
import '../marketplace/marketplace_screen.dart';
import '../marketplace/post_detail_screen.dart';
import '../marketplace/marketplace_service.dart';
import '../models/marketplace_post.dart';
import '../chat/chat_screen.dart';
import '../chat/direct_chat_screen.dart';
import '../chat/chat_service.dart';
import '../chat/direct_chat_websocket_service.dart';
import '../models/chat/direct_message.dart';
import '../models/chat/conversation.dart';
import '../models/chat/message.dart';
import '../models/chat/group.dart';
import '../notifications/realtime_notification_banner.dart';
import '../widgets/animations/smooth_animations.dart';

class MainShell extends StatefulWidget {
  final int initialIndex;
  final String? initialSnackMessage;

  const MainShell({
    super.key,
    this.initialIndex = 0,
    this.initialSnackMessage,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late final List<Widget> _pages;
  final ApiClient _api = ApiClient();
  late final ContractService _contractService = ContractService(_api);
  StompClient? _stompClient;
  final Queue<String> _recentRealtimeKeys = Queue<String>();
  Set<String> _userBuildingIds = <String>{};
  String? _userResidentId;
  StreamSubscription<RemoteMessage>? _pushSubscription;
  final Set<String> _subscribedConversations = <String>{}; // Track subscribed conversations
  bool _hasDirectChatListener = false; // Track if listener is already registered
  final Set<String> _subscribedGroups = <String>{}; // Track subscribed group chats
  bool _hasGroupChatListener = false; // Track if group chat listener is already registered
  String? _currentViewingGroupId; // Track which group chat screen is currently being viewed

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    // DEV LOCAL mode: WebSocket only connects after successful login + profile loaded
    // Listen for login event to connect WebSocket
    AppEventBus().on('user_logged_in', (_) async {
      // Wait a bit for profile to be fully loaded
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
    _connectWebSocket();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final message = widget.initialSnackMessage;
      if (message == null || message.isEmpty) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    });
    _pushSubscription =
        PushNotificationService.instance.notificationClicks.listen(
      (message) {
        if (!mounted) return;
        final data = Map<String, dynamic>.from(message.data);
        _handleNotificationTap(data);
      },
    );

    _pages = [
      HomeScreen(onNavigateToTab: _onItemTapped),
      const ServiceCategoryScreen(),
      const MarketplaceScreen(),
      const MenuScreen(),
    ];
  }

  void _connectWebSocket() async {
    final token = await _api.storage.readAccessToken();
    if (token == null) {
      return;
    }

    await _prepareRealtimeContext();

    // DEV LOCAL mode: Use native WebSocket (not SockJS) for better performance
    // URL should be ws://host:port/ws (not /api/ws since Gateway routes /ws/** directly)
    final wsUrl = '${AppConfig.apiBaseUrl.replaceFirst('http://', 'ws://')}/ws';

    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        onConnect: (_) {
          _onStompConnected();
        },
        onStompError: (frame) {
          // Only log critical STOMP errors
          print('❌ [WebSocket] STOMP error: ${frame.body ?? frame.headers}');
        },
        onDisconnect: (_) {
          // Silent disconnect
        },
        onWebSocketError: (error) {
          // Production-ready: Only log critical connection failures
          final errorStr = error.toString();
          if (errorStr.contains('Connection timed out') || 
              errorStr.contains('Connection refused') ||
              errorStr.contains('HandshakeException')) {
            print('❌ [WebSocket] Connection failed: $errorStr');
          }
        },
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        // DEV LOCAL mode: Disable auto-reconnect to prevent reconnect loops
        reconnectDelay: const Duration(seconds: 0), // 0 = disable auto-reconnect
        // Add connection timeout
        connectionTimeout: const Duration(seconds: 10),
      ),
    );

    try {
      _stompClient?.activate();
    } catch (e) {
      print('❌ [WebSocket] Failed to activate: $e');
    }
  }

  Future<void> _prepareRealtimeContext() async {
    final Set<String> buildingIds = <String>{};
    try {
      final profile = await ProfileService(_api.dio).getProfile();

      // Get residentId for private notifications
      final residentId = _asString(profile['residentId']);
      if (residentId != null && residentId.isNotEmpty) {
        _userResidentId = residentId;
      }

      final profileBuildingId = _asString(profile['buildingId']);
      if (profileBuildingId != null && profileBuildingId.isNotEmpty) {
        buildingIds.add(profileBuildingId.toLowerCase());
      }

      final defaultBuildingId = _asString(profile['defaultBuildingId']);
      if (defaultBuildingId != null && defaultBuildingId.isNotEmpty) {
        buildingIds.add(defaultBuildingId.toLowerCase());
      }
    } catch (e) {
      // Silent fail - profile loading error not critical for WebSocket
    }

    if (buildingIds.isEmpty) {
      try {
        final units = await _contractService.getMyUnits();
        for (final unit in units) {
          final id = _asString(unit.buildingId);
          if (id != null && id.isNotEmpty) {
            buildingIds.add(id.toLowerCase());
          }
        }
      } catch (e) {
        // Silent fail - units loading error not critical for WebSocket
      }
    }

    _userBuildingIds = buildingIds;
  }

  void _onStompConnected() {
    _subscribeToNewsTopic();
    _subscribeToNotificationTopics();
    _subscribeToMarketplaceTopics();
    _setupMarketplaceEventListeners();
    _subscribeToDirectChatConversations();
    _subscribeToGroupChatConversations();
  }

  /// Subscribe to all direct chat conversations for realtime notifications
  Future<void> _subscribeToDirectChatConversations() async {
    try {
      if (_stompClient == null) {
        debugPrint('⚠️ [MainShell] StompClient not connected, cannot subscribe to direct chat');
        return;
      }

      // Load all conversations
      final chatService = ChatService();
      final conversations = await chatService.getConversations();
      
      if (conversations.isEmpty) {
        debugPrint('ℹ️ [MainShell] No conversations to subscribe to');
        return;
      }

      debugPrint('📡 [MainShell] Subscribing to ${conversations.length} direct chat conversations');

      // Track new conversations to subscribe
      final newConversationIds = conversations.map((c) => c.id).toSet();
      
      // Unsubscribe from conversations that no longer exist
      final toUnsubscribe = _subscribedConversations.difference(newConversationIds);
      for (final conversationId in toUnsubscribe) {
        // Note: StompClient doesn't have direct unsubscribe method, but we can track it
        _subscribedConversations.remove(conversationId);
        debugPrint('🔄 [MainShell] Conversation $conversationId no longer exists, will be unsubscribed on reconnect');
      }

      // Subscribe to each conversation topic (only if not already subscribed)
      for (final conversation in conversations) {
        if (_subscribedConversations.contains(conversation.id)) {
          debugPrint('ℹ️ [MainShell] Already subscribed to conversation ${conversation.id}, skipping');
          continue;
        }

        final destination = '/topic/direct-chat/${conversation.id}';
        
        _stompClient?.subscribe(
          destination: destination,
          headers: {'id': 'direct-chat-${conversation.id}'},
          callback: (frame) {
            if (frame.body == null) return;
            try {
              final jsonData = json.decode(frame.body!);
              final type = jsonData['type'] as String?;
              
              if (type == 'DIRECT_MESSAGE' && jsonData['directMessage'] != null) {
                final messageJson = jsonData['directMessage'] as Map<String, dynamic>;
                final message = DirectMessage.fromJson(messageJson);
                
                // Handle incoming message - will show notification if user is not in chat screen
                _handleDirectChatMessage(message);
              }
            } catch (e) {
              debugPrint('❌ [MainShell] Error parsing direct chat message: $e');
            }
          },
        );
        
        _subscribedConversations.add(conversation.id);
        debugPrint('✅ [MainShell] Subscribed to $destination');
      }

      // Listen for conversation updates (new conversations added)
      // Only register listener once to avoid multiple listeners
      if (!_hasDirectChatListener) {
        AppEventBus().on('direct_chat_activity_updated', (_) {
          // Reload conversations and update subscriptions after a delay
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              _subscribeToDirectChatConversations();
            }
          });
        });
        _hasDirectChatListener = true;
      }
    } catch (e) {
      debugPrint('❌ [MainShell] Error subscribing to direct chat conversations: $e');
    }
  }

  /// Handle incoming direct chat message and show notification banner
  /// Shows notification banner on ALL screens EXCEPT when user is currently in the direct chat screen for this conversation
  /// This means notification will appear on: homescreen, marketplace, services, menu, or any other screen
  void _handleDirectChatMessage(DirectMessage message) {
    if (!mounted) return;

    // Check if user is currently viewing this conversation in DirectChatScreen
    // If user is in the direct chat screen, DirectChatScreen will handle the message display
    // and we don't need to show notification banner
    if (directChatWebSocketService.isViewingConversation(message.conversationId)) {
      debugPrint('ℹ️ [MainShell] User is viewing conversation ${message.conversationId}, skipping notification banner');
      // Still emit event to update conversation list
      AppEventBus().emit('direct_chat_activity_updated');
      return;
    }

    // User is NOT in the direct chat screen - check mute status and show notification banner on current screen (could be any screen)
    // Get conversation info to check mute status
    _getConversationInfo(message.conversationId).then((conversation) {
      if (!mounted) return;

      // Check if conversation is muted
      final isMuted = conversation?.isMuted == true || 
          (conversation?.muteUntil != null && 
           conversation!.muteUntil!.isAfter(DateTime.now()));

      if (isMuted) {
        debugPrint('ℹ️ [MainShell] Conversation ${message.conversationId} is muted, skipping notification banner');
        // Still emit event to update conversation list (for unread count)
        AppEventBus().emit('direct_chat_activity_updated');
        return;
      }

      // Conversation is not muted - show notification banner
      final participantName = conversation?.getOtherParticipantName(_userResidentId ?? '') ?? 
                             conversation?.participant1Name ?? 
                             conversation?.participant2Name ?? 
                             'Người dùng';
      
      // Get message preview
      String messagePreview = _getMessagePreview(message);

      // Show realtime notification banner
      RealtimeNotificationBanner.show(
        context: context,
        title: participantName,
        subtitle: 'Chat trực tiếp',
        body: messagePreview,
        leading: const Icon(
          Icons.chat_bubble_outline,
          color: Colors.blue,
        ),
        displayDuration: const Duration(seconds: 4),
        onTap: () {
          // Navigate to direct chat screen
          _navigateToDirectChat(message.conversationId, participantName);
        },
      );

      // Emit event to update conversation list (for unread count badge)
      AppEventBus().emit('direct_chat_activity_updated');
    });
  }

  /// Get conversation info (including mute status)
  Future<Conversation?> _getConversationInfo(String conversationId) async {
    try {
      final chatService = ChatService();
      final conversations = await chatService.getConversations();
      final conversation = conversations.firstWhere(
        (c) => c.id == conversationId,
        orElse: () => throw Exception('Conversation not found'),
      );
      return conversation;
    } catch (e) {
      debugPrint('⚠️ [MainShell] Error getting conversation info: $e');
      return null;
    }
  }

  /// Get message preview text
  String _getMessagePreview(DirectMessage message) {
    if (message.isDeleted == true) {
      return 'Tin nhắn đã bị xóa';
    }
    
    if (message.messageType == 'IMAGE') {
      return '📷 Đã gửi một hình ảnh';
    }
    
    if (message.messageType == 'FILE') {
      return '📎 Đã gửi một tệp';
    }

    if (message.messageType == 'AUDIO') {
      return '🎤 Đã gửi một tin nhắn thoại';
    }
    
    if (message.content != null && message.content!.isNotEmpty) {
      final content = message.content!;
      if (content.length > 100) {
        return content.substring(0, 100) + '...';
      }
      return content;
    }
    
    return 'Tin nhắn mới';
  }

  /// Navigate to direct chat screen
  void _navigateToDirectChat(String conversationId, String participantName) {
    if (!mounted) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DirectChatScreen(
          conversationId: conversationId,
          otherParticipantName: participantName,
        ),
      ),
    );
  }

  /// Subscribe to all group chat conversations for realtime notifications
  Future<void> _subscribeToGroupChatConversations() async {
    try {
      if (_stompClient == null) {
        debugPrint('⚠️ [MainShell] StompClient not connected, cannot subscribe to group chat');
        return;
      }

      // Load all groups
      final chatService = ChatService();
      final groupsResponse = await chatService.getMyGroups(page: 0, size: 100);
      final groups = groupsResponse.content;
      
      if (groups.isEmpty) {
        debugPrint('ℹ️ [MainShell] No group chats to subscribe to');
        return;
      }

      debugPrint('📡 [MainShell] Subscribing to ${groups.length} group chat conversations');

      // Track new groups to subscribe
      final newGroupIds = groups.map((g) => g.id).toSet();
      
      // Unsubscribe from groups that no longer exist
      final toUnsubscribe = _subscribedGroups.difference(newGroupIds);
      for (final groupId in toUnsubscribe) {
        _subscribedGroups.remove(groupId);
        debugPrint('🔄 [MainShell] Group $groupId no longer exists, will be unsubscribed on reconnect');
      }

      // Subscribe to each group topic (only if not already subscribed)
      for (final group in groups) {
        if (_subscribedGroups.contains(group.id)) {
          debugPrint('ℹ️ [MainShell] Already subscribed to group ${group.id}, skipping');
          continue;
        }

        final destination = '/topic/chat/${group.id}';
        
        _stompClient?.subscribe(
          destination: destination,
          headers: {'id': 'group-chat-${group.id}'},
          callback: (frame) {
            if (frame.body == null) return;
            try {
              final jsonData = json.decode(frame.body!);
              final type = jsonData['type'] as String?;
              
              if (type == 'NEW_MESSAGE' && jsonData['message'] != null) {
                final messageJson = jsonData['message'] as Map<String, dynamic>;
                final message = ChatMessage.fromJson(messageJson);
                
                // Handle incoming message - will show notification if user is not in chat screen
                _handleGroupChatMessage(message);
              }
            } catch (e) {
              debugPrint('❌ [MainShell] Error parsing group chat message: $e');
            }
          },
        );
        
        _subscribedGroups.add(group.id);
        debugPrint('✅ [MainShell] Subscribed to $destination');
      }

      // Listen for group updates (new groups added)
      // Only register listener once to avoid multiple listeners
      if (!_hasGroupChatListener) {
        AppEventBus().on('group_chat_activity_updated', (_) {
          // Reload groups and update subscriptions after a delay
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              _subscribeToGroupChatConversations();
            }
          });
        });
        
        // Listen for when user is viewing a group chat screen
        AppEventBus().on('viewing_group_chat', (groupId) {
          if (groupId is String) {
            _currentViewingGroupId = groupId;
            debugPrint('📱 [MainShell] User is viewing group chat: $groupId');
          }
        });
        
        // Listen for when user is no longer viewing a group chat screen
        AppEventBus().on('not_viewing_group_chat', (groupId) {
          if (groupId is String && _currentViewingGroupId == groupId) {
            _currentViewingGroupId = null;
            debugPrint('📱 [MainShell] User is no longer viewing group chat: $groupId');
          }
        });
        
        _hasGroupChatListener = true;
      }
    } catch (e) {
      debugPrint('❌ [MainShell] Error subscribing to group chat conversations: $e');
    }
  }

  /// Handle incoming group chat message and show notification banner
  /// Shows notification banner on ALL screens EXCEPT when user is currently in the group chat screen for this group
  /// This means notification will appear on: homescreen, marketplace, services, menu, or any other screen
  /// Only shows if the group is NOT muted
  void _handleGroupChatMessage(ChatMessage message) {
    if (!mounted) return;

    // Check if user is currently viewing this group chat in ChatScreen
    // If user is in the group chat screen, ChatScreen will handle the message display
    // and we don't need to show notification banner
    if (_currentViewingGroupId == message.groupId) {
      debugPrint('ℹ️ [MainShell] User is viewing group ${message.groupId}, skipping notification banner');
      // Still emit event to update group list
      AppEventBus().emit('group_chat_activity_updated');
      return;
    }

    // User is NOT in the group chat screen - check mute status and show notification banner on current screen (could be any screen)
    // Get group info to check mute status
    _getGroupInfo(message.groupId).then((group) {
      if (!mounted) return;

      // Check if group is muted
      final isMuted = group?.isMuted == true || 
          (group?.muteUntil != null && 
           group!.muteUntil!.isAfter(DateTime.now()));

      if (isMuted) {
        debugPrint('ℹ️ [MainShell] Group ${message.groupId} is muted, skipping notification banner');
        // Still emit event to update group list (for unread count)
        AppEventBus().emit('group_chat_activity_updated');
        return;
      }

      // Group is not muted - show notification banner
      final groupName = group?.name ?? 'Nhóm chat';
      String messagePreview = _getGroupMessagePreview(message);

      // Show realtime notification banner
      RealtimeNotificationBanner.show(
        context: context,
        title: groupName,
        subtitle: 'Chat nhóm',
        body: messagePreview,
        leading: const Icon(Icons.group, color: Colors.green),
        displayDuration: const Duration(seconds: 4),
        onTap: () {
          // Navigate to group chat screen
          _navigateToGroupChat(message.groupId, groupName);
        },
      );

      // Emit event to update group list (for unread count badge)
      AppEventBus().emit('group_chat_activity_updated');
    });
  }

  /// Get group info (including mute status)
  Future<ChatGroup?> _getGroupInfo(String groupId) async {
    try {
      final chatService = ChatService();
      final group = await chatService.getGroupById(groupId);
      return group;
    } catch (e) {
      debugPrint('⚠️ [MainShell] Error getting group info: $e');
      return null;
    }
  }

  /// Get message preview text for group chat
  String _getGroupMessagePreview(ChatMessage message) {
    if (message.isDeleted == true) {
      return 'Tin nhắn đã bị xóa';
    }
    
    if (message.messageType == 'IMAGE') {
      return '📷 Đã gửi một hình ảnh';
    }
    
    if (message.messageType == 'FILE') {
      return '📎 Đã gửi một tệp';
    }

    if (message.messageType == 'AUDIO') {
      return '🎤 Đã gửi một tin nhắn thoại';
    }
    
    if (message.content != null && message.content!.isNotEmpty) {
      final content = message.content!;
      if (content.length > 100) {
        return content.substring(0, 100) + '...';
      }
      return content;
    }
    
    return 'Tin nhắn mới';
  }

  /// Navigate to group chat screen
  void _navigateToGroupChat(String groupId, String groupName) {
    if (!mounted) return;
    
    // Set current viewing group ID
    _currentViewingGroupId = groupId;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(groupId: groupId),
      ),
    ).then((_) {
      // Clear current viewing group ID when user navigates away
      _currentViewingGroupId = null;
    });
  }

  void _setupMarketplaceEventListeners() {
    // Listen for requests to subscribe to post comments
    AppEventBus().on('subscribe_post_comments', (postId) {
      if (postId is String) {
        subscribeToPostComments(postId);
      }
    });
  }

  void _subscribeToNewsTopic() {
    _stompClient?.subscribe(
      destination: '/topic/news',
      headers: const {'id': 'news-topic'},
      callback: _handleNewsFrame,
    );
  }

  void _subscribeToNotificationTopics() {
    // Subscribe to global notification topic
    _stompClient?.subscribe(
      destination: '/topic/notifications',
      headers: const {'id': 'notifications-global'},
      callback: _handleNotificationFrame,
    );
    debugPrint('✅ Subscribed to /topic/notifications');

    // Subscribe to external notifications (for notifications without buildingId)
    _stompClient?.subscribe(
      destination: '/topic/notifications/external',
      headers: const {'id': 'notifications-external'},
      callback: _handleNotificationFrame,
    );
    debugPrint('✅ Subscribed to /topic/notifications/external');

    // Subscribe to building-specific notifications
    for (final buildingId in _userBuildingIds) {
      _stompClient?.subscribe(
        destination: '/topic/notifications/building/$buildingId',
        headers: {'id': 'notifications-building-$buildingId'},
        callback: _handleNotificationFrame,
      );
      debugPrint('✅ Subscribed to /topic/notifications/building/$buildingId');
    }

    // Subscribe to resident-specific notifications (for private notifications like card approvals)
    if (_userResidentId != null && _userResidentId!.isNotEmpty) {
      _stompClient?.subscribe(
        destination: '/topic/notifications/resident/$_userResidentId',
        headers: {'id': 'notifications-resident-$_userResidentId'},
        callback: _handleNotificationFrame,
      );
      debugPrint('✅ Subscribed to /topic/notifications/resident/$_userResidentId');
    } else {
      debugPrint('⚠️ Không có residentId, bỏ qua subscribe đến /topic/notifications/resident/{residentId}');
    }
  }

  void _subscribeToMarketplaceTopics() {
    // Subscribe to building-level marketplace posts
    for (final buildingId in _userBuildingIds) {
      _stompClient?.subscribe(
        destination: '/topic/marketplace/building/$buildingId/posts',
        headers: {'id': 'marketplace-building-$buildingId'},
        callback: _handleMarketplaceFrame,
      );
      debugPrint('✅ Subscribed to /topic/marketplace/building/$buildingId/posts');
    }
    
    // Subscribe to post stats updates for all visible posts
    // This will be done dynamically when posts are loaded
  }

  void subscribeToPostComments(String postId) {
    _stompClient?.subscribe(
      destination: '/topic/marketplace/post/$postId/comments',
      headers: {'id': 'marketplace-post-$postId-comments'},
      callback: _handleMarketplaceFrame,
    );
    debugPrint('✅ Subscribed to /topic/marketplace/post/$postId/comments');
  }

  void _handleMarketplaceFrame(StompFrame frame) {
    if (frame.body == null) return;
    try {
      final decoded = json.decode(frame.body!);
      final type = decoded['type'] as String?;
      final postId = decoded['postId'] as String?;
      final action = decoded['action'] as String?;
      
      debugPrint('🔔 [Marketplace WebSocket] Received: type=$type, postId=$postId, action=$action');
      
      // Emit event to update marketplace screen
      AppEventBus().emit('marketplace_update', decoded);
      
      // Also emit for comment updates
      if (type == 'NEW_COMMENT') {
        // Emit with full data including action for navigation
        AppEventBus().emit('new_comment', {
          'postId': postId,
          'data': decoded, // Include full decoded data with action, commentId, parentCommentId, etc.
        });
      }
    } catch (e) {
      debugPrint('⚠️ [Marketplace WebSocket] Error parsing frame: $e');
    }
  }
  
  Future<void> _handleMarketplaceCommentNotificationTap(Map<String, dynamic> data) async {
    try {
      final postId = data['postId']?.toString();
      final commentId = data['commentId']?.toString();
      
      if (postId == null || postId.isEmpty) {
        debugPrint('⚠️ [MainShell] No postId in marketplace comment notification');
        return;
      }
      
      debugPrint('🔔 [MainShell] Handling marketplace comment notification: postId=$postId, commentId=$commentId');
      
      // Fetch post from API
      final marketplaceService = MarketplaceService();
      final post = await marketplaceService.getPostById(postId);
      
      if (!mounted) return;
      
      // Navigate to post detail screen với commentId để scroll đến comment
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PostDetailScreen(
            post: post,
            scrollToCommentId: commentId, // Pass commentId để scroll đến comment
          ),
        ),
      );
      
      debugPrint('✅ [MainShell] Navigated to post detail screen with commentId: $commentId');
    } catch (e) {
      debugPrint('⚠️ [MainShell] Error handling marketplace comment notification: $e');
    }
  }

  void _handleNewsFrame(StompFrame frame) {
    if (frame.body == null) return;
    try {
      final decoded = json.decode(frame.body!);
      if (decoded is Map<String, dynamic>) {
        final data = Map<String, dynamic>.from(decoded);
        final eventType = _asString(data['type']) ?? '';
        if (eventType.isNotEmpty && !eventType.endsWith('_CREATED')) {
          return;
        }
        final newsId = _asString(data['newsId']) ?? _asString(data['newsUuid']);
        final dedupeKey = newsId != null
            ? 'news:$newsId'
            : 'news:${frame.headers['message-id'] ?? frame.body.hashCode}';
        if (!_markRealtimeKey(dedupeKey)) {
          return;
        }
        _showNotificationBanner(data);
        AppEventBus().emit('news_update', data);
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi parse bản tin realtime: $e');
    }
  }

  void _handleNotificationFrame(StompFrame frame) {
    debugPrint('🔔 [WebSocket] Received frame, body length: ${frame.body?.length ?? 0}');
    if (frame.body == null) {
      debugPrint('⚠️ [WebSocket] Frame body is null');
      return;
    }
    
    debugPrint('🔔 [WebSocket] Raw frame body: ${frame.body}');
    
    try {
      final decoded = json.decode(frame.body!);
      debugPrint('🔔 [WebSocket] Decoded data type: ${decoded.runtimeType}');
      debugPrint('🔔 [WebSocket] Decoded data: $decoded');
      
      if (decoded is Map<String, dynamic>) {
        final data = Map<String, dynamic>.from(decoded);
        final dedupeKeySource = _asString(data['notificationId']) ??
            _asString(data['id']) ??
            frame.headers['message-id']?.toString() ??
            frame.body.hashCode.toString();
        final eventType = _asString(data['eventType']) ?? _asString(data['action']) ?? 'NOTIFICATION_CREATED';
        final dedupeKey = 'notification:$eventType:$dedupeKeySource';
        
        debugPrint('🔔 [WebSocket] Parsed: eventType=$eventType, id=$dedupeKeySource');
        debugPrint('🔔 [WebSocket] Full data keys: ${data.keys.toList()}');
        
        if (!_markRealtimeKey(dedupeKey)) {
          debugPrint('ℹ️ Notification đã nhận trước đó, bỏ qua: $dedupeKey');
          return;
        }

        debugPrint('🔔 Received notification via WebSocket: eventType=$eventType, id=$dedupeKeySource');

        final shouldDisplay = _shouldDisplayNotification(data);
        debugPrint('🔔 [WebSocket] Should display: $shouldDisplay, scope: ${data['scope']}, targetBuildingId: ${data['targetBuildingId']}');
        
        if (!shouldDisplay) {
          debugPrint(
              'ℹ️ Bỏ qua thông báo không liên quan tới căn hộ của user.');
          return;
        }

        if (eventType == 'NOTIFICATION_DELETED') {
          AppEventBus().emit('notifications_update', data);
          AppEventBus().emit('notifications_refetch', data);
          // Also emit notifications_incoming to update count (decrease)
          AppEventBus().emit('notifications_incoming', data);
          return;
        }

        if (eventType == 'NOTIFICATION_UPDATED') {
          AppEventBus().emit('notifications_update', data);
          AppEventBus().emit('notifications_refetch', data);
          // Also emit notifications_incoming to update count
          AppEventBus().emit('notifications_incoming', data);
          return;
        }

        // Handle NOTIFICATION_CREATED or any other event type
        // Default to handling if eventType is empty or is NOTIFICATION_CREATED
        if (eventType.isEmpty || eventType == 'NOTIFICATION_CREATED') {
          _showNotificationBanner(data);
          AppEventBus().emit('notifications_update', data);
          AppEventBus().emit('notifications_incoming', data);
          debugPrint('✅ Emitted notifications_incoming event');
        } else {
          // For any other event type, still emit notifications_incoming to update count
          AppEventBus().emit('notifications_incoming', data);
          debugPrint('✅ Emitted notifications_incoming event for eventType: $eventType');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi parse notification realtime: $e');
      debugPrint('⚠️ Frame body: ${frame.body}');
    }
  }

  bool _shouldDisplayNotification(Map<String, dynamic> data) {
    final scope = _asString(data['scope'])?.toUpperCase();
    debugPrint('🔔 [WebSocket] Checking display: scope=$scope, userBuildingIds=${_userBuildingIds.toList()}');
    
    if (scope == 'EXTERNAL') {
      final target = _asString(data['targetBuildingId']);
      debugPrint('🔔 [WebSocket] EXTERNAL notification, targetBuildingId=$target');
      if (target == null || target.isEmpty) {
        debugPrint('🔔 [WebSocket] No targetBuildingId, should display: true');
        return true;
      }
      final shouldDisplay = _userBuildingIds.contains(target.toLowerCase());
      debugPrint('🔔 [WebSocket] Target building match: $shouldDisplay (target: $target, userBuildings: ${_userBuildingIds.toList()})');
      return shouldDisplay;
    }
    debugPrint('🔔 [WebSocket] Scope is not EXTERNAL, should display: true');
    return true;
  }

  bool _markRealtimeKey(String key) {
    if (_recentRealtimeKeys.contains(key)) {
      return false;
    }
    _recentRealtimeKeys.addLast(key);
    if (_recentRealtimeKeys.length > 32) {
      _recentRealtimeKeys.removeFirst();
    }
    return true;
  }

  void _showNotificationBanner(Map<String, dynamic> data) {
    if (!mounted) return;
    final eventType =
        _asString(data['eventType']) ?? _asString(data['type']) ?? '';
    final isNewsPayload = eventType.startsWith('NEWS_') ||
        data.containsKey('newsId') ||
        data.containsKey('newsUuid');

    final title = _asString(data['title']) ??
        (isNewsPayload ? 'Tin tức mới' : 'Thông báo mới');
    final subtitle = isNewsPayload
        ? (_asString(data['source']) ??
            _asString(data['category']) ??
            'Tin tức')
        : (_asString(data['notificationType']) ??
            _asString(data['type']) ??
            'Thông báo');

    final body = _asString(data['summary']) ??
        _asString(data['content']) ??
        _asString(data['message']) ??
        '';

    RealtimeNotificationBanner.show(
      context: context,
      title: title,
      subtitle: subtitle.toUpperCase(),
      body: body.isEmpty ? null : body,
      onTap: () => _handleNotificationTap(data),
    );
  }

  String? _asString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  void _handleNotificationTap(Map<String, dynamic> data) async {
    RealtimeNotificationBanner.dismiss();

    // Handle chat notifications
    final type = data['type']?.toString();
    if (type == 'groupMessage' || type == 'directMessage') {
      await _handleChatNotificationTap(data);
      return;
    }

    // Handle marketplace comment notifications
    if (type == 'MARKETPLACE_COMMENT') {
      await _handleMarketplaceCommentNotificationTap(data);
      return;
    }

    // Kiểm tra nếu là news notification
    final newsId = data['newsUuid'] ?? data['newsId'];
    if (newsId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewsDetailScreen(id: newsId.toString()),
        ),
      );
      return;
    }

    // Parse notification từ data
    try {
      final notificationId = data['notificationId']?.toString() ?? 
                             data['id']?.toString() ?? 
                             data['notification_id']?.toString();
      
      if (notificationId == null || notificationId.isEmpty) {
        // Nếu không có notification ID, mở notification screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const NotificationScreen(),
          ),
        );
        return;
      }

      // Tạo ResidentNotification từ data
      final createdAt = data['createdAt']?.toString() ?? 
                        DateTime.now().toUtc().toIso8601String();
      final updatedAt = data['updatedAt']?.toString() ?? createdAt;

      // For MARKETPLACE_COMMENT, postId is in data['postId'], not referenceId
      final notificationType = (data['notificationType'] ?? data['type'] ?? 'SYSTEM').toString();
      String? referenceId = data['referenceId']?.toString();
      
      // If type is MARKETPLACE_COMMENT, use postId from data as referenceId
      // và commentId vào actionUrl để NotificationRouter có thể sử dụng
      String? actionUrl = data['actionUrl']?.toString();
      if (notificationType == 'MARKETPLACE_COMMENT' && data['postId'] != null) {
        referenceId = data['postId']?.toString();
        // Build actionUrl với commentId nếu có
        final commentId = data['commentId']?.toString();
        if (commentId != null && commentId.isNotEmpty) {
          actionUrl = 'commentId=$commentId';
        }
      }

      final notification = ResidentNotification(
        id: notificationId,
        type: notificationType,
        title: data['title']?.toString() ?? 'Thông báo',
        message: data['message']?.toString() ?? 
                 data['body']?.toString() ?? 
                 '',
        scope: (data['scope'] ?? 'EXTERNAL').toString(),
        targetRole: data['targetRole']?.toString(),
        targetBuildingId: data['targetBuildingId']?.toString(),
        referenceId: referenceId,
        referenceType: data['referenceType']?.toString(),
        actionUrl: actionUrl,
        iconUrl: data['iconUrl']?.toString(),
        createdAt: DateTime.parse(createdAt),
        updatedAt: DateTime.parse(updatedAt),
        isRead: false,
        readAt: null,
      );

      // Sử dụng router để điều hướng
      await NotificationRouter.navigateToNotificationScreen(
        context: context,
        notification: notification,
        residentId: _userResidentId,
      );
    } catch (e) {
      debugPrint('⚠️ Lỗi khi xử lý notification tap: $e');
      // Fallback: mở notification screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const NotificationScreen(),
          ),
        );
      }
    }
  }

  Future<void> _handleChatNotificationTap(Map<String, dynamic> data) async {
    try {
      final type = data['type']?.toString();
      final chatId = data['chatId']?.toString();
      final groupId = data['groupId']?.toString();
      final conversationId = data['conversationId']?.toString();
      
      if (chatId == null) return;
      
      if (type == 'groupMessage' && groupId != null) {
        // Navigate to group chat
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(groupId: groupId),
            ),
          );
        }
      } else if (type == 'directMessage' && conversationId != null) {
        // Get conversation details to get other participant name
        try {
          final chatService = ChatService();
          final conversations = await chatService.getConversations();
          final conversation = conversations.firstWhere(
            (c) => c.id == conversationId,
            orElse: () => throw Exception('Conversation not found'),
          );
          
          final otherParticipantName = _userResidentId != null
              ? (conversation.getOtherParticipantName(_userResidentId!) ?? 'Người dùng')
              : (conversation.participant1Name ?? conversation.participant2Name ?? 'Người dùng');
          
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DirectChatScreen(
                  conversationId: conversationId,
                  otherParticipantName: otherParticipantName,
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint('⚠️ Error getting conversation details: $e');
          // Fallback: navigate with default name
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DirectChatScreen(
                  conversationId: conversationId,
                  otherParticipantName: data['senderName']?.toString() ?? 'Người dùng',
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error handling chat notification tap: $e');
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  void dispose() {
    _stompClient?.deactivate();
    directChatWebSocketService.disconnect();
    RealtimeNotificationBanner.dismiss();
    AppEventBus().clear();
    _pushSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final scaffold = Scaffold(
      extendBody: true,
      backgroundColor: theme.colorScheme.surface,
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: theme.brightness == Brightness.dark
                      ? AppColors.darkGlassLayerGradient()
                      : AppColors.glassLayerGradient(),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.12),
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14041A2E),
                      blurRadius: 24,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                child: NavigationBar(
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onItemTapped,
                  surfaceTintColor: Colors.transparent,
                  backgroundColor: Colors.transparent,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(CupertinoIcons.house),
                      selectedIcon: Icon(CupertinoIcons.house_fill),
                      label: 'Trang chủ',
                    ),
                    NavigationDestination(
                      icon: Icon(CupertinoIcons.qrcode),
                      selectedIcon: Icon(CupertinoIcons.qrcode_viewfinder),
                      label: 'Dịch vụ',
                    ),
                    NavigationDestination(
                      icon: Icon(CupertinoIcons.cart),
                      selectedIcon: Icon(CupertinoIcons.cart_fill),
                      label: 'Chợ cư dân',
                    ),
                    NavigationDestination(
                      icon: Icon(CupertinoIcons.square_grid_2x2),
                      selectedIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
                      label: 'Tiện ích',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    
    // Only wrap with PopScope on Android to handle back button
    if (Platform.isAndroid) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, dynamic result) async {
          if (didPop) {
            return;
          }
          
          // Check if there are any screens in the navigation stack
          final navigator = Navigator.of(context, rootNavigator: false);
          if (navigator.canPop()) {
            // There are screens to pop, allow normal back navigation
            navigator.pop();
            return;
          }
          
          // No screens to pop (at root - HomeScreen), show exit confirmation
          final shouldExit = await _showExitConfirmationDialog(context);
          if (shouldExit == true && mounted) {
            SystemNavigator.pop();
          }
        },
        child: scaffold,
      );
    }
    
    return scaffold;
  }

  /// Hiển thị dialog xác nhận thoát app với animation mượt
  Future<bool?> _showExitConfirmationDialog(BuildContext context) async {
    final theme = Theme.of(context);
    return showSmoothDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      barrierLabel: 'Đóng dialog xác nhận thoát',
      builder: (BuildContext context) {
        return PopScope(
          canPop: true,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.exit_to_app_rounded,
                      size: 32,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Title
                  Text(
                    'Thoát ứng dụng',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  // Content
                  Text(
                    'Bạn có chắc muốn thoát ứng dụng không?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop(false); // Ở lại
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          'Hủy',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop(true); // Thoát
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'Thoát',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

