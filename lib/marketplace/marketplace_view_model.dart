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
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 0;
  int? _pageSize;
  bool _hasMore = true;
  
  // Memory management: keep max 100 posts in memory
  static const int _maxPostsInMemory = 100;

  // Filters
  String? _selectedCategory;
  String? _searchQuery;
  String _statusFilter = 'ACTIVE';
  String? _sortBy;
  bool _showAllBuildings = false; // false = show only my building, true = show all buildings

  // Getters
  List<MarketplacePost> get posts => _posts;
  List<MarketplaceCategory> get categories => _categories;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String? get selectedCategory => _selectedCategory;
  String? get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;
  String? get sortBy => _sortBy;
  bool get showAllBuildings => _showAllBuildings;

  String? _buildingId;
  final Set<String> _subscribedPostIds = {}; // Track subscribed posts
  StreamSubscription? _marketplaceUpdateSubscription; // Track listener subscription
  bool _listenerSetup = false; // Track if listener has been setup

  Future<void> initialize() async {
    _buildingId = await _tokenStorage.readBuildingId();
    // Setup realtime updates FIRST before loading posts
    // This ensures listener is ready to receive events
    _setupRealtimeUpdates();
    await loadCategories();
    await loadPosts(refresh: true);
  }

  /// Public method to setup or re-setup realtime updates listener
  /// This can be called when app resumes or when listener needs to be refreshed
  void setupRealtimeUpdates() {
    _setupRealtimeUpdates();
  }
  
  void _setupRealtimeUpdates() {
    // Listen for marketplace updates from WebSocket
    // Cancel existing subscription if any to avoid duplicates
    if (_marketplaceUpdateSubscription != null) {
      _marketplaceUpdateSubscription?.cancel();
      _marketplaceUpdateSubscription = null;
    }
    
    
    try {
      _marketplaceUpdateSubscription = AppEventBus().on('marketplace_update', (data) {
        // Check if ViewModel is disposed before processing event
        if (_isDisposed) {
          return;
        }
        
        if (data is Map<String, dynamic>) {
          _handleRealtimeUpdate(data);
        }
      });
      
      _listenerSetup = true;
    } catch (e) {
      _listenerSetup = false;
    }
  }

  void _handleRealtimeUpdate(Map<String, dynamic> data) {
    // Check if ViewModel is disposed before processing
    if (_isDisposed) {
      return;
    }
    
    final type = data['type'] as String?;
    final postId = data['postId'] as String?;
    
    if (postId == null) {
      return;
    }
    
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index == -1) {
      return;
    }
    
    final post = _posts[index];
    
    switch (type) {
      case 'POST_STATS_UPDATE':
        // Update comment count, like count, and view count
        final commentCount = (data['commentCount'] as num?)?.toInt();
        final likeCount = (data['likeCount'] as num?)?.toInt();
        final viewCount = (data['viewCount'] as num?)?.toInt();
        
        // Check if update is actually needed
        final needsUpdate = (commentCount != null && commentCount != post.commentCount) ||
                           (viewCount != null && viewCount != post.viewCount);
        
        if (commentCount != null || likeCount != null || viewCount != null) {
          if (!needsUpdate) {
            return;
          }
          
          final updatedPost = MarketplacePost(
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
            viewCount: viewCount ?? post.viewCount,
            commentCount: commentCount ?? post.commentCount,
            images: post.images,
            author: post.author,
            createdAt: post.createdAt,
            updatedAt: post.updatedAt,
          );
          
          // Always update if we have new data that differs from current state
          // This ensures UI reflects the latest state from backend
          // IMPORTANT: Create a new list to ensure Selector detects the change
          // Selector compares list references, so we need to create a new list instance
          _posts = List.from(_posts); // Create new list instance
          _posts[index] = updatedPost; // Update the post
          
          // Force immediate update by calling notifyListeners synchronously
          _safeNotifyListeners();
        }
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
          commentCount: post.commentCount + 1,
          images: post.images,
          author: post.author,
          createdAt: post.createdAt,
          updatedAt: post.updatedAt,
        );
        _safeNotifyListeners();
        // Emit event for PostDetailScreen to reload comments
        AppEventBus().emit('new_comment', {'postId': postId, 'data': data});
      case 'NEW_POST':
        // Refresh posts list to show new post
        loadPosts(refresh: true);
    }
  }

  void subscribeToPostUpdates(String postId) {
    if (_subscribedPostIds.contains(postId)) return;
    _subscribedPostIds.add(postId);
    // Subscription will be handled by MainShell
  }

  @override
  @override
  void dispose() {
    // Mark as disposed first to prevent any further operations
    _isDisposed = true;
    // Cancel only this instance's subscription, not all listeners
    _marketplaceUpdateSubscription?.cancel();
    _marketplaceUpdateSubscription = null;
    super.dispose();
  }

  bool _isDisposed = false;

  /// Safe notifyListeners that checks if ViewModel is disposed
  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  Future<void> loadCategories() async {
    try {
      _categories = await _service.getCategories();
      _safeNotifyListeners();
    } catch (e) {
      // Error loading categories - silent fail
    }
  }

  Future<void> loadPosts({bool refresh = false, int? page}) async {
    // Check if ViewModel is disposed before loading
    if (_isDisposed) {
      return;
    }
    
    // IMPORTANT: Save existing posts BEFORE clearing for refresh
    // This allows us to preserve realtime updates when merging with API data
    List<MarketplacePost>? existingPostsForMerge;
    if (refresh) {
      existingPostsForMerge = List.from(_posts); // Copy existing posts before clearing
      _currentPage = 0;
      _posts = [];
      _hasMore = true;
    }

    if (!_hasMore && !refresh) return;

    // Set loading state
    if (refresh) {
      _isLoading = true;
    } else {
      _isLoadingMore = true;
    }
    _error = null;
    _safeNotifyListeners();

    try {
      final targetPage = page ?? (refresh ? 0 : _currentPage + 1);
      // Determine filterScope based on showAllBuildings:
      // - If showAllBuildings = false (Building của tôi) → filterScope = "BUILDING"
      // - If showAllBuildings = true (Tất cả) → filterScope = "ALL"
      final filterScope = _showAllBuildings ? 'ALL' : 'BUILDING';
      final response = await _service.getPosts(
        buildingId: _showAllBuildings ? null : _buildingId,
        page: targetPage,
        size: _pageSize ?? 15, // Reduced from 20 to 15 for initial load
        search: _searchQuery,
        category: _selectedCategory,
        status: _statusFilter,
        sortBy: _sortBy,
        filterScope: filterScope,
      );

      _pageSize = response.pageSize;

      if (refresh) {
        // When refreshing, merge with existing posts to preserve realtime updates
        // API list endpoint may return stale values (e.g., commentCount may be outdated)
        // So we preserve values that were updated via realtime events (from PostDetailScreen)
        final existingPostsMap = <String, MarketplacePost>{};
        if (existingPostsForMerge != null) {
          for (var post in existingPostsForMerge) {
            existingPostsMap[post.id] = post;
          }
        }
        
        _posts = response.content.map((apiPost) {
          final existingPost = existingPostsMap[apiPost.id];
          if (existingPost != null) {
            // If existing post has different counts, it was likely updated via realtime events
            // Preserve those values as they may be more accurate than API list endpoint
            // API list endpoint may have stale cache, while realtime events come from PostDetailScreen
            // which fetches directly from backend get by ID endpoint
            if (existingPost.commentCount != apiPost.commentCount || 
                existingPost.viewCount != apiPost.viewCount) {
              return MarketplacePost(
                id: apiPost.id,
                residentId: apiPost.residentId,
                buildingId: apiPost.buildingId,
                title: apiPost.title,
                description: apiPost.description,
                price: apiPost.price,
                category: apiPost.category,
                categoryName: apiPost.categoryName,
                status: apiPost.status,
                contactInfo: apiPost.contactInfo,
                location: apiPost.location,
                viewCount: existingPost.viewCount, // Use realtime updated value
                commentCount: existingPost.commentCount, // Use realtime updated value
                images: apiPost.images,
                author: apiPost.author,
                createdAt: apiPost.createdAt,
                updatedAt: apiPost.updatedAt,
              );
            } else {
              return apiPost;
            }
          } else {
            return apiPost;
          }
        }).toList();
      } else {
        // Append new posts
        _posts.addAll(response.content);
        
        // Memory management: remove old posts if exceeding limit
        if (_posts.length > _maxPostsInMemory) {
          final removeCount = _posts.length - _maxPostsInMemory;
          _posts.removeRange(0, removeCount);
        }
      }

      _currentPage = targetPage;
      _hasMore = !response.last;

      _isLoading = false;
      _isLoadingMore = false;
      _error = null;
      _safeNotifyListeners();
    } catch (e) {
      _isLoading = false;
      _isLoadingMore = false;
      _error = 'Lỗi khi tải danh sách bài đăng: ${e.toString()}';
      _safeNotifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoading) return;
    await loadPosts();
  }

  Future<void> refresh() async {
    if (_isDisposed) {
      return;
    }
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

  void setShowAllBuildings(bool showAll) {
    if (_showAllBuildings == showAll) return;
    _showAllBuildings = showAll;
    loadPosts(refresh: true);
  }


  Future<MarketplacePost?> getPostById(String postId) async {
    try {
      return await _service.getPostById(postId);
    } catch (e) {
      _error = 'Lỗi khi tải chi tiết bài đăng: ${e.toString()}';
      _safeNotifyListeners();
      return null;
    }
  }

  Future<List<MarketplaceComment>> getComments(String postId) async {
    try {
      return await _service.getComments(postId);
    } catch (e) {
      return [];
    }
  }

  Future<CommentPagedResponse> getCommentsPaged(String postId, {int page = 0, int size = 10}) async {
    try {
      return await _service.getCommentsPaged(postId, page: page, size: size);
    } catch (e) {
      rethrow;
    }
  }

  Future<MarketplaceComment?> addComment(String postId, String content, {String? parentCommentId, String? imageUrl, String? videoUrl}) async {
    try {
      final newComment = await _service.addComment(
        postId: postId,
        content: content,
        parentCommentId: parentCommentId,
        imageUrl: imageUrl,
        videoUrl: videoUrl,
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
          commentCount: post.commentCount + 1,
          images: post.images,
          author: post.author,
          createdAt: post.createdAt,
          updatedAt: post.updatedAt,
        );
        _safeNotifyListeners();
      }
      
      return newComment;
    } catch (e) {
      _error = 'Lỗi khi thêm bình luận: ${e.toString()}';
      _safeNotifyListeners();
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
      _safeNotifyListeners();
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
      _safeNotifyListeners();
      
      return true;
    } catch (e) {
      _error = 'Lỗi khi xóa bài đăng: ${e.toString()}';
      _safeNotifyListeners();
      return false;
    }
  }
}


