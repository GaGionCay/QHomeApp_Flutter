import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/chat/group.dart';

class SelectGroupDialog extends StatefulWidget {
  final List<ChatGroup> groups;
  final bool allowCreateNew;
  final String? targetResidentId; // ResidentId của người được mời
  final String? currentResidentId; // ResidentId của người mời

  const SelectGroupDialog({
    super.key,
    required this.groups,
    this.allowCreateNew = true,
    this.targetResidentId,
    this.currentResidentId,
  });

  @override
  State<SelectGroupDialog> createState() => _SelectGroupDialogState();
}

class _SelectGroupDialogState extends State<SelectGroupDialog> {
  ChatGroup? _selectedGroup;
  bool _createNewGroup = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chọn nhóm'),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.groups.isEmpty && !widget.allowCreateNew
            ? const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Bạn chưa có nhóm nào'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.groups.length + (widget.allowCreateNew ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0 && widget.allowCreateNew) {
                    // Option to create new group
                    return RadioListTile<bool>(
                      title: Row(
                        children: [
                          const Icon(CupertinoIcons.add_circled, size: 20),
                          const SizedBox(width: 8),
                          const Text('Tạo nhóm mới'),
                        ],
                      ),
                      value: true,
                      groupValue: _createNewGroup ? true : null,
                      onChanged: (value) {
                        setState(() {
                          _createNewGroup = true;
                          _selectedGroup = null;
                        });
                      },
                      selected: _createNewGroup,
                    );
                  }
                  
                  final groupIndex = widget.allowCreateNew ? index - 1 : index;
                  final group = widget.groups[groupIndex];
                  final isSelected = !_createNewGroup && _selectedGroup?.id == group.id;
                  
                  // Check if both current user and target user are already in this group
                  bool bothInGroup = false;
                  if (widget.targetResidentId != null && widget.currentResidentId != null && group.members != null) {
                    final currentUserInGroup = group.members!.any(
                      (member) => member.residentId == widget.currentResidentId,
                    );
                    final targetUserInGroup = group.members!.any(
                      (member) => member.residentId == widget.targetResidentId,
                    );
                    bothInGroup = currentUserInGroup && targetUserInGroup;
                  }
                  
                  return RadioListTile<ChatGroup>(
                    title: Text(group.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (group.description != null && group.description!.isNotEmpty)
                          Text(
                            group.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (bothInGroup)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              'Cả 2 đã ở nhóm này',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                    value: group,
                    groupValue: _createNewGroup ? null : _selectedGroup,
                    onChanged: bothInGroup ? null : (value) {
                      setState(() {
                        _selectedGroup = value;
                        _createNewGroup = false;
                      });
                    },
                    selected: isSelected,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: (_selectedGroup != null || _createNewGroup)
              ? () => Navigator.pop(context, _createNewGroup ? 'create_new' : _selectedGroup)
              : null,
          child: const Text('Chọn'),
        ),
      ],
    );
  }
}

