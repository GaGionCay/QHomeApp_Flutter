import 'dart:math' as math;
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/electricity_monthly.dart';
import '../theme/app_colors.dart';

enum _ElectricityRange {
  three,
  six,
  twelve,
}

extension _ElectricityRangeX on _ElectricityRange {
  int get months => switch (this) {
        _ElectricityRange.three => 3,
        _ElectricityRange.six => 6,
        _ElectricityRange.twelve => 12,
      };

  String get label => switch (this) {
        _ElectricityRange.three => '3 tháng',
        _ElectricityRange.six => '6 tháng',
        _ElectricityRange.twelve => '12 tháng',
      };
}

class ElectricityChart extends StatefulWidget {
  final List<ElectricityMonthly> monthlyData;

  const ElectricityChart({
    super.key,
    required this.monthlyData,
  });

  @override
  State<ElectricityChart> createState() => _ElectricityChartState();
}

class _ElectricityChartState extends State<ElectricityChart> {
  late List<ElectricityMonthly> _sortedData;
  _ElectricityRange _range = _ElectricityRange.three;

  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );
  final NumberFormat _compactFormatter = NumberFormat.compactCurrency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _sortedData = _prepare(widget.monthlyData);
  }

  @override
  void didUpdateWidget(ElectricityChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.monthlyData, widget.monthlyData)) {
      _sortedData = _prepare(widget.monthlyData);
    }
  }

  List<ElectricityMonthly> _prepare(List<ElectricityMonthly> data) {
    final sorted = List<ElectricityMonthly>.from(data)
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return sorted;
  }

  List<ElectricityMonthly> get _visibleData {
    final data = _sortedData;
    final months = _range.months;
    if (data.length <= months) return data;
    return data.sublist(data.length - months);
  }

  double get _maxAmount {
    final data = _visibleData;
    if (data.isEmpty) return 1;
    final maxValue = data.map((e) => e.amount).reduce(math.max);
    if (maxValue <= 0) return 1;
    return maxValue * 1.2;
  }

  double get _total =>
      _visibleData.fold(0, (double sum, item) => sum + item.amount);

  double get _average {
    final data = _visibleData;
    if (data.isEmpty) return 0;
    return _total / data.length;
  }

  double? get _delta {
    final data = _visibleData;
    if (data.length < 2) return null;
    final latest = data.last.amount;
    final previous = data[data.length - 2].amount;
    if (previous == 0) return null;
    return ((latest - previous) / previous) * 100;
  }

  LinearGradient _cardGradient(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_sortedData.isEmpty) {
      return _buildEmptyState(context);
    }

    final visible = _visibleData;
    final delta = _delta;
    final deltaLabel = delta == null
        ? 'Không đổi'
        : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%';
    final deltaColor = delta == null
        ? theme.colorScheme.onSurfaceVariant
        : (delta >= 0 ? AppColors.success : AppColors.danger);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _cardGradient(context),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.08),
            ),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 20),
                SizedBox(
                  height: 240,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _buildResponsiveBarChart(
                      context,
                      visible,
                      key: ValueKey('${_range.name}-${visible.length}'),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _buildStatsRow(context, deltaLabel, deltaColor),
                const SizedBox(height: 18),
                _buildBreakdown(context, visible),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tiền điện sinh hoạt',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Removed subtitle per latest design feedback to keep header compact.
            ],
          ),
        ),
        _buildRangeSelector(context),
      ],
    );
  }

  Widget _buildRangeSelector(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surface.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _ElectricityRange.values.map((range) {
          final selected = range == _range;
          return GestureDetector(
            onTap: () {
              if (selected) return;
              setState(() => _range = range);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                range.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildResponsiveBarChart(
    BuildContext context,
    List<ElectricityMonthly> data, {
    Key? key,
  }) {
    final maxY = _maxAmount;

    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final availableWidth = constraints.maxWidth;
        final barCount = data.length;
        const minBarWidth = 18.0;
        const maxBarWidth = 42.0;
        const minSpacing = 12.0;

        final desiredContentWidth =
            minBarWidth * barCount + (barCount + 1) * minSpacing;
        final baseWidth = math.max(availableWidth, desiredContentWidth);

        double computedBarWidth =
            ((baseWidth - (barCount + 1) * minSpacing) / barCount)
                .clamp(minBarWidth, maxBarWidth);
        const barSpacing = minSpacing;

        final chartContentWidth =
            barCount * computedBarWidth + (barCount + 1) * barSpacing;
        final chartWidth = math.max(chartContentWidth, availableWidth);
        final textScale = (availableWidth / 360).clamp(0.85, 1.2);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: chartWidth,
            child: BarChart(
              key: key,
              BarChartData(
                maxY: maxY,
                minY: 0,
                alignment: BarChartAlignment.start,
                groupsSpace: barSpacing,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: theme.brightness == Brightness.dark
                        ? AppColors.navySurface.withValues(alpha: 0.9)
                        : Colors.black.withValues(alpha: 0.85),
                    tooltipRoundedRadius: 14,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${data[groupIndex].monthDisplay}\n${_currencyFormatter.format(rod.toY)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= data.length) {
                          return const SizedBox.shrink();
                        }

                        final label = data[index].monthDisplay;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize:
                                  (theme.textTheme.labelSmall?.fontSize ?? 12) *
                                      textScale,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60 * textScale,
                      interval: maxY / 4,
                      getTitlesWidget: (value, meta) {
                        final interval = maxY / 4;
                        final matchesInterval =
                            (value % interval).abs() < interval * 0.05;
                        if (value == maxY || matchesInterval) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              _compactFormatter.format(value),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize:
                                    (theme.textTheme.labelSmall?.fontSize ??
                                            12) *
                                        textScale,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: theme.colorScheme.outline.withValues(alpha: 0.08),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(barCount, (index) {
                  final monthly = data[index];
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: monthly.amount,
                        width: computedBarWidth,
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.primaryEmerald.withValues(alpha: 0.95),
                            AppColors.primaryAqua.withValues(alpha: 0.85),
                          ],
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxY,
                          color: theme.colorScheme.surface.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsRow(
    BuildContext context,
    String deltaLabel,
    Color deltaColor,
  ) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;

    final cards = [
      _MiniStatCard(
        label: 'Tổng ${_range.months} tháng',
        value: _currencyFormatter.format(_total),
        icon: Icons.flash_on_rounded,
        gradient: AppColors.primaryGradient(),
      ),
      _MiniStatCard(
        label: 'Bình quân tháng',
        value: _currencyFormatter.format(_average),
        icon: Icons.auto_graph_rounded,
        gradient: LinearGradient(
          colors: [
            AppColors.skyMist.withValues(alpha: 0.95),
            AppColors.primaryBlue.withValues(alpha: 0.85),
          ],
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? theme.colorScheme.surface.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.08),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(
                deltaLabel.startsWith('+')
                    ? Icons.trending_up_rounded
                    : deltaLabel.startsWith('-')
                        ? Icons.trending_down_rounded
                        : Icons.horizontal_rule_rounded,
                color: deltaColor,
                size: 18,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deltaLabel,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: deltaColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'So với kỳ trước',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        final spacing = isNarrow ? 12.0 : 16.0;
        final crossAxisCount = isNarrow ? 1 : 3;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.spaceBetween,
          children: cards
              .map(
                (card) => SizedBox(
                  width: isNarrow
                      ? double.infinity
                      : (constraints.maxWidth -
                              spacing * (crossAxisCount - 1)) /
                          crossAxisCount,
                  child: card,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildBreakdown(
    BuildContext context,
    List<ElectricityMonthly> visibleData,
  ) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chi tiết từng tháng',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ...visibleData.reversed.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.monthDisplay,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: secondary,
                    ),
                  ),
                ),
                Text(
                  _currencyFormatter.format(item.amount),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _cardGradient(context),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.08),
            ),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 58,
                  width: 58,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient(),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppColors.subtleShadow,
                  ),
                  child: const Icon(
                    Icons.flash_off_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Chưa có dữ liệu tiền điện',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Dữ liệu sẽ xuất hiện khi có hóa đơn điện đầu tiên từ ban quản lý.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.gradient,
  });

  final String label;
  final String value;
  final IconData icon;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? theme.colorScheme.surface.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppColors.subtleShadow,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}



