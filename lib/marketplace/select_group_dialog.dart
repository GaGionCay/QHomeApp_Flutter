import 'package:flutter/material.dart';
import '../models/chat/group.dart';

class SelectGroupDialog extends StatefulWidget {
  final List<ChatGroup> groups;

  const SelectGroupDialog({
    super.key,
    required this.groups,
  });

  @override
  State<SelectGroupDialog> createState() => _SelectGroupDialogState();
}

class _SelectGroupDialogState extends State<SelectGroupDialog> {
  ChatGroup? _selectedGroup;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chọn nhóm'),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.groups.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Bạn chưa có nhóm nào'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.groups.length,
                itemBuilder: (context, index) {
                  final group = widget.groups[index];
                  final isSelected = _selectedGroup?.id == group.id;
                  
                  return RadioListTile<ChatGroup>(
                    title: Text(group.name),
                    subtitle: group.description != null && group.description!.isNotEmpty
                        ? Text(
                            group.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    value: group,
                    groupValue: _selectedGroup,
                    onChanged: (value) {
                      setState(() {
                        _selectedGroup = value;
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
          onPressed: _selectedGroup != null
              ? () => Navigator.pop(context, _selectedGroup)
              : null,
          child: const Text('Chọn'),
        ),
      ],
    );
  }
}

