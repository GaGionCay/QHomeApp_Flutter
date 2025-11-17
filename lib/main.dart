import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool isFirebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase đã khởi tạo thành công.');
    isFirebaseReady = true;

    final tokenStorage = TokenStorage();
    await PushNotificationService.instance.initialize(
      onNotificationTap: _handleNotificationTap,
      residentIdProvider: tokenStorage.readResidentId,
      buildingIdProvider: tokenStorage.readBuildingId,
      roleProvider: tokenStorage.readRole,
    );
    await PushNotificationService.instance.requestPermissions();
  } catch (e) {
    print('⚠️ Lỗi cấu hình Firebase (tạm bỏ qua): $e');
  }

  await ApiClient.ensureInitialized();
  await _configurePreferredRefreshRate();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: MyApp(isFirebaseReady: isFirebaseReady),
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
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (e, stack) {
    debugPrint('⚠️ Không thể đặt tần số quét cao: $e');
    debugPrint('$stack');
  }
}

class MyApp extends StatelessWidget {
  final bool isFirebaseReady;
  const MyApp({super.key, required this.isFirebaseReady});

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
    );
  }
}
