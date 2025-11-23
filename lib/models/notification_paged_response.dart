import 'resident_notification.dart';

class NotificationPagedResponse {
  final List<ResidentNotification> content;
  final int currentPage;
  final int pageSize;
  final int totalElements;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;
  final bool isFirst;
  final bool isLast;

  NotificationPagedResponse({
    required this.content,
    required this.currentPage,
    required this.pageSize,
    required this.totalElements,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrevious,
    required this.isFirst,
    required this.isLast,
  });

  factory NotificationPagedResponse.fromJson(Map<String, dynamic> json) {
    return NotificationPagedResponse(
      content: (json['content'] as List<dynamic>?)
              ?.map((item) => ResidentNotification.fromJson(item as Map<String, dynamic>))
              .toList() ?? [],
      currentPage: json['currentPage'] ?? 0,
      pageSize: json['pageSize'] ?? 7,
      totalElements: json['totalElements'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      hasNext: json['hasNext'] ?? false,
      hasPrevious: json['hasPrevious'] ?? false,
      isFirst: json['isFirst'] ?? false,
      isLast: json['isLast'] ?? false,
    );
  }
}

