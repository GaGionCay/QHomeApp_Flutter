import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
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
  bool _isPostingComment = false;
  String? _currentResidentId;

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
    // Navigate to edit post screen
    final result = await Navigator.push(
      context,
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
      final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
      await viewModel.refresh();
      // Pop to go back to marketplace screen, or refresh current screen
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _deletePost(BuildContext context, MarketplacePost post) async {
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
        final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
        await viewModel.deletePost(post.id);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã xóa bài đăng')),
          );
          Navigator.of(context).pop(true); // Go back to marketplace screen
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _loadComments() async {
    setState(() => _isLoadingComments = true);
    try {
      final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
      final comments = await viewModel.getComments(widget.post.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingComments = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải bình luận: $e')),
        );
      }
    }
  }

  Future<void> _postComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isPostingComment = true);
    try {
      final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
      final newComment = await viewModel.addComment(widget.post.id, content);
      
      if (newComment != null && mounted) {
        _commentController.clear();
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
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
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
                      else
                        ..._comments.map((comment) => _buildCommentCard(
                              context,
                              theme,
                              comment,
                            )),
                      
                      const SizedBox(height: 80), // Space for input field
                    ],
                  ),
                ),
              ),
              
              // Comment Input
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
                            hintText: 'Viết bình luận...',
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
                      if (post.author?.unitNumber != null)
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.home,
                              size: 16,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
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
            
            // Price and Category
            Row(
              children: [
                if (post.price != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatPrice(post.price!),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (post.category.isNotEmpty) ...[
                  if (post.price != null) const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      post.category,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Actions
            Row(
              children: [
                IconButton(
                  onPressed: () => viewModel.toggleLike(post.id),
                  icon: Icon(
                    post.isLiked
                        ? CupertinoIcons.heart_fill
                        : CupertinoIcons.heart,
                    color: post.isLiked
                        ? Colors.red
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  '${post.likeCount}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 24),
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
    MarketplaceComment comment,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              CupertinoIcons.person_fill,
              size: 16,
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
                Text(
                  comment.content,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
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

  String _formatPrice(double price) {
    if (price >= 1000000) {
      return '${(price / 1000000).toStringAsFixed(1)}M đ';
    } else if (price >= 1000) {
      return '${(price / 1000).toStringAsFixed(0)}K đ';
    }
    return '${price.toStringAsFixed(0)} đ';
  }
}

