import 'package:dio/dio.dart';
import 'token_storage.dart';
import 'auth_service.dart';
import 'api_client.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AdminApiClient {
  static const String LAN_HOST_IP = '192.168.100.33';
  static const String LOCALHOST_IP = 'localhost';
  static const int API_PORT = 8086;
  static const int TIMEOUT_SECONDS = 10;

  static const String HOST_IP = kIsWeb ? LOCALHOST_IP : LAN_HOST_IP;
  static final String BASE_URL = 'http://$HOST_IP:$API_PORT/api';

  static Dio createPublicDio() {
    final dio = Dio(BaseOptions(
      baseUrl: BASE_URL,
      connectTimeout: const Duration(seconds: TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));
    
    // Thêm logging cho public dio
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
    final storage = TokenStorage();
    
    final dio = Dio(BaseOptions(
      baseUrl: BASE_URL,
      connectTimeout: const Duration(seconds: TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));

    final authDio = Dio(BaseOptions(
      baseUrl: ApiClient.BASE_URL,
      connectTimeout: const Duration(seconds: TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
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
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
          print('🔑 AdminApiClient: Sending token in Authorization header');
        } else {
          print('⚠️ AdminApiClient: No token found in storage');
        }
        print('📤 AdminApiClient Request: ${options.method} ${options.uri}');
        print('📤 Headers: ${options.headers}');
        return handler.next(options);
      },
      onError: (err, handler) async {
        final options = err.requestOptions;
        
        if (err.response?.statusCode == 401) {
          final refreshToken = await _storage.readRefreshToken();
          
          if (refreshToken == null || isRefreshing) {
            return handler.next(err);
          }

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
            print('🔥 AdminApiClient REFRESH FAILED: $e');
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
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '$BASE_URL$path';
  }
}

