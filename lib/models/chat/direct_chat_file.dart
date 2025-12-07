class DirectChatFile {
  final String id;
  final String conversationId;
  final String messageId;
  final String senderId;
  final String? senderName;
  final String fileName;
  final int fileSize;
  final String? fileType; // IMAGE, AUDIO, VIDEO, DOCUMENT (legacy)
  final String? mimeType; // Actual mime type from backend (e.g., image/jpeg, image/png)
  final String fileUrl;
  final DateTime createdAt;

  DirectChatFile({
    required this.id,
    required this.conversationId,
    required this.messageId,
    required this.senderId,
    this.senderName,
    required this.fileName,
    required this.fileSize,
    this.fileType,
    this.mimeType,
    required this.fileUrl,
    required this.createdAt,
  });

  /// Check if this file is an image based on mimeType
  bool get isImage {
    if (mimeType != null && mimeType!.isNotEmpty) {
      return mimeType!.startsWith('image/');
    }
    // Fallback to fileType if mimeType is not available
    return fileType == 'IMAGE';
  }

  factory DirectChatFile.fromJson(Map<String, dynamic> json) {
    return DirectChatFile(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversationId']?.toString() ?? '',
      messageId: json['messageId']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      senderName: json['senderName'],
      fileName: json['fileName'] ?? 'file',
      fileSize: (json['fileSize'] is int) 
          ? json['fileSize'] as int 
          : (json['fileSize'] is num) 
              ? (json['fileSize'] as num).toInt() 
              : (json['fileSize'] != null ? int.tryParse(json['fileSize'].toString()) ?? 0 : 0),
      fileType: json['fileType'],
      mimeType: json['mimeType'] ?? json['fileType'], // Backend now returns mimeType separately
      fileUrl: json['fileUrl'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'fileName': fileName,
      'fileSize': fileSize,
      'fileType': fileType,
      'mimeType': mimeType,
      'fileUrl': fileUrl,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class DirectChatFilePagedResponse {
  final List<DirectChatFile> content;
  final int currentPage;
  final int pageSize;
  final int totalElements;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;
  final bool first;
  final bool last;

  DirectChatFilePagedResponse({
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

  factory DirectChatFilePagedResponse.fromJson(Map<String, dynamic> json) {
    return DirectChatFilePagedResponse(
      content: (json['content'] as List<dynamic>?)
              ?.map((f) => DirectChatFile.fromJson(f))
              .toList() ??
          [],
      currentPage: json['currentPage'] ?? 0,
      pageSize: json['pageSize'] ?? 20,
      totalElements: json['totalElements'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      hasNext: json['hasNext'] ?? false,
      hasPrevious: json['hasPrevious'] ?? false,
      first: json['first'] ?? false,
      last: json['last'] ?? false,
    );
  }
}


