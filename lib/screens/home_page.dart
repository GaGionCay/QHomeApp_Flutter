import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/login_page.dart';
import 'package:flutter_application_1/screens/notification_page.dart';
import 'package:flutter_application_1/screens/service_registration.dart'; // import page mới
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  final int userId;
  final String email;
  final String username;
  const HomePage({super.key, required this.userId, required this.email, required this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  void _openNotificationPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationPage(
            userId: widget.userId, email: widget.email, username: widget.username),
      ),
    );
  }

  void _openServiceRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceRegistrationPage(userId: widget.userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C3E50),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle('Dịch vụ'),
                        const SizedBox(height: 16),
                        _buildServicesGrid(),
                        const SizedBox(height: 24),
                        _buildSectionTitle('Tiện ích'),
                        const SizedBox(height: 16),
                        _buildUtilitiesGrid(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white24,
            child: Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Xin chào, ${widget.username}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'King C - Cộng đồng',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                color: Colors.white,
                onPressed: _openNotificationPage,
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            color: Colors.white,
            onPressed: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildServicesGrid() {
    final services = [
      {'icon': '🏠', 'label': 'Dịch vụ\nnước', 'color': const Color(0xFFE3F2FD)},
      {'icon': '💡', 'label': 'Đóng tiền\nđiện', 'color': const Color(0xFFFFF9C4)},
      {'icon': '📦', 'label': 'Gửi đồ', 'color': const Color(0xFFE1F5FE)},
      {'icon': '🧹', 'label': 'Mày lành', 'color': const Color(0xFFE0F2F1)},
      {
        'icon': '💳',
        'label': 'Đăng ký thẻ',
        'color': const Color(0xFFE8EAF6),
        'action': _openServiceRegistration
      },
      {'icon': '💧', 'label': 'Bộ đồ\ndùng', 'color': const Color(0xFFE1F5FE)},
      {'icon': '🛠️', 'label': 'Hỗ trợ', 'color': const Color(0xFFFFF9C4)},
      {'icon': '🏢', 'label': 'Dịch vụ\nnước', 'color': const Color(0xFFE3F2FD)},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        return GestureDetector(
          onTap: service['action'] != null
              ? service['action'] as void Function()
              : () {},
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: service['color'] as Color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    service['icon'] as String,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                service['label'] as String,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black87,
                  height: 1.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUtilitiesGrid() {
    final utilities = [
      {'icon': '🏠', 'label': 'Dịch vụ\nnước', 'color': const Color(0xFFE3F2FD)},
      {'icon': '💡', 'label': 'Đóng tiền\nđiện', 'color': const Color(0xFFFFF9C4)},
      {'icon': '📦', 'label': 'Gửi đồ', 'color': const Color(0xFFE1F5FE)},
      {'icon': '🧹', 'label': 'Mày lành', 'color': const Color(0xFFE0F2F1)},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: utilities.length,
      itemBuilder: (context, index) {
        final util = utilities[index];
        return GestureDetector(
          onTap: () {},
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: util['color'] as Color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    util['icon'] as String,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                util['label'] as String,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black87,
                  height: 1.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2196F3),
        unselectedItemColor: Colors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.star_outline),
            activeIcon: Icon(Icons.star),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '',
          ),
        ],
      ),
    );
  }
}
