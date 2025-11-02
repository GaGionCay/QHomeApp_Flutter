import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'service_booking_service.dart';
import '../auth/api_client.dart';
import '../core/event_bus.dart';

class ServiceDetailScreen extends StatefulWidget {
  final int zoneId; // ID của zone (available service)
  final int serviceId; // ID của service gốc
  final DateTime selectedDate;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final int numberOfPeople;
  final String purpose;
  final String categoryCode;
  
  const ServiceDetailScreen({
    super.key,
    required this.zoneId,
    required this.serviceId,
    required this.selectedDate,
    required this.startTime,
    required this.endTime,
    required this.numberOfPeople,
    required this.purpose,
    required this.categoryCode,
  });

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> 
    with WidgetsBindingObserver {
  final ApiClient _apiClient = ApiClient();
  late final ServiceBookingService _serviceBookingService;
  final AppLinks _appLinks = AppLinks();
  
  Map<String, dynamic>? _zone;
  bool _loading = true;
  bool _submitting = false;
  StreamSubscription? _linkSubscription;
  
  static const String _pendingBookingKey = 'pending_service_booking_id';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serviceBookingService = ServiceBookingService(_apiClient.dio);
    _loadZoneDetail();
    _listenForDeepLink();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _listenForDeepLink() {
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'qhomeapp' && uri.host == 'service-booking-result') {
        final bookingIdStr = uri.queryParameters['bookingId'];
        final status = uri.queryParameters['status'];
        
        if (status == 'success' && bookingIdStr != null) {
          _handlePaymentSuccess(int.tryParse(bookingIdStr));
        }
      }
    });
  }

  Future<void> _loadZoneDetail() async {
    setState(() => _loading = true);

    try {
      // Load zone detail từ available services hoặc service detail
      // Tạm thời lấy từ service detail và merge với info từ available
      final service = await _serviceBookingService.getServiceById(widget.serviceId);
      
      // Calculate estimated amount
      final startMinutes = widget.startTime.hour * 60 + widget.startTime.minute;
      final endMinutes = widget.endTime.hour * 60 + widget.endTime.minute;
      final hours = (endMinutes - startMinutes) / 60.0;
      final estimatedAmount = (service['pricePerHour'] as num?) ?? 0 * hours;

      setState(() {
        _zone = {
          ...service,
          'estimatedTotalAmount': estimatedAmount,
        };
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tải thông tin: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handlePaymentSuccess(int? bookingId) async {
    if (bookingId != null) {
      await _removePendingBooking();
      
      if (mounted) {
        AppEventBus().emit('service_booking_payment_result', {
          'success': true,
          'bookingId': bookingId,
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanh toán thành công!'),
            backgroundColor: Colors.green,
          ),
        );
        
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    }
  }

  Future<void> _removePendingBooking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingBookingKey);
  }

  Future<void> _createBookingAndPay() async {
    if (_zone == null) return;

    setState(() => _submitting = true);

    try {
      final startTimeStr = '${widget.startTime.hour.toString().padLeft(2, '0')}:${widget.startTime.minute.toString().padLeft(2, '0')}:00';
      final endTimeStr = '${widget.endTime.hour.toString().padLeft(2, '0')}:${widget.endTime.minute.toString().padLeft(2, '0')}:00';
      
      final startMinutes = widget.startTime.hour * 60 + widget.startTime.minute;
      final endMinutes = widget.endTime.hour * 60 + widget.endTime.minute;
      final durationHours = (endMinutes - startMinutes) / 60.0;

      // Tạo booking
      final booking = await _serviceBookingService.createBooking(
        serviceId: widget.serviceId,
        bookingDate: widget.selectedDate,
        startTime: startTimeStr,
        endTime: endTimeStr,
        durationHours: durationHours,
        numberOfPeople: widget.numberOfPeople,
        purpose: widget.purpose.isEmpty ? null : widget.purpose,
        termsAccepted: true,
      );

      final bookingId = booking['id'] as int?;
      if (bookingId == null) {
        throw Exception('Không lấy được booking ID');
      }

      // Lưu pending booking
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingBookingKey, bookingId.toString());

      // Lấy VNPAY URL
      final paymentUrl = await _serviceBookingService.getVnpayPaymentUrl(bookingId);

      // Mở browser để thanh toán
      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Không thể mở URL thanh toán');
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
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: const Text(
          'Chi tiết khu vực',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF26A69A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _zone == null
              ? const Center(child: Text('Không tìm thấy thông tin'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildZoneInfo(),
                      const SizedBox(height: 24),
                      _buildBookingInfo(),
                      const SizedBox(height: 24),
                      _buildPriceSection(),
                      const SizedBox(height: 24),
                      if (_zone!['location'] != null) ...[
                        _buildLocationSection(),
                        const SizedBox(height: 24),
                      ],
                      if (_zone!['rules'] != null) ...[
                        _buildRulesSection(),
                        const SizedBox(height: 24),
                      ],
                      _buildBookingButton(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildZoneInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _zone!['name'] as String? ?? 'Khu vực',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          if (_zone!['description'] != null) ...[
            const SizedBox(height: 12),
            Text(
              _zone!['description'] as String,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookingInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Thông tin đặt chỗ',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.calendar_today, 'Ngày', 
              DateFormat('dd/MM/yyyy').format(widget.selectedDate)),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.access_time, 'Thời gian', 
              '${widget.startTime.format(context)} - ${widget.endTime.format(context)}'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.people, 'Số người', '${widget.numberOfPeople} người'),
          if (widget.purpose.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow(Icons.description, 'Mục đích', widget.purpose),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.teal),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildPriceSection() {
    final estimatedAmount = _zone!['estimatedTotalAmount'] ?? 0;
    final pricePerHour = _zone!['pricePerHour'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bảng giá',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.access_time, color: Colors.teal),
              const SizedBox(width: 8),
              Text(
                '${_formatPrice(pricePerHour)} VNĐ/giờ',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tổng cộng:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_formatPrice(estimatedAmount)} VNĐ',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vị trí',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _zone!['location'] as String,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRulesSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quy định sử dụng',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _zone!['rules'] as String,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _submitting ? null : _createBookingAndPay,
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
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Đăng ký và thanh toán',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '0';
    if (price is num) {
      return price.toInt().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (match) => '${match.group(1)},',
      );
    }
    return price.toString();
  }
}
