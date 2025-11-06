import 'package:flutter/material.dart';
import 'service_booking_screen.dart';
import 'service_booking_service.dart';
import '../auth/api_client.dart';

class ServiceListScreen extends StatefulWidget {
  final String categoryCode;
  
  const ServiceListScreen({
    super.key,
    required this.categoryCode,
  });

  @override
  State<ServiceListScreen> createState() => _ServiceListScreenState();
}

class _ServiceListScreenState extends State<ServiceListScreen> {
  final ApiClient _apiClient = ApiClient();
  late final ServiceBookingService _serviceBookingService;
  
  List<Map<String, dynamic>> _services = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serviceBookingService = ServiceBookingService(_apiClient.dio);
    _loadServices();
  }

  Future<void> _loadServices() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Lấy danh sách services từ category
      final services = await _serviceBookingService.getServicesByCategoryCode(
        widget.categoryCode,
      );
      
      setState(() {
        _services = services;
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
        title: const Text(
          'Danh sách dịch vụ',
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
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _services.length,
                        itemBuilder: (context, index) {
                          final service = _services[index];
                          return _buildServiceCard(service);
                        },
                      ),
                    ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Navigate đến booking screen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceBookingScreen(
                  serviceId: service['id'] as int,
                  serviceName: service['name'] as String? ?? 'Dịch vụ',
                  categoryCode: widget.categoryCode,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    service['name'] as String? ?? 'Dịch vụ',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

