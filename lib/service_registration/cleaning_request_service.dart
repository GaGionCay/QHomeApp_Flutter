import 'package:dio/dio.dart';

import '../auth/api_client.dart';
import '../models/service_requests.dart';

class CleaningRequestService {
  CleaningRequestService(ApiClient apiClient) : _dio = apiClient.dio;

  final Dio _dio;

  Future<void> createRequest({
    required String unitId,
    required String cleaningType,
    required DateTime cleaningDate,
    required Duration startTime,
    required double durationHours,
    required String location,
    String? note,
    required String contactPhone,
    List<String>? extraServices,
  }) async {
    final payload = {
      'unitId': unitId,
      'cleaningType': cleaningType,
      'cleaningDate': cleaningDate.toIso8601String().split('T').first,
      'startTime': _formatStartTime(startTime),
      'durationHours': durationHours,
      'location': location,
      'note': note,
      'contactPhone': contactPhone,
      'extraServices': extraServices ?? const [],
      'paymentMethod': 'PAY_LATER',
    };

    try {
      await _dio.post('/cleaning-requests', data: payload);
    } on DioException catch (dioErr) {
      final message = dioErr.response?.data is Map<String, dynamic>
          ? (dioErr.response?.data['message'] as String?)
          : dioErr.message;
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Không thể gửi yêu cầu dọn dẹp. Vui lòng thử lại.',
      );
    }
  }

  Future<List<CleaningRequestSummary>> getMyRequests() async {
    try {
      final response = await _dio.get('/cleaning-requests/my');
      final data = response.data;
      if (data is List) {
        return data
            .map((item) => CleaningRequestSummary.fromJson(
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
            : 'Không thể tải danh sách yêu cầu dọn dẹp.',
      );
    }
  }

  String _formatStartTime(Duration startTime) {
    final hours = startTime.inHours.toString().padLeft(2, '0');
    final minutes = (startTime.inMinutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:00';
  }
}
