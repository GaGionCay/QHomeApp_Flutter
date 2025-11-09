import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../auth/asset_maintenance_api_client.dart';
import '../register/register_elevator_card_screen.dart';
import '../register/register_resident_card_screen.dart';
import '../register/register_vehicle_screen.dart';
import 'cleaning_request_screen.dart';
import 'repair_request_screen.dart';
import 'service_booking_service.dart';
import 'service_list_screen.dart';

class ServiceCategoryScreen extends StatefulWidget {
  const ServiceCategoryScreen({super.key});

  @override
  State<ServiceCategoryScreen> createState() => _ServiceCategoryScreenState();
}

class _ServiceCategoryScreenState extends State<ServiceCategoryScreen> {
  late final ServiceBookingService _bookingService;
  final ScrollController _scrollController = ScrollController();

  bool _loadingCategories = true;
  String? _categoryError;
  List<Map<String, dynamic>> _categories = const [];

  late final List<_QuickAction> _quickActions = [
    _QuickAction(
      title: 'Đăng ký thẻ xe',
      description:
          'Tạo, theo dõi trạng thái và thanh toán thẻ gửi xe ngay trong ứng dụng.',
      icon: Icons.directions_car,
      color: const Color(0xFF26A69A),
      builder: (_) => const RegisterVehicleScreen(),
    ),
    _QuickAction(
      title: 'Yêu cầu dọn dẹp',
      description:
          'Đặt lịch dọn dẹp căn hộ, bổ sung dịch vụ tiện ích và theo dõi xử lý.',
      icon: Icons.cleaning_services_outlined,
      color: const Color(0xFF7CB342),
      builder: (_) => const CleaningRequestScreen(),
    ),
    _QuickAction(
      title: 'Yêu cầu sửa chữa',
      description:
          'Gửi phản ánh bảo trì, đính kèm hình ảnh/video minh chứng cho ban quản lý.',
      icon: Icons.build_circle_outlined,
      color: const Color(0xFF0097A7),
      builder: (_) => const RepairRequestScreen(),
    ),
    _QuickAction(
      title: 'Đăng ký thẻ cư dân',
      description:
          'Cấp thẻ cư dân cho gia đình, thanh toán trực tuyến và nhận kết quả nhanh.',
      icon: Icons.badge_outlined,
      color: const Color(0xFF00897B),
      builder: (_) => const RegisterResidentCardScreen(),
    ),
    _QuickAction(
      title: 'Đăng ký thẻ thang máy',
      description:
          'Kích hoạt thẻ thang máy cho cư dân và khách, đảm bảo ra vào an toàn.',
      icon: Icons.elevator,
      color: const Color(0xFF00796B),
      builder: (_) => const RegisterElevatorCardScreen(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _bookingService = ServiceBookingService(AssetMaintenanceApiClient());
    _loadCategories();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoryError = null;
    });
    try {
      final categories = await _bookingService.getActiveCategories();
      setState(() {
        _categories = categories;
        _loadingCategories = false;
      });
    } catch (e) {
      setState(() {
        _categoryError = e.toString();
        _loadingCategories = false;
      });
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
      body: RefreshIndicator(
        onRefresh: _loadCategories,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              _buildHeroCard(context),
              const SizedBox(height: 24),
              _buildDynamicCategories(),
              const SizedBox(height: 24),
              _buildStaticCards(context),
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.miscellaneous_services_outlined,
                      color: Colors.grey.shade400,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Các dịch vụ khác sẽ được cập nhật\ntrong các phiên bản tiếp theo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicCategories() {
    if (_loadingCategories) {
      return _buildCategorySkeleton();
    }
    if (_categoryError != null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tiện ích nội khu',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _categoryError!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadCategories,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (_categories.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Hiện chưa có tiện ích nào được cấu hình cho cư dân.'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final double cardWidth;
        if (width > 960) {
          cardWidth = (width - 48) / 3;
        } else if (width > 640) {
          cardWidth = (width - 36) / 2;
        } else {
          cardWidth = width;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tiện ích nội khu',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _categories.map((category) {
                final name = category['name']?.toString() ?? 'Danh mục';
                final code = category['code']?.toString() ?? '';
                final description = category['description']?.toString();
                return SizedBox(
                  width: cardWidth,
                  child: _AmenityCard(
                    title: name,
                    description: description,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServiceListScreen(
                            categoryCode: code,
                            categoryName: name,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStaticCards(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dịch vụ nhanh',
          style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        ..._quickActions.map(
          (action) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _QuickActionCard(data: action),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF26A69A), Color(0xFF00897B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF26A69A).withOpacity(0.25),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tiện ích cư dân',
            style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Đặt tiện ích thuận tiện, theo dõi trạng thái dịch vụ và thanh toán trực tuyến ngay trong ứng dụng.',
            style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: const [
              _HeroChip(label: 'Đặt tiện ích theo giờ'),
              _HeroChip(label: 'Quản lý yêu cầu sửa chữa'),
              _HeroChip(label: 'Thanh toán an toàn'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final double cardWidth;
          if (width > 960) {
            cardWidth = (width - 48) / 3;
          } else if (width > 640) {
            cardWidth = (width - 36) / 2;
          } else {
            cardWidth = width;
          }

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(
              4,
              (index) => Container(
                width: cardWidth,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AmenityCard extends StatelessWidget {
  const _AmenityCard({
    required this.title,
    this.description,
    required this.onPressed,
  });

  final String title;
  final String? description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.event_available,
                  color: Color(0xFF00695C),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (description != null && description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Đặt ngay',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF00695C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded,
                      color: Color(0xFF00695C)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.data});

  final _QuickAction data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: data.color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(data.icon, color: data.color, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    data.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              data.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: data.color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: data.builder),
                  );
                },
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Thao tác ngay'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.builder,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
}

