import 'package:dio/dio.dart';

import '../auth/customer_interaction_api_client.dart';

class CleaningRequestService {
  CleaningRequestService(CustomerInteractionApiClient apiClient) : _dio = apiClient.dio;

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
    String? paymentMethod,
  }) async {
    // Format content với tất cả thông tin
    final contentParts = <String>[];
    contentParts.add('Loại dịch vụ: $cleaningType');
    contentParts.add('Ngày dọn dẹp: ${cleaningDate.toIso8601String().split('T').first}');
    contentParts.add('Thời gian bắt đầu: ${startTime.inHours.toString().padLeft(2, '0')}:${(startTime.inMinutes % 60).toString().padLeft(2, '0')}');
    contentParts.add('Thời lượng: $durationHours giờ');
    contentParts.add('Địa điểm: $location');
    contentParts.add('Số điện thoại liên hệ: $contactPhone');
    if (extraServices != null && extraServices.isNotEmpty) {
      contentParts.add('Dịch vụ bổ sung: ${extraServices.join(', ')}');
    }
    if (paymentMethod != null && paymentMethod.trim().isNotEmpty) {
      contentParts.add('Phương thức thanh toán: $paymentMethod');
    }
    if (note != null && note.trim().isNotEmpty) {
      contentParts.add('Ghi chú: ${note.trim()}');
    }

    final title = 'Yêu cầu dọn dẹp - $cleaningType';
    final requestContent = contentParts.join('\n');

    final payload = {
      'title': title,
      'content': requestContent,
      'status': 'Pending', // Backend sẽ tự động set nếu không gửi
    };

    try {
      await _dio.post('/requests/createRequest', data: payload);
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
}

