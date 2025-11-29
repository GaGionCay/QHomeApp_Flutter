import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/asset_maintenance_api_client.dart';
import '../theme/app_colors.dart';
import 'service_booking_service.dart';
import 'unpaid_service_bookings_screen.dart';

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

class _ServiceBookingScreenState extends State<ServiceBookingScreen> {
  late final ServiceBookingService _bookingService;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri?>? _paymentSub;
  static const String _pendingPaymentKey = 'pending_service_booking_payment';

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  Map<String, dynamic>? _service;
  List<Map<String, dynamic>> _options = const [];
  List<Map<String, dynamic>> _combos = const [];
  List<Map<String, dynamic>> _tickets = const [];
  List<Map<String, dynamic>> _availabilities = const [];
  Map<String, List<_BookedSlot>> _bookedSlotsByDate = {};
  bool _bookedSlotsLoading = true;
  String? _bookedSlotsError;
  DateTime? _bookedSlotsStart;
  DateTime? _bookedSlotsEnd;

  final Map<String, int> _selectedOptions = {};
  String? _selectedComboId;
  String? _selectedTicketId;

  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  int _numberOfPeople = 1;
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _bookingService.getServiceDetail(widget.serviceId);
      setState(() {
        _service = detail;
        _options = _parseList(detail['options']);
        _combos = _parseList(detail['combos']);
        _tickets = _parseList(detail['tickets']);
        _availabilities = _parseList(detail['availabilities']);
        _applyDefaultSelections();
        _loading = false;
        _bookedSlotsByDate = {};
        _bookedSlotsError = null;
        _bookedSlotsLoading = true;
        _bookedSlotsStart = null;
        _bookedSlotsEnd = null;
      });
      await _reloadBookedSlots(anchor: _selectedDate ?? DateTime.now());
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _bookedSlotsLoading = false;
        _bookedSlotsError = e.toString();
      });
    }
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Thanh toán dịch vụ thành công!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
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

  void _applyDefaultSelections() {
    final detail = _service;
    if (detail == null) return;

    final today = DateTime.now();
    final lastDate = today.add(Duration(days: _advanceBookingDays(detail)));

    DateTime? candidate = today;
    for (int i = 0; i <= lastDate.difference(today).inDays; i++) {
      final date = today.add(Duration(days: i));
      if (_isDateAllowed(detail, date)) {
        candidate = date;
        break;
      }
    }

    _selectedDate = candidate ?? today;

    final availability = _availabilityForDate(detail, _selectedDate!);
    if (availability != null) {
      _startTime = _parseTimeOfDay(availability['startTime']);
      final availabilityEnd = _parseTimeOfDay(availability['endTime']);

      final minDuration = detail['minDurationHours'] is num
          ? (detail['minDurationHours'] as num).toDouble()
          : 1.0;
      _endTime = _addDuration(_startTime!, minDuration);
      if (_endTime != null &&
          availabilityEnd != null &&
          !_isTimeRangeValid(_startTime!, _endTime!, availabilityEnd)) {
        _endTime = availabilityEnd;
      }
    }
  }

  bool _isDateAllowed(Map<String, dynamic> detail, DateTime date) {
    final availability = _availabilityForDate(detail, date);
    return availability != null;
  }

  Map<String, dynamic>? _availabilityForDate(
      Map<String, dynamic> detail, DateTime date) {
    if (!detail.containsKey('availabilities')) return null;
    final dayOfWeek = date.weekday; // Monday = 1
    final match = _availabilities.firstWhere(
      (availability) => availability['dayOfWeek'] == dayOfWeek,
      orElse: () => <String, dynamic>{},
    );
    return match.isEmpty ? null : match;
  }

  int _advanceBookingDays(Map<String, dynamic> detail) {
    // Backend no longer has advanceBookingDays field, use default 30 days
    return 30;
  }

  TimeOfDay? _parseTimeOfDay(dynamic value) {
    if (value == null) return null;
    final str = value.toString();
    final parts = str.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  TimeOfDay? _addDuration(TimeOfDay start, double hours) {
    final totalMinutes = (hours * 60).round();
    final dateTime = DateTime(2020, 1, 1, start.hour, start.minute)
        .add(Duration(minutes: totalMinutes));
    return TimeOfDay(hour: dateTime.hour, minute: dateTime.minute);
  }

  bool _isTimeRangeValid(TimeOfDay start, TimeOfDay end, TimeOfDay maxEnd) {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    final maxMinutes = maxEnd.hour * 60 + maxEnd.minute;
    return endMinutes <= maxMinutes && endMinutes > startMinutes;
  }

  String get _bookingType =>
      (_service?['bookingType']?.toString().toUpperCase()) ?? 'STANDARD';

  int get _maxCapacity {
    final value = _service?['maxCapacity'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 10;
  }

  double? _calculateDurationHours() {
    if (_startTime == null || _endTime == null) return null;
    final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
    final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
    final diff = endMinutes - startMinutes;
    if (diff <= 0) return null;
    return diff / 60.0;
  }

  void _validateTimeRange() {
    if (_service == null || _startTime == null || _endTime == null) return;

    final duration = _calculateDurationHours();
    if (duration == null || duration <= 0) {
      _showMessage('Khung giờ không hợp lệ.', isError: true);
      return;
    }

    final minDuration = _service!['minDurationHours'] is num
        ? (_service!['minDurationHours'] as num).toDouble()
        : 1.0;

    if (duration < minDuration) {
      _showMessage(
          'Thời lượng tối thiểu là ${minDuration.toStringAsFixed(1)} giờ. Vui lòng chọn lại khung giờ.',
          isError: true);
      setState(() {
        // Auto-adjust end time to meet minimum duration
        _endTime = _addDuration(_startTime!, minDuration);
      });
    }
  }

  num _calculateBaseAmount() {
    final detail = _service;
    if (detail == null) return 0;
    final bookingType = _bookingType;

    if (bookingType == 'COMBO_BASED') {
      final combo = _selectedCombo;
      if (combo == null) return 0;
      final price = (combo['price'] as num?) ?? 0;
      return price * _numberOfPeople;
    }

    if (bookingType == 'TICKET_BASED') {
      final ticket = _selectedTicket;
      if (ticket == null) return 0;
      final price = (ticket['price'] as num?) ?? 0;
      return price * _numberOfPeople;
    }

    final pricePerHour = (detail['pricePerHour'] as num?) ?? 0;
    final duration = _calculateDurationHours() ?? 0;
    return pricePerHour * duration;
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

  Map<String, dynamic>? get _selectedTicket {
    if (_selectedTicketId == null) return null;
    return _tickets.firstWhere(
      (element) => element['id'].toString() == _selectedTicketId,
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
            quantity: _numberOfPeople,
            unitPrice: (combo['price'] as num?) ?? 0,
          ),
        );
      }
    }

    if (_bookingType == 'TICKET_BASED') {
      final ticket = _selectedTicket;
      if (ticket != null) {
        items.add(
          _bookingService.buildBookingItem(
            itemType: 'TICKET',
            itemId: ticket['id'].toString(),
            itemCode: ticket['code']?.toString() ?? '',
            itemName: ticket['name']?.toString() ?? 'Vé',
            quantity: _numberOfPeople,
            unitPrice: (ticket['price'] as num?) ?? 0,
          ),
        );
      }
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

    if (_selectedDate == null) {
      _showMessage('Vui lòng chọn ngày đặt dịch vụ.');
      return;
    }
    if (_startTime == null || _endTime == null) {
      _showMessage('Vui lòng chọn khung giờ sử dụng.');
      return;
    }
    // Validate time is not in the past
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = _selectedDate!.year == today.year &&
        _selectedDate!.month == today.month &&
        _selectedDate!.day == today.day;

    if (isToday) {
      final nowTime = TimeOfDay.fromDateTime(now);
      final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
      final nowMinutes = nowTime.hour * 60 + nowTime.minute;
      if (startMinutes <= nowMinutes) {
        _showMessage('Thời gian bắt đầu phải sau thời gian hiện tại.', isError: true);
        return;
      }
      final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
      if (endMinutes <= nowMinutes) {
        _showMessage('Thời gian kết thúc phải sau thời gian hiện tại.', isError: true);
        return;
      }
    }

    final duration = _calculateDurationHours();
    if (duration == null || duration <= 0) {
      _showMessage('Khung giờ không hợp lệ.');
      return;
    }

    // Validate min duration
    final minDuration = _service!['minDurationHours'] is num
        ? (_service!['minDurationHours'] as num).toDouble()
        : 1.0;
    if (duration < minDuration) {
      _showMessage(
          'Thời lượng tối thiểu là ${minDuration.toStringAsFixed(1)} giờ. Vui lòng chọn lại khung giờ.',
          isError: true);
      return;
    }
    if (_bookingType == 'COMBO_BASED' && _selectedComboId == null) {
      _showMessage('Vui lòng chọn gói combo.');
      return;
    }
    if (_bookingType == 'TICKET_BASED' && _selectedTicketId == null) {
      _showMessage('Vui lòng chọn loại vé.');
      return;
    }

    final totalAmount = _calculateTotalAmount();
    if (totalAmount <= 0) {
      _showMessage('Chi phí dịch vụ không hợp lệ.');
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final booking = await _bookingService.createBooking(
        serviceId: widget.serviceId,
        bookingDate: _selectedDate!,
        startTime: _formatTimeOfDay(_startTime!),
        endTime: _formatTimeOfDay(_endTime!),
        durationHours: duration,
        numberOfPeople: _numberOfPeople,
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
        setState(() {
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
                              _buildDateSelector(),
                              const SizedBox(height: 16),
                              _buildTimeSelector(),
                              const SizedBox(height: 16),
                              if (_bookingType == 'COMBO_BASED') _buildCombosSection(),
                              if (_bookingType == 'TICKET_BASED')
                                _buildTicketsSection(),
                              if (_bookingType == 'OPTION_BASED' ||
                                  _bookingType == 'STANDARD')
                                _buildOptionsSection(),
                              const SizedBox(height: 16),
                              _buildPeopleSelector(),
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

  Widget _buildDateSelector() {
    final detail = _service;
    if (detail == null) return const SizedBox.shrink();

    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final lastDate =
        normalizedToday.add(Duration(days: _advanceBookingDays(detail)));
    bool predicate(DateTime date) => _isDateAllowed(detail, date);

    final firstSelectable =
        _nextAllowedDate(detail, normalizedToday, lastDate, predicate);
    if (firstSelectable == null) {
      return _glassPanel(
        child: _buildDetailRow(
          icon: CupertinoIcons.calendar_today,
          label: 'Ngày sử dụng',
          value: 'Hiện không có ngày phù hợp để đặt lịch',
        ),
      );
    }

    DateTime initialCandidate =
        (_selectedDate ?? normalizedToday).isBefore(firstSelectable)
            ? firstSelectable
            : _selectedDate ?? normalizedToday;

    if (initialCandidate.isAfter(lastDate)) {
      initialCandidate = firstSelectable;
    }

    if (!predicate(initialCandidate)) {
      final fallback =
          _nextAllowedDate(detail, initialCandidate, lastDate, predicate);
      initialCandidate = fallback ?? firstSelectable;
    }

    return _glassPanel(
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: initialCandidate,
            firstDate: firstSelectable,
            lastDate: lastDate,
            selectableDayPredicate: predicate,
          );
          if (picked != null) {
            setState(() {
              _selectedDate = picked;
            });
            final availability = _availabilityForDate(detail, picked);
            if (availability != null) {
              setState(() {
                _startTime = _parseTimeOfDay(availability['startTime']);
                _endTime = _parseTimeOfDay(availability['endTime']);
              });
            }
            if (!_isWithinLoadedRange(picked)) {
              await _reloadBookedSlots(anchor: picked);
            }
          }
        },
        borderRadius: BorderRadius.circular(24),
        child: _buildDetailRow(
          icon: CupertinoIcons.calendar_today,
          label: 'Ngày sử dụng',
          value: _selectedDate != null
              ? DateFormat('EEEE, dd/MM/yyyy', 'vi_VN').format(_selectedDate!)
              : 'Chọn ngày',
        ),
      ),
    );
  }

  DateTime? _nextAllowedDate(
    Map<String, dynamic> detail,
    DateTime start,
    DateTime end,
    bool Function(DateTime) predicate,
  ) {
    DateTime current =
        DateTime(start.year, start.month, start.day); // normalize
    while (!current.isAfter(end)) {
      if (predicate(current)) {
        return current;
      }
      current = current.add(const Duration(days: 1));
    }
    return null;
  }

  Widget _buildTimeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _glassPanel(
                child: InkWell(
                  onTap: () async {
                    final now = TimeOfDay.now();
                    final today = DateTime.now();
                    final isToday = _selectedDate != null &&
                        _selectedDate!.year == today.year &&
                        _selectedDate!.month == today.month &&
                        _selectedDate!.day == today.day;

                    final time = await showTimePicker(
                      context: context,
                      initialTime: _startTime ?? now,
                    );
                    if (time != null) {
                      // Validate: if selected date is today, start time must be in the future
                      if (isToday) {
                        final timeMinutes = time.hour * 60 + time.minute;
                        final nowMinutes = now.hour * 60 + now.minute;
                        if (timeMinutes <= nowMinutes) {
                          _showMessage('Thời gian bắt đầu phải sau thời gian hiện tại.', isError: true);
                          return;
                        }
                      }

                      setState(() {
                        _startTime = time;
                        // Reset end time if it's before new start time
                        if (_endTime != null) {
                          final startMinutes = time.hour * 60 + time.minute;
                          final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
                          if (endMinutes <= startMinutes) {
                            _endTime = null;
                          }
                        }
                      });

                      // Validate min duration if end time is set
                      if (_endTime != null) {
                        _validateTimeRange();
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: _buildDetailRow(
                    icon: CupertinoIcons.clock,
                    label: 'Bắt đầu',
                    value: _startTime != null
                        ? _startTime!.format(context)
                        : 'Chọn giờ',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _glassPanel(
                child: InkWell(
                  onTap: () async {
                    if (_startTime == null) {
                      _showMessage('Vui lòng chọn thời gian bắt đầu trước.', isError: true);
                      return;
                    }

                    final now = TimeOfDay.now();
                    final today = DateTime.now();
                    final isToday = _selectedDate != null &&
                        _selectedDate!.year == today.year &&
                        _selectedDate!.month == today.month &&
                        _selectedDate!.day == today.day;

                    final initialEndTime = _endTime ??
                        (_addDuration(_startTime!, 1.0) ?? _startTime!);

                    final time = await showTimePicker(
                      context: context,
                      initialTime: initialEndTime,
                    );
                    if (time != null) {
                      // Validate: end time must be after start time
                      final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
                      final endMinutes = time.hour * 60 + time.minute;
                      if (endMinutes <= startMinutes) {
                        _showMessage('Thời gian kết thúc phải sau thời gian bắt đầu.', isError: true);
                        return;
                      }

                      // Validate: if selected date is today, end time must be in the future
                      if (isToday) {
                        final nowMinutes = now.hour * 60 + now.minute;
                        if (endMinutes <= nowMinutes) {
                          _showMessage('Thời gian kết thúc phải sau thời gian hiện tại.', isError: true);
                          return;
                        }
                      }

                      setState(() {
                        _endTime = time;
                      });

                      // Validate min duration
                      _validateTimeRange();
                    }
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: _buildDetailRow(
                    icon: CupertinoIcons.timer,
                    label: 'Kết thúc',
                    value: _endTime != null
                        ? _endTime!.format(context)
                        : 'Chọn giờ',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildBookedSlotsSection(),
      ],
    );
  }

  Widget _buildBookedSlotsSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Loading state
    if (_bookedSlotsLoading) {
      return _glassPanel(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Đang tải các khung giờ đã được đặt...',
                  style: theme.textTheme.bodyLarge?.copyWith(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.82)
                            : AppColors.textPrimary,
                      ) ??
                      TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.82)
                            : AppColors.textPrimary,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Error state
    if (_bookedSlotsError != null) {
      return _glassPanel(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                icon: Icons.error_outline,
                label: 'Lỗi',
                value: 'Không thể tải các khung giờ đã đặt',
                isError: true,
              ),
              const SizedBox(height: 12),
              Text(
                _bookedSlotsError!,
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
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _reloadBookedSlots(
                      anchor: _selectedDate ?? DateTime.now()),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Thử lại'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Empty state
    if (_bookedSlotsByDate.isEmpty) {
      return _glassPanel(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildDetailRow(
            icon: CupertinoIcons.calendar,
            label: 'Thông tin',
            value: 'Chưa có khung giờ nào được đặt trong khoảng thời gian này.',
          ),
        ),
      );
    }

    // Get all dates with booked slots
    final allDates = _bookedSlotsByDate.keys.toList()..sort();
    final selected = _selectedDate;
    final selectedKey = selected != null
        ? DateFormat('yyyy-MM-dd').format(selected)
        : null;
    final selectedSlots = selectedKey != null
        ? (_bookedSlotsByDate[selectedKey] ?? const [])
        : const <_BookedSlot>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        const SizedBox(height: 28),
        Text(
          'Khung giờ đã được đặt',
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

        // Dates summary
        if (allDates.isNotEmpty) ...[
          _glassPanel(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                    icon: CupertinoIcons.calendar_today,
                    label: 'Các ngày đã có đặt chỗ',
                    value: '${allDates.length} ngày có đặt chỗ',
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allDates.take(7).map((dateKey) {
                      final date = DateTime.parse(dateKey);
                      final slots = _bookedSlotsByDate[dateKey] ?? [];
                      final isSelected = selectedKey == dateKey;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDate = date;
                          });
                          if (!_isWithinLoadedRange(date)) {
                            _reloadBookedSlots(anchor: date);
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                                : colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.3 : 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? colorScheme.primary.withValues(alpha: 0.3)
                                  : colorScheme.outline.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                DateFormat('dd/MM', 'vi_VN').format(date),
                                style: theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? colorScheme.primary
                                          : (isDark ? Colors.white : AppColors.textPrimary),
                                    ) ??
                                    TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? colorScheme.primary
                                          : (isDark ? Colors.white : AppColors.textPrimary),
                                      fontSize: 12,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.clock,
                                    size: 12,
                                    color: isSelected
                                        ? colorScheme.primary
                                        : (isDark ? Colors.white70 : AppColors.textSecondary),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${slots.length}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                          color: isSelected
                                              ? colorScheme.primary
                                              : (isDark
                                                  ? Colors.white70
                                                  : AppColors.textSecondary),
                                        ) ??
                                        TextStyle(
                                          color: isSelected
                                              ? colorScheme.primary
                                              : (isDark
                                                  ? Colors.white70
                                                  : AppColors.textSecondary),
                                          fontSize: 11,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],

        // Selected date slots
        if (selected != null && selectedSlots.isNotEmpty) ...[
          _glassPanel(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                    icon: CupertinoIcons.lock_circle_fill,
                    label: 'Khung giờ đã được đặt',
                    value: DateFormat('EEEE, dd/MM/yyyy', 'vi_VN').format(selected),
                  ),
                  const SizedBox(height: 20),
                  ...selectedSlots.map(
                    (slot) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildBookedSlotItem(slot, theme, colorScheme, isDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else if (selected != null && selectedSlots.isEmpty) ...[
          _glassPanel(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildDetailRow(
                icon: CupertinoIcons.calendar,
                label: 'Thông tin',
                value: 'Chưa có khung giờ nào được đặt trong ngày ${DateFormat('dd/MM/yyyy', 'vi_VN').format(selected)}.',
              ),
            ),
          ),
        ] else ...[
          _glassPanel(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildDetailRow(
                icon: CupertinoIcons.calendar,
                label: 'Hướng dẫn',
                value: 'Chọn ngày để xem những khung giờ đã được đặt trước.',
              ),
            ),
          ),
        ],
      ],
    );
  }

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
      crossAxisAlignment: CrossAxisAlignment.start,
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
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                      color: isDark
                          ? Colors.white70
                          : AppColors.textSecondary,
                      fontSize: 13,
                    ) ??
                    TextStyle(
                      color: isDark ? Colors.white70 : AppColors.textSecondary,
                      fontSize: 13,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                      fontSize: 16,
                    ) ??
                    TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                      fontSize: 16,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBookedSlotItem(
    _BookedSlot slot,
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final statusColor = _getStatusColor(slot.status, colorScheme);
    final statusLabel = _translateBookingStatus(slot.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: isDark ? 0.4 : 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Icon(
              CupertinoIcons.clock_fill,
              size: 22,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Khung giờ',
                  style: theme.textTheme.labelMedium?.copyWith(
                        color: isDark
                            ? Colors.white70
                            : AppColors.textSecondary,
                        fontSize: 13,
                      ) ??
                      TextStyle(
                        color: isDark ? Colors.white70 : AppColors.textSecondary,
                        fontSize: 13,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatDisplayTime(slot.start)} - ${_formatDisplayTime(slot.end)}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                        fontSize: 16,
                      ) ??
                      TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: isDark ? 0.28 : 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: statusColor.withValues(alpha: isDark ? 0.6 : 0.4),
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ) ??
                        TextStyle(
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                          fontSize: 12,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status, ColorScheme colorScheme) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return Colors.orange;
      case 'APPROVED':
        return Colors.blue;
      case 'COMPLETED':
        return Colors.green;
      case 'PAID':
        return Colors.teal;
      default:
        return colorScheme.primary;
    }
  }

  Future<void> _reloadBookedSlots({DateTime? anchor}) async {
    final base = anchor ?? DateTime.now();
    final start = DateTime(base.year, base.month, base.day);
    final end = start.add(const Duration(days: 30));

    setState(() {
      _bookedSlotsLoading = true;
      _bookedSlotsError = null;
      _bookedSlotsStart = start;
      _bookedSlotsEnd = end;
    });

    try {
      final slots = await _bookingService.getBookedSlots(
        serviceId: widget.serviceId,
        from: start,
        to: end,
      );
      if (!mounted) return;
      setState(() {
        _bookedSlotsByDate = _groupSlots(slots);
        _bookedSlotsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookedSlotsByDate = {};
        _bookedSlotsLoading = false;
        _bookedSlotsError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Map<String, List<_BookedSlot>> _groupSlots(List<Map<String, dynamic>> raw) {
    final Map<String, List<_BookedSlot>> grouped = {};
    for (final slot in raw) {
      final dateStr = slot['slotDate']?.toString();
      final startStr = slot['startTime']?.toString();
      final endStr = slot['endTime']?.toString();
      if (dateStr == null || startStr == null || endStr == null) {
        continue;
      }
      DateTime date;
      try {
        date = DateTime.parse(dateStr);
      } catch (_) {
        continue;
      }
      final start = _parseSlotTime(startStr);
      final end = _parseSlotTime(endStr);
      if (start == null || end == null) {
        continue;
      }
      final key = DateFormat('yyyy-MM-dd').format(date);
      final status = slot['bookingStatus']?.toString() ?? '';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(
        _BookedSlot(date: date, start: start, end: end, status: status),
      );
    }

    for (final entry in grouped.values) {
      entry.sort((a, b) {
        final aMinutes = a.start.hour * 60 + a.start.minute;
        final bMinutes = b.start.hour * 60 + b.start.minute;
        return aMinutes.compareTo(bMinutes);
      });
    }

    return grouped;
  }

  TimeOfDay? _parseSlotTime(String raw) {
    final parts = raw.split(':');
    if (parts.length < 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  bool _isWithinLoadedRange(DateTime date) {
    if (_bookedSlotsStart == null || _bookedSlotsEnd == null) {
      return false;
    }
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(_bookedSlotsStart!) && !day.isAfter(_bookedSlotsEnd!);
  }

  String _formatDisplayTime(TimeOfDay time) {
    final dt = DateTime(0, 1, 1, time.hour, time.minute);
    return DateFormat('HH:mm').format(dt);
  }

  String _translateBookingStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PAID':
        return 'Đã thanh toán';
      case 'PENDING':
        return 'Chờ duyệt';
      case 'APPROVED':
        return 'Đã duyệt';
      case 'COMPLETED':
        return 'Hoàn tất';
      default:
        return status;
    }
  }

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
                  setState(() {
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
          const SizedBox(height: 18),
          ..._tickets.map(
            (ticket) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RadioListTile<String>(
                value: ticket['id'].toString(),
                groupValue: _selectedTicketId, // ignore: deprecated_member_use
                onChanged: (value) { // ignore: deprecated_member_use
                  setState(() {
                    _selectedTicketId = value;
                  });
                },
                title: Text(
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
                subtitle: Text(
                  '${_formatCurrency((ticket['price'] as num?) ?? 0)} đ / người',
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
              ),
            ),
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
                  child: CheckboxListTile(
                    value: isSelected,
                    title: Text(
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
                    subtitle: Text(
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
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selectedOptions[optionId] = max(1, quantity);
                        } else {
                          _selectedOptions.remove(optionId);
                        }
                      });
                    },
                    secondary: isSelected
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: quantity > 1
                                    ? () {
                                        setState(() {
                                          _selectedOptions[optionId] =
                                              quantity - 1;
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
                                  setState(() {
                                    _selectedOptions[optionId] = quantity + 1;
                                  });
                                },
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPeopleSelector() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return _glassPanel(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: _buildDetailRow(
              icon: CupertinoIcons.person_3_fill,
              label: 'Số người tham gia',
              value: '$_numberOfPeople người',
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _numberOfPeople > 1
                    ? () => setState(() => _numberOfPeople--)
                    : null,
                style: IconButton.styleFrom(
                  foregroundColor: _numberOfPeople > 1
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
                  '$_numberOfPeople',
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
                onPressed: _numberOfPeople < _maxCapacity
                    ? () => setState(() => _numberOfPeople++)
                    : null,
                style: IconButton.styleFrom(
                  foregroundColor: _numberOfPeople < _maxCapacity
                      ? colorScheme.primary
                      : (isDark ? Colors.white38 : Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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

class _BookedSlot {
  const _BookedSlot({
    required this.date,
    required this.start,
    required this.end,
    required this.status,
  });

  final DateTime date;
  final TimeOfDay start;
  final TimeOfDay end;
  final String status;
}
