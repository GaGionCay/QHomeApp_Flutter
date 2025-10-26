import 'package:flutter/material.dart';
import 'post_service.dart';
import 'post_dto.dart';
import 'post_socket_service.dart';

class CommentWidget extends StatefulWidget {
  final PostService postService;
  final int postId;
  final PostSocketService socketService;

  const CommentWidget({
    super.key,
    required this.postService,
    required this.postId,
    required this.socketService,
  });

  @override
  State<CommentWidget> createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  List<PostCommentDto> comments = [];
  final TextEditingController _controller = TextEditingController();
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadComments();

    // Listen realtime comment
    widget.socketService.listenComments((commentDto) {
      if (commentDto.postId == widget.postId) {
        _updateCommentList(commentDto);
      }
    });
  }

  Future<void> _loadComments() async {
    setState(() => loading = true);
    final fetched = await widget.postService.getComments(widget.postId);
    setState(() {
      comments = fetched;
      loading = false;
    });
  }


void _updateCommentList(PostCommentDto newComment) {
  setState(() {
    if (newComment.parentId == null) {
      if (!comments.any((c) => c.id == newComment.id)) {
        comments.add(newComment);
      }
    } else {
      PostCommentDto? parent;
      for (var c in comments) {
        if (c.id == newComment.parentId) {
          parent = c;
          break;
        }
      }
      if (parent != null && !parent.replies.any((r) => r.id == newComment.id)) {
        parent.replies.add(newComment);
      }
    }
  });
}


  Future<void> _addComment(String content) async {
    if (content.trim().isEmpty) return;
    await widget.postService.commentPost(widget.postId, content);
    _controller.clear();
  }

  Future<void> _replyToComment(int commentId, String content) async {
    if (content.trim().isEmpty) return;
    await widget.postService.replyToComment(widget.postId, commentId, content);
  }

  Future<void> _deleteComment(int commentId) async {
    await widget.postService.deleteComment(commentId);
    setState(() {
      comments.removeWhere((c) => c.id == commentId);
      for (var c in comments) {
        c.replies.removeWhere((r) => r.id == commentId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (loading)
          const LinearProgressIndicator()
        else
          Expanded(
            child: ListView(
              children: comments.map((c) => _buildComment(c)).toList(),
            ),
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Write a comment...',
                  ),
                  onSubmitted: _addComment,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () => _addComment(_controller.text),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComment(PostCommentDto comment) {
    final replyController = TextEditingController();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${comment.userName}: ${comment.content}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 16),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete Comment'),
                          content: const Text('Are you sure?'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel')),
                            ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete')),
                          ],
                        ),
                      ) ??
                      false;

                  if (confirmed) {
                    await _deleteComment(comment.id);
                  }
                },
              )
            ],
          ),
          if (comment.replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Column(
                children: comment.replies.map((r) => _buildComment(r)).toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 2),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: replyController,
                    decoration: const InputDecoration(
                      hintText: 'Reply...',
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                      isDense: true,
                    ),
                    onSubmitted: (text) {
                      _replyToComment(comment.id, text);
                      replyController.clear();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, size: 18),
                  onPressed: () {
                    _replyToComment(comment.id, replyController.text);
                    replyController.clear();
                  },
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
