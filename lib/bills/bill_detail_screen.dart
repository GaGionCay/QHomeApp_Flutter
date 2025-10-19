import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết hóa đơn')),
      body: FutureBuilder<BillDto>(
        future: _futureBill,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Lỗi: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Không tìm thấy dữ liệu.'));
          }

          final bill = snapshot.data!;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Loại: ${bill.billType}', style: const TextStyle(fontSize: 18)),
                Text('Tháng: ${bill.month}'),
                Text('Số tiền: ${bill.amount.toStringAsFixed(0)} VNĐ'),
                Text('Trạng thái: ${bill.status}'),
                Text('Hạn thanh toán: ${bill.dueDate}'),
                const Spacer(),
                if (bill.status == 'UNPAID')
                  Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        await _billService.payBill(bill.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Thanh toán thành công!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        setState(() {
                          _futureBill = _billService.getBillDetail(bill.id);
                        });
                      },
                      child: const Text('Thanh toán'),
                    ),
                  )
              ],
            ),
          );
        },
      ),
    );
  }
}
