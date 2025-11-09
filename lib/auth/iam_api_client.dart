import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class IamApiClient {
  static const String LAN_HOST_IP = '192.168.100.33';
  static const String LOCALHOST_IP = 'localhost';
  static const int IAM_API_PORT = 8088;
  static const int TIMEOUT_SECONDS = 10;

  static const String HOST_IP = kIsWeb ? LOCALHOST_IP : LAN_HOST_IP;
  static final String BASE_URL = 'http://$HOST_IP:$IAM_API_PORT/api';

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
      logPrint: (obj) => print('🔍 IAM API LOG: $obj'),
    ));

    return dio;
  }
}

