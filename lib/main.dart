import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth/auth_provider.dart';
import 'auth/screens/login_screen.dart';
import 'home/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    Widget home;
    if (auth.isLoading) {
      home = const SplashScreen();
    } else {
      home = auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
    }

    return MaterialApp(
      title: 'QHomeBase App',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: home,
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
