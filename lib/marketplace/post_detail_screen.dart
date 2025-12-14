// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../chat/linkable_text_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import 'dart:async';
import '../models/marketplace_post.dart';
import 'video_preview_widget.dart';
import 'video_viewer_screen.dart';
import '../service_registration/video_compression_service.dart';
import '../models/marketplace_comment.dart';
import '../models/comment_paged_response.dart';
import '../auth/token_storage.dart';
import '../auth/api_client.dart';
import '../services/imagekit_service.dart';
import 'marketplace_view_model.dart';
import 'marketplace_service.dart';
import '../core/event_bus.dart';
import 'image_viewer_screen.dart';
import 'edit_post_screen.dart';
import '../chat/chat_service.dart';
import '../models/chat/group.dart';
import '../models/chat/friend.dart';
import '../chat/direct_chat_screen.dart';
import 'select_group_dialog.dart';
import 'create_group_dialog.dart';
import '../widgets/animations/smooth_animations.dart';

class PostDetailScreen extends StatefulWidget {
  final MarketplacePost post;

  const PostDetailScreen({
    super.key,
    required this.post,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TokenStorage _tokenStorage = TokenStorage();
  final ChatService _chatService = ChatService();
  final ApiClient _apiClient = ApiClient();
  final MarketplaceService _marketplaceService = MarketplaceService();
  final ImageKitService _imageKitService = ImageKitService(ApiClient());
  bool _commentsLoaded = false; // Track if comments have been loaded
  List<MarketplaceComment> _comments = [];
  MarketplacePost? _currentPost; // Cache current post for comment count
  bool _isLoadingComments = false;
  bool _isLoadingMoreComments = false;
  bool _isPostingComment = false;
  String? _currentResidentId;
  String? _replyingToCommentId; // ID của comment đang được reply
  MarketplaceComment?
      _replyingToComment; // Comment đang được reply (để hiển thị tên)
  Set<String> _deletingCommentIds =
      {}; // Track comments being deleted for animation
  Set<String> _newCommentIds = {}; // Track new comments for animation
  Set<String> _movedCommentIds =
      {}; // Track comments that were moved (to prevent slide animation)
  int _currentPage = 0;
  int _pageSize = 10;
  bool _hasMoreComments = true;
  Map<String, bool> _expandedComments =
      {}; // Track expanded state for read more
  Set<String> _blockedUserIds = {}; // Cache blocked user IDs
  final Map<String, String> _residentIdToUserIdCache =
      {}; // Cache residentId -> userId mapping
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedImage; // Selected image for comment
  XFile? _selectedVideo; // Selected video for comment

  /// Count nested replies recursively
  int _countNestedReplies(MarketplaceComment comment) {
    int count = 0;
    if (comment.replies.isNotEmpty) {
      for (var reply in comment.replies) {
        count++; // Count this reply
        count += _countNestedReplies(reply); // Count nested replies recursively
      }
    }
    return count;
  }

  /// Calculate total comment count from loaded comments
  /// This is more accurate than trusting API count which might be stale
  int _calculateCommentCount() {
    int total = 0;
    for (var comment in _comments) {
      total++; // Count root comment
      total += _countNestedReplies(comment); // Count all nested replies
    }
    return total;
  }

  /// Check if current user can edit a comment
  /// Returns true if:
  /// - Current user is the comment owner
  bool _canEditComment(MarketplaceComment comment) {
    final currentResidentId = _currentResidentId;
    if (currentResidentId == null) return false;
    // Comment owner can edit their own comment
    return comment.residentId == currentResidentId && !comment.isDeleted;
  }

  /// Check if current user can delete a comment
  /// Returns true if:
  /// - Current user is the post owner, OR
  /// - Current user is the comment owner
  bool _canDeleteComment(MarketplaceComment comment) {
    if (_currentResidentId == null) return false;

    // Post owner can delete any comment
    if (widget.post.residentId == _currentResidentId) {
      return true;
    }

    // Comment owner can delete their own comment
    if (comment.residentId == _currentResidentId) {
      return true;
    }

    return false;
  }

  /// Show delete comment confirmation dialog
  Future<void> _showDeleteCommentDialog(
      BuildContext context, MarketplaceComment comment) async {
    final isRootComment = comment.parentCommentId == null;
    final confirmed = await showSmoothDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa bình luận'),
        content: Text(
          isRootComment
              ? 'Bạn có chắc chắn muốn xóa bình luận này? Tất cả các bình luận con (mọi cấp) sẽ bị xóa.'
              : 'Bạn có chắc chắn muốn xóa bình luận này? Các bình luận con sẽ được giữ lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _deleteComment(comment);
    }
  }

  /// Insert reply into comment tree
  bool _insertReplyIntoTree(MarketplaceComment comment, String parentId,
      MarketplaceComment newReply) {
    if (comment.id == parentId) {
      // Found parent, add reply
      comment.replies.add(newReply);
      return true;
    }
    // Search in replies
    for (var reply in comment.replies) {
      if (_insertReplyIntoTree(reply, parentId, newReply)) {
        return true;
      }
    }
    return false;
  }

  /// Edit a comment
  Future<void> _editComment(
      BuildContext context, MarketplaceComment comment) async {
    final textController = TextEditingController(text: comment.content);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chỉnh sửa bình luận'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Nhập nội dung bình luận...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              final newContent = textController.text.trim();
              if (newContent.isNotEmpty) {
                Navigator.pop(context, newContent);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && context.mounted) {
      try {
        await _marketplaceService.updateComment(
            widget.post.id, comment.id, result);
        if (context.mounted) {
          // Update comment in local state without reloading
          _updateCommentInTree(comment.id, result);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã chỉnh sửa bình luận'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi khi chỉnh sửa bình luận: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Delete a comment
  Future<void> _deleteComment(MarketplaceComment comment) async {
    try {
      // Save scroll position
      final scrollPosition = _scrollController.hasClients
          ? _scrollController.position.pixels
          : 0.0;

      final isRootComment = comment.parentCommentId == null;

      // Start deletion animation
      setState(() {
        _deletingCommentIds.add(comment.id);
      });

      // Wait for animation to start
      await Future.delayed(const Duration(milliseconds: 300));

      // Call API to delete
      await _marketplaceService.deleteComment(widget.post.id, comment.id);

      // Get current post state before updating
      final currentPost = _currentPost ?? widget.post;

      if (mounted) {
        // Remove comment from local list first
        setState(() {
          if (isRootComment) {
            // Remove root comment (entire sub-tree)
            _comments.removeWhere((c) => c.id == comment.id);
          } else {
            // Remove child comment from tree and move its replies to parent
            _comments = _comments.map((rootComment) {
              return _removeCommentFromTreeAndMoveReplies(
                  rootComment, comment.id);
            }).toList();
          }

          // Calculate count from loaded comments after deletion (more accurate)
          // This ensures count is accurate even if comments were loaded from backend
          final calculatedCount =
              _comments.isNotEmpty ? _calculateCommentCount() : 0;
          final newCommentCount = calculatedCount;

          // Update comment count immediately
          _currentPost = MarketplacePost(
            id: currentPost.id,
            residentId: currentPost.residentId,
            buildingId: currentPost.buildingId,
            title: currentPost.title,
            description: currentPost.description,
            price: currentPost.price,
            category: currentPost.category,
            categoryName: currentPost.categoryName,
            status: currentPost.status,
            contactInfo: currentPost.contactInfo,
            location: currentPost.location,
            viewCount: currentPost.viewCount,
            commentCount: newCommentCount,
            images: currentPost.images,
            author: currentPost.author,
            createdAt: currentPost.createdAt,
            updatedAt: currentPost.updatedAt,
          );

          _deletingCommentIds.remove(comment.id);
        });

        // Emit event IMMEDIATELY after removing comment from list and calculating count
        // This ensures marketplace screen gets updated even if widget unmounts
        // Use calculated count from loaded comments (more accurate)
        final updatedCommentCount = _currentPost?.commentCount;
        if (updatedCommentCount != null) {
          print(
              '📡 [PostDetailScreen] Emitting immediate event after deletion: commentCount=$updatedCommentCount, postId=${widget.post.id}');
          AppEventBus().emit('marketplace_update', {
            'type': 'POST_STATS_UPDATE',
            'postId': widget.post.id,
            'commentCount': updatedCommentCount,
            'viewCount': currentPost.viewCount,
          });
        }

        // Remove moved flags after animation completes
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _movedCommentIds.clear();
            });
          }
        });

        // Reload from backend to verify accuracy and emit again if different
        // This ensures we have the correct count from backend
        Future.delayed(const Duration(milliseconds: 800), () {
          // Don't check mounted here - _reloadPostAfterDeletion handles it
          _reloadPostAfterDeletion();
        });

        // Restore scroll position
        if (_scrollController.hasClients) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients && mounted) {
              _scrollController.jumpTo(scrollPosition);
            }
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đã xóa bình luận'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi xóa bình luận: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadBlockedUsers();
    _setupBlockedUsersListener();
    _setupRealtimeUpdates();
    // Don't load comments here - wait for didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load comments after context is available
    if (!_commentsLoaded) {
      _commentsLoaded = true;
      // Load comments first, then reload post with calculated count
      // This ensures _reloadPost() uses calculated count from loaded comments
      _loadComments().then((_) {
        // After comments are loaded, reload post to update with calculated count
        // This ensures comment count is accurate
        _reloadPost();
      });
    }
  }

  /// Check if two image lists are equal
  bool _areImagesEqual(
      List<MarketplacePostImage> images1, List<MarketplacePostImage> images2) {
    if (images1.length != images2.length) return false;
    for (int i = 0; i < images1.length; i++) {
      if (images1[i].id != images2[i].id ||
          images1[i].imageUrl != images2[i].imageUrl) {
        return false;
      }
    }
    return true;
  }

  /// Reload post to get latest data (comment count, view count, images, etc.)
  /// Only updates if data changed to avoid unnecessary rebuilds
  /// Optionally emits event to update marketplace screen
  Future<void> _reloadPost(
      {bool emitEvent = false, bool forceUpdateImages = false}) async {
    try {
      final updatedPost = await _marketplaceService.getPostById(widget.post.id);
      if (mounted) {
        setState(() {
          final currentPost = _currentPost ?? widget.post;

          // Calculate comment count from loaded comments if available
          // This is more accurate than trusting API count which might be stale
          final calculatedCount =
              _comments.isNotEmpty ? _calculateCommentCount() : null;
          final commentCountToUse = calculatedCount ?? updatedPost.commentCount;

          // Check if images changed
          final imagesChanged = forceUpdateImages ||
              updatedPost.images.length != currentPost.images.length ||
              !_areImagesEqual(updatedPost.images, currentPost.images);

          // Only update if comment count, view count, or images changed
          // Use calculated count if available, otherwise use API count
          final shouldUpdate = commentCountToUse != currentPost.commentCount ||
              updatedPost.viewCount != currentPost.viewCount ||
              imagesChanged ||
              updatedPost.title != currentPost.title ||
              updatedPost.description != currentPost.description ||
              updatedPost.price != currentPost.price ||
              updatedPost.category != currentPost.category ||
              updatedPost.location != currentPost.location;

          if (shouldUpdate) {
            // Create updated post with calculated count if available
            final postToUse = calculatedCount != null
                ? MarketplacePost(
                    id: updatedPost.id,
                    residentId: updatedPost.residentId,
                    buildingId: updatedPost.buildingId,
                    title: updatedPost.title,
                    description: updatedPost.description,
                    price: updatedPost.price,
                    category: updatedPost.category,
                    categoryName: updatedPost.categoryName,
                    status: updatedPost.status,
                    contactInfo: updatedPost.contactInfo,
                    location: updatedPost.location,
                    viewCount: updatedPost.viewCount,
                    commentCount: calculatedCount, // Use calculated count
                    images: updatedPost.images,
                    author: updatedPost.author,
                    createdAt: updatedPost.createdAt,
                    updatedAt: updatedPost.updatedAt,
                  )
                : updatedPost; // Use API post if no comments loaded yet

            _currentPost = postToUse;
            print(
                '🔄 [PostDetailScreen] Updated post - commentCount: ${currentPost.commentCount} -> ${postToUse.commentCount}, images: ${currentPost.images.length} -> ${postToUse.images.length}');

            // Always emit event when comment count changes, even if not explicitly requested
            // This ensures marketplace screen gets updated when post is reloaded from backend
            final commentCountChanged =
                commentCountToUse != currentPost.commentCount;
            if (emitEvent || commentCountChanged || imagesChanged) {
              // Use a small delay to ensure setState completes before emitting
              Future.delayed(const Duration(milliseconds: 50), () {
                AppEventBus().emit('marketplace_update', {
                  'type': 'POST_STATS_UPDATE',
                  'postId': widget.post.id,
                  'commentCount': commentCountToUse, // Use calculated count
                  'viewCount': updatedPost.viewCount,
                });
              });
            }
          } else {}
        });
      }
    } catch (e) {
      // Error handled silently in production
    }
  }

  /// Reload post after deletion - always updates comment count from backend
  /// This ensures comment count is accurate after deletion
  /// Emits event with accurate count to update marketplace screen (only if different from current)
  /// Event is emitted even if widget is unmounted to ensure marketplace screen gets updated
  Future<void> _reloadPostAfterDeletion() async {
    try {
      final updatedPost = await _marketplaceService.getPostById(widget.post.id);
      final currentCount =
          _currentPost?.commentCount ?? widget.post.commentCount;
      final updatedCount = updatedPost.commentCount;

      // Only update and emit if backend count differs from current count
      // This prevents unnecessary updates if the immediate event was already correct
      if (updatedCount != currentCount) {
        if (mounted) {
          setState(() {
            _currentPost = updatedPost;
          });
        }

        // Emit event with accurate comment count from backend
        // This ensures marketplace screen gets the correct count if our calculation was wrong
        // Emit even if widget unmounted to ensure marketplace screen gets updated
        AppEventBus().emit('marketplace_update', {
          'type': 'POST_STATS_UPDATE',
          'postId': widget.post.id,
          'commentCount': updatedCount,
          'viewCount': updatedPost.viewCount,
        });
      } else {
        // Still update local state to ensure consistency, but don't emit event
        if (mounted) {
          setState(() {
            _currentPost = updatedPost;
          });
        }
      }
    } catch (e) {
      // Error handled silently in production
      // Don't emit fallback event - we already emitted immediate event
      // If reload fails, the immediate event should be sufficient
    }
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final blockedUserIds = await _chatService.getBlockedUsers();
      if (mounted) {
        setState(() {
          _blockedUserIds = blockedUserIds.toSet();
        });
      }
    } catch (e) {
      // Error handled silently in production
    }
  }

  void _setupBlockedUsersListener() {
    AppEventBus().on('blocked_users_updated', (_) async {
      await _loadBlockedUsers();
      // Refresh comments to show/hide comments from unblocked users
      if (mounted) {
        setState(() {
          // Trigger rebuild to refresh filtered comments
        });
      }
    });
  }

  Future<void> _loadCurrentUser() async {
    _currentResidentId = await _tokenStorage.readResidentId();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    AppEventBus().off('new_comment');
    AppEventBus().off('marketplace_update');
    AppEventBus().off('blocked_users_updated');
    super.dispose();
  }

  Future<void> _editPost(BuildContext context, MarketplacePost post) async {
    // Try to get viewModel if available
    MarketplaceViewModel? viewModel;
    try {
      viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
    } catch (e) {
      // No provider available - edit will still work but won't refresh marketplace
    }

    final navigator = Navigator.of(context);
    // Navigate to edit post screen
    final result = await navigator.push(
      SmoothPageRoute(
        page: EditPostScreen(
          post: post,
          onPostUpdated: () async {
            // Refresh marketplace view model if available
            try {
              final viewModel =
                  Provider.of<MarketplaceViewModel>(context, listen: false);
              await viewModel.refresh();
            } catch (e) {
              // No provider available
            }
          },
        ),
      ),
    );

    // If post was updated, refresh the screen
    if (result == true && mounted) {
      // Reload post data if viewModel is available
      if (viewModel != null) {
        await viewModel.refresh();
      }

      // Reload post detail once to get updated data (images are now uploaded sync, so they should be available immediately)
      if (mounted) {
        await _reloadPost(emitEvent: true, forceUpdateImages: true);
      }

      // Only pop if still mounted and Navigator is still valid
      // Use post-frame callback to ensure widget tree is stable
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          }
        });
      }
    }
  }

  Future<void> _deletePost(BuildContext context, MarketplacePost post) async {
    // Try to get viewModel if available
    MarketplaceViewModel? viewModel;
    try {
      viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
    } catch (e) {
      // No provider available - use service directly
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Show confirmation dialog
    final confirmed = await showSmoothDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text(
            'Bạn có chắc chắn muốn xóa bài đăng này? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        if (viewModel != null) {
          await viewModel.deletePost(post.id);
        } else {
          // Use service directly if no viewModel
          await _marketplaceService.deletePost(post.id);
        }

        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Đã xóa bài đăng')),
          );
          navigator.pop(true); // Go back to marketplace screen
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Lỗi khi xóa bài đăng: $e')),
          );
        }
      }
    }
  }

  void _setupRealtimeUpdates() {
    // Listen for new comments from WebSocket
    AppEventBus().on('new_comment', (data) {
      if (data is Map<String, dynamic>) {
        final postId = data['postId'] as String?;
        if (postId == widget.post.id && mounted) {
          // Reload comments when new comment is added (from other users)
          // Note: If comment was added by current user, it's already in local state
          _loadComments();
          // Reload post to get updated comment count from backend
          // This ensures we have the correct count if multiple users are commenting
          // Emit event to update marketplace screen
          _reloadPost(emitEvent: true);
        }
      }
    });

    // Listen for marketplace updates to update comment count
    AppEventBus().on('marketplace_update', (data) {
      if (data is Map<String, dynamic>) {
        final type = data['type'] as String?;
        final postId = data['postId'] as String?;
        if (postId == widget.post.id &&
            type == 'POST_STATS_UPDATE' &&
            mounted) {
          // Update comment count from event data immediately
          final commentCount = (data['commentCount'] as num?)?.toInt();
          final viewCount = (data['viewCount'] as num?)?.toInt();

          if (commentCount != null || viewCount != null) {
            setState(() {
              // Always update _currentPost, even if it's null (use widget.post as base)
              final currentPost = _currentPost ?? widget.post;

              _currentPost = MarketplacePost(
                id: currentPost.id,
                residentId: currentPost.residentId,
                buildingId: currentPost.buildingId,
                title: currentPost.title,
                description: currentPost.description,
                price: currentPost.price,
                category: currentPost.category,
                categoryName: currentPost.categoryName,
                status: currentPost.status,
                contactInfo: currentPost.contactInfo,
                location: currentPost.location,
                viewCount: viewCount ?? currentPost.viewCount,
                commentCount: commentCount ?? currentPost.commentCount,
                images: currentPost.images,
                author: currentPost.author,
                createdAt: currentPost.createdAt,
                updatedAt: currentPost.updatedAt,
              );
            });
          }

          // Don't reload post immediately - use event data instead
          // Only reload if event data is missing
          if (commentCount == null || viewCount == null) {
            // Emit event after reload to ensure marketplace screen gets updated
            _reloadPost(emitEvent: true);
          }
        }
      }
    });
  }

  Future<void> _loadComments({bool loadMore = false}) async {
    if (loadMore) {
      if (_isLoadingMoreComments || !_hasMoreComments) return;
      setState(() => _isLoadingMoreComments = true);
    } else {
      setState(() {
        _isLoadingComments = true;
        _currentPage = 0;
        _comments = [];
        _hasMoreComments = true;
      });
    }

    try {
      CommentPagedResponse pagedResponse;

      // Try to use MarketplaceViewModel if available, otherwise use MarketplaceService directly
      try {
        final viewModel =
            Provider.of<MarketplaceViewModel>(context, listen: false);
        pagedResponse = await viewModel.getCommentsPaged(
          widget.post.id,
          page: _currentPage,
          size: _pageSize,
        );
      } catch (e) {
        // No provider available, use service directly
        pagedResponse = await _marketplaceService.getCommentsPaged(
          widget.post.id,
          page: _currentPage,
          size: _pageSize,
        );
      }

      if (mounted) {
        setState(() {
          // Filter out deleted comments (backend should already filter, but defensive check)
          final filteredComments = pagedResponse.content
              .where((comment) => !comment.isDeleted)
              .toList();

          if (loadMore) {
            _comments.addAll(filteredComments);
          } else {
            _comments = filteredComments;
          }
          _currentPage = pagedResponse.currentPage + 1;
          _hasMoreComments = pagedResponse.hasNext;
          _isLoadingComments = false;
          _isLoadingMoreComments = false;

          // Update comment count from loaded comments IMMEDIATELY
          // This ensures count is accurate even if API count is stale
          // Emit event immediately to update marketplace screen before any refresh happens
          if (_comments.isNotEmpty) {
            final calculatedCount = _calculateCommentCount();
            final currentPost = _currentPost ?? widget.post;

            // Always update and emit event if calculated count differs from current
            // This ensures marketplace screen gets accurate count immediately
            if (calculatedCount != currentPost.commentCount) {
              _currentPost = MarketplacePost(
                id: currentPost.id,
                residentId: currentPost.residentId,
                buildingId: currentPost.buildingId,
                title: currentPost.title,
                description: currentPost.description,
                price: currentPost.price,
                category: currentPost.category,
                categoryName: currentPost.categoryName,
                status: currentPost.status,
                contactInfo: currentPost.contactInfo,
                location: currentPost.location,
                viewCount: currentPost.viewCount,
                commentCount: calculatedCount,
                images: currentPost.images,
                author: currentPost.author,
                createdAt: currentPost.createdAt,
                updatedAt: currentPost.updatedAt,
              );

              // Emit event IMMEDIATELY to update marketplace screen
              // Don't delay - we want marketplace screen to get accurate count ASAP
              AppEventBus().emit('marketplace_update', {
                'type': 'POST_STATS_UPDATE',
                'postId': widget.post.id,
                'commentCount': calculatedCount,
                'viewCount': currentPost.viewCount,
              });
              print('✅ [PostDetailScreen] Event emitted successfully');
            } else {
              print(
                  'ℹ️ [PostDetailScreen] Calculated count matches current count ($calculatedCount), no update needed');
            }
          } else {
            print(
                'ℹ️ [PostDetailScreen] No comments loaded yet, skipping count calculation');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
          _isLoadingMoreComments = false;
        });
        // Only show error if context is available (not in initState)
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi khi tải bình luận: $e')),
          );
        }
      }
    }
  }

  void _toggleCommentExpand(String commentId) {
    setState(() {
      _expandedComments[commentId] = !(_expandedComments[commentId] ?? false);
    });
  }

  Future<void> _postComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty && _selectedImage == null && _selectedVideo == null)
      return;

    setState(() => _isPostingComment = true);
    try {
      String? imageUrl;
      String? videoUrl;

      // Upload image if selected to ImageKit
      if (_selectedImage != null) {
        try {
          imageUrl = await _imageKitService.uploadImage(
            file: _selectedImage!,
            folder: 'marketplace/comments/${widget.post.id}',
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi khi upload ảnh: ${e.toString()}')),
            );
          }
          return;
        }
      }

      // Upload video if selected to data-docs-service (not ImageKit)
      if (_selectedVideo != null) {
        try {
          // Lấy userId từ storage
          final userId = await ApiClient().storage.readUserId();
          if (userId == null) {
            throw Exception(
                'Không tìm thấy thông tin người dùng. Vui lòng đăng nhập lại.');
          }

          // Nén video trước khi upload
          final compressedFile =
              await VideoCompressionService.instance.compressVideo(
            videoPath: _selectedVideo!.path,
            onProgress: (message) {
              print('Video compression: $message');
            },
          );

          final videoFileToUpload =
              compressedFile ?? File(_selectedVideo!.path);

          // Lấy video metadata nếu có thể
          String? resolution;
          int? durationSeconds;
          int? width;
          int? height;

          try {
            final mediaInfo =
                await VideoCompress.getMediaInfo(videoFileToUpload.path);
            if (mediaInfo != null) {
              if (mediaInfo.width != null && mediaInfo.height != null) {
                width = mediaInfo.width;
                height = mediaInfo.height;
                if (height! <= 360) {
                  resolution = '360p';
                } else if (height! <= 480) {
                  resolution = '480p';
                } else if (height! <= 720) {
                  resolution = '720p';
                } else {
                  resolution = '1080p';
                }
              }
              if (mediaInfo.duration != null) {
                durationSeconds = (mediaInfo.duration! / 1000).round();
              }
            }
          } catch (e) {
            print('⚠️ Không thể lấy video metadata: $e');
          }

          // Upload video lên data-docs-service
          final videoData = await _imageKitService.uploadVideo(
            file: videoFileToUpload,
            category: 'marketplace_comment',
            ownerId: widget.post.id, // Sử dụng postId làm ownerId
            uploadedBy: userId,
            resolution: resolution,
            durationSeconds: durationSeconds,
            width: width,
            height: height,
          );

          videoUrl = videoData['fileUrl'] as String;
          print(
              '✅ [PostDetailScreen] Video comment uploaded to backend: $videoUrl');

          // Xóa file nén nếu khác file gốc
          if (compressedFile != null &&
              compressedFile.path != _selectedVideo!.path) {
            try {
              await compressedFile.delete();
            } catch (e) {
              print('⚠️ Không thể xóa file nén: $e');
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi khi upload video: ${e.toString()}')),
            );
          }
          return;
        }
      }

      MarketplaceComment? newComment;

      // Try to use MarketplaceViewModel if available, otherwise use MarketplaceService directly
      try {
        final viewModel =
            Provider.of<MarketplaceViewModel>(context, listen: false);
        newComment = await viewModel.addComment(
          widget.post.id,
          content
              .trim(), // Send trimmed content (can be empty if image/video is provided)
          parentCommentId: _replyingToCommentId,
          imageUrl: imageUrl,
          videoUrl: videoUrl,
        );
      } catch (e) {
        // No provider available, use service directly
        newComment = await _marketplaceService.addComment(
          postId: widget.post.id,
          content: content
              .trim(), // Send trimmed content (can be empty if image/video is provided)
          parentCommentId: _replyingToCommentId,
          imageUrl: imageUrl,
          videoUrl: videoUrl,
        );
      }

      if (newComment != null && mounted) {
        _commentController.clear();
        final wasReplying = _replyingToCommentId != null;
        _replyingToCommentId = null;
        _replyingToComment = null;
        _selectedImage = null;
        _selectedVideo = null;

        // Save scroll position
        final scrollPosition = _scrollController.hasClients
            ? _scrollController.position.pixels
            : 0.0;

        // Insert comment into local list with animation
        setState(() {
          if (newComment != null) {
            _newCommentIds.add(newComment.id);

            if (wasReplying && newComment.parentCommentId != null) {
              // Insert as reply to parent comment
              for (var rootComment in _comments) {
                if (_insertReplyIntoTree(
                    rootComment, newComment.parentCommentId!, newComment)) {
                  break;
                }
              }
            } else {
              // Insert as root comment (at the end)
              _comments.add(newComment);
            }
          }
        });

        // Update comment count from loaded comments (more accurate than +1)
        // This ensures count is accurate even if comments were loaded from backend
        setState(() {
          final currentPost = _currentPost ?? widget.post;
          // Calculate count from loaded comments if available, otherwise use +1
          final calculatedCount =
              _comments.isNotEmpty ? _calculateCommentCount() : null;
          final newCommentCount =
              calculatedCount ?? (currentPost.commentCount + 1);

          _currentPost = MarketplacePost(
            id: currentPost.id,
            residentId: currentPost.residentId,
            buildingId: currentPost.buildingId,
            title: currentPost.title,
            description: currentPost.description,
            price: currentPost.price,
            category: currentPost.category,
            categoryName: currentPost.categoryName,
            status: currentPost.status,
            contactInfo: currentPost.contactInfo,
            location: currentPost.location,
            viewCount: currentPost.viewCount,
            commentCount: newCommentCount,
            images: currentPost.images,
            author: currentPost.author,
            createdAt: currentPost.createdAt,
            updatedAt: currentPost.updatedAt,
          );
        });

        // Emit event IMMEDIATELY to update marketplace screen (realtime update)
        // Use calculated count if available, otherwise use updated _currentPost count
        final updatedCommentCount = _currentPost?.commentCount;
        if (updatedCommentCount != null) {
          AppEventBus().emit('marketplace_update', {
            'type': 'POST_STATS_UPDATE',
            'postId': widget.post.id,
            'commentCount': updatedCommentCount,
            'viewCount': (_currentPost ?? widget.post).viewCount,
          });
        }

        // Restore scroll position after a brief delay to allow animation
        if (_scrollController.hasClients) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients && mounted) {
              _scrollController.jumpTo(scrollPosition);
              // Smooth scroll to new comment if it's visible
              Future.delayed(const Duration(milliseconds: 300), () {
                if (_scrollController.hasClients && mounted) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
            }
          });
        }

        // Remove animation flag after animation completes
        final commentId = newComment.id;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _newCommentIds.remove(commentId);
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi đăng bình luận: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPostingComment = false);
      }
    }
  }

  void _startReply(MarketplaceComment comment) {
    setState(() {
      _replyingToCommentId = comment.id;
      _replyingToComment = comment;
    });
    // Focus vào comment input
    // Scroll to comment input
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  String _getCategoryDisplayName(MarketplacePost post) {
    // Backend có thể trả về categoryName = category code, nên luôn map từ danh sách categories
    if (post.category.isNotEmpty) {
      try {
        final viewModel =
            Provider.of<MarketplaceViewModel>(context, listen: false);
        final category = viewModel.categories.firstWhere(
          (cat) => cat.code == post.category,
        );
        // Luôn dùng name (tiếng Việt) từ danh sách categories
        return category.name;
      } catch (e) {
        // Nếu không tìm thấy category, kiểm tra categoryName
        if (post.categoryName.isNotEmpty &&
            post.categoryName != post.category) {
          return post.categoryName;
        }
        // Fallback về code
        return post.category;
      }
    }

    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Read _currentPost here to ensure rebuild when it changes
    final currentPostForBuild = _currentPost;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Chi tiết bài đăng'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Show edit/delete buttons only if current user is the post owner
          if (_currentResidentId != null &&
              widget.post.residentId == _currentResidentId)
            PopupMenuButton<String>(
              icon: Icon(
                CupertinoIcons.ellipsis,
                color: theme.colorScheme.onSurface,
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  _editPost(context, widget.post);
                } else if (value == 'delete') {
                  _deletePost(context, widget.post);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.pencil,
                          size: 20, color: theme.colorScheme.onSurface),
                      const SizedBox(width: 12),
                      const Text('Chỉnh sửa'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.delete,
                          size: 20, color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Text('Xóa',
                          style: TextStyle(color: theme.colorScheme.error)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Builder(
        // Use key based on _currentPost to force rebuild when it changes
        // Read _currentPost directly in build method to ensure rebuild
        key: ValueKey(
            'post_detail_body_${currentPostForBuild?.commentCount ?? widget.post.commentCount}'),
        builder: (context) {
          // Try to get updated post from viewModel if available
          // But prioritize _currentPost which is updated immediately on comment add/delete
          // IMPORTANT: Read _currentPost directly here (not from outer scope) to ensure rebuild
          final currentPost = _currentPost;
          MarketplacePost updatedPost = currentPost ?? widget.post;

          try {
            final viewModel =
                Provider.of<MarketplaceViewModel>(context, listen: false);
            final vmPost = viewModel.posts.firstWhere(
              (p) => p.id == widget.post.id,
              orElse: () => updatedPost,
            );
            // Use viewModel post if _currentPost is null
            if (currentPost == null) {
              updatedPost = vmPost;
            }
          } catch (e) {
            // No provider available, use _currentPost or widget.post
          }

          return Column(
            children: [
              // Post Content
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Post Card
                      Builder(
                        builder: (context) {
                          MarketplaceViewModel? viewModel;
                          try {
                            viewModel = Provider.of<MarketplaceViewModel>(
                                context,
                                listen: false);
                          } catch (e) {
                            // No provider available
                            viewModel = null;
                          }
                          return _buildPostCard(
                              context, theme, isDark, updatedPost, viewModel);
                        },
                      ),

                      const SizedBox(height: 24),

                      // Comments Section
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.chat_bubble_fill,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          // Display comment count - will rebuild when _currentPost changes via setState
                          // Use key to force rebuild when comment count changes
                          // IMPORTANT: Read _currentPost directly here, not from outer Builder's updatedPost
                          Builder(
                            key: ValueKey(
                                'comment_count_${_currentPost?.commentCount ?? updatedPost.commentCount}'),
                            builder: (context) {
                              // Always read _currentPost directly from state, not from outer Builder's updatedPost
                              // This ensures the count updates immediately when _currentPost changes
                              final currentPostFromState = _currentPost;

                              // Priority: _currentPost > updatedPost > viewModel post
                              // _currentPost is always the most up-to-date because it's updated realtime in this screen
                              MarketplacePost postToUse =
                                  currentPostFromState ?? updatedPost;

                              // Check viewModel for realtime updates from other screens
                              // But only use it if _currentPost is null (fallback)
                              try {
                                final viewModel =
                                    Provider.of<MarketplaceViewModel>(context,
                                        listen: true);
                                final vmPost = viewModel.posts.firstWhere(
                                  (p) => p.id == widget.post.id,
                                  orElse: () => postToUse,
                                );

                                // Only use viewModel post if _currentPost is null
                                // Otherwise, _currentPost is the source of truth for this screen
                                if (currentPostFromState == null &&
                                    vmPost.commentCount !=
                                        postToUse.commentCount) {
                                  return Text(
                                    'Bình luận (${vmPost.commentCount})',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                }
                              } catch (e) {
                                // ViewModel not available, use _currentPost or updatedPost
                              }

                              return Text(
                                'Bình luận (${postToUse.commentCount})',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Comments List
                      if (_isLoadingComments)
                        _buildCommentSkeleton(theme)
                      else if (_comments.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              children: [
                                Icon(
                                  CupertinoIcons.chat_bubble,
                                  size: 48,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Chưa có bình luận nào',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        // Comments với staggered animation
                        ..._comments.asMap().entries.map((entry) {
                          final index = entry.key;
                          final comment = entry.value;
                          return SmoothAnimations.staggeredItem(
                            index: index,
                            child: _buildCommentCard(
                              context,
                              theme,
                              comment,
                              depth: 0,
                            ),
                          );
                        }).toList(),
                        // Load more button với smooth animation
                        if (_hasMoreComments)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: Center(
                              child: _isLoadingMoreComments
                                  ? const CircularProgressIndicator()
                                  : SmoothAnimations.fadeIn(
                                      child: FilledButton.icon(
                                        onPressed: () =>
                                            _loadComments(loadMore: true),
                                        icon: const Icon(
                                            CupertinoIcons.arrow_down,
                                            size: 16),
                                        label: const Text('Hiển thị thêm'),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 12),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                      ],

                      const SizedBox(height: 80), // Space for input field
                    ],
                  ),
                ),
              ),

              // Comment Input
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Reply banner với smooth slide animation
                  if (_replyingToComment != null)
                    SmoothAnimations.slideIn(
                      slideOffset: const Offset(0, -20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.reply,
                              size: 16,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Đang trả lời ${_replyingToComment!.author?.name ?? 'Người dùng'}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _replyingToComment = null;
                                  _replyingToCommentId = null;
                                });
                              },
                              child: Icon(
                                CupertinoIcons.xmark_circle_fill,
                                size: 20,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Comment input container
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? theme.colorScheme.surfaceContainerHigh
                          : theme.colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 8,
                      bottom: MediaQuery.of(context).padding.bottom + 8,
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Preview selected image/video
                          if (_selectedImage != null || _selectedVideo != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              height: 100,
                              child: Row(
                                children: [
                                  if (_selectedImage != null)
                                    Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.file(
                                            File(_selectedImage!.path),
                                            width: 100,
                                            height: 100,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: IconButton(
                                            icon: const Icon(
                                                CupertinoIcons
                                                    .xmark_circle_fill,
                                                color: Colors.red),
                                            onPressed: () {
                                              setState(() {
                                                _selectedImage = null;
                                              });
                                            },
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (_selectedVideo != null)
                                    Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Container(
                                            width: 100,
                                            height: 100,
                                            color: Colors.black,
                                            child: Icon(
                                              CupertinoIcons.play_circle_fill,
                                              color: Colors.white,
                                              size: 40,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: IconButton(
                                            icon: const Icon(
                                                CupertinoIcons
                                                    .xmark_circle_fill,
                                                color: Colors.red),
                                            onPressed: () {
                                              setState(() {
                                                _selectedVideo = null;
                                              });
                                            },
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _commentController,
                                  decoration: InputDecoration(
                                    hintText: _replyingToComment != null
                                        ? 'Viết câu trả lời...'
                                        : 'Viết bình luận...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  maxLines: null,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _postComment(),
                                ),
                              ),
                              // Image/Video picker button
                              IconButton(
                                onPressed:
                                    _isPostingComment ? null : _showMediaPicker,
                                icon: Icon(
                                  CupertinoIcons.photo_camera,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Send button
                              IconButton(
                                onPressed:
                                    _isPostingComment ? null : _postComment,
                                icon: _isPostingComment
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : Icon(
                                        CupertinoIcons.paperplane_fill,
                                        color: theme.colorScheme.primary,
                                      ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showMediaPicker() async {
    final result = await showSmoothBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.photo),
              title: const Text('Chọn ảnh từ thư viện'),
              onTap: () => Navigator.pop(context, 'image_gallery'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.camera_fill),
              title: const Text('Chụp ảnh'),
              onTap: () => Navigator.pop(context, 'image_camera'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.videocam),
              title: const Text('Chọn video từ thư viện'),
              onTap: () => Navigator.pop(context, 'video_gallery'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.videocam_fill),
              title: const Text('Quay video'),
              onTap: () => Navigator.pop(context, 'video_camera'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'image_gallery') {
      await _pickImage(source: ImageSource.gallery);
    } else if (result == 'image_camera') {
      await _pickImage(source: ImageSource.camera);
    } else if (result == 'video_gallery') {
      await _pickVideo(source: ImageSource.gallery);
    } else if (result == 'video_camera') {
      await _pickVideo(source: ImageSource.camera);
    }
  }

  Future<void> _pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
          _selectedVideo = null; // Clear video if image is selected
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi chọn ảnh: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _pickVideo({ImageSource source = ImageSource.gallery}) async {
    try {
      final video = await _imagePicker.pickVideo(
        source: source,
      );
      if (video != null) {
        setState(() {
          _selectedVideo = video;
          _selectedImage = null; // Clear image if video is selected
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi chọn video: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildPostCard(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    MarketplacePost post,
    MarketplaceViewModel? viewModel,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header - Người đăng bài
            Row(
              children: [
                GestureDetector(
                  onTap: () => _showPostAuthorOptions(context, post),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      CupertinoIcons.person_fill,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _showPostAuthorOptions(context, post),
                        child: Text(
                          post.author?.name ?? 'Người dùng',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.visible,
                          softWrap: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (post.author?.unitNumber != null ||
                          post.author?.buildingName != null)
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.home,
                              size: 16,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                            if (post.author?.buildingName != null) ...[
                              Text(
                                post.author!.buildingName!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (post.author?.unitNumber != null) ...[
                                Text(
                                  ' - ',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ],
                            if (post.author?.unitNumber != null)
                              Text(
                                post.author!.unitNumber!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatDate(post.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              post.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (post.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                post.description,
                style: theme.textTheme.bodyLarge,
              ),
            ],

            // Separate images and video
            Builder(
              builder: (context) {
                final allMedia = post.images;
                final images = <MarketplacePostImage>[];
                MarketplacePostImage? video;

                for (var media in allMedia) {
                  final url = media.imageUrl.toLowerCase();
                  final isVideo = url.contains('.mp4') ||
                      url.contains('.mov') ||
                      url.contains('.avi') ||
                      url.contains('.webm') ||
                      url.contains('.mkv') ||
                      url.contains('video/') ||
                      (media.thumbnailUrl == null &&
                          !url.contains('.jpg') &&
                          !url.contains('.jpeg') &&
                          !url.contains('.png') &&
                          !url.contains('.webp') &&
                          !url.contains('.gif'));

                  if (isVideo) {
                    video = media;
                  } else {
                    images.add(media);
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Video (if exists)
                    if (video != null) ...[
                      const SizedBox(height: 16),
                      VideoPreviewWidget(
                        videoUrl: video.imageUrl,
                        height: 300,
                        onTap: () {
                          Navigator.push(
                            context,
                            SmoothPageRoute(
                              page: VideoViewerScreen(
                                videoUrl: video!.imageUrl,
                                title: post.title,
                              ),
                            ),
                          );
                        },
                      ),
                    ],

                    // Images
                    if (images.isNotEmpty) ...[
                      SizedBox(height: video != null ? 16 : 0),
                      SizedBox(
                        height: 300,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: images.length,
                          itemBuilder: (context, index) {
                            final image = images[index];
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  SmoothPageRoute(
                                    page: ImageViewerScreen(
                                      images: images,
                                      initialIndex: index,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                width: 300,
                                margin: EdgeInsets.only(
                                  right: index < images.length - 1 ? 8 : 0,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: image.imageUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: image.imageUrl,
                                          fit: BoxFit.cover,
                                          httpHeaders: {
                                            'ngrok-skip-browser-warning':
                                                'true',
                                          },
                                          placeholder: (context, url) {
                                            return Container(
                                              color: theme.colorScheme
                                                  .surfaceContainerHighest,
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                              ),
                                            );
                                          },
                                          errorWidget: (context, url, error) {
                                            return Container(
                                              color: theme.colorScheme
                                                  .surfaceContainerHighest,
                                              child: Icon(
                                                CupertinoIcons.photo,
                                                size: 48,
                                                color: theme
                                                    .colorScheme.onSurface
                                                    .withValues(alpha: 0.3),
                                              ),
                                            );
                                          },
                                        )
                                      : Container(
                                          color: theme.colorScheme
                                              .surfaceContainerHighest,
                                          child: Icon(
                                            CupertinoIcons.photo,
                                            size: 48,
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.3),
                                          ),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),

            const SizedBox(height: 12),

            // Price, Category, Location
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (post.price != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.money_dollar,
                          size: 14,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          post.priceDisplay,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (post.category.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.square_grid_2x2,
                          size: 12,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getCategoryDisplayName(post),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (post.location != null && post.location!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.location,
                          size: 12,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            post.location!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            // Contact Info - Always show phone and email if available
            Builder(
              builder: (context) {
                // Debug logging

                if (post.contactInfo != null &&
                    ((post.contactInfo!.phone != null &&
                            post.contactInfo!.phone!.isNotEmpty) ||
                        (post.contactInfo!.email != null &&
                            post.contactInfo!.email!.isNotEmpty))) {
                  return Column(
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  CupertinoIcons.phone_circle,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Thông tin liên hệ',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (post.contactInfo!.phone != null &&
                                post.contactInfo!.phone!.isNotEmpty) ...[
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.phone,
                                    size: 16,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      post.contactInfo!.phone!,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                              if (post.contactInfo!.email != null &&
                                  post.contactInfo!.email!.isNotEmpty)
                                const SizedBox(height: 12),
                            ],
                            if (post.contactInfo!.email != null &&
                                post.contactInfo!.email!.isNotEmpty)
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.mail,
                                    size: 16,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      post.contactInfo!.email!,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                } else {
                  return const SizedBox.shrink();
                }
              },
            ),

            // Removed Actions section (comment icon) since we have a dedicated Comments Section below
            // The comment count is displayed in the Comments Section header instead
          ],
        ),
      ),
    );
  }

  Widget _buildCommentCard(
    BuildContext context,
    ThemeData theme,
    MarketplaceComment comment, {
    int depth = 0, // Độ sâu của reply (0 = top-level comment)
  }) {
    final isReply = depth > 0;
    // Filter out deleted replies
    final activeReplies =
        comment.replies.where((reply) => !reply.isDeleted).toList();

    final isDeleting = _deletingCommentIds.contains(comment.id);
    final isNew = _newCommentIds.contains(comment.id);
    final isMoved = _movedCommentIds.contains(comment.id);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isDeleting ? 0.0 : 1.0,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 400),
          tween: Tween(begin: (isNew && !isMoved) ? 0.0 : 1.0, end: 1.0),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            // Don't slide if comment was moved (to prevent push-up animation)
            return Transform.translate(
              offset: Offset((isNew && !isMoved) ? (1 - value) * 20 : 0, 0),
              child: Opacity(
                opacity: (isNew && !isMoved) ? value : 1.0,
                child: child,
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: EdgeInsets.only(
                  bottom: 12,
                  left: isReply ? 32.0 : 0, // Indent cho replies
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: isReply
                      ? Border(
                          left: BorderSide(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.3),
                            width: 3,
                          ),
                        )
                      : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _showCommentAuthorOptions(context, comment),
                      child: CircleAvatar(
                        radius: isReply ? 14 : 16,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          CupertinoIcons.person_fill,
                          size: isReply ? 14 : 16,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: GestureDetector(
                                  onTap: () => _showCommentAuthorOptions(
                                      context, comment),
                                  child: Text(
                                    comment.author?.name ?? 'Người dùng',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDate(comment.createdAt),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          _buildCommentContent(context, theme, comment),
                          const SizedBox(height: 8),
                          // Action buttons (Reply and Delete)
                          Row(
                            children: [
                              // Reply button
                              InkWell(
                                onTap: () => _startReply(comment),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      CupertinoIcons.arrow_turn_down_right,
                                      size: 16,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Trả lời',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Menu 3 chấm (only show if user is post owner or comment owner)
                              if (_canDeleteComment(comment) ||
                                  _canEditComment(comment)) ...[
                                const SizedBox(width: 16),
                                PopupMenuButton<String>(
                                  icon: Icon(
                                    CupertinoIcons.ellipsis,
                                    size: 16,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      await _editComment(context, comment);
                                    } else if (value == 'delete') {
                                      await _showDeleteCommentDialog(
                                          context, comment);
                                    }
                                  },
                                  itemBuilder: (context) {
                                    final items = <PopupMenuEntry<String>>[];
                                    if (_canEditComment(comment)) {
                                      items.add(
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(CupertinoIcons.pencil,
                                                  size: 18, color: Colors.blue),
                                              SizedBox(width: 8),
                                              Text('Chỉnh sửa'),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                    if (_canEditComment(comment) &&
                                        _canDeleteComment(comment)) {
                                      items.add(const PopupMenuDivider());
                                    }
                                    if (_canDeleteComment(comment)) {
                                      items.add(
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(CupertinoIcons.delete,
                                                  size: 18, color: Colors.red),
                                              SizedBox(width: 8),
                                              Text('Xóa',
                                                  style: TextStyle(
                                                      color: Colors.red)),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                    return items;
                                  },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Hiển thị replies nếu có (filter out deleted replies)
              if (activeReplies.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...activeReplies.map((reply) => _buildCommentCard(
                      context,
                      theme,
                      reply,
                      depth: depth + 1,
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Update comment content in the comment tree recursively
  void _updateCommentInTree(String commentId, String newContent) {
    final updatedComments = _comments.map((comment) {
      return _updateCommentInTreeRecursive(comment, commentId, newContent);
    }).toList();

    setState(() {
      _comments = updatedComments;
    });
  }

  /// Recursively update comment in tree
  MarketplaceComment _updateCommentInTreeRecursive(
      MarketplaceComment comment, String commentId, String newContent) {
    if (comment.id == commentId) {
      // Found the comment to update
      return MarketplaceComment(
        id: comment.id,
        postId: comment.postId,
        residentId: comment.residentId,
        parentCommentId: comment.parentCommentId,
        content: newContent,
        author: comment.author,
        replies: comment.replies,
        replyCount: comment.replyCount,
        createdAt: comment.createdAt,
        updatedAt: DateTime.now(),
        isDeleted: comment.isDeleted,
        imageUrl: comment.imageUrl,
        videoUrl: comment.videoUrl,
      );
    } else {
      // Recursively update replies
      final updatedReplies = comment.replies.map((reply) {
        return _updateCommentInTreeRecursive(reply, commentId, newContent);
      }).toList();

      return MarketplaceComment(
        id: comment.id,
        postId: comment.postId,
        residentId: comment.residentId,
        parentCommentId: comment.parentCommentId,
        content: comment.content,
        author: comment.author,
        replies: updatedReplies,
        replyCount: comment.replyCount,
        createdAt: comment.createdAt,
        updatedAt: comment.updatedAt,
        isDeleted: comment.isDeleted,
        imageUrl: comment.imageUrl,
        videoUrl: comment.videoUrl,
      );
    }
  }

  /// Remove comment from tree recursively and move its replies to parent
  /// Returns a new comment tree with the comment removed and replies moved
  MarketplaceComment _removeCommentFromTreeAndMoveReplies(
      MarketplaceComment comment, String commentIdToDelete) {
    // Check if any reply matches
    final updatedReplies = <MarketplaceComment>[];

    for (var reply in comment.replies) {
      if (reply.id == commentIdToDelete) {
        // Found the comment to delete - skip it but keep its replies
        // Move replies to parent comment (current comment)
        if (reply.replies.isNotEmpty) {
          // Create new comment objects with updated parentCommentId
          final movedReplies = reply.replies.map((childReply) {
            // Mark as moved to prevent slide animation
            _movedCommentIds.add(childReply.id);
            return MarketplaceComment(
              id: childReply.id,
              postId: childReply.postId,
              residentId: childReply.residentId,
              parentCommentId: comment.id, // Update to point to parent
              content: childReply.content,
              author: childReply.author,
              replies: childReply.replies, // Keep nested replies as is
              replyCount: childReply.replyCount,
              createdAt: childReply.createdAt,
              updatedAt: childReply.updatedAt,
              isDeleted: childReply.isDeleted,
              imageUrl: childReply.imageUrl,
              videoUrl: childReply.videoUrl,
            );
          }).toList();

          // Add moved replies to current comment's replies
          updatedReplies.addAll(movedReplies);
        }
      } else {
        // Recursively process this reply
        final updatedReply =
            _removeCommentFromTreeAndMoveReplies(reply, commentIdToDelete);
        updatedReplies.add(updatedReply);
      }
    }

    // Return updated comment with new replies list
    return MarketplaceComment(
      id: comment.id,
      postId: comment.postId,
      residentId: comment.residentId,
      parentCommentId: comment.parentCommentId,
      content: comment.content,
      author: comment.author,
      replies: updatedReplies,
      replyCount: comment.replyCount,
      createdAt: comment.createdAt,
      updatedAt: comment.updatedAt,
      isDeleted: comment.isDeleted,
      imageUrl: comment.imageUrl,
      videoUrl: comment.videoUrl,
    );
  }

  Future<void> _showPostAuthorOptions(
      BuildContext context, MarketplacePost post) async {
    // Don't show options if user is viewing their own post
    if (_currentResidentId != null && post.residentId == _currentResidentId) {
      return;
    }

    // Get author userId from residentId (check cache first)
    String? authorUserId =
        post.author?.userId ?? _residentIdToUserIdCache[post.residentId];

    if (authorUserId == null) {
      try {
        final response =
            await _apiClient.dio.get('/residents/${post.residentId}');
        authorUserId = response.data['userId']?.toString();

        // Cache it for future use
        if (authorUserId != null) {
          _residentIdToUserIdCache[post.residentId] = authorUserId;
        }
      } catch (e) {
        print('⚠️ [PostDetailScreen] Error getting userId: $e');
      }
    }

    // Check if user is blocked
    final isBlocked =
        authorUserId != null && _blockedUserIds.contains(authorUserId);

    // If blocked, show message that user is not found
    if (isBlocked) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không tìm thấy người dùng'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Check if user has active conversation/friendship
    Friend? friend;
    try {
      final friends = await _chatService.getFriends();
      friend = friends.firstWhere(
        (f) => f.friendId == post.residentId,
        orElse: () => Friend(
          friendId: '',
          friendName: '',
          friendPhone: '',
          hasActiveConversation: false,
        ),
      );
    } catch (e) {
      print('⚠️ [PostDetailScreen] Error getting friends: $e');
    }

    final hasActiveConversation = friend != null &&
        friend.friendId == post.residentId &&
        friend.hasActiveConversation &&
        friend.conversationId != null;

    // Show options menu
    final result = await showSmoothBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.chat_bubble),
              title: Text(hasActiveConversation ? 'Mở chat' : 'Gửi tin nhắn'),
              onTap: () => Navigator.pop(
                  context, hasActiveConversation ? 'open_chat' : 'message'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.group),
              title: const Text('Mời vào nhóm'),
              onTap: () => Navigator.pop(context, 'invite_group'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.person_crop_circle_badge_xmark,
                  color: Colors.red),
              title: const Text('Chặn người dùng'),
              onTap: () => Navigator.pop(context, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'open_chat' &&
        context.mounted &&
        friend != null &&
        friend.conversationId != null) {
      // Navigate directly to direct chat
      final friendData = friend;
      final conversationId = friendData.conversationId!;
      // Navigator.push(
      //   context,
      //   SmoothPageRoute(
      //     page: DirectChatScreen(
      //       conversationId: conversationId,
      //       otherParticipantName: friendData.friendName.isNotEmpty ? friendData.friendName : (post.author?.name ?? 'Người dùng'),
      //     ),
      //   ),
      // );
    } else if (result == 'message' && context.mounted && authorUserId != null) {
      await _showDirectChatFromPost(context, post, authorUserId);
    } else if (result == 'invite_group' && context.mounted) {
      await _inviteToGroupFromPost(context, post);
    } else if (result == 'block' && context.mounted && authorUserId != null) {
      await _blockUserFromPost(
          context, authorUserId, post.author?.name ?? 'Người dùng');
    }
  }

  Future<void> _showDirectChatFromPost(
      BuildContext context, MarketplacePost post, String userId) async {
    final result = await showSmoothDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trò chuyện'),
        content: Text(
          'Bạn có muốn gửi tin nhắn trực tiếp cho ${post.author?.name ?? 'cư dân này'} không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi tin nhắn'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đang tạo lời mời...')),
        );

        await _chatService.createDirectInvitation(
          inviteeId: post.residentId,
          initialMessage: null,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã gửi lời mời trò chuyện'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          // Extract error message - remove "Exception: " prefix if present
          String errorMessage = e.toString().replaceFirst('Exception: ', '');

          // Check if this is an informational message (not an error)
          bool isInfoMessage =
              errorMessage.contains('Bạn đã gửi lời mời rồi') ||
                  errorMessage.contains('đã gửi lời mời cho bạn rồi');

          // If error message already contains the full message, use it directly
          if (!errorMessage.startsWith('Lỗi') &&
              !errorMessage.contains('đã gửi lời mời')) {
            errorMessage = 'Lỗi: $errorMessage';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: isInfoMessage ? Colors.orange : Colors.red,
              duration: Duration(seconds: isInfoMessage ? 5 : 4),
            ),
          );
        }
      }
    }
  }

  Future<void> _inviteToGroupFromPost(
      BuildContext context, MarketplacePost post) async {
    try {
      // Get phone number from residentId first
      String? phoneNumber;
      try {
        final response =
            await _apiClient.dio.get('/residents/${post.residentId}');
        phoneNumber = response.data['phone']?.toString();
      } catch (e) {
        print('⚠️ [PostDetailScreen] Error getting phone number: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể lấy số điện thoại của người dùng'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (phoneNumber == null || phoneNumber.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Người dùng này chưa có số điện thoại'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get user's groups
      final groupsResponse = await _chatService.getMyGroups(page: 0, size: 100);
      final groups = groupsResponse.content;

      ChatGroup? selectedGroup;
      bool createNewGroup = false;

      if (groups.isEmpty) {
        // No groups, create a new one
        final groupData = await showSmoothDialog<Map<String, String?>>(
          context: context,
          builder: (context) => CreateGroupDialog(
            defaultName: 'Nhóm với ${post.author?.name ?? 'người dùng'}',
          ),
        );

        if (groupData == null || !context.mounted) {
          return;
        }

        createNewGroup = true;

        // Show loading
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đang tạo nhóm...')),
          );
        }

        // Create new group
        try {
          selectedGroup = await _chatService.createGroup(
            name: groupData['name']!,
            description: groupData['description'],
          );

          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đang gửi lời mời...')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lỗi khi tạo nhóm: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } else {
        // Show group selection dialog
        final result = await showSmoothDialog<dynamic>(
          context: context,
          builder: (context) => SelectGroupDialog(
            groups: groups,
            targetResidentId: post.residentId,
            currentResidentId: _currentResidentId,
          ),
        );

        if (result == null || !context.mounted) {
          return;
        }

        if (result == 'create_new') {
          // User wants to create a new group
          final groupData = await showSmoothDialog<Map<String, String?>>(
            context: context,
            builder: (context) => CreateGroupDialog(
              defaultName: 'Nhóm với ${post.author?.name ?? 'người dùng'}',
            ),
          );

          if (groupData == null || !context.mounted) {
            return;
          }

          createNewGroup = true;

          // Show loading
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đang tạo nhóm...')),
            );
          }

          // Create new group
          try {
            selectedGroup = await _chatService.createGroup(
              name: groupData['name']!,
              description: groupData['description'],
            );

            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đang gửi lời mời...')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Lỗi khi tạo nhóm: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        } else if (result is ChatGroup) {
          selectedGroup = result;

          // Check if user is already in the group
          if (selectedGroup.members != null) {
            final isAlreadyMember = selectedGroup.members!.any(
              (member) => member.residentId == post.residentId,
            );

            if (isAlreadyMember) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${post.author?.name ?? 'Người dùng'} đã ở trong nhóm "${selectedGroup.name}"'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
              return;
            }
          }

          // Show loading
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đang gửi lời mời...')),
            );
          }
        } else {
          return;
        }
      }

      // Invite to group
      await _chatService.inviteMembersByPhone(
        groupId: selectedGroup.id,
        phoneNumbers: [phoneNumber],
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(createNewGroup
                ? 'Đã tạo nhóm "${selectedGroup.name}" và gửi lời mời'
                : 'Đã gửi lời mời vào nhóm "${selectedGroup.name}"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // Extract error message - remove "Exception: " prefix if present
        String errorMessage = e.toString().replaceFirst('Exception: ', '');

        // Check if this is an informational message (not an error)
        bool isInfoMessage = errorMessage.contains('Bạn đã gửi lời mời rồi') ||
            errorMessage.contains('đã gửi lời mời cho bạn rồi');

        // If error message already contains the full message, use it directly
        if (!errorMessage.startsWith('Lỗi') &&
            !errorMessage.contains('đã gửi lời mời')) {
          errorMessage = 'Lỗi: $errorMessage';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: isInfoMessage ? Colors.orange : Colors.red,
            duration: Duration(seconds: isInfoMessage ? 5 : 4),
          ),
        );
      }
    }
  }

  Future<void> _blockUserFromPost(
      BuildContext context, String userId, String userName) async {
    // Show confirmation dialog
    final confirmed = await showSmoothDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chặn người dùng'),
        content: Text('Bạn có chắc chắn muốn chặn $userName không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Chặn'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đang chặn...')),
        );
      }

      await _chatService.blockUser(userId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Đã chặn $userName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Reload blocked users list and refresh comments
        await _loadBlockedUsers();
        await _loadComments();

        // Emit event
        AppEventBus().emit('blocked_users_updated');
      }
    } catch (e) {
      print('❌ [PostDetailScreen] Error blocking user: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi chặn: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showCommentAuthorOptions(
      BuildContext context, MarketplaceComment comment) async {
    // Don't show options if user is viewing their own comment
    if (_currentResidentId != null &&
        comment.residentId == _currentResidentId) {
      return;
    }

    // Get author userId from residentId (check cache first)
    String? authorUserId =
        comment.author?.userId ?? _residentIdToUserIdCache[comment.residentId];

    if (authorUserId == null) {
      try {
        final response =
            await _apiClient.dio.get('/residents/${comment.residentId}');
        authorUserId = response.data['userId']?.toString();

        // Cache it for future use
        if (authorUserId != null) {
          _residentIdToUserIdCache[comment.residentId] = authorUserId;
        }
      } catch (e) {
        print('⚠️ [PostDetailScreen] Error getting userId: $e');
      }
    }

    // Check if user is blocked
    final isBlocked =
        authorUserId != null && _blockedUserIds.contains(authorUserId);

    // If blocked, show message that user is not found
    if (isBlocked) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không tìm thấy người dùng'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Check if user has active conversation/friendship
    Friend? friend;
    try {
      final friends = await _chatService.getFriends();
      friend = friends.firstWhere(
        (f) => f.friendId == comment.residentId,
        orElse: () => Friend(
          friendId: '',
          friendName: '',
          friendPhone: '',
          hasActiveConversation: false,
        ),
      );
    } catch (e) {
      print('⚠️ [PostDetailScreen] Error getting friends: $e');
    }

    final hasActiveConversation = friend != null &&
        friend.friendId == comment.residentId &&
        friend.hasActiveConversation &&
        friend.conversationId != null;

    // Show options menu
    final result = await showSmoothBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.chat_bubble),
              title: Text(hasActiveConversation ? 'Mở chat' : 'Gửi tin nhắn'),
              onTap: () => Navigator.pop(
                  context, hasActiveConversation ? 'open_chat' : 'message'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.group),
              title: const Text('Mời vào nhóm'),
              onTap: () => Navigator.pop(context, 'invite_group'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.person_crop_circle_badge_xmark,
                  color: Colors.red),
              title: const Text('Chặn người dùng'),
              onTap: () => Navigator.pop(context, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'open_chat' &&
        context.mounted &&
        friend != null &&
        friend.conversationId != null) {
      // Navigate directly to direct chat
      final friendData = friend;
      final conversationId = friendData.conversationId!;
      // Navigator.push(
      //   context,
      //   SmoothPageRoute(
      //     page: DirectChatScreen(
      //       conversationId: conversationId,
      //       otherParticipantName: friendData.friendName.isNotEmpty
      //           ? friendData.friendName
      //           : (comment.author?.name ?? 'Người dùng'),
      //     ),
      //   ),
      // );
    } else if (result == 'message' && context.mounted && authorUserId != null) {
      await _showDirectChatFromComment(context, comment, authorUserId);
    } else if (result == 'invite_group' && context.mounted) {
      await _inviteToGroupFromComment(context, comment);
    } else if (result == 'block' && context.mounted && authorUserId != null) {
      await _blockUserFromComment(
          context, authorUserId, comment.author?.name ?? 'Người dùng');
    }
  }

  Future<void> _showDirectChatFromComment(
      BuildContext context, MarketplaceComment comment, String userId) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trò chuyện'),
        content: Text(
          'Bạn có muốn gửi tin nhắn trực tiếp cho ${comment.author?.name ?? 'cư dân này'} không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi tin nhắn'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đang tạo lời mời...')),
        );

        await _chatService.createDirectInvitation(
          inviteeId: comment.residentId,
          initialMessage: null,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã gửi lời mời trò chuyện'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          // Extract error message - remove "Exception: " prefix if present
          String errorMessage = e.toString().replaceFirst('Exception: ', '');

          // Check if this is an informational message (not an error)
          bool isInfoMessage =
              errorMessage.contains('Bạn đã gửi lời mời rồi') ||
                  errorMessage.contains('đã gửi lời mời cho bạn rồi');

          // If error message already contains the full message, use it directly
          if (!errorMessage.startsWith('Lỗi') &&
              !errorMessage.contains('đã gửi lời mời')) {
            errorMessage = 'Lỗi: $errorMessage';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: isInfoMessage ? Colors.orange : Colors.red,
              duration: Duration(seconds: isInfoMessage ? 5 : 4),
            ),
          );
        }
      }
    }
  }

  Future<void> _inviteToGroupFromComment(
      BuildContext context, MarketplaceComment comment) async {
    try {
      // Get phone number from residentId first
      String? phoneNumber;
      try {
        final response =
            await _apiClient.dio.get('/residents/${comment.residentId}');
        phoneNumber = response.data['phone']?.toString();
      } catch (e) {
        print('⚠️ [PostDetailScreen] Error getting phone number: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể lấy số điện thoại của người dùng'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (phoneNumber == null || phoneNumber.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Người dùng này chưa có số điện thoại'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get user's groups
      final groupsResponse = await _chatService.getMyGroups(page: 0, size: 100);
      final groups = groupsResponse.content;

      ChatGroup? selectedGroup;
      bool createNewGroup = false;

      if (groups.isEmpty) {
        // No groups, create a new one
        final groupData = await showSmoothDialog<Map<String, String?>>(
          context: context,
          builder: (context) => CreateGroupDialog(
            defaultName: 'Nhóm với ${comment.author?.name ?? 'người dùng'}',
          ),
        );

        if (groupData == null || !context.mounted) {
          return;
        }

        createNewGroup = true;

        // Show loading
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đang tạo nhóm...')),
          );
        }

        // Create new group
        try {
          selectedGroup = await _chatService.createGroup(
            name: groupData['name']!,
            description: groupData['description'],
          );

          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đang gửi lời mời...')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lỗi khi tạo nhóm: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } else {
        // Show group selection dialog
        final result = await showSmoothDialog<dynamic>(
          context: context,
          builder: (context) => SelectGroupDialog(
            groups: groups,
            targetResidentId: comment.residentId,
            currentResidentId: _currentResidentId,
          ),
        );

        if (result == null || !context.mounted) {
          return;
        }

        if (result == 'create_new') {
          // User wants to create a new group
          final groupData = await showSmoothDialog<Map<String, String?>>(
            context: context,
            builder: (context) => CreateGroupDialog(
              defaultName: 'Nhóm với ${comment.author?.name ?? 'người dùng'}',
            ),
          );

          if (groupData == null || !context.mounted) {
            return;
          }

          createNewGroup = true;

          // Show loading
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đang tạo nhóm...')),
            );
          }

          // Create new group
          try {
            selectedGroup = await _chatService.createGroup(
              name: groupData['name']!,
              description: groupData['description'],
            );

            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đang gửi lời mời...')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Lỗi khi tạo nhóm: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        } else if (result is ChatGroup) {
          selectedGroup = result;

          // Check if user is already in the group
          if (selectedGroup.members != null) {
            final isAlreadyMember = selectedGroup.members!.any(
              (member) => member.residentId == comment.residentId,
            );

            if (isAlreadyMember) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${comment.author?.name ?? 'Người dùng'} đã ở trong nhóm "${selectedGroup.name}"'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
              return;
            }
          }

          // Show loading
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đang gửi lời mời...')),
            );
          }
        } else {
          return;
        }
      }

      // Invite to group
      final inviteResult = await _chatService.inviteMembersByPhone(
        groupId: selectedGroup.id,
        phoneNumbers: [phoneNumber],
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // Check if there are successful invitations
        if (inviteResult.successfulInvitations != null &&
            inviteResult.successfulInvitations!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(createNewGroup
                  ? 'Đã tạo nhóm "${selectedGroup.name}" và gửi lời mời'
                  : 'Đã gửi lời mời vào nhóm "${selectedGroup.name}"'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (inviteResult.skippedPhones != null &&
            inviteResult.skippedPhones!.isNotEmpty) {
          // If only skipped phones (e.g., already sent invitation), show message from skippedPhones
          String skippedMessage = inviteResult.skippedPhones!.first;
          // Extract message from format: "phone (message)"
          if (skippedMessage.contains('(') && skippedMessage.contains(')')) {
            int start = skippedMessage.indexOf('(') + 1;
            int end = skippedMessage.lastIndexOf(')');
            skippedMessage = skippedMessage.substring(start, end);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(skippedMessage),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          // Fallback error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Không thể gửi lời mời'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // Extract error message - remove "Exception: " prefix if present
        String errorMessage = e.toString().replaceFirst('Exception: ', '');

        // Check if this is an informational message (not an error)
        bool isInfoMessage = errorMessage.contains('Bạn đã gửi lời mời rồi') ||
            errorMessage.contains('đã gửi lời mời cho bạn rồi');

        // If error message already contains the full message, use it directly
        if (!errorMessage.startsWith('Lỗi') &&
            !errorMessage.contains('đã gửi lời mời')) {
          errorMessage = 'Lỗi: $errorMessage';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: isInfoMessage ? Colors.orange : Colors.red,
            duration: Duration(seconds: isInfoMessage ? 5 : 4),
          ),
        );
      }
    }
  }

  Future<void> _blockUserFromComment(
      BuildContext context, String userId, String userName) async {
    // Show confirmation dialog
    final confirmed = await showSmoothDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chặn người dùng'),
        content: Text('Bạn có chắc chắn muốn chặn $userName không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Chặn'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đang chặn...')),
        );
      }

      await _chatService.blockUser(userId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Đã chặn $userName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Reload blocked users list and refresh comments
        await _loadBlockedUsers();
        await _loadComments();

        // Emit event
        AppEventBus().emit('blocked_users_updated');
      }
    } catch (e) {
      print('❌ [PostDetailScreen] Error blocking user: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi chặn: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildCommentSkeleton(ThemeData theme) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Shimmer.fromColors(
            baseColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            highlightColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.1),
            period: const Duration(milliseconds: 1200),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 16,
                          width: 120,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        Container(
                          height: 14,
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        Container(
                          height: 14,
                          width: 200,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCommentContent(
      BuildContext context, ThemeData theme, MarketplaceComment comment) {
    const int maxLines = 3;
    final bool isExpanded = _expandedComments[comment.id] ?? false;
    final textStyle = theme.textTheme.bodyMedium;

    // Check if text needs read more
    final textPainter = TextPainter(
      text: TextSpan(text: comment.content, style: textStyle),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: double.infinity);
    final needsReadMore = textPainter.didExceedMaxLines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (comment.content.isNotEmpty)
          LinkableText(
            text: comment.content,
            style: textStyle,
            linkColor: theme.colorScheme.primary,
            textAlign: TextAlign.start,
          ),
        if (needsReadMore && comment.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: InkWell(
              onTap: () => _toggleCommentExpand(comment.id),
              child: Text(
                isExpanded ? 'Thu gọn' : 'Xem thêm',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        // Display image if available
        if (comment.imageUrl != null && comment.imageUrl!.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ImageViewerScreen(
                    images: [
                      MarketplacePostImage(
                        id: comment.id,
                        postId: comment.postId,
                        imageUrl: comment.imageUrl!,
                        sortOrder: 0,
                      ),
                    ],
                    initialIndex: 0,
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: comment.imageUrl!,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 200,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 200,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    CupertinoIcons.photo,
                    size: 48,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
        ],
        // Display video if available
        if (comment.videoUrl != null && comment.videoUrl!.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _openCommentVideo(context, comment.videoUrl!),
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    CupertinoIcons.play_circle_fill,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Text(
                      'Video',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Vừa xong';
        }
        return '${difference.inMinutes} phút trước';
      }
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays == 1) {
      return 'Hôm qua';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _openCommentVideo(BuildContext context, String videoUrl) async {
    try {
      if (!context.mounted) return;

      // Show loading dialog
      showSmoothDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      VideoPlayerController controller;

      try {
        // Check if video URL is from ImageKit (old videos) - skip if ImageKit is blocked
        if (videoUrl.contains('ik.imagekit.io') ||
            videoUrl.contains('imagekit.io')) {
          if (context.mounted) {
            Navigator.of(context).pop(); // Close loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Video này đang được lưu trữ trên ImageKit và hiện không khả dụng. Vui lòng thử lại sau.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        // Use network URL directly (videoUrl is already absolute URL from model)
        final fullUrl =
            videoUrl.startsWith('http://') || videoUrl.startsWith('https://')
                ? videoUrl
                : ApiClient.fileUrl(videoUrl);

        debugPrint('🎬 [PostDetailScreen] Loading video from URL: $fullUrl');

        controller = VideoPlayerController.networkUrl(Uri.parse(fullUrl));

        // Initialize video player
        await controller.initialize();

        if (!context.mounted) {
          controller.dispose();
          return;
        }

        // Close loading dialog
        Navigator.of(context).pop();

        // Show video player dialog
        await showSmoothDialog(
          context: context,
          barrierColor: Colors.black87,
          builder: (context) => _CommentVideoPlayerDialog(
            controller: controller,
            videoUrl: videoUrl,
          ),
        );

        // Dispose controller when dialog is closed
        controller.dispose();
      } catch (e) {
        if (context.mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          String errorMessage = 'Không thể tải video';
          if (e.toString().contains('403') ||
              e.toString().contains('Forbidden')) {
            errorMessage = 'Video không khả dụng. Vui lòng thử lại sau.';
          } else if (e.toString().contains('imagekit') ||
              e.toString().contains('ImageKit')) {
            errorMessage =
                'Video này đang được lưu trữ trên ImageKit và hiện không khả dụng.';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog if still open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể mở video: $e'),
          ),
        );
      }
    }
  }
}

class _CommentVideoPlayerDialog extends StatefulWidget {
  final VideoPlayerController controller;
  final String videoUrl;

  const _CommentVideoPlayerDialog({
    required this.controller,
    required this.videoUrl,
  });

  @override
  State<_CommentVideoPlayerDialog> createState() =>
      _CommentVideoPlayerDialogState();
}

class _CommentVideoPlayerDialogState extends State<_CommentVideoPlayerDialog> {
  bool _isPlaying = false;
  bool _showControls = true;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.controller.value.isPlaying;
    _duration = widget.controller.value.duration;
    _position = widget.controller.value.position;
    widget.controller.addListener(_videoListener);
    _startHideControlsTimer();
  }

  void _videoListener() {
    if (mounted) {
      setState(() {
        _isPlaying = widget.controller.value.isPlaying;
        _duration = widget.controller.value.duration;
        _position = widget.controller.value.position;
      });
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _togglePlayPause() {
    setState(() {
      if (_isPlaying) {
        widget.controller.pause();
      } else {
        widget.controller.play();
      }
      _isPlaying = !_isPlaying;
      _showControls = true;
      _startHideControlsTimer();
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (hours > 0) {
      return '${twoDigits(hours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    widget.controller.removeListener(_videoListener);
    widget.controller.pause(); // Pause video when dialog closes
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Video player
          Center(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _showControls = !_showControls;
                });
                if (_showControls) {
                  _startHideControlsTimer();
                }
              },
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),
          ),

          // Controls overlay
          if (_showControls)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top bar with close button
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon:
                                  const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Bottom controls
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            // Progress bar
                            VideoProgressIndicator(
                              widget.controller,
                              allowScrubbing: true,
                              colors: VideoProgressColors(
                                playedColor: theme.colorScheme.primary,
                                bufferedColor: Colors.white30,
                                backgroundColor: Colors.white12,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Play/pause and time
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(_position),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                IconButton(
                                  icon: Icon(
                                    _isPlaying ? Icons.pause : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                  onPressed: _togglePlayPause,
                                ),
                                Text(
                                  _formatDuration(_duration),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
