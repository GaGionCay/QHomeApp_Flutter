import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'package:http/http.dart' as http;

import '../home/home_screen.dart';
import '../news/news_detail_screen.dart';
import '../profile/profile_screen.dart';
import '../register/register_service_list_screen.dart';
import '../register/register_service_screen.dart';
import '../auth/api_client.dart';

class NewsAttachmentDto {
  final String filename;
  final String url;

  NewsAttachmentDto({required this.filename, required this.url});

  factory NewsAttachmentDto.fromJson(Map<String, dynamic> json) {
    return NewsAttachmentDto(
      filename: json['filename'] ?? '',
      url: json['url'] ?? '',
    );
  }
}

class MainShell extends StatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});
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

  StompClient? _stompClient;
  final ApiClient _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
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

    _connectWebSocket();
  }

  void _connectWebSocket() async {
    final token = await _api.storage.readAccessToken();
    print('🔑 Token: $token'); // debug

    _stompClient = StompClient(
      config: StompConfig(
        url: 'ws://192.168.100.33:8080/ws',
        onConnect: (frame) {
          print('✅ WebSocket connected!');
          _stompClient?.subscribe(
            destination: '/topic/news',
            callback: (frame) {
              print('📩 Received: ${frame.body}');
              if (frame.body != null) {
                final data = json.decode(frame.body!);
                _showNotificationPopup(data);
              }
            },
          );
        },
        onWebSocketError: (dynamic error) => print('❌ WS error: $error'),
        onDisconnect: (frame) => print('🔌 Disconnected from WebSocket'),
        stompConnectHeaders: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ),
    );

    _stompClient?.activate();
  }

  void _showNotificationPopup(Map<String, dynamic> data) {
    if (!mounted) return;

    final attachments = (data['attachments'] as List<dynamic>?)
        ?.map((a) => NewsAttachmentDto.fromJson(a))
        .toList();

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(data['title'] ?? 'Thông báo mới'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(data['summary'] ?? ''),
              if (attachments != null && attachments.isNotEmpty)
                Column(
                  children: attachments.map((a) {
                    return TextButton.icon(
                      icon: const Icon(Icons.attach_file),
                      label: Text(a.filename),
                      onPressed: () => _handleAttachment(a.url),
                    );
                  }).toList(),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                final newsId = data['newsId'];
                if (newsId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NewsDetailScreen(id: newsId),
                    ),
                  );
                }
              },
              child: const Text('Xem chi tiết'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleAttachment(String url) async {
    final filename = url.split('/').last;
    final fullUrl = ApiClient.fileUrl(url);

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Tải về máy'),
              onTap: () async {
                Navigator.pop(context);
                final dir = await getApplicationDocumentsDirectory();
                final filePath = '${dir.path}/$filename';
                final response = await http.get(Uri.parse(fullUrl));
                final file = File(filePath);
                await file.writeAsBytes(response.bodyBytes);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã tải về $filename')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text('Xem trực tiếp'),
              onTap: () async {
                Navigator.pop(context);
                final tempDir = await getTemporaryDirectory();
                final filePath = '${tempDir.path}/$filename';
                final response = await http.get(Uri.parse(fullUrl));
                final file = File(filePath);
                await file.writeAsBytes(response.bodyBytes);
                await OpenFile.open(filePath);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var c in _controllers) c.dispose();
    _stompClient?.deactivate();
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
                              : Icon(_icons[index],
                                  color: Colors.grey, size: 24),
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
