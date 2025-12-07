import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../auth/admin_api_client.dart';

class DeviceTokenRepository {
  DeviceTokenRepository() : _dio = AdminApiClient().dio;

  final Dio _dio;

  Future<void> registerToken({
    required String token,
    String? residentId,
    String? buildingId,
    String? role,
    String platform = 'android',
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final payload = {
      'token': token,
      'platform': platform,
      'appVersion': packageInfo.version,
      if (residentId != null) 'residentId': residentId,
      if (buildingId != null) 'buildingId': buildingId,
      if (role != null) 'role': role,
    };

    await _dio.post(
      '/notifications/device-tokens',
      data: payload,
    );
  }

  Future<void> unregisterToken(String token) async {
    await _dio.delete('/notifications/device-tokens/$token');
  }
}


