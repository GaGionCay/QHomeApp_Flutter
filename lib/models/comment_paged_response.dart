import 'marketplace_comment.dart';

class CommentPagedResponse {
  final List<MarketplaceComment> content;
  final int currentPage;
  final int pageSize;
  final int totalElements;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;

  CommentPagedResponse({
    required this.content,
    required this.currentPage,
    required this.pageSize,
    required this.totalElements,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrevious,
  });

  factory CommentPagedResponse.fromJson(Map<String, dynamic> json) {
    return CommentPagedResponse(
      content: (json['content'] as List<dynamic>?)
          ?.map((item) => MarketplaceComment.fromJson(item))
          .toList() ?? [],
      currentPage: json['currentPage'] ?? 0,
      pageSize: json['pageSize'] ?? 10,
      totalElements: json['totalElements'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      hasNext: json['hasNext'] ?? false,
      hasPrevious: json['hasPrevious'] ?? false,
    );
  }
}


