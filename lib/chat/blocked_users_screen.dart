import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import '../core/event_bus.dart';
import 'chat_service.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final ChatService _chatService = ChatService();
  final ApiClient _apiClient = ApiClient();
  
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final blockedUserIds = await _chatService.getBlockedUsers();
      
      // Fetch user info for each blocked user
      final List<Map<String, dynamic>> users = [];
      for (final userId in blockedUserIds) {
        try {
          // Get resident info by userId
          final response = await _apiClient.dio.get('/residents/by-user/$userId');
          final residentInfo = response.data as Map<String, dynamic>?;
          
          if (residentInfo != null) {
            users.add({
              'userId': userId,
              'name': residentInfo['name'] ?? residentInfo['fullName'] ?? 'Người dùng',
              'avatar': residentInfo['avatar'],
              'residentId': residentInfo['id']?.toString(),
            });
          } else {
            // Add with minimal info if profile fetch fails
            users.add({
              'userId': userId,
              'name': 'Người dùng',
              'avatar': null,
              'residentId': null,
            });
          }
        } catch (e) {
          print('⚠️ [BlockedUsersScreen] Error loading user info for $userId: $e');
          // Add with minimal info if profile fetch fails
          users.add({
            'userId': userId,
            'name': 'Người dùng',
            'avatar': null,
            'residentId': null,
          });
        }
      }

      if (mounted) {
        setState(() {
          _blockedUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ [BlockedUsersScreen] Error loading blocked users: $e');
      if (mounted) {
        setState(() {
          _error = 'Lỗi khi tải danh sách người dùng đã chặn: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _unblockUser(String userId, String userName) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gỡ chặn'),
        content: Text('Bạn có chắc chắn muốn gỡ chặn $userName không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gỡ chặn'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đang gỡ chặn...')),
        );
      }

      await _chatService.unblockUser(userId);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã gỡ chặn $userName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Reload blocked users list
        await _loadBlockedUsers();
        
        // Emit event to refresh marketplace and other screens
        AppEventBus().emit('blocked_users_updated');
      }
    } catch (e) {
      print('❌ [BlockedUsersScreen] Error unblocking user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi gỡ chặn: ${e.toString()}'),
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
        title: const Text('Người dùng đã chặn'),
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
                        onPressed: _loadBlockedUsers,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : _blockedUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.person_crop_circle_badge_xmark,
                            size: 64,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Chưa có người dùng nào bị chặn',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadBlockedUsers,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _blockedUsers.length,
                        itemBuilder: (context, index) {
                          final user = _blockedUsers[index];
                          final userName = user['name'] as String;
                          final userId = user['userId'] as String;
                          final avatar = user['avatar'] as String?;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: avatar != null && avatar.isNotEmpty
                                    ? NetworkImage(avatar)
                                    : null,
                                child: avatar == null || avatar.isEmpty
                                    ? const Icon(CupertinoIcons.person_fill)
                                    : null,
                              ),
                              title: Text(userName),
                              subtitle: const Text('Đã bị chặn'),
                              trailing: FilledButton(
                                onPressed: () => _unblockUser(userId, userName),
                                child: const Text('Gỡ chặn'),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

