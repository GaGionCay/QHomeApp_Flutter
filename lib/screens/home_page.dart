import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/bill_service.dart';
import '../services/news_service.dart';
import 'login_page.dart';
import '../screens/service_registration_service.dart';
import '../screens/bill_list_page.dart';
import '../screens/notification_page.dart';
import '../models/monthly_bill_summary.dart';
import '../models/news.dart';
import '../widgets/monthly_bill_chart.dart';

class HomePage extends StatefulWidget {
  final int id;
  final String email;

  const HomePage({super.key, required this.id, required this.email});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _authService = AuthService();
  final _billService = BillService();
  final _newsService = NewsService();

  List<MonthlyBillSummary> _summary = [];
  List<News> _newsList = [];
  bool _loadingSummary = true;
  bool _loadingNews = true;

  @override
  void initState() {
    super.initState();
    _loadMonthlySummary();
    _loadNews();
  }

  void _loadMonthlySummary() async {
    try {
      final result = await _billService.fetchMonthlySummary(widget.id);
      setState(() {
        _summary = result;
        _loadingSummary = false;
      });
    } catch (e) {
      setState(() {
        _loadingSummary = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tải biểu đồ: $e')),
      );
    }
  }

  void _loadNews() async {
    try {
      final result = await _newsService.fetchNews();
      setState(() {
        _newsList = result;
        _loadingNews = false;
      });
    } catch (e) {
      setState(() {
        _loadingNews = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tải bảng tin: $e')),
      );
    }
  }

  void _logout() async {
    final result = await _authService.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (result == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result)),
      );
    }
  }

  void _goToServiceRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ServiceRegistrationPage(id: widget.id, email: widget.email),
      ),
    );
  }

  void _goToBills() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BillListPage(userId: widget.id)),
    );
  }

  void _goToNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationPage(newsList: _newsList),
      ),
    );
  }

  Widget _buildMonthlySummary() {
    if (_loadingSummary) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_summary.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Chưa có dữ liệu hóa đơn hàng tháng'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MonthlyBillBarChart(data: _summary),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Chi tiết tổng tiền từng tháng:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        ..._summary.map(
          (item) => ListTile(
            leading: const Icon(Icons.bar_chart),
            title: Text('Tháng ${item.month}/${item.year}'),
            subtitle: Text(
              'Tổng tiền: ${item.totalAmount.toStringAsFixed(0)} VND',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNewsSection() {
    if (_loadingNews) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_newsList.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Chưa có bảng tin nào'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('📢 Bảng tin cư dân:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        ..._newsList.map((news) => ListTile(
              leading: const Icon(Icons.announcement),
              title: Text(news.title),
              subtitle: Text(news.content),
              trailing: Text(news.author),
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _newsList.where((n) => !n.isRead).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trang chính'),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: _goToNotifications,
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${widget.email} 👋',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Email: ${widget.email}',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildNewsSection(),
                const Divider(),
                _buildMonthlySummary(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _goToBills,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Khoản thu'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _goToServiceRegistration,
                    icon: const Icon(Icons.app_registration),
                    label: const Text('Đăng ký dịch vụ'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}