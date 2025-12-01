class GroupFile {
  final String id;
  final String groupId;
  final String messageId;
  final String senderId;
  final String? senderName;
  final String? senderAvatar;
  final String fileName;
  final int fileSize;
  final String? fileType; // IMAGE, AUDIO, VIDEO, DOCUMENT (legacy)
  final String? mimeType; // Actual mime type from backend (e.g., image/jpeg, image/png)
  final String fileUrl;
  final DateTime createdAt;

  GroupFile({
    required this.id,
    required this.groupId,
    required this.messageId,
    required this.senderId,
    this.senderName,
    this.senderAvatar,
    required this.fileName,
    required this.fileSize,
    this.fileType,
    this.mimeType,
    required this.fileUrl,
    required this.createdAt,
  });

  /// Check if this file is an image based on mimeType
  bool get isImage {
    if (mimeType == null || mimeType!.isEmpty) {
      // Fallback to fileType if mimeType is not available
      return fileType == 'IMAGE';
    }
    return mimeType!.startsWith('image/');
  }

  factory GroupFile.fromJson(Map<String, dynamic> json) {
    return GroupFile(
      id: json['id']?.toString() ?? '',
      groupId: json['groupId']?.toString() ?? '',
      messageId: json['messageId']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      senderName: json['senderName'],
      senderAvatar: json['senderAvatar'],
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
      'groupId': groupId,
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'fileName': fileName,
      'fileSize': fileSize,
      'fileType': fileType,
      'fileUrl': fileUrl,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class GroupFilePagedResponse {
  final List<GroupFile> content;
  final int currentPage;
  final int pageSize;
  final int totalElements;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;
  final bool isFirst;
  final bool isLast;

  GroupFilePagedResponse({
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

  factory GroupFilePagedResponse.fromJson(Map<String, dynamic> json) {
    return GroupFilePagedResponse(
      content: (json['content'] as List<dynamic>?)
              ?.map((f) => GroupFile.fromJson(f))
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

