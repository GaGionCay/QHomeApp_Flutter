import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/marketplace_post.dart';
import '../models/marketplace_category.dart';
import '../models/marketplace_comment.dart';
import '../models/comment_paged_response.dart';
import 'marketplace_service.dart';
import '../auth/token_storage.dart';
import '../core/event_bus.dart';

class MarketplaceViewModel extends ChangeNotifier {
  final MarketplaceService _service;
  final TokenStorage _tokenStorage;

  MarketplaceViewModel(this._service, this._tokenStorage);

  // State
  List<MarketplacePost> _posts = [];
  List<MarketplaceCategory> _categories = [];
  bool _isLoading = false;
  String? _error;
  int _currentPage = 0;
  int? _pageSize;
  int _totalPages = 0;
  int _totalElements = 0;
  bool _hasMore = true;

  // Filters
  String? _selectedCategory;
  String? _searchQuery;
  String _statusFilter = 'ACTIVE';
  String? _sortBy;

  // Getters
  List<MarketplacePost> get posts => _posts;
  List<MarketplaceCategory> get categories => _categories;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String? get selectedCategory => _selectedCategory;
  String? get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;
  String? get sortBy => _sortBy;

  String? _buildingId;
  String? _residentId;
  final Set<String> _subscribedPostIds = {}; // Track subscribed posts

  Future<void> initialize() async {
    _buildingId = await _tokenStorage.readBuildingId();
    _residentId = await _tokenStorage.readResidentId();
    await loadCategories();
    await loadPosts(refresh: true);
    _setupRealtimeUpdates();
  }

  void _setupRealtimeUpdates() {
    // Listen for marketplace updates from WebSocket
    AppEventBus().on('marketplace_update', (data) {
      if (data is Map<String, dynamic>) {
        _handleRealtimeUpdate(data);
      }
    });
  }

  void _handleRealtimeUpdate(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final postId = data['postId'] as String?;
    
    if (postId == null) return;
    
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;
    
    final post = _posts[index];
    
    switch (type) {
      case 'POST_STATS_UPDATE':
        // Update like count, comment count
        final likeCount = data['likeCount'] as int?;
        final commentCount = data['commentCount'] as int?;
        
        if (likeCount != null || commentCount != null) {
          _posts[index] = MarketplacePost(
            id: post.id,
            residentId: post.residentId,
            buildingId: post.buildingId,
            title: post.title,
            description: post.description,
            price: post.price,
            category: post.category,
            categoryName: post.categoryName,
            status: post.status,
            contactInfo: post.contactInfo,
            location: post.location,
            viewCount: post.viewCount,
            likeCount: likeCount ?? post.likeCount,
            commentCount: commentCount ?? post.commentCount,
            isLiked: post.isLiked,
            images: post.images,
            author: post.author,
            createdAt: post.createdAt,
            updatedAt: post.updatedAt,
          );
          notifyListeners();
        }
        break;
      case 'POST_LIKED':
      case 'POST_UNLIKED':
        // Update like status
        final isLiked = type == 'POST_LIKED';
        _posts[index] = MarketplacePost(
          id: post.id,
          residentId: post.residentId,
          buildingId: post.buildingId,
          title: post.title,
          description: post.description,
          price: post.price,
          category: post.category,
          categoryName: post.categoryName,
          status: post.status,
          contactInfo: post.contactInfo,
          location: post.location,
          viewCount: post.viewCount,
          likeCount: isLiked ? post.likeCount + 1 : (post.likeCount > 0 ? post.likeCount - 1 : 0),
          commentCount: post.commentCount,
          isLiked: isLiked,
          images: post.images,
          author: post.author,
          createdAt: post.createdAt,
          updatedAt: post.updatedAt,
        );
        notifyListeners();
        break;
      case 'NEW_COMMENT':
        // Increment comment count and emit event for PostDetailScreen
        _posts[index] = MarketplacePost(
          id: post.id,
          residentId: post.residentId,
          buildingId: post.buildingId,
          title: post.title,
          description: post.description,
          price: post.price,
          category: post.category,
          categoryName: post.categoryName,
          status: post.status,
          contactInfo: post.contactInfo,
          location: post.location,
          viewCount: post.viewCount,
          likeCount: post.likeCount,
          commentCount: post.commentCount + 1,
          isLiked: post.isLiked,
          images: post.images,
          author: post.author,
          createdAt: post.createdAt,
          updatedAt: post.updatedAt,
        );
        notifyListeners();
        // Emit event for PostDetailScreen to reload comments
        AppEventBus().emit('new_comment', {'postId': postId, 'data': data});
        break;
      case 'NEW_POST':
        // Refresh posts list to show new post
        loadPosts(refresh: true);
        break;
    }
  }

  void subscribeToPostUpdates(String postId) {
    if (_subscribedPostIds.contains(postId)) return;
    _subscribedPostIds.add(postId);
    // Subscription will be handled by MainShell
  }

  @override
  void dispose() {
    AppEventBus().off('marketplace_update');
    super.dispose();
  }

  Future<void> loadCategories() async {
    try {
      _categories = await _service.getCategories();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  Future<void> loadPosts({bool refresh = false, int? page}) async {
    if (_buildingId == null) {
      _error = 'Building ID not found';
      notifyListeners();
      return;
    }

    if (refresh) {
      _currentPage = 0;
      _posts = [];
      _hasMore = true;
    }

    if (!_hasMore && !refresh) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final targetPage = page ?? _currentPage;
      final response = await _service.getPosts(
        buildingId: _buildingId!,
        page: targetPage,
        size: _pageSize ?? 20,
        search: _searchQuery,
        category: _selectedCategory,
        status: _statusFilter,
        sortBy: _sortBy,
      );

      _pageSize = response.pageSize;
      _totalPages = response.totalPages;
      _totalElements = response.totalElements;

      if (refresh) {
        _posts = response.content;
      } else {
        _posts.addAll(response.content);
      }

      _currentPage = targetPage;
      _hasMore = !response.last;

      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Lỗi khi tải danh sách bài đăng: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoading) return;
    await loadPosts();
  }

  Future<void> refresh() async {
    await loadPosts(refresh: true);
  }

  void setCategoryFilter(String? category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    loadPosts(refresh: true);
  }

  void setSearchQuery(String? query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    loadPosts(refresh: true);
  }

  void setStatusFilter(String status) {
    if (_statusFilter == status) return;
    _statusFilter = status;
    loadPosts(refresh: true);
  }

  void setSortBy(String? sort) {
    if (_sortBy == sort) return;
    _sortBy = sort;
    loadPosts(refresh: true);
  }

  Future<void> toggleLike(String postId) async {
    // Optimistic update - update UI immediately
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;
    
    final post = _posts[index];
    final wasLiked = post.isLiked;
    final oldLikeCount = post.likeCount;
    
    // Update UI immediately (optimistic update)
    _posts[index] = MarketplacePost(
      id: post.id,
      residentId: post.residentId,
      buildingId: post.buildingId,
      title: post.title,
      description: post.description,
      price: post.price,
      category: post.category,
      categoryName: post.categoryName,
      status: post.status,
      contactInfo: post.contactInfo,
      location: post.location,
      viewCount: post.viewCount,
      likeCount: wasLiked ? (oldLikeCount > 0 ? oldLikeCount - 1 : 0) : oldLikeCount + 1,
      commentCount: post.commentCount,
      isLiked: !wasLiked,
      images: post.images,
      author: post.author,
      createdAt: post.createdAt,
      updatedAt: post.updatedAt,
    );
    notifyListeners();
    
    // Then call API
    try {
      await _service.toggleLike(postId);
      // Optionally reload to get accurate count from server
      // But optimistic update already shows the change
    } catch (e) {
      // Revert on error
      _posts[index] = post;
      _error = 'Lỗi khi like bài đăng: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<MarketplacePost?> getPostById(String postId) async {
    try {
      return await _service.getPostById(postId);
    } catch (e) {
      _error = 'Lỗi khi tải chi tiết bài đăng: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  Future<List<MarketplaceComment>> getComments(String postId) async {
    try {
      return await _service.getComments(postId);
    } catch (e) {
      debugPrint('Error loading comments: $e');
      return [];
    }
  }

  Future<CommentPagedResponse> getCommentsPaged(String postId, {int page = 0, int size = 10}) async {
    try {
      return await _service.getCommentsPaged(postId, page: page, size: size);
    } catch (e) {
      debugPrint('Error loading comments paged: $e');
      rethrow;
    }
  }

  Future<MarketplaceComment?> addComment(String postId, String content, {String? parentCommentId}) async {
    try {
      final newComment = await _service.addComment(
        postId: postId,
        content: content,
        parentCommentId: parentCommentId,
      );
      
      // Optimistic update - increment comment count immediately
      final index = _posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        final post = _posts[index];
        _posts[index] = MarketplacePost(
          id: post.id,
          residentId: post.residentId,
          buildingId: post.buildingId,
          title: post.title,
          description: post.description,
          price: post.price,
          category: post.category,
          categoryName: post.categoryName,
          status: post.status,
          contactInfo: post.contactInfo,
          location: post.location,
          viewCount: post.viewCount,
          likeCount: post.likeCount,
          commentCount: post.commentCount + 1,
          isLiked: post.isLiked,
          images: post.images,
          author: post.author,
          createdAt: post.createdAt,
          updatedAt: post.updatedAt,
        );
        notifyListeners();
      }
      
      return newComment;
    } catch (e) {
      _error = 'Lỗi khi thêm bình luận: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  /// Update post
  Future<MarketplacePost?> updatePost({
    required String postId,
    String? title,
    String? description,
    double? price,
    String? category,
    String? location,
    MarketplaceContactInfo? contactInfo,
    List<XFile>? newImages,
    List<String>? imagesToDelete,
  }) async {
    try {
      final updatedPost = await _service.updatePost(
        postId: postId,
        title: title,
        description: description,
        price: price,
        category: category,
        location: location,
        contactInfo: contactInfo,
        newImages: newImages,
        imagesToDelete: imagesToDelete,
      );

      // Update in local list
      final index = _posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        _posts[index] = updatedPost;
        notifyListeners();
      }

      return updatedPost;
    } catch (e) {
      _error = 'Lỗi khi cập nhật bài đăng: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  /// Delete post
  Future<bool> deletePost(String postId) async {
    try {
      await _service.deletePost(postId);
      
      // Remove from local list
      _posts.removeWhere((p) => p.id == postId);
      notifyListeners();
      
      return true;
    } catch (e) {
      _error = 'Lỗi khi xóa bài đăng: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }
}

