import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/bill_service.dart';

class BillDetailPage extends StatefulWidget {
  final int billId;
  const BillDetailPage({super.key, required this.billId});

  @override
  State<BillDetailPage> createState() => _BillDetailPageState();
}

class _BillDetailPageState extends State<BillDetailPage> {
  late Future<Map<String, dynamic>> _billFuture;
  final _billService = BillService();

  @override
  void initState() {
    super.initState();
    _billFuture = _billService.getBillDetails(widget.billId);
  }

  void _payBill() async {
    final result = await _billService.payBill(widget.billId);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanh toán thành công!')),
      );
      // Quay lại trang danh sách và refresh
      Navigator.pop(context, true); 
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Thanh toán thất bại: $result')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết hóa đơn')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _billFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Lỗi: ${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return const Center(child: Text('Không tìm thấy hóa đơn.'));
          } else {
            final bill = snapshot.data!;
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loại dịch vụ: ${bill['billType']}', style: const TextStyle(fontSize: 18)),
                  Text('Số tiền: ${bill['amount']} VNĐ', style: const TextStyle(fontSize: 18)),
                  Text('Ngày tạo: ${bill['issueDate']}', style: const TextStyle(fontSize: 16)),
                  Text('Ngày đến hạn: ${bill['dueDate']}', style: const TextStyle(fontSize: 16)),
                  Text('Trạng thái: ${bill['status']}', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 20),
                  if (bill['status'] == 'PENDING')
                    ElevatedButton(
                      onPressed: _payBill,
                      child: const Text('Thanh toán'),
                    ),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}