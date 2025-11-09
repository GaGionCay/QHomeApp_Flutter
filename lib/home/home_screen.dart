import 'package:flutter/material.dart';
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import '../residents/household_member_registration_screen.dart';
import '../residents/account_request_status_screen.dart';
import '../theme/app_colors.dart';
import '../auth/asset_maintenance_api_client.dart';
import '../service_registration/service_booking_service.dart';
import '../service_registration/unpaid_service_bookings_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int)? onNavigateToTab;
  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApiClient _apiClient;
  late final ContractService _contractService;
  late final AssetMaintenanceApiClient _assetMaintenanceClient;
  late final ServiceBookingService _serviceBookingService;
  final _eventBus = AppEventBus();
  late AppLinks _appLinks;
  StreamSubscription? _paymentSub;

  Map<String, dynamic>? _profile;
  // Removed: List<NewsItem> _notifications = []; - now using ResidentNews from admin API
  List<ElectricityMonthly> _electricityMonthlyData = [];
  List<UnitInfo> _units = [];
  String? _selectedUnitId;
  int _unpaidBookingCount = 0;

  static const _selectedUnitPrefsKey = 'selected_unit_id';

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _contractService = ContractService(_apiClient);
    _assetMaintenanceClient = AssetMaintenanceApiClient();
    _serviceBookingService = ServiceBookingService(_assetMaintenanceClient);
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
    
    await _loadUnpaidServices();

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshAll() async {
    await _loadAllData();
  }

  Future<void> _loadUnpaidServices() async {
    try {
      final bookings = await _serviceBookingService.getUnpaidBookings();
      if (mounted) {
        setState(() {
          _unpaidBookingCount = bookings.length;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Không thể tải dịch vụ chưa thanh toán: $e');
      if (mounted) {
        setState(() {
          _unpaidBookingCount = 0;
        });
      }
    }
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

  Widget _buildUnpaidSummaryCard(BuildContext context) {
    if (_unpaidBookingCount <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return _HomeGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _openUnpaidBookingsScreen,
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.pending_actions_outlined,
                color: AppColors.warning,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dịch vụ chưa thanh toán',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bạn có $_unpaidBookingCount dịch vụ cần xử lý.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.arrow_forward_ios_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _openUnpaidBookingsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const UnpaidServiceBookingsScreen(),
      ),
    );
    await _loadUnpaidServices();
  }

  void _listenForPaymentResult() {
    _paymentSub = _appLinks.uriLinkStream.listen((Uri uri) {
      if (uri.scheme == 'qhomeapp' && uri.host == 'service-booking-result') {
        final status = uri.queryParameters['status'];
        
        if (status == 'success') {
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
    });
  }

  @override
  void dispose() {
    _paymentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    final name = _profile?['fullName'] ??
        _profile?['username'] ??
        'Cư dân';
    final avatarUrl = _profile?['avatarUrl'] as String?;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: _loading
              ? const _HomeLoadingState()
              : RefreshIndicator(
                  color: theme.colorScheme.primary,
                  onRefresh: _refreshAll,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: media.size.width > 900 ? media.size.width * 0.18 : 24,
                          vertical: 24,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate.fixed(
                            [
                              _buildGreetingSection(
                                context: context,
                                name: name,
                                avatarUrl: avatarUrl,
                              ),
                              const SizedBox(height: 24),
                              _buildWeatherAndAlerts(context),
                              const SizedBox(height: 24),
                              _buildServiceDeck(context),
                              const SizedBox(height: 24),
                              if (_unpaidBookingCount > 0)
                                _buildUnpaidSummaryCard(context),
                              if (_unpaidBookingCount > 0)
                                const SizedBox(height: 24),
                              if (_electricityMonthlyData.isNotEmpty)
                                _buildElectricityChartSection(media.size),
                              if (_electricityMonthlyData.isNotEmpty)
                                const SizedBox(height: 24),
                              if (_ownerUnits.isNotEmpty)
                                _buildHouseholdManagementCard(media.size),
                              if (_ownerUnits.isNotEmpty)
                                const SizedBox(height: 24),
                              _buildCompactFeatureRow(media.size),
                              const SizedBox(height: 48),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildGreetingSection({
    required BuildContext context,
    required String name,
    String? avatarUrl,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final greet = _greetingMessage();
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: AppColors.primaryGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: AppColors.elevatedShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
      child: Row(
        children: [
          Container(
            height: 72,
            width: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 2),
            ),
            child: ClipOval(
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                    )
                  : Image.asset(
                      'assets/images/avatar_placeholder.png',
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greet,
                  style: textTheme.titleLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Chào buổi ${_localizedPeriod(now)}, $name!',
                  style: textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                _buildUnitSelectorWidget(MediaQuery.of(context).size),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherAndAlerts(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final alertCount = _unpaidBookingCount;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 520;

        Widget buildWeatherCard() => _HomeGlassCard(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.wb_sunny_outlined,
                      color: AppColors.primaryBlue,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thời tiết hôm nay',
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Thông tin thời tiết đang cập nhật. Vui lòng kiểm tra lại sau.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );

        Widget buildAlertsCard() => _HomeGlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.notifications_active_outlined,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thông báo nhanh',
                            style: textTheme.titleMedium,
                          ),
                          Text(
                            alertCount > 0
                                ? '$alertCount dịch vụ cần xử lý'
                                : 'Không có cảnh báo mới',
                            style: textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildStatusChip(
                          context,
                          icon: Icons.receipt_long,
                          label: 'Hóa đơn',
                          value: _unpaidBookingCount.toString(),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusChip(
                          context,
                          icon: Icons.notifications_none,
                          label: 'Thông báo',
                          value: unreadCount.toString(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: buildWeatherCard()),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: buildAlertsCard()),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildWeatherCard(),
            const SizedBox(height: 16),
            buildAlertsCard(),
          ],
        );
      },
    );
  }

  Widget _buildStatusChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surface,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '$label · $value',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceDeck(BuildContext context) {
    final items = _serviceItems(context);
    return _HomeGlassCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Dịch vụ dành cho bạn',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => widget.onNavigateToTab?.call(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              for (final entry in items.asMap().entries)
                TweenAnimationBuilder<double>(
                  key: ValueKey(entry.value.title),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: entry.key == items.length - 1 ? 0 : 12,
                    ),
                    child: _ServiceCard(data: entry.value),
                  ),
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 20),
                      child: child,
                    ),
                  ),
                ),
            ],
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
          color: Colors.white.withValues(alpha: 0.85),
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
        color: Colors.white.withValues(alpha: 0.18),
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

  Widget _buildElectricityChartSection(Size size) {
    final theme = Theme.of(context);

    return _HomeGlassCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Theo dõi điện năng',
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => widget.onNavigateToTab?.call(1),
                icon: const Icon(Icons.auto_graph_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(12),
            child: ElectricityChart(
              monthlyData: _electricityMonthlyData,
            ),
          ),
        ],
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

    final theme = Theme.of(context);

    return _HomeGlassCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quản lý hộ gia đình',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
              Text(
                '$residentName là chủ hộ của ${ownerUnits.length} căn hộ.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
          const SizedBox(height: 16),
          _HomeActionTile(
            icon: Icons.group_add_outlined,
            accentColor: AppColors.primaryEmerald,
            title: 'Đăng ký tài khoản cho thành viên',
            subtitle: const [
              'Gửi lời mời tạo tài khoản cho người thân trong hộ gia đình.',
            ],
            onPressed: () {
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
            actionLabel: 'Tạo yêu cầu',
          ),
          const Divider(),
          _HomeActionTile(
            icon: Icons.history_rounded,
            accentColor: AppColors.primaryBlue,
            title: 'Theo dõi trạng thái yêu cầu',
            subtitle: const [
              'Kiểm tra các yêu cầu đã gửi và cập nhật kết quả nhanh chóng.',
            ],
            onPressed: () {
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
            actionLabel: 'Xem danh sách',
          ),
        ],
      ),
    );
  }

  Widget _buildCompactFeatureRow(Size size) {
    final theme = Theme.of(context);
    final features = [
      _FeatureAction(
        icon: Icons.description_outlined,
        label: 'Hóa đơn mới',
        accent: AppColors.primaryBlue,
        onTap: () {
          debugPrint(
              '🧾 [HomeScreen] mở Hóa đơn mới với unit=$_selectedUnitId, units=${_units.length}');
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
      ),
      _FeatureAction(
        icon: Icons.verified_outlined,
        label: 'Đã thanh toán',
        accent: AppColors.primaryEmerald,
        onTap: () {
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
      ),
      _FeatureAction(
        icon: Icons.newspaper_outlined,
        label: 'Tin tức',
        accent: AppColors.warning,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NewsScreen(),
            ),
          );
        },
      ),
    ];

    final width = size.width;
    double? itemWidth;
    if (width > 820) {
      itemWidth = (width - 120) / 3;
    } else if (width > 560) {
      itemWidth = (width - 96) / 2;
    } else {
      itemWidth = width - 48;
    }

    return Wrap(
      spacing: 18,
      runSpacing: 18,
      children: features.map((feature) {
        return _HomeGlassCard(
          width: itemWidth,
          padding: const EdgeInsets.all(18),
          child: InkWell(
            onTap: feature.onTap,
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: feature.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(feature.icon, color: feature.accent),
                ),
                const SizedBox(height: 18),
                Text(
                  feature.label,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Chạm để xem chi tiết',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _greetingMessage() {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Một buổi sáng tươi đẹp';
    if (hour < 14) return 'Chúc buổi trưa giàu năng lượng';
    if (hour < 18) return 'Buổi chiều an yên';
    return 'Tối thư giãn cùng gia đình';
  }

  String _localizedPeriod(DateTime now) {
    final hour = now.hour;
    if (hour < 11) return 'sáng';
    if (hour < 14) return 'trưa';
    if (hour < 18) return 'chiều';
    return 'tối';
  }

  List<_ServiceCardData> _serviceItems(BuildContext context) {
    return [
      _ServiceCardData(
        title: 'Gửi xe',
        subtitle: 'Đăng ký thẻ xe, quản lý bãi đỗ',
        icon: Icons.local_parking_outlined,
        accent: AppColors.primaryBlue,
        onTap: () => widget.onNavigateToTab?.call(1),
      ),
      _ServiceCardData(
        title: 'Phản ánh',
        subtitle: 'Gửi yêu cầu hỗ trợ tới ban quản lý',
        icon: Icons.support_agent_outlined,
        accent: AppColors.warning,
        onTap: () => widget.onNavigateToTab?.call(1),
      ),
      _ServiceCardData(
        title: 'Thanh toán',
        subtitle: 'Xem và thanh toán hóa đơn dịch vụ',
        icon: Icons.account_balance_wallet_outlined,
        accent: AppColors.primaryEmerald,
        onTap: () {
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
      ),
      _ServiceCardData(
        title: 'Tiện ích',
        subtitle: 'Đặt lịch tiện ích cộng đồng',
        icon: Icons.spa_outlined,
        accent: Colors.purpleAccent,
        onTap: () => widget.onNavigateToTab?.call(1),
      ),
      _ServiceCardData(
        title: 'Cộng đồng',
        subtitle: 'Tin tức, sự kiện cho cư dân',
        icon: Icons.supervised_user_circle_outlined,
        accent: AppColors.primaryBlue.withValues(alpha: 0.8),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NewsScreen(),
            ),
          );
        },
      ),
    ];
  }
}

class _HomeGlassCard extends StatelessWidget {
  const _HomeGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.width,
  });

  final Widget child;
  final EdgeInsets padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
        boxShadow: AppColors.subtleShadow,
      ),
      padding: padding,
      child: child,
    );
  }
}

class _ServiceCardData {
  const _ServiceCardData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.data});

  final _ServiceCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _HomeGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: InkWell(
          onTap: data.onTap,
          borderRadius: BorderRadius.circular(22),
          child: Row(
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  color: data.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(data.icon, color: data.accent, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeActionTile extends StatelessWidget {
  const _HomeActionTile({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    required this.actionLabel,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final List<String> subtitle;
  final VoidCallback onPressed;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    ...subtitle.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          line,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.56),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureAction {
  const _FeatureAction({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
}

class _HomeLoadingState extends StatelessWidget {
  const _HomeLoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Đang chuẩn bị không gian sống của bạn...',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

