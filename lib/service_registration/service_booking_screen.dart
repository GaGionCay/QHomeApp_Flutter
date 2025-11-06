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
  int _numberOfPeople = 1;
  final TextEditingController _purposeController = TextEditingController();
  bool _termsAccepted = false;
  bool _loadingTimeSlots = false;
  bool _loadingZones = false;
  bool _loadingServiceData = false;
  List<Map<String, dynamic>> _timeSlots = [];
  List<Map<String, dynamic>> _zones = []; // List of zones/services when serviceTypeCode is provided
  String? _error;
  Map<String, dynamic>? _selectedTimeSlot; // Selected time slot for booking
  int? _selectedZoneId; // Selected zone/service ID when serviceTypeCode is provided
  
  // Service data
  Map<String, dynamic>? _serviceDetail; // Service detail với code
  String? _serviceType; // BBQ, SPA, POOL, PLAYGROUND, BAR
  
  // BBQ
  List<Map<String, dynamic>> _options = [];
  Map<int, int> _selectedOptions = {}; // optionId -> quantity
  int _extraHours = 0;
  
  // SPA, Bar
  List<Map<String, dynamic>> _combos = [];
  int? _selectedComboId;
  
  // Pool, Playground
  List<Map<String, dynamic>> _tickets = [];
  int? _selectedTicketId;
  
  // Service slots (generic - dùng cho Bar, BBQ, và các service khác)
  List<Map<String, dynamic>> _serviceSlots = [];
  int? _selectedServiceSlotId;
  
  static const String _pendingBookingKey = 'pending_service_booking_id';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serviceBookingService = ServiceBookingService(_apiClient.dio);
    _listenForPaymentResult();
    _checkPendingPayment();
    
    // Nếu có serviceTypeCode nhưng serviceId = 0, cần load danh sách zones
    if (widget.serviceTypeCode != null && widget.serviceId == 0) {
      _loadZones();
    } else if (widget.serviceId != 0) {
      // Load service detail và xác định service type
      _loadServiceDetail();
    }
  }
  
  Future<void> _loadServiceDetail() async {
    setState(() {
      _loadingServiceData = true;
      _error = null;
    });
    
    try {
      final service = await _serviceBookingService.getServiceById(widget.serviceId);
      
      setState(() {
        _serviceDetail = service;
        final bookingType = service['bookingType'] as String?;
        _serviceType = _determineServiceType(bookingType);
        _loadingServiceData = false;
      });
      
      if (_serviceType == 'OPTION_BASED') {
        await _loadOptions();
        if (_selectedDate != null) {
          await _loadServiceSlots();
        }
      } else if (_serviceType == 'COMBO_BASED') {
        await _loadCombos();
        if (_selectedDate != null) {
          await _loadServiceSlots();
        }
      } else if (_serviceType == 'TICKET_BASED') {
        await _loadTickets();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingServiceData = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tải thông tin dịch vụ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  String? _determineServiceType(String? bookingType) {
    if (bookingType == null) return null;
    
    switch (bookingType.toUpperCase()) {
      case 'OPTION_BASED':
        return 'OPTION_BASED';
      case 'COMBO_BASED':
        return 'COMBO_BASED';
      case 'TICKET_BASED':
        return 'TICKET_BASED';
      case 'STANDARD':
        return 'STANDARD';
      default:
        return null;
    }
  }
  
  Future<void> _loadOptions() async {
    try {
      final serviceIdToUse = widget.serviceId != 0 ? widget.serviceId : _selectedZoneId;
      if (serviceIdToUse == null) return;
      
      final options = await _serviceBookingService.getServiceOptions(serviceIdToUse);
      setState(() {
        _options = options;
      });
    } catch (e) {
      print('❌ Lỗi lấy options: $e');
    }
  }
  
  Future<void> _loadCombos() async {
    try {
      final serviceIdToUse = widget.serviceId != 0 ? widget.serviceId : _selectedZoneId;
      if (serviceIdToUse == null) return;
      
      final combos = await _serviceBookingService.getServiceCombos(serviceIdToUse);
      setState(() {
        _combos = combos;
      });
    } catch (e) {
      print('❌ Lỗi lấy combos: $e');
    }
  }
  
  Future<void> _loadTickets() async {
    try {
      final serviceIdToUse = widget.serviceId != 0 ? widget.serviceId : _selectedZoneId;
      if (serviceIdToUse == null) return;
      
      final tickets = await _serviceBookingService.getServiceTickets(serviceIdToUse);
      setState(() {
        _tickets = tickets;
      });
    } catch (e) {
      print('❌ Lỗi lấy tickets: $e');
    }
  }
  
  Future<void> _loadServiceSlots() async {
    try {
      final serviceIdToUse = widget.serviceId != 0 ? widget.serviceId : _selectedZoneId;
      if (serviceIdToUse == null) return;
      
      // Convert selectedDate to DateTime nếu có
      DateTime? selectedDate;
      if (_selectedDate != null) {
        selectedDate = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      }
      
      final slots = await _serviceBookingService.getServiceSlots(serviceIdToUse, selectedDate: selectedDate);
      setState(() {
        _serviceSlots = slots;
      });
    } catch (e) {
      print('❌ Lỗi lấy service slots: $e');
    }
  }
  
  Future<void> _loadServiceDetailForZone(int zoneId) async {
    try {
      final service = await _serviceBookingService.getServiceById(zoneId);
      
      setState(() {
        _serviceDetail = service;
        final bookingType = service['bookingType'] as String?;
        _serviceType = _determineServiceType(bookingType);
      });
      
      // Load data theo booking_type từ database
      if (_serviceType == 'OPTION_BASED') {
        await _loadOptions();
        // Load service slots nếu có (cho BBQ và các service khác)
        if (_selectedDate != null) {
          await _loadServiceSlots();
        }
      } else if (_serviceType == 'COMBO_BASED') {
        await _loadCombos();
        // Load service slots nếu có (cho Bar và các service khác)
        if (_selectedDate != null) {
          await _loadServiceSlots();
        }
      } else if (_serviceType == 'TICKET_BASED') {
        await _loadTickets();
      }
    } catch (e) {
      print('❌ Lỗi load service detail cho zone: $e');
    }
  }
  
  Future<void> _loadZones() async {
    if (widget.serviceTypeCode == null) {
      return;
    }
    
    setState(() {
      _loadingZones = true;
      _error = null;
      _zones = [];
    });
    
    try {
      final zones = await _serviceBookingService.getServicesByCategoryCodeAndType(
        widget.categoryCode,
        widget.serviceTypeCode!,
      );
      
      setState(() {
        _zones = zones;
        _loadingZones = false;
        
        // Nếu chỉ có 1 zone, tự động chọn
        if (zones.length == 1) {
          final zoneId = zones.first['id'] as int;
          setState(() {
            _selectedZoneId = zoneId;
          });
          // Load service detail cho zone đã chọn
          _loadServiceDetailForZone(zoneId);
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingZones = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tải danh sách khu vực: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  Future<void> _loadTimeSlots() async {
    if (_selectedDate == null) {
      return;
    }
    
    // COMBO_BASED và TICKET_BASED không cần time slots
    if (_serviceType == 'COMBO_BASED' || _serviceType == 'TICKET_BASED') {
      return;
    }
    
    // Xác định serviceId để dùng
    int serviceIdToUse = widget.serviceId;
    if (serviceIdToUse == 0 && _selectedZoneId != null) {
      serviceIdToUse = _selectedZoneId!;
    }
    
    if (serviceIdToUse == 0) {
      // Chưa chọn zone, không thể load time slots
      return;
    }

    setState(() {
      _loadingTimeSlots = true;
      _error = null;
      _timeSlots = [];
      _selectedTimeSlot = null;
    });

    try {
      final slots = await _serviceBookingService.getTimeSlotsForService(
        serviceId: serviceIdToUse,
        date: _selectedDate!,
      );

      setState(() {
        _timeSlots = slots;
        _loadingTimeSlots = false;
      });

      if (slots.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không có khung giờ nào cho ngày này'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingTimeSlots = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tải khung giờ: $e'),
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
            // Nếu có serviceTypeCode và serviceId = 0, hiển thị zone selector
            if (widget.serviceTypeCode != null && widget.serviceId == 0) ...[
              _buildZoneSelector(),
              const SizedBox(height: 16),
            ],
            _buildDateSelector(),
            const SizedBox(height: 16),
            // Hiển thị UI theo booking_type từ database
            // COMBO_BASED và TICKET_BASED không cần time slot (bỏ phần chọn khung giờ cũ)
            if (_serviceType == 'COMBO_BASED' || _serviceType == 'TICKET_BASED') ...[
              if (_selectedDate != null) ...[
                if (_serviceType == 'COMBO_BASED') ...[
                  // Hiển thị service slots nếu có (generic - cho Bar, BBQ, và các service khác)
                  if (_serviceSlots.isNotEmpty) ...[
                    _buildServiceSlots(),
                    const SizedBox(height: 16),
                  ],
                  _buildSPACombos(), // Generic combo selector
                  const SizedBox(height: 16),
                ] else if (_serviceType == 'TICKET_BASED') ...[
                  _buildTickets(),
                  const SizedBox(height: 16),
                ],
                _buildPeopleSelector(),
                const SizedBox(height: 16),
                _buildPurposeInput(),
                const SizedBox(height: 24),
                _buildBookingButton(),
              ],
            ] else if (_selectedDate != null && (widget.serviceId != 0 || _selectedZoneId != null)) ...[
              // OPTION_BASED và STANDARD: ưu tiên service slots nếu có, nếu không thì dùng time slots động
              if (_serviceSlots.isNotEmpty) ...[
                // Service có service slots - hiển thị slots từ database
                _buildServiceSlots(),
                const SizedBox(height: 16),
                if (_serviceType == 'OPTION_BASED') ...[
                  _buildBBQOptions(), // Generic option selector
                  const SizedBox(height: 16),
                ],
              ] else ...[
                // Service không có service slots - dùng time slots động
                if (_loadingTimeSlots)
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
                if (_timeSlots.isNotEmpty) ...[
                  const Text(
                    'Chọn khung giờ',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTimeSlotGrid(),
                  const SizedBox(height: 16),
                ],
                if (_selectedTimeSlot != null) ...[
                  if (_serviceType == 'OPTION_BASED') ...[
                    _buildBBQOptions(), // Generic option selector
                    const SizedBox(height: 16),
                  ],
                ],
              ],
              _buildPeopleSelector(),
              const SizedBox(height: 16),
              _buildPurposeInput(),
              const SizedBox(height: 24),
              _buildBookingButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildZoneSelector() {
    return _buildSection(
      title: 'Chọn khu vực',
      child: _loadingZones
          ? const Center(child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ))
          : _zones.isEmpty
              ? const Text(
                  'Không có khu vực nào',
                  style: TextStyle(color: Colors.grey),
                )
              : Column(
                  children: _zones.map((zone) {
                    final zoneId = zone['id'] as int;
                    final isSelected = _selectedZoneId == zoneId;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedZoneId = zoneId;
                            _timeSlots = []; // Clear time slots khi đổi zone
                            _selectedTimeSlot = null;
                          });
                          // Load service detail cho zone mới
                          _loadServiceDetailForZone(zoneId);
                          // Nếu đã chọn ngày, tự động load time slots cho zone mới
                          if (_selectedDate != null) {
                            _loadTimeSlots();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? const Color(0xFF26A69A).withOpacity(0.1)
                                : Colors.white,
                            border: Border.all(
                              color: isSelected 
                                  ? const Color(0xFF26A69A)
                                  : Colors.grey[300]!,
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      zone['name'] as String? ?? 'Khu vực',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected 
                                            ? const Color(0xFF26A69A)
                                            : Colors.black,
                                      ),
                                    ),
                                    if (zone['location'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        zone['location'] as String,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                    if (zone['maxCapacity'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tối đa: ${zone['maxCapacity']} người',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF26A69A),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
    );
  }

  Widget _buildDateSelector() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDate = today.add(const Duration(days: 7)); // Giới hạn 1 tuần

    return _buildSection(
      title: 'Chọn ngày',
      child: InkWell(
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: _selectedDate ?? today,
            firstDate: today, // Chỉ cho phép từ hôm nay
            lastDate: maxDate,
            selectableDayPredicate: (DateTime day) {
              // Chỉ cho phép chọn từ hôm nay trở đi
              return !day.isBefore(today);
            },
          );
          if (date != null) {
            setState(() {
              _selectedDate = date;
              _timeSlots = []; // Clear time slots
              _selectedTimeSlot = null; // Clear selected slot
            });
            // Tự động load time slots khi chọn ngày
            _loadTimeSlots();
            // Reload service slots khi date thay đổi (cho services có slots)
            if (_serviceType == 'COMBO_BASED' || _serviceType == 'OPTION_BASED') {
              _loadServiceSlots();
            }
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

  Widget _buildTimeSlotGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.5,
      ),
      itemCount: _timeSlots.length,
      itemBuilder: (context, index) {
        final slot = _timeSlots[index];
        final isAvailable = slot['available'] == true;
        final isSelected = _selectedTimeSlot != null && 
            _selectedTimeSlot!['startTime'] == slot['startTime'];
        
        return InkWell(
          onTap: isAvailable ? () {
            setState(() {
              _selectedTimeSlot = slot;
            });
          } : null,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected 
                  ? const Color(0xFF26A69A)
                  : isAvailable 
                      ? Colors.green[50]
                      : Colors.red[50],
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF26A69A)
                    : isAvailable
                        ? Colors.green[300]!
                        : Colors.red[300]!,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${_formatTime(slot['startTime'])} - ${_formatTime(slot['endTime'])}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected 
                        ? Colors.white
                        : isAvailable 
                            ? Colors.green[800]
                            : Colors.red[800],
                  ),
                ),
                if (slot['reason'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    slot['reason'] as String,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected 
                          ? Colors.white70
                          : isAvailable 
                              ? Colors.green[600]
                              : Colors.red[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (slot['bookedPeople'] != null && slot['availableCapacity'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${slot['bookedPeople']}/${slot['bookedPeople'] + slot['availableCapacity']}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected 
                          ? Colors.white70
                          : isAvailable 
                              ? Colors.green[600]
                              : Colors.red[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPeopleSelector() {
    // Get max capacity from selected zone or time slot
    int maxCapacity = 999;
    int availableCapacity = 999;
    
    // Ưu tiên lấy từ selected zone
    if (widget.serviceId == 0 && _selectedZoneId != null) {
      final selectedZone = _zones.firstWhere(
        (zone) => zone['id'] == _selectedZoneId,
        orElse: () => {},
      );
      if (selectedZone.isNotEmpty) {
        maxCapacity = selectedZone['maxCapacity'] as int? ?? 999;
      }
    } else if (widget.serviceId != 0) {
      // Nếu có serviceId, có thể lấy từ service detail (cần load nếu chưa có)
      // Tạm thời dùng default
    }
    
    // Nếu có time slot, lấy capacity từ đó
    if (_selectedTimeSlot != null) {
      final bookedPeople = _selectedTimeSlot!['bookedPeople'] as int? ?? 0;
      final availableCap = _selectedTimeSlot!['availableCapacity'] as int?;
      if (availableCap != null) {
        availableCapacity = availableCap;
        maxCapacity = bookedPeople + availableCap;
      } else {
        // Nếu time slot không có capacity info, dùng từ zone
        availableCapacity = maxCapacity;
      }
    } else {
      availableCapacity = maxCapacity;
    }
    
    // Limit max people to available capacity
    int maxAllowedPeople = availableCapacity;
    
    return _buildSection(
      title: 'Số người tham gia',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                onPressed: _numberOfPeople < maxAllowedPeople
                    ? () => setState(() => _numberOfPeople++)
                    : null,
              ),
            ],
          ),
          if (maxCapacity < 999) ...[
            const SizedBox(height: 8),
            Text(
              'Tối đa: $maxCapacity người/khu vực',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
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
  
  // ============================================
  // Widget methods cho từng loại service
  // ============================================
  
  Widget _buildBBQOptions() {
    // Filter options: chỉ hiển thị thịt và cồn, bỏ lửa
    final filteredOptions = _options.where((option) {
      final code = (option['code'] as String? ?? '').toUpperCase();
      return code.contains('MEAT') || code.contains('ALCOHOL');
    }).toList();
    
    if (filteredOptions.isEmpty && _extraHours == 0) {
      return const SizedBox.shrink();
    }
    
    return _buildSection(
      title: 'Tùy chọn dịch vụ ${_serviceDetail?['name'] ?? 'dịch vụ'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Options (thịt, cồn)
          ...filteredOptions.map((option) {
            final optionId = option['id'] as int;
            final isSelected = _selectedOptions.containsKey(optionId);
            final quantity = _selectedOptions[optionId] ?? 0;
            
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: CheckboxListTile(
                title: Text(option['name'] as String? ?? ''),
                subtitle: Text(
                  '${_formatPrice(option['price'] as num? ?? 0)} VNĐ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                value: isSelected,
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedOptions[optionId] = 1;
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
                            icon: const Icon(Icons.remove),
                            onPressed: () {
                              setState(() {
                                if (quantity > 1) {
                                  _selectedOptions[optionId] = quantity - 1;
                                } else {
                                  _selectedOptions.remove(optionId);
                                }
                              });
                            },
                          ),
                          Text('$quantity'),
                          IconButton(
                            icon: const Icon(Icons.add),
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
          }),
          
          // Option thuê thêm giờ (checkbox với số giờ)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: CheckboxListTile(
              title: const Text('Thuê thêm giờ'),
              subtitle: Text('${_formatPrice(100000)} VNĐ/giờ'),
              value: _extraHours > 0,
              onChanged: (checked) {
                setState(() {
                  _extraHours = checked == true ? 1 : 0;
                });
              },
              secondary: _extraHours > 0
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove),
                          onPressed: _extraHours > 1
                              ? () {
                                  setState(() {
                                    _extraHours--;
                                  });
                                }
                              : null,
                        ),
                        Text('$_extraHours giờ'),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            setState(() {
                              _extraHours++;
                            });
                          },
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatPrice(num price) {
    return price.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }
  
  // Format time từ "HH:mm:ss" thành "HH:mm"
  String _formatTime(dynamic timeValue) {
    if (timeValue == null) return '';
    final timeStr = timeValue.toString();
    // Nếu format là "HH:mm:ss", chỉ lấy "HH:mm"
    if (timeStr.contains(':')) {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        return '${parts[0]}:${parts[1]}';
      }
    }
    return timeStr;
  }
  
  Widget _buildSPACombos() {
    if (_combos.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return _buildSection(
      title: 'Chọn gói combo',
      child: Column(
        children: _combos.map((combo) {
          final comboId = combo['id'] as int;
          final isSelected = _selectedComboId == comboId;
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: RadioListTile<int>(
              title: Text(combo['name'] as String? ?? ''),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (combo['description'] != null)
                    Text(combo['description'] as String),
                  if (combo['servicesIncluded'] != null)
                    Text(
                      'Bao gồm: ${combo['servicesIncluded']}',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  Text(
                    '${_formatPrice(combo['price'] as num? ?? 0)} VNĐ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              value: comboId,
              groupValue: _selectedComboId,
              onChanged: (value) {
                setState(() {
                  _selectedComboId = value;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }
  
  Widget _buildTickets() {
    if (_tickets.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return _buildSection(
      title: 'Chọn vé',
      child: Column(
        children: _tickets.map((ticket) {
          final ticketId = ticket['id'] as int;
          final isSelected = _selectedTicketId == ticketId;
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: RadioListTile<int>(
              title: Text(ticket['name'] as String? ?? ''),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ticket['description'] != null)
                    Text(ticket['description'] as String),
                  Text(
                    '${_formatPrice(ticket['price'] as num? ?? 0)} VNĐ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              value: ticketId,
              groupValue: _selectedTicketId,
              onChanged: (value) {
                setState(() {
                  _selectedTicketId = value;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }
  
  Widget _buildServiceSlots() {
    if (_serviceSlots.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return _buildSection(
      title: 'Chọn khung giờ',
      child: Column(
        children: _serviceSlots.map((slot) {
          final slotId = slot['id'] as int;
          final isSelected = _selectedServiceSlotId == slotId;
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: RadioListTile<int>(
              title: Text('${_formatTime(slot['startTime'])} - ${_formatTime(slot['endTime'])}'),
              subtitle: slot['name'] != null
                  ? Text(slot['name'] as String)
                  : slot['note'] != null
                      ? Text(slot['note'] as String)
                      : null,
              value: slotId,
              groupValue: _selectedServiceSlotId,
              onChanged: (value) {
                setState(() {
                  _selectedServiceSlotId = value;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }
  
  Widget _buildBarCombos() {
    if (_combos.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return _buildSection(
      title: 'Chọn combo đồ uống',
      child: Column(
        children: _combos.map((combo) {
          final comboId = combo['id'] as int;
          final isSelected = _selectedComboId == comboId;
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: RadioListTile<int>(
              title: Text(combo['name'] as String? ?? ''),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (combo['servicesIncluded'] != null)
                    Text('Bao gồm: ${combo['servicesIncluded']}'),
                  Text(
                    '${_formatPrice(combo['price'] as num? ?? 0)} VNĐ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              value: comboId,
              groupValue: _selectedComboId,
              onChanged: (value) {
                setState(() {
                  _selectedComboId = value;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }


  Widget _buildBookingButton() {
    bool canBook = _selectedDate != null && _numberOfPeople > 0;
    
    if (_serviceType == 'OPTION_BASED' || _serviceType == 'STANDARD') {
      // OPTION_BASED và STANDARD: nếu có service slots thì dùng slots, nếu không thì dùng time slot động
      if (_serviceSlots.isNotEmpty) {
        canBook = canBook && _selectedServiceSlotId != null;
      } else {
        canBook = canBook && _selectedTimeSlot != null;
      }
    } else if (_serviceType == 'COMBO_BASED') {
      // COMBO_BASED cần combo
      canBook = canBook && _selectedComboId != null;
      // Nếu có service slots thì cũng cần chọn slot
      if (_serviceSlots.isNotEmpty) {
        canBook = canBook && _selectedServiceSlotId != null;
      }
    } else if (_serviceType == 'TICKET_BASED') {
      // TICKET_BASED cần ticket
      canBook = canBook && _selectedTicketId != null;
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canBook ? () {
          // Parse time from time slot (nếu có)
          TimeOfDay startTime;
          TimeOfDay endTime;
          
          if (_serviceType == 'OPTION_BASED' || _serviceType == 'STANDARD') {
            // OPTION_BASED và STANDARD: ưu tiên service slots nếu có, nếu không thì dùng time slot động
            if (_serviceSlots.isNotEmpty && _selectedServiceSlotId != null) {
              // Dùng service slot từ database
              final selectedSlot = _serviceSlots.firstWhere((slot) => slot['id'] == _selectedServiceSlotId);
              final startTimeStr = selectedSlot['startTime'] as String;
              final endTimeStr = selectedSlot['endTime'] as String;
              
              // Parse time strings (format: "HH:mm:ss")
              final startParts = startTimeStr.split(':');
              final endParts = endTimeStr.split(':');
              
              startTime = TimeOfDay(
                hour: int.parse(startParts[0]),
                minute: int.parse(startParts[1]),
              );
              endTime = TimeOfDay(
                hour: int.parse(endParts[0]),
                minute: int.parse(endParts[1]),
              );
            } else if (_selectedTimeSlot != null) {
              // Dùng time slot động
              final startTimeStr = _selectedTimeSlot!['startTime'] as String;
              final endTimeStr = _selectedTimeSlot!['endTime'] as String;
              
              // Parse time strings (format: "HH:mm:ss")
              final startParts = startTimeStr.split(':');
              final endParts = endTimeStr.split(':');
              
              startTime = TimeOfDay(
                hour: int.parse(startParts[0]),
                minute: int.parse(startParts[1]),
              );
              endTime = TimeOfDay(
                hour: int.parse(endParts[0]),
                minute: int.parse(endParts[1]),
              );
            } else {
              // Fallback
              startTime = const TimeOfDay(hour: 9, minute: 0);
              endTime = const TimeOfDay(hour: 17, minute: 0);
            }
          } else {
            // COMBO_BASED, TICKET_BASED: Set default time
            startTime = const TimeOfDay(hour: 9, minute: 0);
            endTime = const TimeOfDay(hour: 17, minute: 0);
          }
          
          // Xác định serviceId để dùng
          int serviceIdToUse = widget.serviceId;
          if (serviceIdToUse == 0 && _selectedZoneId != null) {
            serviceIdToUse = _selectedZoneId!;
          }
          
          // Build selected options for OPTION_BASED services
          List<Map<String, dynamic>>? selectedOptions;
          List<Map<String, dynamic>>? selectedOptionsDetails;
          if (_serviceType == 'OPTION_BASED' && _selectedOptions.isNotEmpty) {
            selectedOptions = _selectedOptions.entries.map((entry) {
              final option = _options.firstWhere((opt) => opt['id'] == entry.key);
              return {
                'itemId': entry.key,
                'itemCode': option['code'] as String? ?? '',
                'quantity': entry.value,
              };
            }).toList();
            
            selectedOptionsDetails = _selectedOptions.entries.map((entry) {
              final option = _options.firstWhere((opt) => opt['id'] == entry.key);
              return {
                'name': option['name'] as String? ?? '',
                'price': option['price'] as num? ?? 0,
                'quantity': entry.value,
              };
            }).toList();
          }
          
          // Tính giá ước tính để hiển thị
          num estimatedTotalAmount = 0;
          Map<String, dynamic>? selectedCombo;
          Map<String, dynamic>? selectedTicket;
          
          if (_serviceType == 'COMBO_BASED' && _selectedComboId != null) {
            selectedCombo = _combos.firstWhere((c) => c['id'] == _selectedComboId);
            final comboPrice = selectedCombo['price'] as num? ?? 0;
            // Giá = combo price * số người
            estimatedTotalAmount = comboPrice * _numberOfPeople;
          } else if (_serviceType == 'TICKET_BASED' && _selectedTicketId != null) {
            selectedTicket = _tickets.firstWhere((t) => t['id'] == _selectedTicketId);
            final ticketPrice = selectedTicket['price'] as num? ?? 0;
            // Tất cả ticket-based: giá = vé * số người
            estimatedTotalAmount = ticketPrice * _numberOfPeople;
          } else if (_serviceType == 'OPTION_BASED') {
            // Tính base price
            final pricePerHour = _serviceDetail?['pricePerHour'] as num? ?? 0;
            final startMinutes = startTime.hour * 60 + startTime.minute;
            final endMinutes = endTime.hour * 60 + endTime.minute;
            final hours = (endMinutes - startMinutes) / 60.0;
            estimatedTotalAmount = pricePerHour * hours;
            
            // Thêm options
            if (selectedOptionsDetails != null) {
              for (var opt in selectedOptionsDetails) {
                estimatedTotalAmount += (opt['price'] as num? ?? 0) * (opt['quantity'] as num? ?? 1);
              }
            }
            
            // Thêm extra hours
            if (_extraHours > 0) {
              estimatedTotalAmount += 100000 * _extraHours;
            }
          }
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ServiceDetailScreen(
                zoneId: serviceIdToUse,
                serviceId: serviceIdToUse,
                selectedDate: _selectedDate!,
                startTime: startTime,
                endTime: endTime,
                numberOfPeople: _numberOfPeople,
                purpose: _purposeController.text,
                categoryCode: widget.categoryCode,
                selectedOptions: selectedOptions,
                selectedComboId: _selectedComboId,
                selectedTicketId: _selectedTicketId,
                selectedServiceSlotId: _selectedServiceSlotId,
                extraHours: _extraHours > 0 ? _extraHours : null,
                estimatedTotalAmount: estimatedTotalAmount,
                selectedCombo: selectedCombo,
                selectedTicket: selectedTicket,
                selectedOptionsDetails: selectedOptionsDetails,
              ),
            ),
          );
        } : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF26A69A),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          'Tiếp tục đặt chỗ',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
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
}
