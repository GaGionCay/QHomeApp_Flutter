import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/asset_maintenance_api_client.dart';
import '../core/app_router.dart';
import '../theme/app_colors.dart';
import 'service_booking_service.dart';
import 'unpaid_service_bookings_screen.dart';

import '../core/safe_state_mixin.dart';
class ServiceBookingScreen extends StatefulWidget {
  const ServiceBookingScreen({
    super.key,
    required this.serviceId,
    required this.serviceName,
    required this.categoryCode,
    this.categoryName,
  });

  final String serviceId;
  final String serviceName;
  final String categoryCode;
  final String? categoryName;

  @override
  State<ServiceBookingScreen> createState() => _ServiceBookingScreenState();
}

class _ServiceBookingScreenState extends State<ServiceBookingScreen> with SafeStateMixin<ServiceBookingScreen> {
  late final ServiceBookingService _bookingService;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri?>? _paymentSub;
  static const String _pendingPaymentKey = 'pending_service_booking_payment';
  bool _isNavigatingToMain = false;

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  Map<String, dynamic>? _service;
  List<Map<String, dynamic>> _options = const [];
  List<Map<String, dynamic>> _combos = const [];
  List<Map<String, dynamic>> _tickets = const [];
  List<Map<String, dynamic>> _availabilities = const [];
  // Bỏ các biến booked slots vì không cần chọn thời gian nữa

  final Map<String, int> _selectedOptions = {};
  String? _selectedComboId;
  final Map<String, int> _selectedTickets = {}; // Map<ticketId, quantity> - Cho phép chọn nhiều loại vé

  final TextEditingController _purposeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bookingService = ServiceBookingService(AssetMaintenanceApiClient());
    _loadService();
    _listenForPaymentResult();
    _checkPendingPayment();
  }

  @override
  void dispose() {
    _paymentSub?.cancel();
    _purposeController.dispose();
    super.dispose();
  }

  Future<void> _loadService() async {
    safeSetState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _bookingService.getServiceDetail(widget.serviceId);
      safeSetState(() {
        _service = detail;
        _options = _parseList(detail['options']);
        _combos = _parseList(detail['combos']);
        _tickets = _parseList(detail['tickets']);
        _availabilities = _parseList(detail['availabilities']);
        // Bỏ applyDefaultSelections vì không cần chọn thời gian nữa
        _loading = false;
        // Bỏ reload booked slots vì không cần chọn thời gian nữa
      });
      // Bỏ reload booked slots vì không cần chọn thời gian nữa
    } catch (e) {
      safeSetState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _navigateToServicesHome({String? snackMessage}) {
    if (!mounted || _isNavigatingToMain) return;
    _isNavigatingToMain = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(
        AppRoute.main.path,
        extra: MainShellArgs(
          initialIndex: 1,
          snackMessage: snackMessage,
        ),
      );
    });
  }

  void _listenForPaymentResult() {
    _paymentSub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;

      if (uri.scheme == 'qhomeapp' &&
          uri.host == 'vnpay-service-booking-result') {
        final responseCode = uri.queryParameters['responseCode'];
        final success = uri.queryParameters['success'] == 'true';

        await _clearPendingPayment();
        if (!mounted) return;

        if (success && responseCode == '00') {
          _navigateToServicesHome(
            snackMessage: '✅ Thanh toán dịch vụ thành công!',
          );
        } else {
          _showMessage('Thanh toán thất bại. Vui lòng thử lại.', isError: true);
        }
      }
    }, onError: (err) {
      debugPrint('❌ Lỗi khi nhận liên kết thanh toán: $err');
    });
  }

  Future<void> _checkPendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getString(_pendingPaymentKey);
      if (pending != null) {
        debugPrint('ℹ️ Đơn đặt dịch vụ $pending đang chờ thanh toán.');
      }
    } catch (e) {
      debugPrint('⚠️ Không thể kiểm tra trạng thái thanh toán: $e');
    }
  }

  Future<void> _clearPendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingPaymentKey);
    } catch (e) {
      debugPrint('⚠️ Không thể xóa trạng thái thanh toán: $e');
    }
  }

  Future<void> _launchVnpayPayment(String bookingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingPaymentKey, bookingId);

      final response = await _bookingService.createVnpayPaymentUrl(bookingId);
      final paymentUrl = response['paymentUrl']?.toString();

      if (paymentUrl == null || paymentUrl.isEmpty) {
        throw Exception('Không nhận được URL thanh toán từ hệ thống.');
      }

      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Đang chuyển tới cổng VNPAY, vui lòng hoàn tất thanh toán.'),
          ),
        );
      } else {
        throw Exception('Không thể mở cổng thanh toán.');
      }
    } catch (e) {
      debugPrint('❌ Lỗi khởi tạo thanh toán dịch vụ: $e');
      await _clearPendingPayment();
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  List<Map<String, dynamic>> _parseList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const [];
  }

  // Bỏ các method liên quan đến date/time selection vì không cần nữa

  String get _bookingType {
    // Tự động xác định booking type dựa trên tickets/combos/options
    // Vì backend đã bỏ cột booking_type, ta xác định dựa trên dữ liệu có sẵn
    final tickets = _parseList(_service?['tickets']);
    final combos = _parseList(_service?['combos']);
    final options = _parseList(_service?['options']);
    
    // Kiểm tra cả camelCase và snake_case
    bool isActive(dynamic item) {
      final active = item['isActive'] ?? item['is_active'];
      return active == true || active == null; // null coi như true (default)
    }
    
    if (tickets.isNotEmpty && tickets.any(isActive)) {
      return 'TICKET_BASED';
    }
    if (combos.isNotEmpty && combos.any(isActive)) {
      return 'COMBO_BASED';
    }
    if (options.isNotEmpty && options.any(isActive)) {
      return 'OPTION_BASED';
    }
    return 'STANDARD';
  }

  int get _maxCapacity {
    final value = _service?['maxCapacity'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 10;
  }

  // Bỏ các method tính duration và validate time range vì không cần nữa

  num _calculateBaseAmount() {
    final detail = _service;
    if (detail == null) return 0;
    final bookingType = _bookingType;

    if (bookingType == 'COMBO_BASED') {
      final combo = _selectedCombo;
      if (combo == null) return 0;
      final price = (combo['price'] as num?) ?? 0;
      // Tính tổng số người từ các vé đã chọn hoặc mặc định 1
      final totalPeople = _selectedTickets.values.fold<int>(0, (sum, qty) => sum + qty);
      return price * (totalPeople > 0 ? totalPeople : 1);
    }

    if (bookingType == 'TICKET_BASED') {
      // Tính tổng giá của tất cả các vé đã chọn
      num total = 0;
      _selectedTickets.forEach((ticketId, quantity) {
        final ticket = _tickets.firstWhere(
          (element) => element['id'].toString() == ticketId,
          orElse: () => <String, dynamic>{},
        );
        if (ticket.isNotEmpty) {
          final price = (ticket['price'] as num?) ?? 0;
          total += price * quantity;
        }
      });
      return total;
    }

    // Fallback cho STANDARD (không dùng nữa nhưng giữ lại để tránh lỗi)
    return 0;
  }

  num _calculateOptionsAmount() {
    num total = 0;
    _selectedOptions.forEach((optionId, quantity) {
      final option = _options.firstWhere(
        (element) => element['id'].toString() == optionId,
      );
      final price = (option['price'] as num?) ?? 0;
      total += price * quantity;
    });
    return total;
  }

  num _calculateTotalAmount() {
    return _calculateBaseAmount() + _calculateOptionsAmount();
  }

  Map<String, dynamic>? get _selectedCombo {
    if (_selectedComboId == null) return null;
    return _combos.firstWhere(
      (element) => element['id'].toString() == _selectedComboId,
      orElse: () => <String, dynamic>{},
    );
  }


  List<Map<String, dynamic>> _buildBookingItems() {
    final items = <Map<String, dynamic>>[];
    if (_bookingType == 'COMBO_BASED') {
      final combo = _selectedCombo;
      if (combo != null) {
        items.add(
          _bookingService.buildBookingItem(
            itemType: 'COMBO',
            itemId: combo['id'].toString(),
            itemCode: combo['code']?.toString() ?? '',
            itemName: combo['name']?.toString() ?? 'Combo',
            quantity: _selectedTickets.values.fold<int>(0, (sum, qty) => sum + qty),
            unitPrice: (combo['price'] as num?) ?? 0,
          ),
        );
      }
    }

    if (_bookingType == 'TICKET_BASED') {
      // Thêm tất cả các vé đã chọn vào items
      _selectedTickets.forEach((ticketId, quantity) {
        final ticket = _tickets.firstWhere(
          (element) => element['id'].toString() == ticketId,
          orElse: () => <String, dynamic>{},
        );
        if (ticket.isNotEmpty && quantity > 0) {
          items.add(
            _bookingService.buildBookingItem(
              itemType: 'TICKET',
              itemId: ticket['id'].toString(),
              itemCode: ticket['code']?.toString() ?? '',
              itemName: ticket['name']?.toString() ?? 'Vé',
              quantity: quantity,
              unitPrice: (ticket['price'] as num?) ?? 0,
            ),
          );
        }
      });
    }

    _selectedOptions.forEach((optionId, quantity) {
      final option = _options.firstWhere(
        (element) => element['id'].toString() == optionId,
      );
      items.add(
        _bookingService.buildBookingItem(
          itemType: 'OPTION',
          itemId: option['id'].toString(),
          itemCode: option['code']?.toString() ?? '',
          itemName: option['name']?.toString() ?? 'Tùy chọn',
          quantity: quantity,
          unitPrice: (option['price'] as num?) ?? 0,
        ),
      );
    });

    return items;
  }

  Future<void> _submit() async {
    if (_service == null) return;

    // Validate tickets selection
    if (_bookingType == 'COMBO_BASED' && _selectedComboId == null) {
      _showMessage('Vui lòng chọn gói combo.');
      return;
    }
    if (_bookingType == 'TICKET_BASED' && _selectedTickets.isEmpty) {
      _showMessage('Vui lòng chọn ít nhất một loại vé.');
      return;
    }

    // Validate total quantity > 0
    final totalQuantity = _selectedTickets.values.fold<int>(0, (sum, qty) => sum + qty);
    if (_bookingType == 'TICKET_BASED' && totalQuantity <= 0) {
      _showMessage('Vui lòng chọn số lượng vé.');
      return;
    }

    final totalAmount = _calculateTotalAmount();
    if (totalAmount <= 0) {
      _showMessage('Chi phí dịch vụ không hợp lệ.');
      return;
    }

    safeSetState(() {
      _submitting = true;
    });

    try {
      // Tính tổng số người từ các vé đã chọn
      final totalPeople = _selectedTickets.values.fold<int>(0, (sum, qty) => sum + qty);
      
      // Sử dụng ngày hiện tại và thời gian mặc định (không quan trọng vì chỉ tính theo vé)
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final booking = await _bookingService.createBooking(
        serviceId: widget.serviceId,
        bookingDate: today, // Ngày hiện tại
        startTime: '08:00', // Thời gian mặc định
        endTime: '10:00', // Thời gian mặc định
        durationHours: 2.0, // Duration mặc định
        numberOfPeople: totalPeople > 0 ? totalPeople : 1,
        totalAmount: totalAmount,
        purpose: _purposeController.text.trim().isEmpty
            ? null
            : _purposeController.text.trim(),
        items: _buildBookingItems(),
      );

      final bookingId = booking['id']?.toString();
      if (bookingId == null || bookingId.isEmpty) {
        throw Exception('Không thể xác định mã đơn đặt dịch vụ.');
      }

      if (!mounted) return;
      await _launchVnpayPayment(bookingId);
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      if (message.contains('chưa được thanh toán')) {
        _showOutstandingDialog(message);
      } else {
        _showMessage(message, isError: true);
      }
    } finally {
      if (mounted) {
        safeSetState(() {
          _submitting = false;
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.orange,
      ),
    );
  }

  void _showOutstandingDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bạn có dịch vụ chưa thanh toán'),
        content: Text(
          '$message\n\nVui lòng thanh toán hoặc hủy dịch vụ đang chờ trong mục "Dịch vụ chưa thanh toán".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const UnpaidServiceBookingsScreen(),
                ),
              );
            },
            child: const Text('Xem ngay'),
          ),
        ],
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  String _formatCurrency(num value) {
    final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: '');
    return formatter.format(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final backgroundGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF04101F),
              Color(0xFF0A1D34),
              Color(0xFF071225),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEFF6FF),
              Color(0xFFF8FBFF),
              Colors.white,
            ],
          );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: colorScheme.onSurface,
              elevation: 0,
              scrolledUnderElevation: 0,
              pinned: true,
              stretch: true,
              leadingWidth: 66,
              expandedHeight: 120,
              systemOverlayStyle: theme.appBarTheme.systemOverlayStyle,
              title: Text(
                'Đặt dịch vụ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              centerTitle: true,
              leading: Padding(
                padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
                child: _buildFrostedIconButton(
                  icon: CupertinoIcons.chevron_left,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: Container(
                  decoration: BoxDecoration(gradient: backgroundGradient),
                  padding: const EdgeInsets.fromLTRB(24, 80, 24, 20),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.serviceName,
                          style: theme.textTheme.titleLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ) ??
                              TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(48.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _error ?? 'Đã xảy ra lỗi',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _loadService,
                                  child: const Text('Thử lại'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildServiceInfoCard(),
                              const SizedBox(height: 16),
                              if (_bookingType == 'COMBO_BASED') _buildCombosSection(),
                              if (_bookingType == 'TICKET_BASED')
                                _buildTicketsSection(),
                              // Hiển thị options section:
                              // - Nếu OPTION_BASED hoặc STANDARD: hiển thị như booking type chính
                              // - Nếu TICKET_BASED hoặc COMBO_BASED: hiển thị như additional options
                              if (_options.isNotEmpty) ...[
                                if (_bookingType == 'OPTION_BASED' ||
                                    _bookingType == 'STANDARD')
                                  _buildOptionsSection()
                                else ...[
                                  // Additional options cho TICKET_BASED và COMBO_BASED
                                  _buildOptionsSection(),
                                ],
                              ],
                              const SizedBox(height: 16),
                              _buildPurposeField(),
                              const SizedBox(height: 16),
                              _buildPriceSummary(),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _submitting ? null : _submit,
                                  icon: _submitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Icon(
                                          CupertinoIcons.calendar_badge_plus,
                                          size: 20,
                                        ),
                                  label: Text(
                                    _submitting
                                        ? 'Đang xử lý...'
                                        : 'Gửi yêu cầu đặt dịch vụ',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrostedIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.75),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                icon,
                size: 20,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServiceInfoCard() {
    final detail = _service;
    if (detail == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.serviceName,
            style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ) ??
                TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
          ),
          if (detail['description'] != null &&
              detail['description'].toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              detail['description'].toString(),
              style: theme.textTheme.bodyLarge?.copyWith(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.82)
                        : AppColors.textPrimary,
                    height: 1.6,
                  ) ??
                  TextStyle(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.82)
                        : AppColors.textPrimary,
                    height: 1.6,
                  ),
            ),
          ],
          if (detail['location'] != null &&
              detail['location'].toString().isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildDetailRow(
              icon: CupertinoIcons.location_fill,
              label: 'Địa điểm',
              value: detail['location'].toString(),
            ),
          ],
          const SizedBox(height: 18),
          _buildDetailRow(
            icon: CupertinoIcons.tag_fill,
            label: 'Loại đặt',
            value: _bookingType == 'COMBO_BASED'
                ? 'Đặt theo combo'
                : _bookingType == 'TICKET_BASED'
                    ? 'Đặt theo vé'
                    : 'Giá theo giờ${_bookingType == 'OPTION_BASED' || _bookingType == 'STANDARD' ? ' - ${_formatCurrency((detail['pricePerHour'] as num?) ?? 0)} đ/giờ' : ''}',
          ),
        ],
      ),
    );
  }

  // Đã xóa _buildDateSelector và _nextAllowedDate vì không cần chọn thời gian nữa

  // Đã xóa _buildTimeSelector vì không cần chọn thời gian nữa

  // Đã xóa _buildBookedSlotsSection vì không cần chọn thời gian nữa

  Widget _glassPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(24),
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gradient = isDark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();
    final borderColor = (isDark ? AppColors.navyOutline : AppColors.neutralOutline)
        .withValues(alpha: 0.45);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isError = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = isError ? colorScheme.error : colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: isDark ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: iconColor.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: iconColor,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                      color: isDark
                          ? Colors.white70
                          : AppColors.textSecondary,
                      fontSize: 12,
                    ) ??
                    TextStyle(
                      color: isDark ? Colors.white70 : AppColors.textSecondary,
                      fontSize: 12,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                      fontSize: 15,
                    ) ??
                    TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                      fontSize: 15,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Đã xóa tất cả các method liên quan đến booked slots vì không cần chọn thời gian nữa

  Widget _buildCombosSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (_combos.isEmpty) {
      return _glassPanel(
        child: _buildDetailRow(
          icon: CupertinoIcons.square_grid_2x2_fill,
          label: 'Gói combo',
          value: 'Hiện chưa có gói combo khả dụng.',
        ),
      );
    }
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chọn gói combo',
            style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ) ??
                TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                  fontSize: 18,
                ),
          ),
          const SizedBox(height: 18),
          ..._combos.map(
            (combo) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RadioListTile<String>(
                value: combo['id'].toString(),
                groupValue: _selectedComboId, // ignore: deprecated_member_use
                onChanged: (value) { // ignore: deprecated_member_use
                  safeSetState(() {
                    _selectedComboId = value;
                  });
                },
                title: Text(
                  combo['name']?.toString() ?? 'Combo',
                  style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ) ??
                      TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (combo['description'] != null &&
                        combo['description'].toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        combo['description'].toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? Colors.white70
                                  : AppColors.textSecondary,
                            ) ??
                            TextStyle(
                              color: isDark
                                  ? Colors.white70
                                  : AppColors.textSecondary,
                              fontSize: 12,
                            ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      '${_formatCurrency((combo['price'] as num?) ?? 0)} đ / người',
                      style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ) ??
                          TextStyle(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                            fontSize: 14,
                          ),
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

  Widget _buildTicketsSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (_tickets.isEmpty) {
      return _glassPanel(
        child: _buildDetailRow(
          icon: CupertinoIcons.ticket_fill,
          label: 'Loại vé',
          value: 'Hiện chưa có loại vé khả dụng.',
        ),
      );
    }
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chọn loại vé',
            style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ) ??
                TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                  fontSize: 18,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Bạn có thể chọn nhiều loại vé (ví dụ: vé người lớn và vé trẻ em)',
            style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ) ??
                TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
          ),
          const SizedBox(height: 18),
          ..._tickets.map(
            (ticket) {
              final ticketId = ticket['id'].toString();
              final quantity = _selectedTickets[ticketId] ?? 0;
              final price = (ticket['price'] as num?) ?? 0;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ticket['name']?.toString() ?? 'Vé',
                            style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                ) ??
                                TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_formatCurrency(price)} đ / người',
                            style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ) ??
                                TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                  fontSize: 14,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: quantity > 0
                              ? () {
                                  safeSetState(() {
                                    if (quantity > 1) {
                                      _selectedTickets[ticketId] = quantity - 1;
                                    } else {
                                      _selectedTickets.remove(ticketId);
                                    }
                                  });
                                }
                              : null,
                          style: IconButton.styleFrom(
                            foregroundColor: quantity > 0
                                ? colorScheme.primary
                                : (isDark ? Colors.white38 : Colors.grey),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '$quantity',
                            style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ) ??
                                TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            safeSetState(() {
                              _selectedTickets[ticketId] = (quantity) + 1;
                            });
                          },
                          style: IconButton.styleFrom(
                            foregroundColor: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsSection() {
    if (_options.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tùy chọn bổ sung',
            style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ) ??
                TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                  fontSize: 18,
                ),
          ),
          const SizedBox(height: 18),
          ..._options.map(
            (option) {
              final optionId = option['id'].toString();
              final isSelected = _selectedOptions.containsKey(optionId);
              final quantity = _selectedOptions[optionId] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.3 : 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary.withValues(alpha: 0.3)
                          : colorScheme.outline.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: (checked) {
                          safeSetState(() {
                            if (checked == true) {
                              _selectedOptions[optionId] = max(1, quantity);
                            } else {
                              _selectedOptions.remove(optionId);
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Option name
                            Text(
                              option['name']?.toString() ?? 'Tùy chọn',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : AppColors.textPrimary,
                                  ) ??
                                  TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : AppColors.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            // Description (nếu có)
                            if (option['description'] != null &&
                                option['description'].toString().isNotEmpty) ...[
                              Text(
                                option['description'].toString(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                      color: isDark
                                          ? Colors.white70
                                          : AppColors.textSecondary,
                                      height: 1.4,
                                    ) ??
                                    TextStyle(
                                      color: isDark
                                          ? Colors.white70
                                          : AppColors.textSecondary,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                            ],
                            // Unit và Price
                            Wrap(
                              spacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                // Unit (nếu có)
                                if (option['unit'] != null &&
                                    option['unit'].toString().isNotEmpty)
                                  Text(
                                    'Đơn vị: ${option['unit']}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                          color: isDark
                                              ? Colors.white70
                                              : AppColors.textSecondary,
                                        ) ??
                                        TextStyle(
                                          color: isDark
                                              ? Colors.white70
                                              : AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                  ),
                                // Price
                                Text(
                                  '${_formatCurrency((option['price'] as num?) ?? 0)} đ',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.primary,
                                      ) ??
                                      TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.primary,
                                        fontSize: 14,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Quantity controls (nếu đã chọn)
                      if (isSelected)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: quantity > 1
                                  ? () {
                                      safeSetState(() {
                                        _selectedOptions[optionId] = quantity - 1;
                                      });
                                    }
                                  : null,
                            ),
                            Text(
                              '$quantity',
                              style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : AppColors.textPrimary,
                                  ) ??
                                  TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : AppColors.textPrimary,
                                  ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () {
                                safeSetState(() {
                                  _selectedOptions[optionId] = quantity + 1;
                                });
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Đã xóa _buildPeopleSelector vì số người được tính từ vé đã chọn

  Widget _buildPurposeField() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ghi chú / mục đích (tuỳ chọn)',
            style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ) ??
                TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _purposeController,
            maxLines: 3,
            style: theme.textTheme.bodyLarge?.copyWith(
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ) ??
                TextStyle(
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
            decoration: InputDecoration(
              hintText: 'Ví dụ: tổ chức sinh nhật gia đình...',
              hintStyle: TextStyle(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : AppColors.textSecondary,
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.3 : 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: colorScheme.primary.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSummary() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final total = _calculateTotalAmount();

    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tổng chi phí dự kiến',
            style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ) ??
                TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                  fontSize: 18,
                ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Chi phí cơ bản',
                style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.75)
                          : AppColors.textSecondary,
                    ) ??
                    TextStyle(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.75)
                          : AppColors.textSecondary,
                    ),
              ),
              Text(
                '${_formatCurrency(_calculateBaseAmount())} đ',
                style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ) ??
                    TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
              ),
            ],
          ),
          if (_selectedOptions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tùy chọn bổ sung',
                  style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.75)
                            : AppColors.textSecondary,
                      ) ??
                      TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.75)
                            : AppColors.textSecondary,
                      ),
                ),
                Text(
                  '${_formatCurrency(_calculateOptionsAmount())} đ',
                  style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ) ??
                      TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Divider(
            height: 1,
            color: colorScheme.outline.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tổng thanh toán',
                style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ) ??
                    TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
              ),
              Text(
                '${_formatCurrency(total)} đ',
                style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ) ??
                    TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Đã xóa _BookedSlot class vì không cần chọn thời gian nữa


