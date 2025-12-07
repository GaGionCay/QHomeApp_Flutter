import 'marketplace_post.dart';

class MarketplacePagedResponse {
  final List<MarketplacePost> content;
  final int currentPage;
  final int totalPages;
  final int totalElements;
  final int pageSize;
  final bool first;
  final bool last;

  MarketplacePagedResponse({
    required this.content,
    required this.currentPage,
    required this.totalPages,
    required this.totalElements,
    required this.pageSize,
    required this.first,
    required this.last,
  });

  factory MarketplacePagedResponse.fromJson(Map<String, dynamic> json) {
    return MarketplacePagedResponse(
      content: (json['content'] as List<dynamic>?)
          ?.map((item) => MarketplacePost.fromJson(item))
          .toList() ?? [],
      currentPage: json['currentPage'] ?? json['number'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      totalElements: json['totalElements'] ?? json['totalElements'] ?? 0,
      pageSize: json['pageSize'] ?? json['size'] ?? 20,
      first: json['first'] ?? false,
      last: json['last'] ?? false,
    );
  }
}


