import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
          child: child!,
        );
      },
    );
  }
}
