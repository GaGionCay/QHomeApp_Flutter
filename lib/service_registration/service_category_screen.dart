import 'package:flutter/material.dart';
import 'service_list_screen.dart';
import '../register/register_vehicle_screen.dart';
import '../register/register_resident_card_screen.dart';
import '../register/register_elevator_card_screen.dart';

class ServiceCategoryScreen extends StatefulWidget {
  const ServiceCategoryScreen({super.key});

  @override
  State<ServiceCategoryScreen> createState() => _ServiceCategoryScreenState();
}

class _ServiceCategoryScreenState extends State<ServiceCategoryScreen> {
  // Mock data - sẽ được thay bằng API call sau
  final List<Map<String, dynamic>> _categories = [
    {
      'code': 'ENTERTAINMENT',
      'name': 'Tiện ích giải trí',
      'description': 'BBQ, hồ bơi, sân chơi',
      'icon': Icons.sports_esports,
      'color': Colors.orange,
    },
    {
      'code': 'RENTAL',
      'name': 'Dịch vụ thuê mặt bằng',
      'description': 'Gian hàng lễ hội, sự kiện',
      'icon': Icons.store,
      'color': Colors.blue,
    },
    {
      'code': 'TECHNICAL',
      'name': 'Dịch vụ kỹ thuật',
      'description': 'Sửa điện nước, bảo trì',
      'icon': Icons.build,
      'color': Colors.grey,
    },
    {
      'code': 'OPERATION',
      'name': 'Dịch vụ vận hành',
      'description': 'Đăng ký xe, thẻ ra vào, chuyển nhượng',
      'icon': Icons.local_parking,
      'color': Colors.teal,
    },
  ];

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
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          return _buildCategoryCard(category);
        },
      ),
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
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
                    color: (category['color'] as Color).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    category['icon'] as IconData,
                    color: category['color'] as Color,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category['name'] as String,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        category['description'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
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

