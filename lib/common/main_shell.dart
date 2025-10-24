import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/news/news_screen.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'package:http/http.dart' as http;
import '../core/event_bus.dart';
import '../home/home_screen.dart';
import '../news/news_detail_screen.dart';
import '../register/register_service_screen.dart';
import '../auth/api_client.dart';
import 'menu_screen.dart';

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
  late final List<Widget> _pages;
  StompClient? _stompClient;
  final ApiClient _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _connectWebSocket();

    _pages = [
      HomeScreen(onNavigateToTab: _onItemTapped),
      const NewsScreen(),
      const RegisterServiceScreen(),
      const MenuScreen(),
    ];
  }

  void _connectWebSocket() async {
    final token = await _api.storage.readAccessToken();
    if (token == null) {
      debugPrint('⚠️ Không có token, bỏ qua kết nối WebSocket');
      return;
    }

    _stompClient = StompClient(
      config: StompConfig.sockJS(
        url: 'http://192.168.100.33:8080/ws',
        onConnect: (frame) {
          debugPrint('✅ WebSocket connected');

          _stompClient?.subscribe(
            destination: '/topic/news',
            callback: (frame) {
              if (frame.body != null) {
                final data = json.decode(frame.body!);
                _showNotificationPopup(data);

                AppEventBus().emit('news_update');
              }
            },
          );
        },
        onWebSocketError: (error) => debugPrint('❌ WS error: $error'),
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        reconnectDelay: const Duration(seconds: 5),
        heartbeatIncoming: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 10),
      ),
    );

    try {
      _stompClient?.activate();
    } catch (e) {
      debugPrint('❗ Failed to activate WebSocket: $e');
    }
  }

  void _showNotificationPopup(Map<String, dynamic> data) {
    if (!mounted) return;
    final attachments = (data['attachments'] as List<dynamic>?)
        ?.map((a) => NewsAttachmentDto.fromJson(a))
        .toList();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(data['title'] ?? 'Thông báo mới'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data['summary'] ?? ''),
              if (attachments != null && attachments.isNotEmpty)
                ...attachments.map(
                  (a) => TextButton.icon(
                    icon: const Icon(Icons.attach_file),
                    label: Text(a.filename),
                    onPressed: () => _handleAttachment(a.url),
                  ),
                ),
            ],
          ),
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
      ),
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
                if (!mounted) return;
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

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  void dispose() {
    _stompClient?.deactivate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _pages),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_outlined, Icons.home, 'Trang chủ'),
                _buildNavItem(
                    1, Icons.article_outlined, Icons.article, 'Tin tức'),
                _buildNavItem(2, Icons.app_registration_outlined,
                    Icons.app_registration, 'Dịch vụ'),
                _buildNavItem(3, Icons.menu_outlined, Icons.menu, 'Menu'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => _onItemTapped(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF26A69A).withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: AnimatedScale(
            scale: isSelected ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected
                      ? const Color(0xFF26A69A)
                      : Colors.grey.shade600,
                  size: isSelected ? 26 : 24,
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isSelected
                        ? const Color(0xFF26A69A)
                        : Colors.grey.shade600,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
