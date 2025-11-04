class ResidentNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final String scope;
  final String? targetRole;
  final String? targetBuildingId;
  final String? referenceId;
  final String? referenceType;
  final String? actionUrl;
  final String? iconUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  ResidentNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.scope,
    this.targetRole,
    this.targetBuildingId,
    this.referenceId,
    this.referenceType,
    this.actionUrl,
    this.iconUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ResidentNotification.fromJson(Map<String, dynamic> json) {
    return ResidentNotification(
      id: json['id']?.toString() ?? '',
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      scope: json['scope'] ?? '',
      targetRole: json['targetRole'],
      targetBuildingId: json['targetBuildingId'],
      referenceId: json['referenceId'],
      referenceType: json['referenceType'],
      actionUrl: json['actionUrl'],
      iconUrl: json['iconUrl'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

