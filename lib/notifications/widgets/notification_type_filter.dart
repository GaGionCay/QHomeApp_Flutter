import 'package:flutter/material.dart';

enum NotificationTypeFilter {
  all,
  cardApproved,
}

class NotificationTypeFilterWidget extends StatelessWidget {
  final NotificationTypeFilter currentFilter;
  final Function(NotificationTypeFilter) onFilterChanged;

  const NotificationTypeFilterWidget({
    super.key,
    required this.currentFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = [
      (
        filter: NotificationTypeFilter.all,
        label: 'Tất cả',
        icon: Icons.notifications_outlined,
      ),
      (
        filter: NotificationTypeFilter.cardApproved,
        label: 'Thẻ đã duyệt',
        icon: Icons.check_circle_outline,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Loại thông báo',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: chips.map((chip) {
              final isSelected = chip.filter == currentFilter;
              return GestureDetector(
                onTap: () => onFilterChanged(chip.filter),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color:
                                  theme.colorScheme.primary.withValues(alpha: 0.25),
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
                        chip.icon,
                        size: 16,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        chip.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
