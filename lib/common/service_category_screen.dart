import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shimmer/shimmer.dart';

import '../auth/asset_maintenance_api_client.dart';
import '../feedback/feedback_screen.dart';
import '../register/register_elevator_card_screen.dart';
import '../register/register_resident_card_screen.dart';
import '../register/register_vehicle_screen.dart';
import '../theme/app_colors.dart';
import 'layout_insets.dart';
import '../service_registration/repair_request_screen.dart';
import '../service_registration/service_booking_service.dart';
import '../service_registration/service_list_screen.dart';

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

  late final List<_QuickAction> _cardServices = [
    _QuickAction(
      title: 'Đăng ký thẻ xe',
      description:
          'Tạo, theo dõi trạng thái và thanh toán thẻ gửi xe ngay trong ứng dụng.',
      icon: Icons.directions_car,
      color: const Color(0xFF26A69A),
      builder: (_) => const RegisterVehicleScreen(),
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

  late final List<_QuickAction> _maintenanceServices = [
    _QuickAction(
      title: 'Yêu cầu sửa chữa',
      description:
          'Gửi yêu cầu sửa chữa hoặc bảo trì, đính kèm hình ảnh/video minh chứng cho ban quản lý.',
      icon: Icons.build_circle_outlined,
      color: const Color(0xFF0097A7),
      builder: (_) => const RepairRequestScreen(),
    ),
    _QuickAction(
      title: 'Phản ánh cư dân',
      description:
          'Góp ý, khiếu nại hoặc yêu cầu hỗ trợ trực tiếp tới ban quản lý.',
      icon: Icons.support_agent_outlined,
      color: const Color(0xFFFFB74D),
      builder: (_) => const FeedbackScreen(),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final backgroundGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0B1728),
              Color(0xFF0F213A),
              Color(0xFF071117),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE7F3FF),
              Color(0xFFF5FAFF),
              Colors.white,
            ],
          );

    final bottomInset = LayoutInsets.bottomNavContentPadding(
      context,
      extra: -LayoutInsets.navBarHeight + 6,
      minimumGap: 16,
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Đăng ký dịch vụ'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: RefreshIndicator(
          color: colorScheme.primary,
          onRefresh: _loadCategories,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 28, 20, bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroCard(context),
                const SizedBox(height: 28),
                _buildDynamicCategories(context),
                const SizedBox(height: 28),
                _buildCardServices(context),
                const SizedBox(height: 28),
                _buildMaintenanceServices(context),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicCategories(BuildContext context) {
    if (_loadingCategories) {
      return _buildCategorySkeleton(context);
    }
    if (_categoryError != null) {
      final theme = Theme.of(context);
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tiện ích nội khu',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _categoryError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
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
        ..._buildCategoryRows(_categories),
      ],
    );
  }

  List<Widget> _buildCategoryRows(
    List<Map<String, dynamic>> categories,
  ) {
    final rows = <Widget>[];
    for (int i = 0; i < categories.length; i += 2) {
      final rowCategories = categories.skip(i).take(2).toList();
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _AmenityCard(
                  title: rowCategories[0]['name']?.toString() ?? 'Danh mục',
                  description: rowCategories[0]['description']?.toString(),
                  categoryCode: rowCategories[0]['code']?.toString() ?? '',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceListScreen(
                          categoryCode: rowCategories[0]['code']?.toString() ?? '',
                          categoryName: rowCategories[0]['name']?.toString() ?? 'Danh mục',
                        ),
                      ),
                    );
                  },
                  onLongPress: () {
                    _showIOSStylePopup(context, rowCategories[0]);
                  },
                ),
              ),
              if (rowCategories.length > 1) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _AmenityCard(
                    title: rowCategories[1]['name']?.toString() ?? 'Danh mục',
                    description: rowCategories[1]['description']?.toString(),
                    categoryCode: rowCategories[1]['code']?.toString() ?? '',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServiceListScreen(
                            categoryCode: rowCategories[1]['code']?.toString() ?? '',
                            categoryName: rowCategories[1]['name']?.toString() ?? 'Danh mục',
                          ),
                        ),
                      );
                    },
                    onLongPress: () {
                      _showIOSStylePopup(context, rowCategories[1]);
                    },
                  ),
                ),
              ] else
                const Expanded(child: SizedBox()),
            ],
          ),
        ),
      );
      if (i + 2 < categories.length) {
        rows.add(const SizedBox(height: 12));
      }
    }
    return rows;
  }

  void _showIOSStylePopup(BuildContext context, Map<String, dynamic> category) {
    final name = category['name']?.toString() ?? 'Danh mục';
    final description = category['description']?.toString() ?? '';
    final code = category['code']?.toString() ?? '';

    final overlayState = Overlay.of(context);

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _IOSStyleServicePopup(
        name: name,
        description: description,
        categoryCode: code,
        onClose: () => overlayEntry.remove(),
        onOpen: () {
          overlayEntry.remove();
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
        onDetails: () {
          overlayEntry.remove();
          _showCategoryDetail(context, category);
        },
      ),
    );

    overlayState.insert(overlayEntry);
  }

  void _showCategoryDetail(BuildContext context, Map<String, dynamic> category) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    final name = category['name']?.toString() ?? 'Danh mục';
    final description = category['description']?.toString() ?? '';
    final code = category['code']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: isDark
              ? AppColors.darkGlassLayerGradient()
              : AppColors.glassLayerGradient(),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 64,
                      width: 64,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 
                          isDark ? 0.24 : 0.32,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.event_available,
                        color: colorScheme.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Mô tả',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.8),
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
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
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Xem danh sách dịch vụ'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
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

  Widget _buildCardServices(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dịch vụ thẻ cư dân',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ..._cardServices.map(
          (action) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _QuickActionCard(data: action),
          ),
        ),
      ],
    );
  }

  Widget _buildMaintenanceServices(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dịch vụ đồ đạc',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ..._maintenanceServices.map(
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
    final isDark = theme.brightness == Brightness.dark;
    final gradient = isDark
        ? const LinearGradient(
            colors: [Color(0xFF1D3A66), Color(0xFF0E2742)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : AppColors.primaryGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.elevatedShadow,
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
              color: Colors.white.withValues(alpha: 0.9),
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

  Widget _buildCategorySkeleton(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
    final highlight = theme.colorScheme.surface.withValues(alpha: 0.7);
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
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
                  color: theme.cardColor,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
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
    this.categoryCode,
    required this.onPressed,
    this.onLongPress,
  });

  final String title;
  final String? description;
  final String? categoryCode;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppColors.darkGlassLayerGradient()
                  : AppColors.glassLayerGradient(),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.08),
              ),
              boxShadow: AppColors.subtleShadow,
            ),
             child: Padding(
               padding: const EdgeInsets.all(18),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Container(
                     height: 46,
                     width: 46,
                     decoration: BoxDecoration(
                       color: colorScheme.primaryContainer.withValues(alpha: 
                         isDark ? 0.24 : 0.32,
                       ),
                       borderRadius: BorderRadius.circular(14),
                     ),
                     child: Icon(
                       Icons.event_available,
                       color: colorScheme.primary,
                     ),
                   ),
                   const SizedBox(height: 14),
                   Text(
                     title,
                     style: theme.textTheme.titleMedium?.copyWith(
                       fontWeight: FontWeight.w700,
                     ),
                     maxLines: 2,
                     overflow: TextOverflow.ellipsis,
                   ),
                   if (description != null && description!.isNotEmpty) ...[
                     const SizedBox(height: 6),
                     Text(
                       description!,
                       maxLines: 3,
                       overflow: TextOverflow.ellipsis,
                       style: theme.textTheme.bodySmall?.copyWith(
                         color: colorScheme.onSurface.withValues(alpha: 0.64),
                         height: 1.38,
                       ),
                     ),
                   ],
                   const Spacer(),
                   Row(
                     mainAxisAlignment: MainAxisAlignment.end,
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       Flexible(
                         child: Text(
                           'Đặt ngay',
                           style: theme.textTheme.labelLarge?.copyWith(
                             color: colorScheme.primary,
                             fontWeight: FontWeight.w600,
                           ),
                           overflow: TextOverflow.ellipsis,
                         ),
                       ),
                       const SizedBox(width: 6),
                       Icon(Icons.arrow_forward_rounded,
                           color: colorScheme.primary, size: 18),
                     ],
                   ),
                 ],
               ),
             ),
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
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: data.builder),
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppColors.darkGlassLayerGradient()
                : AppColors.glassLayerGradient(),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.08),
            ),
            boxShadow: AppColors.subtleShadow,
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
                        color: data.color.withValues(alpha: isDark ? 0.22 : 0.18),
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
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Thao tác ngay',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: data.color,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, color: data.color, size: 18),
                  ],
                ),
              ],
            ),
          ),
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

class _IOSStyleServicePopup extends StatefulWidget {
  const _IOSStyleServicePopup({
    required this.name,
    required this.description,
    required this.categoryCode,
    required this.onClose,
    required this.onOpen,
    required this.onDetails,
  });

  final String name;
  final String description;
  final String categoryCode;
  final VoidCallback onClose;
  final VoidCallback onOpen;
  final VoidCallback onDetails;

  @override
  State<_IOSStyleServicePopup> createState() => _IOSStyleServicePopupState();
}

class _IOSStyleServicePopupState extends State<_IOSStyleServicePopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _backdropFadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _backdropFadeAnimation = Tween<double>(begin: 0.0, end: 0.4).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleClose() async {
    await _controller.reverse();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: _handleClose,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              children: [
                // Backdrop với blur
                Positioned.fill(
                  child: Opacity(
                    opacity: _backdropFadeAnimation.value,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.6)
                            : Colors.black.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                // Popup content
                Center(
                  child: Opacity(
                    opacity: _fadeAnimation.value,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: GestureDetector(
                        onTap: () {}, // Prevent tap through
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          constraints: BoxConstraints(
                            maxWidth: 320,
                            maxHeight: screenSize.height * 0.5,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1C1C1E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 30,
                                spreadRadius: 5,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Icon section
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 32,
                                  left: 24,
                                  right: 24,
                                ),
                                child: Container(
                                  height: 80,
                                  width: 80,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient(),
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorScheme.primary
                                            .withValues(alpha: 0.3),
                                        blurRadius: 15,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.event_available,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              // Title
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Text(
                                  widget.name,
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Description
                              if (widget.description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Text(
                                    widget.description,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurface
                                          .withValues(alpha: 0.7),
                                      height: 1.4,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              const SizedBox(height: 32),
                              // Action buttons
                              Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: colorScheme.outline
                                          .withValues(alpha: 0.1),
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    _IOSActionButton(
                                      label: 'Mở',
                                      icon: CupertinoIcons.arrow_right_circle_fill,
                                      onTap: widget.onOpen,
                                      isPrimary: true,
                                    ),
                                    Container(
                                      height: 0.5,
                                      color: colorScheme.outline
                                          .withValues(alpha: 0.1),
                                    ),
                                    _IOSActionButton(
                                      label: 'Chi tiết',
                                      icon: CupertinoIcons.info_circle_fill,
                                      onTap: widget.onDetails,
                                      isPrimary: false,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IOSActionButton extends StatelessWidget {
  const _IOSActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isPrimary,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isPrimary
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.7),
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isPrimary
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.7),
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

