import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/news_service.dart';
import 'news_list_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthService authService;

  const HomeScreen({super.key, required this.authService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final NewsService newsService;
  int unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    newsService = NewsService(apiClient: widget.authService.apiClient);
    _fetchUnreadCount();
  }

  void _fetchUnreadCount() async {
    try {
      final count = await newsService.unreadCount();
      setState(() => unreadNotifications = count);
    } catch (e) {
      // Ignore errors
    }
  }

  void logout() async {
    await widget.authService.logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen(authService: widget.authService)),
      (route) => false,
    );
  }

  void goToNewsList() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewsListScreen(newsService: newsService)),
    ).then((_) => _fetchUnreadCount()); // refresh badge
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          Stack(
            children: [
              IconButton(icon: const Icon(Icons.notifications), onPressed: goToNewsList),
              if (unreadNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
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
          IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: const Center(child: Text('Welcome Resident!')),
    );
  }
}
