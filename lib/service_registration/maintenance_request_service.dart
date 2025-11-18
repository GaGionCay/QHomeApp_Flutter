import 'package:dio/dio.dart';

import '../auth/customer_interaction_api_client.dart';

class MaintenanceRequestService {
  MaintenanceRequestService(CustomerInteractionApiClient apiClient) : _dio = apiClient.dio;

  final Dio _dio;

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
    // Format content với tất cả thông tin
    final contentParts = <String>[];
    contentParts.add('Danh mục: $category');
    contentParts.add('Mô tả: $description');
    contentParts.add('Địa điểm: $location');
    contentParts.add('Người liên hệ: $contactName');
    contentParts.add('Số điện thoại: $contactPhone');
    if (preferredDateTime != null) {
      contentParts.add('Thời gian mong muốn: ${preferredDateTime.toIso8601String().replaceAll('T', ' ').substring(0, 16)}');
    }
    if (attachments != null && attachments.isNotEmpty) {
      contentParts.add('Số lượng file đính kèm: ${attachments.length}');
    }
    if (note != null && note.trim().isNotEmpty) {
      contentParts.add('Ghi chú: ${note.trim()}');
    }

    final requestTitle = title.trim().isNotEmpty ? title : 'Yêu cầu sửa chữa - $category';
    final requestContent = contentParts.join('\n');

    final payload = {
      'title': requestTitle,
      'content': requestContent,
      'status': 'Pending', // Backend sẽ tự động set nếu không gửi
      if (attachments != null && attachments.isNotEmpty && attachments.first.startsWith('data:'))
        'imagePath': attachments.first, // Nếu có ảnh, gửi ảnh đầu tiên
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
            : 'Không thể gửi yêu cầu sửa chữa. Vui lòng thử lại.',
      );
    }
  }
}

