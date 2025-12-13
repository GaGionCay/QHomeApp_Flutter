class GroupInvitationResponse {
  final String id;
  final String groupId;
  final String? groupName;
  final String inviterId;
  final String? inviterName;
  final String inviteePhone;
  final String? inviteeResidentId;
  final String status; // PENDING, ACCEPTED, DECLINED (no longer EXPIRED - invitations don't expire)
  final DateTime createdAt;
  final DateTime? expiresAt; // No longer used - invitations don't expire, only accept/decline changes status

  GroupInvitationResponse({
    required this.id,
    required this.groupId,
    this.groupName,
    required this.inviterId,
    this.inviterName,
    required this.inviteePhone,
    this.inviteeResidentId,
    required this.status,
    required this.createdAt,
    this.expiresAt, // Optional now since backend doesn't set it
  });

  factory GroupInvitationResponse.fromJson(Map<String, dynamic> json) {
    return GroupInvitationResponse(
      id: json['id']?.toString() ?? '',
      groupId: json['groupId']?.toString() ?? '',
      groupName: json['groupName'],
      inviterId: json['inviterId']?.toString() ?? '',
      inviterName: json['inviterName'],
      inviteePhone: json['inviteePhone'] ?? '',
      inviteeResidentId: json['inviteeResidentId']?.toString(),
      status: json['status'] ?? 'PENDING',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : null, // Backend no longer sets expiresAt - invitations don't expire
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'groupName': groupName,
      'inviterId': inviterId,
      'inviterName': inviterName,
      'inviteePhone': inviteePhone,
      'inviteeResidentId': inviteeResidentId,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  // Invitations no longer expire - only accept/decline changes status
  bool get isExpired => false;
}


