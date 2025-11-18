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

  Future<List<MaintenanceRequestSummary>> getMyRequests() async {
    try {
      final response = await _dio.get('/maintenance-requests/my');
      final data = response.data;
      if (data is List) {
        return data
            .map((item) => MaintenanceRequestSummary.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList();
      }
      throw Exception('Dữ liệu trả về không hợp lệ');
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
}
