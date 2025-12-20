import 'package:dio/dio.dart';

import '../auth/api_client.dart';

class CommonAreaMaintenanceRequestService {
  CommonAreaMaintenanceRequestService(ApiClient apiClient) : _dio = apiClient.dio;

  final Dio _dio;

  Future<Map<String, dynamic>> createRequest({
    String? buildingId,
    required String areaType,
    required String title,
    required String description,
    required String location,
    required String contactName,
    required String contactPhone,
    List<String>? attachments,
    String? note,
  }) async {
    final payload = {
      if (buildingId != null) 'buildingId': buildingId,
      'areaType': areaType,
      'title': title,
      'description': description,
      'location': location,
      'contactName': contactName,
      'contactPhone': contactPhone,
      'attachments': attachments ?? const [],
      if (note != null) 'note': note,
    };

    try {
      final response = await _dio.post('/common-area-maintenance-requests', data: payload);
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (dioErr) {
      final message = dioErr.response?.data is Map<String, dynamic>
          ? (dioErr.response?.data['message'] as String?)
          : dioErr.message;
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Không thể gửi yêu cầu bảo trì khu vực chung. Vui lòng thử lại.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getMyRequests() async {
    try {
      final response = await _dio.get('/common-area-maintenance-requests/my');
      final data = response.data;
      if (data is List) {
        return data
            .map((json) => Map<String, dynamic>.from(json))
            .toList();
      }
      return [];
    } on DioException catch (dioErr) {
      final message = dioErr.response?.data is Map<String, dynamic>
          ? (dioErr.response?.data['message'] as String?)
          : dioErr.message;
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Không thể tải danh sách yêu cầu bảo trì khu vực chung.',
      );
    }
  }

  // Removed approveResponse and rejectResponse - không cần resident approve/reject response nữa
  // Admin/Staff approve/deny trực tiếp, không cần resident xác nhận

  Future<void> cancelRequest(String requestId) async {
    try {
      await _dio.patch('/common-area-maintenance-requests/$requestId/cancel');
    } on DioException catch (dioErr) {
      final message = dioErr.response?.data is Map<String, dynamic>
          ? (dioErr.response?.data['message'] as String?)
          : dioErr.message;
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Không thể hủy yêu cầu bảo trì khu vực chung.',
      );
    }
  }
}
