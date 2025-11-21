import 'package:flutter/material.dart';

enum NotificationReadStatusFilter {
  all,
  read,
  unread,
}

class NotificationReadStatusFilterWidget extends StatelessWidget {
  final NotificationReadStatusFilter currentFilter;
  final Function(NotificationReadStatusFilter) onFilterChanged;

  const NotificationReadStatusFilterWidget({
    super.key,
    required this.currentFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filters = [
      (
        filter: NotificationReadStatusFilter.all,
        label: 'Tất cả',
        icon: Icons.list_rounded
      ),
      (
        filter: NotificationReadStatusFilter.unread,
        label: 'Chưa đọc',
        icon: Icons.mark_email_unread_outlined
      ),
      (
        filter: NotificationReadStatusFilter.read,
        label: 'Đã đọc',
        icon: Icons.done_all_rounded
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.colorScheme.surface,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: filters.map((entry) {
          final isSelected = currentFilter == entry.filter;
          return GestureDetector(
            onTap: () => onFilterChanged(entry.filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(32),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.24),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    entry.icon,
                    size: 16,
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    entry.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
