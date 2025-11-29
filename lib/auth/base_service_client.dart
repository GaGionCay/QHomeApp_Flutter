import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'api_client.dart';
import 'auth_service.dart';
import 'iam_api_client.dart';
import 'token_storage.dart';

class BaseServiceClient {
  // Note: All requests go through API Gateway (port 8989)
  // API Gateway routes /api/** to base-service (8081)
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
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        final deviceId = await _storage.readDeviceId();
        if (deviceId != null) options.headers['X-Device-Id'] = deviceId;
        return handler.next(options);
      },
      onError: (err, handler) async {
        final options = err.requestOptions;
        if (err.response?.statusCode == 401) {
          final refreshToken = await _storage.readRefreshToken();
          if (refreshToken == null || isRefreshing) {
            // Only delete session data, keep fingerprint credentials
            await _storage.deleteSessionData();
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
    // All requests go through API Gateway
    return '${ApiClient.buildServiceBase()}$path';
  }
}
