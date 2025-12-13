import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'api_client.dart';

class IamApiClient {
  // All requests go through API Gateway (port 8989)
  // Gateway routes /api/iam/** to IAM service (8088)
  static const int timeoutSeconds = 10;

  /// Check if hostname is an ngrok URL
  static bool _isNgrokUrl(String hostname) {
    return hostname.contains('ngrok-free.dev') ||
           hostname.contains('ngrok-free.app') ||
           hostname.contains('ngrok.io') ||
           hostname.contains('ngrok.app');
  }

  static String get baseUrl =>
      ApiClient.buildServiceBase(path: '/api/iam');

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
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // Add ngrok-skip-browser-warning header for ngrok URLs
        final uri = options.uri;
        if (_isNgrokUrl(uri.host)) {
          options.headers['ngrok-skip-browser-warning'] = 'true';
        }
        return handler.next(options);
      },
    ));
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => print('🔍 IAM API LOG: $obj'),
    ));
    return dio;
  }

  final Dio dio;

  IamApiClient._(this.dio);

  factory IamApiClient() {
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
      logPrint: (obj) => print('🔍 IAM PRIVATE API LOG: $obj'),
    ));
    return IamApiClient._(dio);
  }
}

