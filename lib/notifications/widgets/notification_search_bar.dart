import 'package:flutter/material.dart';

class NotificationSearchBar extends StatefulWidget {
  final String searchQuery;
  final Function(String) onSearchChanged;
  final VoidCallback onClear;

  const NotificationSearchBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClear,
  });

  @override
  State<NotificationSearchBar> createState() => _NotificationSearchBarState();
}

class _NotificationSearchBarState extends State<NotificationSearchBar> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(NotificationSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _controller.text = widget.searchQuery;
      _controller.selection =
          TextSelection.collapsed(offset: widget.searchQuery.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.08),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.search, size: 20),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: widget.onSearchChanged,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm thông báo...',
                  border: InputBorder.none,
                  isDense: true,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            if (widget.searchQuery.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  _controller.clear();
                  widget.onClear();
                },
                tooltip: 'Xóa tìm kiếm',
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

