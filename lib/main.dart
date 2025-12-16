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
import 'auth/backend_discovery_service.dart';
import 'core/app_config.dart';
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
  
  // Background message received - handled silently in production

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
      
      if (chatId != null) {
        // Extract unread count (though it won't be used in background handler)
        
        // Emit event to update chat unreadCount (if AppEventBus is available)
        // Note: Background handler runs in isolate, so we can't use AppEventBus directly
        // The event will be handled when app comes to foreground
        // Chat notification handled
      }
    } catch (e) {
      // Error handled silently
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
    
    // Notification displayed
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
    
    // Notification displayed (data payload)
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  await ApiClient.ensureInitialized();
  
  // DEBUG: Uncomment to clear tokens and force login (useful if token expired)
  // final tokenStorage = TokenStorage();
  // await tokenStorage.deleteSessionData();
  // print('🗑️ Cleared all session data - user will need to login again');
  
  // If manual ngrok URL is set in config, use it immediately
  if (AppConfig.manualNgrokUrl != null && AppConfig.manualNgrokUrl!.isNotEmpty) {
    try {
      final discoveryService = ApiClient.discoveryService;
      if (discoveryService != null) {
        final success = await discoveryService.setManualBackendUrl(AppConfig.manualNgrokUrl!);
        if (success) {
          print('✅ Using manual ngrok URL from config: ${AppConfig.manualNgrokUrl}');
          // Force refresh to use new URL
          ApiClient.forceRefreshDiscovery();
        } else {
          print('⚠️ Failed to set manual ngrok URL from config');
        }
      }
    } catch (e) {
      print('⚠️ Error setting manual ngrok URL: $e');
    }
  }
  
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
  // Notification tapped - handled by router
}

Future<void> _configurePreferredRefreshRate() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  try {
    // Lấy danh sách các refresh rate có sẵn
    final modes = await FlutterDisplayMode.supported;
    if (modes.isEmpty) {
      // No refresh rate supported
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
    // Refresh rate set successfully
  } catch (e) {
    // Error setting refresh rate - trying fallback
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (fallbackError) {
      // Fallback failed - handled silently
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

        // Không thể pop (đang ở màn hình root), hiển thị dialog xác nhận ngay lập tức
        final shouldExit = await _showExitConfirmationDialog(context);
        if (shouldExit == true && mounted) {
          // Thoát app
          SystemNavigator.pop();
        }
      },
      child: widget.child,
    );
  }

  /// Hiển thị dialog xác nhận thoát app
  Future<bool?> _showExitConfirmationDialog(BuildContext context) async {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
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
                    'Bạn có chắc chắn muốn thoát ứng dụng?',
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
                          Navigator.of(context).pop(false); // Không thoát
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

