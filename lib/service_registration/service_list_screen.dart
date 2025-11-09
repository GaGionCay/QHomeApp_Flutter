import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/asset_maintenance_api_client.dart';
import 'service_booking_screen.dart';
import 'service_booking_service.dart';

class ServiceListScreen extends StatefulWidget {
  final String categoryCode;
  final String? categoryName;

  const ServiceListScreen({
    super.key,
    required this.categoryCode,
    this.categoryName,
  });

  @override
  State<ServiceListScreen> createState() => _ServiceListScreenState();
}

class _ServiceListScreenState extends State<ServiceListScreen> {
  late final ServiceBookingService _serviceBookingService;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _filteredServices = const [];
  bool _loading = true;
  String? _error;
  final NumberFormat _currencyFormatter =
      NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  @override
  void initState() {
    super.initState();
    _serviceBookingService = ServiceBookingService(AssetMaintenanceApiClient());
    _searchController.addListener(_onSearchChanged);
    _loadServices();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final services = await _serviceBookingService.getServicesByCategory(widget.categoryCode);

      final filtered = _filterServices(services, _searchController.text);
      setState(() {
        _services = services;
        _filteredServices = filtered;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tải danh sách dịch vụ: $e'),
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
          widget.categoryName ?? 'Danh sách dịch vụ',
          style: const TextStyle(
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
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Lỗi: $_error',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadServices,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : _services.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Chưa có dịch vụ nào',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadServices,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildHeaderCard(context),
                          const SizedBox(height: 20),
                          _buildSearchField(context),
                          const SizedBox(height: 16),
                          if (_filteredServices.isEmpty)
                            _buildEmptyFilterState(context)
                          else
                            ..._filteredServices.map(_buildServiceCard),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final bookingType = (service['bookingType'] as String?) ?? 'STANDARD';
    final pricingType = (service['pricingType'] as String?) ?? 'HOURLY';
    final priceText = _buildPriceText(service, pricingType);
    final capacity = service['maxCapacity'];
    final durationMin = service['minDurationHours'];
    final location = service['location']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ServiceBookingScreen(
                serviceId: service['id'].toString(),
                serviceName: service['name'] as String? ?? 'Dịch vụ',
                categoryCode: widget.categoryCode,
                categoryName: widget.categoryName,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'] as String? ?? 'Dịch vụ',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          priceText,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: const Color(0xFF00695C),
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  _buildBookingTypeChip(bookingType),
                ],
              ),
              const SizedBox(height: 12),
              if (service['description'] != null &&
                  (service['description'] as String).isNotEmpty)
                Text(
                  service['description'] as String,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                ),
              if (location != null && location.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        location,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (capacity != null)
                    _InfoChip(
                      icon: Icons.people_alt_outlined,
                      label: 'Tối đa $capacity người',
                    ),
                  if (durationMin != null)
                    _InfoChip(
                      icon: Icons.schedule_outlined,
                      label: 'Tối thiểu ${durationMin.toString()} giờ',
                    ),
                  if (service['advanceBookingDays'] != null)
                    _InfoChip(
                      icon: Icons.calendar_month_outlined,
                      label:
                          'Đặt trước ${service['advanceBookingDays'].toString()} ngày',
                    ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF26A69A),
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF26A69A), Color(0xFF2BBBAD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.categoryName ?? 'Tiện ích',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Chọn khung giờ phù hợp và gửi yêu cầu để ban quản lý chuẩn bị trước cho bạn.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: 'Tìm theo tên dịch vụ hoặc mô tả...',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildEmptyFilterState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Không tìm thấy dịch vụ phù hợp',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Thử đổi từ khóa khác hoặc xem các dịch vụ bên dưới.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingTypeChip(String bookingType) {
    final label = _bookingTypeLabel(bookingType);
    final color = _bookingTypeColor(bookingType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  String _bookingTypeLabel(String bookingType) {
    switch (bookingType) {
      case 'COMBO_BASED':
        return 'Combo ưu đãi';
      case 'TICKET_BASED':
        return 'Theo lượt/Vé';
      case 'OPTION_BASED':
        return 'Tùy chọn linh hoạt';
      default:
        return 'Đặt theo giờ';
    }
  }

  Color _bookingTypeColor(String bookingType) {
    switch (bookingType) {
      case 'COMBO_BASED':
        return const Color(0xFF8E24AA);
      case 'TICKET_BASED':
        return const Color(0xFF3949AB);
      case 'OPTION_BASED':
        return const Color(0xFF00796B);
      default:
        return const Color(0xFF006064);
    }
  }

  String _buildPriceText(Map<String, dynamic> service, String pricingType) {
    if (pricingType == 'FREE') {
      return 'Miễn phí cho cư dân';
    }
    final pricePerSession = service['pricePerSession'] as num?;
    final pricePerHour = service['pricePerHour'] as num?;
    if (pricingType == 'SESSION' && pricePerSession != null) {
      return '${_currencyFormatter.format(pricePerSession)} / lượt';
    }
    if (pricePerHour != null && pricePerHour > 0) {
      return '${_currencyFormatter.format(pricePerHour)} / giờ';
    }
    return 'Liên hệ ban quản lý';
  }

  void _onSearchChanged() {
    final filtered = _filterServices(_services, _searchController.text);
    setState(() {
      _filteredServices = filtered;
    });
  }

  List<Map<String, dynamic>> _filterServices(
    List<Map<String, dynamic>> source,
    String query,
  ) {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) {
      return List<Map<String, dynamic>>.from(source);
    }
    return source.where((service) {
      final name = service['name']?.toString().toLowerCase() ?? '';
      final description = service['description']?.toString().toLowerCase() ?? '';
      final location = service['location']?.toString().toLowerCase() ?? '';
      return name.contains(term) ||
          description.contains(term) ||
          location.contains(term);
    }).toList();
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.grey.shade700,
                ),
          ),
        ],
      ),
    );
  }
}

