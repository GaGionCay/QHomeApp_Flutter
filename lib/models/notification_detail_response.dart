class NotificationDetailResponse {
  final String type;
  final String title;
  final String message;
  final String scope;
  final String? targetBuildingId;
  final String? actionUrl;
  final DateTime createdAt;

  NotificationDetailResponse({
    required this.type,
    required this.title,
    required this.message,
    required this.scope,
    this.targetBuildingId,
    this.actionUrl,
    required this.createdAt,
  });

  factory NotificationDetailResponse.fromJson(Map<String, dynamic> json) {
    return NotificationDetailResponse(
      type: json['type']?.toString() ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      scope: json['scope'] ?? '',
      targetBuildingId: json['targetBuildingId']?.toString(),
      actionUrl: json['actionUrl'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'title': title,
      'message': message,
      'scope': scope,
      'targetBuildingId': targetBuildingId,
      'actionUrl': actionUrl,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

