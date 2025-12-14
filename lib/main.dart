import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:provider/provider.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'auth/api_client.dart';
import 'auth/auth_provider.dart';
import 'auth/token_storage.dart';
import 'core/app_router.dart';
import 'core/push_notification_service.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

/// ==========================
/// CONFIG
/// ==========================

/// ❗ Firebase chỉ bật cho mobile
final bool enableFirebase = !Platform.isWindows;

/// ==========================
/// FIREBASE BACKGROUND HANDLER
/// ==========================

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!enableFirebase) return;

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseMessaging.instance.setAutoInitEnabled(true);

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
  final payload = jsonEncode(message.data);

  if (notification != null) {
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
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
  }
}

/// ==========================
/// MAIN
/// ==========================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// Firebase (Mobile only)
  if (enableFirebase) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );
  }

  await ApiClient.ensureInitialized();
  await _configurePreferredRefreshRate();

  final tokenStorage = TokenStorage();

  if (enableFirebase) {
    // await PushNotificationService.instance.initialize(
    //   onNotificationTap: _handleNotificationTap,
    //   residentIdProvider: tokenStorage.readResidentId,
    //   buildingIdProvider: tokenStorage.readBuildingId,
    //   roleProvider: tokenStorage.readRole,
    // );

    //await PushNotificationService.instance.requestPermissions();
  }

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

/// ==========================
/// NOTIFICATION TAP
/// ==========================

void _handleNotificationTap(RemoteMessage message) {
  // Điều hướng đã được xử lý trong router
}

/// ==========================
/// REFRESH RATE (ANDROID ONLY)
/// ==========================

Future<void> _configurePreferredRefreshRate() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  try {
    final modes = await FlutterDisplayMode.supported;
    if (modes.isEmpty) return;

    modes.sort((a, b) => b.refreshRate.compareTo(a.refreshRate));
    final preferred = modes.first;

    await FlutterDisplayMode.setPreferredMode(preferred);
  } catch (_) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {}
  }
}

/// ==========================
/// APP ROOT
/// ==========================

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
    );
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
