import 'package:dio/dio.dart';

import '../auth/admin_api_client.dart';
import '../models/resident_news.dart';
import '../models/resident_notification.dart';
import '../models/notification_detail_response.dart';

class ResidentService {
  final _publicDio = AdminApiClient.createPublicDio();

  ResidentService();

  Future<List<ResidentNews>> getResidentNews(
    String residentId, {
    int page = 0,
    int size = 10,
  }) async {
    try {
      print('🔍 [ResidentService] Gọi API với page=$page, size=$size');
      final response = await _publicDio.get(
        '/news/resident',
        queryParameters: {
          'residentId': residentId,
          'page': page,
          'size': size,
        },
      );
      print('🔍 [ResidentService] Response type: ${response.data.runtimeType}');

      if (response.data is Map && response.data['content'] != null) {
        final items = (response.data['content'] as List)
            .map((json) => ResidentNews.fromJson(json))
            .toList();
        print('✅ [ResidentService] Paginated response: ${items.length} items');
        return items;
      } else if (response.data is List) {
        final allItems = (response.data as List)
            .map((json) => ResidentNews.fromJson(json))
            .toList();

        print('ℹ️ [ResidentService] API trả về ${allItems.length} items');
        if (size >= 1000) {
          return allItems;
        }

        final startIndex = page * size;
        final endIndex = (startIndex + size).clamp(0, allItems.length);
        if (startIndex >= allItems.length) {
          print(
              '⚠️ [ResidentService] Start index $startIndex vượt quá tổng số items ${allItems.length}');
          return [];
        }

        final paginatedItems = allItems.sublist(startIndex, endIndex);
        print(
            '✅ [ResidentService] Paginated ở client: trang $page = ${paginatedItems.length} items (từ $startIndex đến $endIndex)');
        return paginatedItems;
      }

      print(
          '⚠️ [ResidentService] Response format không hỗ trợ, trả về empty list');
      return [];
    } on DioException catch (e) {
      print('❌ Lỗi lấy resident news: ${e.message}');
      return [];
    } catch (e) {
      print('❌ Lỗi lấy resident news: $e');
      return [];
    }
  }

  /// Get total count of news items (for pagination)
  /// Returns null if API doesn't support count
  Future<int?> getResidentNewsCount(String residentId) async {
    try {
      final response = await _publicDio.get(
        '/news/resident',
        queryParameters: {
          'residentId': residentId,
          'page': 0,
          'size': 1,
        },
      );

      if (response.data is Map && response.data['totalElements'] != null) {
        final total = response.data['totalElements'] as int;
        print('✅ [ResidentService] Total từ API Page object: $total');
        return total;
      }

      if (response.data is List) {
        final fullResponse = await _publicDio.get(
          '/news/resident',
          queryParameters: {
            'residentId': residentId,
          },
        );

        if (fullResponse.data is List) {
          final total = (fullResponse.data as List).length;
          print('✅ [ResidentService] Total từ List response: $total');
          return total;
        }
      }

      return 0;
    } on DioException catch (e) {
      print('❌ Lỗi lấy total count: ${e.message}');
      return 0;
    } catch (e) {
      print('❌ Lỗi lấy total count: $e');
      return 0;
    }
  }

  Future<List<ResidentNotification>> getResidentNotifications(
    String residentId,
    String buildingId,
  ) async {
    try {
      print(
          '🔍 [ResidentService] Gọi API notifications với residentId=$residentId, buildingId=$buildingId');
      final response = await _publicDio.get(
        '/notifications/resident',
        queryParameters: {
          'residentId': residentId,
          'buildingId': buildingId,
        },
      );

      print('🔍 [ResidentService] Response status: ${response.statusCode}');
      print(
          '🔍 [ResidentService] Response data type: ${response.data.runtimeType}');
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
        print(
            '❌ [ResidentService] DioException status: ${e.response?.statusCode}');
        print('❌ [ResidentService] DioException data: ${e.response?.data}');
      }
      rethrow;
    }
  }

  Future<NotificationDetailResponse> getNotificationDetailById(
      String notificationId) async {
    try {
      print(
          '🔍 [ResidentService] Gọi API notification detail với id=$notificationId');
      final response = await _publicDio.get(
        '/notifications/$notificationId',
      );

      print('🔍 [ResidentService] Response status: ${response.statusCode}');
      print('🔍 [ResidentService] Response data: ${response.data}');

      if (response.data is Map) {
        final detail = NotificationDetailResponse.fromJson(
            response.data as Map<String, dynamic>);
        print('✅ [ResidentService] Parsed notification detail');
        return detail;
      }

      throw Exception('Invalid response format');
    } catch (e) {
      print('❌ [ResidentService] Lỗi lấy notification detail: $e');
      if (e is DioException) {
        print(
            '❌ [ResidentService] DioException status: ${e.response?.statusCode}');
        print('❌ [ResidentService] DioException data: ${e.response?.data}');
      }
      rethrow;
    }
  }
}
