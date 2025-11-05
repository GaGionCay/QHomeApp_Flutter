import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import '../models/unified_paid_invoice.dart';
import 'dart:convert';
import 'package:dio/dio.dart';

class PaidInvoicesScreen extends StatefulWidget {
  const PaidInvoicesScreen({super.key});

  @override
  State<PaidInvoicesScreen> createState() => _PaidInvoicesScreenState();
}

class _PaidInvoicesScreenState extends State<PaidInvoicesScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final ApiClient _apiClient = ApiClient();
  List<UnifiedPaidInvoice> _allInvoices = [];
  bool _loading = true;
  String? _error;

  // Current selected month (default to current month)
  DateTime _selectedMonth = DateTime.now();

  // Categories available in the system
  List<String> _categories = [];
  Map<String, List<UnifiedPaidInvoice>> _invoicesByCategory = {};
  Map<String, List<UnifiedPaidInvoice>> _invoicesByMonth = {};

  @override
  void initState() {
    super.initState();
    _loadPaidInvoices();
  }

  Future<void> _loadPaidInvoices() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _apiClient.dio.get('/invoices/paid/all');
      
      if (response.statusCode == 200 && response.data['success'] == true) {
        final List<dynamic> data = response.data['data'] ?? [];
        _allInvoices = data
            .map((json) => UnifiedPaidInvoice.fromJson(json))
            .toList();

        // Extract unique categories
        _categories = _allInvoices
            .map((inv) => inv.category)
            .toSet()
            .toList();

        // Initialize tab controller with categories
        if (_tabController != null) {
          _tabController!.dispose();
        }
        _tabController = TabController(
          length: _categories.length > 0 ? _categories.length : 1,
          vsync: this,
        );

        // Group by month
        _groupByMonth();
        
        // Set selected month to current month if it has invoices, otherwise use first available month
        final currentMonthKey = _getMonthKey(DateTime.now());
        if (_invoicesByMonth.containsKey(currentMonthKey)) {
          _selectedMonth = DateTime.now();
        } else if (_invoicesByMonth.isNotEmpty) {
          // Use first available month (newest)
          final firstMonth = _invoicesByMonth.keys.toList()
            ..sort((a, b) => b.compareTo(a));
          if (firstMonth.isNotEmpty) {
            final parts = firstMonth[0].split('-');
            _selectedMonth = DateTime(int.parse(parts[0]), int.parse(parts[1]));
          }
        }
        
        // Filter by selected month and group by category
        _filterAndGroupByCategory();

        setState(() {
          _loading = false;
        });
      } else {
        setState(() {
          _error = response.data['message'] ?? 'Không thể tải danh sách hóa đơn';
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi tải hóa đơn đã thanh toán: $e');
      setState(() {
        _error = 'Lỗi khi tải danh sách hóa đơn: ${e.toString()}';
        _loading = false;
      });
    }
  }

  void _groupByMonth() {
    _invoicesByMonth.clear();
    for (var invoice in _allInvoices) {
      final key = invoice.monthYearKey;
      _invoicesByMonth.putIfAbsent(key, () => []).add(invoice);
    }
    
    // Sort invoices within each month by payment date descending
    _invoicesByMonth.forEach((key, invoices) {
      invoices.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    });
  }

  void _filterAndGroupByCategory() {
    _invoicesByCategory.clear();
    final selectedMonthKey = _getMonthKey(_selectedMonth);
    
    // Filter invoices for selected month
    final monthInvoices = _invoicesByMonth[selectedMonthKey] ?? [];
    
    // Group by category
    for (var invoice in monthInvoices) {
      _invoicesByCategory.putIfAbsent(invoice.category, () => []).add(invoice);
    }
    
    // Sort invoices within each category by payment date descending
    _invoicesByCategory.forEach((key, invoices) {
      invoices.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    });
  }

  String _getMonthKey(DateTime month) {
    return '${month.year}-${month.month.toString().padLeft(2, '0')}';
  }

  List<String> _getAvailableMonths() {
    final months = _invoicesByMonth.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // Sort descending (newest first)
    return months;
  }

  Future<void> _selectMonth() async {
    final availableMonths = _getAvailableMonths();
    if (availableMonths.isEmpty) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Chọn tháng',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...availableMonths.map((monthKey) {
                final parts = monthKey.split('-');
                final year = int.parse(parts[0]);
                final month = int.parse(parts[1]);
                final date = DateTime(year, month);
                final displayText = DateFormat('MM/yyyy').format(date);
                final count = _invoicesByMonth[monthKey]?.length ?? 0;
                
                return ListTile(
                  title: Text(displayText),
                  subtitle: Text('$count hóa đơn'),
                  onTap: () => Navigator.pop(context, monthKey),
                );
              }),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      final parts = selected.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      setState(() {
        _selectedMonth = DateTime(year, month);
        _filterAndGroupByCategory();
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Hóa đơn đã thanh toán'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Hóa đơn đã thanh toán'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadPaidInvoices,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    if (_allInvoices.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Hóa đơn đã thanh toán'),
        ),
        body: const Center(
          child: Text('Chưa có hóa đơn đã thanh toán'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hóa đơn đã thanh toán'),
        bottom: _categories.length > 1 && _tabController != null
            ? TabBar(
                controller: _tabController!,
                isScrollable: true,
                tabs: _categories.map((cat) {
                  final categoryName = _getCategoryDisplayName(cat);
                  final count = _invoicesByCategory[cat]?.length ?? 0;
                  return Tab(
                    text: '$categoryName ($count)',
                  );
                }).toList(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectMonth,
            tooltip: 'Chọn tháng',
          ),
        ],
      ),
      body: Column(
        children: [
          // Month selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[100],
            child: Row(
              children: [
                const Icon(Icons.date_range, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Tháng: ${DateFormat('MM/yyyy').format(_selectedMonth)}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  '${_invoicesByCategory.values.fold<int>(0, (sum, list) => sum + list.length)} hóa đơn',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
              ],
            ),
          ),
          
          // Invoice list
          Expanded(
            child: _categories.isEmpty
                ? const Center(child: Text('Không có hóa đơn'))
                : _tabController != null
                    ? TabBarView(
                        controller: _tabController!,
                    children: _categories.map((category) {
                      final invoices = _invoicesByCategory[category] ?? [];
                      return _buildInvoiceList(invoices);
                      }).toList(),
                    )
                    : const Center(child: Text('Không có dữ liệu')),
          ),
        ],
      ),
    );
  }

  String _getCategoryDisplayName(String category) {
    final invoice = _allInvoices.firstWhere(
      (inv) => inv.category == category,
      orElse: () => UnifiedPaidInvoice(
        id: '',
        category: category,
        categoryName: category,
        title: '',
        amount: 0,
        paymentDate: DateTime.now(),
      ),
    );
    return invoice.categoryName;
  }

  Widget _buildInvoiceList(List<UnifiedPaidInvoice> invoices) {
    if (invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Không có hóa đơn trong tháng này',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: invoices.length,
      itemBuilder: (context, index) {
        final invoice = invoices[index];
        return _buildInvoiceCard(invoice);
      },
    );
  }

  Widget _buildInvoiceCard(UnifiedPaidInvoice invoice) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    invoice.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    NumberFormat.currency(
                      locale: 'vi_VN',
                      symbol: '₫',
                    ).format(invoice.amount),
                    style: TextStyle(
                      color: Colors.green[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            if (invoice.description != null) ...[
              const SizedBox(height: 8),
              Text(
                invoice.description!,
                style: TextStyle(color: Colors.grey[700], fontSize: 14),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(invoice.paymentDate),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                if (invoice.paymentGateway != null) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.payment, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    invoice.paymentGateway!,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
            if (invoice.reference != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.receipt, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Mã: ${invoice.reference}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

