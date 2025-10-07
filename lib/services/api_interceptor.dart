import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'secure_storage_util.dart';

class ApiInterceptor {
  final String baseUrl = 'http://localhost:8080/api';
  final AuthService _authService = AuthService();

  Future<http.Response> get(String path) async {
    return _sendRequest('GET', path);
  }

  Future<http.Response> post(String path, {Map<String, dynamic>? body}) async {
    return _sendRequest('POST', path, body: body);
  }

  Future<http.Response> _sendRequest(String method, String path, {Map<String, dynamic>? body}) async {
    String? accessToken = await SecureStorageUtil.read('accessToken');
    final headers = {
      'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };

    final uri = Uri.parse('$baseUrl$path');
    http.Response response;

    // Gửi request lần đầu
    if (method == 'GET') {
      response = await http.get(uri, headers: headers);
    } else {
      response = await http.post(uri, headers: headers, body: jsonEncode(body));
    }

    // Nếu 401 → refresh token
    if (response.statusCode == 401) {
      bool refreshed = await _refreshToken();
      if (refreshed) {
        accessToken = await SecureStorageUtil.read('accessToken');
        final retryHeaders = {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        };
        if (method == 'GET') {
          response = await http.get(uri, headers: retryHeaders);
        } else {
          response = await http.post(uri, headers: retryHeaders, body: jsonEncode(body));
        }
      } else {
        // refresh token hết hạn → logout
        await _authService.logout();
      }
    }

    return response;
  }

  Future<bool> _refreshToken() async {
    final refreshToken = await SecureStorageUtil.read('refreshToken');
    if (refreshToken == null) return false;

    final response = await http.post(
      Uri.parse('$baseUrl/auth/refresh-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await SecureStorageUtil.write('accessToken', data['accessToken']);
      return true;
    }
    return false;
  }
}
