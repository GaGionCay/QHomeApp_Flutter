import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final authService = AuthService();
  final apiClient = ApiClient(authService: authService);
  authService.setApiClient(apiClient);

  runApp(MyApp(authService: authService));
}

class MyApp extends StatelessWidget {
  final AuthService authService;
  const MyApp({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resident App',
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
      home: LoginScreen(authService: authService),
    );
  }
}
