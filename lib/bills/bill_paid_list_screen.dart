import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import 'bill_detail_screen.dart';
import 'bill_service.dart';

class BillPaidListScreen extends StatefulWidget {
  const BillPaidListScreen({super.key});

  @override
  State<BillPaidListScreen> createState() => _BillPaidListScreenState();
}

class _BillPaidListScreenState extends State<BillPaidListScreen> {
  late final BillService _service;
  late Future<List<BillDto>> _futureBills;

  @override
  void initState() {
    super.initState();
    _service = BillService(ApiClient());
    _futureBills = _service.getPaidBills();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hóa đơn đã thanh toán')),
      body: FutureBuilder<List<BillDto>>(
        future: _futureBills,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final bills = snapshot.data!;
          if (bills.isEmpty) {
            return const Center(child: Text('Không có hóa đơn nào.'));
          }
          return ListView.builder(
            itemCount: bills.length,
            itemBuilder: (context, index) {
              final bill = bills[index];
              return ListTile(
                title: Text('${bill.billType} (${bill.month})'),
                subtitle: Text('Số tiền: ${bill.amount} VNĐ'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        BillDetailScreen(billId: bill.id), // ✅ chỉ truyền ID
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
