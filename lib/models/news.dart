// news.dart
class News {
  final int id;
  final String title;
  final String summary;
  final String content;
  final String category;
  final String createdAt;

  News({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    required this.category,
    required this.createdAt,
  });

  factory News.fromJson(Map<String, dynamic> json) {
    return News(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      title: json['title'] ?? '',
      summary: json['summary'] ?? '',
      content: json['content'] ?? '',
      category: json['category'] ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}
