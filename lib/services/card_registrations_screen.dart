import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/api_client.dart';
import '../theme/app_colors.dart';
import '../models/card_registration_summary.dart';
import '../models/unit_info.dart';
import '../services/card_registration_service.dart';

enum _CardCategory { vehicle, resident, elevator }

enum _StatusFilter { all, approved, paid, pending }

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

  static const String _statusFilterPrefKey = 'card_registrations_status_filter';

  static const Map<_StatusFilter, String> _statusFilterLabels = {
    _StatusFilter.all: 'Tất cả',
    _StatusFilter.approved: 'Đã duyệt',
    _StatusFilter.paid: 'Đã thanh toán',
    _StatusFilter.pending: 'Chờ xử lý',
  };

  late final ApiClient _apiClient;
  late final CardRegistrationService _service;

  List<CardRegistrationSummary> _cards = const [];
  bool _isLoading = true;
  String? _error;
  _CardCategory _selectedCategory = _CardCategory.resident;
  _StatusFilter _statusFilter = _StatusFilter.all;

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
    _loadStatusFilterPreference();
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
        const SizedBox(height: 12),
        _buildStatusFilter(theme),
        const SizedBox(height: 16),
        if (filteredCards.isEmpty)
          _buildEmptyFilteredState(theme)
        else
          ..._buildGroupedByDay(theme, filteredCards),
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
      if (!_matchesStatusFilter(card)) return false;
      if (_fromDate == null && _toDate == null) return true;

      // Ưu tiên lọc theo paymentDate nếu có, ngược lại theo createdAt
      final DateTime? pivot =
          card.paymentDate ?? card.createdAt ?? card.updatedAt;
      if (pivot == null) return false;

      bool ok = true;
      if (_fromDate != null) {
        final start =
            DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
        ok = ok && !pivot.isBefore(start);
      }
      if (_toDate != null) {
        final end = DateTime(
            _toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59, 999);
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

  Future<void> _loadStatusFilterPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_statusFilterPrefKey);
      final filter = _statusFilterFromStorage(stored);
      if (!mounted || filter == _statusFilter) return;
      setState(() => _statusFilter = filter);
    } catch (e) {
      debugPrint('⚠️ [CardRegistrations] Không thể tải bộ lọc trạng thái: $e');
    }
  }

  Future<void> _saveStatusFilterPreference(_StatusFilter filter) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_statusFilterPrefKey, filter.name);
    } catch (e) {
      debugPrint('⚠️ [CardRegistrations] Không thể lưu bộ lọc trạng thái: $e');
    }
  }

  _StatusFilter _statusFilterFromStorage(String? value) {
    if (value == null || value.isEmpty) {
      return _StatusFilter.all;
    }
    return _StatusFilter.values.firstWhere(
      (element) => element.name == value,
      orElse: () => _StatusFilter.all,
    );
  }

  List<Widget> _buildGroupedByDay(
      ThemeData theme, List<CardRegistrationSummary> items) {
    // Group theo ngày dựa trên paymentDate nếu có, ngược lại theo createdAt (hoặc updatedAt)
    final Map<DateTime, List<CardRegistrationSummary>> byDay = {};
    for (final item in items) {
      final pivot = item.paymentDate ?? item.createdAt ?? item.updatedAt;
      if (pivot == null) continue;
      final key = DateTime(pivot.year, pivot.month, pivot.day);
      byDay.putIfAbsent(key, () => []).add(item);
    }

    // Sắp xếp ngày giảm dần
    final dayKeys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
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
    final noDate = items
        .where((e) => (e.paymentDate ?? e.createdAt ?? e.updatedAt) == null)
        .toList();
    if (noDate.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
          child: Text(
            'Khác',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
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

  bool _matchesStatusFilter(CardRegistrationSummary card) {
    switch (_statusFilter) {
      case _StatusFilter.all:
        return true;
      case _StatusFilter.approved:
        return _isApprovedCard(card);
      case _StatusFilter.paid:
        return _isPaidCard(card);
      case _StatusFilter.pending:
        return _isPendingCard(card);
    }
  }

  bool _isApprovedCard(CardRegistrationSummary card) {
    final status = card.status?.trim().toUpperCase();
    if (status == null || status.isEmpty) return false;
    return _approvedStatuses.contains(status);
  }

  bool _isPaidCard(CardRegistrationSummary card) {
    final paymentStatus = card.paymentStatus?.trim().toUpperCase();
    if (paymentStatus == 'PAID') {
      return true;
    }
    // Paid filter should include "chờ duyệt" items that have been paid
    final status = card.status?.trim().toUpperCase();
    if ((status == 'PENDING' || status == 'REVIEW_PENDING') &&
        paymentStatus == 'PAID') {
      return true;
    }
    return false;
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
                    ? theme.colorScheme.primary.withValues(alpha: 0.15)
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.35)
                      : theme.colorScheme.outline.withValues(alpha: 0.12),
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
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$label ($count)',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.75),
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

  Widget _buildStatusFilter(ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _StatusFilter.values.map((filter) {
        final selected = _statusFilter == filter;
        final label = _statusFilterLabels[filter]!;
        return ChoiceChip(
          label: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          selected: selected,
          onSelected: (_) => _onStatusFilterChanged(filter),
          selectedColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          labelStyle: theme.textTheme.labelMedium?.copyWith(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.8),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.4)
                  : theme.colorScheme.outline.withValues(alpha: 0.15),
            ),
          ),
          backgroundColor: theme.colorScheme.surface,
        );
      }).toList(),
    );
  }

  void _onStatusFilterChanged(_StatusFilter filter) {
    if (_statusFilter == filter) return;
    setState(() => _statusFilter = filter);
    unawaited(_saveStatusFilterPreference(filter));
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFilteredState(ThemeData theme) {
    if (_statusFilter == _StatusFilter.all) {
      return _buildEmptyCategoryCard(theme, _selectedCategory);
    }
    return _buildEmptyFilterCard(theme, _selectedCategory, _statusFilter);
  }

  Widget _buildEmptyFilterCard(
      ThemeData theme, _CardCategory category, _StatusFilter filter) {
    final categoryLabel = _categoryLabels[category]!;
    final filterLabel = _statusFilterLabels[filter]!;

    String title;
    String description;

    switch (filter) {
      case _StatusFilter.approved:
        title = 'Chưa có thẻ đã duyệt';
        description =
            'Hiện chưa có $categoryLabel nào đã được duyệt. Khi thẻ được admin phê duyệt, chúng sẽ hiển thị ở đây.';
      case _StatusFilter.paid:
        title = 'Chưa có thẻ đã thanh toán';
        description =
            'Bạn chưa có $categoryLabel nào đã thanh toán trong bộ lọc hiện tại. Vui lòng kiểm tra lại sau khi hoàn tất thanh toán.';
      case _StatusFilter.pending:
        title = 'Không có thẻ chờ xử lý';
        description =
            'Tất cả $categoryLabel của bạn đều đã được cập nhật trạng thái. Các thẻ đang chờ duyệt hoặc chờ thanh toán sẽ xuất hiện tại đây.';
      case _StatusFilter.all:
        title = 'Không có dữ liệu';
        description =
            'Không có $categoryLabel nào trong danh sách theo điều kiện lọc hiện tại.';
    }

    return _HomeGlassSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Bộ lọc: $filterLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontStyle: FontStyle.italic,
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardItem(ThemeData theme, CardRegistrationSummary card) {
    final icon = _cardTypeIcon(card.cardType);
    final label = _cardTypeLabel(card.cardType);
    final approvalLabel = _approvalStatusLabel(card);
    final approvalColor = _approvalStatusColor(theme, card);
    final paymentLabel = _paymentStatusLabel(card.paymentStatus);
    final paymentColor = _paymentStatusColor(theme, card.paymentStatus);
    final subtitleParts = <String>[];

    // Chỉ hiển thị Căn hộ và Tòa nhà
    if (card.apartmentNumber != null && card.apartmentNumber!.isNotEmpty) {
      subtitleParts.add('Căn hộ ${card.apartmentNumber}');
    }
    if (card.buildingName != null && card.buildingName!.isNotEmpty) {
      subtitleParts.add('Tòa ${card.buildingName}');
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
                color: approvalColor.withValues(alpha: 0.16),
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
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                            color:
                                theme.colorScheme.onSurface.withValues(alpha: 0.62),
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
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
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
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {},
                  child: _CardDetailSheet(
                    card: card,
                    onRefresh: _fetchData,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
    // Pending filter: statuses explicitly waiting for approval/review/payment
    if (status == 'PENDING' ||
        status == 'REVIEW_PENDING' ||
        status == 'READY_FOR_PAYMENT' ||
        status == 'PAYMENT_PENDING' ||
        status == 'PROCESSING' ||
        status == 'IN_PROGRESS') {
      return true;
    }
    // fallback: if status is empty but payment indicates still not done
    final payment = (card.paymentStatus ?? '').toUpperCase();
    if (status.isEmpty && payment.isNotEmpty && payment != 'PAID') {
      return true;
    }
    return false;
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
      case 'NEEDS_RENEWAL':
        return 'Cần gia hạn';
      case 'SUSPENDED':
        return 'Tạm ngưng';
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
      case 'NEEDS_RENEWAL':
        return AppColors.warning; // Màu vàng để nhắc người dùng
      case 'SUSPENDED':
        return theme.colorScheme.error; // Màu đỏ để cảnh báo
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
        return theme.colorScheme.primary.withValues(alpha: 0.6);
    }
  }

  static const Set<String> _approvedStatuses = {
    'COMPLETED',
    'APPROVED',
    'ACTIVE',
    'ISSUED',
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
      StatusChipTone.solid => color.withValues(alpha: 0.16),
      StatusChipTone.neutral => color.withValues(alpha: 0.1),
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
            ? Border.all(color: color.withValues(alpha: 0.3))
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
              color: accent.withValues(alpha: 0.16),
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
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
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
              color: theme.colorScheme.outline.withValues(alpha: 0.08),
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
  bool _isCancelling = false;
  bool _isRequestingReplacement = false;
  final DateFormat _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
  
  // Images for vehicle card
  List<String>? _vehicleImages;
  bool _isLoadingImages = false;

  bool _canResumePayment() {
    final paymentStatus = widget.card.paymentStatus?.trim().toUpperCase() ?? '';
    final status = widget.card.status?.trim().toUpperCase() ?? '';
    final cardType = widget.card.cardType.trim().toUpperCase();

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
    if (status == 'REJECTED' || status == 'CANCELLED') {
      return false;
    }

    // Kiểm tra thời gian: trong vòng 10 phút
    final now = DateTime.now();
    final pivot = widget.card.updatedAt ?? widget.card.createdAt;
    if (pivot == null) return false;

    final diff = now.difference(pivot);
    return diff.inMinutes <= 10;
  }

  bool _canRenewCard() {
    final status = widget.card.status?.trim().toUpperCase() ?? '';
    final paymentStatus = widget.card.paymentStatus?.trim().toUpperCase() ?? '';
    
    // Chỉ cho phép gia hạn nếu:
    // 1. status = NEEDS_RENEWAL (cần gia hạn sau 30 ngày)
    // 2. paymentStatus = PAID (đã thanh toán trước đó)
    // 3. Có approvedAt (đã được admin approve)
    if (status != 'NEEDS_RENEWAL' && status != 'SUSPENDED') {
      return false;
    }
    if (paymentStatus != 'PAID') {
      return false;
    }
    if (widget.card.approvedAt == null) {
      return false;
    }
    
    return true;
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

      // Refresh danh sách sau khi tạo link thanh toán
      widget.onRefresh();
      if (mounted) {
        Navigator.of(context).pop();
      }
      await _launchPaymentUrl(paymentUrl);
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

  Future<void> _renewCard() async {
    if (_isProcessingPayment) return;

    setState(() => _isProcessingPayment = true);

    try {
      final client = await _getServicesCardClient();
      final cardType = widget.card.cardType.toUpperCase();

      // Xác định endpoint dựa trên loại thẻ (dùng resume-payment endpoint cho gia hạn)
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
        throw Exception('Không thể tạo liên kết thanh toán gia hạn');
      }

      final paymentUrl = res.data['paymentUrl']?.toString();
      if (paymentUrl == null || paymentUrl.isEmpty) {
        throw Exception('Không nhận được đường dẫn thanh toán');
      }

      // Refresh danh sách sau khi tạo link thanh toán
      widget.onRefresh();
      if (mounted) {
        Navigator.of(context).pop();
      }
      await _launchPaymentUrl(paymentUrl);
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
      connectTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
      receiveTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
    ));

    final token = await _apiClient.storage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }

    return dio;
  }

  bool _canRequestReplacement() {
    final cardType = widget.card.cardType.trim().toUpperCase();
    final status = widget.card.status?.trim().toUpperCase() ?? '';
    final paymentStatus = widget.card.paymentStatus?.trim().toUpperCase() ?? '';

    if (status != 'CANCELLED') return false;
    if (paymentStatus != 'PAID') return false;

    return cardType.contains('RESIDENT') ||
        cardType.contains('ELEVATOR') ||
        cardType.contains('VEHICLE');
  }

  Future<void> _requestReplacement() async {
    if (_isRequestingReplacement) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Yêu cầu cấp lại thẻ'),
        content: const Text(
          'Hệ thống sẽ sử dụng lại toàn bộ thông tin của thẻ này để tạo yêu cầu cấp lại mới. Bạn chỉ cần thanh toán để hoàn tất.\n\nBạn có muốn tiếp tục?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tiếp tục', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isRequestingReplacement = true);

    try {
      final cardType = widget.card.cardType.trim().toUpperCase();
      if (cardType.contains('RESIDENT')) {
        await _requestReplacementResident();
      } else if (cardType.contains('ELEVATOR')) {
        await _requestReplacementElevator();
      } else if (cardType.contains('VEHICLE')) {
        await _requestReplacementVehicle();
      } else {
        throw Exception('Loại thẻ không hỗ trợ cấp lại');
      }
    } catch (e) {
      _showErrorSnackbar(
        error: e,
        fallback: 'Không thể cấp lại thẻ',
      );
    } finally {
      if (mounted) {
        setState(() => _isRequestingReplacement = false);
      }
    }
  }

  bool _canCancelCard() {
    final status = widget.card.status?.trim().toUpperCase() ?? '';
    if (status == 'CANCELLED' || status == 'REJECTED' || status == 'VOID') {
      return false;
    }
    final paymentStatus = widget.card.paymentStatus?.trim().toUpperCase() ?? '';
    return paymentStatus == 'PAID';
  }

  Future<void> _cancelCard() async {
    if (_isCancelling) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hủy thẻ hiện tại'),
        content: const Text(
          'Sau khi hủy, thẻ này sẽ bị vô hiệu hóa hoàn toàn và không thể sử dụng nữa. Bạn có chắc chắn muốn tiếp tục?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Giữ lại'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hủy thẻ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isCancelling = true);

    try {
      final client = await _getServicesCardClient();
      final cardType = widget.card.cardType.trim().toUpperCase();
      String endpoint;
      if (cardType.contains('ELEVATOR')) {
        endpoint = '/elevator-card/${widget.card.id}/cancel';
      } else if (cardType.contains('RESIDENT')) {
        endpoint = '/resident-card/${widget.card.id}/cancel';
      } else if (cardType.contains('VEHICLE')) {
        endpoint = '/register-service/${widget.card.id}/cancel';
      } else {
        throw Exception('Loại thẻ không hỗ trợ hủy');
      }

      final res = await client.delete(endpoint);
      if (res.statusCode != null &&
          res.statusCode! >= 200 &&
          res.statusCode! < 300) {
        widget.onRefresh();
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã hủy thẻ. Bạn có thể đăng ký thẻ mới.'),
            ),
          );
        }
      } else {
        throw Exception('Không thể hủy thẻ (mã lỗi ${res.statusCode})');
      }
    } catch (e) {
      _showErrorSnackbar(
        error: e,
        fallback: 'Không thể hủy thẻ',
      );
    } finally {
      if (mounted) {
        setState(() => _isCancelling = false);
      }
    }
  }

  Future<void> _requestReplacementResident() async {
    final client = await _getServicesCardClient();
    final detailRes = await client.get('/resident-card/${widget.card.id}');

    if (detailRes.statusCode != 200 || detailRes.data is! Map) {
      throw Exception('Không thể lấy thông tin thẻ gốc');
    }

    final detail = Map<String, dynamic>.from(detailRes.data as Map);
    final unitId = detail['unitId'] ?? widget.card.unitId;
    final residentId = detail['residentId'] ?? widget.card.residentId;
    final fullName =
        detail['fullName'] ?? detail['displayName'] ?? widget.card.displayName;
    final apartmentNumber =
        detail['apartmentNumber'] ?? widget.card.apartmentNumber;
    final buildingName = detail['buildingName'] ?? widget.card.buildingName;
    final citizenId = detail['citizenId'];
    final phoneNumber = detail['phoneNumber'];

    final missing = <String>[];
    if (unitId == null || unitId.toString().isEmpty) missing.add('căn hộ');
    if (residentId == null || residentId.toString().isEmpty) {
      missing.add('cư dân');
    }
    if (fullName == null || fullName.toString().isEmpty) missing.add('họ tên');
    if (apartmentNumber == null || apartmentNumber.toString().isEmpty) {
      missing.add('số căn hộ');
    }
    if (buildingName == null || buildingName.toString().isEmpty) {
      missing.add('tòa nhà');
    }
    if (citizenId == null || citizenId.toString().isEmpty) {
      missing.add('CCCD/CMND');
    }
    if (phoneNumber == null || phoneNumber.toString().isEmpty) {
      missing.add('số điện thoại');
    }

    if (missing.isNotEmpty) {
      throw Exception('Thiếu thông tin bắt buộc: ${missing.join(', ')}');
    }

    final payload = {
      'unitId': unitId,
      'residentId': residentId,
      'requestType': 'REPLACE_CARD',
      'fullName': fullName,
      'apartmentNumber': apartmentNumber,
      'buildingName': buildingName,
      'citizenId': citizenId,
      'phoneNumber': phoneNumber,
      'note': _buildReplacementNote(detail['note']),
    };

    final response =
        await client.post('/resident-card/vnpay-url', data: payload);
    if (response.statusCode != 200 || response.data is! Map) {
      throw Exception('Không thể khởi tạo yêu cầu cấp lại');
    }

    final data = response.data as Map;
    final paymentUrl = data['paymentUrl']?.toString();

    if (paymentUrl == null || paymentUrl.isEmpty) {
      throw Exception('Thiếu thông tin thanh toán cho yêu cầu cấp lại');
    }

    widget.onRefresh();
    if (mounted) {
      Navigator.of(context).pop();
    }
    await _launchPaymentUrl(paymentUrl);
  }

  Future<void> _requestReplacementElevator() async {
    final client = await _getServicesCardClient();
    final detailRes = await client.get('/elevator-card/${widget.card.id}');

    if (detailRes.statusCode != 200 || detailRes.data is! Map) {
      throw Exception('Không thể lấy thông tin thẻ gốc');
    }

    final detail = Map<String, dynamic>.from(detailRes.data as Map);
    final unitId = detail['unitId'] ?? widget.card.unitId;
    final residentId = detail['residentId'] ?? widget.card.residentId;
    final apartmentNumber =
        detail['apartmentNumber'] ?? widget.card.apartmentNumber;
    final buildingName = detail['buildingName'] ?? widget.card.buildingName;
    final phoneNumber = detail['phoneNumber'];

    final missing = <String>[];
    if (unitId == null || unitId.toString().isEmpty) missing.add('căn hộ');
    if (residentId == null || residentId.toString().isEmpty) {
      missing.add('cư dân');
    }
    if (apartmentNumber == null || apartmentNumber.toString().isEmpty) {
      missing.add('số căn hộ');
    }
    if (buildingName == null || buildingName.toString().isEmpty) {
      missing.add('tòa nhà');
    }
    if (phoneNumber == null || phoneNumber.toString().isEmpty) {
      missing.add('số điện thoại');
    }

    if (missing.isNotEmpty) {
      throw Exception('Thiếu thông tin bắt buộc: ${missing.join(', ')}');
    }

    final payload = {
      'unitId': unitId,
      'residentId': residentId,
      'requestType': 'REPLACE_CARD',
      'apartmentNumber': apartmentNumber,
      'buildingName': buildingName,
      'phoneNumber': phoneNumber,
      'note': _buildReplacementNote(detail['note']),
    };

    final response =
        await client.post('/elevator-card/vnpay-url', data: payload);
    if (response.statusCode != 200 || response.data is! Map) {
      throw Exception('Không thể khởi tạo yêu cầu cấp lại');
    }

    final data = response.data as Map;
    final paymentUrl = data['paymentUrl']?.toString();

    if (paymentUrl == null || paymentUrl.isEmpty) {
      throw Exception('Thiếu thông tin thanh toán cho yêu cầu cấp lại');
    }

    widget.onRefresh();
    if (mounted) {
      Navigator.of(context).pop();
    }
    await _launchPaymentUrl(paymentUrl);
  }

  Future<void> _requestReplacementVehicle() async {
    final client = await _getServicesCardClient();
    final detailRes = await client.get('/register-service/${widget.card.id}');

    if (detailRes.statusCode != 200 || detailRes.data is! Map) {
      throw Exception('Không thể lấy thông tin thẻ gốc');
    }

    final detail = Map<String, dynamic>.from(detailRes.data as Map);
    final unitId = detail['unitId'] ?? widget.card.unitId;
    final serviceType = detail['serviceType'] ?? 'VEHICLE_REGISTRATION';
    final vehicleType = detail['vehicleType'];
    final licensePlate = detail['licensePlate'];
    final vehicleBrand = detail['vehicleBrand'];
    final vehicleColor = detail['vehicleColor'];
    final apartmentNumber =
        detail['apartmentNumber'] ?? widget.card.apartmentNumber;
    final buildingName = detail['buildingName'] ?? widget.card.buildingName;
    final images = (detail['images'] as List?)
        ?.map((img) => (img as Map?)?['imageUrl']?.toString())
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList();

    final missing = <String>[];
    if (unitId == null || unitId.toString().isEmpty) missing.add('căn hộ');
    if (licensePlate == null || licensePlate.toString().isEmpty) {
      missing.add('biển số xe');
    }
    if (vehicleType == null || vehicleType.toString().isEmpty) {
      missing.add('loại phương tiện');
    }

    if (missing.isNotEmpty) {
      throw Exception('Thiếu thông tin bắt buộc: ${missing.join(', ')}');
    }

    final payload = {
      'serviceType': serviceType,
      'requestType': 'REPLACE_CARD',
      'note': _buildReplacementNote(detail['note']),
      'unitId': unitId,
      'vehicleType': vehicleType,
      'licensePlate': licensePlate,
      'vehicleBrand': vehicleBrand,
      'vehicleColor': vehicleColor,
      'apartmentNumber': apartmentNumber,
      'buildingName': buildingName,
      if (images != null && images.isNotEmpty) 'imageUrls': images,
    };

    final response =
        await client.post('/register-service/vnpay-url', data: payload);
    if (response.statusCode != 200 || response.data is! Map) {
      throw Exception('Không thể khởi tạo yêu cầu cấp lại');
    }

    final data = response.data as Map;
    final paymentUrl = data['paymentUrl']?.toString();

    if (paymentUrl == null || paymentUrl.isEmpty) {
      throw Exception('Thiếu thông tin thanh toán cho yêu cầu cấp lại');
    }

    widget.onRefresh();
    if (mounted) {
      Navigator.of(context).pop();
    }
    await _launchPaymentUrl(paymentUrl);
  }

  String _buildReplacementNote(dynamic _) =>
      'Yêu cầu cấp lại từ thẻ ${widget.card.id}';

  Future<void> _launchPaymentUrl(String paymentUrl) async {
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

    if (!launched && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      launched = true;
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể mở trình duyệt thanh toán'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showErrorSnackbar({required Object error, required String fallback}) {
    final message = _extractErrorMessage(error, fallback);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _extractErrorMessage(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map &&
          data['message'] is String &&
          data['message'].toString().isNotEmpty) {
        debugPrint(
            '❌ DioException ${error.response?.statusCode}: ${data['message']}');
        return data['message'].toString();
      }
      if (error.message != null && error.message!.isNotEmpty) {
        debugPrint(
            '❌ DioException ${error.response?.statusCode}: ${error.message}');
        return error.message!;
      }
      debugPrint(
          '❌ DioException ${error.response?.statusCode}: ${error.response?.data}');
      return fallback;
    }
    debugPrint('❌ Error: $error');
    return fallback;
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
      case 'NEEDS_RENEWAL':
        return 'Cần gia hạn';
      case 'SUSPENDED':
        return 'Tạm ngưng';
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
      case 'NEEDS_RENEWAL':
        return AppColors.warning; // Màu vàng để nhắc người dùng
      case 'SUSPENDED':
        return theme.colorScheme.error; // Màu đỏ để cảnh báo
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
        return theme.colorScheme.primary.withValues(alpha: 0.6);
    }
  }

  String _formatVnd(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      final remaining = digits.length - i - 1;
      if (remaining % 3 == 0 && remaining != 0) {
        buffer.write('.');
      }
    }
    return '${buffer.toString()} VNĐ';
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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
  void initState() {
    super.initState();
    // Fetch images for vehicle card
    if (widget.card.cardType.toUpperCase().contains('VEHICLE')) {
      _loadVehicleImages();
    }
  }

  Future<void> _loadVehicleImages() async {
    if (_isLoadingImages) return;
    
    setState(() => _isLoadingImages = true);
    
    try {
      final client = await _getServicesCardClient();
      final detailRes = await client.get('/register-service/${widget.card.id}');
      
      if (detailRes.statusCode == 200 && detailRes.data is Map) {
        final detail = Map<String, dynamic>.from(detailRes.data as Map);
        final images = (detail['images'] as List?)
            ?.map((img) => (img as Map?)?['imageUrl']?.toString())
            .whereType<String>()
            .where((url) => url.isNotEmpty)
            .toList();
        
        if (mounted) {
          setState(() {
            _vehicleImages = images;
            _isLoadingImages = false;
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error loading vehicle images: $e');
      if (mounted) {
        setState(() {
          _isLoadingImages = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canResume = _canResumePayment();
    final canRenew = _canRenewCard();
    final canRequestReplacement = _canRequestReplacement();
    final canCancel = _canCancelCard();
    final isVehicleCard = widget.card.cardType.toUpperCase().contains('VEHICLE');

    return DraggableScrollableSheet(
      expand: false,
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
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
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
                    widget.card.displayName ??
                        _cardTypeLabel(widget.card.cardType),
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
                          label:
                              _paymentStatusLabel(widget.card.paymentStatus) ??
                                  '',
                          color: _paymentStatusColor(
                              theme, widget.card.paymentStatus),
                          tone: StatusChipTone.neutral,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Details
                  _buildDetailRow(theme, 'Mã đăng ký', widget.card.id),
                  if (widget.card.apartmentNumber != null &&
                      widget.card.apartmentNumber!.isNotEmpty)
                    _buildDetailRow(
                        theme, 'Căn hộ', widget.card.apartmentNumber!),
                  if (widget.card.buildingName != null &&
                      widget.card.buildingName!.isNotEmpty)
                    _buildDetailRow(
                        theme, 'Tòa nhà', widget.card.buildingName!),
                  if (widget.card.paymentAmount != null)
                    _buildDetailRow(theme, 'Số tiền',
                        _formatVnd(widget.card.paymentAmount!.toInt())),
                  if (widget.card.createdAt != null)
                    _buildDetailRow(theme, 'Ngày tạo',
                        _dateTimeFmt.format(widget.card.createdAt!.toLocal())),
                  if (widget.card.paymentDate != null)
                    _buildDetailRow(
                        theme,
                        'Ngày thanh toán',
                        _dateTimeFmt
                            .format(widget.card.paymentDate!.toLocal())),
                  if (widget.card.approvedAt != null)
                    _buildDetailRow(theme, 'Ngày duyệt',
                        _dateTimeFmt.format(widget.card.approvedAt!.toLocal())),
                  if (widget.card.note != null && widget.card.note!.isNotEmpty)
                    _buildDetailRow(theme, 'Ghi chú', widget.card.note!),

                  // Vehicle images section
                  if (isVehicleCard) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Ảnh đăng ký',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isLoadingImages)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_vehicleImages != null && _vehicleImages!.isNotEmpty)
                      _buildImageGrid(theme, _vehicleImages!)
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'Không có ảnh',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                  ],

                  const SizedBox(height: 24),

                  // Renew card button (khi thẻ cần gia hạn)
                  if (canRenew)
                    FilledButton.icon(
                      onPressed: _isProcessingPayment ? null : _renewCard,
                      icon: _isProcessingPayment
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_isProcessingPayment
                          ? 'Đang xử lý...'
                          : 'Gia hạn thẻ'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.primaryAqua,
                      ),
                    ),

                  if (canRenew) const SizedBox(height: 12),

                  // Info message for renewal
                  if (canRenew)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Thẻ của bạn đã hết hạn. Vui lòng thanh toán để gia hạn thẻ.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Resume payment button (cho đăng ký mới, chưa thanh toán)
                  if (canResume && !canRenew)
                    FilledButton.icon(
                      onPressed: _isProcessingPayment ? null : _resumePayment,
                      icon: _isProcessingPayment
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.payment),
                      label: Text(_isProcessingPayment
                          ? 'Đang xử lý...'
                          : 'Tiếp tục thanh toán'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),

                  if (canResume && !canRenew) const SizedBox(height: 12),

                  // Info message
                  if (canResume && !canRenew)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Bạn có thể tiếp tục thanh toán trong vòng 10 phút kể từ khi tạo đăng ký.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (canCancel) ...[
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _isCancelling ? null : _cancelCard,
                      icon: _isCancelling
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cancel_outlined,
                              color: Colors.red),
                      label: Text(
                        _isCancelling ? 'Đang hủy...' : 'Hủy thẻ hiện tại',
                        style: const TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 20, color: theme.colorScheme.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Sau khi hủy, thẻ này sẽ bị vô hiệu hóa hoàn toàn. Bạn cần hủy thẻ cũ trước khi đăng ký thẻ thay thế.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (canRequestReplacement) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed:
                          _isRequestingReplacement ? null : _requestReplacement,
                      icon: _isRequestingReplacement
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.credit_card),
                      label: Text(
                        _isRequestingReplacement
                            ? 'Đang khởi tạo...'
                            : 'Yêu cầu cấp lại thẻ',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 20, color: theme.colorScheme.secondary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Chức năng này dùng lại toàn bộ thông tin của thẻ đã duyệt để tạo đăng ký cấp lại. Bạn chỉ cần thanh toán để hoàn tất.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid(ThemeData theme, List<String> imageUrls) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemCount: imageUrls.length,
      itemBuilder: (context, index) {
        final imageUrl = imageUrls[index];
        return GestureDetector(
          onTap: () => _showImageFullScreen(context, imageUrl, imageUrls, index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    size: 40,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showImageFullScreen(
    BuildContext context,
    String imageUrl,
    List<String> allImages,
    int initialIndex,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _ImageFullScreenViewer(
          images: allImages,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

class _ImageFullScreenViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _ImageFullScreenViewer({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_ImageFullScreenViewer> createState() => _ImageFullScreenViewerState();
}

class _ImageFullScreenViewerState extends State<_ImageFullScreenViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 3.0,
              child: Image.network(
                widget.images[index],
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.broken_image,
                          color: Colors.white70,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Không thể tải ảnh',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

