import 'package:dio/dio.dart';

import '../auth/api_client.dart';
import '../models/service_requests.dart';

class MaintenanceRequestService {
  MaintenanceRequestService(ApiClient apiClient) : _dio = apiClient.dio;

  final Dio _dio;

  Future<void> createRequest({
    required String unitId,
    required String category,
    required String title,
    required String description,
    required String location,
    required String contactName,
    required String contactPhone,
    required DateTime preferredDateTime,
    List<String>? attachments,
    String? note,
  }) async {
    final payload = {
      'unitId': unitId,
      'category': category,
      'title': title,
      'description': description,
      'location': location,
      'contactName': contactName,
      'contactPhone': contactPhone,
      'preferredDatetime': preferredDateTime.toUtc().toIso8601String(),
      'attachments': attachments ?? const [],
      'note': note,
    };

    try {
      await _dio.post('/maintenance-requests', data: payload);
    } on DioException catch (dioErr) {
      final message = dioErr.response?.data is Map<String, dynamic>
          ? (dioErr.response?.data['message'] as String?)
          : dioErr.message;
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Không thể gửi yêu cầu sửa chữa. Vui lòng thử lại.',
      );
    }
  }

  Future<ServiceRequestPage<MaintenanceRequestSummary>> getMyRequests({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        '/maintenance-requests/my',
        queryParameters: {
          'limit': limit,
          'offset': offset,
        },
      );
      return parseServiceRequestPage(
        response.data,
        (json) => MaintenanceRequestSummary.fromJson(json),
        limit: limit,
        offset: offset,
      );
    } on DioException catch (dioErr) {
      final message = dioErr.response?.data is Map<String, dynamic>
          ? (dioErr.response?.data['message'] as String?)
          : dioErr.message;
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Không thể tải danh sách yêu cầu sửa chữa.',
      );
    }
  }

  Future<void> cancelRequest(String requestId) async {
    try {
      await _dio.patch('/maintenance-requests/$requestId/cancel');
    } on DioException catch (dioErr) {
      final message = dioErr.response?.data is Map<String, dynamic>
          ? (dioErr.response?.data['message'] as String?)
          : dioErr.message;
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Không thể hủy yêu cầu sửa chữa.',
      );
    }
  }
}
