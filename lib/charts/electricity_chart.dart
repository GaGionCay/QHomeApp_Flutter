import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/electricity_monthly.dart';

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
  late PageController _pageController;
  int _currentPage = 0;
  int _itemsPerPage = 3; // Hiển thị 3 tháng mỗi lần

  @override
  void initState() {
    super.initState();
    // Initialize to show the most recent 3 months
    if (widget.monthlyData.isNotEmpty) {
      final totalPages = (widget.monthlyData.length / _itemsPerPage).ceil();
      _currentPage = totalPages > 0 ? totalPages - 1 : 0; // Start from last page
    }
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _totalPages {
    if (widget.monthlyData.isEmpty) return 1;
    return (widget.monthlyData.length / _itemsPerPage).ceil();
  }

  List<ElectricityMonthly> _getCurrentPageData() {
    if (widget.monthlyData.isEmpty) return [];
    
    final startIndex = _currentPage * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, widget.monthlyData.length);
    
    if (startIndex >= widget.monthlyData.length) {
      return [];
    }
    
    return widget.monthlyData.sublist(startIndex, endIndex);
  }

  double _getMaxAmount() {
    if (widget.monthlyData.isEmpty) return 1000000;
    return widget.monthlyData
            .map((e) => e.amount)
            .reduce((a, b) => a > b ? a : b) *
        1.2; // Add 20% padding
  }

  @override
  Widget build(BuildContext context) {
    if (widget.monthlyData.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: Text(
            'Chưa có dữ liệu tiền điện',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final currentData = _getCurrentPageData();
    final maxAmount = _getMaxAmount();

    return Column(
      children: [
        // Chart header with month info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tiền điện',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              if (_totalPages > 1)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _currentPage > 0
                          ? () {
                              setState(() {
                                _currentPage--;
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              });
                            }
                          : null,
                      iconSize: 20,
                    ),
                    Text(
                      '${_currentPage + 1}/$_totalPages',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _currentPage < _totalPages - 1
                          ? () {
                              setState(() {
                                _currentPage++;
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              });
                            }
                          : null,
                      iconSize: 20,
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Chart container with horizontal scroll
        Container(
          height: 250,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (page) {
              setState(() {
                _currentPage = page;
              });
            },
            itemCount: _totalPages,
            itemBuilder: (context, pageIndex) {
              final startIndex = pageIndex * _itemsPerPage;
              final endIndex = (startIndex + _itemsPerPage)
                  .clamp(0, widget.monthlyData.length);
              final pageData = widget.monthlyData.sublist(startIndex, endIndex);

              return _buildChart(pageData, maxAmount);
            },
          ),
        ),

        // Month labels
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: currentData.map((data) {
              return Expanded(
                child: Center(
                  child: Text(
                    data.monthDisplay,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildChart(List<ElectricityMonthly> data, double maxAmount) {
    if (data.isEmpty) {
      return const Center(child: Text('Không có dữ liệu'));
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxAmount,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.teal,
            tooltipRoundedRadius: 8,
            tooltipPadding: const EdgeInsets.all(8),
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                NumberFormat.currency(
                  locale: 'vi_VN',
                  symbol: '₫',
                  decimalDigits: 0,
                ).format(rod.toY),
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (value, meta) {
                if (value % (maxAmount / 4) == 0 || value == maxAmount) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      NumberFormat.compactCurrency(
                        locale: 'vi_VN',
                        symbol: '₫',
                        decimalDigits: 0,
                      ).format(value),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: Colors.grey[300]!),
            left: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxAmount / 4,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey[200]!,
              strokeWidth: 1,
            );
          },
        ),
        barGroups: data.asMap().entries.map((entry) {
          final index = entry.key;
          final monthly = entry.value;
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: monthly.amount,
                color: const Color(0xFF26A69A),
                width: 40,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

