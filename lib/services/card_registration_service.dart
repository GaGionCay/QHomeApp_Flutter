import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/api_client.dart';
import '../models/card_registration_summary.dart';

class CardRegistrationService {
  // All requests go through API Gateway (port 8989)
  // Gateway routes /api/card-registrations/** to services-card-service (8083)

  final ApiClient apiClient;
  final Dio? _overriddenClient;

  CardRegistrationService(this.apiClient, {Dio? client}) : _overriddenClient = client;

  Future<Dio> _prepareClient() async {
    if (_overriddenClient != null) {
      return _overriddenClient!;
    }
    // Use API Gateway - routes /api/card-registrations/** to services-card-service
    // Note: buildServiceBase() already includes /api in the base URL
    final baseUrl = ApiClient.buildServiceBase();
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
      receiveTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
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
      '/card-registrations',
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




