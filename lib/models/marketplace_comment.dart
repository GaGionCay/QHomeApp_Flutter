import 'marketplace_post.dart';

class MarketplaceComment {
  final String id;
  final String postId;
  final String residentId;
  final String? parentCommentId; // Cho reply
  final String content;
  final MarketplaceResidentInfo? author;
  final List<MarketplaceComment> replies; // Nested replies
  final int replyCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;

  MarketplaceComment({
    required this.id,
    required this.postId,
    required this.residentId,
    this.parentCommentId,
    required this.content,
    this.author,
    required this.replies,
    required this.replyCount,
    required this.createdAt,
    this.updatedAt,
    required this.isDeleted,
  });

  factory MarketplaceComment.fromJson(Map<String, dynamic> json) {
    return MarketplaceComment(
      id: json['id']?.toString() ?? '',
      postId: json['postId']?.toString() ?? '',
      residentId: json['residentId']?.toString() ?? '',
      parentCommentId: json['parentCommentId']?.toString(),
      content: json['content'] ?? '',
      author: json['author'] != null
          ? MarketplaceResidentInfo.fromJson(json['author'])
          : null,
      replies: (json['replies'] as List<dynamic>?)
          ?.map((reply) => MarketplaceComment.fromJson(reply))
          .toList() ?? [],
      replyCount: json['replyCount'] ?? 0,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt']) 
          : null,
      isDeleted: json['isDeleted'] ?? json['deletedAt'] != null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'postId': postId,
      'residentId': residentId,
      'parentCommentId': parentCommentId,
      'content': content,
    };
  }

  bool get hasReplies => replies.isNotEmpty || replyCount > 0;
}

