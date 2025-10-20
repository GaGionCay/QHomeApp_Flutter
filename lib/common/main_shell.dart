import 'package:flutter/material.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../register/register_service_list_screen.dart';
import '../register/register_service_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with TickerProviderStateMixin {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    HomeScreen(),
    RegisterServiceScreen(),
    RegisterServiceListScreen(),
    ProfileScreen(),
  ];

  final List<IconData> _icons = [
    Icons.home,
    Icons.build,
    Icons.list_alt,
    Icons.person,
  ];

  final List<String> _labels = [
    'Trang chủ',
    'Đăng ký',
    'Danh sách',
    'Hồ sơ',
  ];

  late List<AnimationController> _controllers;
  late List<Animation<double>> _iconScales;
  late List<Animation<double>> _labelFades;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);

    _controllers = List.generate(_pages.length, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 250),
      );
    });

    _iconScales = _controllers
        .map((c) => Tween<double>(begin: 1.0, end: 1.25).animate(
              CurvedAnimation(parent: c, curve: Curves.easeOutBack),
            ))
        .toList();

    _labelFades = _controllers
        .map((c) => Tween<double>(begin: 0.0, end: 1.0).animate(c))
        .toList();

    _controllers[_selectedIndex].forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index != _selectedIndex) {
      _controllers[_selectedIndex].reverse();
      _controllers[index].forward();

      setState(() => _selectedIndex = index);

      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Widget _buildGradientIcon(IconData icon) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFF4DB6AC), Color(0xFF26A69A), Color(0xFF00897B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      child: Icon(icon, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          setState(() => _selectedIndex = index);
        },
        children: List.generate(
          _pages.length,
          (index) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.05, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: _pages[index],
          ),
        ),
      ),

      // 🔻 Thanh điều hướng
      bottomNavigationBar: Container(
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
            ),
          ],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_pages.length, (index) {
            final isSelected = _selectedIndex == index;

            return Expanded(
              child: InkWell(
                onTap: () => _onItemTapped(index),
                borderRadius: BorderRadius.circular(16),
                splashColor: Colors.teal.withOpacity(0.2),
                highlightColor: Colors.transparent,
                child: AnimatedBuilder(
                  animation: _controllers[index],
                  builder: (context, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: _iconScales[index].value,
                          child: isSelected
                              ? _buildGradientIcon(_icons[index])
                              : Icon(_icons[index], color: Colors.grey, size: 24),
                        ),
                        const SizedBox(height: 4),
                        Opacity(
                          opacity: _labelFades[index].value,
                          child: Text(
                            _labels[index],
                            style: TextStyle(
                              color: isSelected ? Colors.teal : Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
