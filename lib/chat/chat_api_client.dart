import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import '../auth/api_client.dart';
import '../auth/auth_service.dart';
import '../auth/token_storage.dart';

class ChatApiClient {
  static String get baseUrl => ApiClient.buildServiceBase(
        path: '/api/chat',
      );

  /// Check if hostname is an ngrok URL
  static bool _isNgrokUrl(String hostname) {
    return hostname.contains('ngrok-free.dev') ||
           hostname.contains('ngrok-free.app') ||
           hostname.contains('ngrok.io') ||
           hostname.contains('ngrok.app');
  }

  final Dio dio;
  final TokenStorage _storage;
  final AuthService _authService;
  bool isRefreshing = false;

  ChatApiClient._(this.dio, this._storage, this._authService) {
    _setupInterceptors();
  }

  factory ChatApiClient() {
    assert(
      ApiClient.isInitialized,
      'ApiClient.ensureInitialized() must be awaited before creating clients.',
    );

    final storage = TokenStorage();
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: ApiClient.connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: ApiClient.receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: ApiClient.sendTimeoutSeconds),
    ));
    
    // Configure SSL certificate validation for development
    if (!kIsWeb && kDebugMode) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        // Allow bad certificates in debug mode (development only)
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          return true; // Accept all certificates in debug mode
        };
        return client;
      };
    }
    
    final authDio = Dio(BaseOptions(
      baseUrl: ApiClient.activeBaseUrl,
      connectTimeout: const Duration(seconds: ApiClient.connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: ApiClient.receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: ApiClient.sendTimeoutSeconds),
    ));
    
    // Configure SSL certificate validation for development
    if (!kIsWeb && kDebugMode) {
      (authDio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        // Allow bad certificates in debug mode (development only)
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          return true; // Accept all certificates in debug mode
        };
        return client;
      };
    }
    final authService = AuthService(authDio, storage);
    return ChatApiClient._(dio, storage, authService);
  }

  void _setupInterceptors() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.readAccessToken();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        final deviceId = await _storage.readDeviceId();
        if (deviceId != null) options.headers['X-Device-Id'] = deviceId;
        
        // Add ngrok-skip-browser-warning header for ngrok URLs
        final uri = options.uri;
        if (_isNgrokUrl(uri.host)) {
          options.headers['ngrok-skip-browser-warning'] = 'true';
        }
        
        return handler.next(options);
      },
      onError: (err, handler) async {
        final options = err.requestOptions;
        final statusCode = err.response?.statusCode;
        
        if (statusCode == 401) {
          final refreshToken = await _storage.readRefreshToken();
          if (refreshToken == null || isRefreshing) {
            await _storage.deleteSessionData();
            return handler.next(err);
          }
          try {
            isRefreshing = true;
            await _authService.refreshToken();
            final newAccessToken = await _storage.readAccessToken();
            if (newAccessToken != null) {
              options.headers['Authorization'] = 'Bearer $newAccessToken';
              final cloned = await dio.fetch(options);
              return handler.resolve(cloned);
            }
          } on DioException catch (e) {
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
}


