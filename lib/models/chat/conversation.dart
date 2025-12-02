import 'direct_message.dart';

class Conversation {
  final String id;
  final String participant1Id;
  final String participant2Id;
  final String? participant1Name;
  final String? participant2Name;
  final String status; // PENDING, ACTIVE, BLOCKED, CLOSED
  final String createdBy;
  final DirectMessage? lastMessage;
  final int? unreadCount;
  final DateTime? lastReadAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.participant1Id,
    required this.participant2Id,
    this.participant1Name,
    this.participant2Name,
    required this.status,
    required this.createdBy,
    this.lastMessage,
    this.unreadCount,
    this.lastReadAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id']?.toString() ?? '',
      participant1Id: json['participant1Id']?.toString() ?? '',
      participant2Id: json['participant2Id']?.toString() ?? '',
      participant1Name: json['participant1Name'],
      participant2Name: json['participant2Name'],
      status: json['status'] ?? 'PENDING',
      createdBy: json['createdBy']?.toString() ?? '',
      lastMessage: json['lastMessage'] != null
          ? DirectMessage.fromJson(json['lastMessage'])
          : null,
      unreadCount: json['unreadCount'],
      lastReadAt: json['lastReadAt'] != null
          ? DateTime.parse(json['lastReadAt'])
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'participant1Id': participant1Id,
      'participant2Id': participant2Id,
      'participant1Name': participant1Name,
      'participant2Name': participant2Name,
      'status': status,
      'createdBy': createdBy,
      'lastMessage': lastMessage?.toJson(),
      'unreadCount': unreadCount,
      'lastReadAt': lastReadAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Get the other participant's ID
  String getOtherParticipantId(String currentUserId) {
    if (participant1Id == currentUserId) {
      return participant2Id;
    } else if (participant2Id == currentUserId) {
      return participant1Id;
    }
    throw Exception('User is not a participant in this conversation');
  }

  /// Get the other participant's name
  String? getOtherParticipantName(String currentUserId) {
    if (participant1Id == currentUserId) {
      return participant2Name;
    } else if (participant2Id == currentUserId) {
      return participant1Name;
    }
    return null;
  }
}

