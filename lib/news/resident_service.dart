import 'package:dio/dio.dart';

import '../auth/admin_api_client.dart';
import '../models/resident_news.dart';
import '../models/news_paged_response.dart';
import '../models/resident_notification.dart';
import '../models/notification_detail_response.dart';
import '../models/notification_paged_response.dart';

class ResidentService {
  final _publicDio = AdminApiClient.createPublicDio();

  ResidentService();

  Future<NewsPagedResponse> getResidentNewsPaged(
    String residentId, {
    int page = 0,
    int size = 7,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'residentId': residentId,
        'page': page,
        'size': size,
      };

      if (dateFrom != null) {
        queryParams['dateFrom'] = dateFrom.toIso8601String();
      }
      if (dateTo != null) {
        queryParams['dateTo'] = dateTo.toIso8601String();
      }

      print('🔍 [ResidentService] Gọi API với residentId=$residentId, page=$page, size=$size, dateFrom=$dateFrom, dateTo=$dateTo');
      print('🔍 [ResidentService] Query params: $queryParams');
      final response = await _publicDio.get(
        '/news/resident',
        queryParameters: queryParams,
      );
      print('🔍 [ResidentService] Response status: ${response.statusCode}');
      print('🔍 [ResidentService] Response type: ${response.data.runtimeType}');
      print('🔍 [ResidentService] Response data: ${response.data}');

      if (response.data is Map && response.data['content'] != null) {
        // Paginated response from backend
        final pagedResponse = NewsPagedResponse.fromJson(response.data as Map<String, dynamic>);
        print('✅ [ResidentService] Paginated response: ${pagedResponse.content.length} items, page ${pagedResponse.currentPage + 1}/${pagedResponse.totalPages}');
        return pagedResponse;
      } else if (response.data is List) {
        // Legacy list response - convert to paged response
        var allItems = (response.data as List)
            .map((json) => ResidentNews.fromJson(json))
            .toList();

        if (dateFrom != null || dateTo != null) {
          allItems = allItems.where((news) {
            final newsDate = news.publishAt ?? news.createdAt;
            if (dateFrom != null) {
              final startDate = DateTime(dateFrom.year, dateFrom.month, dateFrom.day);
              final newsDateOnly = DateTime(newsDate.year, newsDate.month, newsDate.day);
              if (newsDateOnly.isBefore(startDate)) {
                return false;
              }
            }
            if (dateTo != null) {
              final endDate = DateTime(dateTo.year, dateTo.month, dateTo.day).add(const Duration(days: 1));
              final newsDateOnly = DateTime(newsDate.year, newsDate.month, newsDate.day);
              if (newsDateOnly.isAfter(endDate.subtract(const Duration(days: 1)))) {
                return false;
              }
            }
            return true;
          }).toList();
        }

        final totalElements = allItems.length;
        final totalPages = (totalElements / size).ceil();
        final startIndex = page * size;
        final endIndex = (startIndex + size).clamp(0, allItems.length);
        final paginatedItems = startIndex < allItems.length 
            ? allItems.sublist(startIndex, endIndex)
            : <ResidentNews>[];

        return NewsPagedResponse(
          content: paginatedItems,
          currentPage: page,
          pageSize: size,
          totalElements: totalElements,
          totalPages: totalPages,
          hasNext: page < totalPages - 1,
          hasPrevious: page > 0,
          isFirst: page == 0,
          isLast: page >= totalPages - 1 || totalPages == 0,
        );
      }

      print('⚠️ [ResidentService] Response format không hỗ trợ, trả về empty paged response');
      return NewsPagedResponse(
        content: [],
        currentPage: page,
        pageSize: size,
        totalElements: 0,
        totalPages: 0,
        hasNext: false,
        hasPrevious: false,
        isFirst: true,
        isLast: true,
      );
    } on DioException catch (e) {
      print('❌ Lỗi lấy resident news: ${e.message}');
      return NewsPagedResponse(
        content: [],
        currentPage: page,
        pageSize: size,
        totalElements: 0,
        totalPages: 0,
        hasNext: false,
        hasPrevious: false,
        isFirst: true,
        isLast: true,
      );
    } catch (e) {
      print('❌ Lỗi lấy resident news: $e');
      return NewsPagedResponse(
        content: [],
        currentPage: page,
        pageSize: size,
        totalElements: 0,
        totalPages: 0,
        hasNext: false,
        hasPrevious: false,
        isFirst: true,
        isLast: true,
      );
    }
  }

  // Backward compatibility method
  Future<List<ResidentNews>> getResidentNews(
    String residentId, {
    int page = 0,
    int size = 10,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final pagedResponse = await getResidentNewsPaged(
      residentId,
      page: page,
      size: size,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    return pagedResponse.content;
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
    String buildingId, {
    int page = 0,
    int limit = 20,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final pagedResponse = await getResidentNotificationsPaged(
      residentId,
      buildingId,
      page: page,
      size: limit,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    return pagedResponse.content;
  }

  /// Fetch all notifications across all pages (for counting unread)
  Future<List<ResidentNotification>> getAllResidentNotifications(
    String residentId,
    String buildingId, {
    DateTime? dateFrom,
    DateTime? dateTo,
    int maxPages = 100, // Limit to prevent infinite loops
  }) async {
    List<ResidentNotification> allNotifications = [];
    int currentPage = 0;
    bool hasMore = true;

    while (hasMore && currentPage < maxPages) {
      final pagedResponse = await getResidentNotificationsPaged(
        residentId,
        buildingId,
        page: currentPage,
        size: 7,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      allNotifications.addAll(pagedResponse.content);

      if (pagedResponse.hasNext && pagedResponse.content.isNotEmpty) {
        currentPage++;
      } else {
        hasMore = false;
      }
    }

    print('✅ [ResidentService] Fetched ${allNotifications.length} notifications across ${currentPage + 1} pages');
    return allNotifications;
  }

  Future<NotificationPagedResponse> getResidentNotificationsPaged(
    String residentId,
    String buildingId, {
    int page = 0,
    int size = 7, // Fixed size as per requirement
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      // Backend now gets residentId from authenticated user, so we don't send it
      final queryParams = <String, dynamic>{
        // 'residentId': residentId, // Removed - backend gets from authenticated user
        if (buildingId.isNotEmpty) 'buildingId': buildingId,
        'page': page,
        'size': size,
      };

      if (dateFrom != null) {
        queryParams['dateFrom'] = dateFrom.toIso8601String();
      }
      if (dateTo != null) {
        queryParams['dateTo'] = dateTo.toIso8601String();
      }

      print('🔍 [ResidentService] Gọi API notifications/resident với page=$page, size=$size, dateFrom=$dateFrom, dateTo=$dateTo');
      final response = await _publicDio.get(
        '/notifications/resident',
        queryParameters: queryParams,
      );

      print('🔍 [ResidentService] Response type: ${response.data.runtimeType}');

      if (response.data is Map) {
        final pagedResponse = NotificationPagedResponse.fromJson(response.data);
        print('✅ [ResidentService] Paginated response: ${pagedResponse.content.length} items, totalPages: ${pagedResponse.totalPages}');
        return pagedResponse;
      }

      print('⚠️ [ResidentService] Response format không hỗ trợ, trả về empty NotificationPagedResponse');
      return NotificationPagedResponse(
        content: [],
        currentPage: 0,
        pageSize: size,
        totalElements: 0,
        totalPages: 0,
        hasNext: false,
        hasPrevious: false,
        isFirst: true,
        isLast: true,
      );
    } catch (e) {
      print('❌ [ResidentService] Lỗi lấy resident notifications: $e');
      if (e is DioException) {
        print('❌ [ResidentService] DioException status: ${e.response?.statusCode}');
        print('❌ [ResidentService] DioException data: ${e.response?.data}');
      }
      rethrow;
    }
  }
  
  Future<int> getResidentNotificationsCount(
    String residentId,
    String buildingId, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      // Try the new count endpoint first
      try {
        // Backend now gets residentId from authenticated user, so we don't send it
        final queryParams = <String, dynamic>{
          // 'residentId': residentId, // Removed - backend gets from authenticated user
          if (buildingId.isNotEmpty) 'buildingId': buildingId,
        };

        final response = await _publicDio.get(
          '/notifications/resident/count',
          queryParameters: queryParams,
        );

        if (response.data is Map && response.data['totalCount'] != null) {
          final total = response.data['totalCount'] as int;
          print('✅ [ResidentService] Total notifications count from count endpoint: $total');
          
          // If date filters are provided, we need to get the full list and filter
          if (dateFrom != null || dateTo != null) {
            final allNotifications = await getAllResidentNotifications(
              residentId,
              buildingId,
              dateFrom: dateFrom,
              dateTo: dateTo,
            );
            return allNotifications.length;
          }
          
          return total;
        }
      } catch (countError) {
        print('⚠️ [ResidentService] Count endpoint failed, using paginated endpoint as fallback: $countError');
      }

      // Fallback: use paginated endpoint to get totalElements
      final pagedResponse = await getResidentNotificationsPaged(
        residentId,
        buildingId,
        page: 0,
        size: 7,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      
      if (dateFrom != null || dateTo != null) {
        // If date filters are provided, we need to get all notifications
        final allNotifications = await getAllResidentNotifications(
          residentId,
          buildingId,
          dateFrom: dateFrom,
          dateTo: dateTo,
        );
        return allNotifications.length;
      }
      
      print('✅ [ResidentService] Total notifications count from paginated endpoint: ${pagedResponse.totalElements}');
      return pagedResponse.totalElements;
    } catch (e) {
      print('❌ [ResidentService] Lỗi lấy count: $e');
      return 0;
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
