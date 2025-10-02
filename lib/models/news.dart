class News {
  final int id;
  final String title;
  final String content;
  final String author;
  final String createdAt;
  final bool isRead;

  News({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    required this.createdAt,
    required this.isRead,
  });

  factory News.fromJson(Map<String, dynamic> json) {
    return News(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      author: json['author'],
      createdAt: json['createdAt'],
      isRead: json['isRead'] ?? false,
    );
  }
}