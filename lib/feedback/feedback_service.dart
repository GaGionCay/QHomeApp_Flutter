import 'package:dio/dio.dart';

import '../auth/customer_interaction_api_client.dart';

class FeedbackRequest {
  FeedbackRequest({
    required this.id,
    required this.requestCode,
    required this.residentId,
    required this.residentName,
    required this.title,
    required this.content,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.updatedAt,
    this.imagePath,
  });

  final String id;
  final String requestCode;
  final String residentId;
  final String residentName;
  final String title;
  final String content;
  final String status;
  final String priority;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? imagePath;

  factory FeedbackRequest.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String? value) {
      if (value == null || value.isEmpty) return null;
      try {
        return DateTime.parse(value.replaceFirst(' ', 'T'));
      } catch (_) {
        return null;
      }
    }

    return FeedbackRequest(
      id: json['id']?.toString() ?? '',
      requestCode: json['requestCode']?.toString() ?? '',
      residentId: json['residentId']?.toString() ?? '',
      residentName: json['residentName']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      priority: json['priority']?.toString() ?? '',
      createdAt: parseDate(json['createdAt']?.toString()) ?? DateTime.now(),
      updatedAt: parseDate(json['updatedAt']?.toString()),
      imagePath: json['imagePath']?.toString(),
    );
  }
}

class FeedbackPage {
  FeedbackPage({
    required this.items,
    required this.pageNumber,
    required this.totalPages,
    required this.totalElements,
    required this.isLast,
  });

  final List<FeedbackRequest> items;
  final int pageNumber;
  final int totalPages;
  final int totalElements;
  final bool isLast;
}

class FeedbackService {
  FeedbackService(CustomerInteractionApiClient apiClient) : _dio = apiClient.dio;

  final Dio _dio;

  Future<FeedbackPage> getRequests({
    int page = 0,
    String? projectCode,
    String? title,
    String? status,
    String? priority,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final params = <String, dynamic>{
        'pageNo': page,
      };
      void addParam(String key, String? value) {
        if (value != null && value.isNotEmpty) {
          params[key] = value;
        }
      }

      addParam('projectCode', projectCode);
      addParam('title', title);
      addParam('status', status);
      addParam('priority', priority);
      addParam('dateFrom', dateFrom);
      addParam('dateTo', dateTo);

      final response = await _dio.get(
        '/requests',
        queryParameters: params,
      );

      final data = response.data as Map<String, dynamic>?
          ?? const <String, dynamic>{'content': <dynamic>[], 'totalElements': 0};
      final content = (data['content'] as List<dynamic>? ?? const [])
          .map((item) => FeedbackRequest.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList();

      final int totalElements = (data['totalElements'] as num?)?.toInt() ?? 0;
      final int totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
      final int pageNumber = (data['number'] as num?)?.toInt() ?? page;
      final bool isLast = data['last'] as bool? ?? true;

      return FeedbackPage(
        items: content,
        pageNumber: pageNumber,
        totalPages: totalPages,
        totalElements: totalElements,
        isLast: isLast,
      );
    } on DioException catch (e) {
      throw Exception(_extractError(e, 'Không thể tải danh sách phản ánh.'));
    }
  }

  Future<Map<String, int>> getCounts({
    String? projectCode,
    String? title,
    String? residentName,
    String? priority,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final params = <String, dynamic>{};
      void addParam(String key, String? value) {
        if (value != null && value.isNotEmpty) {
          params[key] = value;
        }
      }

      addParam('projectCode', projectCode);
      addParam('title', title);
      addParam('residentName', residentName);
      addParam('priority', priority);
      addParam('dateFrom', dateFrom);
      addParam('dateTo', dateTo);

      final response = await _dio.get(
        '/requests/counts',
        queryParameters: params.isEmpty ? null : params,
      );

      final raw = Map<String, dynamic>.from(response.data as Map);
      return raw.map((key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0));
    } on DioException catch (e) {
      throw Exception(_extractError(e, 'Không thể tải thống kê phản ánh.'));
    }
  }

  Future<FeedbackRequest> createRequest({
    required String title,
    required String content,
    required String priority,
    String status = 'PENDING',
    String? imagePath,
  }) async {
    try {
      final response = await _dio.post(
        '/requests/createRequest',
        data: <String, dynamic>{
          'title': title,
          'content': content,
          'priority': priority,
          'status': status,
          'imagePath': imagePath,
        },
      );
      return FeedbackRequest.fromJson(Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (e) {
      throw Exception(_extractError(e, 'Không thể gửi phản ánh.'));
    }
  }

  String _extractError(DioException error, String fallback) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    if (data is String && data.isNotEmpty) {
      return data;
    }
    return fallback;
  }
}
