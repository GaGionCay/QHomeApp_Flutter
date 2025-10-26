import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../auth/api_client.dart';
import 'post_dto.dart';
import 'post_service.dart';

class PostFeed extends StatefulWidget {
  final PostService postService;
  const PostFeed({super.key, required this.postService});

  @override
  State<PostFeed> createState() => _PostFeedState();
}

class _PostFeedState extends State<PostFeed> {
  List<PostDto> posts = [];

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    final fetched = await widget.postService.getAllPosts();
    setState(() => posts = fetched);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(post.content),
              Wrap(
                children: post.imageUrls
                    .map((url) => Image.network(ApiClient.fileUrl(url)))
                    .toList(),
              ),
              Row(
                children: [
                  IconButton(
                      icon: Icon(
                          post.likedByMe ? Icons.favorite : Icons.favorite_border),
                      onPressed: () async {
                        if (post.likedByMe) {
                          await widget.postService.unlikePost(post.id);
                        } else {
                          await widget.postService.likePost(post.id);
                        }
                        _loadPosts();
                      }),
                  Text('${post.likeCount} likes'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
