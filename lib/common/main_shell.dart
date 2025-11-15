import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../core/event_bus.dart';
import '../home/home_screen.dart';
import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../news/news_detail_screen.dart';
import '../notifications/realtime_notification_banner.dart';
import '../notifications/notification_screen.dart';
import '../core/push_notification_service.dart';
import '../profile/profile_service.dart';
import 'service_category_screen.dart';
import '../theme/app_colors.dart';
import 'menu_screen.dart';

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
  StreamSubscription<RemoteMessage>? _pushSubscription;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _connectWebSocket();
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
      const MenuScreen(),
    ];
  }

  void _connectWebSocket() async {
    final token = await _api.storage.readAccessToken();
    if (token == null) {
      debugPrint('⚠️ Không có access token, bỏ qua kết nối WebSocket.');
      return;
    }

    await _prepareRealtimeContext();

    _stompClient = StompClient(
      config: StompConfig.sockJS(
        url: ApiClient.buildServiceBase(port: 8086, path: '/ws'),
        onConnect: (_) => _onStompConnected(),
        onStompError: (frame) =>
            debugPrint('❌ STOMP error: ${frame.body ?? frame.headers}'),
        onDisconnect: (_) => debugPrint('ℹ️ WebSocket disconnected'),
        onWebSocketError: (error) => debugPrint('❌ WS error: $error'),
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        reconnectDelay: const Duration(seconds: 5),
      ),
    );

    _stompClient?.activate();
  }

  Future<void> _prepareRealtimeContext() async {
    final Set<String> buildingIds = <String>{};
    try {
      final profile = await ProfileService(_api.dio).getProfile();

      final profileBuildingId = _asString(profile['buildingId']);
      if (profileBuildingId != null && profileBuildingId.isNotEmpty) {
        buildingIds.add(profileBuildingId.toLowerCase());
      }

      final defaultBuildingId = _asString(profile['defaultBuildingId']);
      if (defaultBuildingId != null && defaultBuildingId.isNotEmpty) {
        buildingIds.add(defaultBuildingId.toLowerCase());
      }
    } catch (e) {
      debugPrint('⚠️ Không lấy được profile cho realtime: $e');
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
        debugPrint('⚠️ Không lấy được danh sách căn hộ cho realtime: $e');
      }
    }

    _userBuildingIds = buildingIds;
    debugPrint('ℹ️ BuildingIds realtime: $_userBuildingIds');
  }

  void _onStompConnected() {
    debugPrint('✅ WebSocket connected');
    _subscribeToNewsTopic();
    _subscribeToNotificationTopics();
  }

  void _subscribeToNewsTopic() {
    _stompClient?.subscribe(
      destination: '/topic/news',
      headers: const {'id': 'news-topic'},
      callback: _handleNewsFrame,
    );
  }

  void _subscribeToNotificationTopics() {
    _stompClient?.subscribe(
      destination: '/topic/notifications',
      headers: const {'id': 'notifications-global'},
      callback: _handleNotificationFrame,
    );

    for (final buildingId in _userBuildingIds) {
      _stompClient?.subscribe(
        destination: '/topic/notifications/building/$buildingId',
        headers: {'id': 'notifications-building-$buildingId'},
        callback: _handleNotificationFrame,
      );
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
    if (frame.body == null) return;
    try {
      final decoded = json.decode(frame.body!);
      if (decoded is Map<String, dynamic>) {
        final data = Map<String, dynamic>.from(decoded);
        final dedupeKeySource = _asString(data['notificationId']) ??
            _asString(data['id']) ??
            frame.headers['message-id']?.toString() ??
            frame.body.hashCode.toString();
        final eventType = _asString(data['eventType']) ?? '';
        final dedupeKey = 'notification:$eventType:$dedupeKeySource';
        if (!_markRealtimeKey(dedupeKey)) {
          return;
        }

        if (!_shouldDisplayNotification(data)) {
          debugPrint(
              'ℹ️ Bỏ qua thông báo không liên quan tới căn hộ của user.');
          return;
        }

        if (eventType == 'NOTIFICATION_DELETED') {
          AppEventBus().emit('notifications_update', data);
          AppEventBus().emit('notifications_refetch', data);
          return;
        }

        if (eventType == 'NOTIFICATION_UPDATED') {
          AppEventBus().emit('notifications_update', data);
          AppEventBus().emit('notifications_refetch', data);
          return;
        }

        _showNotificationBanner(data);
        AppEventBus().emit('notifications_update', data);
        AppEventBus().emit('notifications_incoming', data);
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi parse notification realtime: $e');
    }
  }

  bool _shouldDisplayNotification(Map<String, dynamic> data) {
    final scope = _asString(data['scope'])?.toUpperCase();
    if (scope == 'EXTERNAL') {
      final target = _asString(data['targetBuildingId']);
      if (target == null || target.isEmpty) {
        return true;
      }
      return _userBuildingIds.contains(target.toLowerCase());
    }
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

  void _handleNotificationTap(Map<String, dynamic> data) {
    final newsId = data['newsUuid'] ?? data['newsId'];
    if (newsId != null) {
      RealtimeNotificationBanner.dismiss();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewsDetailScreen(id: newsId.toString()),
        ),
      );
      return;
    }

    RealtimeNotificationBanner.dismiss();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NotificationScreen(),
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  void dispose() {
    _stompClient?.deactivate();
    RealtimeNotificationBanner.dismiss();
    AppEventBus().clear();
    _pushSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
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
                    color: theme.colorScheme.outline.withOpacity(0.12),
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
  }
}
