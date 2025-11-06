import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
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
  
  // Service-specific items
  final List<Map<String, dynamic>>? selectedOptions;
  final int? selectedComboId;
  final int? selectedTicketId;
  final int? selectedServiceSlotId;
  final int? extraHours;
  
  // Price information (tính từ screen trước)
  final num? estimatedTotalAmount;
  final Map<String, dynamic>? selectedCombo; // Combo details for display
  final Map<String, dynamic>? selectedTicket; // Ticket details for display
  final List<Map<String, dynamic>>? selectedOptionsDetails; // Options details for display
  
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
    this.selectedOptions,
    this.selectedComboId,
    this.selectedTicketId,
    this.selectedServiceSlotId,
    this.extraHours,
    this.estimatedTotalAmount,
    this.selectedCombo,
    this.selectedTicket,
    this.selectedOptionsDetails,
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
      
      // Use estimated amount từ widget (đã tính từ screen trước)
      num estimatedAmount = widget.estimatedTotalAmount ?? 0;
      
      // Nếu chưa có, tính lại từ widget data
      if (estimatedAmount == 0) {
        final bookingType = service['bookingType'] as String?;
        
        if (bookingType == 'COMBO_BASED' && widget.selectedCombo != null) {
          final comboPrice = widget.selectedCombo!['price'] as num? ?? 0;
          // Giá = combo price * số người
          estimatedAmount = comboPrice * widget.numberOfPeople;
        } else if (bookingType == 'TICKET_BASED' && widget.selectedTicket != null) {
          final ticketPrice = widget.selectedTicket!['price'] as num? ?? 0;
          // Tất cả ticket-based: giá = vé * số người
          estimatedAmount = ticketPrice * widget.numberOfPeople;
        } else if (bookingType == 'OPTION_BASED') {
          final startMinutes = widget.startTime.hour * 60 + widget.startTime.minute;
          final endMinutes = widget.endTime.hour * 60 + widget.endTime.minute;
          final hours = (endMinutes - startMinutes) / 60.0;
          final pricePerHour = (service['pricePerHour'] as num?) ?? 0;
          estimatedAmount = pricePerHour * hours;
          
          if (widget.selectedOptionsDetails != null) {
            for (var opt in widget.selectedOptionsDetails!) {
              estimatedAmount += (opt['price'] as num? ?? 0) * (opt['quantity'] as num? ?? 1);
            }
          }
          
          if (widget.extraHours != null && widget.extraHours! > 0) {
            estimatedAmount += 100000 * widget.extraHours!;
          }
        } else {
          // STANDARD
          final startMinutes = widget.startTime.hour * 60 + widget.startTime.minute;
          final endMinutes = widget.endTime.hour * 60 + widget.endTime.minute;
          final hours = (endMinutes - startMinutes) / 60.0;
          final pricePerHour = (service['pricePerHour'] as num?) ?? 0;
          estimatedAmount = pricePerHour * hours;
        }
      }

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
        selectedOptions: widget.selectedOptions,
        selectedComboId: widget.selectedComboId,
        selectedTicketId: widget.selectedTicketId,
        selectedServiceSlotId: widget.selectedServiceSlotId,
        extraHours: widget.extraHours,
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
        String errorMessage = 'Đã có lỗi xảy ra. Vui lòng thử lại.';
        
        // Xử lý DioException để lấy message từ response
        if (e is DioException) {
          if (e.response != null) {
            final statusCode = e.response!.statusCode;
            // Xử lý cả 400 và 500 để lấy message từ response
            if (statusCode == 400 || statusCode == 500) {
              try {
                final responseData = e.response!.data;
                if (responseData is Map<String, dynamic>) {
                  // Lấy message từ response (có thể có prefix "Lỗi hệ thống: ")
                  String rawMessage = responseData['message'] ?? errorMessage;
                  
                  // Loại bỏ prefix "Lỗi hệ thống: " nếu có
                  if (rawMessage.startsWith('Lỗi hệ thống: ')) {
                    rawMessage = rawMessage.substring('Lỗi hệ thống: '.length);
                  }
                  
                  errorMessage = rawMessage;
                  
                  // Kiểm tra errorCode để hiển thị message và icon phù hợp
                  final errorCode = responseData['errorCode'];
                  if (errorCode == 'UNPAID_BOOKING_EXISTS') {
                    errorMessage = 'Bạn có một hóa đơn booking dịch vụ chưa hoàn tất. Không thể đặt dịch vụ mới.';
                  } else if (errorCode == 'SERVICE_NOT_AVAILABLE') {
                    // Message đã được set từ backend với thông tin chi tiết
                    // Nếu có reason, có thể hiển thị thêm
                    final reason = responseData['reason'];
                    if (reason != null && reason.toString().isNotEmpty) {
                      errorMessage = '$errorMessage\n\n$reason';
                    }
                  }
                }
              } catch (_) {
                // Fallback to default message
              }
            }
          }
        }
        
        // Hiển thị dialog thay vì SnackBar
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Text('Thông báo'),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(
                errorMessage,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đã hiểu'),
              ),
            ],
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
    final bookingType = _zone?['bookingType'] as String?;
    
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
          
          // Hiển thị thông tin theo booking type
          if (bookingType == 'COMBO_BASED') ...[
            if (widget.selectedServiceSlotId != null && _zone?['serviceSlots'] != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.access_time, 'Khung giờ', 
                  _getServiceSlotName(widget.selectedServiceSlotId!)),
            ],
            if (widget.selectedCombo != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.restaurant_menu, 'Gói combo', 
                  widget.selectedCombo!['name'] as String? ?? 'Combo'),
              if (widget.selectedCombo!['servicesIncluded'] != null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Text(
                    'Bao gồm: ${widget.selectedCombo!['servicesIncluded']}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ),
              ],
            ],
          ] else if (bookingType == 'TICKET_BASED') ...[
            if (widget.selectedTicket != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.confirmation_number, 'Vé', 
                  widget.selectedTicket!['name'] as String? ?? 'Vé'),
            ],
          ] else ...[
            // OPTION_BASED và STANDARD
            const SizedBox(height: 8),
            _buildInfoRow(Icons.access_time, 'Thời gian', 
                '${_formatTimeOfDay(widget.startTime)} - ${_formatTimeOfDay(widget.endTime)}'),
            if (widget.selectedOptionsDetails != null && widget.selectedOptionsDetails!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.checklist, 'Tùy chọn', 
                  '${widget.selectedOptionsDetails!.length} tùy chọn'),
            ],
            if (widget.extraHours != null && widget.extraHours! > 0) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.schedule, 'Thuê thêm giờ', '${widget.extraHours} giờ'),
            ],
          ],
          
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
  
  String _getServiceSlotName(int slotId) {
    // Load từ service slots nếu có
    // TODO: Cần load service slots từ API hoặc pass từ screen trước
    return 'Khung giờ đã chọn';
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
    final bookingType = _zone?['bookingType'] as String?;
    final estimatedAmount = widget.estimatedTotalAmount ?? _zone?['estimatedTotalAmount'] ?? 0;
    
    // Tính toán giá trước (không thể khai báo final trong collection spread)
    num? ticketPrice;
    String? serviceCode;
    num? pricePerHour;
    double? hours;
    
    if (bookingType == 'TICKET_BASED' && widget.selectedTicket != null) {
      ticketPrice = widget.selectedTicket!['price'] as num? ?? 0;
      serviceCode = _zone?['code']?.toString() ?? '';
    } else if (bookingType == 'OPTION_BASED' || bookingType == null || bookingType == 'STANDARD') {
      pricePerHour = _zone?['pricePerHour'] as num? ?? 0;
      final startMinutes = widget.startTime.hour * 60 + widget.startTime.minute;
      final endMinutes = widget.endTime.hour * 60 + widget.endTime.minute;
      hours = (endMinutes - startMinutes) / 60.0;
    }
    
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
          
          // Hiển thị chi tiết giá theo booking type
          ..._buildPriceDetails(bookingType, ticketPrice, serviceCode, pricePerHour, hours),
          
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
  
  List<Widget> _buildPriceDetails(String? bookingType, num? ticketPrice, String? serviceCode, num? pricePerHour, double? hours) {
    List<Widget> widgets = [];
    
    if (bookingType == 'COMBO_BASED' && widget.selectedCombo != null) {
      final comboPrice = widget.selectedCombo!['price'] as num? ?? 0;
      // Hiển thị: Gói combo, Số người, Tổng tiền
      widgets.add(_buildPriceRow('Gói combo (${widget.selectedCombo!['name']})', comboPrice));
      widgets.add(_buildPriceRow('Số người', widget.numberOfPeople));
      widgets.add(_buildPriceRow('Tổng combo', comboPrice * widget.numberOfPeople));
    } else if (bookingType == 'TICKET_BASED' && widget.selectedTicket != null && ticketPrice != null) {
      // Tất cả ticket-based: hiển thị vé, số người, tổng vé
      widgets.add(_buildPriceRow('Vé (${widget.selectedTicket!['name']})', ticketPrice));
      widgets.add(_buildPriceRow('Số người', widget.numberOfPeople));
      widgets.add(_buildPriceRow('Tổng vé', ticketPrice * widget.numberOfPeople));
    } else if (bookingType == 'OPTION_BASED' && pricePerHour != null && hours != null) {
      widgets.add(_buildPriceRow('Giá cơ bản', pricePerHour * hours));
      if (widget.selectedOptionsDetails != null) {
        for (var opt in widget.selectedOptionsDetails!) {
          widgets.add(_buildPriceRow(
            opt['name'] as String? ?? 'Tùy chọn', 
            (opt['price'] as num? ?? 0) * (opt['quantity'] as num? ?? 1)
          ));
        }
      }
      if (widget.extraHours != null && widget.extraHours! > 0) {
        widgets.add(_buildPriceRow('Thuê thêm giờ', 100000 * widget.extraHours!));
      }
    } else if (pricePerHour != null && hours != null) {
      // STANDARD
      widgets.add(_buildPriceRow('Giá/giờ', pricePerHour));
      widgets.add(_buildPriceRow('Số giờ', hours));
      widgets.add(_buildPriceRow('Tổng cơ bản', pricePerHour * hours));
    }
    
    return widgets;
  }
  
  Widget _buildPriceRow(String label, num amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            amount is int ? '$amount' : _formatPrice(amount),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
  
  // Format TimeOfDay thành "HH:mm"
  String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
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
