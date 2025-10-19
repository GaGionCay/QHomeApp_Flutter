import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../bills/bill_service.dart';
import '../../bills/bill_month_detail_screen.dart';

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

  /// 🔧 Chuẩn hóa billType để gửi đúng format backend
  String _normalizeBillType(String type) {
    switch (type) {
      case 'Điện':
        return 'ELECTRICITY';
      case 'Nước':
        return 'WATER';
      case 'Internet':
        return 'INTERNET';
      case 'Tất cả':
        return 'ALL';
      default:
        return 'ALL';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return const Center(child: Text('Không có dữ liệu để hiển thị.'));
    }

    // ==== Chuẩn hóa dữ liệu ====
    final months = stats.map((e) => e.month).toSet().toList()..sort();
    final billTypes = ['Điện', 'Nước', 'Internet'];
    final colors = [Colors.blue, Colors.green, Colors.orange];

    final dataMap = <String, Map<String, double>>{};
    for (var month in months) {
      dataMap[month] = {for (var type in billTypes) type: 0};
    }
    for (var s in stats) {
      if (dataMap.containsKey(s.month)) {
        dataMap[s.month]![s.billType] = s.totalAmount;
      }
    }

    // ==== Tạo nhóm cột ====
    final barGroups = <BarChartGroupData>[];
    for (var i = 0; i < months.length; i++) {
      final month = months[i];
      final amounts = billTypes.map((t) => dataMap[month]![t] ?? 0).toList();
      final rods = <BarChartRodData>[];
      for (var j = 0; j < amounts.length; j++) {
        rods.add(
          BarChartRodData(
            toY: amounts[j],
            width: 10,
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: [colors[j].withOpacity(0.6), colors[j]],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        );
      }
      barGroups.add(BarChartGroupData(x: i, barRods: rods, barsSpace: 6));
    }

    final maxY =
        stats.map((e) => e.totalAmount).reduce((a, b) => a > b ? a : b) * 1.2;

    // ==== Biểu đồ ====
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
                  horizontalInterval: maxY / 4),
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
                            fontSize: 10, color: Colors.black87),
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
                              fontSize: 11, fontWeight: FontWeight.w500),
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

              /// ✅ FIX DOUBLE NAVIGATION BUG
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  tooltipBgColor: Colors.white,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '${billTypes[rodIndex]}: ${rod.toY.toStringAsFixed(0)} VNĐ',
                      const TextStyle(
                          color: Colors.black87, fontSize: 12),
                    );
                  },
                ),
                touchCallback: (event, response) {
                  // Chỉ xử lý khi user tap hoàn chỉnh (FlTapUpEvent)
                  if (event is FlTapUpEvent && response?.spot != null) {
                    final i = response!.spot!.touchedBarGroupIndex;
                    final month = months[i];
                    final normalizedType = _normalizeBillType(filterType);

                    debugPrint(
                        "📊 [BillChart] Tapped → Month: $month, FilterType: $filterType → Sent: $normalizedType");

                    // Chỉ mở một lần duy nhất
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
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(billTypes.length, (i) {
            return Row(
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
                      fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}
