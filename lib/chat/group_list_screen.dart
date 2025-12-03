import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat/group.dart';
import '../models/chat/conversation.dart';
import 'chat_service.dart';
import 'chat_view_model.dart';
import 'create_group_screen.dart';
import 'chat_screen.dart';
import 'invitations_screen.dart';
import 'direct_chat_screen.dart';
import 'direct_invitations_screen.dart';
import 'blocked_users_screen.dart';
import 'friends_screen.dart';
import '../auth/token_storage.dart';
import '../core/event_bus.dart';
import '../models/marketplace_post.dart';

class GroupListScreen extends StatefulWidget {
  final MarketplacePost? sharePost;
  
  const GroupListScreen({super.key, this.sharePost});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  late final ChatViewModel _viewModel;
  final ChatService _chatService = ChatService();
  final TokenStorage _tokenStorage = TokenStorage();
  int _pendingInvitationsCount = 0;
  int _pendingDirectInvitationsCount = 0;
  List<Conversation> _directConversations = [];
  String? _currentResidentId;

  @override
  void initState() {
    super.initState();
    final service = ChatService();
    _viewModel = ChatViewModel(service);
    _viewModel.initialize();
    _loadInvitationsCount();
    _loadDirectInvitationsCount();
    _loadDirectConversations();
    _loadCurrentResidentId();
    _setupChatNotificationListener();
  }

  void _setupChatNotificationListener() {
    AppEventBus().on('chat_notification_received', (data) {
      if (!mounted) return;
      
      try {
        final type = data['type']?.toString();
        final chatId = data['chatId']?.toString();
        
        if (type == 'groupMessage' && chatId != null) {
          // Refresh groups to update unreadCount
          _viewModel.refresh();
        } else if (type == 'directMessage' && chatId != null) {
          // Refresh direct conversations to update unreadCount
          _loadDirectConversations();
        }
      } catch (e) {
        print('⚠️ Error handling chat notification: $e');
      }
    });
  }

  Future<void> _loadCurrentResidentId() async {
    _currentResidentId = await _tokenStorage.readResidentId();
    if (mounted) setState(() {});
  }

  Future<void> _loadInvitationsCount() async {
    try {
      final invitations = await _chatService.getMyPendingInvitations();
      if (mounted) {
        setState(() {
          _pendingInvitationsCount = invitations.length;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingInvitationsCount = 0;
        });
      }
    }
  }

  Future<void> _loadDirectInvitationsCount() async {
    try {
      print('📤 [GroupListScreen] Loading pending direct invitations count...');
      final count = await _chatService.countPendingDirectInvitations();
      print('✅ [GroupListScreen] Pending direct invitations count: $count');
      if (mounted) {
        setState(() {
          _pendingDirectInvitationsCount = count;
        });
      }
    } catch (e) {
      print('❌ [GroupListScreen] Error loading direct invitations count: $e');
      if (mounted) {
        setState(() {
          _pendingDirectInvitationsCount = 0;
        });
      }
    }
  }

  Future<void> _loadDirectConversations() async {
    try {
      final conversations = await _chatService.getConversations();
      if (mounted) {
        setState(() {
          _directConversations = conversations;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _directConversations = [];
        });
      }
    }
  }

  @override
  void dispose() {
    _viewModel.dispose();
    AppEventBus().off('blocked_users_updated');
    AppEventBus().off('chat_notification_received');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Nhóm chat'),
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
                        builder: (_) => const InvitationsScreen(),
                      ),
                    );
                    if (mounted) {
                      _viewModel.refresh();
                      _loadInvitationsCount();
                    }
                  },
                ),
                // Badge for invitations count
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
            IconButton(
              icon: const Icon(CupertinoIcons.add),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateGroupScreen(),
                  ),
                );
                if (result == true && mounted) {
                  _viewModel.refresh();
                }
              },
            ),
          ],
        ),
        body: Consumer<ChatViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.isLoading && viewModel.groups.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (viewModel.error != null && viewModel.groups.isEmpty) {
              return Center(
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
                      viewModel.error!,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => viewModel.refresh(),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              );
            }

            if (viewModel.groups.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.chat_bubble_2,
                      size: 64,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Chưa có nhóm chat nào',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tạo nhóm mới để bắt đầu trò chuyện',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreateGroupScreen(),
                          ),
                        );
                        if (result == true && mounted) {
                          viewModel.refresh();
                        }
                      },
                      icon: const Icon(CupertinoIcons.add),
                      label: const Text('Tạo nhóm mới'),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                await viewModel.refresh();
                await _loadInvitationsCount();
                await _loadDirectInvitationsCount();
                await _loadDirectConversations();
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: (_pendingInvitationsCount > 0 ? 1 : 0) + // Group invitations
                          (_pendingDirectInvitationsCount > 0 ? 1 : 0) + // Direct invitations
                          (_directConversations.isNotEmpty ? 1 : 0) + // Direct chat section header
                          _directConversations.length +
                          (viewModel.groups.isNotEmpty ? 1 : 0) + // Group chat section header
                          viewModel.groups.length + 
                          2 + // Blocked users section + Friends section
                          (viewModel.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  int currentIndex = index;
                  
                  // Group invitations section (first item if there are invitations)
                  if (_pendingInvitationsCount > 0 && currentIndex == 0) {
                    return _InvitationsSection(
                      count: _pendingInvitationsCount,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const InvitationsScreen(),
                          ),
                        );
                        if (mounted) {
                          _viewModel.refresh();
                          _loadInvitationsCount();
                        }
                      },
                    );
                  }
                  
                  // Adjust index after group invitations
                  if (_pendingInvitationsCount > 0) {
                    currentIndex--;
                  }
                  
                  // Direct invitations section
                  if (_pendingDirectInvitationsCount > 0 && currentIndex == 0) {
                    return _DirectInvitationsSection(
                      count: _pendingDirectInvitationsCount,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DirectInvitationsScreen(),
                          ),
                        );
                        if (mounted) {
                          _loadDirectInvitationsCount();
                          _loadDirectConversations();
                        }
                      },
                    );
                  }
                  
                  // Adjust index after direct invitations
                  if (_pendingDirectInvitationsCount > 0) {
                    currentIndex--;
                  }
                  
                  // Direct chat section header
                  if (_directConversations.isNotEmpty && currentIndex == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(
                        'Trò chuyện',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    );
                  }
                  
                  // Adjust index after direct chat header
                  if (_directConversations.isNotEmpty) {
                    currentIndex--;
                  }
                  
                  // Direct chat conversations
                  if (currentIndex < _directConversations.length) {
                    final conversation = _directConversations[currentIndex];
                    final otherParticipantName = _currentResidentId != null
                        ? (conversation.getOtherParticipantName(_currentResidentId!) ?? 'Người dùng')
                        : (conversation.participant1Name ?? conversation.participant2Name ?? 'Người dùng');
                    final unreadCount = conversation.unreadCount ?? 0;
                    final isMuted = conversation.isMuted || 
                        (conversation.muteUntil != null && 
                         conversation.muteUntil!.isAfter(DateTime.now()));
                    
                    String _getLastMessagePreview(Conversation conv) {
                      final lastMessage = conv.lastMessage;
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
                      final content = lastMessage.content;
                      if (content != null && content.isNotEmpty) {
                        return content.length > 50
                            ? '${content.substring(0, 50)}...'
                            : content;
                      }
                      return 'Tin nhắn mới';
                    }
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          radius: 28,
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          child: Text(
                            otherParticipantName.isNotEmpty
                                ? otherParticipantName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: theme.colorScheme.onSecondaryContainer,
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isMuted)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(
                                  CupertinoIcons.bell_slash,
                                  size: 18,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            if (unreadCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        ),
                        onLongPress: () => _showDirectConversationOptions(context, conversation),
                        onTap: () async {
                          if (widget.sharePost != null) {
                            // Share post to direct chat
                            try {
                              await _chatService.shareMarketplacePostToDirect(
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
                              _loadDirectConversations();
                              _viewModel.refresh();
                            }
                          }
                        },
                      ),
                    );
                  }
                  
                  // Adjust index after direct conversations
                  currentIndex -= _directConversations.length;
                  
                  // Group chat section header
                  if (viewModel.groups.isNotEmpty && currentIndex == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(
                        'Nhóm chat',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    );
                  }
                  
                  // Adjust index after group chat header
                  if (viewModel.groups.isNotEmpty) {
                    currentIndex--;
                  }
                  
                  // Group chat groups
                  if (currentIndex < viewModel.groups.length) {
                    final group = viewModel.groups[currentIndex];
                    return _GroupListItem(
                      group: group,
                      onTap: () async {
                        if (widget.sharePost != null) {
                          // Share post to group
                          try {
                            await _chatService.shareMarketplacePostToGroup(
                              groupId: group.id,
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
                              builder: (_) => ChatScreen(groupId: group.id),
                            ),
                          );
                          if (mounted) {
                            viewModel.refresh();
                          }
                        }
                      },
                      onLongPress: () => _showGroupOptions(context, group),
                    );
                  }
                  
                  // Adjust index after groups
                  if (viewModel.groups.isNotEmpty) {
                    currentIndex -= viewModel.groups.length;
                  }
                  
                  // Friends section
                  if (currentIndex == 0) {
                    return _FriendsSection(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FriendsScreen(),
                          ),
                        );
                      },
                    );
                  }
                  
                  // Adjust index after friends section
                  currentIndex--;
                  
                  // Blocked users section
                  if (currentIndex == 0) {
                    return _BlockedUsersSection(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BlockedUsersScreen(),
                          ),
                        );
                      },
                    );
                  }
                  
                  // Adjust index after blocked users section
                  currentIndex--;
                  
                  // Load more indicator
                  if (viewModel.hasMore && currentIndex == 0) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final group = viewModel.groups[currentIndex];
                  return _GroupListItem(
                    group: group,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(groupId: group.id),
                        ),
                      );
                      // Refresh to update unread count after returning from chat
                      if (mounted) {
                        _viewModel.refresh();
                      }
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showDirectConversationOptions(BuildContext context, Conversation conversation) async {
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
          await _chatService.unmuteDirectConversation(conversation.id);
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
          await _chatService.muteDirectConversation(
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
            await _chatService.hideDirectConversation(conversation.id);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Đã xóa đoạn chat')),
            );
          }
        }
        
        if (mounted) {
          _loadDirectConversations();
          _viewModel.refresh();
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

  Future<void> _showGroupOptions(BuildContext context, ChatGroup group) async {
    final isMuted = group.isMuted || 
        (group.muteUntil != null && group.muteUntil!.isAfter(DateTime.now()));
    
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      try {
        if (result == 'unmute') {
          await _chatService.unmuteGroupChat(group.id);
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
          await _chatService.muteGroupChat(
            groupId: group.id,
            durationHours: durationHours,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Đã tắt thông báo${durationHours != null ? ' trong $durationHours giờ' : ''}')),
          );
        }
        
        if (mounted) {
          _viewModel.refresh();
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

class _InvitationsSection extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _InvitationsSection({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.mail,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lời mời',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bạn có $count lời mời tham gia nhóm',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.right_chevron,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupListItem extends StatelessWidget {
  final ChatGroup group;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _GroupListItem({
    required this.group,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = (group.unreadCount ?? 0) > 0;
    final isMuted = group.isMuted || 
        (group.muteUntil != null && group.muteUntil!.isAfter(DateTime.now()));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage: group.avatarUrl != null
              ? NetworkImage(group.avatarUrl!)
              : null,
          child: group.avatarUrl == null
              ? Text(
                  group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        title: Text(
          group.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (group.description != null && group.description!.isNotEmpty)
              Text(
                group.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            Text(
              '${group.currentMemberCount}/${group.maxMembers} thành viên',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMuted)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  CupertinoIcons.bell_slash,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            if (hasUnread)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  group.unreadCount! > 99 ? '99+' : '${group.unreadCount}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        onLongPress: onLongPress,
        onTap: onTap,
      ),
    );
  }
}

class _FriendsSection extends StatelessWidget {
  final VoidCallback onTap;

  const _FriendsSection({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.person_2,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bạn bè',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Xem danh sách bạn bè và liên lạc lại',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedUsersSection extends StatelessWidget {
  final VoidCallback onTap;

  const _BlockedUsersSection({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.person_crop_circle_badge_xmark,
                  color: theme.colorScheme.onSecondaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Người dùng đã chặn',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Xem và quản lý danh sách người dùng đã chặn',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectInvitationsSection extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _DirectInvitationsSection({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.chat_bubble_2,
                  color: theme.colorScheme.onSecondaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lời mời trò chuyện',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bạn có $count lời mời trò chuyện',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.right_chevron,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


