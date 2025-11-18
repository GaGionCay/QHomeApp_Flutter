import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';
import 'package:dio/dio.dart';

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

    return InkWell(
      onTap: () => _showCardDetail(context, card),
      borderRadius: BorderRadius.circular(24),
      child: _HomeGlassSection(
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
      ),
    );
  }

  void _showCardDetail(BuildContext context, CardRegistrationSummary card) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CardDetailSheet(
        card: card,
        onRefresh: _fetchData,
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

class _CardDetailSheet extends StatefulWidget {
  const _CardDetailSheet({
    required this.card,
    required this.onRefresh,
  });

  final CardRegistrationSummary card;
  final VoidCallback onRefresh;

  @override
  State<_CardDetailSheet> createState() => _CardDetailSheetState();
}

class _CardDetailSheetState extends State<_CardDetailSheet> {
  final ApiClient _apiClient = ApiClient();
  bool _isProcessingPayment = false;
  final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');

  bool _canResumePayment() {
    final paymentStatus = widget.card.paymentStatus?.toUpperCase() ?? '';
    final status = widget.card.status?.toUpperCase() ?? '';
    final cardType = widget.card.cardType.toUpperCase();
    
    // Chỉ cho phép tiếp tục thanh toán nếu:
    // 1. payment_status là UNPAID, PAYMENT_PENDING, hoặc PAYMENT_APPROVAL (cho vehicle)
    // 2. status không phải REJECTED
    // 3. Trong vòng 10 phút từ khi tạo (hoặc updatedAt nếu có)
    final allowedPaymentStatuses = ['UNPAID', 'PAYMENT_PENDING'];
    if (cardType.contains('VEHICLE')) {
      allowedPaymentStatuses.add('PAYMENT_APPROVAL');
    }
    
    if (!allowedPaymentStatuses.contains(paymentStatus)) {
      return false;
    }
    if (status == 'REJECTED') {
      return false;
    }
    
    // Kiểm tra thời gian: trong vòng 10 phút
    final now = DateTime.now();
    final pivot = widget.card.updatedAt ?? widget.card.createdAt;
    if (pivot == null) return false;
    
    final diff = now.difference(pivot);
    return diff.inMinutes <= 10;
  }

  Future<void> _resumePayment() async {
    if (_isProcessingPayment) return;
    
    setState(() => _isProcessingPayment = true);
    
    try {
      final client = await _getServicesCardClient();
      final cardType = widget.card.cardType.toUpperCase();
      
      // Xác định endpoint dựa trên loại thẻ
      String endpoint;
      if (cardType.contains('ELEVATOR')) {
        endpoint = '/elevator-card/${widget.card.id}/resume-payment';
      } else if (cardType.contains('RESIDENT')) {
        endpoint = '/resident-card/${widget.card.id}/resume-payment';
      } else if (cardType.contains('VEHICLE')) {
        endpoint = '/register-service/${widget.card.id}/resume-payment';
      } else {
        throw Exception('Loại thẻ không được hỗ trợ');
      }
      
      final res = await client.post(endpoint);
      
      if (res.statusCode != 200) {
        throw Exception('Không thể tạo liên kết thanh toán');
      }
      
      final paymentUrl = res.data['paymentUrl']?.toString();
      if (paymentUrl == null || paymentUrl.isEmpty) {
        throw Exception('Không nhận được đường dẫn thanh toán');
      }
      
      // Đóng bottom sheet
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // Mở trình duyệt thanh toán
      final uri = Uri.parse(paymentUrl);
      bool launched = false;
      
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final intent = AndroidIntent(
            action: 'action_view',
            data: paymentUrl,
          );
          await intent.launchChooser('Chọn trình duyệt để thanh toán');
          launched = true;
        } catch (e) {
          debugPrint('⚠️ Không thể mở chooser: $e');
        }
      }
      
      if (!launched) {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          launched = true;
        }
      }
      
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể mở trình duyệt thanh toán'),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      // Refresh danh sách sau khi thanh toán
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  Future<Dio> _getServicesCardClient() async {
    final baseUrl = ApiClient.buildServiceBase(port: 8083, path: '/api');
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
    ));
    
    final token = await _apiClient.storage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }
    
    return dio;
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

  Widget _buildDetailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canResume = _canResumePayment();
    
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  // Title
                  Text(
                    widget.card.displayName ?? _cardTypeLabel(widget.card.cardType),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Status chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusChip(
                        label: _approvalStatusLabel(widget.card),
                        color: _approvalStatusColor(theme, widget.card),
                        tone: StatusChipTone.solid,
                      ),
                      if (widget.card.paymentStatus != null)
                        _StatusChip(
                          label: _paymentStatusLabel(widget.card.paymentStatus) ?? '',
                          color: _paymentStatusColor(theme, widget.card.paymentStatus),
                          tone: StatusChipTone.neutral,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Details
                  _buildDetailRow(theme, 'Mã đăng ký', widget.card.id),
                  if (widget.card.apartmentNumber != null && widget.card.apartmentNumber!.isNotEmpty)
                    _buildDetailRow(theme, 'Căn hộ', widget.card.apartmentNumber!),
                  if (widget.card.buildingName != null && widget.card.buildingName!.isNotEmpty)
                    _buildDetailRow(theme, 'Tòa nhà', widget.card.buildingName!),
                  if (widget.card.paymentAmount != null)
                    _buildDetailRow(theme, 'Số tiền', '${widget.card.paymentAmount!.toStringAsFixed(0)} VNĐ'),
                  if (widget.card.createdAt != null)
                    _buildDetailRow(theme, 'Ngày tạo', _dateTimeFmt.format(widget.card.createdAt!.toLocal())),
                  if (widget.card.paymentDate != null)
                    _buildDetailRow(theme, 'Ngày thanh toán', _dateTimeFmt.format(widget.card.paymentDate!.toLocal())),
                  if (widget.card.approvedAt != null)
                    _buildDetailRow(theme, 'Ngày duyệt', _dateTimeFmt.format(widget.card.approvedAt!.toLocal())),
                  if (widget.card.note != null && widget.card.note!.isNotEmpty)
                    _buildDetailRow(theme, 'Ghi chú', widget.card.note!),
                  
                  const SizedBox(height: 24),
                  
                  // Resume payment button (cho cả 3 loại thẻ)
                  if (canResume)
                    FilledButton.icon(
                      onPressed: _isProcessingPayment ? null : _resumePayment,
                      icon: _isProcessingPayment
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.payment),
                      label: Text(_isProcessingPayment ? 'Đang xử lý...' : 'Tiếp tục thanh toán'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  
                  if (canResume)
                    const SizedBox(height: 12),
                  
                  // Info message
                  if (canResume)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Bạn có thể tiếp tục thanh toán trong vòng 10 phút kể từ khi tạo đăng ký.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
