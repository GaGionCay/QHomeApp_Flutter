class NewsItem {
  final String id;
  final String title;
  final String body;
  final DateTime date;
  bool isRead;
  NewsItem({required this.title, required this.body, required this.date, required this.id, required this.isRead});

factory NewsItem.fromJson(Map<String, dynamic> json) {
    return NewsItem(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      body: json['summary'] ?? json['content'] ?? '',
      date: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      isRead: json['isRead'] ?? false,
    );
  }

  get content => null;

  get createdAt => null;
}