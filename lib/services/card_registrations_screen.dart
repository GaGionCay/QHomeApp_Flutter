import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/api_client.dart';
import '../theme/app_colors.dart';
import '../models/card_registration_summary.dart';
import '../models/unit_info.dart';
import '../services/card_registration_service.dart';

enum _CardCategory { vehicle, resident, elevator }

class CardRegistrationsScreen extends StatefulWidget {
  const CardRegistrationsScreen({
    super.key,
    required this.residentId,
    required this.unitId,
    this.unitDisplayName,
    this.initialCards = const [],
    this.units = const [],
  });

  final String residentId;
  final String unitId;
  final String? unitDisplayName;
  final List<CardRegistrationSummary> initialCards;
  final List<UnitInfo> units;

  @override
  State<CardRegistrationsScreen> createState() =>
      _CardRegistrationsScreenState();
}

class _CardRegistrationsScreenState extends State<CardRegistrationsScreen> {
  static const List<_CardCategory> _categoryOrder = [
    _CardCategory.vehicle,
    _CardCategory.resident,
    _CardCategory.elevator,
  ];

  static const Map<_CardCategory, String> _categoryLabels = {
    _CardCategory.vehicle: 'Thẻ xe',
    _CardCategory.resident: 'Thẻ cư dân',
    _CardCategory.elevator: 'Thẻ thang máy',
  };

  static const Map<_CardCategory, IconData> _categoryIcons = {
    _CardCategory.vehicle: Icons.directions_car_rounded,
    _CardCategory.resident: Icons.badge_outlined,
    _CardCategory.elevator: Icons.elevator,
  };

  static const Map<_CardCategory, String> _categoryTypeCodes = {
    _CardCategory.vehicle: 'VEHICLE_CARD',
    _CardCategory.resident: 'RESIDENT_CARD',
    _CardCategory.elevator: 'ELEVATOR_CARD',
  };

  late final ApiClient _apiClient;
  late final CardRegistrationService _service;

  List<CardRegistrationSummary> _cards = const [];
  bool _isLoading = true;
  String? _error;
  _CardCategory _selectedCategory = _CardCategory.vehicle;

  DateTime? _fromDate;
  DateTime? _toDate;

  final DateFormat _dateFmt = DateFormat('dd/MM/yyyy');
  final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _service = CardRegistrationService(_apiClient);
    _cards = widget.initialCards;
    _isLoading = _cards.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchData());
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await _service.getRegistrations(
        residentId: widget.residentId,
        unitId: widget.unitId,
      );
      if (!mounted) return;
      setState(() {
        _cards = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitLabel = widget.unitDisplayName ??
        widget.units
            .firstWhere(
              (u) => u.id == widget.unitId,
              orElse: () => UnitInfo(id: widget.unitId, code: widget.unitId),
            )
            .displayName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thẻ cư dân & dịch vụ'),
      ),
      body: RefreshIndicator(
        color: theme.colorScheme.primary,
        onRefresh: _fetchData,
        child: _buildContent(theme, unitLabel),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, String unitLabel) {
    if (_isLoading && _cards.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _cards.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          _buildErrorCard(theme, unitLabel),
        ],
      );
    }

    if (_cards.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          _buildDateFilter(context),
          const SizedBox(height: 12),
          _buildEmptyCard(theme, unitLabel),
        ],
      );
    }

    final filteredCards = _filteredCards();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _buildDateFilter(context),
        const SizedBox(height: 12),
        _buildSummaryCard(theme, unitLabel),
        const SizedBox(height: 16),
        _buildCategorySelector(theme),
        const SizedBox(height: 16),
        if (filteredCards.isEmpty)
          _buildEmptyCategoryCard(theme, _selectedCategory)
        else ..._buildGroupedByDay(theme, filteredCards),
        if (_isLoading && filteredCards.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  List<CardRegistrationSummary> _filteredCards() {
    final category = _selectedCategory;
    final filtered = _cards.where((card) {
      if (_categoryOf(card) != category) return false;
      if (_fromDate == null && _toDate == null) return true;

      // Ưu tiên lọc theo paymentDate nếu có, ngược lại theo createdAt
      final DateTime? pivot =
          card.paymentDate ?? card.createdAt ?? card.updatedAt;
      if (pivot == null) return false;

      bool ok = true;
      if (_fromDate != null) {
        final start = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
        ok = ok && !pivot.isBefore(start);
      }
      if (_toDate != null) {
        final end = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59, 999);
        ok = ok && !pivot.isAfter(end);
      }
      return ok;
    }).toList();
    filtered.sort(
      (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
    return filtered;
  }

  List<Widget> _buildGroupedByDay(ThemeData theme, List<CardRegistrationSummary> items) {
    // Group theo ngày dựa trên paymentDate nếu có, ngược lại theo createdAt (hoặc updatedAt)
    final Map<DateTime, List<CardRegistrationSummary>> byDay = {};
    for (final item in items) {
      final pivot = item.paymentDate ?? item.createdAt ?? item.updatedAt;
      if (pivot == null) continue;
      final key = DateTime(pivot.year, pivot.month, pivot.day);
      byDay.putIfAbsent(key, () => []).add(item);
    }

    // Sắp xếp ngày giảm dần
    final dayKeys = byDay.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final List<Widget> widgets = [];
    for (final day in dayKeys) {
      final list = byDay[day]!;
      // Section header
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
          child: Text(
            _humanDayLabel(day),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withOpacity(0.85),
            ),
          ),
        ),
      );
      // Items của ngày
      for (final card in list) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildCardItem(theme, card),
          ),
        );
      }
      widgets.add(const SizedBox(height: 8));
    }

    // Các item không có ngày (hiếm) gom vào cuối
    final noDate = items.where((e) => (e.paymentDate ?? e.createdAt ?? e.updatedAt) == null).toList();
    if (noDate.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
          child: Text(
            'Khác',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withOpacity(0.85),
            ),
          ),
        ),
      );
      for (final card in noDate) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildCardItem(theme, card),
          ),
        );
      }
    }

    return widgets;
  }

  String _humanDayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final labelDate = _dateFmt.format(day);
    if (day == today) return 'Hôm nay ($labelDate)';
    if (day == yesterday) return 'Hôm qua ($labelDate)';
    return labelDate;
  }

  int _countFor(_CardCategory category) {
    return _cards.where((card) => _categoryOf(card) == category).length;
  }

  _CardCategory _categoryOf(CardRegistrationSummary card) {
    final type = card.cardType.toUpperCase();
    if (type.contains('VEHICLE')) {
      return _CardCategory.vehicle;
    }
    if (type.contains('ELEVATOR')) {
      return _CardCategory.elevator;
    }
    if (type.contains('RESIDENT')) {
      return _CardCategory.resident;
    }
    if (type == _categoryTypeCodes[_CardCategory.vehicle]) {
      return _CardCategory.vehicle;
    }
    if (type == _categoryTypeCodes[_CardCategory.elevator]) {
      return _CardCategory.elevator;
    }
    if (type == _categoryTypeCodes[_CardCategory.resident]) {
      return _CardCategory.resident;
    }
    return _CardCategory.resident;
  }

  Widget _buildCategorySelector(ThemeData theme) {
    return Row(
      children: _categoryOrder.map((category) {
        final selected = _selectedCategory == category;
        final count = _countFor(category);
        final label = _categoryLabels[category]!;
        final icon = _categoryIcons[category]!;

        return Expanded(
          child: GestureDetector(
            onTap: () {
              if (_selectedCategory != category) {
                setState(() => _selectedCategory = category);
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary.withOpacity(0.15)
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary.withOpacity(0.35)
                      : theme.colorScheme.outline.withOpacity(0.12),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$label ($count)',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.75),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyCategoryCard(ThemeData theme, _CardCategory category) {
    final label = _categoryLabels[category]!;
    return _HomeGlassSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chưa có $label',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Bạn chưa có đăng ký $label trong danh sách hiện tại. Vui lòng chọn loại thẻ khác hoặc tạo mới từ trang dịch vụ.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme, String unitLabel) {
    final total = _cards.length;
    final pending = _cards.where(_isPendingCard).length;
    final vehicleCount = _countFor(_CardCategory.vehicle);
    final residentCount = _countFor(_CardCategory.resident);
    final elevatorCount = _countFor(_CardCategory.elevator);
    final viewingLabel = _categoryLabels[_selectedCategory]!;
    final viewingCount = _countFor(_selectedCategory);

    final summaryLine =
        'Tổng: $total • Xe: $vehicleCount • Cư dân: $residentCount • Thang máy: $elevatorCount';
    final viewingLine = 'Đang xem: $viewingLabel ($viewingCount)';
    final pendingLine = pending > 0
        ? '$pending thẻ đang xử lý'
        : 'Tất cả thẻ đã được cập nhật trạng thái';

    return _HomeInfoCard(
      leading: Icons.credit_card,
      accent: theme.colorScheme.primary,
      title: 'Đăng ký thẻ tại $unitLabel',
      subtitle: '$summaryLine\n$viewingLine\n$pendingLine',
      trailing: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : null,
    );
  }

  Widget _buildErrorCard(ThemeData theme, String unitLabel) {
    return _HomeGlassSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Không thể tải trạng thái thẻ',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Vui lòng kiểm tra kết nối và thử lại.\n$_error',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.65),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _fetchData,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(ThemeData theme, String unitLabel) {
    return _HomeGlassSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chưa có đăng ký thẻ',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Bạn chưa có đăng ký thẻ cư dân, thang máy hoặc thẻ xe tại $unitLabel.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardItem(ThemeData theme, CardRegistrationSummary card) {
    final icon = _cardTypeIcon(card.cardType);
    final label = _cardTypeLabel(card.cardType);
    final unit = _unitDisplayName(card.unitId);
    final approvalLabel = _approvalStatusLabel(card);
    final approvalColor = _approvalStatusColor(theme, card);
    final paymentLabel = _paymentStatusLabel(card.paymentStatus);
    final paymentColor = _paymentStatusColor(theme, card.paymentStatus);
    final subtitleParts = <String>[];

    if (card.apartmentNumber != null && card.apartmentNumber!.isNotEmpty) {
      subtitleParts.add('Căn hộ ${card.apartmentNumber}');
    }
    if (card.buildingName != null && card.buildingName!.isNotEmpty) {
      subtitleParts.add(card.buildingName!);
    }
    if (card.reference != null && card.reference!.isNotEmpty) {
      subtitleParts.add(card.reference!);
    }
    if (unit != null && unit.isNotEmpty) {
      subtitleParts.add(unit);
    }

    return _HomeGlassSection(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: approvalColor.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: approvalColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.displayName ?? label,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitleParts.join(' • '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                if (card.paymentStatus != null &&
                    card.paymentStatus!.toUpperCase() == 'PAID' &&
                    card.paymentDate != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Thanh toán: ${_dateTimeFmt.format(card.paymentDate!.toLocal())}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                // Hiển thị thời gian admin duyệt khi có approvedAt
                if (card.approvedAt != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.verified, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Duyệt: ${_dateTimeFmt.format(card.approvedAt!.toLocal())}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.62),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                if (card.note != null && card.note!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    card.note!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusChip(
                      label: approvalLabel,
                      color: approvalColor,
                      tone: StatusChipTone.solid,
                    ),
                    if (paymentLabel != null)
                      _StatusChip(
                        label: paymentLabel,
                        color: paymentColor,
                        tone: StatusChipTone.neutral,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilter(BuildContext context) {
    final theme = Theme.of(context);
    final hasFilter = _fromDate != null || _toDate != null;
    return _HomeGlassSection(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final initial = _fromDate ?? DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(2020, 1, 1),
                  lastDate: DateTime(2100, 12, 31),
                );
                if (picked != null) {
                  setState(() {
                    _fromDate = picked;
                    if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
                      _toDate = _fromDate;
                    }
                  });
                }
              },
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(
                _fromDate == null ? 'Từ ngày' : _dateFmt.format(_fromDate!),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                final initial = _toDate ?? _fromDate ?? DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(2020, 1, 1),
                  lastDate: DateTime(2100, 12, 31),
                );
                if (picked != null) {
                  setState(() {
                    _toDate = picked;
                    if (_fromDate != null && _toDate!.isBefore(_fromDate!)) {
                      _fromDate = _toDate;
                    }
                  });
                }
              },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(
                _toDate == null ? 'Đến ngày' : _dateFmt.format(_toDate!),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (hasFilter)
            IconButton(
              tooltip: 'Xóa lọc',
              onPressed: () {
                setState(() {
                  _fromDate = null;
                  _toDate = null;
                });
              },
              icon: Icon(Icons.clear, color: theme.colorScheme.error),
            ),
        ],
      ),
    );
  }

  bool _isPendingCard(CardRegistrationSummary card) {
    final status = (card.status ?? '').toUpperCase();
    if (status.isNotEmpty) {
      if (_approvedStatuses.contains(status)) {
        return false;
      }
      if (_terminalStatuses.contains(status)) {
        return false;
      }
      return true;
    }

    final payment = (card.paymentStatus ?? '').toUpperCase();
    if (payment == 'PAID') {
      return false;
    }
    return payment.isNotEmpty;
  }

  String? _paymentStatusLabel(String? paymentStatus) {
    final normalized = (paymentStatus ?? '').toUpperCase();
    return switch (normalized) {
      'PAID' => 'Đã thanh toán',
      'PAYMENT_PENDING' => 'Thanh toán đang xử lý',
      'UNPAID' => 'Chưa thanh toán',
      'PENDING' => 'Thanh toán đang chờ',
      _ => null,
    };
  }

  String _approvalStatusLabel(CardRegistrationSummary card) {
    final status = (card.status ?? '').toUpperCase();
    switch (status) {
      case 'COMPLETED':
      case 'APPROVED':
      case 'ACTIVE':
        return 'Đã duyệt';
      case 'ISSUED':
        return 'Đã phát hành';
      case 'READY_FOR_PAYMENT':
        return 'Chờ thanh toán';
      case 'PAYMENT_PENDING':
        return 'Thanh toán đang xử lý';
      case 'PROCESSING':
      case 'IN_PROGRESS':
        return 'Đang xử lý';
      case 'PENDING':
      case 'REVIEW_PENDING':
        return 'Chờ duyệt';
      case 'REJECTED':
        return 'Bị từ chối';
      case 'CANCELLED':
      case 'VOID':
        return 'Đã hủy';
      default:
        return status.isEmpty ? 'Không xác định' : status;
    }
  }

  // _isApproved removed: now we rely solely on approvedAt presence for display

  Color _approvalStatusColor(ThemeData theme, CardRegistrationSummary card) {
    final status = (card.status ?? '').toUpperCase();
    switch (status) {
      case 'COMPLETED':
      case 'APPROVED':
      case 'ACTIVE':
      case 'ISSUED':
        return AppColors.success;
      case 'READY_FOR_PAYMENT':
        return theme.colorScheme.error;
      case 'PAYMENT_PENDING':
        return AppColors.warning;
      case 'PROCESSING':
      case 'IN_PROGRESS':
        return AppColors.warning;
      case 'PENDING':
      case 'REVIEW_PENDING':
        return AppColors.warning;
      case 'REJECTED':
        return theme.colorScheme.error;
      case 'CANCELLED':
      case 'VOID':
        return theme.colorScheme.outline;
      default:
        return theme.colorScheme.primary;
    }
  }

  Color _paymentStatusColor(ThemeData theme, String? paymentStatus) {
    final normalized = (paymentStatus ?? '').toUpperCase();
    switch (normalized) {
      case 'PAID':
        return AppColors.success;
      case 'PAYMENT_PENDING':
      case 'PENDING':
        return AppColors.warning;
      case 'UNPAID':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.primary.withOpacity(0.6);
    }
  }

  static const Set<String> _approvedStatuses = {
    'COMPLETED',
    'APPROVED',
    'ACTIVE',
    'ISSUED',
  };

  static const Set<String> _terminalStatuses = {
    'REJECTED',
    'CANCELLED',
    'VOID',
  };

  IconData _cardTypeIcon(String? type) {
    switch (type?.toUpperCase()) {
      case 'RESIDENT_CARD':
        return Icons.badge_outlined;
      case 'ELEVATOR_CARD':
        return Icons.elevator;
      case 'VEHICLE_CARD':
        return Icons.directions_car_rounded;
      default:
        return Icons.credit_card;
    }
  }

  String _cardTypeLabel(String? type) {
    switch (type?.toUpperCase()) {
      case 'RESIDENT_CARD':
        return 'Thẻ cư dân';
      case 'ELEVATOR_CARD':
        return 'Thẻ thang máy';
      case 'VEHICLE_CARD':
        return 'Thẻ xe';
      default:
        return 'Thẻ cư dân';
    }
  }

  String? _unitDisplayName(String? unitId) {
    if (unitId == null || unitId.isEmpty) return null;
    for (final unit in widget.units) {
      if (unit.id == unitId) {
        return unit.displayName;
      }
    }
    return null;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    this.tone = StatusChipTone.solid,
  });

  final String label;
  final Color color;
  final StatusChipTone tone;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(14);
    final background = switch (tone) {
      StatusChipTone.solid => color.withOpacity(0.16),
      StatusChipTone.neutral => color.withOpacity(0.1),
    };
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius,
        border: tone == StatusChipTone.neutral
            ? Border.all(color: color.withOpacity(0.3))
            : null,
      ),
      child: Text(label, style: textStyle),
    );
  }
}

enum StatusChipTone { solid, neutral }

class _HomeInfoCard extends StatelessWidget {
  const _HomeInfoCard({
    required this.leading,
    required this.accent,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData leading;
  final Color accent;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _HomeGlassSection(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(leading, color: accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _HomeGlassSection extends StatelessWidget {
  const _HomeGlassSection({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(24);
    final theme = Theme.of(context);
    final gradient = theme.brightness == Brightness.dark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: borderRadius,
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.08),
            ),
            boxShadow: AppColors.subtleShadow,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
