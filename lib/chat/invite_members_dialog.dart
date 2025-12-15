import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'chat_service.dart';
import '../auth/api_client.dart';
import '../auth/token_storage.dart';
import '../models/chat/invitation.dart';
import '../models/chat/friend.dart';
import '../profile/profile_service.dart';

class InviteMembersDialog extends StatefulWidget {
  final String groupId;

  const InviteMembersDialog({super.key, required this.groupId});

  @override
  State<InviteMembersDialog> createState() => _InviteMembersDialogState();
}

class _InviteMembersDialogState extends State<InviteMembersDialog> with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final ChatService _service = ChatService();
  final ApiClient _apiClient = ApiClient();
  final TokenStorage _tokenStorage = TokenStorage();
  List<String> _phoneNumbers = [];
  bool _isLoading = false;
  
  // Phone autocomplete
  List<Map<String, dynamic>> _phoneSuggestions = [];
  bool _isSearchingPhone = false;
  Timer? _phoneSearchDebounce;
  
  // Invitations for this group (PENDING or ACCEPTED - already invited)
  Set<String> _invitedPhones = {}; // Normalized phone numbers
  Map<String, String> _invitationStatusByPhone = {}; // Map phone -> status (PENDING/ACCEPTED)
  bool _isLoadingInvitations = false;
  
  // Group members - to check if already a member
  Set<String> _memberResidentIds = {}; // Resident IDs that are already members
  bool _isLoadingMembers = false;
  
  // Current user phone number (normalized) - to identify "me" in suggestions
  String? _currentUserPhoneNormalized;
  
  // Tab management
  late final TabController _tabController;
  
  // Friends list for "Chọn từ bạn bè" tab
  List<Friend> _friends = [];
  Set<String> _selectedFriendIds = {}; // Selected friend residentIds
  bool _isLoadingFriends = false;
  final _friendSearchController = TextEditingController();
  List<Friend> _filteredFriends = [];

  @override
  void initState() {
    super.initState();
    // Initialize TabController immediately
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index == 1 && _friends.isEmpty) {
        // Load friends when switching to friends tab
        _loadFriends();
      }
    });
    _loadCurrentUserPhone();
    _loadInvitations();
    _loadGroupMembers();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _friendSearchController.dispose();
    _tabController.dispose();
    _phoneSearchDebounce?.cancel();
    super.dispose();
  }

  /// Load current user phone number
  Future<void> _loadCurrentUserPhone() async {
    try {
      final apiClient = await ApiClient.create();
      final profileService = ProfileService(apiClient.dio);
      final profile = await profileService.getProfile();
      
      // Get phone from profile (could be 'phone' or 'phoneNumber')
      final phone = profile['phone'] ?? profile['phoneNumber'];
      if (phone != null && phone.toString().isNotEmpty) {
        _currentUserPhoneNormalized = _normalizePhone(phone.toString());
      }
    } catch (e) {
      debugPrint('⚠️ [InviteMembersDialog] Error loading current user phone: $e');
      // Continue without current user phone - suggestions will still work
    }
  }

  /// Normalize phone number: Remove leading '0', prefix '84' if not present
  /// This ensures consistent comparison between user input and API response
  String _normalizePhone(String phone) {
    // Remove all non-digit characters first
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Remove leading '0' if present
    if (cleaned.startsWith('0') && cleaned.length > 1) {
      cleaned = cleaned.substring(1);
    }
    
    // Prefix '84' if not already present
    if (!cleaned.startsWith('84')) {
      cleaned = '84$cleaned';
    }
    
    return cleaned;
  }
  
  /// Check if a phone number belongs to current user
  bool _isCurrentUser(String phone) {
    if (_currentUserPhoneNormalized == null) return false;
    final normalizedPhone = _normalizePhone(phone);
    return normalizedPhone == _currentUserPhoneNormalized;
  }

  /// Load invitations for this group (PENDING and ACCEPTED)
  Future<void> _loadInvitations() async {
    setState(() {
      _isLoadingInvitations = true;
    });

    try {
      // Use new API to get all invitations for this specific group
      // This includes invitations sent by current user (as inviter) and received by current user (as invitee)
      final groupInvitations = await _service.getGroupInvitations(widget.groupId);

      // Normalize phone numbers and store in set, also track status
      final normalizedPhones = <String>{};
      final statusMap = <String, String>{};
      
      for (final inv in groupInvitations) {
        // Only process PENDING or ACCEPTED invitations
        if (inv.status == 'PENDING' || inv.status == 'ACCEPTED') {
          final normalizedPhone = _normalizePhone(inv.inviteePhone);
          normalizedPhones.add(normalizedPhone);
          statusMap[normalizedPhone] = inv.status;
        }
      }

      if (mounted) {
        setState(() {
          _invitedPhones = normalizedPhones;
          _invitationStatusByPhone = statusMap;
          _isLoadingInvitations = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ [InviteMembersDialog] Error loading invitations: $e');
      if (mounted) {
        setState(() {
          _isLoadingInvitations = false;
        });
      }
    }
  }

  /// Load group members to check if already a member
  Future<void> _loadGroupMembers() async {
    setState(() {
      _isLoadingMembers = true;
    });

    try {
      final group = await _service.getGroupById(widget.groupId);
      
      if (group.members != null && mounted) {
        final memberIds = group.members!
            .map((member) => member.residentId)
            .toSet();
        
        setState(() {
          _memberResidentIds = memberIds;
          _isLoadingMembers = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ [InviteMembersDialog] Error loading group members: $e');
      if (mounted) {
        setState(() {
          _isLoadingMembers = false;
        });
      }
    }
  }

  Future<void> _searchResidentsByPhone(String phonePrefix) async {
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
      return;
    }
    
    // Debounce: wait 500ms before searching
    _phoneSearchDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() {
        _isSearchingPhone = true;
      });
      
      try {
        final response = await _apiClient.dio.get(
          '/residents/search-by-phone',
          queryParameters: {'prefix': normalizedPhone},
        );
        
        if (mounted) {
          final List<dynamic> data = response.data ?? [];
          setState(() {
            _phoneSuggestions = data.map((item) => {
              'id': item['id']?.toString() ?? '',
              'fullName': item['fullName']?.toString() ?? '',
              'phone': item['phone']?.toString() ?? '',
            }).toList();
            _isSearchingPhone = false;
          });
        }
      } catch (e) {
        debugPrint('⚠️ [InviteMembersDialog] Error searching residents by phone: $e');
        if (mounted) {
          setState(() {
            _phoneSuggestions = [];
            _isSearchingPhone = false;
          });
        }
      }
    });
  }

  void _selectPhoneSuggestion(Map<String, dynamic> resident) {
    final phone = resident['phone']?.toString() ?? '';
    if (phone.isEmpty) return;
    
    // Normalize phone for comparison
    final normalizedPhone = _normalizePhone(phone);
    
    // Check if already added to list (compare with normalized phones in list)
    final isAlreadyAdded = _phoneNumbers.any((p) => _normalizePhone(p) == normalizedPhone);
    if (isAlreadyAdded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số điện thoại đã được thêm')),
      );
      return;
    }
    
    // Get resident ID from suggestion
    final residentId = resident['id']?.toString() ?? '';
    
    // Check if current user (cannot invite yourself)
    if (_isCurrentUser(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn không thể mời chính mình vào nhóm'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Check if already a member
    if (_isAlreadyMember(residentId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Người dùng này đã là thành viên của nhóm'),
          backgroundColor: Colors.blue,
        ),
      );
      return;
    }
    
    // Check if already has invitation (PENDING or ACCEPTED)
    if (_hasInvitation(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã gửi lời mời cho số điện thoại này'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Store phone in original format (as user sees it) for display
    final displayPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    setState(() {
      _phoneNumbers.add(displayPhone);
      _phoneController.clear();
      _phoneSuggestions = [];
    });
  }
  
  /// Check if a phone number has an invitation (PENDING or ACCEPTED)
  bool _hasInvitation(String phone) {
    final normalizedPhone = _normalizePhone(phone);
    return _invitedPhones.contains(normalizedPhone);
  }
  
  /// Get invitation status for a phone number
  String? _getInvitationStatus(String phone) {
    final normalizedPhone = _normalizePhone(phone);
    return _invitationStatusByPhone[normalizedPhone];
  }
  
  /// Check if a resident is already a member of the group
  bool _isAlreadyMember(String residentId) {
    return _memberResidentIds.contains(residentId);
  }
  
  /// Check if should disable a resident (has invitation OR already a member OR is current user)
  bool _shouldDisableResident(String residentId, String phone) {
    return _isAlreadyMember(residentId) || _hasInvitation(phone) || _isCurrentUser(phone);
  }
  
  /// Get status text for a resident
  String? _getResidentStatusText(String residentId, String phone) {
    // Priority: Check if current user first
    if (_isCurrentUser(phone)) {
      return null; // Will show "(tôi)" in name instead
    }
    // Check if already a member
    if (_isAlreadyMember(residentId)) {
      return 'Đã là thành viên';
    }
    // If not a member, check invitation status
    if (_hasInvitation(phone)) {
      // Has invitation (PENDING or ACCEPTED) but not a member yet
      return 'Đã gửi lời mời';
    }
    return null;
  }
  
  /// Get display name for a resident (with "(tôi)" suffix if current user)
  String _getDisplayName(String fullName, String phone) {
    if (_isCurrentUser(phone)) {
      return '$fullName (tôi)';
    }
    return fullName;
  }
  
  /// Get status icon for a resident
  IconData? _getResidentStatusIcon(String residentId, String phone) {
    // Don't show icon for current user (will show "(tôi)" in name instead)
    if (_isCurrentUser(phone)) {
      return null;
    }
    if (_isAlreadyMember(residentId)) {
      return CupertinoIcons.person_circle_fill;
    }
    final invitationStatus = _getInvitationStatus(phone);
    if (invitationStatus == 'PENDING') {
      return CupertinoIcons.clock;
    } else if (invitationStatus == 'ACCEPTED') {
      return CupertinoIcons.check_mark_circled;
    }
    return null;
  }
  
  /// Get status color for a resident
  Color _getResidentStatusColor(String residentId, String phone) {
    // Don't show color for current user (will show "(tôi)" in name instead)
    if (_isCurrentUser(phone)) {
      return Colors.grey;
    }
    if (_isAlreadyMember(residentId)) {
      return Colors.blue;
    }
    final invitationStatus = _getInvitationStatus(phone);
    if (invitationStatus == 'PENDING') {
      return Colors.orange;
    } else if (invitationStatus == 'ACCEPTED') {
      return Colors.green;
    }
    return Colors.grey;
  }
  
  /// Load friends list
  Future<void> _loadFriends() async {
    if (_friends.isNotEmpty) {
      // Already loaded, just filter
      _filterFriends();
      return;
    }
    
    if (mounted) {
      setState(() {
        _isLoadingFriends = true;
      });
    }
    
    try {
      final friends = await _service.getFriends();
      if (mounted) {
        setState(() {
          _friends = friends;
          _isLoadingFriends = false;
        });
        _filterFriends();
      }
    } catch (e) {
      debugPrint('⚠️ [InviteMembersDialog] Error loading friends: $e');
      if (mounted) {
        setState(() {
          _isLoadingFriends = false;
        });
      }
    }
  }
  
  /// Filter friends based on search query
  void _filterFriends() {
    final query = _friendSearchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredFriends = List.from(_friends);
      });
    } else {
      setState(() {
        _filteredFriends = _friends.where((friend) {
          final name = friend.friendName.toLowerCase();
          final phone = friend.friendPhone.toLowerCase();
          return name.contains(query) || phone.contains(query);
        }).toList();
      });
    }
  }
  
  /// Toggle friend selection
  void _toggleFriendSelection(String friendId, String friendPhone) {
    // Check if should disable
    if (_isAlreadyMember(friendId) || _hasInvitation(friendPhone) || _isCurrentUser(friendPhone)) {
      return; // Don't allow selection
    }
    
    setState(() {
      if (_selectedFriendIds.contains(friendId)) {
        _selectedFriendIds.remove(friendId);
      } else {
        _selectedFriendIds.add(friendId);
      }
    });
  }
  
  /// Check if friend should be disabled
  bool _shouldDisableFriend(Friend friend) {
    return _isAlreadyMember(friend.friendId) || 
           _hasInvitation(friend.friendPhone) || 
           _isCurrentUser(friend.friendPhone);
  }
  
  /// Get status text for friend
  String? _getFriendStatusText(Friend friend) {
    if (_isCurrentUser(friend.friendPhone)) {
      return null; // Will show "(tôi)" in name
    }
    if (_isAlreadyMember(friend.friendId)) {
      return 'Đã tham gia';
    }
    if (_hasInvitation(friend.friendPhone)) {
      return 'Đã gửi lời mời';
    }
    return null;
  }
  
  /// Get display name for friend (with "(tôi)" if current user)
  String _getFriendDisplayName(Friend friend) {
    if (_isCurrentUser(friend.friendPhone)) {
      return '${friend.friendName} (tôi)';
    }
    return friend.friendName;
  }


  void _removePhoneNumber(String phone) {
    setState(() {
      _phoneNumbers.remove(phone);
    });
  }

  Future<void> _inviteMembers() async {
    // Collect phone numbers from both tabs
    final phonesToInvite = <String>[];
    
    // From phone input tab
    if (_tabController.index == 0) {
      if (_phoneNumbers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng thêm ít nhất một số điện thoại')),
        );
        return;
      }
      
      // Filter out phones that already have invitations or are current user
      for (final phone in _phoneNumbers) {
        // Skip if current user (cannot invite yourself)
        if (_currentUserPhoneNormalized != null && _normalizePhone(phone) == _currentUserPhoneNormalized) {
          continue;
        }
        // Skip if already has invitation
        if (!_hasInvitation(phone)) {
          phonesToInvite.add(phone);
        }
      }
    } 
    // From friends tab
    else {
      if (_selectedFriendIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng chọn ít nhất một bạn bè')),
        );
        return;
      }
      
      // Convert selected friends to phone numbers
      for (final friendId in _selectedFriendIds) {
        final friend = _friends.firstWhere(
          (f) => f.friendId == friendId,
          orElse: () => Friend(
            friendId: '',
            friendName: '',
            friendPhone: '',
            hasActiveConversation: false,
          ),
        );
        
        if (friend.friendId.isEmpty || friend.friendPhone.isEmpty) continue;
        
        // Skip if current user
        if (_isCurrentUser(friend.friendPhone)) {
          continue;
        }
        // Skip if already has invitation or is member
        if (!_hasInvitation(friend.friendPhone) && !_isAlreadyMember(friendId)) {
          // Normalize phone: remove non-digits
          final phone = friend.friendPhone.replaceAll(RegExp(r'[^0-9]'), '');
          if (phone.isNotEmpty) {
            phonesToInvite.add(phone);
          }
        }
      }
    }
    
    // If all phones are already invited or are current user, show message and return
    if (phonesToInvite.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Người này đã được mời trước đó'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _service.inviteMembersByPhone(
        groupId: widget.groupId,
        phoneNumbers: phonesToInvite,
      );

      if (mounted) {
        // Parse skipped phones from response and add to invited phones
        // Format: "0346583387 (Bạn đã gửi lời mời rồi...)" or just "0346583387"
        final newInvitedPhones = <String>{};
        for (final skippedPhone in result.skippedPhones) {
          // Extract phone number from string (remove text in parentheses)
          // Match pattern: digits at the start, optionally followed by space and text in parentheses
          final phoneMatch = RegExp(r'^(\d+)').firstMatch(skippedPhone);
          if (phoneMatch != null) {
            final phoneStr = phoneMatch.group(1) ?? '';
            if (phoneStr.isNotEmpty) {
              // Normalize phone before adding
              final normalizedPhone = _normalizePhone(phoneStr);
              newInvitedPhones.add(normalizedPhone);
            }
          }
        }
        
        // Update state with new invited phones before reloading
        if (newInvitedPhones.isNotEmpty) {
          setState(() {
            _invitedPhones.addAll(newInvitedPhones);
            // Mark as PENDING since it's skipped due to existing invitation
            for (final phone in newInvitedPhones) {
              _invitationStatusByPhone[phone] = 'PENDING';
            }
          });
        }
        
        // Reload invitations and members to update the list
        await _loadInvitations();
        await _loadGroupMembers();
        
        Navigator.pop(context, true);
        
        // Only show success message if at least one invitation was sent successfully
        if (result.successfulInvitations.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã gửi lời mời thành công'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
        // Don't show "Không có lời mời nào được gửi" - this happens when all selected phones
        // already have invitations, which is expected behavior
      }
    } catch (e) {
      if (mounted) {
        // Extract error message - remove "Exception: " prefix if present
        String errorMessage = e.toString().replaceFirst('Exception: ', '');
        
        // Check if this is an informational message (not an error)
        bool isInfoMessage = errorMessage.contains('Bạn đã gửi lời mời rồi') || 
                             errorMessage.contains('đã gửi lời mời cho bạn rồi');
        
        // If error message already contains the full message, use it directly
        if (!errorMessage.startsWith('Lỗi') && !errorMessage.contains('đã gửi lời mời')) {
          errorMessage = 'Lỗi khi mời thành viên: $errorMessage';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: isInfoMessage ? Colors.orange : Colors.red,
            duration: Duration(seconds: isInfoMessage ? 5 : 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Mời thành viên'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tab bar
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Nhập số điện thoại'),
                Tab(text: 'Chọn từ bạn bè'),
              ],
            ),
            const SizedBox(height: 8),
            // Tab content
            SizedBox(
              height: 400,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPhoneInputTab(theme),
                  _buildFriendsTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _inviteMembers,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Gửi lời mời'),
        ),
      ],
    );
  }
  
  /// Build phone input tab
  Widget _buildPhoneInputTab(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nhập số điện thoại của cư dân để mời họ tham gia nhóm',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Số điện thoại',
                  hintText: 'Nhập số điện thoại để tìm cư dân',
                  border: const OutlineInputBorder(),
                  suffixIcon: _isSearchingPhone
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                  _searchResidentsByPhone(value);
                },
              ),
              // Phone suggestions dropdown
              if (_phoneSuggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
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
                      final fullName = resident['fullName']?.toString() ?? '';
                      final phone = resident['phone']?.toString() ?? '';
                      final residentId = resident['id']?.toString() ?? '';
                      final normalizedPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
                      final shouldDisable = _shouldDisableResident(residentId, phone);
                      final statusText = _getResidentStatusText(residentId, phone);
                      final statusIcon = _getResidentStatusIcon(residentId, phone);
                      final statusColor = _getResidentStatusColor(residentId, phone);
                      final displayName = _getDisplayName(fullName, phone);
                      final isCurrentUser = _isCurrentUser(phone);
                      
                      return AbsorbPointer(
                        absorbing: shouldDisable,
                        child: Opacity(
                          opacity: shouldDisable ? 0.4 : 1.0,
                          child: ListTile(
                            dense: true,
                            enabled: !shouldDisable,
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName.isNotEmpty ? displayName : 'Không có tên',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: shouldDisable
                                          ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                                          : null,
                                      fontWeight: isCurrentUser ? FontWeight.w500 : null,
                                    ),
                                  ),
                                ),
                                if (shouldDisable && statusIcon != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: Icon(
                                      statusIcon,
                                      size: 16,
                                      color: statusColor,
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  phone,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                                if (shouldDisable && statusText != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      children: [
                                        Icon(
                                          CupertinoIcons.info_circle,
                                          size: 12,
                                          color: statusColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          statusText,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: statusColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            leading: Icon(
                              CupertinoIcons.person_circle,
                              color: shouldDisable
                                  ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                                  : theme.colorScheme.primary,
                            ),
                            onTap: () {
                              if (!shouldDisable) {
                                _selectPhoneSuggestion(resident);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          if (_phoneNumbers.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _phoneNumbers.map((phone) {
                return Chip(
                  label: Text(phone),
                  onDeleted: () => _removePhoneNumber(phone),
                  deleteIcon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
  
  /// Build friends tab
  Widget _buildFriendsTab(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chọn bạn bè từ danh sách để mời vào nhóm',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        // Search field
        TextField(
          controller: _friendSearchController,
          decoration: InputDecoration(
            labelText: 'Tìm kiếm',
            hintText: 'Tìm theo tên hoặc số điện thoại',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(CupertinoIcons.search),
          ),
          onChanged: (_) => _filterFriends(),
        ),
        const SizedBox(height: 16),
        // Friends list
        if (_isLoadingFriends)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_filteredFriends.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _friends.isEmpty ? 'Chưa có bạn bè nào' : 'Không tìm thấy bạn bè',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filteredFriends.length,
              itemBuilder: (context, index) {
                final friend = _filteredFriends[index];
                final shouldDisable = _shouldDisableFriend(friend);
                final statusText = _getFriendStatusText(friend);
                final displayName = _getFriendDisplayName(friend);
                final isSelected = _selectedFriendIds.contains(friend.friendId);
                final isCurrentUser = _isCurrentUser(friend.friendPhone);
                
                return AbsorbPointer(
                  absorbing: shouldDisable,
                  child: Opacity(
                    opacity: shouldDisable ? 0.4 : 1.0,
                    child: CheckboxListTile(
                      value: isSelected,
                      enabled: !shouldDisable,
                      title: Text(
                        displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: shouldDisable
                              ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                              : null,
                          fontWeight: isCurrentUser ? FontWeight.w500 : null,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            friend.friendPhone,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          if (shouldDisable && statusText != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.info_circle,
                                    size: 12,
                                    color: _isAlreadyMember(friend.friendId)
                                        ? Colors.blue
                                        : Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _isAlreadyMember(friend.friendId)
                                          ? Colors.blue
                                          : Colors.orange,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      onChanged: shouldDisable
                          ? null
                          : (value) => _toggleFriendSelection(friend.friendId, friend.friendPhone),
                    ),
                  ),
                );
              },
            ),
          ),
        if (_selectedFriendIds.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedFriendIds.map((friendId) {
              final friend = _friends.firstWhere((f) => f.friendId == friendId);
              return Chip(
                label: Text(friend.friendName),
                onDeleted: () => _toggleFriendSelection(friendId, friend.friendPhone),
                deleteIcon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}


