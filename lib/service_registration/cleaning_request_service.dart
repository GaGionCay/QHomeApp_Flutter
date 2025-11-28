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

  Future<ServiceRequestPage<CleaningRequestSummary>> getMyRequests({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.get(
        '/cleaning-requests/my',
        queryParameters: {
          'limit': limit,
          'offset': offset,
        },
      );
      return parseServiceRequestPage(
        response.data,
        (json) => CleaningRequestSummary.fromJson(json),
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
            : 'Không thể tải danh sách yêu cầu dọn dẹp.',
      );
    }
  }

  Future<List<CleaningRequestSummary>> getPaidRequests() async {
    try {
      final response = await _dio.get('/cleaning-requests/my/paid');
      final data = response.data;
      if (data is List) {
        return data
            .map((json) => CleaningRequestSummary.fromJson(
                Map<String, dynamic>.from(json)))
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
            : 'Không thể tải danh sách yêu cầu dọn dẹp đã thanh toán.',
      );
    }
  }

  Future<void> cancelRequest(String requestId) async {
    try {
      await _dio.patch('/cleaning-requests/$requestId/cancel');
    } on DioException catch (dioErr) {
      final message = dioErr.response?.data is Map<String, dynamic>
          ? (dioErr.response?.data['message'] as String?)
          : dioErr.message;
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Không thể hủy yêu cầu dọn dẹp.',
      );
    }
  }

  Future<void> resendRequest(String requestId) async {
    try {
      await _dio.post('/cleaning-requests/$requestId/resend');
    } on DioException catch (dioErr) {
      final message = dioErr.response?.data is Map<String, dynamic>
          ? (dioErr.response?.data['message'] as String?)
          : dioErr.message;
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Không thể gửi lại yêu cầu dọn dẹp. Vui lòng thử lại sau.',
      );
    }
  }

  Future<CleaningRequestConfig> getConfig() async {
    try {
      final response = await _dio.get('/cleaning-requests/config');
      return CleaningRequestConfig.fromJson(response.data);
    } on DioException catch (dioErr) {
      final message = dioErr.response?.data is Map<String, dynamic>
          ? (dioErr.response?.data['message'] as String?)
          : dioErr.message;
      throw Exception(
        message?.isNotEmpty == true
            ? message
            : 'Không thể tải cấu hình yêu cầu dọn dẹp.',
      );
    }
  }

  String _formatStartTime(Duration startTime) {
    final hours = startTime.inHours.toString().padLeft(2, '0');
    final minutes = (startTime.inMinutes % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:00';
  }
}

class CleaningRequestConfig {
  final Duration reminderThreshold;
  final Duration resendCancelThreshold;
  final Duration noResendCancelThreshold;

  CleaningRequestConfig({
    required this.reminderThreshold,
    required this.resendCancelThreshold,
    required this.noResendCancelThreshold,
  });

  factory CleaningRequestConfig.fromJson(Map<String, dynamic> json) {
    return CleaningRequestConfig(
      reminderThreshold: Duration(
        seconds: json['reminderThresholdSeconds'] as int? ?? 18000, // Default 5 hours
      ),
      resendCancelThreshold: Duration(
        seconds: json['resendCancelThresholdSeconds'] as int? ?? 18000, // Default 5 hours
      ),
      noResendCancelThreshold: Duration(
        seconds: json['noResendCancelThresholdSeconds'] as int? ?? 21600, // Default 6 hours
      ),
    );
  }
}
