import 'dart:convert';
import 'package:http/http.dart' as http;
import 'secure_storage_util.dart';
import 'api_client.dart';

class AuthService {
  late final ApiClient apiClient;

  AuthService();

  void setApiClient(ApiClient client) {
    apiClient = client;
  }

  Future<bool> refreshToken() async {
    try {
      final refreshToken = await SecureStorageUtil.read('refreshToken');
      if (refreshToken == null) return false;

      final response = await http.post(
        Uri.parse('http://localhost:8080/api/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await SecureStorageUtil.write('accessToken', data['accessToken']);
        return true;
      } else {
        await logout();
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<bool> logout() async {
    try {
      if (apiClient != null) {
        final response = await apiClient.post('/auth/logout');
        if (response.statusCode == 200) {
          await SecureStorageUtil.deleteAll();
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await apiClient.post('/auth/login', body: {
        'email': email.trim(),
        'password': password.trim(),
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await SecureStorageUtil.write('accessToken', data['accessToken']);
        await SecureStorageUtil.write('refreshToken', data['refreshToken']);
        return data;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> requestReset(String email) async {
    try {
      final response = await apiClient.post('/auth/request-reset', body: {'email': email.trim()});
      return response.statusCode == 200;
    } catch (_) {}
    return false;
  }

  Future<bool> verifyOtp(String email, String otp) async {
    try {
      final response = await apiClient.post('/auth/verify-otp', body: {'email': email.trim(), 'otp': otp.trim()});
      return response.statusCode == 200;
    } catch (_) {}
    return false;
  }

  Future<bool> confirmReset(String email, String otp, String newPassword) async {
    try {
      final response = await apiClient.post('/auth/confirm-reset', body: {
        'email': email.trim(),
        'otp': otp.trim(),
        'newPassword': newPassword.trim(),
      });
      return response.statusCode == 200;
    } catch (_) {}
    return false;
  }
}
