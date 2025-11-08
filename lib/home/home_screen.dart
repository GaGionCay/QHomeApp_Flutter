import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import '../core/event_bus.dart';
import '../news/news_screen.dart';
import '../profile/profile_service.dart';
import '../contracts/contract_service.dart';
import '../invoices/invoice_list_screen.dart';
import '../invoices/paid_invoices_screen.dart';
import '../invoices/invoice_service.dart';
import '../charts/electricity_chart.dart';
import '../models/electricity_monthly.dart';
import '../models/unit_info.dart';
import '../service_registration/service_booking_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import '../residents/household_member_registration_screen.dart';
import '../residents/account_request_status_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int)? onNavigateToTab;
  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApiClient _apiClient;
  late final ServiceBookingService _serviceBookingService;
  late final ContractService _contractService;
  final _eventBus = AppEventBus();
  late AppLinks _appLinks;
  StreamSubscription? _paymentSub;

  Map<String, dynamic>? _profile;
  // Removed: List<NewsItem> _notifications = []; - now using ResidentNews from admin API
  List<Map<String, dynamic>> _unpaidBookings = [];
  List<ElectricityMonthly> _electricityMonthlyData = [];
  List<UnitInfo> _units = [];
  String? _selectedUnitId;

  static const _selectedUnitPrefsKey = 'selected_unit_id';

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _serviceBookingService = ServiceBookingService(_apiClient.dio);
    _contractService = ContractService(_apiClient);
    _appLinks = AppLinks();
    _initialize();
    _listenForPaymentResult();

    _eventBus.on('news_update', (_) async {
      debugPrint('🔔 HomeScreen nhận event news_update -> reload dữ liệu...');
      await _refreshAll();
    });

  }

  Future<void> _initialize() async {
    await _loadUnitContext();
    await _loadAllData();
    await _initRealTime();
  }

  Future<void> _loadUnitContext() async {
    try {
      final units = await _contractService.getMyUnits();
      final prefs = await SharedPreferences.getInstance();
      final savedUnitId = prefs.getString(_selectedUnitPrefsKey);

      String? nextSelected;
      if (units.isNotEmpty) {
        final exists = units.any((unit) => unit.id == savedUnitId);
        if (exists && savedUnitId != null) {
          nextSelected = savedUnitId;
        } else {
          nextSelected = units.first.id;
        }
      }

      if (mounted) {
        setState(() {
          _units = units;
          _selectedUnitId = nextSelected;
        });
      }

      if (nextSelected != null && nextSelected != savedUnitId) {
        await prefs.setString(_selectedUnitPrefsKey, nextSelected);
      }
    } catch (e) {
      debugPrint('⚠️ Load unit context error: $e');
      if (mounted) {
        setState(() {
          _units = [];
          _selectedUnitId = null;
        });
      }
    }
  }

  Future<void> _initRealTime() async {
    debugPrint('ℹ️ WebSocket connection temporarily disabled');
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    
    // Load profile (required)
    try {
      final profile = await ProfileService(_apiClient.dio).getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Load profile error: $e');
      // Continue even if profile fails
    }
    
    // Load unpaid bookings (optional)
    try {
      final unpaidBookings = await _serviceBookingService.getUnpaidBookings();
      if (mounted) {
        setState(() {
          _unpaidBookings = unpaidBookings;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Load unpaid bookings error: $e');
      // Continue with empty list
      if (mounted) {
        setState(() {
          _unpaidBookings = [];
        });
      }
    }
    
    // Load electricity data (optional)
    try {
      final invoiceService = InvoiceService(_apiClient);
      final electricityData = await invoiceService.getElectricityMonthlyData(
        unitId: _selectedUnitId,
      );
      if (mounted) {
        setState(() {
          _electricityMonthlyData = electricityData;
        });
      }
    } catch (e) {
      debugPrint('ℹ️ Không có dữ liệu tiền điện (coi như đã thanh toán hết)');
      // Continue with empty list
      if (mounted) {
        setState(() {
          _electricityMonthlyData = [];
        });
      }
    }
    
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshAll() async {
    await _loadAllData();
  }

  Future<void> _onUnitChanged(String? unitId) async {
    if (unitId == null || unitId == _selectedUnitId) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedUnitPrefsKey, unitId);

    if (mounted) {
      setState(() {
        _selectedUnitId = unitId;
      });
    }

    await _loadAllData();
  }

  List<UnitInfo> get _ownerUnits {
    final residentId = _profile?['residentId']?.toString();
    if (residentId == null || residentId.isEmpty) return [];
    return _units.where((unit) => unit.isPrimaryResident(residentId)).toList();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double paddingH = size.width * 0.05;
    final double paddingV = size.height * 0.02;

    // Priority: fullName > username > default
    final name = _profile?['fullName'] ?? 
                 _profile?['username'] ?? 
                 'Cư dân';
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
                      if (_ownerUnits.isNotEmpty) ...[
                        _buildHouseholdManagementCard(size),
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
                SizedBox(height: size.height * 0.015),
                _buildUnitSelectorWidget(size),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitSelectorWidget(Size size) {
    if (_units.isEmpty) {
      debugPrint('🏠 [HomeScreen] Không có căn hộ nào để chọn');
      return Text(
        'Bạn chưa được gán vào căn hộ nào',
        style: TextStyle(
          color: Colors.white.withOpacity(0.85),
          fontSize: size.width * 0.035,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final currentUnitId = _selectedUnitId ?? _units.first.id;
    debugPrint('🏠 [HomeScreen] Hiển thị dropdown với ${_units.length} căn hộ, đang chọn $currentUnitId');

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size.width * 0.035,
        vertical: size.height * 0.008,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white30, width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentUnitId,
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          style: TextStyle(
            color: Colors.black87,
            fontSize: size.width * 0.038,
            fontWeight: FontWeight.w600,
          ),
          selectedItemBuilder: (context) {
            return _units.map((unit) {
              return Text(
                unit.displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: size.width * 0.038,
                ),
              );
            }).toList();
          },
          items: _units.map((unit) {
            return DropdownMenuItem<String>(
              value: unit.id,
              child: Text(unit.displayName),
            );
          }).toList(),
          onChanged: (value) {
            debugPrint('🏠 [HomeScreen] Người dùng chọn căn hộ $value');
            _onUnitChanged(value);
          },
        ),
      ),
    );
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

  Widget _buildHouseholdManagementCard(Size size) {
    final ownerUnits = _ownerUnits;
    if (ownerUnits.isEmpty) return const SizedBox.shrink();

    final defaultUnitId = ownerUnits.any((unit) => unit.id == _selectedUnitId)
        ? (_selectedUnitId ?? ownerUnits.first.id)
        : ownerUnits.first.id;

    final residentName = _profile?['fullName']?.toString() ??
        _profile?['username']?.toString() ??
        'Bạn';

    return Container(
      width: double.infinity,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quản lý hộ gia đình',
            style: TextStyle(
              fontSize: size.width * 0.045,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$residentName là chủ hộ của ${ownerUnits.length} căn hộ.',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: size.width * 0.034,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFE0F7FA),
              child: Icon(Icons.group_add, color: Colors.teal.shade600),
            ),
            title: const Text(
              'Đăng ký tài khoản cho thành viên',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Chọn thành viên chưa có tài khoản để gửi yêu cầu tạo tài khoản.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HouseholdMemberRegistrationScreen(
                    unit: ownerUnits.firstWhere(
                      (unit) => unit.id == defaultUnitId,
                      orElse: () => ownerUnits.first,
                    ),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFF1F8E9),
              child: Icon(Icons.history, color: Colors.lightGreen.shade700),
            ),
            title: const Text(
              'Theo dõi trạng thái yêu cầu',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Xem kết quả các yêu cầu tạo tài khoản đã gửi.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AccountRequestStatusScreen(
                    units: ownerUnits,
                    initialUnitId: defaultUnitId,
                  ),
                ),
              );
            },
          ),
        ],
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
          debugPrint('🧾 [HomeScreen] mở Hóa đơn mới với unit=$_selectedUnitId, units=${_units.length}');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InvoiceListScreen(
                initialUnitId: _selectedUnitId,
                initialUnits: _units,
              ),
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
              builder: (_) => PaidInvoicesScreen(
                initialUnitId: _selectedUnitId,
                initialUnits: _units,
              ),
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

