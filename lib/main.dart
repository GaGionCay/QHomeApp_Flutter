import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:provider/provider.dart';

import 'auth/api_client.dart';
import 'auth/auth_provider.dart';
import 'core/app_router.dart';
import 'core/push_notification_service.dart';
import 'auth/token_storage.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'package:go_router/go_router.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseMessaging.instance.setAutoInitEnabled(true);
  
  debugPrint('🔔 Background message received: ${message.messageId}');
  debugPrint('   Title: ${message.notification?.title}');
  debugPrint('   Body: ${message.notification?.body}');
  debugPrint('   Data: ${message.data}');

  final FlutterLocalNotificationsPlugin localNotifications =
      FlutterLocalNotificationsPlugin();
  
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initializationSettings = InitializationSettings(android: androidInit);
  
  await localNotifications.initialize(initializationSettings);

  const channel = AndroidNotificationChannel(
    'qhome_resident_channel',
    'Thông báo QHome',
    description: 'Kênh thông báo realtime cho cư dân.',
    importance: Importance.high,
    playSound: true,
  );

  await localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Handle chat notifications
  final type = message.data['type']?.toString();
  if (type == 'groupMessage' || type == 'directMessage') {
    try {
      final chatId = message.data['chatId']?.toString();
      final unreadCountStr = message.data['unreadCount']?.toString();
      
      if (chatId != null) {
        final unreadCount = unreadCountStr != null ? int.tryParse(unreadCountStr) ?? 0 : 0;
        
        // Emit event to update chat unreadCount (if AppEventBus is available)
        // Note: Background handler runs in isolate, so we can't use AppEventBus directly
        // The event will be handled when app comes to foreground
        debugPrint('🔔 [FCM Background] Chat notification: type=$type, chatId=$chatId, unreadCount=$unreadCount');
      }
    } catch (e) {
      debugPrint('⚠️ [FCM Background] Error handling chat notification: $e');
    }
  }

  final notification = message.notification;
  if (notification != null) {
    final payload = jsonEncode(message.data);
    
    await localNotifications.show(
      notification.hashCode,
      notification.title ?? 'Thông báo mới',
      notification.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'Thông báo QHome',
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
    
    debugPrint('✅ Background notification displayed');
  } else if (message.data.isNotEmpty) {
    final title = message.data['title']?.toString() ?? 'Thông báo mới';
    final body = message.data['body']?.toString() ?? 
                 message.data['message']?.toString() ?? 
                 'Có thông báo mới';
    final payload = jsonEncode(message.data);
    
    await localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'Thông báo QHome',
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
    
    debugPrint('✅ Background notification displayed (data payload)');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  await ApiClient.ensureInitialized();
  await _configurePreferredRefreshRate();
  final tokenStorage = TokenStorage();

  await PushNotificationService.instance.initialize(
    onNotificationTap: _handleNotificationTap,
    residentIdProvider: tokenStorage.readResidentId,
    buildingIdProvider: tokenStorage.readBuildingId,
    roleProvider: tokenStorage.readRole,
  );
  await PushNotificationService.instance.requestPermissions();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: const MyApp(),
    ),
  );
}

void _handleNotificationTap(RemoteMessage message) {
  debugPrint('🔔 Notification tapped: ${message.data}');
}

Future<void> _configurePreferredRefreshRate() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  try {
    // Lấy danh sách các refresh rate có sẵn
    final modes = await FlutterDisplayMode.supported;
    if (modes.isEmpty) {
      debugPrint('⚠️ Không có refresh rate nào được hỗ trợ');
      return;
    }

    // Sắp xếp theo refresh rate giảm dần
    modes.sort((a, b) => b.refreshRate.compareTo(a.refreshRate));
    
    // Tìm refresh rate cao nhất (thường là 90Hz, 120Hz, hoặc 144Hz)
    // Ưu tiên 120Hz hoặc 90Hz nếu có, nếu không thì lấy cao nhất
    DisplayMode? preferredMode;
    
    // Ưu tiên 120Hz
    preferredMode = modes.firstWhere(
      (mode) => mode.refreshRate == 120,
      orElse: () => modes.first,
    );
    
    // Nếu không có 120Hz, thử 90Hz
    if (preferredMode.refreshRate != 120) {
      preferredMode = modes.firstWhere(
        (mode) => mode.refreshRate == 90,
        orElse: () => modes.first,
      );
    }
    
    // Set refresh rate đã chọn
    await FlutterDisplayMode.setPreferredMode(preferredMode);
    debugPrint('✅ Đã đặt refresh rate: ${preferredMode.refreshRate}Hz (${preferredMode.width}x${preferredMode.height})');
    
    // Log tất cả các mode có sẵn để debug
    debugPrint('📱 Các refresh rate có sẵn:');
    for (final mode in modes) {
      debugPrint('   - ${mode.refreshRate}Hz (${mode.width}x${mode.height})');
    }
  } catch (e, stack) {
    debugPrint('⚠️ Không thể đặt refresh rate: $e');
    debugPrint('$stack');
    
    // Fallback: thử set high refresh rate
    try {
      await FlutterDisplayMode.setHighRefreshRate();
      debugPrint('✅ Đã đặt high refresh rate (fallback)');
    } catch (fallbackError) {
      debugPrint('⚠️ Không thể đặt high refresh rate (fallback): $fallbackError');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();

    return MaterialApp.router(
      title: 'QHome Resident',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeController.themeMode,
      routerConfig: AppRouter.router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('vi', 'VN'),
      ],
      locale: const Locale('vi', 'VN'),
      // Tối ưu performance
      builder: (context, child) {
        // Wrap với MediaQuery để đảm bảo text scaling không ảnh hưởng performance
        return MediaQuery(
          // Giữ nguyên text scaling nhưng tối ưu
          data: MediaQuery.of(context).copyWith(
            // Giảm text scaling factor nếu quá lớn để tránh lag
            textScaler: MediaQuery.of(context).textScaler.clamp(
              minScaleFactor: 0.8,
              maxScaleFactor: 1.2,
            ),
          ),
          child: ExitConfirmationWrapper(child: child!),
        );
      },
    );
  }
}

/// Widget wrapper để xác nhận trước khi thoát app trên Android
class ExitConfirmationWrapper extends StatefulWidget {
  final Widget child;

  const ExitConfirmationWrapper({
    super.key,
    required this.child,
  });

  @override
  State<ExitConfirmationWrapper> createState() => _ExitConfirmationWrapperState();
}

class _ExitConfirmationWrapperState extends State<ExitConfirmationWrapper> {
  DateTime? _lastBackPressed;

  @override
  Widget build(BuildContext context) {
    // Chỉ áp dụng cho Android
    if (!Platform.isAndroid) {
      return widget.child;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) {
          return;
        }

        // Kiểm tra xem có thể pop không (tức là có màn hình trước đó)
        // Sử dụng GoRouter để kiểm tra
        final router = GoRouter.of(context);
        if (router.canPop()) {
          // Có màn hình trước đó, cho phép pop bình thường
          router.pop();
          return;
        }

        // Không thể pop (đang ở màn hình đầu tiên), hiển thị dialog xác nhận
        final now = DateTime.now();
        final shouldShowDialog = _lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2);

        if (shouldShowDialog) {
          _lastBackPressed = now;
          final shouldExit = await _showExitConfirmationDialog(context);
          if (shouldExit == true && mounted) {
            // Thoát app
            SystemNavigator.pop();
          }
        }
      },
      child: widget.child,
    );
  }

  /// Hiển thị dialog xác nhận thoát app
  Future<bool?> _showExitConfirmationDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Thoát ứng dụng',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Bạn có chắc chắn muốn thoát ứng dụng?',
            style: TextStyle(fontSize: 16),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // Không thoát
              },
              child: const Text(
                'Không',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true); // Thoát
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text(
                'Có',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
