import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import '../models/marketplace_post.dart';
import '../models/marketplace_comment.dart';
import '../auth/token_storage.dart';
import 'marketplace_view_model.dart';
import '../core/event_bus.dart';
import 'image_viewer_screen.dart';
import 'edit_post_screen.dart';

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
  List<MarketplaceComment> _comments = [];
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

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadComments();
    _setupRealtimeUpdates();
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
    super.dispose();
  }

  Future<void> _editPost(BuildContext context, MarketplacePost post) async {
    // Capture dependencies before async gap
    final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
    final navigator = Navigator.of(context);
    // Navigate to edit post screen
    final result = await navigator.push(
      MaterialPageRoute(
        builder: (context) => EditPostScreen(
          post: post,
          onPostUpdated: () async {
            // Refresh marketplace view model
            final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
            await viewModel.refresh();
          },
        ),
      ),
    );
    
    // If post was updated, refresh the screen
    if (result == true && mounted) {
      // Reload post data
      await viewModel.refresh();
      // Pop to go back to marketplace screen, or refresh current screen
      navigator.pop(true);
    }
  }

  Future<void> _deletePost(BuildContext context, MarketplacePost post) async {
    // Capture dependencies before async gap
    final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
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
        await viewModel.deletePost(post.id);
        
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
        }
      }
    });
    
    // Listen for marketplace updates to update comment count
    AppEventBus().on('marketplace_update', (data) {
      if (data is Map<String, dynamic>) {
        final type = data['type'] as String?;
        final postId = data['postId'] as String?;
        if (postId == widget.post.id && type == 'POST_STATS_UPDATE' && mounted) {
          // Update comment count from stats update
          setState(() {
            // The post will be updated via Consumer, but we can also reload comments
            // to ensure we have the latest count
          });
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
      final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
      final pagedResponse = await viewModel.getCommentsPaged(
        widget.post.id,
        page: _currentPage,
        size: _pageSize,
      );
      
      if (mounted) {
        setState(() {
          if (loadMore) {
            _comments.addAll(pagedResponse.content);
          } else {
            _comments = pagedResponse.content;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải bình luận: $e')),
        );
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
    if (content.isEmpty) return;

    setState(() => _isPostingComment = true);
    try {
      final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
      final newComment = await viewModel.addComment(
        widget.post.id, 
        content,
        parentCommentId: _replyingToCommentId,
      );
      
      if (newComment != null && mounted) {
        _commentController.clear();
        _replyingToCommentId = null;
        _replyingToComment = null;
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
      body: Consumer<MarketplaceViewModel>(
        builder: (context, viewModel, child) {
          // Get updated post from viewModel
          final updatedPost = viewModel.posts.firstWhere(
            (p) => p.id == widget.post.id,
            orElse: () => widget.post,
          );

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
                      _buildPostCard(context, theme, isDark, updatedPost, viewModel),
                      
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
                          Text(
                            'Bình luận (${updatedPost.commentCount})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
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
                      child: Row(
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
                          const SizedBox(width: 8),
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

  Widget _buildPostCard(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    MarketplacePost post,
    MarketplaceViewModel viewModel,
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
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    CupertinoIcons.person_fill,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 24,
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
                            child: Text(
                              post.author?.name ?? 'Người dùng',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: (_currentResidentId != null && 
                                        post.residentId == _currentResidentId)
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (_currentResidentId != null && 
                                      post.residentId == _currentResidentId)
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              (_currentResidentId != null && 
                               post.residentId == _currentResidentId)
                                  ? 'Bạn'
                                  : 'Người đăng',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: (_currentResidentId != null && 
                                        post.residentId == _currentResidentId)
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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
              CircleAvatar(
                radius: isReply ? 14 : 16,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  CupertinoIcons.person_fill,
                  size: isReply ? 14 : 16,
                  color: theme.colorScheme.onPrimaryContainer,
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
                          child: Text(
                            comment.author?.name ?? 'Người dùng',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: (_currentResidentId != null && 
                                      comment.residentId == _currentResidentId)
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_currentResidentId != null && 
                            comment.residentId == _currentResidentId) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Bạn',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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
                  ],
                ),
              ),
            ],
          ),
        ),
        // Hiển thị replies nếu có
        if (comment.replies.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...comment.replies.map((reply) => _buildCommentCard(
            context,
            theme,
            reply,
            depth: depth + 1,
          )),
        ],
      ],
    );
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
        Linkify(
          onOpen: (link) async {
            final uri = Uri.parse(link.url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          text: comment.content,
          style: textStyle,
          linkStyle: textStyle?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          options: const LinkifyOptions(
            humanize: false,
            removeWww: false,
          ),
          maxLines: isExpanded ? null : maxLines,
          overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
        if (needsReadMore)
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

