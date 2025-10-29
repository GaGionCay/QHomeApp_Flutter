import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// Đảm bảo BillService, BillDto, và BillStatistics được import
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

class _BillMonthDetailScreenState extends State<BillMonthDetailScreen>
    with TickerProviderStateMixin {
  late Future<List<BillDto>> _futureBills;
  late AnimationController _totalController;

  @override
  void initState() {
    super.initState();
    _futureBills = widget.billService.getBillsByMonthAndType(
      widget.month,
      billType: widget.billType,
    );
    _totalController =
        AnimationController(vsync: this, duration: const Duration(seconds: 1));
  }

  String _formatAmount(double a) =>
      NumberFormat('#,###', 'vi_VN').format(a).replaceAll(',', '.');

  Future<void> _refresh() async {
    setState(() {
      _futureBills = widget.billService.getBillsByMonthAndType(
        widget.month,
        billType: widget.billType,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Chi tiết ${widget.billType} - ${widget.month}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: FutureBuilder<List<BillDto>>(
        future: _futureBills,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Lỗi: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red)),
            );
          }

          final bills = snapshot.data ?? [];
          if (bills.isEmpty) {
            return const Center(child: Text('Không có hóa đơn nào.'));
          }

          final total = bills.fold<double>(0, (sum, b) => sum + b.amount);
          final totalAnim =
              Tween<double>(begin: 0, end: total).animate(_totalController);
          
          if (_totalController.status != AnimationStatus.forward) {
             _totalController.forward(from: 0);
          }


          return RefreshIndicator(
            onRefresh: _refresh,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: bills.length,
                    itemBuilder: (context, i) {
                      final bill = bills[i];
                      final paid = bill.status.toUpperCase() == 'PAID';

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: paid
                              ? Colors.green.shade50
                              : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListTile(
                          leading: Icon(
                            paid
                                ? Icons.check_circle
                                : Icons.pending_actions_rounded,
                            color: paid ? Colors.green : Colors.orange,
                            size: 36,
                          ),
                          title: Text(
                            'Tháng ${bill.billingMonth}', 
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Số tiền: ${_formatAmount(bill.amount)} VNĐ | Loại: ${bill.billType}',
                          ),
                          trailing: paid
                              ? const Icon(Icons.receipt_long,
                                  color: Colors.blue)
                              : ElevatedButton.icon(
                                  icon: const Icon(Icons.payment),
                                  onPressed: () async {
                                    try {
                                       await widget.billService.payBill(bill.id);
                                       
                                        if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Thanh toán thành công!'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                        }

                                       // Refresh danh sách
                                       await _refresh();

                                    } catch (e) {
                                       // Xử lý lỗi khi thanh toán
                                       if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Thanh toán thất bại: ${e.toString()}'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                       }
                                    }
                                  },
                                  label: const Text('Thanh toán'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                          blurRadius: 10,
                          color: Colors.black12,
                          spreadRadius: 1)
                    ],
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: AnimatedBuilder(
                    animation: totalAnim,
                    builder: (_, __) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tổng chi tiêu:',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${_formatAmount(totalAnim.value)} VNĐ',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _totalController.dispose();
    super.dispose();
  }
}