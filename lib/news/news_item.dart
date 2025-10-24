class NotificationItem {
  final int id;
  final String title;
  final String body;
  final DateTime date;

  NotificationItem({required this.title, required this.body, required this.date, required this.id});

factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      body: json['summary'] ?? json['content'] ?? '',
      date: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  get content => null;

  get createdAt => null;
}