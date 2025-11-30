import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../models/marketplace_post.dart';
import '../models/marketplace_comment.dart';
import '../models/marketplace_category.dart';
import '../models/marketplace_paged_response.dart';
import '../models/comment_paged_response.dart';
import 'marketplace_api_client.dart';

class MarketplaceService {
  final MarketplaceApiClient _apiClient;

  MarketplaceService() : _apiClient = MarketplaceApiClient();

  /// Lấy danh sách posts với pagination và filter
  Future<MarketplacePagedResponse> getPosts({
    required String buildingId,
    int page = 0,
    int size = 20,
    String? search,
    String? category,
    String? status,
    double? minPrice,
    double? maxPrice,
    String? sortBy, // 'newest', 'oldest', 'price_asc', 'price_desc', 'popular'
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'buildingId': buildingId,
        'page': page,
        'size': size,
      };

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (category != null && category.isNotEmpty) {
        queryParams['category'] = category;
      }
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }
      if (minPrice != null) {
        queryParams['minPrice'] = minPrice;
      }
      if (maxPrice != null) {
        queryParams['maxPrice'] = maxPrice;
      }
      if (sortBy != null && sortBy.isNotEmpty) {
        queryParams['sortBy'] = sortBy;
      }

      final response = await _apiClient.dio.get(
        '/posts',
        queryParameters: queryParams,
      );

      // Debug: Check if response contains author info and images
      if (response.data != null && response.data['content'] != null) {
        final posts = response.data['content'] as List;
        if (posts.isNotEmpty) {
          final firstPost = posts[0];
          print('🔍 [MarketplaceService] First post author: ${firstPost['author']}');
          print('🖼️ [MarketplaceService] First post images: ${firstPost['images']}');
          if (firstPost['images'] != null && firstPost['images'] is List) {
            print('✅ [MarketplaceService] First post has ${(firstPost['images'] as List).length} images');
            if ((firstPost['images'] as List).isNotEmpty) {
              print('🖼️ [MarketplaceService] First image: ${(firstPost['images'] as List)[0]}');
            }
          } else {
            print('⚠️ [MarketplaceService] First post has no images or images is not a List');
          }
        }
      }

      return MarketplacePagedResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi lấy danh sách posts: ${e.toString()}');
    }
  }

  /// Lấy chi tiết post
  Future<MarketplacePost> getPostById(String postId) async {
    try {
      final response = await _apiClient.dio.get('/posts/$postId');
      return MarketplacePost.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi lấy chi tiết post: ${e.toString()}');
    }
  }

  /// Tạo post mới
  Future<MarketplacePost> createPost({
    required String buildingId,
    required String title,
    required String description,
    double? price,
    required String category,
    String? location,
    MarketplaceContactInfo? contactInfo,
    required List<XFile> images,
  }) async {
    try {
      // Tạo JSON data cho CreatePostRequest
      final requestData = {
        'buildingId': buildingId,
        'title': title,
        'description': description,
        if (price != null) 'price': price,
        'category': category,
        if (location != null) 'location': location,
        if (contactInfo != null) 'contactInfo': contactInfo.toJson(),
      };

      // Convert to JSON string
      final jsonString = jsonEncode(requestData);

      // Tạo FormData với part "data" chứa JSON
      final formData = FormData();

      // Thêm part "data" với JSON content
      formData.files.add(
        MapEntry(
          'data',
          MultipartFile.fromString(
            jsonString,
            filename: 'data.json',
          ),
        ),
      );

      // Thêm images
      for (int i = 0; i < images.length; i++) {
        formData.files.add(
          MapEntry(
            'images',
            await MultipartFile.fromFile(
              images[i].path,
              filename: 'image_$i.jpg',
            ),
          ),
        );
      }

      final response = await _apiClient.dio.post(
        '/posts',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
        ),
      );

      return MarketplacePost.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi tạo post: ${e.toString()}');
    }
  }

  /// Cập nhật post
  Future<MarketplacePost> updatePost({
    required String postId,
    String? title,
    String? description,
    double? price,
    String? category,
    String? location,
    MarketplaceContactInfo? contactInfo,
    List<XFile>? newImages,
    List<String>? imagesToDelete, // IDs của images cần xóa
  }) async {
    try {
      // Tạo JSON data cho UpdatePostRequest
      final requestData = <String, dynamic>{};
      if (title != null) requestData['title'] = title;
      if (description != null) requestData['description'] = description;
      if (price != null) requestData['price'] = price;
      if (category != null) requestData['category'] = category;
      if (location != null) requestData['location'] = location;
      if (contactInfo != null) requestData['contactInfo'] = contactInfo.toJson();
      if (imagesToDelete != null && imagesToDelete.isNotEmpty) {
        requestData['imagesToDelete'] = imagesToDelete;
      }

      // Convert to JSON string
      final jsonString = jsonEncode(requestData);

      // Tạo FormData với part "data" chứa JSON
      final formData = FormData();

      // Thêm part "data" với JSON content
      formData.files.add(
        MapEntry(
          'data',
          MultipartFile.fromString(
            jsonString,
            filename: 'data.json',
          ),
        ),
      );

      // Thêm images mới
      if (newImages != null && newImages.isNotEmpty) {
        for (int i = 0; i < newImages.length; i++) {
          formData.files.add(
            MapEntry(
              'images',
              await MultipartFile.fromFile(
                newImages[i].path,
                filename: 'image_$i.jpg',
              ),
            ),
          );
        }
      }

      final response = await _apiClient.dio.put(
        '/posts/$postId',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
        ),
      );

      return MarketplacePost.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi cập nhật post: ${e.toString()}');
    }
  }

  /// Xóa post
  Future<void> deletePost(String postId) async {
    try {
      await _apiClient.dio.delete('/posts/$postId');
    } catch (e) {
      throw Exception('Lỗi khi xóa post: ${e.toString()}');
    }
  }

  /// Đổi status của post (ACTIVE -> SOLD)
  Future<MarketplacePost> updatePostStatus(String postId, String status) async {
    try {
      final response = await _apiClient.dio.post(
        '/posts/$postId/status',
        data: {'status': status},
      );
      return MarketplacePost.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi cập nhật status: ${e.toString()}');
    }
  }

  /// Like/Unlike post
  Future<void> toggleLike(String postId) async {
    try {
      await _apiClient.dio.post('/posts/$postId/like');
    } catch (e) {
      throw Exception('Lỗi khi like post: ${e.toString()}');
    }
  }

  /// Lấy danh sách comments của post (deprecated - use getCommentsPaged)
  Future<List<MarketplaceComment>> getComments(String postId) async {
    try {
      final response = await _apiClient.dio.get('/posts/$postId/comments');
      return (response.data as List<dynamic>)
          .map((json) => MarketplaceComment.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Lỗi khi lấy comments: ${e.toString()}');
    }
  }

  /// Lấy danh sách comments của post với pagination
  Future<CommentPagedResponse> getCommentsPaged(String postId, {int page = 0, int size = 10}) async {
    try {
      final response = await _apiClient.dio.get(
        '/posts/$postId/comments',
        queryParameters: {
          'page': page,
          'size': size,
        },
      );
      return CommentPagedResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi lấy comments: ${e.toString()}');
    }
  }

  /// Thêm comment
  Future<MarketplaceComment> addComment({
    required String postId,
    required String content,
    String? parentCommentId, // Cho reply
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/posts/$postId/comments',
        data: {
          'content': content,
          if (parentCommentId != null) 'parentCommentId': parentCommentId,
        },
      );
      return MarketplaceComment.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi thêm comment: ${e.toString()}');
    }
  }

  /// Cập nhật comment
  Future<MarketplaceComment> updateComment(String postId, String commentId, String content) async {
    try {
      final response = await _apiClient.dio.put(
        '/posts/$postId/comments/$commentId',
        data: {'content': content},
      );
      return MarketplaceComment.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi cập nhật comment: ${e.toString()}');
    }
  }

  /// Xóa comment
  Future<void> deleteComment(String postId, String commentId) async {
    try {
      await _apiClient.dio.delete('/posts/$postId/comments/$commentId');
    } catch (e) {
      throw Exception('Lỗi khi xóa comment: ${e.toString()}');
    }
  }

  /// Lấy danh sách categories
  Future<List<MarketplaceCategory>> getCategories() async {
    try {
      final response = await _apiClient.dio.get('/categories');
      return (response.data as List<dynamic>)
          .map((json) => MarketplaceCategory.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Lỗi khi lấy categories: ${e.toString()}');
    }
  }

  /// Lấy posts của user
  Future<MarketplacePagedResponse> getMyPosts({
    required String residentId,
    int page = 0,
    int size = 20,
    String? status,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'residentId': residentId,
        'page': page,
        'size': size,
      };

      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }

      final response = await _apiClient.dio.get(
        '/posts/my',
        queryParameters: queryParams,
      );

      return MarketplacePagedResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi lấy posts của tôi: ${e.toString()}');
    }
  }
}

