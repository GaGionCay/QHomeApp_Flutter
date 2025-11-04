import 'package:dio/dio.dart';

import '../auth/admin_api_client.dart';
import '../models/resident_news.dart';
import '../models/resident_notification.dart';

class ResidentService {
  final AdminApiClient _apiClient;
  final _publicDio = AdminApiClient.createPublicDio();

  ResidentService() : _apiClient = AdminApiClient();

  Future<List<ResidentNews>> getResidentNews(String residentId) async {
    try {
      final response = await _publicDio.get(
        '/news/resident',
        queryParameters: {'residentId': residentId},
      );
      
      if (response.data is List) {
        return (response.data as List)
            .map((json) => ResidentNews.fromJson(json))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ Lỗi lấy resident news: $e');
      rethrow;
    }
  }

  Future<List<ResidentNotification>> getResidentNotifications(
    String residentId,
    String buildingId,
  ) async {
    try {
      print('🔍 [ResidentService] Gọi API notifications với residentId=$residentId, buildingId=$buildingId');
      final response = await _publicDio.get(
        '/notifications/resident',
        queryParameters: {
          'residentId': residentId,
          'buildingId': buildingId,
        },
      );
      
      print('🔍 [ResidentService] Response status: ${response.statusCode}');
      print('🔍 [ResidentService] Response data type: ${response.data.runtimeType}');
      print('🔍 [ResidentService] Response data: ${response.data}');
      
      if (response.data is List) {
        final list = (response.data as List)
            .map((json) => ResidentNotification.fromJson(json))
            .toList();
        print('✅ [ResidentService] Parsed ${list.length} notifications');
        return list;
      }
      
      print('⚠️ [ResidentService] Response không phải List, trả về empty list');
      return [];
    } catch (e) {
      print('❌ [ResidentService] Lỗi lấy resident notifications: $e');
      if (e is DioException) {
        print('❌ [ResidentService] DioException status: ${e.response?.statusCode}');
        print('❌ [ResidentService] DioException data: ${e.response?.data}');
      }
      rethrow;
    }
  }
}

