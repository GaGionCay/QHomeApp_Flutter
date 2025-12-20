import 'marketplace_post.dart';
import '../auth/api_client.dart';

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
  final String? imageUrl; // URL of image attached to comment
  final String? videoUrl; // URL of video attached to comment

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
      this.imageUrl,
      this.videoUrl,
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
      imageUrl: json['imageUrl'] != null ? _buildImageUrl(json['imageUrl']!.toString()) : null,
      videoUrl: json['videoUrl'] != null ? _normalizeVideoUrl(json['videoUrl']!.toString()) : null,
    );
  }

  // Helper to normalize video URL to absolute URL using API Gateway
  static String? _normalizeVideoUrl(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    
    // If URL is already absolute, return as-is
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    // Backend returns relative path: /api/videos/stream/{videoId}
    // Normalize it to use API Gateway base URL
    try {
      if (url.startsWith('/api/')) {
        // Remove /api prefix and prepend API Gateway base URL (which already includes /api)
        final apiGatewayBase = ApiClient.buildServiceBase();
        final pathWithoutApi = url.substring(4); // Remove /api prefix
        return '$apiGatewayBase$pathWithoutApi';
      } else if (url.startsWith('/')) {
        // Already relative but doesn't start with /api, prepend API Gateway base
        final apiGatewayBase = ApiClient.buildServiceBase();
        return '$apiGatewayBase$url';
      } else {
        // Not a valid URL format, try to construct from API Gateway
        final apiGatewayBase = ApiClient.buildServiceBase();
        return '$apiGatewayBase/$url';
      }
    } catch (e) {
      // If normalization fails, return original URL
      return url;
    }
  }

  // Helper to build absolute image/video URL
  static String _buildImageUrl(String url) {
    try {
      // If URL is already absolute (starts with http:// or https://), return as-is
      // This handles ImageKit URLs and other external URLs
      if (url.startsWith('http://') || url.startsWith('https://')) {
        print('🔗 [MarketplaceComment] URL is already absolute: $url');
        return url;
      }
      
      // Use ApiClient.activeFileBaseUrl if ApiClient is initialized
      // activeFileBaseUrl is http://host:port (without /api)
      // relativePath is like /api/marketplace/uploads/...
      // So we just concatenate them
      if (ApiClient.isInitialized) {
        final baseUrl = ApiClient.activeFileBaseUrl;
        // Ensure url starts with /
        final path = url.startsWith('/') ? url : '/$url';
        final fullUrl = '$baseUrl$path';
        print('🔗 [MarketplaceComment] Building URL: baseUrl=$baseUrl, path=$path, fullUrl=$fullUrl');
        return fullUrl;
      } else {
        // Fallback: construct from known pattern
        const host = 'localhost';
        const port = 8989;
        final path = url.startsWith('/') ? url : '/$url';
        return 'http://$host:$port$path';
      }
    } catch (e) {
      print('⚠️ [MarketplaceComment] Error in _buildImageUrl: $e');
      // If URL is already absolute, return as-is even on error
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return url;
      }
      // Fallback: assume localhost:8989
      final path = url.startsWith('/') ? url : '/$url';
      return 'http://localhost:8989$path';
    }
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


