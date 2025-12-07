import 'resident_news.dart';

class NewsPagedResponse {
  final List<ResidentNews> content;
  final int currentPage;
  final int pageSize;
  final int totalElements;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;
  final bool isFirst;
  final bool isLast;

  NewsPagedResponse({
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

  factory NewsPagedResponse.fromJson(Map<String, dynamic> json) {
    return NewsPagedResponse(
      content: (json['content'] as List<dynamic>?)
              ?.map((item) => ResidentNews.fromJson(item as Map<String, dynamic>))
              .toList() ?? [],
      currentPage: json['currentPage'] ?? 0,
      pageSize: json['pageSize'] ?? 7,
      totalElements: json['totalElements'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      hasNext: json['hasNext'] ?? false,
      hasPrevious: json['hasPrevious'] ?? false,
      isFirst: json['isFirst'] ?? false,
      isLast: json['isLast'] ?? false,
    );
  }
}


