import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import 'post_service.dart';
import 'create_post_widget.dart';
import 'comment_widget.dart';
import 'post_dto.dart';
import 'post_socket_service.dart';
import '../auth/token_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class PostFeedScreen extends StatefulWidget {
  const PostFeedScreen({super.key});

  @override
  State<PostFeedScreen> createState() => _PostFeedScreenState();
}

class _PostFeedScreenState extends State<PostFeedScreen> {
  late PostService postService;
  late PostSocketService socketService;
  List<PostDto> posts = [];
  int? currentUserId;

  @override
  void initState() {
    super.initState();
    postService = PostService(ApiClient());
    socketService = PostSocketService();
    _loadCurrentUserId();
    _loadPosts();

    socketService.listenLikes(_onLikeReceived);
    socketService.listenComments(_onCommentReceived);
    socketService.listenShares(_onShareReceived);
  }

  void _onLikeReceived(PostLikeDto likeDto) {
    final idx = posts.indexWhere((p) => p.id == likeDto.postId);
    if (idx != -1) {
      final p = posts[idx];
      if (likeDto.userId != currentUserId) {
        setState(() => posts[idx] = p.copyWith(likeCount: p.likeCount + 1));
      }
    }
  }

  void _onCommentReceived(PostCommentDto commentDto) {
    final idx = posts.indexWhere((p) => p.id == commentDto.postId);
    if (idx != -1) {
      final p = posts[idx];
      setState(() => posts[idx] = p.copyWith(commentCount: p.commentCount + 1));
    }
  }

  void _onShareReceived(Map<String, dynamic> shareData) {
    final postId = shareData['postId'];
    final userId = shareData['userId'];
    final idx = posts.indexWhere((p) => p.id == postId);
    if (idx != -1) setState(() {});

    if (userId == currentUserId) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('You shared a post!')));
    }
  }

  Future<void> _loadCurrentUserId() async {
    final token = await TokenStorage().readAccessToken();
    if (token != null) {
      final decoded = JwtDecoder.decode(token);
      setState(() {
        currentUserId = decoded['userId'] is int
            ? decoded['userId']
            : int.tryParse(decoded['userId'].toString());
      });
    }
  }

  Future<void> _loadPosts() async {
    final fetched = await postService.getAllPosts();
    setState(() => posts = fetched);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mini Facebook')),
      body: RefreshIndicator(
        onRefresh: _loadPosts,
        child: ListView(
          children: [
            CreatePostWidget(postService: postService, onPostCreated: _loadPosts),
            const Divider(),
            ...posts.map((post) => _buildPostCard(post)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(PostDto post) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage:
                      NetworkImage(ApiClient.fileUrl("avatar_${post.userId}.jpg")),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "User ${post.userId}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  "${post.createdAt.hour}:${post.createdAt.minute.toString().padLeft(2, '0')}",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(post.content),
            if (post.imageUrls.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: post.imageUrls
                    .map((url) => Image.network(
                          ApiClient.fileUrl(url),
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ))
                    .toList(),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton(
                  icon: Icon(post.likedByMe ? Icons.favorite : Icons.favorite_border),
                  onPressed: () async {
                    final updatedPost = post.copyWith(
                      likedByMe: !post.likedByMe,
                      likeCount: post.likeCount + (post.likedByMe ? -1 : 1),
                    );

                    setState(() {
                      final idx = posts.indexWhere((p) => p.id == post.id);
                      if (idx != -1) posts[idx] = updatedPost;
                    });

                    if (updatedPost.likedByMe) {
                      await postService.likePost(post.id);
                    } else {
                      await postService.unlikePost(post.id);
                    }
                  },
                ),
                Text('${post.likeCount} likes'),
                IconButton(
                  icon: const Icon(Icons.comment),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => SizedBox(
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: CommentWidget(
                          postService: postService,
                          postId: post.id,
                          socketService: socketService,
                        ),
                      ),
                    );
                  },
                ),
                Text('${post.commentCount} comments'),
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () async {
                    await postService.sharePost(post.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Post shared!')));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    socketService.dispose();
    super.dispose();
  }
}
