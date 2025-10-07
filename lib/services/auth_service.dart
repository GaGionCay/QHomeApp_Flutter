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

  Future<Map<String, dynamic>?> login(String email, String password) async {
    final response = await apiClient.post('/auth/login', body: {
      'email': email,
      'password': password,
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await SecureStorageUtil.write('accessToken', data['accessToken']);
      await SecureStorageUtil.write('refreshToken', data['refreshToken']);
      return data;
    }
    return null;
  }

  Future<bool> logout() async {
    final response = await apiClient.post('/auth/logout');
    if (response.statusCode == 200) {
      await SecureStorageUtil.deleteAll();
      return true;
    }
    return false;
  }

  Future<bool> refreshToken() async {
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
  }

  Future<bool> requestReset(String email) async {
    final response = await apiClient.post('/auth/request-reset', body: {'email': email});
    return response.statusCode == 200;
  }

  Future<bool> verifyOtp(String email, String otp) async {
    final response = await apiClient.post('/auth/verify-otp', body: {'email': email, 'otp': otp});
    return response.statusCode == 200;
  }

  Future<bool> confirmReset(String email, String otp, String newPassword) async {
    final response = await apiClient.post('/auth/confirm-reset', body: {
      'email': email,
      'otp': otp,
      'newPassword': newPassword,
    });
    return response.statusCode == 200;
  }
}
