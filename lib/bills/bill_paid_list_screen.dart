import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import 'bill_detail_screen.dart';
import 'bill_service.dart';

class BillPaidListScreen extends StatefulWidget {
  const BillPaidListScreen({super.key});

  @override
  State<BillPaidListScreen> createState() => _BillPaidListScreenState();
}

class _BillPaidListScreenState extends State<BillPaidListScreen>
    with SingleTickerProviderStateMixin {
  late final BillService _service;
  late Future<List<BillDto>> _futureBills;

  @override
  void initState() {
    super.initState();
    _service = BillService(ApiClient());
    _futureBills = _service.getPaidBills();
  }

  String _formatAmount(double a) =>
      NumberFormat('#,###', 'vi_VN').format(a).replaceAll(',', '.');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Hóa đơn đã thanh toán'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
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
                'Lỗi tải dữ liệu: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final bills = snapshot.data ?? [];
          if (bills.isEmpty) {
            return const Center(
              child: Text('Không có hóa đơn nào.'),
            );
          }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: bills.length,
              itemBuilder: (context, i) {
                final bill = bills[i];
                return Hero(
                  tag: 'bill_${bill.id}',
                  child: Card(
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            transitionDuration:
                                const Duration(milliseconds: 350),
                            pageBuilder: (_, __, ___) =>
                                BillDetailScreen(billId: bill.id),
                            transitionsBuilder: (_, a, __, child) {
                              return FadeTransition(
                                opacity: a,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.1),
                                    end: Offset.zero,
                                  ).animate(a),
                                  child: child,
                                ),
                              );
                            },
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.white, Colors.blue.shade50],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.receipt_long,
                                size: 40, color: Colors.blueAccent),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bill.billType,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Tháng ${bill.billingMonth}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatAmount(bill.amount)} VNĐ',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: Colors.blueAccent),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
