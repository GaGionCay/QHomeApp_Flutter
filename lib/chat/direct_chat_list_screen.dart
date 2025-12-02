import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/chat/conversation.dart';
import 'chat_service.dart';
import 'direct_chat_screen.dart';
import 'direct_invitations_screen.dart';

class DirectChatListScreen extends StatefulWidget {
  const DirectChatListScreen({super.key});

  @override
  State<DirectChatListScreen> createState() => _DirectChatListScreenState();
}

class _DirectChatListScreenState extends State<DirectChatListScreen> {
  final ChatService _service = ChatService();
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;
  int _pendingInvitationsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _loadInvitationsCount();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final conversations = await _service.getConversations();
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Lỗi khi tải danh sách: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadInvitationsCount() async {
    try {
      final count = await _service.countPendingDirectInvitations();
      if (mounted) {
        setState(() {
          _pendingInvitationsCount = count;
        });
      }
    } catch (e) {
      // Ignore error
    }
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Hôm qua';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  String _getLastMessagePreview(Conversation conversation) {
    final lastMessage = conversation.lastMessage;
    if (lastMessage == null) return 'Chưa có tin nhắn';
    
    if (lastMessage.isDeleted) return 'Tin nhắn đã bị xóa';
    if (lastMessage.messageType == 'IMAGE') return '📷 Đã gửi một hình ảnh';
    if (lastMessage.messageType == 'FILE') return '📎 Đã gửi một tệp';
    if (lastMessage.messageType == 'AUDIO') return '🎤 Đã gửi một tin nhắn thoại';
    if (lastMessage.content != null && lastMessage.content!.isNotEmpty) {
      return lastMessage.content!.length > 50
          ? '${lastMessage.content!.substring(0, 50)}...'
          : lastMessage.content!;
    }
    return 'Tin nhắn mới';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Trò chuyện'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(CupertinoIcons.mail),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DirectInvitationsScreen(),
                    ),
                  );
                  if (mounted) {
                    _loadConversations();
                    _loadInvitationsCount();
                  }
                },
              ),
              if (_pendingInvitationsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 2,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Center(
                      child: Text(
                        _pendingInvitationsCount > 99
                            ? '99+'
                            : '$_pendingInvitationsCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadConversations();
          await _loadInvitationsCount();
        },
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _conversations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadConversations,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  )
                : _conversations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.chat_bubble,
                              size: 64,
                              color: theme.colorScheme.onSurface.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Chưa có cuộc trò chuyện nào',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          final conversation = _conversations[index];
                          final otherParticipantName = conversation.participant1Name ?? 
                              conversation.participant2Name ?? 'Người dùng';
                          final unreadCount = conversation.unreadCount ?? 0;
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Text(
                                otherParticipantName.isNotEmpty
                                    ? otherParticipantName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              otherParticipantName,
                              style: TextStyle(
                                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              _getLastMessagePreview(conversation),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: unreadCount > 0
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatTime(conversation.lastMessage?.createdAt ?? conversation.updatedAt),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                                if (unreadCount > 0) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      unreadCount > 99 ? '99+' : '$unreadCount',
                                      style: TextStyle(
                                        color: theme.colorScheme.onPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DirectChatScreen(
                                    conversationId: conversation.id,
                                    otherParticipantName: otherParticipantName,
                                  ),
                                ),
                              );
                              if (mounted) {
                                _loadConversations();
                              }
                            },
                          );
                        },
                      ),
      ),
    );
  }
}

