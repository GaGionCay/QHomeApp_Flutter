import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'bill_service.dart';
import 'bill_month_detail_screen.dart';

class BillChart extends StatelessWidget {
  final List<BillStatistics> stats;
  final String filterType;
  final BillService billService;

  const BillChart({
    super.key,
    required this.stats,
    required this.filterType,
    required this.billService,
  });

  String _normalizeBillType(String type) {
    switch (type) {
      case 'Điện':
        return 'ELECTRICITY';
      case 'Nước':
        return 'WATER';
      default:
        return 'ALL';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return const Center(child: Text('Không có dữ liệu để hiển thị.'));
    }

    final billTypes = ['Điện', 'Nước'];
    final colors = [Colors.blueAccent, Colors.teal];

    final months = stats.map((e) => e.month).toSet().toList()..sort();

    // Dữ liệu tổng hợp cho từng tháng
    final dataMap = <String, Map<String, double>>{};
    for (var month in months) {
      dataMap[month] = {for (var type in billTypes) type: 0};
    }
    for (var s in stats) {
      if (dataMap.containsKey(s.month) && billTypes.contains(s.billType)) {
        dataMap[s.month]![s.billType] = s.totalAmount;
      }
    }

    final barGroups = <BarChartGroupData>[];
    for (var i = 0; i < months.length; i++) {
      final month = months[i];
      final rods = <BarChartRodData>[];

      for (var j = 0; j < billTypes.length; j++) {
        final type = billTypes[j];
        final amount = dataMap[month]![type] ?? 0;
        rods.add(
          BarChartRodData(
            toY: amount,
            width: 12,
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: [colors[j].withOpacity(0.6), colors[j]],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        );
      }

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: rods,
          barsSpace: 8,
        ),
      );
    }

    final maxY =
        stats.map((e) => e.totalAmount).reduce((a, b) => a > b ? a : b) * 1.2;

    return Column(
      children: [
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 1.6,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawHorizontalLine: true,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.grey.withOpacity(0.2),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              maxY: maxY,
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    getTitlesWidget: (value, _) {
                      return Text(
                        '${(value / 1000).round()}K',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      );
                    },
                    interval: maxY / 4,
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      final i = value.toInt();
                      if (i < 0 || i >= months.length) {
                        return const SizedBox.shrink();
                      }
                      final parts = months[i].split('-');
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${parts[1]}/${parts[0].substring(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),

              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  tooltipBgColor: Colors.white,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final amount = rod.toY.toStringAsFixed(0);
                    return BarTooltipItem(
                      '${billTypes[rodIndex]}: $amount VNĐ',
                      const TextStyle(color: Colors.black87, fontSize: 12),
                    );
                  },
                ),
                touchCallback: (event, response) {
                  if (event is FlTapUpEvent && response?.spot != null) {
                    final i = response!.spot!.touchedBarGroupIndex;
                    final month = months[i];
                    final normalizedType = _normalizeBillType(filterType);

                    debugPrint(
                        "📊 [BillChart] Tapped → Month: $month, FilterType: $filterType → Sent: $normalizedType");

                    Future.microtask(() {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BillMonthDetailScreen(
                            month: month,
                            billType: normalizedType,
                            billService: billService,
                          ),
                        ),
                      );
                    });
                  }
                },
              ),
              barGroups: barGroups,
            ),
          ),
        ),

        const SizedBox(height: 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(billTypes.length, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: colors[i],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    billTypes[i],
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}
