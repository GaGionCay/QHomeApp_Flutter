import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/chat/message.dart';
import 'chat_service.dart';
import 'chat_message_view_model.dart';
import 'invite_members_dialog.dart';
import 'group_members_screen.dart';

class ChatScreen extends StatefulWidget {
  final String groupId;

  const ChatScreen({super.key, required this.groupId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatMessageViewModel _viewModel;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final service = ChatService();
    _viewModel = ChatMessageViewModel(service);
    _viewModel.initialize(widget.groupId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    _viewModel.sendMessage(content);
    _messageController.clear();
  }

  Future<void> _showRenameDialog(BuildContext context, ChatMessageViewModel viewModel) async {
    final controller = TextEditingController(text: viewModel.groupName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đổi tên nhóm'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Nhập tên nhóm mới',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(context, newName);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      try {
        await viewModel.updateGroupName(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã đổi tên nhóm thành công')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: ${e.toString()}')),
          );
        }
      }
    }
  }

  Future<void> _showLeaveConfirmation(BuildContext context, ChatMessageViewModel viewModel) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rời nhóm'),
        content: const Text('Bạn có chắc chắn muốn rời nhóm này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Rời nhóm'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        await viewModel.leaveGroup();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã rời nhóm')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: ${e.toString()}')),
          );
        }
      }
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context, ChatMessageViewModel viewModel) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa nhóm'),
        content: const Text('Bạn có chắc chắn muốn xóa nhóm này không? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa nhóm'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        await viewModel.deleteGroup();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã xóa nhóm')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: ${e.toString()}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: Consumer<ChatMessageViewModel>(
            builder: (context, viewModel, child) {
              if (viewModel.isLoading && viewModel.groupName == null) {
                return const Text('Đang tải...');
              }
              return Text(
                viewModel.groupName ?? 'Nhóm chat',
                style: const TextStyle(fontWeight: FontWeight.bold),
              );
            },
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(CupertinoIcons.person_add),
              onPressed: () async {
                final result = await showDialog(
                  context: context,
                  builder: (_) => InviteMembersDialog(groupId: widget.groupId),
                );
                if (result == true && mounted) {
                  // Refresh group info if needed
                }
              },
            ),
            Consumer<ChatMessageViewModel>(
              builder: (context, viewModel, child) {
                return PopupMenuButton<String>(
                  icon: const Icon(CupertinoIcons.ellipsis),
                  onSelected: (value) async {
                    if (value == 'members') {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupMembersScreen(groupId: widget.groupId),
                        ),
                      );
                    } else if (value == 'rename') {
                      await _showRenameDialog(context, viewModel);
                    } else if (value == 'leave') {
                      await _showLeaveConfirmation(context, viewModel);
                    } else if (value == 'delete') {
                      await _showDeleteConfirmation(context, viewModel);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'members',
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.person_2, size: 20),
                          SizedBox(width: 8),
                          Text('Xem thành viên'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.pencil, size: 20),
                          SizedBox(width: 8),
                          Text('Đổi tên nhóm'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'leave',
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.arrow_right_square, size: 20),
                          SizedBox(width: 8),
                          Text('Rời nhóm'),
                        ],
                      ),
                    ),
                    if (viewModel.isCreator)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(CupertinoIcons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Xóa nhóm', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Consumer<ChatMessageViewModel>(
                builder: (context, viewModel, child) {
                  if (viewModel.isLoading && viewModel.messages.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (viewModel.messages.isEmpty) {
                    return Center(
                      child: Text(
                        'Chưa có tin nhắn nào',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: viewModel.messages.length + (viewModel.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == viewModel.messages.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final message = viewModel.messages[viewModel.messages.length - 1 - index];
                      // Check if this is a system message
                      if (message.messageType == 'SYSTEM') {
                        return _SystemMessageBubble(message: message);
                      }
                      return _MessageBubble(
                        message: message,
                        currentResidentId: viewModel.currentResidentId,
                      );
                    },
                  );
                },
              ),
            ),
            _MessageInput(
              controller: _messageController,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String? currentResidentId;

  const _MessageBubble({
    required this.message,
    this.currentResidentId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = currentResidentId != null && message.senderId == currentResidentId;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                message.senderName ?? 'Người dùng',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isMe
                      ? Colors.white.withOpacity(0.8)
                      : theme.colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (message.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: message.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              )
            else if (message.content != null && message.content!.isNotEmpty)
              Text(
                message.content!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isMe ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: isMe
                    ? Colors.white.withOpacity(0.7)
                    : theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${time.day}/${time.month}/${time.year}';
  }
}

class _SystemMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _SystemMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.3),
                    thickness: 1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    message.content ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280), // Gray color
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.3),
                    thickness: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _MessageInput({
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Nhập tin nhắn...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(CupertinoIcons.paperplane_fill),
            onPressed: onSend,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

