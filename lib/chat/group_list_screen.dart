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
import '../auth/token_storage.dart';

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key});

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
      }
    } catch (e) {
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
                    
                    String _getLastMessagePreview(Conversation conv) {
                      final lastMessage = conv.lastMessage;
                      if (lastMessage == null) return 'Chưa có tin nhắn';
                      if (lastMessage.isDeleted) return 'Tin nhắn đã bị xóa';
                      if (lastMessage.messageType == 'IMAGE') return '📷 Đã gửi một hình ảnh';
                      if (lastMessage.messageType == 'FILE') return '📎 Đã gửi một tệp';
                      if (lastMessage.messageType == 'AUDIO') return '🎤 Đã gửi một tin nhắn thoại';
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
                        trailing: unreadCount > 0
                            ? Container(
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
                              )
                            : null,
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
                            _loadDirectConversations();
                            _viewModel.refresh();
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
                  
                  // Load more indicator
                  if (currentIndex == viewModel.groups.length) {
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

  const _GroupListItem({
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = (group.unreadCount ?? 0) > 0;

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
        trailing: hasUnread
            ? Container(
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
              )
            : null,
        onTap: onTap,
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


