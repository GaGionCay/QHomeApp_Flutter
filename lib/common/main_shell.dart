import 'dart:io';
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../core/event_bus.dart';
import '../home/home_screen.dart';
import '../news/news_detail_screen.dart';
import '../service_registration/service_category_screen.dart';
import '../auth/api_client.dart';
import '../theme/app_colors.dart';
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

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    // Temporarily disabled WebSocket connection
    // _connectWebSocket();

    _pages = [
      HomeScreen(onNavigateToTab: _onItemTapped),
      const ServiceCategoryScreen(),
      const MenuScreen(),
    ];
  }

  // Temporarily disabled WebSocket connection
  /*
  void _connectWebSocket() async {
    final token = await _api.storage.readAccessToken();
    if (token == null) return;

    final profile = await ProfileService(_api.dio).getProfile();
    final userId = profile['id']?.toString() ?? '';

    _stompClient = StompClient(
      config: StompConfig.sockJS(
        url: '${ApiClient.FILE_BASE_URL}/ws',
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

          if (userId.isNotEmpty) {
            _stompClient?.subscribe(
              destination: '/topic/notifications/$userId',
              callback: (frame) {
                if (frame.body != null) {
                  final data = json.decode(frame.body!);
                  debugPrint('📨 Update read state: $data');
                  AppEventBus().emit('news_update');
                }
              },
            );
          } else {
            debugPrint('⚠️ userId trống — không đăng ký kênh cá nhân');
          }
        },
        onWebSocketError: (error) => debugPrint('❌ WS error: $error'),
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        reconnectDelay: const Duration(seconds: 5),
      ),
    );

    _stompClient?.activate();
  }
  */

  // ignore: unused_element
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
              final newsUuid = data['newsUuid'];
              if (newsUuid != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NewsDetailScreen(id: newsUuid.toString()),
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
    // Temporarily disabled WebSocket disconnection
    // _stompClient?.deactivate();
    AppEventBus().clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 320),
        transitionBuilder: (
          Widget child,
          Animation<double> primaryAnimation,
          Animation<double> secondaryAnimation,
        ) {
          return FadeThroughTransition(
            animation: primaryAnimation,
            secondaryAnimation: secondaryAnimation,
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_selectedIndex),
          child: _pages[_selectedIndex],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: NavigationBar(
              height: 72,
              indicatorColor: AppColors.primaryEmerald.withOpacity(0.12),
              backgroundColor: theme.colorScheme.surface,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Trang chủ',
                ),
                NavigationDestination(
                  icon: Icon(Icons.qr_code_scanner_outlined),
                  selectedIcon: Icon(Icons.app_registration_rounded),
                  label: 'Dịch vụ',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: 'Tiện ích',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
