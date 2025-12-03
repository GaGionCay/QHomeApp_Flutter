import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'device_token_repository.dart';
import 'event_bus.dart';

typedef NotificationTapCallback = void Function(RemoteMessage message);

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  DeviceTokenRepository? _deviceTokenRepository;

  final StreamController<RemoteMessage> _notificationClicks =
      StreamController.broadcast();

  Stream<RemoteMessage> get notificationClicks => _notificationClicks.stream;

  bool _initialized = false;
  AndroidNotificationChannel? _channel;
  String? _cachedToken;
  Future<String?> Function()? _residentIdProvider;
  Future<String?> Function()? _buildingIdProvider;
  Future<String?> Function()? _roleProvider;

  Future<void> initialize({
    required NotificationTapCallback onNotificationTap,
    required Future<String?> Function() residentIdProvider,
    required Future<String?> Function() buildingIdProvider,
    required Future<String?> Function() roleProvider,
  }) async {
    if (_initialized) return;

    await _setupLocalNotifications();
    await _messaging.setAutoInitEnabled(true);
    _deviceTokenRepository = DeviceTokenRepository();
    _residentIdProvider = residentIdProvider;
    _buildingIdProvider = buildingIdProvider;
    _roleProvider = roleProvider;

    // Foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // App in background → opened via notification
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _notificationClicks.add(message);
      onNotificationTap(message);
    });

    // App launched from terminated state via notification tap
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      Future.microtask(() {
        _notificationClicks.add(initialMessage);
        onNotificationTap(initialMessage);
      });
    }


    await _registerTokenWithServer();

    FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) async {
        _cachedToken = token;
        await _registerTokenWithServer(tokenOverride: token);
      },
    );

    _initialized = true;
  }

  Future<NotificationSettings> requestPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
    return settings;
  }

  Future<String?> getToken() => _messaging.getToken();

  Future<void> unregisterToken() async {
    if (_cachedToken == null || _deviceTokenRepository == null) return;
    try {
      await _deviceTokenRepository!.unregisterToken(_cachedToken!);
    } catch (_) {
      // ignore cleanup errors
    } finally {
      _cachedToken = null;
    }
  }

  Future<void> refreshRegistration() async {
    if (!_initialized) return;
    await _registerTokenWithServer();
  }

  Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidInit);

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload == null) return;
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          final message = RemoteMessage(data: data);
          _notificationClicks.add(message);
        } catch (_) {}
      },
    );

    _channel ??= const AndroidNotificationChannel(
      'qhome_resident_channel',
      'Thông báo QHome',
      description: 'Kênh thông báo realtime cho cư dân.',
      importance: Importance.high,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel!);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    
    // Handle chat notifications
    final type = data['type']?.toString();
    if (type == 'groupMessage' || type == 'directMessage') {
      _handleChatNotification(data);
    }

    final android = notification?.android;
    if (notification == null || android == null) return;

    final payload = jsonEncode(message.data);

    await _localNotifications.show(
      notification.hashCode,
      notification.title ?? 'Thông báo mới',
      notification.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel?.id ?? 'qhome_resident_channel',
          _channel?.name ?? 'Thông báo QHome',
          channelDescription: _channel?.description,
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'Thông báo QHome',
        ),
      ),
      payload: payload,
    );
  }

  void _handleChatNotification(Map<String, dynamic> data) {
    try {
      final type = data['type']?.toString();
      final chatId = data['chatId']?.toString();
      final groupId = data['groupId']?.toString();
      final conversationId = data['conversationId']?.toString();
      final unreadCountStr = data['unreadCount']?.toString();
      
      if (chatId == null) return;
      
      final unreadCount = unreadCountStr != null ? int.tryParse(unreadCountStr) ?? 0 : 0;
      
      // Emit event to update chat unreadCount
      AppEventBus().emit('chat_notification_received', {
        'type': type,
        'chatId': chatId,
        'groupId': groupId,
        'conversationId': conversationId,
        'unreadCount': unreadCount,
        'senderName': data['senderName']?.toString(),
        'excerptMessage': data['excerptMessage']?.toString(),
      });
      
      debugPrint('🔔 [FCM] Chat notification received: type=$type, chatId=$chatId, unreadCount=$unreadCount');
    } catch (e) {
      debugPrint('⚠️ [FCM] Error handling chat notification: $e');
    }
  }

  Future<void> _registerTokenWithServer({String? tokenOverride}) async {
    try {
      if (_deviceTokenRepository == null) return;
      final token = tokenOverride ?? await _messaging.getToken();
      if (token == null) {
        debugPrint('⚠️ Không nhận được FCM token (null).');
        return;
      }
      _cachedToken = token;
      final residentId =
          _residentIdProvider != null ? await _residentIdProvider!() : null;
      final buildingId =
          _buildingIdProvider != null ? await _buildingIdProvider!() : null;
      final role = _roleProvider != null ? await _roleProvider!() : null;

      await _deviceTokenRepository!.registerToken(
        token: token,
        residentId: residentId,
        buildingId: buildingId,
        role: role,
        platform:
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      );
      debugPrint('✅ FCM token registered with backend');
    } catch (e, stack) {
      debugPrint('⚠️ Không thể đăng ký FCM token: $e');
      debugPrint('$stack');
    }
  }
}

