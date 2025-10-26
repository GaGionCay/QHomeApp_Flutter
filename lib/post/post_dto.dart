class PostDto {
  final int id;
  final String content;
  final List<String> imageUrls;
  final int userId;
  final DateTime createdAt;
  final int likeCount;
  final bool likedByMe;
  final int commentCount;
  final int shareCount;

  PostDto({
    required this.id,
    required this.content,
    required this.imageUrls,
    required this.userId,
    required this.createdAt,
    this.likeCount = 0,
    this.likedByMe = false,
    this.commentCount = 0,
    this.shareCount = 0,
  });

  PostDto copyWith({
    int? id,
    String? content,
    List<String>? imageUrls,
    int? userId,
    DateTime? createdAt,
    int? likeCount,
    bool? likedByMe,
    int? commentCount,
    int? shareCount,
  }) {
    return PostDto(
      id: id ?? this.id,
      content: content ?? this.content,
      imageUrls: imageUrls ?? this.imageUrls,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
    );
  }

  factory PostDto.fromJson(Map<String, dynamic> json) => PostDto(
        id: json['id'],
        content: json['content'],
        imageUrls: List<String>.from(json['imageUrls'] ?? []),
        userId: json['userId'],
        createdAt: DateTime.parse(json['createdAt']),
        likeCount: json['likeCount'] ?? 0,
        likedByMe: json['likedByMe'] ?? false,
        commentCount: json['commentCount'] ?? 0,
        shareCount: json['shareCount'] ?? 0,
      );
}

class CreatePostRequest {
  final String content;
  final String? topic;

  CreatePostRequest({required this.content, this.topic});

  Map<String, dynamic> toJson() => {
        'content': content,
        if (topic != null) 'topic': topic,
      };
}

class PostLikeDto {
  final int postId;
  final int userId;

  PostLikeDto({required this.postId, required this.userId});

  factory PostLikeDto.fromJson(Map<String, dynamic> json) => PostLikeDto(
        postId: json['postId'],
        userId: json['userId'],
      );
}

class PostCommentDto {
  final int id;
  final int postId;
  final int? parentId; // null nếu comment, id comment nếu là reply
  final int userId;
  final String userName;
  final String content;
  final DateTime createdAt;
  final List<PostCommentDto> replies;

  PostCommentDto({
    required this.id,
    required this.postId,
    this.parentId,
    required this.userId,
    required this.userName,
    required this.content,
    required this.createdAt,
    this.replies = const [],
  });

  factory PostCommentDto.fromJson(Map<String, dynamic> json) => PostCommentDto(
        id: json['id'],
        postId: json['postId'],
        parentId: json['parentId'],
        userId: json['userId'],
        userName: json['userName'],
        content: json['content'],
        createdAt: DateTime.parse(json['createdAt']),
        replies: (json['replies'] as List<dynamic>?)
                ?.map((e) => PostCommentDto.fromJson(e))
                .toList() ??
            [],
      );
}

class CreateCommentRequest {
  final String content;
  CreateCommentRequest({required this.content});

  Map<String, dynamic> toJson() => {'content': content};
}
