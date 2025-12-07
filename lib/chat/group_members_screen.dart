import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/chat/group.dart';
import 'chat_service.dart';

class GroupMembersScreen extends StatefulWidget {
  final String groupId;

  const GroupMembersScreen({super.key, required this.groupId});

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  final ChatService _service = ChatService();
  ChatGroup? _group;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGroupInfo();
  }

  Future<void> _loadGroupInfo() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final group = await _service.getGroupById(widget.groupId);
      setState(() {
        _group = group;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Lỗi khi tải thông tin nhóm: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  String _getRoleLabel(String role) {
    switch (role.toUpperCase()) {
      case 'ADMIN':
        return 'Quản trị viên';
      case 'MODERATOR':
        return 'Điều hành viên';
      case 'MEMBER':
        return 'Thành viên';
      default:
        return role;
    }
  }

  Color _getRoleColor(String role) {
    switch (role.toUpperCase()) {
      case 'ADMIN':
        return Colors.red;
      case 'MODERATOR':
        return Colors.orange;
      case 'MEMBER':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  List<GroupMember> _getSortedMembers() {
    if (_group?.members == null) return [];
    
    final members = List<GroupMember>.from(_group!.members!);
    members.sort((a, b) {
      // Sort by role: ADMIN first, then MODERATOR, then MEMBER
      final roleOrder = {'ADMIN': 0, 'MODERATOR': 1, 'MEMBER': 2};
      final aOrder = roleOrder[a.role.toUpperCase()] ?? 3;
      final bOrder = roleOrder[b.role.toUpperCase()] ?? 3;
      
      if (aOrder != bOrder) {
        return aOrder.compareTo(bOrder);
      }
      
      // If same role, sort by name
      final aName = a.residentName ?? '';
      final bName = b.residentName ?? '';
      return aName.compareTo(bName);
    });
    
    return members;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Thành viên nhóm'),
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
                        onPressed: _loadGroupInfo,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : _group == null || _group!.members == null || _group!.members!.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.person_2,
                            size: 64,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Chưa có thành viên nào',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Group info header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            border: Border(
                              bottom: BorderSide(
                                color: theme.colorScheme.outline.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (_group!.avatarUrl != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: CachedNetworkImage(
                                    imageUrl: _group!.avatarUrl!,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.group,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _group!.name,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (_group!.description != null && _group!.description!.isNotEmpty)
                                      Text(
                                        _group!.description!,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Member count
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Text(
                                'Thành viên (${_group!.currentMemberCount}/${_group!.maxMembers})',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Members list
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _getSortedMembers().length,
                            itemBuilder: (context, index) {
                              final member = _getSortedMembers()[index];
                              return _MemberListItem(
                                member: member,
                                roleLabel: _getRoleLabel(member.role),
                                roleColor: _getRoleColor(member.role),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _MemberListItem extends StatelessWidget {
  final GroupMember member;
  final String roleLabel;
  final Color roleColor;

  const _MemberListItem({
    required this.member,
    required this.roleLabel,
    required this.roleColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Avatar
          if (member.residentAvatar != null && member.residentAvatar!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: member.residentAvatar!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                CupertinoIcons.person_fill,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
          const SizedBox(width: 12),
          // Name and role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.residentName ?? 'Người dùng',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: roleColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    roleLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: roleColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Role icon
          Icon(
            member.role.toUpperCase() == 'ADMIN'
                ? CupertinoIcons.star_fill
                : member.role.toUpperCase() == 'MODERATOR'
                    ? CupertinoIcons.shield_fill
                    : CupertinoIcons.person,
            color: roleColor,
            size: 20,
          ),
        ],
      ),
    );
  }
}



