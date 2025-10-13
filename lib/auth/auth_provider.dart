import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'screens/login_screen.dart';
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
      // Nếu token chưa hết hạn
      if (!JwtDecoder.isExpired(token)) {
        _isAuthenticated = true;
      } else {
        // Nếu hết hạn -> thử refresh
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
    // Gọi API logout tới Spring Boot
    await authService.logout();
  } catch (e) {
    // Nếu lỗi (ví dụ mất mạng) vẫn tiếp tục logout local
  } finally {
    // Dù thế nào cũng xóa token local
    await storage.deleteAll();
    _isAuthenticated = false;
    notifyListeners();

    // Chuyển về LoginScreen và xóa toàn bộ navigation stack
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }
}


  // OTP helpers
  Future<void> requestReset(String email) => authService.requestReset(email);
  Future<void> verifyOtp(String email, String otp) => authService.verifyOtp(email, otp);
  Future<void> confirmReset(String email, String otp, String newPassword) =>
      authService.confirmReset(email, otp, newPassword);
}
