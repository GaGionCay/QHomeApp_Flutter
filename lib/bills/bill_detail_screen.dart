import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import 'bill_service.dart';

class BillDetailScreen extends StatefulWidget {
  final int billId;
  const BillDetailScreen({super.key, required this.billId});

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  late final BillService _billService;
  late Future<BillDto> _futureBill;

  @override
  void initState() {
    super.initState();
    _billService = BillService(ApiClient());
    _futureBill = _billService.getBillDetail(widget.billId);
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'điện':
        return Icons.electric_bolt;
      case 'nước':
        return Icons.water_drop;
      case 'internet':
        return Icons.wifi;
      default:
        return Icons.receipt_long;
    }
  }

  Color _colorForType(String type) {
    switch (type.toLowerCase()) {
      case 'điện':
        return Colors.orangeAccent;
      case 'nước':
        return Colors.blueAccent;
      case 'internet':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatMoney(double amount) {
    final formatter = NumberFormat("#,##0", "vi_VN");
    return '${formatter.format(amount)} VNĐ';
  }

  String _formatDate(String date) {
    try {
      final parsed = DateTime.parse(date);
      return DateFormat('dd/MM/yyyy').format(parsed);
    } catch (_) {
      return date;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _futureBill = _billService.getBillDetail(widget.billId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: const Text('Chi tiết hóa đơn'),
        backgroundColor: const Color(0xFF26A69A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<BillDto>(
          future: _futureBill,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('⚠️ Lỗi tải dữ liệu: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: Text('Không tìm thấy hóa đơn.'));
            }

            final bill = snapshot.data!;
            final color = _colorForType(bill.billType);
            final icon = _iconForType(bill.billType);

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(icon, color: color, size: 30),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bill.billType,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tháng ${bill.billingMonth}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24, thickness: 0.7),
                        _infoRow('Số tiền', _formatMoney(bill.amount)),
                        _infoRow('Hạn thanh toán', _formatDate(bill.paymentDate)),
                        _infoRow(
                          'Trạng thái',
                          bill.status == 'PAID'
                              ? 'Đã thanh toán'
                              : 'Chưa thanh toán',
                          valueColor: bill.status == 'PAID'
                              ? Colors.green
                              : Colors.redAccent,
                        ),
                        const SizedBox(height: 16),
                        if (bill.status == 'UNPAID')
                          Center(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: color,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () async {
                                await _billService.payBill(bill.id);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('💰 Thanh toán thành công!'),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                _refresh();
                              },
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text(
                                'Thanh toán ngay',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
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
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 15, color: Colors.black54),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
