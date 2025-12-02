class DirectInvitation {
  final String id;
  final String conversationId;
  final String inviterId;
  final String? inviterName;
  final String inviteeId;
  final String? inviteeName;
  final String status; // PENDING, ACCEPTED, DECLINED, EXPIRED
  final String? initialMessage;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? respondedAt;

  DirectInvitation({
    required this.id,
    required this.conversationId,
    required this.inviterId,
    this.inviterName,
    required this.inviteeId,
    this.inviteeName,
    required this.status,
    this.initialMessage,
    required this.createdAt,
    required this.expiresAt,
    this.respondedAt,
  });

  factory DirectInvitation.fromJson(Map<String, dynamic> json) {
    return DirectInvitation(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversationId']?.toString() ?? '',
      inviterId: json['inviterId']?.toString() ?? '',
      inviterName: json['inviterName'],
      inviteeId: json['inviteeId']?.toString() ?? '',
      inviteeName: json['inviteeName'],
      status: json['status'] ?? 'PENDING',
      initialMessage: json['initialMessage'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : DateTime.now().add(const Duration(days: 7)),
      respondedAt: json['respondedAt'] != null
          ? DateTime.parse(json['respondedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'inviterId': inviterId,
      'inviterName': inviterName,
      'inviteeId': inviteeId,
      'inviteeName': inviteeName,
      'status': status,
      'initialMessage': initialMessage,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'respondedAt': respondedAt?.toIso8601String(),
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

