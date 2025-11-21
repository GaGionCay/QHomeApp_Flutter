import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/api_client.dart';
import '../auth/asset_maintenance_api_client.dart';
import '../common/layout_insets.dart';
import '../models/invoice_category.dart';
import '../models/invoice_line.dart';
import '../models/unit_info.dart';
import '../service_registration/service_booking_service.dart';
import '../theme/app_colors.dart';
import 'invoice_service.dart';

class PaidInvoicesScreen extends StatefulWidget {
  final String? initialUnitId;
  final List<UnitInfo>? initialUnits;

  const PaidInvoicesScreen({
    super.key,
    this.initialUnitId,
    this.initialUnits,
  });

  @override
  State<PaidInvoicesScreen> createState() => _PaidInvoicesScreenState();
}

class _PaidInvoicesScreenState extends State<PaidInvoicesScreen> {
  late final ApiClient _apiClient;
  late final InvoiceService _invoiceService;
  late final AssetMaintenanceApiClient _assetMaintenanceApiClient;
  late final ServiceBookingService _bookingService;
  late Future<_PaidData> _futureData;
  String? _selectedCategoryCode;
  List<UnitInfo> _units = [];
  late String _selectedUnitId;
  static const String _allUnitsKey = 'ALL_UNITS';
  static const String _allMonthsKey = 'ALL';
  String _selectedMonthKey = _allMonthsKey;

  Future<_PaidData> _loadData() async {
    String? unitFilter =
        _selectedUnitId == _allUnitsKey ? null : _selectedUnitId;
    if (unitFilter == null || unitFilter.isEmpty) {
      if (_units.isNotEmpty) {
        unitFilter = _units.first.id;
      } else if (widget.initialUnitId != null &&
          widget.initialUnitId!.isNotEmpty) {
        unitFilter = widget.initialUnitId;
      }
    }

    if (unitFilter == null || unitFilter.isEmpty) {
      debugPrint(
          '⚠️ [PaidInvoicesScreen] Không có căn hộ hợp lệ để tải hóa đơn');
      final bookings = await _bookingService.getPaidBookings();
      return _PaidData(categories: const [], paidBookings: bookings);
    }

    final String unitIdForRequest = unitFilter;
    final categoriesFuture =
        _invoiceService.getPaidInvoicesByCategory(unitId: unitIdForRequest);
    final bookingsFuture = _bookingService.getPaidBookings();

    final categories = await categoriesFuture;
    final bookings = await bookingsFuture;

    return _PaidData(categories: categories, paidBookings: bookings);
  }

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _invoiceService = InvoiceService(_apiClient);
    _assetMaintenanceApiClient = AssetMaintenanceApiClient();
    _bookingService = ServiceBookingService(_assetMaintenanceApiClient);
    _units = widget.initialUnits != null
        ? List<UnitInfo>.from(widget.initialUnits!)
        : <UnitInfo>[];
    _selectedUnitId = _allUnitsKey;
    _selectedMonthKey = _allMonthsKey;
    _futureData = _loadData();
  }

  Future<void> _refresh() async {
    setState(() {
      _futureData = _loadData();
    });
  }

  LinearGradient _backgroundGradient(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF050F1F),
          Color(0xFF0F1E33),
          Color(0xFF152B47),
        ],
      );
    }

    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFE8F4FF),
        Color(0xFFF2F6FF),
        Color(0xFFF9FBFF),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaPadding = MediaQuery.of(context).padding;
    final topOffset = mediaPadding.top + kToolbarHeight + 18;
    final bottomPadding =
        LayoutInsets.bottomNavContentPadding(context, minimumGap: 28);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Lịch sử thanh toán'),
        backgroundColor: Colors.transparent,
        foregroundColor: theme.brightness == Brightness.dark
            ? Colors.white
            : AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _backgroundGradient(context),
        ),
        child: SafeArea(
          top: false,
          child: FutureBuilder<_PaidData>(
            future: _futureData,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                final error = snapshot.error;
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      topOffset,
                      24,
                      bottomPadding,
                    ),
                    child: _PaidGlassCard(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 58,
                            width: 58,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.danger.withValues(alpha: 0.88),
                                  Colors.redAccent.withValues(alpha: 0.82),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: AppColors.subtleShadow,
                            ),
                            child: const Icon(
                              Icons.error_outline,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Không thể tải lịch sử thanh toán',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '$error',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _refresh,
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final rawCategories = snapshot.data?.categories ?? [];
              final paidBookings = snapshot.data?.paidBookings ?? [];
              final monthOptions = _buildMonthOptions(rawCategories);

              if (_selectedMonthKey != _allMonthsKey &&
                  !monthOptions.any((opt) => opt.key == _selectedMonthKey)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _selectedMonthKey = _allMonthsKey;
                    _selectedCategoryCode = null;
                  });
                });
              }

              final categories =
                  _filterCategoriesByMonth(rawCategories, _selectedMonthKey);

              InvoiceCategory? selectedCategory;
              if (categories.isNotEmpty) {
                selectedCategory = categories.firstWhere(
                  (c) => c.categoryCode == _selectedCategoryCode,
                  orElse: () => categories.first,
                );
                if (_selectedCategoryCode != selectedCategory.categoryCode) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _selectedCategoryCode = selectedCategory?.categoryCode;
                    });
                  });
                }
              }

              final content = <Widget>[
                _buildUnitFilterCard(),
                const SizedBox(height: 18),
                _buildMonthFilterCard(monthOptions),
                const SizedBox(height: 18),
              ];

              if (categories.isEmpty) {
                content.add(_buildAllPaidState());
              } else {
                content
                  ..add(_buildOverviewHeader(categories))
                  ..add(const SizedBox(height: 20))
                  ..add(_buildCategorySelector(categories))
                  ..add(const SizedBox(height: 18));

                if (selectedCategory != null) {
                  content
                    ..add(_buildCategorySummary(selectedCategory))
                    ..add(const SizedBox(height: 18));

                  if (selectedCategory.invoices.isEmpty) {
                    content.add(_buildCategoryEmptyState(selectedCategory));
                  } else {
                    content.addAll(
                      selectedCategory.invoices.map(_buildInvoiceCard),
                    );
                  }
                }
              }

              content
                ..add(const SizedBox(height: 26))
                ..add(_buildPaidBookingsSection(paidBookings));

              return RefreshIndicator(
                edgeOffset: topOffset,
                color: theme.colorScheme.primary,
                onRefresh: _refresh,
                child: ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    24,
                    topOffset,
                    24,
                    bottomPadding,
                  ),
                  children: content,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMonthFilterCard(List<_MonthOption> options) {
    final theme = Theme.of(context);
    if (options.isEmpty) {
      return _PaidGlassCard(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient(),
                borderRadius: BorderRadius.circular(18),
                boxShadow: AppColors.subtleShadow,
              ),
              child: const Icon(
                Icons.inbox_outlined,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Chưa có hóa đơn đã thanh toán',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Lịch sử thanh toán sẽ hiển thị ở đây khi bạn hoàn tất hóa đơn đầu tiên.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return _PaidGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chọn tháng hiển thị',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.surface.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.08),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedMonthKey,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                borderRadius: BorderRadius.circular(18),
                items: options
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.key,
                        child: Text(
                          option.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: option.key == _selectedMonthKey
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedMonthKey = value;
                    _selectedCategoryCode = null;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelector(List<InvoiceCategory> categories) {
    final theme = Theme.of(context);
    return _PaidGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nhóm dịch vụ đã thanh toán',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: categories.map((category) {
              final selected = category.categoryCode == _selectedCategoryCode;
              final accent = _colorForServiceCode(category.categoryCode);
              final icon = _iconForServiceCode(category.categoryCode);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCategoryCode = category.categoryCode;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: selected
                        ? accent.withValues(alpha: 0.16)
                        : theme.brightness == Brightness.dark
                            ? theme.colorScheme.surface.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.72),
                    border: Border.all(
                      color: selected
                          ? accent.withValues(alpha: 0.65)
                          : theme.colorScheme.outline.withValues(alpha: 0.12),
                    ),
                    boxShadow: selected ? AppColors.subtleShadow : const [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: selected
                            ? accent
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${category.categoryName} (${category.invoiceCount})',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? accent
                              : theme.colorScheme.onSurfaceVariant,
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

  Widget _buildOverviewHeader(List<InvoiceCategory> categories) {
    final theme = Theme.of(context);
    double totalAmount = 0;
    int totalInvoices = 0;
    final Set<String> servicedMonths = <String>{};

    for (final category in categories) {
      totalAmount += category.totalAmount;
      totalInvoices += category.invoiceCount;
      for (final invoice in category.invoices) {
        final key = _monthKeyFromServiceDate(invoice.serviceDate);
        if (key != null) servicedMonths.add(key);
      }
    }

    final average =
        totalInvoices == 0 ? 0.0 : totalAmount / totalInvoices.toDouble();
    final monthsCount = servicedMonths.length;

    String latestMonthLabel = 'Không xác định';
    if (servicedMonths.isNotEmpty) {
      final latestKey =
          servicedMonths.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
      latestMonthLabel = _formatMonthLabel(latestKey);
    }

    return _PaidGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tổng quan lịch sử',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSummaryStatTile(
                  label: 'Tổng đã thanh toán',
                  value: _formatMoney(totalAmount),
                  icon: Icons.payments_rounded,
                  accent: AppColors.primaryEmerald,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildSummaryStatTile(
                  label: 'Số hóa đơn',
                  value: '$totalInvoices khoản',
                  icon: Icons.receipt_long_outlined,
                  accent: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildSummaryStatTile(
                  label: 'Bình quân mỗi hóa đơn',
                  value: _formatMoney(average),
                  icon: Icons.bar_chart_rounded,
                  accent: AppColors.skyMist,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildSummaryStatTile(
                  label: monthsCount > 0
                      ? '$monthsCount tháng đã thanh toán'
                      : 'Chưa ghi nhận tháng',
                  value: latestMonthLabel,
                  icon: Icons.event_available_outlined,
                  accent: AppColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStatTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surface.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
        boxShadow: AppColors.subtleShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    accent.withValues(alpha: 0.9),
                    accent.withValues(alpha: 0.55),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppColors.subtleShadow,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return IntrinsicWidth(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surface.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.08),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnitFilterCard() {
    final theme = Theme.of(context);
    final options = <_UnitOption>[
      const _UnitOption(_allUnitsKey, 'Tất cả căn hộ'),
      ..._units.map((unit) => _UnitOption(unit.id, unit.displayName)),
    ];

    final current = _selectedUnitId;

    return _PaidGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lọc theo căn hộ',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: options.map((option) {
              final selected = current == option.id;
              final accent = theme.colorScheme.primary;

              return GestureDetector(
                onTap: () {
                  if (_selectedUnitId == option.id) return;
                  setState(() {
                    _selectedUnitId = option.id;
                    _selectedCategoryCode = null;
                    _selectedMonthKey = _allMonthsKey;
                    _futureData = _loadData();
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: selected
                        ? accent.withValues(alpha: 0.18)
                        : theme.brightness == Brightness.dark
                            ? theme.colorScheme.surface.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.78),
                    border: Border.all(
                      color: selected
                          ? accent.withValues(alpha: 0.7)
                          : theme.colorScheme.outline.withValues(alpha: 0.12),
                    ),
                    boxShadow: selected ? AppColors.subtleShadow : const [],
                  ),
                  child: Text(
                    option.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? accent
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (_units.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Bạn chưa được gán vào căn hộ nào, hiển thị tất cả hóa đơn.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategorySummary(InvoiceCategory category) {
    final theme = Theme.of(context);
    final accent = _colorForServiceCode(category.categoryCode);
    final icon = _iconForServiceCode(category.categoryCode);

    return _PaidGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.92),
                      accent.withValues(alpha: 0.55),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: AppColors.subtleShadow,
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.categoryName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${category.invoiceCount} hóa đơn đã thanh toán',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.surface.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.08),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.payments_rounded,
                    color: accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatMoney(category.totalAmount),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                        Text(
                          'Tổng số tiền đã thanh toán cho nhóm dịch vụ này',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllPaidState() {
    final theme = Theme.of(context);
    return _PaidGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withValues(alpha: 0.9),
                  AppColors.primaryEmerald.withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppColors.subtleShadow,
            ),
            child: const Icon(
              Icons.celebration,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '🎉 Bạn đã hoàn tất mọi hóa đơn',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Hãy tiếp tục theo dõi lịch sử thanh toán tại đây để quản lý tài chính minh bạch và thuận tiện.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryEmptyState(InvoiceCategory category) {
    final theme = Theme.of(context);
    final accent = _colorForServiceCode(category.categoryCode);
    return _PaidGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.9),
                  accent.withValues(alpha: 0.55),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppColors.subtleShadow,
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Không còn hóa đơn ${category.categoryName.toLowerCase()} trong tháng này',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Chúng tôi sẽ gửi thông báo ngay khi có hóa đơn mới trong nhóm dịch vụ này.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<_MonthOption> _buildMonthOptions(List<InvoiceCategory> categories) {
    final Map<String, String> monthMap = {};

    for (final category in categories) {
      for (final invoice in category.invoices) {
        final key = _monthKeyFromServiceDate(invoice.serviceDate);
        if (key == null) continue;
        monthMap.putIfAbsent(key, () => _formatMonthLabel(key));
      }
    }

    final sortedKeys = monthMap.keys.toList()..sort((a, b) => b.compareTo(a));

    final options = <_MonthOption>[
      _MonthOption(_allMonthsKey, 'Tất cả tháng'),
      ...sortedKeys.map((key) => _MonthOption(key, monthMap[key]!)),
    ];

    return options;
  }

  List<InvoiceCategory> _filterCategoriesByMonth(
      List<InvoiceCategory> categories, String selectedMonth) {
    if (selectedMonth == _allMonthsKey) {
      return categories;
    }

    final List<InvoiceCategory> filtered = [];

    for (final category in categories) {
      final invoices = category.invoices
          .where((invoice) =>
              _monthKeyFromServiceDate(invoice.serviceDate) == selectedMonth)
          .toList();

      if (invoices.isEmpty) continue;

      final total =
          invoices.fold<double>(0, (sum, item) => sum + item.lineTotal);

      filtered.add(InvoiceCategory(
        categoryCode: category.categoryCode,
        categoryName: category.categoryName,
        totalAmount: total,
        invoiceCount: invoices.length,
        invoices: invoices,
      ));
    }

    return filtered;
  }

  String? _formatServiceMonth(String serviceDate) {
    final key = _monthKeyFromServiceDate(serviceDate);
    if (key == null) return null;
    return _formatMonthLabel(key);
  }

  String _formatMonthLabel(String key) {
    try {
      final parts = key.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final date = DateTime(year, month);
      return DateFormat('MM/yyyy').format(date);
    } catch (_) {
      return key;
    }
  }

  String? _monthKeyFromServiceDate(String serviceDate) {
    if (serviceDate.isEmpty) return null;
    try {
      final date = DateTime.parse(serviceDate);
      final year = date.year.toString().padLeft(4, '0');
      final month = date.month.toString().padLeft(2, '0');
      return '$year-$month';
    } catch (_) {
      return null;
    }
  }

  Widget _buildInvoiceCard(InvoiceLineResponseDto invoice) {
    final theme = Theme.of(context);
    final serviceColor = _colorForServiceCode(invoice.serviceCode);
    final serviceIcon = _iconForServiceCode(invoice.serviceCode);
    final monthLabel = _formatServiceMonth(invoice.serviceDate);
    final secondary = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _PaidGlassCard(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        serviceColor.withValues(alpha: 0.92),
                        serviceColor.withValues(alpha: 0.55),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: AppColors.subtleShadow,
                  ),
                  child: Icon(serviceIcon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              invoice.serviceCodeDisplay,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'ĐÃ THANH TOÁN',
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        invoice.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondary,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 14,
                        runSpacing: 8,
                        children: [
                          if (monthLabel != null)
                            _buildMetaChip(
                              icon: Icons.calendar_month_outlined,
                              label: 'Tháng $monthLabel',
                            ),
                          _buildMetaChip(
                            icon: Icons.calendar_today_outlined,
                            label: _formatDate(invoice.serviceDate),
                          ),
                          if (invoice.quantity > 0 && invoice.unit.isNotEmpty)
                            _buildMetaChip(
                              icon: Icons.align_horizontal_left_rounded,
                              label:
                                  '${invoice.quantity.toStringAsFixed(2)} ${invoice.unit}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: secondary.withValues(alpha: 0.12), height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatMoney(invoice.lineTotal),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: serviceColor,
                    ),
                    softWrap: true,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  fit: FlexFit.loose,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildMetaChip(
                      icon: Icons.receipt_long_outlined,
                      label: invoice.invoiceId,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _colorForServiceCode(String serviceCode) {
    switch (serviceCode.toUpperCase()) {
      case 'ELECTRIC':
      case 'ELECTRICITY':
        return Colors.orangeAccent;
      case 'WATER':
        return Colors.blueAccent;
      case 'INTERNET':
        return Colors.teal;
      case 'ELEVATOR':
      case 'ELEVATOR_CARD':
        return Colors.deepPurpleAccent;
      case 'PARKING':
      case 'CAR_PARK':
      case 'CARPARK':
      case 'VEHICLE_PARKING':
      case 'MOTORBIKE_PARK':
        return Colors.indigoAccent;
      default:
        return Colors.grey;
    }
  }

  IconData _iconForServiceCode(String serviceCode) {
    switch (serviceCode.toUpperCase()) {
      case 'ELECTRIC':
      case 'ELECTRICITY':
        return Icons.electric_bolt;
      case 'WATER':
        return Icons.water_drop;
      case 'INTERNET':
        return Icons.wifi;
      case 'ELEVATOR':
      case 'ELEVATOR_CARD':
        return Icons.elevator;
      case 'PARKING':
      case 'CAR_PARK':
      case 'CARPARK':
      case 'VEHICLE_PARKING':
      case 'MOTORBIKE_PARK':
        return Icons.local_parking;
      default:
        return Icons.receipt_long;
    }
  }

  String _formatMoney(double amount) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(amount);
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy', 'vi_VN').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildPaidBookingsSection(List<Map<String, dynamic>> bookings) {
    final theme = Theme.of(context);
    if (bookings.isEmpty) {
      return _PaidGlassCard(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient(),
                borderRadius: BorderRadius.circular(18),
                boxShadow: AppColors.subtleShadow,
              ),
              child: const Icon(
                Icons.event_available_outlined,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có dịch vụ tiện ích nào đã thanh toán',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Khi bạn sử dụng tiện ích và hoàn tất thanh toán, thông tin sẽ được lưu tại đây.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PaidGlassCard(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
          child: Row(
            children: [
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient(),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: AppColors.subtleShadow,
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dịch vụ tiện ích đã thanh toán',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${bookings.length} lượt đặt tiện ích đã được ghi nhận',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ...bookings.map(_buildPaidBookingCard),
      ],
    );
  }

  Widget _buildPaidBookingCard(Map<String, dynamic> booking) {
    final serviceName = booking['serviceName']?.toString() ?? 'Dịch vụ';
    final categoryCode = booking['serviceCode']?.toString() ?? '';
    final totalAmount = (booking['totalAmount'] as num?)?.toDouble() ?? 0;
    final bookingDateStr = booking['bookingDate']?.toString();
    final startTime = booking['startTime']?.toString();
    final endTime = booking['endTime']?.toString();
    final paymentDateStr = booking['paymentDate']?.toString();
    final paymentStatus = booking['paymentStatus']?.toString() ?? '';
    final purpose = booking['purpose']?.toString();

    final bookingDateLabel =
        bookingDateStr != null ? _formatDate(bookingDateStr) : '—';
    final paymentDateLabel = _formatDateTime(paymentDateStr);
    final timeRangeLabel = _formatTimeRange(startTime, endTime);
    final amountLabel = _formatMoney(totalAmount);
    final paymentStatusLabel = _translatePaymentStatus(paymentStatus);

    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _PaidGlassCard(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient(),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: AppColors.subtleShadow,
                  ),
                  child: const Icon(
                    Icons.event_available_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        serviceName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (categoryCode.isNotEmpty)
                        Text(
                          categoryCode,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    paymentStatusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ngày sử dụng: $bookingDateLabel',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondary,
                        ),
                      ),
                      if (timeRangeLabel != null)
                        Text(
                          'Khung giờ: $timeRangeLabel',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: secondary,
                          ),
                        ),
                      Text(
                        'Thanh toán lúc: $paymentDateLabel',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tổng tiền',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                      ),
                    ),
                    Text(
                      amountLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryEmerald,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Trạng thái',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                      ),
                    ),
                    Text(
                      paymentStatusLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (purpose != null && purpose.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Ghi chú: $purpose',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm', 'vi_VN').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  String? _formatTimeRange(String? start, String? end) {
    if ((start == null || start.isEmpty) && (end == null || end.isEmpty)) {
      return null;
    }

    String shorten(String value) {
      return value.length >= 5 ? value.substring(0, 5) : value;
    }

    if (start != null && end != null && start.isNotEmpty && end.isNotEmpty) {
      return '${shorten(start)} - ${shorten(end)}';
    }
    if (start != null && start.isNotEmpty) {
      return shorten(start);
    }
    if (end != null && end.isNotEmpty) {
      return shorten(end);
    }
    return null;
  }

  String _translatePaymentStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PAID':
        return 'Đã thanh toán';
      case 'PENDING':
        return 'Đang chờ xử lý';
      case 'UNPAID':
        return 'Chưa thanh toán';
      default:
        return status;
    }
  }
}

class _MonthOption {
  final String key;
  final String label;

  const _MonthOption(this.key, this.label);
}

class _PaidData {
  final List<InvoiceCategory> categories;
  final List<Map<String, dynamic>> paidBookings;

  const _PaidData({required this.categories, required this.paidBookings});
}

class _UnitOption {
  final String id;
  final String label;

  const _UnitOption(this.id, this.label);
}

class _PaidGlassCard extends StatelessWidget {
  const _PaidGlassCard({
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(28);
    final gradient = theme.brightness == Brightness.dark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: borderRadius,
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.08),
            ),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}


