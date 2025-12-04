import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chat_service.dart';
import '../models/chat/friend.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  final ChatService _service = ChatService();
  
  List<String> _phoneNumbers = [];
  List<Friend> _friends = [];
  Set<String> _selectedFriendIds = {}; // Selected friend residentIds
  bool _isLoading = false;
  bool _isLoadingFriends = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoadingFriends = true;
    });

    try {
      final friends = await _service.getFriends();
      if (mounted) {
        setState(() {
          _friends = friends;
          _isLoadingFriends = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFriends = false;
        });
        // Don't show error, just log it - friends list is optional
        debugPrint('⚠️ [CreateGroupScreen] Error loading friends: $e');
      }
    }
  }

  void _toggleFriendSelection(String friendId) {
    setState(() {
      if (_selectedFriendIds.contains(friendId)) {
        _selectedFriendIds.remove(friendId);
      } else {
        _selectedFriendIds.add(friendId);
      }
    });
  }

  void _addPhoneNumber() {
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập số điện thoại')),
      );
      return;
    }

    if (phone.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số điện thoại phải có 10 chữ số')),
      );
      return;
    }

    if (_phoneNumbers.contains(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số điện thoại đã được thêm')),
      );
      return;
    }

    setState(() {
      _phoneNumbers.add(phone);
      _phoneController.clear();
    });
  }

  void _removePhoneNumber(String phone) {
    setState(() {
      _phoneNumbers.remove(phone);
    });
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên nhóm')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final group = await _service.createGroup(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      // Add friends as members if selected
      if (_selectedFriendIds.isNotEmpty) {
        try {
          await _service.addMembers(
            groupId: group.id,
            memberIds: _selectedFriendIds.toList(),
          );
          debugPrint('✅ Added ${_selectedFriendIds.length} friends to group');
        } catch (e) {
          debugPrint('⚠️ Error adding friends to group: $e');
          // Continue even if adding friends fails
        }
      }

      // Invite members by phone if provided
      if (_phoneNumbers.isNotEmpty) {
        try {
          final inviteResult = await _service.inviteMembersByPhone(
            groupId: group.id,
            phoneNumbers: _phoneNumbers,
          );
          if (inviteResult.invalidPhones.isNotEmpty) {
            debugPrint('Some phone numbers are invalid: ${inviteResult.invalidPhones}');
          }
        } catch (e) {
          debugPrint('Error inviting members: $e');
          // Continue even if invitation fails
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tạo nhóm thành công'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tạo nhóm: ${e.toString()}'),
            backgroundColor: Colors.red,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo nhóm chat'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên nhóm *',
                hintText: 'Nhập tên nhóm',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vui lòng nhập tên nhóm';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Mô tả (tùy chọn)',
                hintText: 'Nhập mô tả nhóm',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            // Add friends section
            Text(
              'Thêm thành viên từ bạn bè',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Chọn bạn bè để thêm vào nhóm',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoadingFriends)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_friends.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Bạn chưa có bạn bè nào',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _friends.length,
                  itemBuilder: (context, index) {
                    final friend = _friends[index];
                    final isSelected = _selectedFriendIds.contains(friend.friendId);
                    return CheckboxListTile(
                      title: Text(friend.friendName),
                      subtitle: friend.friendPhone.isNotEmpty
                          ? Text(friend.friendPhone)
                          : null,
                      value: isSelected,
                      onChanged: (value) => _toggleFriendSelection(friend.friendId),
                      dense: true,
                    );
                  },
                ),
              ),
            if (_selectedFriendIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedFriendIds.map((friendId) {
                  final friend = _friends.firstWhere((f) => f.friendId == friendId);
                  return Chip(
                    label: Text(friend.friendName),
                    onDeleted: () => _toggleFriendSelection(friendId),
                    deleteIcon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Thêm thành viên bằng số điện thoại',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nhập số điện thoại của cư dân để mời họ tham gia nhóm',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại',
                      hintText: '0123456789',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(CupertinoIcons.add_circled),
                  onPressed: _addPhoneNumber,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer,
                  ),
                ),
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
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _isLoading ? null : _createGroup,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Tạo nhóm'),
            ),
          ],
        ),
      ),
    );
  }
}


