import 'package:flutter/material.dart';
import '../common/custom_app_bar.dart';
import '../bills/bill_list_screen.dart';
import '../bills/bill_paid_list_screen.dart';
import '../bills/bill_service.dart';
import '../auth/api_client.dart';
import '../news/widgets/bill_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final BillService _billService;
  late Future<List<BillStatistics>> _futureStats;

  String _filterType = 'Tất cả';
  final List<String> _billTypes = ['Tất cả', 'Điện', 'Nước', 'Internet'];

  @override
  void initState() {
    super.initState();
    _billService = BillService(ApiClient());
    _futureStats = _billService.getStatistics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Trang chủ',
        showHomeIcon: true, // 👈 bật hiển thị icon góc trái
        onHomeTap: () {
          // Có thể reload trang hoặc scroll lên top
          setState(() {
            _futureStats = _billService.getStatistics();
          });
        },
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Thống kê hóa đơn',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: _filterType,
                  items: _billTypes.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _filterType = value!);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: FutureBuilder<List<BillStatistics>>(
                future: _futureStats,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return BillChart(
                    stats: snapshot.data!,
                    filterType: _filterType,
                    billService: _billService,
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.payment),
              label: const Text('Hóa đơn cần thanh toán'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BillListScreen()),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text('Hóa đơn đã thanh toán'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BillPaidListScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
