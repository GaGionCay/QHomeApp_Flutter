import 'package:dio/dio.dart';

import '../auth/api_client.dart';

class CleaningRequestService {
  CleaningRequestService(this._client);

  final ApiClient _client;

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
    final payload = {
      'unitId': unitId,
      'cleaningType': cleaningType,
      'cleaningDate': cleaningDate.toIso8601String().split('T').first,
      'startTime':
          '${startTime.inHours.toString().padLeft(2, '0')}:${(startTime.inMinutes % 60).toString().padLeft(2, '0')}:00',
      'durationHours': durationHours,
      'location': location,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'contactPhone': contactPhone,
      if (extraServices != null && extraServices.isNotEmpty)
        'extraServices': extraServices,
      if (paymentMethod != null && paymentMethod.trim().isNotEmpty)
        'paymentMethod': paymentMethod.trim(),
    };

    try {
      await _client.dio.post('/cleaning-requests', data: payload);
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

