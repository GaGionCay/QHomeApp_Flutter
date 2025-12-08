// ignore_for_file: use_build_context_synchronously
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/chat/conversation.dart';
import 'chat_service.dart';
import 'direct_chat_screen.dart';
import 'direct_invitations_screen.dart';
import '../core/event_bus.dart';
import '../models/marketplace_post.dart';
import '../auth/token_storage.dart';

class DirectChatListScreen extends StatefulWidget {
  final MarketplacePost? sharePost;
  
  const DirectChatListScreen({super.key, this.sharePost});

  @override
  State<DirectChatListScreen> createState() => _DirectChatListScreenState();
}

class _DirectChatListScreenState extends State<DirectChatListScreen> {
  final ChatService _service = ChatService();
  final TokenStorage _tokenStorage = TokenStorage();
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;
  int _pendingInvitationsCount = 0;
  String? _currentResidentId;

  @override
  void initState() {
    super.initState();
    _loadCurrentResidentId();
    _loadConversations();
    _loadInvitationsCount();
    _setupChatNotificationListener();
  }

  Future<void> _loadCurrentResidentId() async {
    _currentResidentId = await _tokenStorage.readResidentId();
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
      print('📢 [DirectChatListScreen] Received direct_chat_activity_updated event');
      if (!mounted) {
        print('⚠️ [DirectChatListScreen] Widget not mounted, skipping refresh');
        return;
      }
      print('🔄 [DirectChatListScreen] Refreshing conversations list...');
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
    print('📥 [DirectChatListScreen] _loadConversations called');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print('📤 [DirectChatListScreen] Calling getConversations API');
      final conversations = await _service.getConversations();
      print('✅ [DirectChatListScreen] getConversations response received - count: ${conversations.length}');
      
      // Log unread counts for each conversation
      for (var conv in conversations) {
        print('   - Conversation ${conv.id}: unreadCount = ${conv.unreadCount ?? 0}');
      }
      
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _isLoading = false;
        });
        print('✅ [DirectChatListScreen] State updated with ${conversations.length} conversations');
      }
    } catch (e, stackTrace) {
      print('❌ [DirectChatListScreen] Error loading conversations: $e');
      print('❌ [DirectChatListScreen] Stack trace: $stackTrace');
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showInviteByPhoneDialog(context),
        child: const Icon(CupertinoIcons.person_add),
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
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Chưa có cuộc trò chuyện nào',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                          
                          return GestureDetector(
                            onLongPress: () {
                              print('🔍 [DirectChatListScreen] GestureDetector onLongPress triggered!');
                              print('   - Conversation ID: ${conversation.id}');
                              print('   - Calling _showConversationOptions...');
                              _showConversationOptions(context, conversation);
                            },
                            child: ListTile(
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
                                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                        ),
                                      if (isMuted) const SizedBox(width: 4),
                                      Text(
                                        _formatTime(conversation.lastMessage?.createdAt ?? conversation.updatedAt),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  Future<void> _showConversationOptions(BuildContext context, Conversation conversation) async {
    print('🔍 [DirectChatListScreen] Long press detected on conversation:');
    print('   - Conversation ID: ${conversation.id}');
    print('   - Participant 1: ${conversation.participant1Id} (${conversation.participant1Name})');
    print('   - Participant 2: ${conversation.participant2Id} (${conversation.participant2Name})');
    print('   - Current Resident ID: $_currentResidentId');
    print('   - Status: ${conversation.status}');
    print('   - Is Muted: ${conversation.isMuted}');
    print('   - Mute Until: ${conversation.muteUntil}');
    
    final isMuted = conversation.isMuted || 
        (conversation.muteUntil != null && conversation.muteUntil!.isAfter(DateTime.now()));
    
    print('   - Will show muted options: $isMuted');
    print('   - Showing conversation options bottom sheet...');
    
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
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
              leading: const Icon(CupertinoIcons.person_crop_circle_badge_xmark, color: Colors.red),
              title: const Text('Chặn người dùng', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'block'),
            ),
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

    print('🔍 [DirectChatListScreen] User selected option: $result');

    if (result != null && mounted) {
      try {
        final messenger = ScaffoldMessenger.of(context);
        if (result == 'unmute') {
          print('🔍 [DirectChatListScreen] Processing: Unmute conversation');
          await _service.unmuteDirectConversation(conversation.id);
          messenger.showSnackBar(
            const SnackBar(content: Text('✅ Đã bật lại thông báo')),
          );
        } else if (result.startsWith('mute_')) {
          print('🔍 [DirectChatListScreen] Processing: Mute conversation - $result');
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
          messenger.showSnackBar(
            SnackBar(content: Text('✅ Đã tắt thông báo${durationHours != null ? ' trong $durationHours giờ' : ''}')),
          );
        } else if (result == 'block') {
          print('🔍 [DirectChatListScreen] Processing: Block user');
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Chặn người dùng'),
              content: const Text(
                'Bạn có chắc chắn muốn chặn người dùng này? Sau khi chặn, bạn sẽ không thể gửi hoặc nhận tin nhắn từ người này.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Chặn'),
                ),
              ],
            ),
          );
          
          if (confirmed == true && mounted) {
            try {
              if (_currentResidentId == null) {
                await _loadCurrentResidentId();
              }
              
              if (_currentResidentId == null) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Không thể xác định người dùng để chặn'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }
              
              final otherParticipantId = conversation.getOtherParticipantId(_currentResidentId!);
              await _service.blockUser(otherParticipantId);
              
              // Emit event to update badges and refresh blocked users list
              AppEventBus().emit('direct_chat_activity_updated');
              AppEventBus().emit('blocked_users_updated');
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Đã chặn người dùng'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Lỗi khi chặn người dùng: ${e.toString()}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }
        } else if (result == 'hide') {
          print('🔍 [DirectChatListScreen] Processing: Hide conversation');
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

  Future<void> _showInviteByPhoneDialog(BuildContext context) async {
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mời chat bằng số điện thoại'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    hintText: '0123456789',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  enabled: !isLoading,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng nhập số điện thoại';
                    }
                    final phone = value.trim().replaceAll(RegExp(r'[^0-9]'), '');
                    if (phone.length != 10) {
                      return 'Số điện thoại phải có 10 chữ số';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: isLoading ? null : () async {
                if (!formKey.currentState!.validate()) return;
                
                setDialogState(() => isLoading = true);
                
                try {
                  final phone = phoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
                  final invitation = await _service.createDirectInvitation(
                    phoneNumber: phone,
                    initialMessage: null,
                  );
                  
                  if (mounted) {
                    Navigator.pop(context);
                    // Check invitation status to show appropriate message
                    // If status is PENDING and invitation was created more than 1 second ago, it's an existing invitation
                    final now = DateTime.now();
                    final createdAt = invitation.createdAt;
                    final isExistingInvitation = createdAt != null && 
                        now.difference(createdAt).inSeconds > 1;
                    
                    if (invitation.status == 'PENDING' && isExistingInvitation) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lời mời đã tồn tại và đang chờ phản hồi'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Đã gửi lời mời chat'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                    _loadConversations();
                    _loadInvitationsCount();
                  }
                } catch (e) {
                  if (mounted) {
                    setDialogState(() => isLoading = false);
                    final errorMessage = e.toString().replaceFirst('Exception: ', '');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Lỗi: $errorMessage'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                }
              },
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Gửi lời mời'),
            ),
          ],
        ),
      ),
    );
  }
}



