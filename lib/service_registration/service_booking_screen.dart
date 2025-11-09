import 'dart:async';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/asset_maintenance_api_client.dart';
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

      if (uri.scheme == 'qhomeapp' && uri.host == 'vnpay-service-booking-result') {
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
            content: Text('Đang chuyển tới cổng VNPAY, vui lòng hoàn tất thanh toán.'),
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
    final value = detail['advanceBookingDays'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 14;
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
    final duration = _calculateDurationHours();
    if (duration == null || duration <= 0) {
      _showMessage('Khung giờ không hợp lệ.');
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
          ElevatedButton(
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: Text(widget.serviceName),
        backgroundColor: const Color(0xFF26A69A),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.red.shade400, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _error ?? 'Đã xảy ra lỗi',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadService,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
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
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF26A69A),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Gửi yêu cầu đặt dịch vụ',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildServiceInfoCard() {
    final detail = _service;
    if (detail == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.serviceName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail['description'] != null &&
                detail['description'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                detail['description'].toString(),
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
            if (detail['location'] != null &&
                detail['location'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.location_on,
                      size: 16, color: Colors.blueGrey.shade400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      detail['location'].toString(),
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.receipt_long, size: 16, color: Colors.teal),
                const SizedBox(width: 6),
                Text(
                  _bookingType == 'COMBO_BASED'
                      ? 'Đặt theo combo'
                      : _bookingType == 'TICKET_BASED'
                          ? 'Đặt theo vé'
                          : 'Giá theo giờ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.teal,
                  ),
                ),
                if (_bookingType == 'OPTION_BASED' ||
                    _bookingType == 'STANDARD') ...[
                  const SizedBox(width: 12),
                  Text(
                    '${_formatCurrency((detail['pricePerHour'] as num?) ?? 0)} đ/giờ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final detail = _service;
    if (detail == null) return const SizedBox.shrink();

    final today = DateTime.now();
    final lastDate = today.add(Duration(days: _advanceBookingDays(detail)));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        title: const Text(
          'Ngày sử dụng',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _selectedDate != null
              ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
              : 'Chọn ngày',
        ),
        trailing: const Icon(Icons.calendar_today),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _selectedDate ?? today,
            firstDate: today,
            lastDate: lastDate,
            selectableDayPredicate: (date) => _isDateAllowed(detail, date),
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
      ),
    );
  }

  Widget _buildTimeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Card(
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  title: const Text('Bắt đầu'),
                  subtitle: Text(_startTime != null
                      ? _startTime!.format(context)
                      : 'Chọn giờ'),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _startTime ?? TimeOfDay.now(),
                    );
                    if (time != null) {
                      setState(() {
                        _startTime = time;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  title: const Text('Kết thúc'),
                  subtitle: Text(_endTime != null
                      ? _endTime!.format(context)
                      : 'Chọn giờ'),
                  trailing: const Icon(Icons.timer_outlined),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _endTime ??
                          (_startTime != null
                              ? _addDuration(_startTime!, 1.0) ?? TimeOfDay.now()
                              : TimeOfDay.now()),
                    );
                    if (time != null) {
                      setState(() {
                        _endTime = time;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildBookedSlotsBanner(),
      ],
    );
  }

  Widget _buildBookedSlotsBanner() {
    if (_bookedSlotsLoading) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text('Đang tải các khung giờ đã được đặt...'),
              ),
            ],
          ),
        ),
      );
    }

    if (_bookedSlotsError != null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Không thể tải các khung giờ đã đặt',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _bookedSlotsError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _reloadBookedSlots(anchor: _selectedDate ?? DateTime.now()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final selected = _selectedDate;
    if (selected == null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Chọn ngày để xem những khung giờ đã được đặt trước.'),
        ),
      );
    }

    final key = DateFormat('yyyy-MM-dd').format(selected);
    final slots = _bookedSlotsByDate[key] ?? const [];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: slots.isEmpty
            ? const Text(
                'Hiện chưa có ai đặt dịch vụ trong ngày này.',
                style: TextStyle(color: Colors.black54),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Khung giờ đã được giữ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...slots.map(
                    (slot) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_clock, size: 16, color: Colors.redAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_formatDisplayTime(slot.start)} - ${_formatDisplayTime(slot.end)} • ${_translateBookingStatus(slot.status)}',
                              style: const TextStyle(fontSize: 13),
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
    if (_combos.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Hiện chưa có gói combo khả dụng.'),
        ),
      );
    }
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn gói combo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._combos.map(
              (combo) => RadioListTile<String>(
                value: combo['id'].toString(),
                groupValue: _selectedComboId,
                onChanged: (value) {
                  setState(() {
                    _selectedComboId = value;
                  });
                },
                title: Text(combo['name']?.toString() ?? 'Combo'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (combo['description'] != null &&
                        combo['description'].toString().isNotEmpty)
                      Text(combo['description'].toString()),
                    Text(
                      '${_formatCurrency((combo['price'] as num?) ?? 0)} đ / người',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.teal,
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

  Widget _buildTicketsSection() {
    if (_tickets.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Hiện chưa có loại vé khả dụng.'),
        ),
      );
    }
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn loại vé',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._tickets.map(
              (ticket) => RadioListTile<String>(
                value: ticket['id'].toString(),
                groupValue: _selectedTicketId,
                onChanged: (value) {
                  setState(() {
                    _selectedTicketId = value;
                  });
                },
                title: Text(ticket['name']?.toString() ?? 'Vé'),
                subtitle: Text(
                  '${_formatCurrency((ticket['price'] as num?) ?? 0)} đ / người',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.teal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsSection() {
    if (_options.isEmpty) return const SizedBox.shrink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tùy chọn bổ sung',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._options.map(
              (option) {
                final optionId = option['id'].toString();
                final isSelected = _selectedOptions.containsKey(optionId);
                final quantity = _selectedOptions[optionId] ?? 0;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: CheckboxListTile(
                    value: isSelected,
                    title: Text(option['name']?.toString() ?? 'Tùy chọn'),
                    subtitle: Text(
                      '${_formatCurrency((option['price'] as num?) ?? 0)} đ',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.teal,
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
                              Text('$quantity'),
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
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeopleSelector() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Số người tham gia',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _numberOfPeople > 1
                      ? () => setState(() => _numberOfPeople--)
                      : null,
                ),
                Text(
                  '$_numberOfPeople',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _numberOfPeople < _maxCapacity
                      ? () => setState(() => _numberOfPeople++)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurposeField() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ghi chú / mục đích (tuỳ chọn)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _purposeController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Ví dụ: tổ chức sinh nhật gia đình...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSummary() {
    final total = _calculateTotalAmount();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tổng chi phí dự kiến',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Chi phí cơ bản'),
                Text(
                  '${_formatCurrency(_calculateBaseAmount())} đ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (_selectedOptions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tùy chọn bổ sung'),
                  Text(
                    '${_formatCurrency(_calculateOptionsAmount())} đ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tổng thanh toán',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${_formatCurrency(total)} đ',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
          ],
        ),
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

