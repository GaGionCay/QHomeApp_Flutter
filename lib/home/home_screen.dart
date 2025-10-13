import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../common/custom_app_bar.dart';
import '../news/news_screen.dart';
import '../register/register_service_screen.dart';
import '../register/register_service_list_screen.dart';
import '../auth/auth_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  final List<Widget> _pages = const [
    Center(
      child: Text(
        'Xin chào!',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
    ),
    NewsScreen(),
    RegisterServiceScreen(),
    RegisterServiceListScreen(),
  ];

  final List<String> _titles = [
    'Trang chủ',
    'Bảng tin',
    'Đăng ký dịch vụ',
    'Lịch sử đăng ký',
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    return Scaffold(
      appBar: CustomAppBar(
        title: _titles[_index],
        onHomeTap: () => setState(() => _index = 0),
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                'Menu',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            _menuItem('Trang chủ', 0),
            _menuItem('Bảng tin', 1),
            _menuItem('Đăng ký dịch vụ', 2),
            _menuItem('Lịch sử đăng ký', 3),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Đăng xuất'),
              onTap: () {
                Navigator.pop(context);
                _showLogoutDialog(context, auth);
              },
            ),
          ],
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _pages[_index],
      ),
    );
  }

  Widget _menuItem(String title, int i) {
    return ListTile(
      title: Text(title),
      onTap: () {
        setState(() => _index = i);
        Navigator.pop(context);
      },
    );
  }

  void _showLogoutDialog(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xác nhận'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await auth.logout(context);
              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
            },
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }
}
