import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/chat/invitation.dart';
import '../core/event_bus.dart';
import 'chat_service.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  final ChatService _service = ChatService();
  List<GroupInvitationResponse> _invitations = [];
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
      final invitations = await _service.getMyPendingInvitations();
      setState(() {
        _invitations = invitations;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Lỗi khi tải lời mời: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptInvitation(GroupInvitationResponse invitation) async {
    try {
      await _service.acceptInvitation(invitation.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã chấp nhận lời mời'),
            backgroundColor: Colors.green,
          ),
        );
        _loadInvitations();
        // Emit event to update badge on HomeScreen
        AppEventBus().emit('chat_activity_updated');
      }
    } catch (e) {
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

  Future<void> _declineInvitation(GroupInvitationResponse invitation) async {
    try {
      await _service.declineInvitation(invitation.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã từ chối lời mời'),
          ),
        );
        _loadInvitations();
        // Emit event to update badge on HomeScreen
        AppEventBus().emit('chat_activity_updated');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lời mời tham gia nhóm'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
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
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadInvitations,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _invitations.length,
                        itemBuilder: (context, index) {
                          final invitation = _invitations[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              title: Text(
                                invitation.groupName ?? 'Nhóm chat',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  if (invitation.inviterName != null)
                                    Text(
                                      '${invitation.inviterName} mời bạn tham gia',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Hết hạn: ${_formatDate(invitation.expiresAt)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => _declineInvitation(invitation),
                                    child: const Text('Từ chối'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () => _acceptInvitation(invitation),
                                    child: const Text('Chấp nhận'),
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now);

    if (diff.inDays < 0) {
      return 'Đã hết hạn';
    }
    if (diff.inDays == 0) {
      return 'Hôm nay';
    }
    if (diff.inDays == 1) {
      return 'Ngày mai';
    }
    return '${diff.inDays} ngày nữa';
  }
}

