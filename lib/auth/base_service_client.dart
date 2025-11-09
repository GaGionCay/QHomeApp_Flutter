import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'token_storage.dart';
import 'auth_service.dart';
import 'iam_api_client.dart';

class BaseServiceClient {
  static const String LAN_HOST_IP = '192.168.100.33';
  static const String LOCALHOST_IP = 'localhost';
  static const int BASE_SERVICE_PORT = 8081;
  static const int TIMEOUT_SECONDS = 10;

  static const String HOST_IP = kIsWeb ? LOCALHOST_IP : LAN_HOST_IP;
  static const String BASE_URL = 'http://$HOST_IP:$BASE_SERVICE_PORT/api';

  static Dio createPublicDio() {
    final dio = Dio(BaseOptions(
      baseUrl: BASE_URL,
      connectTimeout: const Duration(seconds: TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));

    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => print('🔍 BASE SERVICE API LOG: $obj'),
    ));

    return dio;
  }

  final Dio dio;
  final TokenStorage _storage;
  final AuthService _authService;
  bool isRefreshing = false;

  BaseServiceClient._(this.dio, this._storage, this._authService) {
    _setupInterceptors();
  }

  factory BaseServiceClient() {
    final storage = TokenStorage();
    
    final dio = Dio(BaseOptions(
      baseUrl: BASE_URL,
      connectTimeout: const Duration(seconds: TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));

    // Dùng iamDio từ IamApiClient để refresh token
    final iamDio = IamApiClient.createPublicDio();
    final authService = AuthService(iamDio, storage);

    return BaseServiceClient._(dio, storage, authService);
  }

  void _setupInterceptors() {
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => print('🔍 BASE SERVICE API LOG: $obj'),
    ));
    
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.readAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
          print('🔑 BaseServiceClient: Sending token in Authorization header');
        } else {
          print('⚠️ BaseServiceClient: No token found in storage');
        }
        print('📤 BaseServiceClient Request: ${options.method} ${options.uri}');
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
            
            // Refresh token qua iam-service
            await _authService.refreshToken();
            
            final newAccessToken = await _storage.readAccessToken();
            if (newAccessToken != null) {
              options.headers['Authorization'] = 'Bearer $newAccessToken';
              final clonedResponse = await dio.fetch(options);
              return handler.resolve(clonedResponse);
            }
          } on DioException catch (e) {
            print('🔥 BaseServiceClient REFRESH FAILED: $e');
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

