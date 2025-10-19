import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import 'bill_detail_screen.dart';
import 'bill_service.dart';

class BillListScreen extends StatefulWidget {
  const BillListScreen({super.key});

  @override
  State<BillListScreen> createState() => _BillListScreenState();
}

class _BillListScreenState extends State<BillListScreen> {
  late final BillService _service;
  late Future<List<BillDto>> _futureBills;

  @override
  void initState() {
    super.initState();
    _service = BillService(ApiClient());
    _futureBills = _service.getUnpaidBills();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hóa đơn cần thanh toán')),
      body: FutureBuilder<List<BillDto>>(
        future: _futureBills,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final bills = snapshot.data!;
          if (bills.isEmpty) {
            return const Center(
                child: Text('Không có hóa đơn cần thanh toán.'));
          }
          return ListView.builder(
            itemCount: bills.length,
            itemBuilder: (context, index) {
              final bill = bills[index];
              return ListTile(
                title: Text('${bill.billType} (${bill.month})'),
                subtitle: Text('Số tiền: ${bill.amount} VNĐ'),
                trailing: TextButton(
                  child: const Text('Thanh toán'),
                  onPressed: () async {
                    await _service.payBill(bill.id);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Thanh toán thành công!')),
                    );
                    setState(() => _futureBills = _service.getUnpaidBills());
                  },
                ),
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
