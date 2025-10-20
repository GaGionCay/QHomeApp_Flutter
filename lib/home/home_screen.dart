import 'package:flutter/material.dart';
import '../bills/bill_list_screen.dart';
import '../bills/bill_paid_list_screen.dart';
import '../bills/bill_service.dart';
import '../auth/api_client.dart';
import '../profile/profile_service.dart';
import '../news/widgets/bill_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final BillService _billService;
  late Future<List<BillStatistics>> _futureStats;
  late Future<Map<String, dynamic>> _futureProfile;

  String _filterType = 'Tất cả';
  final List<String> _billTypes = ['Tất cả', 'Điện', 'Nước', 'Internet'];

  @override
  void initState() {
    super.initState();
    _billService = BillService(ApiClient());
    _futureStats = _billService.getStatistics();
    _futureProfile = ProfileService(ApiClient().dio).getProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD8FFB1),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _futureProfile,
            builder: (context, snapshot) {
              final name = snapshot.data?['fullName'] ?? 'Người dùng';
              final avatarUrl = snapshot.data?['avatarUrl'];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(name, avatarUrl),
                  const SizedBox(height: 20),

                  // 📊 Thống kê hóa đơn
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Thống kê hóa đơn',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      DropdownButton<String>(
                        value: _filterType,
                        items: _billTypes
                            .map((type) =>
                                DropdownMenuItem(value: type, child: Text(type)))
                            .toList(),
                        onChanged: (value) {
                          setState(() => _filterType = value!);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 📈 Biểu đồ
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

                  // 🌈 4 icon chức năng ngay dưới biểu đồ
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMiniCard(Icons.newspaper, 'Tin tức',
                            Colors.lightBlueAccent, () {
                          // TODO: Mở trang tin tức
                        }),
                        _buildMiniCard(Icons.app_registration, 'Đăng ký',
                            Colors.deepOrangeAccent, () {
                          // TODO: Mở trang đăng ký dịch vụ
                        }),
                        _buildMiniCard(Icons.payment, 'Cần TT', Colors.redAccent,
                            () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const BillListScreen()),
                          );
                        }),
                        _buildMiniCard(Icons.receipt_long, 'Đã TT', Colors.green,
                            () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const BillPaidListScreen()),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String name, String? avatarUrl) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF9BE15D), Color(0xFF00E3AE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : const AssetImage('assets/images/avatar_placeholder.png')
                    as ImageProvider,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              "Chào mừng, $name 🌿",
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCard(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(3, 4))
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 5),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}
