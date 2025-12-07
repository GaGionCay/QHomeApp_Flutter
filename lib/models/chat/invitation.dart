class GroupInvitationResponse {
  final String id;
  final String groupId;
  final String? groupName;
  final String inviterId;
  final String? inviterName;
  final String inviteePhone;
  final String? inviteeResidentId;
  final String status; // PENDING, ACCEPTED, DECLINED, EXPIRED
  final DateTime createdAt;
  final DateTime expiresAt;

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
    required this.expiresAt,
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
          : DateTime.now(),
    );
  }
}


