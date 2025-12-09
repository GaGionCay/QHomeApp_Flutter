// ignore_for_file: use_build_context_synchronously
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
        // Error handled silently
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
      final count = await _chatService.countPendingDirectInvitations();
      if (mounted) {
        setState(() {
          _pendingDirectInvitationsCount = count;
        });
        // Force rebuild to ensure UI updates
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      // Error handled silently
      if (mounted) {
        setState(() {
          _pendingDirectInvitationsCount = 0;
        });
      }
    }
  }

  Future<void> _loadDirectConversations() async {
    print('📋 [GroupListScreen] ========== _loadDirectConversations START ==========');
    print('📋 [GroupListScreen] Current _directConversations.length: ${_directConversations.length}');
    try {
      print('📋 [GroupListScreen] Calling _chatService.getConversations()...');
      final conversations = await _chatService.getConversations();
      print('📋 [GroupListScreen] getConversations() returned ${conversations.length} conversations');
      
      if (mounted) {
        print('📋 [GroupListScreen] Widget is mounted, updating state...');
        setState(() {
          _directConversations = conversations;
        });
        print('📋 [GroupListScreen] State updated successfully');
        print('📋 [GroupListScreen]   _directConversations.length: ${_directConversations.length}');
      } else {
        print('⚠️ [GroupListScreen] Widget NOT mounted, skipping state update');
      }
      print('📋 [GroupListScreen] ========== _loadDirectConversations END ==========');
    } catch (e, stackTrace) {
      print('❌ [GroupListScreen] Error loading direct conversations:');
      print('❌ [GroupListScreen]   Error: $e');
      print('❌ [GroupListScreen]   Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _directConversations = [];
        });
        print('⚠️ [GroupListScreen] Set _directConversations to empty list due to error');
      }
      print('📋 [GroupListScreen] ========== _loadDirectConversations END (ERROR) ==========');
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
    print('📋 [GroupListScreen] ========== build() called ==========');
    print('📋 [GroupListScreen]   _directConversations.length: ${_directConversations.length}');
    print('📋 [GroupListScreen]   _pendingInvitationsCount: $_pendingInvitationsCount');
    print('📋 [GroupListScreen]   _pendingDirectInvitationsCount: $_pendingDirectInvitationsCount');
    print('📋 [GroupListScreen]   viewModel.groups.length: ${_viewModel.groups.length}');
    
    final theme = Theme.of(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
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
                        builder: (_) => const InvitationsScreen(),
                      ),
                    );
                    if (mounted) {
                      _viewModel.refresh();
                      _loadInvitationsCount();
                      _loadDirectInvitationsCount();
                      _loadDirectConversations();
                    }
                  },
                ),
                // Badge for total invitations count (group + direct)
                if ((_pendingInvitationsCount + _pendingDirectInvitationsCount) > 0)
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
                          (_pendingInvitationsCount + _pendingDirectInvitationsCount) > 99
                              ? '99+'
                              : '${_pendingInvitationsCount + _pendingDirectInvitationsCount}',
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
            PopupMenuButton<String>(
              icon: const Icon(CupertinoIcons.ellipsis),
              onSelected: (value) async {
                if (value == 'friends') {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FriendsScreen(),
                    ),
                  );
                } else if (value == 'blocked') {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BlockedUsersScreen(),
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'friends',
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.person_2, size: 20),
                      SizedBox(width: 12),
                      Text('Bạn bè'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'blocked',
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.person_crop_circle_badge_xmark, size: 20),
                      SizedBox(width: 12),
                      Text('Người dùng đã chặn'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Builder(
          builder: (context) {
            final viewModel = Provider.of<ChatViewModel>(context);
            
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

            // Show empty state only if no groups AND no direct conversations
            if (viewModel.groups.isEmpty && _directConversations.isEmpty) {
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
                      'Chưa có cuộc trò chuyện nào',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tạo nhóm mới hoặc mời bạn bè để bắt đầu trò chuyện',
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

            // Calculate itemCount with clear sections - chỉ Direct Chat và Group Chat
            int itemCount = 0;
            int directChatHeaderCount = _directConversations.isNotEmpty ? 1 : 0;
            int directChatItemsCount = _directConversations.length;
            int groupChatHeaderCount = viewModel.groups.isNotEmpty ? 1 : 0;
            int groupChatItemsCount = viewModel.groups.length;
            int loadMoreCount = viewModel.hasMore ? 1 : 0;
            
            itemCount = directChatHeaderCount + 
                       directChatItemsCount + 
                       groupChatHeaderCount + 
                       groupChatItemsCount + 
                       loadMoreCount;
            
            print('📋 [GroupListScreen] ListView itemCount calculation:');
            print('📋 [GroupListScreen]   directChatHeaderCount: $directChatHeaderCount');
            print('📋 [GroupListScreen]   directChatItemsCount: $directChatItemsCount');
            print('📋 [GroupListScreen]   groupChatHeaderCount: $groupChatHeaderCount');
            print('📋 [GroupListScreen]   groupChatItemsCount: $groupChatItemsCount');
            print('📋 [GroupListScreen]   loadMoreCount: $loadMoreCount');
            print('📋 [GroupListScreen]   Total itemCount: $itemCount');
            
            return RefreshIndicator(
              onRefresh: () async {
                await viewModel.refresh();
                await _loadInvitationsCount();
                await _loadDirectInvitationsCount();
                await _loadDirectConversations();
              },
              child: ListView.builder(
                key: ValueKey('list_${_directConversations.length}_${viewModel.groups.length}'),
                padding: const EdgeInsets.all(16),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  print('📋 [GroupListScreen] ListView.builder building item $index');
                  
                  int offset = 0;
                  
                  // 1. Direct chat section header
                  if (index == offset && directChatHeaderCount > 0) {
                    print('📋 [GroupListScreen]   Rendering direct chat header');
                    return Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(
                        'Trò chuyện trực tiếp',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    );
                  }
                  offset += directChatHeaderCount;
                  
                  // 2. Direct chat conversations
                  if (index >= offset && index < offset + directChatItemsCount) {
                    final conversationIndex = index - offset;
                    print('📋 [GroupListScreen]   Rendering direct conversation item $conversationIndex of ${_directConversations.length}');
                    final conversation = _directConversations[conversationIndex];
                    print('📋 [GroupListScreen]     Conversation ID: ${conversation.id}');
                    print('📋 [GroupListScreen]     Status: ${conversation.status}');
                    
                    final otherParticipantName = _currentResidentId != null
                        ? (conversation.getOtherParticipantName(_currentResidentId!) ?? 'Người dùng')
                        : (conversation.participant1Name ?? conversation.participant2Name ?? 'Người dùng');
                    final unreadCount = conversation.unreadCount ?? 0;
                    final isMuted = conversation.isMuted || 
                        (conversation.muteUntil != null && 
                         conversation.muteUntil!.isAfter(DateTime.now()));
                    
                    print('📋 [GroupListScreen]     otherParticipantName: $otherParticipantName');
                    print('📋 [GroupListScreen]     unreadCount: $unreadCount');
                    
                    String getLastMessagePreview(Conversation conv) {
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
                      child: GestureDetector(
                        onLongPress: () {
                          _showDirectConversationOptions(context, conversation);
                        },
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
                          getLastMessagePreview(conversation),
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
                      ),
                    );
                  }
                  offset += directChatItemsCount;
                  
                  // 3. Group chat section header
                  if (index == offset && groupChatHeaderCount > 0) {
                    print('📋 [GroupListScreen]   Rendering group chat header');
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
                  offset += groupChatHeaderCount;
                  
                  // 4. Group chat groups
                  if (index >= offset && index < offset + groupChatItemsCount) {
                    final groupIndex = index - offset;
                    print('📋 [GroupListScreen]   Rendering group item $groupIndex of ${viewModel.groups.length}');
                    final group = viewModel.groups[groupIndex];
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
                  offset += groupChatItemsCount;
                  
                  // 5. Load more indicator
                  if (index == offset && loadMoreCount > 0) {
                    print('📋 [GroupListScreen]   Rendering load more indicator');
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  
                  // Should not reach here
                  print('⚠️ [GroupListScreen] Unexpected index: $index, itemCount: $itemCount, offset: $offset');
                  return const SizedBox.shrink();
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

    if (result != null && mounted) {
      try {
        final messenger = ScaffoldMessenger.of(context);
        if (result == 'unmute') {
          await _chatService.unmuteDirectConversation(conversation.id);
          messenger.showSnackBar(
            const SnackBar(content: Text('✅ Đã bật lại thông báo')),
          );
        } else if (result.startsWith('mute_')) {
          print('🔍 [GroupListScreen] Processing: Mute conversation - $result');
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
          messenger.showSnackBar(
            SnackBar(content: Text('✅ Đã tắt thông báo${durationHours != null ? ' trong $durationHours giờ' : ''}')),
          );
        } else if (result == 'block') {
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
              await _chatService.blockUser(otherParticipantId);
              
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
          print('🔍 [GroupListScreen] Processing: Mute conversation - $result');
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
            fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (group.description != null && group.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                group.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '${group.currentMemberCount}/${group.maxMembers} thành viên',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
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

class _UnifiedInvitationsSection extends StatelessWidget {
  final int groupInvitationsCount;
  final int directInvitationsCount;
  final VoidCallback onGroupInvitationsTap;
  final VoidCallback onDirectInvitationsTap;

  const _UnifiedInvitationsSection({
    required this.groupInvitationsCount,
    required this.directInvitationsCount,
    required this.onGroupInvitationsTap,
    required this.onDirectInvitationsTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalCount = groupInvitationsCount + directInvitationsCount;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        child: Column(
          children: [
            // Header
            Padding(
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Lời mời',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          totalCount > 0 
                              ? 'Bạn có $totalCount lời mời mới'
                              : 'Lời mời',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (totalCount > 0) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        totalCount > 99 ? '99+' : '$totalCount',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Divider
            const Divider(height: 1),
            // Group invitations button
            if (groupInvitationsCount > 0)
              InkWell(
                onTap: onGroupInvitationsTap,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.group,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Lời mời tham gia nhóm',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          groupInvitationsCount > 99 ? '99+' : '$groupInvitationsCount',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ),
              ),
            // Direct invitations button
            if (directInvitationsCount > 0)
              InkWell(
                onTap: onDirectInvitationsTap,
                borderRadius: BorderRadius.only(
                  bottomLeft: const Radius.circular(12),
                  bottomRight: const Radius.circular(12),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: groupInvitationsCount > 0 ? 12 : 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.chat_bubble_2,
                        size: 20,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Lời mời trò chuyện',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          directInvitationsCount > 99 ? '99+' : '$directInvitationsCount',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DirectInvitationsSection extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _DirectInvitationsSection({
    super.key,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('direct_invitations_$count'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: () {
            onTap();
          },
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Lời mời trò chuyện',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        count > 0 
                            ? 'Bạn có $count lời mời trò chuyện'
                            : 'Lời mời trò chuyện',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                // Only show count badge if count >= 1
                if (count > 0) ...[
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
                ],
                const SizedBox(width: 8),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



