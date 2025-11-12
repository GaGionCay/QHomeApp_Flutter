import 'dart:convert';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
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
import '../news/resident_service.dart';
import '../notifications/notification_screen.dart';
import '../notifications/notification_read_store.dart';
import '../residents/household_member_request_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import '../residents/household_member_registration_screen.dart';
import '../residents/account_request_status_screen.dart';
import '../auth/asset_maintenance_api_client.dart';
import '../service_registration/service_booking_service.dart';
import '../service_registration/unpaid_service_bookings_screen.dart';
import '../feedback/feedback_screen.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../common/layout_insets.dart';

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
  final ResidentService _residentService = ResidentService();
  final _eventBus = AppEventBus();
  late AppLinks _appLinks;
  StreamSubscription? _paymentSub;

  Map<String, dynamic>? _profile;
  // Removed: List<NewsItem> _notifications = []; - now using ResidentNews from admin API
  List<ElectricityMonthly> _electricityMonthlyData = [];
  List<UnitInfo> _units = [];
  String? _selectedUnitId;
  int _unpaidBookingCount = 0;
  int _unpaidInvoiceCount = 0;
  int _unreadNotificationCount = 0;
  bool _isWeatherLoading = true;
  _WeatherSnapshot? _weatherSnapshot;
  String? _weatherError;
  static _WeatherSnapshot? _cachedWeatherSnapshot;
  static DateTime? _cachedWeatherFetchedAt;
  static const Duration _weatherRefreshInterval = Duration(minutes: 30);

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
    _loadWeatherSnapshot();

    _eventBus.on('news_update', (_) async {
      debugPrint('🔔 HomeScreen nhận event news_update -> reload dữ liệu...');
      await _refreshAll();
    });
    _eventBus.on('notifications_update', (_) async {
      debugPrint(
          '🔔 HomeScreen nhận event notifications_update -> cập nhật quick alerts...');
      await _loadUnreadNotifications();
    });
    _eventBus.on('unit_context_changed', (data) {
      if (!mounted) return;
      final unitId = (data is String && data.isNotEmpty) ? data : null;
      unawaited(_onUnitChanged(unitId));
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

    final invoiceService = InvoiceService(_apiClient);

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

    await Future.wait([
      _loadUnpaidServices(),
      _loadUnpaidInvoices(invoiceService),
      _loadUnreadNotifications(),
    ]);

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

  Future<void> _loadUnpaidInvoices(InvoiceService invoiceService) async {
    try {
      final categories = await invoiceService.getUnpaidInvoicesByCategory(
          unitId: _selectedUnitId);
      final total = categories.fold<int>(
          0, (sum, category) => sum + category.invoiceCount);
      if (mounted) {
        setState(() {
          _unpaidInvoiceCount = total;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Không thể tải hóa đơn chưa thanh toán: $e');
      if (mounted) {
        setState(() {
          _unpaidInvoiceCount = 0;
        });
      }
    }
  }

  Future<void> _loadUnreadNotifications() async {
    final residentId = _profile?['residentId']?.toString();
    if (residentId == null || residentId.isEmpty) {
      if (mounted) {
        setState(() => _unreadNotificationCount = 0);
      }
      return;
    }

    UnitInfo? selectedUnit;
    if (_selectedUnitId != null) {
      for (final unit in _units) {
        if (unit.id == _selectedUnitId) {
          selectedUnit = unit;
          break;
        }
      }
    }
    selectedUnit ??= _units.isNotEmpty ? _units.first : null;

    String? targetBuildingId =
        selectedUnit?.buildingId ?? _profile?['buildingId']?.toString();

    if (targetBuildingId == null || targetBuildingId.isEmpty) {
      if (mounted) {
        setState(() => _unreadNotificationCount = 0);
      }
      return;
    }

    try {
      final notifications = await _residentService.getResidentNotifications(
        residentId,
        targetBuildingId,
      );
      final readIds = await NotificationReadStore.load(residentId);
      final unread = notifications
          .where((notification) => !readIds.contains(notification.id))
          .length;
      if (mounted) {
        setState(() => _unreadNotificationCount = unread);
      }
    } catch (e) {
      debugPrint('⚠️ Không thể tải thông báo chưa đọc: $e');
      if (mounted) {
        setState(() => _unreadNotificationCount = 0);
      }
    }
  }

  Future<void> _loadWeatherSnapshot({bool force = false}) async {
    if (!force &&
        _cachedWeatherSnapshot != null &&
        _cachedWeatherFetchedAt != null &&
        DateTime.now().difference(_cachedWeatherFetchedAt!) <
            _weatherRefreshInterval) {
      if (mounted) {
        setState(() {
          _weatherSnapshot = _cachedWeatherSnapshot;
          _weatherError = null;
          _isWeatherLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isWeatherLoading = true;
      _weatherError = null;
    });

    try {
      double? latitude;
      double? longitude;
      String? city;

      final position = await _getDevicePosition();
      if (position != null) {
        latitude = position.latitude;
        longitude = position.longitude;
        city = await _resolveLocality(latitude, longitude);
      }

      if (latitude == null || longitude == null) {
        final locationResponse =
            await http.get(Uri.parse('https://ipapi.co/json/')).timeout(
                  const Duration(seconds: 6),
                );

        if (locationResponse.statusCode == 429) {
          throw _WeatherRateLimitException(source: 'ipapi.co');
        }

        if (locationResponse.statusCode != 200) {
          throw Exception(
              'Location lookup failed with status ${locationResponse.statusCode}');
        }

        final locationJson =
            jsonDecode(locationResponse.body) as Map<String, dynamic>;
        latitude = (locationJson['latitude'] as num?)?.toDouble();
        longitude = (locationJson['longitude'] as num?)?.toDouble();
        city = (locationJson['city'] as String?) ?? 'Khu dân cư của bạn';

        if (latitude == null || longitude == null) {
          throw Exception('Missing geolocation data');
        }
      }

      final double lat = latitude;
      final double lon = longitude;

      final weatherUri = Uri.https(
        'api.open-meteo.com',
        '/v1/forecast',
        <String, String>{
          'latitude': lat.toString(),
          'longitude': lon.toString(),
          'current_weather': 'true',
          'hourly': 'relativehumidity_2m',
          'timezone': 'auto',
        },
      );

      final weatherResponse =
          await http.get(weatherUri).timeout(const Duration(seconds: 6));

      if (weatherResponse.statusCode == 429) {
        throw _WeatherRateLimitException(source: 'open-meteo.com');
      }

      if (weatherResponse.statusCode != 200) {
        throw Exception(
            'Weather fetch failed with status ${weatherResponse.statusCode}');
      }

      final weatherJson =
          jsonDecode(weatherResponse.body) as Map<String, dynamic>;
      final current = weatherJson['current_weather'] as Map<String, dynamic>?;
      if (current == null) throw Exception('Missing current weather payload');

      final timezone = weatherJson['timezone'] as String?;
      final derivedCity = city ??
          (() {
            if (timezone == null) return null;
            if (!timezone.contains('/')) return timezone;
            final parts = timezone.split('/');
            return parts.last.replaceAll('_', ' ');
          })();

      final temperature = (current['temperature'] as num?)?.toDouble();
      final windSpeed = (current['windspeed'] as num?)?.toDouble();
      final weatherCode = current['weathercode'] as int? ?? 0;
      final humiditySeries = (weatherJson['hourly']
          as Map<String, dynamic>?)?['relativehumidity_2m'] as List<dynamic>?;
      final humidity = (humiditySeries != null && humiditySeries.isNotEmpty)
          ? (humiditySeries.first as num?)?.toDouble()
          : null;

      final descriptor = _describeWeatherCode(weatherCode);
      final fallbackLat = lat.toStringAsFixed(2);
      final fallbackLon = lon.toStringAsFixed(2);
      final snapshot = _WeatherSnapshot(
        city: derivedCity ?? 'Lat $fallbackLat, Lon $fallbackLon',
        temperatureCelsius: temperature ?? 0,
        weatherLabel: descriptor.label,
        weatherIcon: descriptor.icon,
        windSpeed: windSpeed,
        humidity: humidity,
        fetchedAt: DateTime.now(),
      );

      _cachedWeatherSnapshot = snapshot;
      _cachedWeatherFetchedAt = snapshot.fetchedAt;

      if (mounted) {
        setState(() {
          _weatherSnapshot = snapshot;
          _isWeatherLoading = false;
        });
      }
    } on _WeatherRateLimitException catch (e) {
      debugPrint(
          '⚠️ Weather rate limited by ${e.source}. Using cached data when available.');
      if (mounted) {
        setState(() {
          _weatherError =
              'Máy chủ thời tiết đang tạm giới hạn. Thử lại sau ít phút.';
          _isWeatherLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('⚠️ Không thể tải thời tiết: $e');
      debugPrint('↪ Weather stack trace: $stack');
      if (mounted) {
        setState(() {
          _weatherError = 'Không thể cập nhật thời tiết';
          _isWeatherLoading = false;
        });
      }
    }
  }

  Future<Position?> _getDevicePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('ℹ️ Location services disabled. Falling back to IP lookup.');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        debugPrint(
            'ℹ️ Location permission not granted. Falling back to IP lookup.');
        return null;
      }

      return Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
    } catch (e, stack) {
      debugPrint('⚠️ Failed to obtain device location: $e');
      debugPrint('↪ Location stack trace: $stack');
      return null;
    }
  }

  Future<String?> _resolveLocality(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);

      for (final placemark in placemarks) {
        final seen = <String>{};
        final ordered = <String>[];

        void addCandidate(String? value) {
          final trimmed = value?.trim();
          if (trimmed == null || trimmed.isEmpty || seen.contains(trimmed)) {
            return;
          }
          seen.add(trimmed);
          ordered.add(trimmed);
        }

        addCandidate(placemark.subLocality);
        addCandidate(placemark.locality);
        addCandidate(placemark.subAdministrativeArea);
        addCandidate(placemark.administrativeArea);
        addCandidate(placemark.country);

        if (ordered.isNotEmpty) {
          debugPrint(
              'ℹ️ Reverse geocode resolved to: ${ordered.take(4).join(' • ')}');
          final display = ordered.take(3).join(', ');
          return display;
        }
      }
    } catch (e, stack) {
      debugPrint('⚠️ Failed to reverse geocode position: $e');
      debugPrint('↪ Reverse geocode stack trace: $stack');
    }
    return null;
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
  int get unreadCount =>
      0; // Placeholder - notifications now come from admin API

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
                CupertinoIcons.timer,
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
                      color: theme.colorScheme.onSurface.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              CupertinoIcons.right_chevron,
              size: 18,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
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

  Future<void> _openUnpaidInvoicesScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceListScreen(
          initialUnitId: _selectedUnitId,
          initialUnits: _units,
        ),
      ),
    );
    final invoiceService = InvoiceService(_apiClient);
    await _loadUnpaidInvoices(invoiceService);
  }

  Future<void> _openNotificationsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NotificationScreen(),
      ),
    );
    await _loadUnreadNotifications();
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
    final themeController = context.watch<ThemeController>();
    final double bottomNavInset = LayoutInsets.bottomNavContentPadding(
      context,
      extra: -LayoutInsets.navBarHeight + 60,
      minimumGap: 16,
    );

    final name = _profile?['fullName'] ?? _profile?['username'] ?? 'Cư dân';
    final avatarUrl = _profile?['avatarUrl'] as String?;

    final backgroundGradient = theme.brightness == Brightness.dark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF020A16),
              Color(0xFF0D1E36),
              Color(0xFF041018),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEAF5FF),
              Color(0xFFF8FBFF),
              Colors.white,
            ],
          );

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: backgroundGradient,
              ),
            ),
          ),
          Positioned(
            top: -media.size.width * 0.25,
            right: -media.size.width * 0.1,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                width: media.size.width * 0.7,
                height: media.size.width * 0.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withOpacity(0.12),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
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
                              horizontal: media.size.width > 900
                                  ? media.size.width * 0.18
                                  : 24,
                              vertical: 24,
                            ),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate.fixed(
                                [
                                  _buildGreetingSection(
                                    context: context,
                                    name: name,
                                    avatarUrl: avatarUrl,
                                    themeController: themeController,
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
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(height: bottomNavInset),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGreetingSection({
    required BuildContext context,
    required String name,
    String? avatarUrl,
    required ThemeController themeController,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final greet = _greetingMessage();
    final now = DateTime.now();
    final isDark = themeController.isDark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: AppColors.heroBackdropGradient(),
        boxShadow: AppColors.elevatedShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 78,
                width: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.35), width: 2.4),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22102136),
                      blurRadius: 20,
                      offset: Offset(0, 12),
                    ),
                  ],
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
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white.withOpacity(0.8),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Chào buổi ${_localizedPeriod(now)}, $name!',
                      style: textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _buildUnitSelectorWidget(MediaQuery.of(context).size,
              isDarkMode: isDark),
        ],
      ),
    );
  }

  _WeatherDescriptor _describeWeatherCode(int code) {
    if (code == 0) {
      return const _WeatherDescriptor(
          'Trời quang', CupertinoIcons.sun_max_fill);
    } else if (<int>{1, 2}.contains(code)) {
      return const _WeatherDescriptor('Ít mây', CupertinoIcons.cloud_sun_fill);
    } else if (code == 3) {
      return const _WeatherDescriptor('Nhiều mây', CupertinoIcons.cloud_fill);
    } else if (<int>{45, 48}.contains(code)) {
      return const _WeatherDescriptor(
          'Sương mù', CupertinoIcons.cloud_fog_fill);
    } else if (<int>{51, 53, 55, 56, 57}.contains(code)) {
      return const _WeatherDescriptor(
          'Mưa phùn nhẹ', CupertinoIcons.cloud_drizzle_fill);
    } else if (<int>{61, 63, 65}.contains(code)) {
      return const _WeatherDescriptor(
          'Mưa rào', CupertinoIcons.cloud_rain_fill);
    } else if (<int>{66, 67, 80, 81, 82}.contains(code)) {
      return const _WeatherDescriptor(
          'Mưa lớn', CupertinoIcons.cloud_heavyrain_fill);
    } else if (<int>{71, 73, 75, 77, 85, 86}.contains(code)) {
      return const _WeatherDescriptor('Tuyết', CupertinoIcons.cloud_snow_fill);
    } else if (<int>{95, 96, 99}.contains(code)) {
      return const _WeatherDescriptor(
          'Dông', CupertinoIcons.cloud_bolt_rain_fill);
    }
    return const _WeatherDescriptor(
        'Thời tiết ổn định', CupertinoIcons.cloud_fill);
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${diff.inDays} ngày trước';
  }

  Widget _buildWeatherAndAlerts(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 520;

        Widget buildWeatherCard() {
          final snapshot = _weatherSnapshot;
          return _HomeGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  height: 58,
                  width: 58,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient(),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppColors.subtleShadow,
                  ),
                  child: Icon(
                    snapshot?.weatherIcon ?? CupertinoIcons.sparkles,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    child: _isWeatherLoading
                        ? Row(
                            key: const ValueKey('weather-loading'),
                            children: [
                              SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Đang cập nhật khí hậu...',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.7),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          )
                        : (_weatherError != null || snapshot == null)
                            ? Text(
                                _weatherError ?? 'Không lấy được thời tiết',
                                key: const ValueKey('weather-error'),
                                style: textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.7),
                                ),
                              )
                            : Column(
                                key: ValueKey(snapshot.city),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    snapshot.city,
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${snapshot.temperatureCelsius.toStringAsFixed(1)}°C • ${snapshot.weatherLabel}',
                                    style: textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  if (snapshot.windSpeed != null ||
                                      snapshot.humidity != null)
                                    Text(
                                      [
                                        if (snapshot.windSpeed != null)
                                          'Gió ${snapshot.windSpeed?.toStringAsFixed(0)} km/h',
                                        if (snapshot.humidity != null)
                                          'Độ ẩm ${snapshot.humidity?.toStringAsFixed(0)}%',
                                      ].join(' · '),
                                      style: textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.6),
                                      ),
                                    ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Cập nhật ${_formatTime(snapshot.fetchedAt)}',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.45),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Làm mới',
                  child: IconButton(
                    onPressed: _isWeatherLoading
                        ? null
                        : () => _loadWeatherSnapshot(force: true),
                    icon: Icon(
                      CupertinoIcons.refresh_bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

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
                          CupertinoIcons.bell_fill,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thông báo nhanh',
                              style: textTheme.titleMedium,
                            ),
                            Builder(
                              builder: (context) {
                                final summaryParts = <String>[];
                                if (_unpaidInvoiceCount > 0) {
                                  summaryParts.add(
                                      '$_unpaidInvoiceCount hóa đơn chưa thanh toán');
                                }
                                if (_unreadNotificationCount > 0) {
                                  summaryParts.add(
                                      '$_unreadNotificationCount thông báo mới');
                                }
                                if (_unpaidBookingCount > 0) {
                                  summaryParts.add(
                                      '$_unpaidBookingCount dịch vụ chờ xử lý');
                                }
                                final summaryText = summaryParts.isEmpty
                                    ? 'Không có cảnh báo mới'
                                    : summaryParts.join(' • ');
                                return Text(
                                  summaryText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
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
                          value: _unpaidInvoiceCount.toString(),
                          onTap: _openUnpaidInvoicesScreen,
                        ),
                        const SizedBox(width: 8),
                        _buildStatusChip(
                          context,
                          icon: Icons.notifications_none,
                          label: 'Thông báo',
                          value: _unreadNotificationCount.toString(),
                          onTap: _openNotificationsScreen,
                        ),
                        const SizedBox(width: 8),
                        _buildStatusChip(
                          context,
                          icon: Icons.pending_actions_outlined,
                          label: 'Dịch vụ',
                          value: _unpaidBookingCount.toString(),
                          onTap: _openUnpaidBookingsScreen,
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
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final chip = AnimatedContainer(
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

    if (onTap == null) {
      return chip;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: chip,
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

  Widget _buildUnitSelectorWidget(Size size, {required bool isDarkMode}) {
    if (_units.isEmpty) {
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
    final selectedUnit = _units.firstWhere(
      (unit) => unit.id == currentUnitId,
      orElse: () => _units.first,
    );
    final theme = Theme.of(context);
    final backgroundGradient = isDarkMode
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();
    final outlineColor = isDarkMode
        ? Colors.white.withOpacity(0.18)
        : Colors.white.withOpacity(0.32);
    final textColor = isDarkMode
        ? Colors.white
        : theme.colorScheme.onSurface.withOpacity(0.86);
    final secondaryTextColor = isDarkMode
        ? Colors.white70
        : theme.colorScheme.onSurface.withOpacity(0.6);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: size.width * 0.035,
            vertical: size.height * 0.008,
          ),
          decoration: BoxDecoration(
            gradient: backgroundGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: outlineColor, width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22102136),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient(),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppColors.subtleShadow,
                ),
                child: const Icon(
                  CupertinoIcons.house_alt_fill,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Căn hộ mặc định',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: secondaryTextColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedUnit.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bạn có thể đổi căn hộ trong phần Cài đặt.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
          ElectricityChart(
            monthlyData: _electricityMonthlyData,
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
            icon: Icons.person_add_outlined,
            accentColor: AppColors.primaryAqua,
            title: 'Đăng ký thành viên mới',
            subtitle: const [
              'Gửi yêu cầu thêm thành viên vào hộ gia đình của bạn.',
            ],
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HouseholdMemberRequestScreen(
                    units: ownerUnits,
                    initialUnitId: defaultUnitId,
                  ),
                ),
              );
            },
            actionLabel: 'Gửi yêu cầu',
          ),
          const Divider(),
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
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FeedbackScreen(),
            ),
          );
        },
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
    final borderRadius = BorderRadius.circular(28);
    final gradient = theme.brightness == Brightness.dark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: borderRadius,
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.08),
            ),
            boxShadow: AppColors.subtleShadow,
          ),
          padding: padding,
          child: child,
        ),
      ),
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
              Icon(
                CupertinoIcons.chevron_forward,
                size: 18,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
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
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.56),
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

class _WeatherSnapshot {
  const _WeatherSnapshot({
    required this.city,
    required this.temperatureCelsius,
    required this.weatherLabel,
    required this.weatherIcon,
    required this.fetchedAt,
    this.windSpeed,
    this.humidity,
  });

  final String city;
  final double temperatureCelsius;
  final String weatherLabel;
  final IconData weatherIcon;
  final double? windSpeed;
  final double? humidity;
  final DateTime fetchedAt;
}

class _WeatherDescriptor {
  const _WeatherDescriptor(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _WeatherRateLimitException implements Exception {
  const _WeatherRateLimitException({required this.source});

  final String source;
}
