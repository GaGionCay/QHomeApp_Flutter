class ResidentNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final String scope;
  final String? targetRole;
  final String? targetBuildingId;
  final String? targetResidentId; // For private notifications (riêng tư)
  final String? referenceId;
  final String? referenceType;
  final String? actionUrl;
  final String? iconUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isRead;
  final DateTime? readAt;

  ResidentNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.scope,
    this.targetRole,
    this.targetBuildingId,
    this.targetResidentId,
    this.referenceId,
    this.referenceType,
    this.actionUrl,
    this.iconUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.isRead,
    this.readAt,
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
      targetResidentId: json['targetResidentId'],
      referenceId: json['referenceId'],
      referenceType: json['referenceType'],
      actionUrl: json['actionUrl'],
      iconUrl: json['iconUrl'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      isRead: json['read'] as bool? ?? false,
      readAt: json['readAt'] != null ? DateTime.parse(json['readAt']) : null,
    );
  }

  ResidentNotification copyWith({
    bool? isRead,
    DateTime? readAt,
  }) {
    return ResidentNotification(
      id: id,
      type: type,
      title: title,
      message: message,
      scope: scope,
      targetRole: targetRole,
      targetBuildingId: targetBuildingId,
      targetResidentId: targetResidentId,
      referenceId: referenceId,
      referenceType: referenceType,
      actionUrl: actionUrl,
      iconUrl: iconUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
    );
  }
}

