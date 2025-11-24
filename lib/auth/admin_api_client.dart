import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'api_client.dart';
import 'auth_service.dart';
import 'token_storage.dart';

class AdminApiClient {
  static const int apiPort = 8086;
  static const int timeoutSeconds = 10;

  // Note: buildServiceBase() already includes /api in the base URL
  static String get baseUrl =>
      ApiClient.buildServiceBase();

  static Dio createPublicDio() {
    assert(
      ApiClient.isInitialized || kIsWeb,
      'ApiClient.ensureInitialized() must be awaited before creating clients.',
    );

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
    ));
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => print('🔍 ADMIN PUBLIC API LOG: $obj'),
    ));
    return dio;
  }

  final Dio dio;
  final TokenStorage _storage;
  final AuthService _authService;
  bool isRefreshing = false;

  AdminApiClient._(this.dio, this._storage, this._authService) {
    _setupInterceptors();
  }

  factory AdminApiClient() {
    assert(
      ApiClient.isInitialized || kIsWeb,
      'ApiClient.ensureInitialized() must be awaited before creating clients.',
    );

    final storage = TokenStorage();
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
    ));
    final authDio = Dio(BaseOptions(
      baseUrl: ApiClient.activeBaseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
    ));
    final authService = AuthService(authDio, storage);
    return AdminApiClient._(dio, storage, authService);
  }

  void _setupInterceptors() {
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => print('🔍 ADMIN API LOG: $obj'),
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.readAccessToken();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        final deviceId = await _storage.readDeviceId();
        if (deviceId != null) options.headers['X-Device-Id'] = deviceId;
        
        // Add ngrok-skip-browser-warning header for ngrok URLs
        final uri = options.uri;
        if (uri.host.contains('ngrok') || uri.host.contains('ngrok-free.app')) {
          options.headers['ngrok-skip-browser-warning'] = 'true';
        }
        
        return handler.next(options);
      },
      onError: (err, handler) async {
        final options = err.requestOptions;
        if (err.response?.statusCode == 401) {
          final refreshToken = await _storage.readRefreshToken();
          if (refreshToken == null || isRefreshing) return handler.next(err);
          try {
            isRefreshing = true;
            await _authService.refreshToken();
            final newAccessToken = await _storage.readAccessToken();
            if (newAccessToken != null) {
              options.headers['Authorization'] = 'Bearer $newAccessToken';
              final clonedResponse = await dio.fetch(options);
              return handler.resolve(clonedResponse);
            }
          } on DioException catch (e) {
            await _storage.deleteAll();
            return handler.next(e);
          } finally {
            isRefreshing = false;
          }
        }
        return handler.next(err);
      },
    ));
  }

  String fileUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    // Note: buildServiceBase() already includes /api in the base URL
    return '${ApiClient.buildServiceBase()}$path';
  }
}
