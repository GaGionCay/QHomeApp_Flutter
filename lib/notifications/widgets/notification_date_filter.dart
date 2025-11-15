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
    if (oldWidget.dateFrom != widget.dateFrom || oldWidget.dateTo != widget.dateTo) {
      _updateControllers();
    }
  }

  void _updateControllers() {
    _fromDateController.text = widget.dateFrom != null ? _dateFormat.format(widget.dateFrom!) : '';
    _toDateController.text = widget.dateTo != null ? _dateFormat.format(widget.dateTo!) : '';
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _DateInputField(
                  controller: _fromDateController,
                  label: 'Từ ngày',
                  hint: 'dd/MM/yyyy',
                  onTap: () => _selectDate(context, isFromDate: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateInputField(
                  controller: _toDateController,
                  label: 'Đến ngày',
                  hint: 'dd/MM/yyyy',
                  onTap: () => _selectDate(context, isFromDate: false),
                ),
              ),
              if (widget.hasActiveFilters) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _fromDateController.clear();
                    _toDateController.clear();
                    widget.onClearFilters();
                  },
                  tooltip: 'Xóa bộ lọc',
                  color: theme.colorScheme.error,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, {required bool isFromDate}) async {
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

class _DateInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback onTap;

  const _DateInputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: TextField(
        controller: controller,
        enabled: false,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: const Icon(Icons.calendar_today, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          filled: true,
          fillColor: theme.colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          labelStyle: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 13,
          ),
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
