import 'group.dart';

class ChatMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String? senderName;
  final String? senderAvatar;
  final String? content;
  final String messageType; // TEXT, IMAGE, AUDIO, FILE, SYSTEM
  final String? imageUrl;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? replyToMessageId;
  final ChatMessage? replyToMessage;
  final bool isEdited;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    this.senderName,
    this.senderAvatar,
    this.content,
    required this.messageType,
    this.imageUrl,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.replyToMessageId,
    this.replyToMessage,
    required this.isEdited,
    required this.isDeleted,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      groupId: json['groupId']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      senderName: json['senderName'],
      senderAvatar: json['senderAvatar'],
      content: json['content'],
      messageType: json['messageType'] ?? 'TEXT',
      imageUrl: json['imageUrl'],
      fileUrl: json['fileUrl'],
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      mimeType: json['mimeType'],
      replyToMessageId: json['replyToMessageId']?.toString(),
      replyToMessage: json['replyToMessage'] != null
          ? ChatMessage.fromJson(json['replyToMessage'])
          : null,
      isEdited: json['isEdited'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
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
      'groupId': groupId,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'content': content,
      'messageType': messageType,
      'imageUrl': imageUrl,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'replyToMessageId': replyToMessageId,
      'replyToMessage': replyToMessage?.toJson(),
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class MessagePagedResponse {
  final List<ChatMessage> content;
  final int currentPage;
  final int pageSize;
  final int totalElements;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;
  final bool isFirst;
  final bool isLast;

  MessagePagedResponse({
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

  factory MessagePagedResponse.fromJson(Map<String, dynamic> json) {
    return MessagePagedResponse(
      content: (json['content'] as List<dynamic>?)
              ?.map((m) => ChatMessage.fromJson(m))
              .toList() ??
          [],
      currentPage: json['currentPage'] ?? 0,
      pageSize: json['pageSize'] ?? 20,
      totalElements: json['totalElements'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      hasNext: json['hasNext'] ?? false,
      hasPrevious: json['hasPrevious'] ?? false,
      isFirst: json['isFirst'] ?? false,
      isLast: json['isLast'] ?? false,
    );
  }
}

class GroupPagedResponse {
  final List<ChatGroup> content;
  final int currentPage;
  final int pageSize;
  final int totalElements;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;
  final bool isFirst;
  final bool isLast;

  GroupPagedResponse({
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

  factory GroupPagedResponse.fromJson(Map<String, dynamic> json) {
    return GroupPagedResponse(
      content: (json['content'] as List<dynamic>?)
              ?.map((g) => ChatGroup.fromJson(g))
              .toList() ??
          [],
      currentPage: json['currentPage'] ?? 0,
      pageSize: json['pageSize'] ?? 20,
      totalElements: json['totalElements'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      hasNext: json['hasNext'] ?? false,
      hasPrevious: json['hasPrevious'] ?? false,
      isFirst: json['isFirst'] ?? false,
      isLast: json['isLast'] ?? false,
    );
  }
}

