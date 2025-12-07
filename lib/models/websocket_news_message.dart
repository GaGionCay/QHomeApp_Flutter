import 'dart:convert';

class WebSocketNewsMessage {
  final String type;
  final String newsId;
  final String? title;
  final String? summary;
  final String? coverImageUrl;
  final DateTime timestamp;
  final String? deepLink;
  final String? tenantId;

  WebSocketNewsMessage({
    required this.type,
    required this.newsId,
    this.title,
    this.summary,
    this.coverImageUrl,
    required this.timestamp,
    this.deepLink,
    this.tenantId,
  });

  factory WebSocketNewsMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketNewsMessage(
      type: json['type'] ?? '',
      newsId: json['newsId'] ?? '',
      title: json['title'],
      summary: json['summary'],
      coverImageUrl: json['coverImageUrl'],
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      deepLink: json['deepLink'],
      tenantId: json['tenantId'],
    );
  }

  static WebSocketNewsMessage fromFrameBody(String? body) {
    if (body == null) throw ArgumentError("Frame body is null");
    final jsonData = json.decode(body);
    return WebSocketNewsMessage.fromJson(jsonData);
  }

  bool get isCreated => type == 'NEWS_CREATED';
  bool get isUpdated => type == 'NEWS_UPDATED';
  bool get isDeleted => type == 'NEWS_DELETED';
}

