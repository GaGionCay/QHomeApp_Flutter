import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/api_client.dart';
import '../models/card_registration_summary.dart';

class CardRegistrationService {
  static const int _servicePort = 8083;

  final ApiClient apiClient;
  final Dio? _overriddenClient;

  CardRegistrationService(this.apiClient, {Dio? client}) : _overriddenClient = client;

  Future<Dio> _prepareClient() async {
    if (_overriddenClient != null) {
      return _overriddenClient!;
    }
    final baseUrl = ApiClient.buildServiceBase(port: _servicePort);
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
    ));
    dio.interceptors.add(LogInterceptor(
      request: false,
      responseBody: kDebugMode,
      requestHeader: false,
      responseHeader: false,
      error: true,
      logPrint: (obj) => debugPrint('🪪 CARD SERVICE: $obj'),
    ));
    return dio;
  }

  Future<List<CardRegistrationSummary>> getRegistrations({
    required String residentId,
    required String unitId,
  }) async {
    final client = await _prepareClient();
    final token = await apiClient.storage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      client.options.headers['Authorization'] = 'Bearer $token';
    } else {
      client.options.headers.remove('Authorization');
    }

    final response = await client.get(
      '/api/card-registrations',
      queryParameters: {
        'residentId': residentId,
        'unitId': unitId,
      },
    );

    if (response.statusCode != 200) {
      debugPrint('⚠️ [CardRegistrationService] API trả mã ${response.statusCode}');
      return [];
    }

    final body = response.data;
    final List<dynamic>? rawList;
    if (body is Map) {
      rawList = body['data'] as List<dynamic>?;
    } else if (body is List) {
      rawList = body;
    } else {
      rawList = const [];
    }

    if (rawList == null || rawList.isEmpty) {
      return [];
    }

    return rawList
        .map((item) => CardRegistrationSummary.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();
  }
}


