import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/chat/invitation.dart';
import '../models/chat/direct_invitation.dart';
import '../core/event_bus.dart';
import 'chat_service.dart';
import 'direct_chat_screen.dart';
import 'package:flutter/widgets.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  final ChatService _service = ChatService();
  List<GroupInvitationResponse> _groupInvitations = [];
  List<DirectInvitation> _directInvitations = [];
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

    print('📋 [InvitationsScreen] ========== _loadInvitations START ==========');
    
    List<GroupInvitationResponse> groupInvitations = [];
    List<DirectInvitation> directInvitations = [];
    List<String> errors = [];

    // Load group invitations independently
    try {
      print('📋 [InvitationsScreen] Loading group invitations...');
      groupInvitations = await _service.getMyPendingInvitations();
      print('✅ [InvitationsScreen] Loaded ${groupInvitations.length} group invitations');
    } catch (e, stackTrace) {
      print('❌ [InvitationsScreen] Error loading group invitations: $e');
      print('❌ [InvitationsScreen] Stack trace: $stackTrace');
      errors.add('Lỗi khi tải lời mời nhóm: ${e.toString()}');
    }

    // Load direct invitations independently
    try {
      print('📋 [InvitationsScreen] Loading direct invitations...');
      directInvitations = await _service.getPendingDirectInvitations();
      print('✅ [InvitationsScreen] Loaded ${directInvitations.length} direct invitations');
      
      // Filter only PENDING invitations
      directInvitations = directInvitations.where((inv) => inv.status == 'PENDING').toList();
      print('✅ [InvitationsScreen] Filtered to ${directInvitations.length} PENDING direct invitations');
    } catch (e, stackTrace) {
      print('❌ [InvitationsScreen] Error loading direct invitations: $e');
      print('❌ [InvitationsScreen] Stack trace: $stackTrace');
      errors.add('Lỗi khi tải lời mời trực tiếp: ${e.toString()}');
    }

    final totalCount = groupInvitations.length + directInvitations.length;
    print('📋 [InvitationsScreen] Total invitations loaded: $totalCount (${groupInvitations.length} group + ${directInvitations.length} direct)');
    
    if (errors.isNotEmpty && totalCount == 0) {
      // Only show error if we have no invitations at all
      print('⚠️ [InvitationsScreen] Errors occurred and no invitations loaded');
    } else if (errors.isNotEmpty) {
      // Show warning but still display what we have
      print('⚠️ [InvitationsScreen] Some errors occurred but ${totalCount} invitations loaded');
    }
    
    setState(() {
      _groupInvitations = groupInvitations;
      _directInvitations = directInvitations;
      _isLoading = false;
      // Only set error if we have no invitations AND there were errors
      if (errors.isNotEmpty && totalCount == 0) {
        _error = errors.join('\n');
      } else {
        _error = null;
      }
    });
    
    print('📋 [InvitationsScreen] ========== _loadInvitations END ==========');
  }

  Future<void> _acceptGroupInvitation(GroupInvitationResponse invitation) async {
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

  Future<void> _declineGroupInvitation(GroupInvitationResponse invitation) async {
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

  Future<void> _acceptDirectInvitation(DirectInvitation invitation) async {
    try {
      print('📤 [InvitationsScreen] Accepting direct invitation: ${invitation.id}');
      
      final acceptedInvitation = await _service.acceptDirectInvitation(invitation.id);
      
      print('✅ [InvitationsScreen] Direct invitation accepted');
      print('   Conversation ID: ${acceptedInvitation.conversationId}');
      
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
      print('❌ [InvitationsScreen] Error accepting direct invitation: $e');
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

  Future<void> _declineDirectInvitation(DirectInvitation invitation) async {
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
    final totalCount = _groupInvitations.length + _directInvitations.length;
    
    print('📋 [InvitationsScreen] ========== build() called ==========');
    print('📋 [InvitationsScreen]   _groupInvitations.length: ${_groupInvitations.length}');
    print('📋 [InvitationsScreen]   _directInvitations.length: ${_directInvitations.length}');
    print('📋 [InvitationsScreen]   totalCount: $totalCount');
    print('📋 [InvitationsScreen]   _isLoading: $_isLoading');
    print('📋 [InvitationsScreen]   _error: $_error');
    
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
            : _error != null && totalCount == 0
                ? SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.of(context).size.height - 
                                  MediaQuery.of(context).padding.top - 
                                  kToolbarHeight,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
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
                        ),
                      ),
                    ),
                  )
                : totalCount == 0
                    ? SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: MediaQuery.of(context).size.height - 
                                      MediaQuery.of(context).padding.top - 
                                      kToolbarHeight,
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.mail,
                                    size: 64,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Không có lời mời nào',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Các lời mời trò chuyện sẽ hiển thị ở đây',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.errorContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            CupertinoIcons.info,
                                            color: theme.colorScheme.onErrorContainer,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _error!,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onErrorContainer,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          // Show error banner if there's a partial error but we have some invitations
                          if (_error != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              color: theme.colorScheme.errorContainer,
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.exclamationmark_triangle,
                                    color: theme.colorScheme.onErrorContainer,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(CupertinoIcons.xmark, size: 18),
                                    color: theme.colorScheme.onErrorContainer,
                                    onPressed: () {
                                      setState(() {
                                        _error = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: totalCount + 
                                  (_groupInvitations.isNotEmpty ? 1 : 0) + // Group header
                                  (_directInvitations.isNotEmpty ? 1 : 0), // Direct header
                        itemBuilder: (context, index) {
                          int currentIndex = index;
                          
                          // Group invitations section header
                          if (_groupInvitations.isNotEmpty && currentIndex == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Lời mời tham gia nhóm',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            );
                          }
                          if (_groupInvitations.isNotEmpty) {
                            currentIndex--;
                          }
                          
                          // Group invitations
                          if (currentIndex < _groupInvitations.length) {
                            final invitation = _groupInvitations[currentIndex];
                            return TweenAnimationBuilder<double>(
                              duration: Duration(milliseconds: 300 + (currentIndex * 50)),
                              tween: Tween(begin: 0.0, end: 1.0),
                              curve: Curves.easeOut,
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Transform.translate(
                                    offset: Offset(0, 20 * (1 - value)),
                                    child: child,
                                  ),
                                );
                              },
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                                    width: 1,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: null,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Icon - fixed size để layout không nhảy
                                        Container(
                                          height: 56,
                                          width: 56,
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primaryContainer,
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: Icon(
                                            CupertinoIcons.group,
                                            color: theme.colorScheme.onPrimaryContainer,
                                            size: 28,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Content section - Expanded để chiếm không gian còn lại, đảm bảo không overflow
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Dòng 1: Tên nhóm - wrap text, max 2 dòng, ưu tiên xuống dòng
                                              Text(
                                                invitation.groupName ?? 'Nhóm chat',
                                                style: theme.textTheme.titleLarge?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 17,
                                                  letterSpacing: -0.2,
                                                  height: 1.4,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: true,
                                              ),
                                              const SizedBox(height: 12),
                                              // Dòng 2: Tên người gửi - format cố định, label trên, tên dưới, wrap đầy đủ
                                              if (invitation.inviterName != null) ...[
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Người gửi:',
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w500,
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      invitation.inviterName!,
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w600,
                                                        height: 1.5,
                                                      ),
                                                      maxLines: 3,
                                                      softWrap: true,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                              ],
                                              // Don't show expiration date - group invitations don't expire
                                              // Removed expiration display section
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Action buttons - vertical layout, fixed width để không nhảy
                                        SizedBox(
                                          width: 90,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              FilledButton(
                                                onPressed: () => _acceptGroupInvitation(invitation),
                                                style: FilledButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                                  minimumSize: const Size(0, 40),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'Chấp nhận',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              OutlinedButton(
                                                onPressed: () => _declineGroupInvitation(invitation),
                                                style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                                  minimumSize: const Size(0, 40),
                                                  side: BorderSide(
                                                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                child: Text(
                                                  'Từ chối',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          
                          // Adjust index after group invitations
                          currentIndex -= _groupInvitations.length;
                          
                          // Direct invitations section header
                          if (_directInvitations.isNotEmpty && currentIndex == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 12),
                              child: Text(
                                'Lời mời trò chuyện trực tiếp',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                            );
                          }
                          if (_directInvitations.isNotEmpty) {
                            currentIndex--;
                          }
                          
                          // Direct invitations
                          final directIndex = currentIndex;
                          final invitation = _directInvitations[directIndex];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
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
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                                        onPressed: () => _declineDirectInvitation(invitation),
                                        child: const Text('Từ chối'),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () => _acceptDirectInvitation(invitation),
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
                        ],
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



