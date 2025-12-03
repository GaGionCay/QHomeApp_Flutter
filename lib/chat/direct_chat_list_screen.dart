import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/chat/conversation.dart';
import 'chat_service.dart';
import 'direct_chat_screen.dart';
import 'direct_invitations_screen.dart';
import '../core/event_bus.dart';
import '../models/marketplace_post.dart';

class DirectChatListScreen extends StatefulWidget {
  final MarketplacePost? sharePost;
  
  const DirectChatListScreen({super.key, this.sharePost});

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
    _setupChatNotificationListener();
  }

  void _setupChatNotificationListener() {
    AppEventBus().on('chat_notification_received', (data) {
      if (!mounted) return;
      
      try {
        final type = data['type']?.toString();
        final chatId = data['chatId']?.toString();
        
        if (type == 'directMessage' && chatId != null) {
          // Refresh conversations to update unreadCount and show unhidden conversations
          // When a new message arrives, hidden conversations will be unhidden automatically
          _loadConversations();
        }
      } catch (e) {
        print('⚠️ Error handling chat notification: $e');
      }
    });
    
    // Also listen for direct chat activity updates
    AppEventBus().on('direct_chat_activity_updated', (_) {
      if (!mounted) return;
      _loadConversations();
    });
  }

  @override
  void dispose() {
    AppEventBus().off('chat_notification_received');
    AppEventBus().off('direct_chat_activity_updated');
    super.dispose();
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
      print('📤 [DirectChatListScreen] Loading pending invitations count...');
      final count = await _service.countPendingDirectInvitations();
      print('✅ [DirectChatListScreen] Pending invitations count: $count');
      if (mounted) {
        setState(() {
          _pendingInvitationsCount = count;
        });
      }
    } catch (e) {
      print('❌ [DirectChatListScreen] Error loading invitations count: $e');
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
    if (lastMessage.messageType == 'VIDEO') return '🎥 Đã gửi một video';
    if (lastMessage.messageType == 'MARKETPLACE_POST') {
      // Hiển thị tiêu đề bài viết thay vì JSON
      if (lastMessage.postTitle != null && lastMessage.postTitle!.isNotEmpty) {
        return '📦 ${lastMessage.postTitle!.length > 45 
            ? '${lastMessage.postTitle!.substring(0, 45)}...' 
            : lastMessage.postTitle!}';
      }
      return '📦 Đã chia sẻ một bài viết';
    }
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
                          final isMuted = conversation.isMuted || 
                              (conversation.muteUntil != null && 
                               conversation.muteUntil!.isAfter(DateTime.now()));
                          
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
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isMuted)
                                      Icon(
                                        CupertinoIcons.bell_slash,
                                        size: 16,
                                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                                      ),
                                    if (isMuted) const SizedBox(width: 4),
                                    Text(
                                      _formatTime(conversation.lastMessage?.createdAt ?? conversation.updatedAt),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                  ],
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
                            onLongPress: () => _showConversationOptions(context, conversation),
                            onTap: () async {
                              if (widget.sharePost != null) {
                                // Share post to direct chat
                                try {
                                  await _service.shareMarketplacePostToDirect(
                                    conversationId: conversation.id,
                                    post: widget.sharePost!,
                                  );
                                  if (mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('✅ Đã chia sẻ bài viết'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Lỗi: ${e.toString()}'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              } else {
                                // Normal navigation to chat
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
                              }
                            },
                          );
                        },
                      ),
      ),
    );
  }

  Future<void> _showConversationOptions(BuildContext context, Conversation conversation) async {
    final isMuted = conversation.isMuted || 
        (conversation.muteUntil != null && conversation.muteUntil!.isAfter(DateTime.now()));
    
    final result = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMuted)
              ListTile(
                leading: const Icon(CupertinoIcons.bell),
                title: const Text('Bật thông báo'),
                onTap: () => Navigator.pop(context, 'unmute'),
              )
            else ...[
              ListTile(
                leading: const Icon(CupertinoIcons.bell_slash),
                title: const Text('Tắt thông báo trong 1 giờ'),
                onTap: () => Navigator.pop(context, 'mute_1h'),
              ),
              ListTile(
                leading: const Icon(CupertinoIcons.bell_slash),
                title: const Text('Tắt thông báo trong 2 giờ'),
                onTap: () => Navigator.pop(context, 'mute_2h'),
              ),
              ListTile(
                leading: const Icon(CupertinoIcons.bell_slash),
                title: const Text('Tắt thông báo trong 24 giờ'),
                onTap: () => Navigator.pop(context, 'mute_24h'),
              ),
              ListTile(
                leading: const Icon(CupertinoIcons.bell_slash),
                title: const Text('Tắt thông báo cho đến khi mở lại'),
                onTap: () => Navigator.pop(context, 'mute_indefinite'),
              ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(CupertinoIcons.delete, color: Colors.red),
              title: const Text('Xóa đoạn chat', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'hide'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      try {
        if (result == 'unmute') {
          await _service.unmuteDirectConversation(conversation.id);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Đã bật lại thông báo')),
          );
        } else if (result.startsWith('mute_')) {
          int? durationHours;
          if (result == 'mute_1h') {
            durationHours = 1;
          } else if (result == 'mute_2h') {
            durationHours = 2;
          } else if (result == 'mute_24h') {
            durationHours = 24;
          } else if (result == 'mute_indefinite') {
            durationHours = null;
          }
          await _service.muteDirectConversation(
            conversationId: conversation.id,
            durationHours: durationHours,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Đã tắt thông báo${durationHours != null ? ' trong $durationHours giờ' : ''}')),
          );
        } else if (result == 'hide') {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Xóa đoạn chat'),
              content: const Text('Bạn có chắc chắn muốn xóa đoạn chat này? Đoạn chat sẽ xuất hiện lại khi có tin nhắn mới.'),
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
            await _service.hideDirectConversation(conversation.id);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Đã xóa đoạn chat')),
            );
          }
        }
        
        if (mounted) {
          _loadConversations();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: ${e.toString()}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

