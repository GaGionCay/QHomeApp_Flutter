import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_application_1/news/news_detail_screen.dart';
import 'package:flutter_application_1/news/news_screen.dart';
import 'package:flutter_application_1/post/post_feed_screen.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import '../auth/token_storage.dart';
import '../bills/bill_chart.dart';
import '../bills/bill_item.dart';
import '../bills/bill_list_screen.dart';
import '../bills/bill_paid_list_screen.dart';
import '../bills/bill_service.dart';
import '../core/event_bus.dart';
import '../news/news_item.dart';
import '../news/news_service.dart';
import '../profile/profile_service.dart';
import '../register/register_service_list_screen.dart';
import '../websocket/web_socket_service.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int)? onNavigateToTab;
  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApiClient _apiClient;
  late final BillService _billService;
  late final WebSocketService _wsService;
  final _tokenStorage = TokenStorage();
  final _eventBus = AppEventBus();

  StreamSubscription<String>? _eventSub;

  Map<String, dynamic>? _profile;
  List<NotificationItem> _notifications = [];
  List<BillItem> _unpaidBills = [];
  List<BillStatistics> _stats = [];

  bool _loading = true;
  String _filterType = 'Tất cả';
  final List<String> _billTypes = ['Tất cả', 'Điện', 'Nước', 'Internet'];

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _billService = BillService(_apiClient);
    _wsService = WebSocketService();
    _initialize();
    _eventBus.on('news_update', (_) async {
      debugPrint('🔔 HomeScreen nhận event news_update -> reload dữ liệu...');
      await _refreshAll();
    });

    // _eventBus.on('bill_update', (_) async {
    //   debugPrint('💰 HomeScreen nhận event bill_update -> reload dữ liệu...');
    //   await _refreshAll();
    // });
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
          debugPrint('🔔 Real-time notification received');
          _eventBus.emit('news_update');
        },
        onBill: (data) {
          debugPrint('💰 Real-time bill update received');
          _eventBus.emit('bill_update');
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
      final notiFuture = NotificationService(api: _apiClient, context: context)
          .getUnreadNotifications();
      final billFuture = _billService.getUnpaidBills();
      final statFuture = _billService.getStatistics();

      final results = await Future.wait([
        profileFuture,
        notiFuture,
        billFuture,
        statFuture,
      ]);

      final profile = results[0] as Map<String, dynamic>;
      final notis = results[1] as List<NotificationItem>;
      final billDtos = results[2] as List;
      final stats = results[3] as List<BillStatistics>;

      final bills = billDtos.map<BillItem>((dto) {
        DateTime billingMonth;
        DateTime? paymentDate;

        if (dto.billingMonth is String) {
          billingMonth = DateTime.parse(dto.billingMonth as String);
        } else if (dto.billingMonth is DateTime) {
          billingMonth = dto.billingMonth as DateTime;
        } else {
          billingMonth = DateTime.now();
        }

        if (dto.paymentDate != null) {
          if (dto.paymentDate is String) {
            paymentDate = DateTime.parse(dto.paymentDate as String);
          } else if (dto.paymentDate is DateTime) {
            paymentDate = dto.paymentDate as DateTime;
          }
        }

        return BillItem(
          id: dto.id ?? 0,
          billType: dto.billType ?? '',
          amount: dto.amount?.toDouble() ?? 0,
          billingMonth: billingMonth,
          status: dto.status ?? 'UNPAID',
          description: dto.description,
          paymentDate: paymentDate,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _profile = profile;
          _notifications = notis;
          _unpaidBills = bills;
          _stats = stats;
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

  @override
  void dispose() {
    _eventSub?.cancel();
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
                      _buildNotificationSection(size),
                      SizedBox(height: size.height * 0.03),
                      _buildUnpaidBillSection(size),
                      SizedBox(height: size.height * 0.03),
                      _buildStatisticsSection(size),
                      SizedBox(height: size.height * 0.03),
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
    if (_notifications.isEmpty) {
      return Card(
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Không có thông báo mới'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Thông báo mới',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            CircleAvatar(
              backgroundColor: Colors.redAccent,
              radius: 14,
              child: Text(
                '${_notifications.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            )
          ],
        ),
        ..._notifications.take(3).map((n) => Card(
              child: ListTile(
                title: Text(n.title),
                subtitle: Text(
                  n.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  DateFormat('dd/MM/yyyy').format(n.date),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => NewsDetailScreen(id: n.id))),
              ),
            )),
        if (_notifications.length > 3)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const NewsScreen())),
              child: const Text('Xem tất cả'),
            ),
          ),
      ],
    );
  }

  Widget _buildUnpaidBillSection(Size size) {
    if (_unpaidBills.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('Không có hóa đơn cần thanh toán')));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Hóa đơn cần thanh toán',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BillListScreen())),
              child: const Text('Xem tất cả'),
            ),
          ],
        ),
        ..._unpaidBills.take(3).map((b) => Card(
              child: ListTile(
                title: Text(
                    '${b.billType} - ${NumberFormat.currency(locale: "vi_VN", symbol: "₫").format(b.amount)}'),
                subtitle: Text(
                    'Hạn: ${DateFormat('dd/MM/yyyy').format(b.billingMonth)}'),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(b.status,
                      style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildStatisticsSection(Size size) {
    return Container(
      padding: EdgeInsets.all(size.width * 0.04),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Thống kê hóa đơn',
                  style: TextStyle(
                      fontSize: size.width * 0.05,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              DropdownButton<String>(
                value: _filterType,
                underline: const SizedBox(),
                borderRadius: BorderRadius.circular(12),
                items: _billTypes
                    .map((type) =>
                        DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (value) => setState(() => _filterType = value!),
              ),
            ],
          ),
          SizedBox(height: size.height * 0.015),
          BillChart(
              stats: _stats,
              filterType: _filterType,
              billService: _billService),
        ],
      ),
    );
  }

  Widget _buildCompactFeatureRow(Size size) {
    final iconSize = size.width * 0.09;
    final labelSize = size.width * 0.032;

    final features = [
      {
        'icon': Icons.local_parking,
        'label': 'Thẻ xe đã đăng ký',
        'color': Colors.lightBlueAccent,
        'onTap': () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const RegisterServiceListScreen())),
      },
      {
        'icon': Icons.payment,
        'label': 'Cần thanh toán',
        'color': Colors.redAccent,
        'onTap': () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const BillListScreen())),
      },
      {
        'icon': Icons.receipt_long,
        'label': 'Đã thanh toán',
        'color': Colors.green,
        'onTap': () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BillPaidListScreen())),
      },
      {
        'icon': Icons.post_add,
        'label': 'Đăng bài',
        'color': Colors.orangeAccent,
        'onTap': () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PostFeedScreen())),
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
