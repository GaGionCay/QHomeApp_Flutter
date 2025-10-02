import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/bill_service.dart';
import 'bill_detail_page.dart';

class BillListPage extends StatefulWidget {
  final int userId;
  const BillListPage({super.key, required this.userId});

  @override
  State<BillListPage> createState() => _BillListPageState();
}

class _BillListPageState extends State<BillListPage> {
  late Future<List<dynamic>> _billsFuture;
  final _billService = BillService();

  @override
  void initState() {
    super.initState();
    _billsFuture = _billService.getUserBills(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Khoản thu hàng tháng')),
      body: FutureBuilder<List<dynamic>>(
        future: _billsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Lỗi: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Không có hóa đơn nào.'));
          } else {
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final bill = snapshot.data![index];
                return ListTile(
                  title: Text(bill['billType']),
                  subtitle: Text('Số tiền: ${bill['amount']} VNĐ'),
                  trailing: Text(
                    bill['status'],
                    style: TextStyle(
                      color: bill['status'] == 'PAID' ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BillDetailPage(billId: bill['id']),
                      ),
                    );
                  },
                );
              },
            );
          }
        },
      ),
    );
  }
}