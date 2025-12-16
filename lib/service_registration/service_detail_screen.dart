import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/asset_maintenance_api_client.dart';
import '../theme/app_colors.dart';
import 'service_booking_screen.dart';
import 'service_booking_service.dart';

class ServiceDetailScreen extends StatefulWidget {
  final String serviceId;
  final String serviceName;
  final String categoryCode;
  final String? categoryName;

  const ServiceDetailScreen({
    super.key,
    required this.serviceId,
    required this.serviceName,
    required this.categoryCode,
    this.categoryName,
  });

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  late final ServiceBookingService _bookingService;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _service;

  @override
  void initState() {
    super.initState();
    _bookingService = ServiceBookingService(AssetMaintenanceApiClient());
    _loadService();
  }

  Future<void> _loadService() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await _bookingService.getServiceDetail(widget.serviceId);
      setState(() {
        _service = detail;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _bookingTypeLabel(String? bookingType) {
    switch (bookingType?.toUpperCase()) {
      case 'COMBO_BASED':
        return 'Đặt theo combo';
      case 'TICKET_BASED':
        return 'Đặt theo vé';
      case 'OPTION_BASED':
        return 'Tùy chọn linh hoạt';
      default:
        return 'Giá theo giờ';
    }
  }

  IconData _getServiceIcon(String? bookingType) {
    switch (bookingType?.toUpperCase()) {
      case 'COMBO_BASED':
        return CupertinoIcons.square_grid_2x2_fill;
      case 'TICKET_BASED':
        return CupertinoIcons.ticket_fill;
      case 'OPTION_BASED':
        return CupertinoIcons.list_bullet;
      default:
        return CupertinoIcons.clock_fill;
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
              Color(0xFF04101F),
              Color(0xFF0A1D34),
              Color(0xFF071225),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEFF6FF),
              Color(0xFFF8FBFF),
              Colors.white,
            ],
          );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: colorScheme.onSurface,
              elevation: 0,
              scrolledUnderElevation: 0,
              pinned: true,
              stretch: true,
              leadingWidth: 66,
              expandedHeight: widget.categoryName != null ? 180 : 120,
              systemOverlayStyle: theme.appBarTheme.systemOverlayStyle,
              title: Text(
                widget.categoryName ?? 'Chi tiết dịch vụ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              centerTitle: true,
              leading: Padding(
                padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
                child: _buildFrostedIconButton(
                  icon: CupertinoIcons.chevron_left,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: Container(
                  decoration: BoxDecoration(gradient: backgroundGradient),
                  padding: const EdgeInsets.fromLTRB(24, 80, 24, 20),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.serviceName,
                          style: theme.textTheme.titleLarge?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ) ??
                              TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!_loading && _error == null && _service != null)
              SliverToBoxAdapter(
                child: _buildHeaderBanner(theme, colorScheme, isDark),
              ),
            SliverToBoxAdapter(
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(48.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _error ?? 'Đã xảy ra lỗi',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _loadService,
                                  child: const Text('Thử lại'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _service == null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Không tìm thấy thông tin dịch vụ',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                              child: _glassPanel(
                                child: _buildServiceInfo(),
                              ),
                            ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _loading || _error != null || _service == null
          ? null
          : Builder(
              builder: (context) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: backgroundGradient,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ServiceBookingScreen(
                                serviceId: widget.serviceId,
                                serviceName: widget.serviceName,
                                categoryCode: widget.categoryCode,
                                categoryName: widget.categoryName,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(
                          CupertinoIcons.calendar_badge_plus,
                          size: 20,
                        ),
                        label: const Text(
                          'Đặt dịch vụ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _glassPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(24),
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gradient = isDark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();
    final borderColor = (isDark ? AppColors.navyOutline : AppColors.neutralOutline)
        .withValues(alpha: 0.45);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner(ThemeData theme, ColorScheme colorScheme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  colorScheme.primary.withValues(alpha: 0.3),
                  colorScheme.primary.withValues(alpha: 0.2),
                ]
              : [
                  colorScheme.primary.withValues(alpha: 0.15),
                  colorScheme.primary.withValues(alpha: 0.08),
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chọn khung giờ phù hợp và gửi yêu cầu để ban quản lý chuẩn bị cho bạn.',
            style: theme.textTheme.bodyLarge?.copyWith(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.9)
                      : colorScheme.onSurface.withValues(alpha: 0.85),
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ) ??
                TextStyle(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.9)
                      : colorScheme.onSurface.withValues(alpha: 0.85),
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildFeatureBadge(
                theme,
                colorScheme,
                isDark,
                CupertinoIcons.calendar,
                'Đặt lịch linh hoạt',
              ),
              _buildFeatureBadge(
                theme,
                colorScheme,
                isDark,
                CupertinoIcons.creditcard,
                'Thanh toán tiện lợi',
              ),
              _buildFeatureBadge(
                theme,
                colorScheme,
                isDark,
                CupertinoIcons.bell,
                'Nhắc nhở tự động',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBadge(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
    IconData icon,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.9)
                      : colorScheme.onSurface.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ) ??
                TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.9)
                      : colorScheme.onSurface.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceInfo() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final service = _service!;

    final description = service['description']?.toString();
    final location = service['location']?.toString();
    final rules = service['rules']?.toString();
    final bookingType = service['bookingType']?.toString() ?? 'STANDARD';
    final pricingType = service['pricingType']?.toString() ?? 'HOURLY';
    final maxCapacity = service['maxCapacity'];
    final minDurationHours = service['minDurationHours'];
    final availabilities = _parseList(service['availabilities']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Service Icon & Name
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 
                  isDark ? 0.28 : 0.26,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                _getServiceIcon(bookingType),
                color: colorScheme.primary,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.serviceName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ) ??
                        TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 
                            isDark ? 0.28 : 0.16,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 
                              isDark ? 0.6 : 0.4,
                            ),
                          ),
                        ),
                        child: Text(
                          _bookingTypeLabel(bookingType),
                          style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ) ??
                              TextStyle(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                                fontSize: 11,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        // Tickets Section - Chỉ hiển thị tickets, bỏ pricingType và pricePerHour
        const SizedBox(height: 24),
        _buildTicketsSection(service, theme, colorScheme, isDark),

        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Mô tả',
            style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ) ??
                TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.82)
                      : AppColors.textPrimary,
                ) ??
                TextStyle(
                  height: 1.6,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.82)
                      : AppColors.textPrimary,
                ),
          ),
        ],

        // Service Details
        const SizedBox(height: 28),
        Text(
          'Thông tin chi tiết',
          style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ) ??
              TextStyle(
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
                fontSize: 18,
              ),
        ),
        const SizedBox(height: 18),
        _buildDetailRow(
          icon: CupertinoIcons.location_fill,
          label: 'Địa điểm',
          value: location ?? 'Chưa có thông tin',
        ),
        if (maxCapacity != null) ...[
          const SizedBox(height: 18),
          _buildDetailRow(
            icon: CupertinoIcons.person_3_fill,
            label: 'Sức chứa',
            value: '$maxCapacity người',
          ),
        ],
        if (minDurationHours != null) ...[
          const SizedBox(height: 18),
          _buildDetailRow(
            icon: CupertinoIcons.timer_fill,
            label: 'Thời lượng tối thiểu',
            value: '${minDurationHours.toString()} giờ',
          ),
        ],
        if (availabilities.isNotEmpty) ...[
          const SizedBox(height: 18),
          _buildAvailabilitySection(availabilities, theme, colorScheme, isDark),
        ],
        if (rules != null && rules.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Quy định',
            style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ) ??
                TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            rules,
            style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.75)
                      : AppColors.textSecondary,
                ) ??
                TextStyle(
                  height: 1.6,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.75)
                      : AppColors.textSecondary,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                      color: isDark
                          ? Colors.white70
                          : AppColors.textSecondary,
                      fontSize: 13,
                    ) ??
                    TextStyle(
                      color: isDark ? Colors.white70 : AppColors.textSecondary,
                      fontSize: 13,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                      fontSize: 16,
                    ) ??
                    TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                      fontSize: 16,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFrostedIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.75),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                icon,
                size: 20,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTicketsSection(
    Map<String, dynamic> service,
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final NumberFormat currencyFormatter =
        NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
    
    // Chỉ hiển thị Tickets - bỏ pricingType và pricePerHour
    final tickets = _parseList(service['tickets']);
    if (tickets.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildPriceListSection(
      theme,
      colorScheme,
      isDark,
      'Loại Vé',
      CupertinoIcons.ticket,
      tickets,
      currencyFormatter,
    );
  }

  Widget _buildPriceCard(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
    String text,
    IconData icon,
    Color iconColor, {
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isHighlight
            ? iconColor.withValues(alpha: isDark ? 0.25 : 0.15)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlight
              ? iconColor.withValues(alpha: 0.4)
              : colorScheme.outline.withValues(alpha: 0.1),
          width: isHighlight ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleLarge?.copyWith(
                    color: isHighlight
                        ? iconColor
                        : (isDark ? Colors.white : AppColors.textPrimary),
                    fontWeight: FontWeight.w700,
                  ) ??
                  TextStyle(
                    fontSize: 18,
                    color: isHighlight
                        ? iconColor
                        : (isDark ? Colors.white : AppColors.textPrimary),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceListSection(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
    String title,
    IconData icon,
    List<Map<String, dynamic>> items,
    NumberFormat currencyFormatter,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ) ??
                    TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                      fontSize: 14,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final name = item['name']?.toString() ?? 'N/A';
            final price = item['price'] as num?;
            final description = item['description']?.toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : AppColors.textPrimary,
                              ) ??
                              TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : AppColors.textPrimary,
                              ),
                        ),
                        if (description != null && description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark
                                      ? Colors.white70
                                      : AppColors.textSecondary,
                                ) ??
                                TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (price != null && price > 0)
                    Text(
                      currencyFormatter.format(price),
                      style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ) ??
                          TextStyle(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                            fontSize: 16,
                          ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAvailabilitySection(
    List<Map<String, dynamic>> availabilities,
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final dayFullNames = [
      'Chủ nhật',
      'Thứ 2',
      'Thứ 3',
      'Thứ 4',
      'Thứ 5',
      'Thứ 6',
      'Thứ 7'
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              CupertinoIcons.calendar,
              size: 20,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Khung giờ hoạt động',
              style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ) ??
                  TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                    fontSize: 14,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: availabilities.map((avail) {
            final dayOfWeek = avail['dayOfWeek'] as int?;
            final startTime = avail['startTime']?.toString() ?? '';
            final endTime = avail['endTime']?.toString() ?? '';
            final isAvailable = avail['isAvailable'] as bool? ?? true;

            if (dayOfWeek == null || !isAvailable) {
              return const SizedBox.shrink();
            }

            final dayFullName = dayOfWeek >= 1 && dayOfWeek <= 7
                ? dayFullNames[dayOfWeek - 1]
                : 'N/A';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dayFullName,
                    style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ) ??
                        TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                          fontSize: 12,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatTime(startTime)} - ${_formatTime(endTime)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? Colors.white70 : AppColors.textSecondary,
                        ) ??
                        TextStyle(
                          color: isDark ? Colors.white70 : AppColors.textSecondary,
                          fontSize: 12,
                        ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _formatTime(String timeStr) {
    if (timeStr.isEmpty) return '';
    final parts = timeStr.split(':');
    if (parts.length >= 2) {
      return '${parts[0]}:${parts[1]}';
    }
    return timeStr;
  }

  List<Map<String, dynamic>> _parseList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const [];
  }
}

