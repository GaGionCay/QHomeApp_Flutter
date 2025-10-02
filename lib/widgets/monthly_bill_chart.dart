import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/monthly_bill_summary.dart';

class MonthlyBillBarChart extends StatelessWidget {
  final List<MonthlyBillSummary> data;

  const MonthlyBillBarChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final barGroups = data.map((item) {
      final x = item.month + item.year * 12;
      return BarChartGroupData(
        x: x,
        barRods: [
          BarChartRodData(
            toY: item.totalAmount,
            width: 16,
            color: Colors.blueAccent,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Biểu đồ tổng tiền hóa đơn hàng tháng',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 300,
          child: BarChart(
            BarChartData(
              barGroups: barGroups,
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      final month = (value % 12).toInt();
                      final year = (value ~/ 12).toInt();
                      return Text('$month/$year', style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true),
                ),
              ),
              gridData: FlGridData(show: true),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
      ],
    );
  }
}