import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import '../auth/token_storage.dart';
import '../core/event_bus.dart';
import '../news/news_detail_screen.dart';
import '../news/news_screen.dart';
import '../notifications/notification_screen.dart';
import '../profile/profile_service.dart';
import '../websocket/web_socket_service.dart';
import '../invoices/invoice_list_screen.dart';
import '../invoices/paid_invoices_screen.dart';
import '../invoices/invoice_service.dart';
import '../charts/electricity_chart.dart';
import '../models/electricity_monthly.dart';
import '../service_registration/service_booking_service.dart';
import '../service_registration/service_detail_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  final void Function(int)? onNavigateToTab;
  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApiClient _apiClient;
  late final ServiceBookingService _serviceBookingService;
  late final WebSocketService _wsService;
  final _tokenStorage = TokenStorage();
  final _eventBus = AppEventBus();
  late AppLinks _appLinks;
  StreamSubscription? _paymentSub;

  Map<String, dynamic>? _profile;
  // Removed: List<NewsItem> _notifications = []; - now using ResidentNews from admin API
  List<Map<String, dynamic>> _unpaidBookings = [];
  List<ElectricityMonthly> _electricityMonthlyData = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _serviceBookingService = ServiceBookingService(_apiClient.dio);
    _wsService = WebSocketService();
    _appLinks = AppLinks();
    _initialize();
    _listenForPaymentResult();

    _eventBus.on('news_update', (_) async {
      debugPrint('🔔 HomeScreen nhận event news_update -> reload dữ liệu...');
      await _refreshAll();
    });

  }

  Future<void> _initialize() async {
    await _loadAllData();
    await _initRealTime();
  }

  Future<void> _initRealTime() async {
    try {
      final token = await _tokenStorage.readAccessToken() ?? '';
      final profile = await ProfileService(_apiClient.dio).getProfile();
      final userId = profile['id'].toString();

      _wsService.connect(
        token: token,
        userId: userId,
        onNotification: (data) {
          debugPrint('🔔 Realtime notification received: $data');
          // Removed: News notifications handling - now using ResidentNews from admin API
          // WebSocket notifications can be handled separately if needed
        },
      );
    } catch (e) {
      debugPrint('⚠️ WebSocket init failed: $e');
    }
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    try {
      final profileFuture = ProfileService(_apiClient.dio).getProfile();
      // Removed: NewsService.getUnreadNotifications() - now using ResidentNews from admin API
      final unpaidBookingsFuture = _serviceBookingService.getUnpaidBookings();
      final electricityFuture = InvoiceService(_apiClient).getElectricityMonthlyData();

      final results = await Future.wait([
        profileFuture,
        unpaidBookingsFuture,
        electricityFuture,
      ]);

      final profile = results[0] as Map<String, dynamic>;
      final unpaidBookings = results[1] as List<Map<String, dynamic>>;
      final electricityData = results[2] as List<ElectricityMonthly>;

      if (mounted) {
        setState(() {
          _profile = profile;
          // Removed: _notifications - now using ResidentNews from admin API
          _unpaidBookings = unpaidBookings;
          _electricityMonthlyData = electricityData;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Load data error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshAll() async {
    await _loadAllData();
  }

  // Removed: int get unreadCount => _notifications.where((n) => !n.isRead).length; - now using ResidentNews from admin API
  int get unreadCount => 0; // Placeholder - notifications now come from admin API

  Widget _buildUnpaidBookingSection(Size size) {
    if (_unpaidBookings.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Dịch vụ cần thanh toán',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orangeAccent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_unpaidBookings.length}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._unpaidBookings.map((booking) {
          final serviceName = booking['service']?['name'] ?? 'Dịch vụ';
          final totalAmount = booking['totalAmount']?.toDouble() ?? 0.0;
          final bookingDate = booking['bookingDate'] != null
              ? DateTime.parse(booking['bookingDate'])
              : null;
          final startTime = booking['startTime'] ?? '';
          final endTime = booking['endTime'] ?? '';
          final bookingId = booking['id'] as int? ?? 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.orange.withOpacity(0.1),
                child: const Icon(Icons.event_available, color: Colors.orange),
              ),
              title: Text(
                serviceName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bookingDate != null)
                    Text(
                      'Ngày: ${DateFormat('dd/MM/yyyy').format(bookingDate)}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  if (startTime.isNotEmpty && endTime.isNotEmpty)
                    Text(
                      'Giờ: ${startTime.substring(0, 5)} - ${endTime.substring(0, 5)}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  Text(
                    'Số tiền: ${NumberFormat.currency(locale: "vi_VN", symbol: "₫").format(totalAmount)}',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              trailing: ElevatedButton(
                onPressed: () => _payBooking(bookingId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('Thanh toán'),
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _payBooking(int bookingId) async {
    try {
      final paymentUrl = await _serviceBookingService.getVnpayPaymentUrl(bookingId);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_booking_$bookingId', bookingId.toString());
      
      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _listenForPaymentResult() {
    _paymentSub = _appLinks.uriLinkStream.listen((Uri uri) {
      if (uri.scheme == 'qhomeapp' && uri.host == 'service-booking-result') {
        final status = uri.queryParameters['status'];
        final bookingIdStr = uri.queryParameters['bookingId'];
        
        if (status == 'success' && bookingIdStr != null) {
          final bookingId = int.tryParse(bookingIdStr);
          if (bookingId != null) {
            _removePendingBooking(bookingId);
            _refreshAll();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Thanh toán thành công!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        }
      }
    });
  }

  Future<void> _removePendingBooking(int bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_booking_$bookingId');
  }

  void dispose() {
    _paymentSub?.cancel();
    _wsService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double paddingH = size.width * 0.05;
    final double paddingV = size.height * 0.02;

    final name = _profile?['fullName'] ?? 'Cư dân';
    final avatarUrl = _profile?['avatarUrl'];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding:
                EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildModernHeader(size, name, avatarUrl)
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .slideY(begin: -0.2, curve: Curves.easeOutCubic),
                      SizedBox(height: size.height * 0.03),
                      if (_unpaidBookings.isNotEmpty) ...[
                        _buildUnpaidBookingSection(size),
                        SizedBox(height: size.height * 0.03),
                      ],
                      _buildNewsSection(size), // Thêm phần tin tức
                      SizedBox(height: size.height * 0.03),
                      if (_electricityMonthlyData.isNotEmpty) ...[
                        _buildElectricityChartSection(size),
                        SizedBox(height: size.height * 0.03),
                      ],
                      _buildCompactFeatureRow(size),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeader(Size size, String name, String? avatarUrl) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(size.width * 0.05),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00B686), Color(0xFF72EABF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: size.width * 0.1,
            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : const AssetImage('assets/images/avatar_placeholder.png')
                    as ImageProvider,
          ),
          SizedBox(width: size.width * 0.05),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Xin chào 👋",
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: size.width * 0.04)),
                SizedBox(height: size.height * 0.005),
                Text(name,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: size.width * 0.055,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSection(Size size) {
    // Removed: News notifications - now using ResidentNews from admin API
    // This section is kept for future notifications from other sources
    return const SizedBox.shrink();
  }

  Widget _buildNewsSection(Size size) {
    // Removed: News section - now using ResidentNews from admin API (NewsScreen)
    // Users can navigate to NewsScreen from menu or feature buttons
    return const SizedBox.shrink();
  }

  Widget _buildElectricityChartSection(Size size) {
    return Container(
      padding: EdgeInsets.all(size.width * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElectricityChart(
        monthlyData: _electricityMonthlyData,
      ),
    );
  }

  Widget _buildCompactFeatureRow(Size size) {
    final iconSize = size.width * 0.09;
    final labelSize = size.width * 0.032;

    final features = [
      {
        'icon': Icons.description,
        'label': 'Hóa đơn mới',
        'color': Colors.purple,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const InvoiceListScreen(),
            ),
          );
        },
      },
      {
        'icon': Icons.check_circle,
        'label': 'Đã thanh toán',
        'color': Colors.green,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PaidInvoicesScreen(),
            ),
          );
        },
      },
      {
        'icon': Icons.article,
        'label': 'Tin tức',
        'color': Colors.blue,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NewsScreen(),
            ),
          );
        },
      },
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: features.map((f) {
        return Flexible(
          child: GestureDetector(
            onTap: f['onTap'] as VoidCallback,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: iconSize,
                  backgroundColor: (f['color'] as Color).withOpacity(0.15),
                  child: Icon(f['icon'] as IconData,
                      color: f['color'] as Color, size: iconSize),
                ),
                SizedBox(height: size.height * 0.008),
                Text(f['label'] as String,
                    style: TextStyle(
                        fontSize: labelSize, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

