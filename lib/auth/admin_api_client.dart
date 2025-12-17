import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

import 'api_client.dart';
import 'auth_service.dart';
import 'backend_discovery_service.dart';
import 'token_storage.dart';

class AdminApiClient {
  static const int apiPort = 8086;
  // DEV LOCAL mode: Timeout configuration aligned with ApiClient
  static const int connectTimeoutSeconds = 10;
  static const int receiveTimeoutSeconds = 30;
  static const int sendTimeoutSeconds = 10;

  /// Check if hostname is an ngrok URL (no-op in DEV LOCAL mode)
  static bool _isNgrokUrl(String hostname) {
    // DEV LOCAL mode: Always return false - no ngrok URLs used
    return false;
  }

  // buildServiceBase() already includes /api in the base URL
  // But if called without path, it returns baseUrl + /api
  // So we use it directly for baseUrl
  static String get baseUrl =>
      ApiClient.buildServiceBase();

  static Dio createPublicDio() {
    assert(
      ApiClient.isInitialized || kIsWeb,
      'ApiClient.ensureInitialized() must be awaited before creating clients.',
    );

    final storage = TokenStorage();
    
    // DEV LOCAL mode: No ngrok headers needed
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: sendTimeoutSeconds),
    ));
    
    // Add authentication interceptor FIRST (before LogInterceptor) so headers are added before logging
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.readAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        final deviceId = await storage.readDeviceId();
        if (deviceId != null) options.headers['X-Device-Id'] = deviceId;
        
        // DEV LOCAL mode: No ngrok headers needed
        return handler.next(options);
      },
    ));
    
    // Production-ready: No LogInterceptor - errors logged only after final failure
    
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
    
    // DEV LOCAL mode: No ngrok headers needed
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: sendTimeoutSeconds),
    ));
    final authDio = Dio(BaseOptions(
      baseUrl: ApiClient.activeBaseUrl,
      connectTimeout: const Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: sendTimeoutSeconds),
    ));
    final authService = AuthService(authDio, storage);
    return AdminApiClient._(dio, storage, authService);
  }

  void _setupInterceptors() {
    // Production-ready: No LogInterceptor - errors logged only after final retry failure

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.readAccessToken();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        final deviceId = await _storage.readDeviceId();
        if (deviceId != null) options.headers['X-Device-Id'] = deviceId;
        
        // DEV LOCAL mode: No ngrok headers needed
        return handler.next(options);
      },
      onError: (err, handler) async {
        final options = err.requestOptions;
        
        // DEV LOCAL mode: No ngrok fallback, no retry loops
        // Errors are logged but connection is not changed
        
        // Log error only after final failure (production-ready)
        final uri = err.requestOptions.uri;
        if (err.response != null) {
          print('[AdminApiClient] HTTP ${err.response?.statusCode}: ${uri.path}');
        } else if (err.type == DioExceptionType.receiveTimeout || 
                   err.type == DioExceptionType.sendTimeout ||
                   err.type == DioExceptionType.connectionTimeout) {
          print('[AdminApiClient] Timeout: ${uri.path}');
        } else if (err.type == DioExceptionType.connectionError) {
          final baseUri = Uri.parse(baseUrl);
          print('[AdminApiClient] Connection failed: ${baseUri.host}:${baseUri.port}');
        }
        
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
            // Only delete session data, keep fingerprint credentials
            await _storage.deleteSessionData();
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

