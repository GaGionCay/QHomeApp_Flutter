import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/chat/friend.dart';
import 'chat_service.dart';
import 'direct_chat_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final ChatService _service = ChatService();
  List<Friend> _friends = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final friends = await _service.getFriends();
      if (mounted) {
        setState(() {
          _friends = friends;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Lỗi khi tải danh sách bạn bè: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _navigateToChat(Friend friend) async {
    if (friend.hasActiveConversation && friend.conversationId != null) {
      // Navigate to existing conversation
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DirectChatScreen(
              conversationId: friend.conversationId!,
              otherParticipantName: friend.friendName,
            ),
          ),
        );
      }
    } else {
      // Create new invitation to start conversation
      try {
        final invitation = await _service.createDirectInvitation(
          inviteeId: friend.friendId,
          initialMessage: null,
        );
        if (mounted) {
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
        }
      } catch (e) {
        if (mounted) {
          print('❌ [FriendsScreen] Error creating invitation: $e');
          
          // Extract error message - remove "Exception: " prefix if present
          String errorMessage = e.toString().replaceFirst('Exception: ', '');
          print('   📋 Extracted error message: $errorMessage');
          
          // Check if this is an informational message (not an error)
          bool isInfoMessage = errorMessage.contains('Bạn đã gửi lời mời rồi') || 
                               errorMessage.contains('đã gửi lời mời cho bạn rồi') ||
                               errorMessage.contains('Vui lòng đợi phản hồi');
          
          print('   📋 Is info message: $isInfoMessage');
          
          // If error message already contains the full message, use it directly
          // Otherwise, prepend "Lỗi khi gửi lời mời: "
          if (!errorMessage.startsWith('Lỗi khi') && !errorMessage.contains('đã gửi lời mời')) {
            errorMessage = 'Lỗi khi gửi lời mời: $errorMessage';
          }
          
          print('   🚀 Showing SnackBar with message: $errorMessage');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: isInfoMessage ? Colors.orange : Colors.red,
              duration: Duration(seconds: isInfoMessage ? 5 : 4),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bạn bè'),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.refresh),
            onPressed: _loadFriends,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadFriends,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _friends.isEmpty
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
                          onPressed: _loadFriends,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  )
                : _friends.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.person_2,
                              size: 64,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Chưa có bạn bè nào',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Chấp nhận lời mời chat để thêm bạn bè',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _friends.length,
                        itemBuilder: (context, index) {
                          final friend = _friends[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Text(
                                friend.friendName.isNotEmpty
                                    ? friend.friendName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(friend.friendName),
                            subtitle: friend.friendPhone.isNotEmpty
                                ? Text(friend.friendPhone)
                                : null,
                            trailing: friend.hasActiveConversation
                                ? Icon(
                                    CupertinoIcons.chat_bubble_2,
                                    color: theme.colorScheme.primary,
                                  )
                                : Icon(
                                    CupertinoIcons.chat_bubble,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  ),
                            onTap: () => _navigateToChat(friend),
                          );
                        },
                      ),
      ),
    );
  }
}



