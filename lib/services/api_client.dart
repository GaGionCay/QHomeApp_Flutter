import 'dart:convert';
import 'package:http/http.dart' as http;
import 'secure_storage_util.dart';
import 'auth_service.dart';

class ApiClient {
  final String baseUrl = 'http://localhost:8080/api';
  final AuthService authService;

  ApiClient({required this.authService});

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

    if (method == 'GET') {
      response = await http.get(uri, headers: headers);
    } else {
      response = await http.post(uri, headers: headers, body: jsonEncode(body));
    }

    // Nếu 401 → refresh token
    if (response.statusCode == 401) {
      bool refreshed = await authService.refreshToken();
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
      }
    }

    return response;
  }
}
