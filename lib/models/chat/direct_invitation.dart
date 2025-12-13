class DirectInvitation {
  final String id;
  final String conversationId;
  final String inviterId;
  final String? inviterName;
  final String inviteeId;
  final String? inviteeName;
  final String status; // PENDING, ACCEPTED, DECLINED (no longer EXPIRED - invitations don't expire)
  final String? initialMessage;
  final DateTime createdAt;
  final DateTime? expiresAt; // No longer used - invitations don't expire, only accept/decline changes status
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
    this.expiresAt, // Optional now since backend doesn't set it
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
          : null, // Backend no longer sets expiresAt - invitations don't expire
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
      'expiresAt': expiresAt?.toIso8601String(),
      'respondedAt': respondedAt?.toIso8601String(),
    };
  }

  // Invitations no longer expire - only accept/decline changes status
  bool get isExpired => false;
}


