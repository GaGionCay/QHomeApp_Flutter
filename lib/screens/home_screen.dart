import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/news_service.dart';
import 'news_list_screen.dart';
import 'login_screen.dart';
import 'register_service_screen.dart'; 

class HomeScreen extends StatefulWidget {
  final AuthService authService;
  final NewsService newsService;

  const HomeScreen({
    super.key,
    required this.authService,
    required this.newsService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _fetchUnreadCount();
  }

  void _fetchUnreadCount() async {
    try {
      final count = await widget.newsService.unreadCount();
      setState(() => unreadNotifications = count);
    } catch (e) {
    }
  }

  void logout() async {
    await widget.authService.logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(authService: widget.authService),
      ),
      (route) => false,
    );
  }

  // Chuyển sang danh sách thông báo
  void goToNewsList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewsListScreen(newsService: widget.newsService),
      ),
    ).then((_) => _fetchUnreadCount()); // refresh badge khi quay lại
  }

  // Chuyển sang màn hình đăng ký dịch vụ
  void goToRegisterService() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyRegisterServiceScreen(authService: widget.authService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          // Icon thông báo với badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: goToNewsList,
              ),
              if (unreadNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$unreadNotifications',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Welcome Resident!'),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: goToRegisterService,
              icon: const Icon(Icons.add_box),
              label: const Text('Register Service'),
            ),
          ],
        ),
      ),
    );
  }
}
