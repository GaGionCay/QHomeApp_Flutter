import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../login/login_screen.dart';
import 'token_storage.dart';
import 'api_client.dart';
import 'auth_service.dart';

class AuthProvider extends ChangeNotifier {
  late final ApiClient apiClient;
  late final AuthService authService;
  final TokenStorage storage = TokenStorage();

  bool _isAuthenticated = false;
  bool _isLoading = true;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    apiClient = await ApiClient.create();
    authService = AuthService(apiClient.dio, storage);

    final token = await storage.readAccessToken();

    if (token != null) {
      if (!JwtDecoder.isExpired(token)) {
        _isAuthenticated = true;
      } else {
        try {
          await authService.refreshToken();
          _isAuthenticated = true;
        } catch (_) {
          await storage.deleteAll();
          _isAuthenticated = false;
        }
      }
    } else {
      _isAuthenticated = false;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      await authService.login(email, password);
      _isAuthenticated = true;
      notifyListeners();
      return true;
    } catch (e) {
      _isAuthenticated = false;
      notifyListeners();
      return false;
    }
  }

Future<void> logout(BuildContext context) async {
  try {
    await authService.logout();
  } catch (e) {
  } finally {
    await storage.deleteAll();
    _isAuthenticated = false;
    notifyListeners();

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }
}

  Future<void> requestReset(String email) => authService.requestReset(email);
  Future<void> verifyOtp(String email, String otp) => authService.verifyOtp(email, otp);
  Future<void> confirmReset(String email, String otp, String newPassword) =>
      authService.confirmReset(email, otp, newPassword);
}
