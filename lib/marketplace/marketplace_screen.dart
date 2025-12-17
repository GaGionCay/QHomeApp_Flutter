// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../auth/token_storage.dart';
import 'marketplace_view_model.dart';
import 'marketplace_service.dart';
import '../models/marketplace_post.dart';
import '../models/marketplace_category.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import 'image_viewer_screen.dart';
import 'video_preview_widget.dart';
import 'video_viewer_screen.dart';
import '../chat/chat_service.dart';
import '../chat/group_list_screen.dart';
import '../chat/group_list_screen.dart';
import '../chat/direct_chat_screen.dart';
import '../models/chat/group.dart';
import '../models/chat/friend.dart';
import '../auth/api_client.dart';
import '../core/event_bus.dart';
import 'select_group_dialog.dart';
import 'create_group_dialog.dart';
import 'package:flutter/services.dart';
import '../widgets/animations/smooth_animations.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> with WidgetsBindingObserver {
  late final MarketplaceViewModel _viewModel;
  final ScrollController _scrollController = ScrollController();
  final TokenStorage _tokenStorage = TokenStorage();
  final ChatService _chatService = ChatService();
  String? _currentResidentId;
  Set<String> _blockedUserIds = {}; // Cache blocked user IDs
  final Map<String, String> _residentIdToUserIdCache = {}; // Cache residentId -> userId mapping
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final service = MarketplaceService();
    final storage = TokenStorage();
    _viewModel = MarketplaceViewModel(service, storage);
    _viewModel.initialize();
    _scrollController.addListener(_onScroll);
    _loadCurrentUser();
    _loadBlockedUsers();
    _setupBlockedUsersListener();
    
    // Ensure listener is setup for realtime updates
    // This is already done in initialize(), but we ensure it's set up here too
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Reload posts when app resumes to get latest comment counts
    if (state == AppLifecycleState.resumed && _hasInitialized) {
      // Ensure listener is still active when app resumes
      _viewModel.setupRealtimeUpdates();
      _viewModel.refresh();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Mark as initialized on first call
    if (!_hasInitialized) {
      _hasInitialized = true;
    }
    // Note: We don't refresh here to avoid unnecessary API calls
    // Comment count will be updated via POST_STATS_UPDATE events
  }

  Future<void> _loadCurrentUser() async {
    _currentResidentId = await _tokenStorage.readResidentId();
    if (mounted) setState(() {});
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final blockedUserIds = await _chatService.getBlockedUsers();
      if (mounted) {
        setState(() {
          _blockedUserIds = blockedUserIds.toSet();
        });
      }
    } catch (e) {
      print('⚠️ [MarketplaceScreen] Error loading blocked users: $e');
    }
  }

  void _setupBlockedUsersListener() {
    AppEventBus().on('blocked_users_updated', (_) async {
      print('🔄 [MarketplaceScreen] blocked_users_updated event received, reloading blocked users...');
      await _loadBlockedUsers();
      // Refresh posts to show/hide posts from unblocked users
      // setState will trigger rebuild and re-filter posts based on updated _blockedUserIds
      if (mounted) {
        setState(() {
          // Trigger rebuild to refresh filtered posts
          print('✅ [MarketplaceScreen] Blocked users reloaded, refreshing UI. Blocked count: ${_blockedUserIds.length}');
        });
      }
    });
  }

  Future<void> _showUserOptions(BuildContext context, MarketplacePost post) async {
    // Don't show options if user is viewing their own post
    if (_currentResidentId != null && post.residentId == _currentResidentId) {
      return;
    }

    // Get author userId from residentId (check cache first)
    String? authorUserId = post.author?.userId ?? _residentIdToUserIdCache[post.residentId];
    
    if (authorUserId == null) {
      try {
        final apiClient = ApiClient();
        final response = await apiClient.dio.get('/residents/${post.residentId}');
        authorUserId = response.data['userId']?.toString();
        
        // Cache it for future use
        if (authorUserId != null) {
          _residentIdToUserIdCache[post.residentId] = authorUserId;
        }
      } catch (e) {
        print('⚠️ [MarketplaceScreen] Error getting userId: $e');
      }
    }

    // Check if user is blocked
    final isBlocked = authorUserId != null && _blockedUserIds.contains(authorUserId);
    
    // If blocked, show message that user is not found
    if (isBlocked) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không tìm thấy người dùng'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Check if already friends
    Friend? friend;
    try {
      final friends = await _chatService.getFriends();
      friend = friends.firstWhere(
        (f) => f.friendId == post.residentId,
        orElse: () => Friend(
          friendId: '',
          friendName: '',
          friendPhone: '',
          hasActiveConversation: false,
        ),
      );
    } catch (e) {
      print('⚠️ [MarketplaceScreen] Error getting friends: $e');
    }

    final hasActiveConversation = friend != null && 
                                   friend.friendId == post.residentId && 
                                   friend.hasActiveConversation && 
                                   friend.conversationId != null;

    // Show options menu
    final result = await showSmoothBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.chat_bubble),
              title: Text(hasActiveConversation ? 'Mở chat' : 'Gửi tin nhắn'),
              onTap: () => Navigator.pop(context, hasActiveConversation ? 'open_chat' : 'message'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.group),
              title: const Text('Mời vào nhóm'),
              onTap: () => Navigator.pop(context, 'invite_group'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.person_crop_circle_badge_xmark, color: Colors.red),
              title: const Text('Chặn người dùng'),
              onTap: () => Navigator.pop(context, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'open_chat' && context.mounted && friend != null && friend.conversationId != null) {
      // Navigate directly to direct chat if already friends
      Navigator.push(
        context,
        SmoothPageRoute(
          page: DirectChatScreen(
            conversationId: friend.conversationId!,
            otherParticipantName: friend.friendName.isNotEmpty ? friend.friendName : (post.author?.name ?? 'Người dùng'),
          ),
        ),
      );
    } else if (result == 'message' && context.mounted) {
      await _showDirectChatPopup(context, post);
    } else if (result == 'invite_group' && context.mounted) {
      await _inviteToGroup(context, post);
    } else if (result == 'block' && context.mounted && authorUserId != null) {
      await _blockUser(context, authorUserId, post.author?.name ?? 'Người dùng');
    }
  }

  Future<void> _showDirectChatPopup(BuildContext context, MarketplacePost post) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Trò chuyện'),
        content: Text(
          'Bạn có muốn gửi tin nhắn trực tiếp cho ${post.author?.name ?? 'cư dân này'} không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi tin nhắn'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      try {
        // Show loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đang tạo lời mời...')),
        );

        // Create direct invitation
        await _chatService.createDirectInvitation(
          inviteeId: post.residentId,
          initialMessage: null,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã gửi lời mời trò chuyện'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          // Extract error message - remove "Exception: " prefix if present
          String errorMessage = e.toString().replaceFirst('Exception: ', '');
          
          // Check if this is an informational message (not an error)
          bool isInfoMessage = errorMessage.contains('Bạn đã gửi lời mời rồi') || 
                               errorMessage.contains('đã gửi lời mời cho bạn rồi');
          
          // If error message already contains the full message, use it directly
          if (!errorMessage.startsWith('Lỗi') && !errorMessage.contains('đã gửi lời mời')) {
            errorMessage = 'Lỗi: $errorMessage';
          }
          
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

  Future<void> _inviteToGroup(BuildContext context, MarketplacePost post) async {
    try {
      // Get phone number from residentId first
      String? phoneNumber;
      try {
        final apiClient = ApiClient();
        final response = await apiClient.dio.get('/residents/${post.residentId}');
        phoneNumber = response.data['phone']?.toString();
      } catch (e) {
        print('⚠️ [MarketplaceScreen] Error getting phone number: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể lấy số điện thoại của người dùng'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      if (phoneNumber == null || phoneNumber.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Người dùng này chưa có số điện thoại'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // Get user's groups
      final groupsResponse = await _chatService.getMyGroups(page: 0, size: 100);
      List<ChatGroup> groups = groupsResponse.content;
      
      // Load full group data with members for each group to check membership
      final groupsWithMembers = <ChatGroup>[];
      for (var group in groups) {
        try {
          final fullGroup = await _chatService.getGroupById(group.id);
          groupsWithMembers.add(fullGroup);
        } catch (e) {
          print('⚠️ [MarketplaceScreen] Error loading group ${group.id}: $e');
          // Add original group if loading fails
          groupsWithMembers.add(group);
        }
      }
      groups = groupsWithMembers;
      
      ChatGroup? selectedGroup;
      
      if (groups.isEmpty) {
        // No groups, create a new one
        final groupData = await showDialog<Map<String, String?>>(
          context: context,
          builder: (context) => CreateGroupDialog(
            defaultName: 'Nhóm với ${post.author?.name ?? 'người dùng'}',
          ),
        );
        
        if (groupData == null || !context.mounted) {
          return;
        }
        
        // Show loading
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đang tạo nhóm...')),
          );
        }
        
        // Create new group
        try {
          selectedGroup = await _chatService.createGroup(
            name: groupData['name']!,
            description: groupData['description'],
          );
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đang gửi lời mời...')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lỗi khi tạo nhóm: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } else {
        // Show group selection dialog with target and current resident IDs
        final result = await showDialog<dynamic>(
          context: context,
          builder: (context) => SelectGroupDialog(
            groups: groups,
            targetResidentId: post.residentId,
            currentResidentId: _currentResidentId,
          ),
        );
        
        if (result == null || !context.mounted) {
          return;
        }
        
        if (result == 'create_new') {
          // User wants to create a new group
          final groupData = await showDialog<Map<String, String?>>(
            context: context,
            builder: (context) => CreateGroupDialog(
              defaultName: 'Nhóm với ${post.author?.name ?? 'người dùng'}',
            ),
          );
          
          if (groupData == null || !context.mounted) {
            return;
          }
          
          // Show loading
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đang tạo nhóm...')),
            );
          }
          
          // Create new group
          try {
            selectedGroup = await _chatService.createGroup(
              name: groupData['name']!,
              description: groupData['description'],
            );
            
            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đang gửi lời mời...')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Lỗi khi tạo nhóm: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        } else if (result is ChatGroup) {
          selectedGroup = result;
          
          // Show loading
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đang gửi lời mời...')),
            );
          }
        } else {
          return;
        }
      }
      
      // Check if target user is already in the group
      // Refresh group data to get full members list
      try {
        final fullGroupData = await _chatService.getGroupById(selectedGroup.id);
        final targetUserInGroup = fullGroupData.members != null &&
            fullGroupData.members!.any(
              (member) => member.residentId == post.residentId,
            );
        
        if (targetUserInGroup) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Người dùng đã ở trong nhóm "${selectedGroup.name}"'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      } catch (e) {
        print('⚠️ [MarketplaceScreen] Error checking group members: $e');
        // Continue with invite if check fails
      }
      
      // Invite to group
      print('📨 [MarketplaceScreen] Inviting user to group - groupId: ${selectedGroup.id}, phoneNumber: $phoneNumber, targetResidentId: ${post.residentId}');
      final inviteResult = await _chatService.inviteMembersByPhone(
        groupId: selectedGroup.id,
        phoneNumbers: [phoneNumber],
      );
      
      print('📨 [MarketplaceScreen] Invite result - successful: ${inviteResult.successfulInvitations?.length ?? 0}, invalid: ${inviteResult.invalidPhones?.length ?? 0}, skipped: ${inviteResult.skippedPhones?.length ?? 0}');
      if (inviteResult.successfulInvitations != null && inviteResult.successfulInvitations!.isNotEmpty) {
        for (var inv in inviteResult.successfulInvitations!) {
          print('📨 [MarketplaceScreen]   Successful invitation - ID: ${inv.id}, InviteeResidentId: ${inv.inviteeResidentId}, InviteePhone: ${inv.inviteePhone}');
        }
      }
      if (inviteResult.invalidPhones != null && inviteResult.invalidPhones!.isNotEmpty) {
        print('📨 [MarketplaceScreen]   Invalid phones: ${inviteResult.invalidPhones}');
      }
      if (inviteResult.skippedPhones != null && inviteResult.skippedPhones!.isNotEmpty) {
        print('📨 [MarketplaceScreen]   Skipped phones: ${inviteResult.skippedPhones}');
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (inviteResult.successfulInvitations != null && inviteResult.successfulInvitations!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã gửi lời mời vào nhóm "${selectedGroup.name}"'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Không thể gửi lời mời: ${inviteResult.invalidPhones?.join(", ") ?? inviteResult.skippedPhones?.join(", ") ?? "Lỗi không xác định"}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // Extract error message - remove "Exception: " prefix if present
        String errorMessage = e.toString().replaceFirst('Exception: ', '');
        
        // Check if this is an informational message (not an error)
        bool isInfoMessage = errorMessage.contains('Bạn đã gửi lời mời rồi') || 
                             errorMessage.contains('đã gửi lời mời cho bạn rồi');
        
        // If error message already contains the full message, use it directly
        if (!errorMessage.startsWith('Lỗi') && !errorMessage.contains('đã gửi lời mời')) {
          errorMessage = 'Lỗi: $errorMessage';
        }
        
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

  Future<void> _blockUser(BuildContext context, String userId, String userName) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chặn người dùng'),
        content: Text('Bạn có chắc chắn muốn chặn $userName không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Chặn'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Show loading
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đang chặn...')),
        );
      }

      await _chatService.blockUser(userId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Đã chặn $userName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // Reload blocked users list
        await _loadBlockedUsers();
        
        // Emit event to refresh marketplace
        AppEventBus().emit('blocked_users_updated');
      }
    } catch (e) {
      print('❌ [MarketplaceScreen] Error blocking user: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi chặn: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showShareBottomSheet(BuildContext context, MarketplacePost post) async {
    final theme = Theme.of(context);
    final deepLink = 'app://marketplace/post/${post.id}';
    
    showSmoothBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(
                CupertinoIcons.link,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Sao chép liên kết'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: deepLink));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã sao chép liên kết'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                CupertinoIcons.chat_bubble_2,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Chia sẻ vào chat'),
              onTap: () {
                Navigator.pop(context);
                _navigateToChatSelection(context, post);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToChatSelection(BuildContext context, MarketplacePost post) async {
    final theme = Theme.of(context);
    
    showSmoothBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(
                CupertinoIcons.group_solid,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Chia sẻ vào nhóm chat'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  SmoothPageRoute(
                    page: GroupListScreen(sharePost: post),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                CupertinoIcons.person_2,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Chia sẻ vào tin nhắn riêng'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  SmoothPageRoute(
                    page: GroupListScreen(sharePost: post),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _viewModel.dispose();
    AppEventBus().off('blocked_users_updated');
    super.dispose();
  }

  void _onScroll() {
    // Load more when user scrolls to 80% of the list
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_viewModel.isLoadingMore && _viewModel.hasMore) {
        _viewModel.loadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Use ChangeNotifierProvider.value - it should work with notifyListeners()
    // But ensure Consumer rebuilds by using listen: true explicitly
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Chợ cư dân'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            // Đăng bài button
            IconButton(
              icon: Icon(
                CupertinoIcons.add_circled,
                color: theme.colorScheme.primary,
              ),
              onPressed: () async {
                final result = await Navigator.push<MarketplacePost>(
                  context,
                  SmoothPageRoute(
                    page: const CreatePostScreen(),
                  ),
                );
                
                // Refresh posts if a new post was created
                if (result != null && mounted) {
                  _viewModel.refresh();
                }
              },
              tooltip: 'Đăng bài',
            ),
            // Filter button
            Consumer<MarketplaceViewModel>(
              builder: (context, viewModel, child) {
                return IconButton(
                  icon: Stack(
                    children: [
                      Icon(
                        CupertinoIcons.slider_horizontal_3,
                        color: theme.colorScheme.onSurface,
                      ),
                      // Badge to show active filters
                      if (viewModel.selectedCategory != null || viewModel.sortBy != null)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () => _showFilterBottomSheet(context, viewModel),
                  tooltip: 'Bộ lọc',
                );
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(96), // Increased for filter badges
            child: Column(
              children: [
                Consumer<MarketplaceViewModel>(
                  builder: (context, viewModel, child) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Building của tôi'),
                            icon: Icon(CupertinoIcons.building_2_fill, size: 16),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Tất cả'),
                            icon: Icon(CupertinoIcons.globe, size: 16),
                          ),
                        ],
                        selected: {viewModel.showAllBuildings},
                        onSelectionChanged: (Set<bool> selected) {
                          if (selected.isNotEmpty) {
                            viewModel.setShowAllBuildings(selected.first);
                          }
                        },
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    );
                  },
                ),
                // Filter badges
                Consumer<MarketplaceViewModel>(
                  builder: (context, viewModel, child) {
                    if (viewModel.selectedCategory == null && viewModel.sortBy == null) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (viewModel.selectedCategory != null)
                            _buildFilterChip(
                              context,
                              theme,
                              _getCategoryName(viewModel.selectedCategory!, viewModel.categories),
                              () => viewModel.setCategoryFilter(null),
                            ),
                          if (viewModel.sortBy != null)
                            _buildFilterChip(
                              context,
                              theme,
                              _getSortByLabel(viewModel.sortBy!),
                              () => viewModel.setSortBy(null),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        body: Selector<MarketplaceViewModel, List<MarketplacePost>>(
          selector: (context, viewModel) => viewModel.posts,
          shouldRebuild: (previous, next) {
            // Always rebuild when posts list changes
            // This ensures UI updates when commentCount changes
            if (previous.length != next.length) {
              return true;
            }
            
            // Check if any post's commentCount or viewCount changed
            // Since we create a new list instance in MarketplaceViewModel, 
            // Selector should detect the change, but we also check content
            for (int i = 0; i < previous.length && i < next.length; i++) {
              if (previous[i].id == next[i].id) {
                if (previous[i].commentCount != next[i].commentCount ||
                    previous[i].viewCount != next[i].viewCount) {
                  return true;
                }
              } else {
                // Post order changed or post was replaced
                return true;
              }
            }
            
            // If list reference changed (new instance), rebuild
            // This handles the case where we create a new list in MarketplaceViewModel
            if (previous != next) {
              return true;
            }
            
            return false;
          },
          builder: (context, posts, child) {
            final viewModel = Provider.of<MarketplaceViewModel>(context, listen: false);
            
            // Ensure listener is setup when Consumer rebuilds
            // This is critical to ensure listener is active when returning to screen
            // Use postFrameCallback to avoid setup during build phase
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                // setupRealtimeUpdates() will cancel existing subscription if any before creating new one
                // This ensures we always have exactly one active listener
                viewModel.setupRealtimeUpdates();
              }
            });
            
            if (viewModel.isLoading && posts.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (viewModel.error != null && posts.isEmpty) {
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
                      style: theme.textTheme.bodyLarge,
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

            if (posts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.shopping_cart,
                      size: 64,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Chưa có bài đăng nào',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () => viewModel.refresh(),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                // Use key to preserve scroll position when items are added
                key: const PageStorageKey<String>('marketplace_posts_list'),
                cacheExtent: 500, // Cache items outside viewport for smoother scrolling
                itemCount: posts.length + 
                          (viewModel.isLoadingMore ? 1 : 0) + 
                          (!viewModel.hasMore && posts.isNotEmpty ? 1 : 0),
                itemBuilder: (context, index) {
                  // Show loading indicator at the end when loading more
                  if (index == posts.length && viewModel.isLoadingMore) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  
                  // Show "No more posts" indicator
                  if (index == posts.length && !viewModel.hasMore) {
                    return Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Text(
                          'Không còn bài viết nào nữa',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    );
                  }

                  final post = posts[index];
                  
                  // Debug log to verify post is updated
                  debugPrint('📋 [MarketplaceScreen] Building post card for post ${post.id}, commentCount: ${post.commentCount}');
                  
                  // Filter out posts from blocked users
                  String? authorUserId = post.author?.userId;
                  
                  // If userId not in author, try to get from cache or fetch
                  if (authorUserId == null && post.residentId.isNotEmpty) {
                    authorUserId = _residentIdToUserIdCache[post.residentId];
                    
                    // If not in cache, fetch it (async, but we'll skip for now and fetch later)
                    if (authorUserId == null) {
                      // Will be fetched when user clicks on author
                      // For now, show the post
                    }
                  }
                  
                  // If author is blocked, skip this post
                  if (authorUserId != null && _blockedUserIds.contains(authorUserId)) {
                    return const SizedBox.shrink();
                  }
                  
                  // Use key that includes commentCount to ensure rebuild when count changes
                  return SmoothAnimations.staggeredItem(
                    index: index,
                    child: _PostCard(
                    key: ValueKey('${post.id}_${post.commentCount}'),
                    post: post,
                    currentResidentId: _currentResidentId,
                    categories: viewModel.categories,
                    onTap: () {
                      Navigator.push(
                        context,
                          SmoothPageRoute(
                            page: ChangeNotifierProvider.value(
                            value: viewModel,
                            child: PostDetailScreen(post: post),
                          ),
                        ),
                      );
                    },
                    onAuthorTap: () => _showUserOptions(context, post),
                    onShareTap: () => _showShareBottomSheet(context, post),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _showFilterBottomSheet(BuildContext context, MarketplaceViewModel viewModel) {
    final theme = Theme.of(context);
    String? selectedCategory = viewModel.selectedCategory;
    String? selectedSortBy = viewModel.sortBy;

    showSmoothBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom,
              top: 20,
              left: 20,
              right: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Bộ lọc',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Clear all filters
                        setState(() {
                          selectedCategory = null;
                          selectedSortBy = null;
                        });
                        viewModel.setCategoryFilter(null);
                        viewModel.setSortBy(null);
                      },
                      child: const Text('Xóa tất cả'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Category Filter
                Text(
                  'Danh mục',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // "Tất cả" option
                    ChoiceChip(
                      label: const Text('Tất cả'),
                      selected: selectedCategory == null,
                      onSelected: (selected) {
                        setState(() {
                          selectedCategory = null;
                        });
                        viewModel.setCategoryFilter(null);
                      },
                    ),
                    // Category options
                    ...viewModel.categories
                        .where((cat) => cat.active)
                        .map((category) => ChoiceChip(
                              label: Text(category.name),
                              selected: selectedCategory == category.code,
                              onSelected: (selected) {
                                setState(() {
                                  selectedCategory = selected ? category.code : null;
                                });
                                viewModel.setCategoryFilter(selected ? category.code : null);
                              },
                            )),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Price Sort
                Text(
                  'Sắp xếp theo giá',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Mặc định'),
                      selected: selectedSortBy == null,
                      onSelected: (selected) {
                        setState(() {
                          selectedSortBy = null;
                        });
                        viewModel.setSortBy(null);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Giá: Thấp → Cao'),
                      selected: selectedSortBy == 'price_asc',
                      onSelected: (selected) {
                        setState(() {
                          selectedSortBy = selected ? 'price_asc' : null;
                        });
                        viewModel.setSortBy(selected ? 'price_asc' : null);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Giá: Cao → Thấp'),
                      selected: selectedSortBy == 'price_desc',
                      onSelected: (selected) {
                        setState(() {
                          selectedSortBy = selected ? 'price_desc' : null;
                        });
                        viewModel.setSortBy(selected ? 'price_desc' : null);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, ThemeData theme, String label, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label),
        onDeleted: onRemove,
        deleteIcon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
        backgroundColor: theme.colorScheme.primaryContainer,
        labelStyle: TextStyle(
          color: theme.colorScheme.onPrimaryContainer,
          fontSize: 12,
        ),
      ),
    );
  }

  String _getCategoryName(String categoryCode, List<MarketplaceCategory> categories) {
    try {
      final category = categories.firstWhere(
        (cat) => cat.code == categoryCode,
      );
      return category.name;
    } catch (e) {
      return categoryCode;
    }
  }

  String _getSortByLabel(String sortBy) {
    switch (sortBy) {
      case 'price_asc':
        return 'Giá: Thấp → Cao';
      case 'price_desc':
        return 'Giá: Cao → Thấp';
      case 'newest':
        return 'Mới nhất';
      case 'oldest':
        return 'Cũ nhất';
      default:
        return sortBy;
    }
  }
}

class _PostCard extends StatelessWidget {
  final MarketplacePost post;
  final String? currentResidentId;
  final List<MarketplaceCategory> categories;
  final VoidCallback onTap;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onShareTap;

  const _PostCard({
    super.key,
    required this.post,
    this.currentResidentId,
    required this.categories,
    required this.onTap,
    this.onAuthorTap,
    this.onShareTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header - Người đăng bài
                Row(
                  children: [
                    GestureDetector(
                      onTap: onAuthorTap,
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          CupertinoIcons.person_fill,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: onAuthorTap,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.author?.name ?? 'Người dùng',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: (currentResidentId != null && 
                                        post.residentId == currentResidentId)
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.visible,
                              softWrap: true,
                            ),
                          const SizedBox(height: 4),
                          if (post.author?.unitNumber != null || post.author?.buildingName != null)
                            Row(
                              children: [
                                Icon(
                                  CupertinoIcons.home,
                                  size: 14,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 4),
                                if (post.author?.buildingName != null) ...[
                                  Text(
                                    post.author!.buildingName!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (post.author?.unitNumber != null) ...[
                                    Text(
                                      ' - ',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ],
                                if (post.author?.unitNumber != null)
                                  Text(
                                    post.author!.unitNumber!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatDate(post.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  post.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (post.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    post.description,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // Price, Category, Location
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (post.price != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.money_dollar,
                              size: 14,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              post.priceDisplay,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (post.category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.square_grid_2x2,
                              size: 12,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getCategoryDisplayName(post),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (post.location != null && post.location!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.location,
                              size: 12,
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                post.location!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onTertiaryContainer,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                // Contact Info (if visible)
                if (post.contactInfo != null && 
                    ((post.contactInfo!.showPhone && post.contactInfo!.phone != null && post.contactInfo!.phone!.isNotEmpty) ||
                     (post.contactInfo!.showEmail && post.contactInfo!.email != null && post.contactInfo!.email!.isNotEmpty))) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.phone_circle,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      if (post.contactInfo!.showPhone && post.contactInfo!.phone != null && post.contactInfo!.phone!.isNotEmpty) ...[
                        Icon(
                          CupertinoIcons.phone,
                          size: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          post.contactInfo!.phone!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        if (post.contactInfo!.showEmail && post.contactInfo!.email != null && post.contactInfo!.email!.isNotEmpty)
                          const SizedBox(width: 12),
                      ],
                      if (post.contactInfo!.showEmail && post.contactInfo!.email != null && post.contactInfo!.email!.isNotEmpty) ...[
                        Icon(
                          CupertinoIcons.mail,
                          size: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            post.contactInfo!.email!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                // Separate images and video, then display
                Builder(
                  builder: (context) {
                    final allMedia = post.images;
                    final images = <MarketplacePostImage>[];
                    MarketplacePostImage? video;
                    
                    for (var media in allMedia) {
                      final url = media.imageUrl.toLowerCase();
                      final isVideo = url.contains('.mp4') || 
                                     url.contains('.mov') || 
                                     url.contains('.avi') || 
                                     url.contains('.webm') ||
                                     url.contains('.mkv') ||
                                     url.contains('video/') ||
                                     (media.thumbnailUrl == null && 
                                      !url.contains('.jpg') && 
                                      !url.contains('.jpeg') && 
                                      !url.contains('.png') && 
                                      !url.contains('.webp') &&
                                      !url.contains('.gif'));
                      
                      if (isVideo) {
                        video = media;
                      } else {
                        images.add(media);
                      }
                    }
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Video (if exists) - show first
                        if (video != null) ...[
                          const SizedBox(height: 12),
                          VideoPreviewWidget(
                            videoUrl: video.imageUrl,
                            height: 200,
                            width: double.infinity,
                            onTap: () {
                              Navigator.push(
                                context,
                                SmoothPageRoute(
                                  page: VideoViewerScreen(
                                    videoUrl: video!.imageUrl,
                                    title: post.title,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                        
                        // Images - Only show first 3 images, click to view all
                        if (images.isNotEmpty) ...[
                          SizedBox(height: video != null ? 12 : 0),
                          SizedBox(
                            height: 200,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: images.length > 3 ? 3 : images.length,
                              itemBuilder: (context, index) {
                                final image = images[index];
                                final isLastVisible = index == 2 && images.length > 3;
                                return GestureDetector(
                                  onTap: () {
                                    // Open image viewer with only images (not video)
                                    Navigator.push(
                                      context,
                                      SmoothPageRoute(
                                        page: ImageViewerScreen(
                                          images: images,
                                          initialIndex: index,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 200,
                                        margin: EdgeInsets.only(
                                          right: index < (images.length > 3 ? 2 : images.length - 1) ? 8 : 0,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          color: theme.colorScheme.surfaceContainerHighest,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.08),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: image.imageUrl.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: image.imageUrl,
                                                  fit: BoxFit.cover,
                                                  httpHeaders: {
                                                    'ngrok-skip-browser-warning': 'true',
                                                  },
                                                  placeholder: (context, url) => Container(
                                                    color: theme.colorScheme.surfaceContainerHighest,
                                                    child: Center(
                                                      child: SizedBox(
                                                        width: 24,
                                                        height: 24,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: theme.colorScheme.primary,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  errorWidget: (context, url, error) => Container(
                                                    color: theme.colorScheme.surfaceContainerHighest,
                                                    child: Icon(
                                                      CupertinoIcons.photo,
                                                      size: 48,
                                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                                    ),
                                                  ),
                                                )
                                              : Container(
                                                  color: theme.colorScheme.surfaceContainerHighest,
                                                  child: Icon(
                                                    CupertinoIcons.photo,
                                                    size: 48,
                                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      // Show "+X more" badge on last visible image if there are more images
                                      if (isLastVisible)
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              color: Colors.black.withValues(alpha: 0.5),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '+${images.length - 3}',
                                                style: theme.textTheme.titleLarge?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                // Actions - Comment and Share
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.chat_bubble,
                      size: 20,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.commentCount}',
                      key: ValueKey('comment_count_${post.id}_${post.commentCount}'),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (onShareTap != null) ...[
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () {
                          if (onShareTap != null) {
                            onShareTap!();
                          }
                        },
                        child: Icon(
                          CupertinoIcons.share,
                          size: 20,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Vừa xong';
        }
        return '${difference.inMinutes} phút trước';
      }
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays == 1) {
      return 'Hôm qua';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _getCategoryDisplayName(MarketplacePost post) {
    // Backend có thể trả về categoryName = category code, nên luôn map từ danh sách categories
    if (post.category.isNotEmpty) {
      try {
        final category = categories.firstWhere(
          (cat) => cat.code == post.category,
        );
        // Luôn dùng name (tiếng Việt) từ danh sách categories
        return category.name;
      } catch (e) {
        // Nếu không tìm thấy category, kiểm tra categoryName
        if (post.categoryName.isNotEmpty && post.categoryName != post.category) {
          return post.categoryName;
        }
        // Fallback về code
        return post.category;
      }
    }
    
    return '';
  }
}


