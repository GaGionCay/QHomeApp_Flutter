import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import '../chat/linkable_text_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:shimmer/shimmer.dart';
import '../models/marketplace_post.dart';
import '../models/marketplace_comment.dart';
import '../models/comment_paged_response.dart';
import '../auth/token_storage.dart';
import '../auth/api_client.dart';
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
  bool _commentsLoaded = false; // Track if comments have been loaded
  List<MarketplaceComment> _comments = [];
  MarketplacePost? _currentPost; // Cache current post for comment count
  bool _isLoadingComments = false;
  bool _isLoadingMoreComments = false;
  bool _isPostingComment = false;
  String? _currentResidentId;
  String? _replyingToCommentId; // ID của comment đang được reply
  MarketplaceComment? _replyingToComment; // Comment đang được reply (để hiển thị tên)
  int _currentPage = 0;
  int _pageSize = 10;
  bool _hasMoreComments = true;
  Map<String, bool> _expandedComments = {}; // Track expanded state for read more
  Set<String> _blockedUserIds = {}; // Cache blocked user IDs
  final Map<String, String> _residentIdToUserIdCache = {}; // Cache residentId -> userId mapping
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
  Future<void> _showDeleteCommentDialog(BuildContext context, MarketplaceComment comment) async {
    final isRootComment = comment.parentCommentId == null;
    final confirmed = await showDialog<bool>(
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




  /// Delete a comment
  Future<void> _deleteComment(MarketplaceComment comment) async {
    try {
      await _marketplaceService.deleteComment(widget.post.id, comment.id);
      
      if (mounted) {
        final isRootComment = comment.parentCommentId == null;
        
        // Reload comments to get correct state from backend
        // This ensures that when deleting a child comment, its replies are preserved
        // Backend will keep the replies (orphaned), and we need to reload to see them
        await _loadComments();
        
        // Reload post to get updated comment count from backend
        int? updatedCommentCount;
        try {
          final updatedPost = await _marketplaceService.getPostById(widget.post.id);
          setState(() {
            _currentPost = updatedPost;
          });
          updatedCommentCount = updatedPost.commentCount;
        } catch (e) {
          // Failed to reload post, estimate count by decrementing
          print('⚠️ Failed to reload post after delete: $e');
          final currentPost = _currentPost ?? widget.post;
          // Estimate: decrement by 1 for the deleted comment
          // TH1: If root comment, add entire sub-tree count (all levels recursively)
          // TH2: If child comment, only decrement by 1 (no replies deleted)
          int deletedCount = 1;
          if (isRootComment) {
            // Count entire sub-tree recursively
            deletedCount += _countNestedReplies(comment);
          }
          // TH2: Child comment deletion - only 1 comment deleted, no need to add replies
          updatedCommentCount = (currentPost.commentCount - deletedCount).clamp(0, double.infinity).toInt();
        }
        
        // Emit event to update marketplace screen (realtime update)
        // This ensures marketplace screen updates even if WebSocket event is delayed
        AppEventBus().emit('marketplace_update', {
          'type': 'POST_STATS_UPDATE',
          'postId': widget.post.id,
          'commentCount': updatedCommentCount,
          'viewCount': (_currentPost ?? widget.post).viewCount,
        });
        
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
      _loadComments();
      // Reload post to get latest comment count
      _reloadPost();
    }
  }

  /// Reload post to get latest comment count
  Future<void> _reloadPost() async {
    try {
      final updatedPost = await _marketplaceService.getPostById(widget.post.id);
      if (mounted) {
        setState(() {
          _currentPost = updatedPost;
        });
      }
    } catch (e) {
      print('⚠️ Failed to reload post: $e');
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
      print('⚠️ [PostDetailScreen] Error loading blocked users: $e');
    }
  }

  void _setupBlockedUsersListener() {
    AppEventBus().on('blocked_users_updated', (_) async {
      print('🔄 [PostDetailScreen] blocked_users_updated event received, reloading blocked users...');
      await _loadBlockedUsers();
      // Refresh comments to show/hide comments from unblocked users
      if (mounted) {
        setState(() {
          // Trigger rebuild to refresh filtered comments
          print('✅ [PostDetailScreen] Blocked users reloaded, refreshing UI. Blocked count: ${_blockedUserIds.length}');
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
      MaterialPageRoute(
        builder: (context) => EditPostScreen(
          post: post,
          onPostUpdated: () async {
            // Refresh marketplace view model if available
            try {
              final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
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
      // Pop to go back to marketplace screen, or refresh current screen
      navigator.pop(true);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text('Bạn có chắc chắn muốn xóa bài đăng này? Hành động này không thể hoàn tác.'),
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
          // Reload comments when new comment is added
          _loadComments();
          // Also reload post to get updated comment count
          _reloadPost();
        }
      }
    });
    
    // Listen for marketplace updates to update comment count
    AppEventBus().on('marketplace_update', (data) {
      if (data is Map<String, dynamic>) {
        final type = data['type'] as String?;
        final postId = data['postId'] as String?;
        if (postId == widget.post.id && type == 'POST_STATS_UPDATE' && mounted) {
          // Update comment count from event data immediately
          final commentCount = (data['commentCount'] as num?)?.toInt();
          if (commentCount != null) {
            setState(() {
              // Update _currentPost with new comment count
              if (_currentPost != null) {
                _currentPost = MarketplacePost(
                  id: _currentPost!.id,
                  residentId: _currentPost!.residentId,
                  buildingId: _currentPost!.buildingId,
                  title: _currentPost!.title,
                  description: _currentPost!.description,
                  price: _currentPost!.price,
                  category: _currentPost!.category,
                  categoryName: _currentPost!.categoryName,
                  status: _currentPost!.status,
                  contactInfo: _currentPost!.contactInfo,
                  location: _currentPost!.location,
                  viewCount: _currentPost!.viewCount,
                  commentCount: commentCount,
                  images: _currentPost!.images,
                  author: _currentPost!.author,
                  createdAt: _currentPost!.createdAt,
                  updatedAt: _currentPost!.updatedAt,
                );
              }
            });
          }
          // Also reload post to get latest data from backend
          _reloadPost();
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
        final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
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
          final filteredComments = pagedResponse.content.where((comment) => !comment.isDeleted).toList();
          
          if (loadMore) {
            _comments.addAll(filteredComments);
          } else {
            _comments = filteredComments;
          }
          _currentPage = pagedResponse.currentPage + 1;
          _hasMoreComments = pagedResponse.hasNext;
          _isLoadingComments = false;
          _isLoadingMoreComments = false;
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
    if (content.isEmpty && _selectedImage == null && _selectedVideo == null) return;

    setState(() => _isPostingComment = true);
    try {
      String? imageUrl;
      String? videoUrl;
      
      // Upload image if selected
      if (_selectedImage != null) {
        try {
          final formData = FormData.fromMap({
            'file': await MultipartFile.fromFile(
              _selectedImage!.path,
              filename: _selectedImage!.name,
            ),
          });
          final response = await _apiClient.dio.post(
            '/uploads/marketplace/comment/image',
            data: formData,
          );
          imageUrl = response.data['imageUrl']?.toString();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi khi upload ảnh: ${e.toString()}')),
            );
          }
          return;
        }
      }
      
      // Upload video if selected
      if (_selectedVideo != null) {
        try {
          final formData = FormData.fromMap({
            'file': await MultipartFile.fromFile(
              _selectedVideo!.path,
              filename: _selectedVideo!.name,
            ),
          });
          final response = await _apiClient.dio.post(
            '/uploads/marketplace/comment/video',
            data: formData,
          );
          videoUrl = response.data['videoUrl']?.toString();
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
        final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
        newComment = await viewModel.addComment(
          widget.post.id, 
          content.isEmpty ? ' ' : content, // Allow empty content if image/video is provided
          parentCommentId: _replyingToCommentId,
          imageUrl: imageUrl,
          videoUrl: videoUrl,
        );
      } catch (e) {
        // No provider available, use service directly
        newComment = await _marketplaceService.addComment(
          postId: widget.post.id,
          content: content.isEmpty ? ' ' : content,
          parentCommentId: _replyingToCommentId,
          imageUrl: imageUrl,
          videoUrl: videoUrl,
        );
      }
      
      if (newComment != null && mounted) {
        _commentController.clear();
        _replyingToCommentId = null;
        _replyingToComment = null;
        _selectedImage = null;
        _selectedVideo = null;
        // Reload comments to get updated list
        await _loadComments();
        // Scroll to bottom to show new comment
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
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

  void _cancelReply() {
    setState(() {
      _replyingToCommentId = null;
      _replyingToComment = null;
    });
  }

  String _getCategoryDisplayName(MarketplacePost post) {
    // Backend có thể trả về categoryName = category code, nên luôn map từ danh sách categories
    if (post.category.isNotEmpty) {
      try {
        final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
        final category = viewModel.categories.firstWhere(
          (cat) => cat.code == post.category,
        );
        // Luôn dùng name (tiếng Việt) từ danh sách categories
        return category.name;
      } catch (e) {
        // Nếu không tìm thấy category, kiểm tra categoryName
        if (post.categoryName.isNotEmpty && post.categoryName != post.category) {
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

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Chi tiết bài đăng'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Show edit/delete buttons only if current user is the post owner
          if (_currentResidentId != null && widget.post.residentId == _currentResidentId)
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
                      Icon(CupertinoIcons.pencil, size: 20, color: theme.colorScheme.onSurface),
                      const SizedBox(width: 12),
                      const Text('Chỉnh sửa'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.delete, size: 20, color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Text('Xóa', style: TextStyle(color: theme.colorScheme.error)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          // Try to get updated post from viewModel if available
          MarketplacePost updatedPost = widget.post;
          try {
            final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
            updatedPost = viewModel.posts.firstWhere(
              (p) => p.id == widget.post.id,
              orElse: () => widget.post,
            );
          } catch (e) {
            // No provider available, use widget.post
            updatedPost = widget.post;
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
                            viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
                          } catch (e) {
                            // No provider available
                            viewModel = null;
                          }
                          return _buildPostCard(context, theme, isDark, updatedPost, viewModel);
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
                          Builder(
                            builder: (context) {
                              // Try to get updated post from viewModel (realtime updates)
                              MarketplacePost postToUse = _currentPost ?? updatedPost;
                              try {
                                final viewModel = Provider.of<MarketplaceViewModel>(context, listen: true);
                                final vmPost = viewModel.posts.firstWhere(
                                  (p) => p.id == widget.post.id,
                                  orElse: () => postToUse,
                                );
                                // Use viewModel post if it has newer comment count
                                if (vmPost.commentCount != postToUse.commentCount) {
                                  postToUse = vmPost;
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
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Chưa có bình luận nào',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        ..._comments.map((comment) => _buildCommentCard(
                              context,
                              theme,
                              comment,
                              depth: 0,
                            )),
                        // Load more button
                        if (_hasMoreComments)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: Center(
                              child: _isLoadingMoreComments
                                  ? const CircularProgressIndicator()
                                  : TextButton.icon(
                                      onPressed: () => _loadComments(loadMore: true),
                                      icon: const Icon(CupertinoIcons.arrow_down),
                                      label: const Text('Xem thêm bình luận'),
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
                  // Reply banner
                  if (_replyingToComment != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                        border: Border(
                          bottom: BorderSide(
                            color: theme.colorScheme.outline.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.arrow_turn_down_right,
                            size: 16,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Đang trả lời cho ${_replyingToComment!.author?.name ?? 'Người dùng'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              CupertinoIcons.xmark_circle_fill,
                              size: 20,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                            onPressed: _cancelReply,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? theme.colorScheme.surfaceContainerHigh
                          : theme.colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outline.withValues(alpha: 0.12),
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
                                          borderRadius: BorderRadius.circular(8),
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
                                            icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.red),
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
                                          borderRadius: BorderRadius.circular(8),
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
                                            icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.red),
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
                                onPressed: _isPostingComment ? null : _showMediaPicker,
                                icon: Icon(
                                  CupertinoIcons.photo_camera,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Send button
                              IconButton(
                                onPressed: _isPostingComment ? null : _postComment,
                                icon: _isPostingComment
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2),
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
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.photo),
              title: const Text('Chọn ảnh'),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.videocam),
              title: const Text('Chọn video'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'image') {
      await _pickImage();
    } else if (result == 'video') {
      await _pickVideo();
    }
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
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

  Future<void> _pickVideo() async {
    try {
      final video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
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
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (post.author?.unitNumber != null || post.author?.buildingName != null)
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.home,
                              size: 16,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                            if (post.author?.buildingName != null) ...[
                              Text(
                                post.author!.buildingName!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (post.author?.unitNumber != null) ...[
                                Text(
                                  ' - ',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ],
                            if (post.author?.unitNumber != null)
                              Text(
                                post.author!.unitNumber!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
            
            // Images
            if (post.images.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 300,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: post.images.length,
                  itemBuilder: (context, index) {
                    final image = post.images[index];
                    // Debug: Log image URLs
                    print('🖼️ [PostDetailScreen] Displaying image $index: imageUrl=${image.imageUrl}');
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ImageViewerScreen(
                              images: post.images,
                              initialIndex: index,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 300,
                        margin: EdgeInsets.only(
                          right: index < post.images.length - 1 ? 8 : 0,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: theme.colorScheme.surfaceContainerHighest,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
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
                                    'ngrok-skip-browser-warning': 'true', // Skip ngrok browser warning
                                  },
                                  placeholder: (context, url) {
                                    print('🖼️ [PostDetailScreen] Loading image: $url');
                                    return Container(
                                      color: theme.colorScheme.surfaceContainerHighest,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    );
                                  },
                                  errorWidget: (context, url, error) {
                                    print('❌ [PostDetailScreen] Error loading image: url=$url, error=$error');
                                    print('❌ [PostDetailScreen] Error type: ${error.runtimeType}');
                                    if (error is DioException) {
                                      print('❌ [PostDetailScreen] DioException: statusCode=${error.response?.statusCode}, message=${error.message}');
                                    }
                                    return Container(
                                      color: theme.colorScheme.surfaceContainerHighest,
                                      child: Icon(
                                        CupertinoIcons.photo,
                                        size: 48,
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    CupertinoIcons.photo,
                                    size: 48,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            
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
                print('📞 [PostDetailScreen] Checking contactInfo:');
                print('   - contactInfo is null: ${post.contactInfo == null}');
                if (post.contactInfo != null) {
                  print('   - phone: ${post.contactInfo!.phone}');
                  print('   - email: ${post.contactInfo!.email}');
                  print('   - showPhone: ${post.contactInfo!.showPhone}');
                  print('   - showEmail: ${post.contactInfo!.showEmail}');
                }
                
                if (post.contactInfo != null && 
                    ((post.contactInfo!.phone != null && post.contactInfo!.phone!.isNotEmpty) ||
                     (post.contactInfo!.email != null && post.contactInfo!.email!.isNotEmpty))) {
                  return Column(
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outline.withValues(alpha: 0.12),
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
                            if (post.contactInfo!.phone != null && post.contactInfo!.phone!.isNotEmpty) ...[
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.phone,
                                    size: 16,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
                              if (post.contactInfo!.email != null && post.contactInfo!.email!.isNotEmpty)
                                const SizedBox(height: 12),
                            ],
                            if (post.contactInfo!.email != null && post.contactInfo!.email!.isNotEmpty)
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.mail,
                                    size: 16,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
            
            const SizedBox(height: 12),
            
            // Actions
            Row(
              children: [
                Icon(
                  CupertinoIcons.chat_bubble,
                  size: 20,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  '${post.commentCount}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
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
    final activeReplies = comment.replies.where((reply) => !reply.isDeleted).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.only(
            bottom: 12,
            left: isReply ? 32.0 : 0, // Indent cho replies
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: isReply 
                ? Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
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
                            onTap: () => _showCommentAuthorOptions(context, comment),
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
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Delete button (only show if user is post owner or comment owner)
                        if (_canDeleteComment(comment)) ...[
                          const SizedBox(width: 16),
                          InkWell(
                            onTap: () => _showDeleteCommentDialog(context, comment),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.delete,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Xóa',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
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
    );
  }

  Future<void> _showPostAuthorOptions(BuildContext context, MarketplacePost post) async {
    // Don't show options if user is viewing their own post
    if (_currentResidentId != null && post.residentId == _currentResidentId) {
      return;
    }

    // Get author userId from residentId (check cache first)
    String? authorUserId = post.author?.userId ?? _residentIdToUserIdCache[post.residentId];
    
    if (authorUserId == null) {
      try {
        final response = await _apiClient.dio.get('/residents/${post.residentId}');
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
    final isBlocked = authorUserId != null && _blockedUserIds.contains(authorUserId);
    
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
    final result = await showModalBottomSheet<String>(
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
              onTap: () => Navigator.pop(context, hasActiveConversation ? 'open_chat' : 'message'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.group),
              title: const Text('Mời vào nhóm'),
              onTap: () => Navigator.pop(context, 'invite_group'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.person_crop_circle_badge_xmark, color: Colors.red),
              title: const Text('Chặn người dùng'),
              onTap: () => Navigator.pop(context, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'open_chat' && context.mounted && friend != null && friend.conversationId != null) {
      // Navigate directly to direct chat
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DirectChatScreen(
            conversationId: friend!.conversationId!,
            otherParticipantName: friend.friendName.isNotEmpty ? friend.friendName : (post.author?.name ?? 'Người dùng'),
          ),
        ),
      );
    } else if (result == 'message' && context.mounted && authorUserId != null) {
      await _showDirectChatFromPost(context, post, authorUserId);
    } else if (result == 'invite_group' && context.mounted) {
      await _inviteToGroupFromPost(context, post);
    } else if (result == 'block' && context.mounted && authorUserId != null) {
      await _blockUserFromPost(context, authorUserId, post.author?.name ?? 'Người dùng');
    }
  }

  Future<void> _showDirectChatFromPost(BuildContext context, MarketplacePost post, String userId) async {
    final result = await showDialog<bool>(
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _inviteToGroupFromPost(BuildContext context, MarketplacePost post) async {
    try {
      // Get phone number from residentId first
      String? phoneNumber;
      try {
        final response = await _apiClient.dio.get('/residents/${post.residentId}');
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
        final groupData = await showDialog<Map<String, String?>>(
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
        final result = await showDialog<dynamic>(
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
          final groupData = await showDialog<Map<String, String?>>(
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
                    content: Text('${post.author?.name ?? 'Người dùng'} đã ở trong nhóm "${selectedGroup.name}"'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _blockUserFromPost(BuildContext context, String userId, String userName) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
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

  Future<void> _showCommentAuthorOptions(BuildContext context, MarketplaceComment comment) async {
    // Don't show options if user is viewing their own comment
    if (_currentResidentId != null && comment.residentId == _currentResidentId) {
      return;
    }

    // Get author userId from residentId (check cache first)
    String? authorUserId = comment.author?.userId ?? _residentIdToUserIdCache[comment.residentId];
    
    if (authorUserId == null) {
      try {
        final response = await _apiClient.dio.get('/residents/${comment.residentId}');
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
    final isBlocked = authorUserId != null && _blockedUserIds.contains(authorUserId);
    
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
    final result = await showModalBottomSheet<String>(
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
              onTap: () => Navigator.pop(context, hasActiveConversation ? 'open_chat' : 'message'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.group),
              title: const Text('Mời vào nhóm'),
              onTap: () => Navigator.pop(context, 'invite_group'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.person_crop_circle_badge_xmark, color: Colors.red),
              title: const Text('Chặn người dùng'),
              onTap: () => Navigator.pop(context, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'open_chat' && context.mounted && friend != null && friend.conversationId != null) {
      // Navigate directly to direct chat
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DirectChatScreen(
            conversationId: friend!.conversationId!,
            otherParticipantName: friend.friendName.isNotEmpty ? friend.friendName : (comment.author?.name ?? 'Người dùng'),
          ),
        ),
      );
    } else if (result == 'message' && context.mounted && authorUserId != null) {
      await _showDirectChatFromComment(context, comment, authorUserId);
    } else if (result == 'invite_group' && context.mounted) {
      await _inviteToGroupFromComment(context, comment);
    } else if (result == 'block' && context.mounted && authorUserId != null) {
      await _blockUserFromComment(context, authorUserId, comment.author?.name ?? 'Người dùng');
    }
  }

  Future<void> _showDirectChatFromComment(BuildContext context, MarketplaceComment comment, String userId) async {
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _inviteToGroupFromComment(BuildContext context, MarketplaceComment comment) async {
    try {
      // Get phone number from residentId first
      String? phoneNumber;
      try {
        final response = await _apiClient.dio.get('/residents/${comment.residentId}');
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
        final groupData = await showDialog<Map<String, String?>>(
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
        final result = await showDialog<dynamic>(
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
          final groupData = await showDialog<Map<String, String?>>(
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
                    content: Text('${comment.author?.name ?? 'Người dùng'} đã ở trong nhóm "${selectedGroup.name}"'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _blockUserFromComment(BuildContext context, String userId, String userName) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
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
            baseColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            highlightColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
            period: const Duration(milliseconds: 1200),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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

  Widget _buildCommentContent(BuildContext context, ThemeData theme, MarketplaceComment comment) {
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
          Container(
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

}

