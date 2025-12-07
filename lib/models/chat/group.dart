class ChatGroup {
  final String id;
  final String name;
  final String? description;
  final String createdBy;
  final String? createdByName;
  final String? buildingId;
  final String? buildingName;
  final String? avatarUrl;
  final int maxMembers;
  final int currentMemberCount;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<GroupMember>? members;
  final String? userRole;
  final int? unreadCount;
  final DateTime? muteUntil;
  final bool isMuted;

  ChatGroup({
    required this.id,
    required this.name,
    this.description,
    required this.createdBy,
    this.createdByName,
    this.buildingId,
    this.buildingName,
    this.avatarUrl,
    required this.maxMembers,
    required this.currentMemberCount,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.members,
    this.userRole,
    this.unreadCount,
    this.muteUntil,
    this.isMuted = false,
  });

  factory ChatGroup.fromJson(Map<String, dynamic> json) {
    return ChatGroup(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      createdBy: json['createdBy']?.toString() ?? '',
      createdByName: json['createdByName'],
      buildingId: json['buildingId']?.toString(),
      buildingName: json['buildingName'],
      avatarUrl: json['avatarUrl'],
      maxMembers: json['maxMembers'] ?? 30,
      currentMemberCount: json['currentMemberCount'] ?? 0,
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
      members: json['members'] != null
          ? (json['members'] as List)
              .map((m) => GroupMember.fromJson(m))
              .toList()
          : null,
      userRole: json['userRole'],
      unreadCount: json['unreadCount'],
      muteUntil: json['muteUntil'] != null
          ? DateTime.parse(json['muteUntil'])
          : null,
      isMuted: json['isMuted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'buildingId': buildingId,
      'buildingName': buildingName,
      'avatarUrl': avatarUrl,
      'maxMembers': maxMembers,
      'currentMemberCount': currentMemberCount,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'members': members?.map((m) => m.toJson()).toList(),
      'userRole': userRole,
      'unreadCount': unreadCount,
      'muteUntil': muteUntil?.toIso8601String(),
      'isMuted': isMuted,
    };
  }
}

class GroupMember {
  final String id;
  final String groupId;
  final String residentId;
  final String? residentName;
  final String? residentAvatar;
  final String role; // ADMIN, MODERATOR, MEMBER
  final DateTime joinedAt;
  final DateTime? lastReadAt;
  final bool isMuted;
  final DateTime? muteUntil;

  GroupMember({
    required this.id,
    required this.groupId,
    required this.residentId,
    this.residentName,
    this.residentAvatar,
    required this.role,
    required this.joinedAt,
    this.lastReadAt,
    required this.isMuted,
    this.muteUntil,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id']?.toString() ?? '',
      groupId: json['groupId']?.toString() ?? '',
      residentId: json['residentId']?.toString() ?? '',
      residentName: json['residentName'],
      residentAvatar: json['residentAvatar'],
      role: json['role'] ?? 'MEMBER',
      joinedAt: json['joinedAt'] != null
          ? DateTime.parse(json['joinedAt'])
          : DateTime.now(),
      lastReadAt: json['lastReadAt'] != null
          ? DateTime.parse(json['lastReadAt'])
          : null,
      isMuted: json['isMuted'] ?? false,
      muteUntil: json['muteUntil'] != null
          ? DateTime.parse(json['muteUntil'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'residentId': residentId,
      'residentName': residentName,
      'residentAvatar': residentAvatar,
      'role': role,
      'joinedAt': joinedAt.toIso8601String(),
      'lastReadAt': lastReadAt?.toIso8601String(),
      'isMuted': isMuted,
      'muteUntil': muteUntil?.toIso8601String(),
    };
  }
}


