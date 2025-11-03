import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'service_detail_screen.dart';
import 'service_booking_service.dart';
import '../auth/api_client.dart';
import '../core/event_bus.dart';

class ServiceBookingScreen extends StatefulWidget {
  final int serviceId;
  final String serviceName;
  final String categoryCode;
  final String? serviceTypeCode; // Optional: khi có thì filter theo type này
  
  const ServiceBookingScreen({
    super.key,
    required this.serviceId,
    required this.serviceName,
    required this.categoryCode,
    this.serviceTypeCode,
  });

  @override
  State<ServiceBookingScreen> createState() => _ServiceBookingScreenState();
}

class _ServiceBookingScreenState extends State<ServiceBookingScreen> 
    with WidgetsBindingObserver {
  final ApiClient _apiClient = ApiClient();
  late final ServiceBookingService _serviceBookingService;
  
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  int _numberOfPeople = 1;
  final TextEditingController _purposeController = TextEditingController();
  bool _termsAccepted = false;
  bool _loadingAvailableZones = false;
  List<Map<String, dynamic>> _availableZones = [];
  String? _error;
  
  static const String _pendingBookingKey = 'pending_service_booking_id';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serviceBookingService = ServiceBookingService(_apiClient.dio);
    _listenForPaymentResult();
    _checkPendingPayment();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _purposeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingPayment();
    }
  }

  void _listenForPaymentResult() {
    AppEventBus().on('service_booking_payment_result', (data) {
      if (mounted) {
        final success = data['success'] == true;
        final bookingId = data['bookingId'];
        
        if (success && bookingId != null) {
          _removePendingBooking();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Thanh toán thành công!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      }
    });
  }

  Future<void> _checkPendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookingIdStr = prefs.getString(_pendingBookingKey);
      
      if (bookingIdStr != null) {
        final bookingId = int.tryParse(bookingIdStr);
        if (bookingId != null) {
          final booking = await _serviceBookingService.getBookingById(bookingId);
          if (booking['paymentStatus'] == 'PAID') {
            _removePendingBooking();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Thanh toán đã được xử lý thành công!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Bạn có một booking chưa thanh toán. Vui lòng hoàn tất thanh toán.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      print('❌ Lỗi check pending payment: $e');
    }
  }

  Future<void> _removePendingBooking() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingBookingKey);
  }

  Future<void> _searchAvailableZones() async {
    if (_selectedDate == null || _startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn đầy đủ ngày và giờ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validate time range
    final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
    final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
    
    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Giờ kết thúc phải sau giờ bắt đầu'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _loadingAvailableZones = true;
      _error = null;
      _availableZones = [];
    });

    try {
      final startTimeStr = '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}:00';
      final endTimeStr = '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}:00';
      
      final zones = await _serviceBookingService.getAvailableServices(
        categoryCode: widget.categoryCode,
        date: _selectedDate!,
        startTime: startTimeStr,
        endTime: endTimeStr,
        serviceType: widget.serviceTypeCode, // Pass serviceTypeCode để filter
      );

      setState(() {
        _availableZones = zones;
        _loadingAvailableZones = false;
      });

      if (zones.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không có khu vực nào khả dụng trong khoảng thời gian này'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingAvailableZones = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tìm kiếm khu vực: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: Text(
          widget.serviceName,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF26A69A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateSelector(),
            const SizedBox(height: 16),
            _buildTimeSelector(),
            const SizedBox(height: 16),
            _buildPeopleSelector(),
            const SizedBox(height: 16),
            _buildPurposeInput(),
            const SizedBox(height: 24),
            _buildSearchButton(),
            if (_loadingAvailableZones)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Lỗi: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            if (_availableZones.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Các khu vực khả dụng',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ..._availableZones.map((zone) => _buildZoneCard(zone)),
            ],
            if (_availableZones.isEmpty && !_loadingAvailableZones && _error == null && 
                _selectedDate != null && _startTime != null && _endTime != null) ...[
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Nhấn "Tìm kiếm khu vực" để xem các khu vực khả dụng',
                      style: TextStyle(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    final today = DateTime.now();
    final maxDate = today.add(const Duration(days: 7)); // Giới hạn 1 tuần

    return _buildSection(
      title: 'Chọn ngày',
      child: InkWell(
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: _selectedDate ?? today,
            firstDate: today,
            lastDate: maxDate,
          );
          if (date != null) {
            setState(() {
              _selectedDate = date;
              _availableZones = []; // Clear khi đổi ngày
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, color: Colors.teal),
              const SizedBox(width: 12),
              Text(
                _selectedDate != null
                    ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
                    : 'Chọn ngày (từ hôm nay đến 1 tuần sau)',
                style: TextStyle(
                  fontSize: 16,
                  color: _selectedDate != null ? Colors.black : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSelector() {
    return _buildSection(
      title: 'Chọn khoảng thời gian',
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: _startTime ?? const TimeOfDay(hour: 14, minute: 0),
                );
                if (time != null) {
                  setState(() {
                    _startTime = time;
                    _availableZones = []; // Clear khi đổi giờ
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time, color: Colors.teal),
                    const SizedBox(width: 12),
                    Text(
                      _startTime != null
                          ? _startTime!.format(context)
                          : 'Giờ bắt đầu',
                      style: TextStyle(
                        fontSize: 16,
                        color: _startTime != null ? Colors.black : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: InkWell(
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: _endTime ?? const TimeOfDay(hour: 17, minute: 0),
                );
                if (time != null) {
                  setState(() {
                    _endTime = time;
                    _availableZones = []; // Clear khi đổi giờ
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time, color: Colors.teal),
                    const SizedBox(width: 12),
                    Text(
                      _endTime != null
                          ? _endTime!.format(context)
                          : 'Giờ kết thúc',
                      style: TextStyle(
                        fontSize: 16,
                        color: _endTime != null ? Colors.black : Colors.grey,
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

  Widget _buildPeopleSelector() {
    return _buildSection(
      title: 'Số người tham gia',
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: _numberOfPeople > 1
                ? () => setState(() => _numberOfPeople--)
                : null,
          ),
          Text(
            '$_numberOfPeople người',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => setState(() => _numberOfPeople++),
          ),
        ],
      ),
    );
  }

  Widget _buildPurposeInput() {
    return _buildSection(
      title: 'Mục đích sử dụng (tùy chọn)',
      child: TextField(
        controller: _purposeController,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: 'Nhập mục đích sử dụng...',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchButton() {
    final canSearch = _selectedDate != null && _startTime != null && _endTime != null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canSearch ? _searchAvailableZones : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF26A69A),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'Tìm kiếm khu vực khả dụng',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildZoneCard(Map<String, dynamic> zone) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceDetailScreen(
                  zoneId: zone['id'] as int,
                  serviceId: zone['id'] as int, // Use zone ID as serviceId
                  selectedDate: _selectedDate!,
                  startTime: _startTime!,
                  endTime: _endTime!,
                  numberOfPeople: _numberOfPeople,
                  purpose: _purposeController.text,
                  categoryCode: widget.categoryCode,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        zone['name'] as String? ?? 'Khu vực',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        zone['availabilityStatus'] == 'AVAILABLE' ? 'Có sẵn' : 'Một phần',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[800],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (zone['description'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    zone['description'] as String,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (zone['location'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.red),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          zone['location'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (zone['estimatedTotalAmount'] != null) ...[
                      const Icon(Icons.attach_money, size: 16, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        '${_formatPrice(zone['estimatedTotalAmount'])} VNĐ',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                    ],
                    if (zone['maxCapacity'] != null) ...[
                      const Spacer(),
                      const Icon(Icons.people, size: 16, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text(
                        'Tối đa ${zone['maxCapacity']} người',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
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
