import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';

import '../auth/api_client.dart';
import 'post_dto.dart';

class PostService {
  final ApiClient apiClient;
  PostService(this.apiClient);

  // Get all posts
  Future<List<PostDto>> getAllPosts({int page = 0, int size = 10}) async {
    final res = await apiClient.dio.get('/posts', queryParameters: {
      'page': page,
      'size': size,
    });
    final posts =
        (res.data['posts'] as List).map((e) => PostDto.fromJson(e)).toList();
    return posts;
  }

  // Create post with optional images
  Future<PostDto> createPost(String content,
      {List<File>? images, String? topic}) async {
    final formData = FormData();

    final request = CreatePostRequest(content: content, topic: topic);
    // Sửa lỗi transformer bằng jsonEncode từ dart:convert
    formData.fields.add(MapEntry('request', jsonEncode(request.toJson())));

    if (images != null) {
      for (var file in images) {
        formData.files.add(MapEntry(
          'files',
          await MultipartFile.fromFile(
            file.path,
            filename: file.path.split('/').last,
          ),
        ));
      }
    }

    final res = await apiClient.dio.post('/posts', data: formData);
    return PostDto.fromJson(res.data);
  }

  // Like post
  Future<PostLikeDto> likePost(int postId) async {
    final res = await apiClient.dio.post('/posts/$postId/like');
    return PostLikeDto.fromJson(res.data);
  }

  // Unlike post
  Future<void> unlikePost(int postId) async {
    await apiClient.dio.post('/posts/$postId/unlike');
  }

  // Comment
  Future<PostCommentDto> commentPost(int postId, String content) async {
    final request = CreateCommentRequest(content: content);
    final res = await apiClient.dio
        .post('/posts/$postId/comment', data: request.toJson());
    return PostCommentDto.fromJson(res.data);
  }

  // Reply
  Future<PostCommentDto> replyToComment(
      int postId, int commentId, String content) async {
    final request = CreateCommentRequest(content: content);
    final res = await apiClient.dio.post(
        '/posts/$postId/comments/$commentId/reply',
        data: request.toJson());
    return PostCommentDto.fromJson(res.data);
  }

  // Share
  Future<void> sharePost(int postId) async {
    await apiClient.dio.post('/posts/$postId/share');
  }

  // Get comments
  Future<List<PostCommentDto>> getComments(int postId) async {
    final res = await apiClient.dio.get('/posts/$postId/comments');
    return (res.data as List).map((e) => PostCommentDto.fromJson(e)).toList();
  }

// Delete post
  Future<void> deletePost(int postId) async {
    await apiClient.dio.delete('/posts/$postId');
  }

// Delete comment
  Future<void> deleteComment(int commentId) async {
    await apiClient.dio.delete('/posts/comments/$commentId');
  }
}
