import 'package:flutter/material.dart';
import 'bill_service.dart';

class BillMonthDetailScreen extends StatefulWidget {
  final String month;
  final String billType;
  final BillService billService;

  const BillMonthDetailScreen({
    super.key,
    required this.month,
    required this.billType,
    required this.billService,
  });

  @override
  State<BillMonthDetailScreen> createState() => _BillMonthDetailScreenState();
}

class _BillMonthDetailScreenState extends State<BillMonthDetailScreen> {
  late Future<List<BillDto>> _futureBills;

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  void _loadBills() {
    _futureBills = widget.billService.getBillsByMonthAndType(
      widget.month,
      widget.billType,
    );
  }

  Future<void> _refresh() async {
    _loadBills();
    setState(() {});
  }

  void _payBill(BillDto bill) async {
    try {
      await widget.billService.payBill(bill.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanh toán thành công!'),
          backgroundColor: Colors.green,
        ),
      );
      await _refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Thanh toán thất bại: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Chi tiết ${widget.billType} tháng ${widget.month}',
        ),
      ),
      body: FutureBuilder<List<BillDto>>(
        future: _futureBills,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                '⚠️ Lỗi tải dữ liệu: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Không có hóa đơn nào.'));
          }

          final bills = snapshot.data!;
          final total = bills.fold<double>(0, (sum, b) => sum + b.amount);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: bills.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) {
                      final bill = bills[i];
                      final paid = bill.status.toUpperCase() == 'PAID';
                      return ListTile(
                        leading: Icon(
                          paid ? Icons.receipt_long : Icons.pending_actions,
                          color: paid ? Colors.green : Colors.orange,
                        ),
                        title: Text(
                          '${bill.billType} - ${bill.month}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Số tiền: ${bill.amount.toStringAsFixed(0)} VNĐ',
                        ),
                        trailing: paid
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : ElevatedButton(
                                onPressed: () => _payBill(bill),
                                child: const Text('Trả tiền'),
                              ),
                      );
                    },
                  ),
                ),
                Container(
                  color: Colors.blue.shade50,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tổng chi tiêu:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '${total.toStringAsFixed(0)} VNĐ',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
