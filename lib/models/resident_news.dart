class ResidentNews {
  final String id;
  final String title;
  final String summary;
  final String bodyHtml;
  final String? coverImageUrl;
  final String status;
  final DateTime? publishAt;
  final DateTime? expireAt;
  final int displayOrder;
  final int viewCount;
  final List<NewsImage> images;
  final String? createdBy;
  final DateTime createdAt;
  final String? updatedBy;
  final DateTime updatedAt;

  ResidentNews({
    required this.id,
    required this.title,
    required this.summary,
    required this.bodyHtml,
    this.coverImageUrl,
    required this.status,
    this.publishAt,
    this.expireAt,
    required this.displayOrder,
    required this.viewCount,
    required this.images,
    this.createdBy,
    required this.createdAt,
    this.updatedBy,
    required this.updatedAt,
  });

  factory ResidentNews.fromJson(Map<String, dynamic> json) {
    return ResidentNews(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      summary: json['summary'] ?? '',
      bodyHtml: json['bodyHtml'] ?? '',
      coverImageUrl: json['coverImageUrl'],
      status: json['status'] ?? '',
      publishAt: json['publishAt'] != null 
          ? DateTime.parse(json['publishAt']) 
          : null,
      expireAt: json['expireAt'] != null 
          ? DateTime.parse(json['expireAt']) 
          : null,
      displayOrder: json['displayOrder'] ?? 0,
      viewCount: json['viewCount'] ?? 0,
      images: (json['images'] as List<dynamic>?)
          ?.map((img) => NewsImage.fromJson(img))
          .toList() ?? [],
      createdBy: json['createdBy'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedBy: json['updatedBy'],
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

class NewsImage {
  final String id;
  final String newsId;
  final String url;
  final String? caption;
  final int sortOrder;
  final int? fileSize;
  final String? contentType;

  NewsImage({
    required this.id,
    required this.newsId,
    required this.url,
    this.caption,
    required this.sortOrder,
    this.fileSize,
    this.contentType,
  });

  factory NewsImage.fromJson(Map<String, dynamic> json) {
    return NewsImage(
      id: json['id']?.toString() ?? '',
      newsId: json['newsId']?.toString() ?? '',
      url: json['url'] ?? '',
      caption: json['caption'],
      sortOrder: json['sortOrder'] ?? 0,
      fileSize: json['fileSize'],
      contentType: json['contentType'],
    );
  }
}

