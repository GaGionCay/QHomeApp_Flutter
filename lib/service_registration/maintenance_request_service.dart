import 'package:dio/dio.dart';

import '../auth/api_client.dart';

class MaintenanceRequestService {
  MaintenanceRequestService(this._client);

  final ApiClient _client;

  Future<void> createRequest({
    required String unitId,
    required String category,
    required String title,
    required String description,
    required String location,
    required String contactName,
    required String contactPhone,
    List<String>? attachments,
    DateTime? preferredDateTime,
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
      if (attachments != null && attachments.isNotEmpty) 'attachments': attachments,
      if (preferredDateTime != null)
        'preferredDatetime': preferredDateTime.toUtc().toIso8601String(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };

    try {
      await _client.dio.post('/maintenance-requests', data: payload);
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
}

