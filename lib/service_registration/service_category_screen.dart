import 'package:flutter/material.dart';
import 'service_list_screen.dart';
import 'service_booking_service.dart';
import '../register/register_vehicle_screen.dart';
import '../register/register_resident_card_screen.dart';
import '../register/register_elevator_card_screen.dart';
import '../auth/api_client.dart';

class ServiceCategoryScreen extends StatefulWidget {
  const ServiceCategoryScreen({super.key});

  @override
  State<ServiceCategoryScreen> createState() => _ServiceCategoryScreenState();
}

class _ServiceCategoryScreenState extends State<ServiceCategoryScreen> {
  final ApiClient _apiClient = ApiClient();
  late final ServiceBookingService _serviceBookingService;
  
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serviceBookingService = ServiceBookingService(_apiClient.dio);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final categories = await _serviceBookingService.getAllCategories();
      
      setState(() {
        _categories = categories;
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
            content: Text('Lỗi tải danh sách loại dịch vụ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Map icon string từ database sang IconData
  IconData _getIconData(String? iconName) {
    if (iconName == null || iconName.isEmpty) {
      return Icons.category;
    }
    
    // Map icon names từ database sang Flutter icons
    switch (iconName.toLowerCase()) {
      case 'entertainment':
      case 'sports_esports':
        return Icons.sports_esports;
      case 'rental':
      case 'store':
        return Icons.store;
      case 'technical':
      case 'build':
        return Icons.build;
      case 'operation':
      case 'local_parking':
        return Icons.local_parking;
      default:
        return Icons.category;
    }
  }

  // Map icon string từ database sang Color
  Color _getIconColor(String? iconName) {
    if (iconName == null || iconName.isEmpty) {
      return Colors.teal;
    }
    
    switch (iconName.toLowerCase()) {
      case 'entertainment':
      case 'sports_esports':
        return Colors.orange;
      case 'rental':
      case 'store':
        return Colors.blue;
      case 'technical':
      case 'build':
        return Colors.grey;
      case 'operation':
      case 'local_parking':
        return Colors.teal;
      default:
        return Colors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: const Text(
          'Đăng ký dịch vụ',
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
                        onPressed: _loadCategories,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : _categories.isEmpty
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
                            'Chưa có loại dịch vụ nào',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadCategories,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _categories.length,
                        itemBuilder: (context, index) {
                          final category = _categories[index];
                          return _buildCategoryCard(category);
                        },
                      ),
                    ),
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
    final iconName = category['icon'] as String?;
    final iconData = _getIconData(iconName);
    final iconColor = _getIconColor(iconName);
    
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
          onTap: () => _onCategoryTap(category),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    iconData,
                    color: iconColor,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category['name'] as String? ?? 'Dịch vụ',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      if (category['description'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          category['description'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onCategoryTap(Map<String, dynamic> category) {
    final code = category['code'] as String;
    
    // Nếu là OPERATION, hiển thị dialog để chọn dịch vụ
    if (code == 'OPERATION') {
      _showOperationServicesDialog();
    } else {
      // Navigate đến service list screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceListScreen(categoryCode: code),
        ),
      );
    }
  }

  void _showOperationServicesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chọn dịch vụ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.directions_car, color: Colors.teal),
              title: const Text('Đăng ký thẻ xe'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RegisterVehicleScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.badge, color: Colors.teal),
              title: const Text('Đăng ký thẻ cư dân'),
              subtitle: const Text('Dịch vụ ra vào'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RegisterResidentCardScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.elevator, color: Colors.teal),
              title: const Text('Đăng ký thẻ thang máy'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RegisterElevatorCardScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
        ],
      ),
    );
  }
}

