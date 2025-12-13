import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'chat_service.dart';

class InviteMembersDialog extends StatefulWidget {
  final String groupId;

  const InviteMembersDialog({super.key, required this.groupId});

  @override
  State<InviteMembersDialog> createState() => _InviteMembersDialogState();
}

class _InviteMembersDialogState extends State<InviteMembersDialog> {
  final _phoneController = TextEditingController();
  final ChatService _service = ChatService();
  List<String> _phoneNumbers = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
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

  Future<void> _inviteMembers() async {
    if (_phoneNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng thêm ít nhất một số điện thoại')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _service.inviteMembersByPhone(
        groupId: widget.groupId,
        phoneNumbers: _phoneNumbers,
      );

      if (mounted) {
        // Build message with results
        final messages = <String>[];
        
        if (result.successfulInvitations.isNotEmpty) {
          messages.add('Đã gửi ${result.successfulInvitations.length} lời mời thành công');
        }
        
        if (result.invalidPhones.isNotEmpty) {
          messages.add('${result.invalidPhones.length} số không hợp lệ: ${result.invalidPhones.join(", ")}');
        }
        
        if (result.skippedPhones.isNotEmpty) {
          messages.add('${result.skippedPhones.length} số đã bỏ qua: ${result.skippedPhones.join(", ")}');
        }

        final message = messages.isEmpty 
            ? 'Không có lời mời nào được gửi'
            : messages.join('\n');

        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: result.invalidPhones.isEmpty && result.skippedPhones.isEmpty
                ? Colors.green
                : Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nhập số điện thoại của cư dân để mời họ tham gia nhóm',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
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
            ],
          ),
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
}


