import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../models/chat/friend.dart';
import 'chat_service.dart';
import 'direct_chat_screen.dart';
import '../auth/api_client.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final ChatService _service = ChatService();
  final ApiClient _apiClient = ApiClient();
  List<Friend> _friends = [];
  bool _isLoading = true;
  String? _error;

  // Phone autocomplete for direct invitation
  final _phoneController = TextEditingController();
  List<Map<String, dynamic>> _phoneSuggestions = [];
  bool _isSearchingPhone = false;
  Timer? _phoneSearchDebounce;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _searchResidentsByPhone(String phonePrefix,
      {VoidCallback? onUpdate}) async {
    // Cancel previous debounce
    _phoneSearchDebounce?.cancel();

    // Normalize phone: remove all non-digit characters
    final normalizedPhone = phonePrefix.replaceAll(RegExp(r'[^0-9]'), '');

    // Only search if at least 3 digits
    if (normalizedPhone.length < 3) {
      setState(() {
        _phoneSuggestions = [];
        _isSearchingPhone = false;
      });
      onUpdate?.call();
      return;
    }

    // Debounce: wait 500ms before searching
    _phoneSearchDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() {
        _isSearchingPhone = true;
      });
      onUpdate?.call();

      try {
        final response = await _apiClient.dio.get(
          '/residents/search-by-phone',
          queryParameters: {'prefix': normalizedPhone},
        );

        if (mounted) {
          final List<dynamic> data = response.data ?? [];
          setState(() {
            _phoneSuggestions = data
                .map((item) => {
                      'id': item['id']?.toString() ?? '',
                      'fullName': item['fullName']?.toString() ?? '',
                      'phone': item['phone']?.toString() ?? '',
                    })
                .toList();
            _isSearchingPhone = false;
          });
          onUpdate?.call();
        }
      } catch (e) {
        print('⚠️ [FriendsScreen] Error searching residents by phone: $e');
        if (mounted) {
          setState(() {
            _phoneSuggestions = [];
            _isSearchingPhone = false;
          });
          onUpdate?.call();
        }
      }
    });
  }

  Future<void> _sendDirectInvitationByPhone(String phoneNumber) async {
    try {
      final invitation = await _service.createDirectInvitation(
        phoneNumber: phoneNumber,
        initialMessage: null,
      );

      if (mounted) {
        Navigator.pop(context); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đã gửi lời mời chat'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Extract error message
        String errorMessage = e.toString().replaceFirst('Exception: ', '');

        // Check if this is an informational message
        bool isInfoMessage = errorMessage.contains('Bạn đã gửi lời mời rồi') ||
            errorMessage.contains('đã gửi lời mời cho bạn rồi') ||
            errorMessage.contains('Vui lòng đợi phản hồi');

        if (!errorMessage.startsWith('Lỗi khi') &&
            !errorMessage.contains('đã gửi lời mời')) {
          errorMessage = 'Lỗi khi gửi lời mời: $errorMessage';
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

  void _showInviteByPhoneDialog() {
    _phoneController.clear();
    setState(() {
      _phoneSuggestions = [];
      _isSearchingPhone = false;
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Gửi lời mời chat bằng số điện thoại'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: 'Số điện thoại',
                      hintText: '0123456789',
                      border: const OutlineInputBorder(),
                      suffixIcon: _isSearchingPhone
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onChanged: (value) {
                      _searchResidentsByPhone(value, onUpdate: () {
                        setDialogState(
                            () {}); // Update dialog state to show suggestions
                      });
                    },
                  ),
                  // Phone suggestions dropdown
                  if (_phoneSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.2),
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _phoneSuggestions.length,
                        itemBuilder: (context, index) {
                          final resident = _phoneSuggestions[index];
                          final fullName =
                              resident['fullName']?.toString() ?? '';
                          final phone = resident['phone']?.toString() ?? '';
                          return ListTile(
                            dense: true,
                            title: Text(
                              fullName.isNotEmpty ? fullName : 'Không có tên',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            subtitle: Text(
                              phone,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                            ),
                            leading: Icon(
                              CupertinoIcons.person_circle,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            onTap: () {
                              final normalizedPhone =
                                  phone.replaceAll(RegExp(r'[^0-9]'), '');
                              _sendDirectInvitationByPhone(normalizedPhone);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () {
                  final phone = _phoneController.text
                      .trim()
                      .replaceAll(RegExp(r'[^0-9]'), '');
                  if (phone.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Vui lòng nhập số điện thoại')),
                    );
                    return;
                  }
                  if (phone.length != 10) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Số điện thoại phải có 10 chữ số')),
                    );
                    return;
                  }
                  _sendDirectInvitationByPhone(phone);
                },
                child: const Text('Gửi lời mời'),
              ),
            ],
          );
        },
      ),
    );
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
      // if (mounted) {
      //   Navigator.push(
      //     context,
      //     MaterialPageRoute(
      //       builder: (context) => DirectChatScreen(
      //         conversationId: friend.conversationId!,
      //         otherParticipantName: friend.friendName,
      //       ),
      //     ),
      //   );
      // }
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
          final isExistingInvitation =
              createdAt != null && now.difference(createdAt).inSeconds > 1;

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
          bool isInfoMessage =
              errorMessage.contains('Bạn đã gửi lời mời rồi') ||
                  errorMessage.contains('đã gửi lời mời cho bạn rồi') ||
                  errorMessage.contains('Vui lòng đợi phản hồi');

          print('   📋 Is info message: $isInfoMessage');

          // If error message already contains the full message, use it directly
          // Otherwise, prepend "Lỗi khi gửi lời mời: "
          if (!errorMessage.startsWith('Lỗi khi') &&
              !errorMessage.contains('đã gửi lời mời')) {
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
            icon: const Icon(CupertinoIcons.person_add),
            onPressed: _showInviteByPhoneDialog,
            tooltip: 'Gửi lời mời chat bằng số điện thoại',
          ),
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
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Chưa có bạn bè nào',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Chấp nhận lời mời chat để thêm bạn bè',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
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
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
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
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                            onTap: () => _navigateToChat(friend),
                          );
                        },
                      ),
      ),
    );
  }
}
