class News {
  final int id;
  final String? categoryCode;
  final String? categoryName;
  final String title;
  final String? summary;
  final String content;
  final String? author;
  final String? source;
  final DateTime? publishedAt;
  final bool pinned;
  final bool visibleToAll;
  final String? createdBy;
  final DateTime createdAt; // Không nullable nữa
  final String? updatedBy;
  final DateTime? updatedAt;
  bool read;
  final List<NewsAttachment> attachments;

  News({
    required this.id,
    this.categoryCode,
    this.categoryName,
    required this.title,
    this.summary,
    required this.content,
    this.author,
    this.source,
    this.publishedAt,
    this.pinned = false,
    this.visibleToAll = true,
    this.createdBy,
    required this.createdAt,
    this.updatedBy,
    this.updatedAt,
    this.read = false,
    this.attachments = const [],
  });

  factory News.fromJson(Map<String, dynamic> json) {
    return News(
      id: json['id'],
      categoryCode: json['categoryCode'],
      categoryName: json['categoryName'],
      title: json['title'] ?? '',
      summary: json['summary'],
      content: json['content'] ?? '',
      author: json['author'],
      source: json['source'],
      publishedAt: json['publishedAt'] != null
          ? DateTime.tryParse(json['publishedAt'])
          : null,
      pinned: json['pinned'] ?? false,
      visibleToAll: json['visibleToAll'] ?? true,
      createdBy: json['createdBy'],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
          : DateTime.now(),
      updatedBy: json['updatedBy'],
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
      read: json['read'] ?? false,
      attachments: (json['attachments'] as List<dynamic>?)
              ?.map((e) => NewsAttachment.fromJson(e))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'categoryCode': categoryCode,
      'categoryName': categoryName,
      'title': title,
      'summary': summary,
      'content': content,
      'author': author,
      'source': source,
      'publishedAt': publishedAt?.toIso8601String(),
      'pinned': pinned,
      'visibleToAll': visibleToAll,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedBy': updatedBy,
      'updatedAt': updatedAt?.toIso8601String(),
      'read': read,
      'attachments': attachments.map((a) => a.toJson()).toList(),
    };
  }
}

class NewsAttachment {
  final int? id;
  final String filename;
  final String url;

  NewsAttachment({
    this.id,
    required this.filename,
    required this.url,
  });

  factory NewsAttachment.fromJson(Map<String, dynamic> json) {
    return NewsAttachment(
      id: json['id'],
      filename: json['filename'] ?? '',
      url: json['url'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'url': url,
    };
  }
}