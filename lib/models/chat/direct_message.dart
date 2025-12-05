class DirectMessage {
  final String id;
  final String conversationId;
  final String? senderId;
  final String? senderName;
  final String? content;
  final String messageType; // TEXT, IMAGE, AUDIO, FILE, SYSTEM
  final String? imageUrl;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? localPath; // Local path of the file (for sender's uploaded file)
  final bool? isDownloaded; // Whether file is downloaded to public directory
  final String? fileType; // image, video, audio, document
  final String? fileExtension; // File extension (jpg, pdf, etc.)
  final String? replyToMessageId;
  final DirectMessage? replyToMessage;
  final bool isEdited;
  final bool isDeleted;
  final String? deleteType; // FOR_ME, FOR_EVERYONE, or null if not deleted
  final DateTime createdAt;
  final DateTime updatedAt;
  // Marketplace post fields (for MARKETPLACE_POST message type)
  final String? postId;
  final String? postTitle;
  final String? postThumbnailUrl;
  final double? postPrice;
  final String? deepLink;

  DirectMessage({
    required this.id,
    required this.conversationId,
    this.senderId,
    this.senderName,
    this.content,
    required this.messageType,
    this.imageUrl,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.localPath,
    this.isDownloaded,
    this.fileType,
    this.fileExtension,
    this.replyToMessageId,
    this.replyToMessage,
    required this.isEdited,
    required this.isDeleted,
    this.deleteType,
    required this.createdAt,
    required this.updatedAt,
    // Marketplace post fields
    this.postId,
    this.postTitle,
    this.postThumbnailUrl,
    this.postPrice,
    this.deepLink,
  });

  factory DirectMessage.fromJson(Map<String, dynamic> json) {
    return DirectMessage(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversationId']?.toString() ?? '',
      senderId: json['senderId']?.toString(),
      senderName: json['senderName'],
      content: json['content'],
      messageType: json['messageType'] ?? 'TEXT',
      imageUrl: json['imageUrl'],
      fileUrl: json['fileUrl'],
      fileName: json['fileName'],
      fileSize: json['fileSize'] is int
          ? json['fileSize']
          : json['fileSize'] is String
              ? int.tryParse(json['fileSize'])
              : null,
      mimeType: json['mimeType'],
      localPath: json['localPath'],
      isDownloaded: json['isDownloaded'],
      fileType: json['fileType'],
      fileExtension: json['fileExtension'],
      replyToMessageId: json['replyToMessageId']?.toString(),
      replyToMessage: json['replyToMessage'] != null
          ? DirectMessage.fromJson(json['replyToMessage'])
          : null,
      isEdited: json['isEdited'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
      deleteType: json['deleteType']?.toString(),
      // Marketplace post fields
      postId: json['postId']?.toString(),
      postTitle: json['postTitle']?.toString(),
      postThumbnailUrl: json['postThumbnailUrl']?.toString(),
      postPrice: json['postPrice'] != null 
          ? (json['postPrice'] is num ? json['postPrice'].toDouble() : double.tryParse(json['postPrice'].toString()))
          : null,
      deepLink: json['deepLink']?.toString(),
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
      'conversationId': conversationId,
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'messageType': messageType,
      'imageUrl': imageUrl,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'localPath': localPath,
      'isDownloaded': isDownloaded,
      'fileType': fileType,
      'fileExtension': fileExtension,
      'replyToMessageId': replyToMessageId,
      'replyToMessage': replyToMessage?.toJson(),
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'deleteType': deleteType,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      // Marketplace post fields
      'postId': postId,
      'postTitle': postTitle,
      'postThumbnailUrl': postThumbnailUrl,
      'postPrice': postPrice,
      'deepLink': deepLink,
    };
  }
}

class DirectMessagePagedResponse {
  final List<DirectMessage> content;
  final int currentPage;
  final int pageSize;
  final int totalElements;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;
  final bool first;
  final bool last;

  DirectMessagePagedResponse({
    required this.content,
    required this.currentPage,
    required this.pageSize,
    required this.totalElements,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrevious,
    required this.first,
    required this.last,
  });

  factory DirectMessagePagedResponse.fromJson(Map<String, dynamic> json) {
    return DirectMessagePagedResponse(
      content: (json['content'] as List<dynamic>?)
              ?.map((m) => DirectMessage.fromJson(m))
              .toList() ??
          [],
      currentPage: json['currentPage'] ?? 0,
      pageSize: json['pageSize'] ?? 25,
      totalElements: json['totalElements'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      hasNext: json['hasNext'] ?? false,
      hasPrevious: json['hasPrevious'] ?? false,
      first: json['first'] ?? false,
      last: json['last'] ?? false,
    );
  }
}

