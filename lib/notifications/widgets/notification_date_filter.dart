import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificationDateFilter extends StatefulWidget {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final Function(DateTime?, DateTime?) onDateFilterChanged;
  final VoidCallback onClearFilters;
  final bool hasActiveFilters;

  const NotificationDateFilter({
    super.key,
    this.dateFrom,
    this.dateTo,
    required this.onDateFilterChanged,
    required this.onClearFilters,
    required this.hasActiveFilters,
  });

  @override
  State<NotificationDateFilter> createState() => _NotificationDateFilterState();
}

class _NotificationDateFilterState extends State<NotificationDateFilter> {
  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _updateControllers();
  }

  @override
  void didUpdateWidget(NotificationDateFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateFrom != widget.dateFrom ||
        oldWidget.dateTo != widget.dateTo) {
      _updateControllers();
    }
  }

  void _updateControllers() {
    _fromDateController.text =
        widget.dateFrom != null ? _dateFormat.format(widget.dateFrom!) : '';
    _toDateController.text =
        widget.dateTo != null ? _dateFormat.format(widget.dateTo!) : '';
  }

  @override
  void dispose() {
    _fromDateController.dispose();
    _toDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Khoảng thời gian',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
              if (widget.hasActiveFilters)
                TextButton.icon(
                  onPressed: () {
                    _fromDateController.clear();
                    _toDateController.clear();
                    widget.onClearFilters();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Đặt lại'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DatePill(
                  label: 'Từ ngày',
                  value: _fromDateController.text,
                  isActive: widget.dateFrom != null,
                  onTap: () => _selectDate(context, isFromDate: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DatePill(
                  label: 'Đến ngày',
                  value: _toDateController.text,
                  isActive: widget.dateTo != null,
                  onTap: () => _selectDate(context, isFromDate: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(BuildContext context,
      {required bool isFromDate}) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 1, 1, 1);
    final lastDate = now;

    DateTime? initialDate;
    DateTime? firstSelectableDate;
    DateTime? lastSelectableDate;

    if (isFromDate) {
      initialDate = widget.dateFrom ?? now;
      firstSelectableDate = firstDate;
      lastSelectableDate = widget.dateTo ?? lastDate;
    } else {
      initialDate = widget.dateTo ?? now;
      firstSelectableDate = widget.dateFrom ?? firstDate;
      lastSelectableDate = lastDate;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstSelectableDate,
      lastDate: lastSelectableDate,
      locale: const Locale('vi', 'VN'),
    );

    if (picked != null && mounted) {
      DateTime? newFromDate = widget.dateFrom;
      DateTime? newToDate = widget.dateTo;

      if (isFromDate) {
        newFromDate = picked;
        if (newToDate != null && newFromDate.isAfter(newToDate)) {
          newToDate = newFromDate;
        }
      } else {
        newToDate = picked;
        if (newFromDate != null && newToDate.isBefore(newFromDate)) {
          newFromDate = newToDate;
        }
      }

      widget.onDateFilterChanged(newFromDate, newToDate);
    }
  }
}

class _DatePill extends StatelessWidget {
  final String label;
  final String value;
  final bool isActive;
  final VoidCallback onTap;

  const _DatePill({
    required this.label,
    required this.value,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final display = value.isEmpty ? 'dd/MM/yyyy' : value;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary.withValues(alpha: 0.4)
                : theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    display,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.calendar_today_rounded,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

