import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/chat/direct_invitation.dart';
import '../core/event_bus.dart';
import 'chat_service.dart';
import 'direct_chat_screen.dart';

class DirectInvitationsScreen extends StatefulWidget {
  const DirectInvitationsScreen({super.key});

  @override
  State<DirectInvitationsScreen> createState() => _DirectInvitationsScreenState();
}

class _DirectInvitationsScreenState extends State<DirectInvitationsScreen> {
  final ChatService _service = ChatService();
  List<DirectInvitation> _invitations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvitations();
  }

  Future<void> _loadInvitations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print('📤 [DirectInvitationsScreen] Loading pending invitations...');
      final invitations = await _service.getPendingDirectInvitations();
      print('✅ [DirectInvitationsScreen] Loaded ${invitations.length} invitations');
      for (var inv in invitations) {
        print('   - Invitation ID: ${inv.id}, Inviter: ${inv.inviterId}, Invitee: ${inv.inviteeId}, Status: ${inv.status}');
      }
      if (mounted) {
        setState(() {
          _invitations = invitations;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ [DirectInvitationsScreen] Error loading invitations: $e');
      if (mounted) {
        setState(() {
          _error = 'Lỗi khi tải lời mời: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _acceptInvitation(DirectInvitation invitation) async {
    try {
      print('📤 [DirectInvitationsScreen] Accepting invitation: ${invitation.id}');
      
      final acceptedInvitation = await _service.acceptDirectInvitation(invitation.id);
      
      print('✅ [DirectInvitationsScreen] Invitation accepted');
      print('   Conversation ID: ${acceptedInvitation.conversationId}');
      print('   Status: ${acceptedInvitation.status}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã chấp nhận lời mời'),
            backgroundColor: Colors.green,
          ),
        );
        _loadInvitations();
        // Emit event to update badge
        AppEventBus().emit('direct_chat_activity_updated');
        
        // Wait a bit to ensure backend has updated conversation status
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Navigate to chat screen
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DirectChatScreen(
                conversationId: acceptedInvitation.conversationId,
                otherParticipantName: invitation.inviterName ?? 'Người dùng',
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [DirectInvitationsScreen] Error accepting invitation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi chấp nhận: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _declineInvitation(DirectInvitation invitation) async {
    try {
      await _service.declineDirectInvitation(invitation.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã từ chối lời mời'),
          ),
        );
        _loadInvitations();
        // Emit event to update badge
        AppEventBus().emit('direct_chat_activity_updated');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi từ chối: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return 'Hôm nay';
    } else if (difference.inDays == 1) {
      return 'Hôm qua';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Lời mời trò chuyện'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadInvitations,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _invitations.isEmpty
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
                          onPressed: _loadInvitations,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  )
                : _invitations.isEmpty
                    ? Center(
                        // Always show screen even when empty (like group invitations)
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.mail,
                              size: 64,
                              color: theme.colorScheme.onSurface.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Không có lời mời nào',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Các lời mời trò chuyện sẽ hiển thị ở đây',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _invitations.length,
                        itemBuilder: (context, index) {
                          final invitation = _invitations[index];
                          // Only show PENDING invitations
                          if (invitation.status != 'PENDING') {
                            return const SizedBox.shrink();
                          }
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: theme.colorScheme.primaryContainer,
                                        child: Text(
                                          (invitation.inviterName ?? 'U')[0].toUpperCase(),
                                          style: TextStyle(
                                            color: theme.colorScheme.onPrimaryContainer,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              invitation.inviterName ?? 'Người dùng',
                                              style: theme.textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              _formatTime(invitation.createdAt),
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (invitation.initialMessage != null &&
                                      invitation.initialMessage!.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        invitation.initialMessage!,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: () => _declineInvitation(invitation),
                                        child: const Text('Từ chối'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () => _acceptInvitation(invitation),
                                        child: const Text('Chấp nhận'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

