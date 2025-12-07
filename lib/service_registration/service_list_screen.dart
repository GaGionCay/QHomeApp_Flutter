import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/asset_maintenance_api_client.dart';
import '../theme/app_colors.dart';
import '../common/layout_insets.dart';
import 'service_booking_service.dart';
import 'service_detail_screen.dart';

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

  List<Map<String, dynamic>> _services = [];
  bool _loading = true;
  String? _error;
  final NumberFormat _currencyFormatter =
      NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  @override
  void initState() {
    super.initState();
    _serviceBookingService = ServiceBookingService(AssetMaintenanceApiClient());
    _loadServices();
  }

  Future<void> _loadServices() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final services = await _serviceBookingService
          .getServicesByCategory(widget.categoryCode);

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final double bottomInset = LayoutInsets.bottomNavContentPadding(
      context,
      extra: -LayoutInsets.navBarHeight + 6,
      minimumGap: 16,
    );

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

    return Scaffold(
      extendBody: true,
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.categoryName ?? 'Danh sách dịch vụ'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildErrorState(theme)
                : _services.isEmpty
                    ? _buildEmptyState(theme)
                    : RefreshIndicator(
                        color: colorScheme.primary,
                        onRefresh: _loadServices,
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(20, 24, 20, bottomInset),
                          children: [
                            _buildHeaderCard(context),
                            const SizedBox(height: 24),
                            if (_services.isEmpty)
                              _buildEmptyState(theme)
                            else
                              ..._services.map(
                                (service) => Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: _ServiceGlassCard(
                                    child: _buildServiceCard(service),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final bookingType = (service['bookingType'] as String?) ?? 'STANDARD';
    final pricingType = (service['pricingType'] as String?) ?? 'HOURLY';
    final capacity = service['maxCapacity'];
    final durationMin = service['minDurationHours'];
    final location = service['location']?.toString();
    final description = service['description']?.toString();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceDetailScreen(
              serviceId: service['id'].toString(),
              serviceName: service['name'] as String? ?? 'Dịch vụ',
              categoryCode: widget.categoryCode,
              categoryName: widget.categoryName,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 58,
                  width: 58,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.26),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    _iconForService(service),
                    color: colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service['name'] as String? ?? 'Dịch vụ',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildBookingTypeChip(bookingType),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPriceSection(service, pricingType, theme, colorScheme),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  height: 1.46,
                ),
              ),
            ],
            if (location != null && location.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    CupertinoIcons.map_pin_ellipse,
                    size: 18,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      location,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (capacity != null)
                  _buildInfoChip(
                    context: context,
                    label: 'Sức chứa',
                    value: '$capacity người',
                    icon: CupertinoIcons.person_3_fill,
                  ),
                if (durationMin != null)
                  _buildInfoChip(
                    context: context,
                    label: 'Thời lượng tối thiểu',
                    value: '${durationMin.toString()} giờ',
                    icon: CupertinoIcons.timer,
                  ),
                // Note: advanceBookingDays field was removed from backend
                // Service booking is available up to 30 days in advance by default
              ],
            ),
            const SizedBox(height: 20),
            _buildActionRow(context, service),
          ],
        ),
      ),
    );
  }

  IconData _iconForService(Map<String, dynamic> service) {
    final name = (service['name'] as String?)?.toLowerCase() ?? '';
    if (name.contains('spa') || name.contains('wellness')) {
      return CupertinoIcons.sparkles;
    }
    if (name.contains('gym') || name.contains('fitness')) {
      return CupertinoIcons.heart_circle;
    }
    if (name.contains('hồ bơi') || name.contains('pool')) {
      return CupertinoIcons.drop;
    }
    if (name.contains('bbq')) {
      return CupertinoIcons.flame_fill;
    }
    return CupertinoIcons.square_grid_2x2;
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: theme.colorScheme.error.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            'Lỗi: $_error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.74),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _loadServices,
            icon: const Icon(CupertinoIcons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Chưa có dịch vụ nào',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF1D3A66), Color(0xFF0E2742)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : AppColors.primaryGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: AppColors.elevatedShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.categoryName ?? 'Tiện ích',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Chọn khung giờ phù hợp và gửi yêu cầu để ban quản lý chuẩn bị cho bạn.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: const [
              _HeroTag(label: 'Đặt lịch linh hoạt'),
              _HeroTag(label: 'Thanh toán tiện lợi'),
              _HeroTag(label: 'Nhắc nhở tự động'),
            ],
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
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surface.withValues(alpha: 0.75),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection(
    Map<String, dynamic> service,
    String pricingType,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final List<Widget> priceWidgets = [];

    // Base price
    if (pricingType == 'FREE') {
      priceWidgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.checkmark_circle_fill,
                  size: 16, color: Colors.green.shade700),
              const SizedBox(width: 6),
              Text(
                'Miễn phí cho cư dân',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final pricePerHour = service['pricePerHour'] as num?;
      final pricePerSession = service['pricePerSession'] as num?;

      if (pricingType == 'SESSION' && pricePerSession != null) {
        priceWidgets.add(
          _buildPriceChip(
            theme,
            colorScheme,
            '${_currencyFormatter.format(pricePerSession)} / lượt',
            CupertinoIcons.ticket_fill,
          ),
        );
      } else if (pricePerHour != null && pricePerHour > 0) {
        priceWidgets.add(
          _buildPriceChip(
            theme,
            colorScheme,
            '${_currencyFormatter.format(pricePerHour)} / giờ',
            CupertinoIcons.clock_fill,
          ),
        );
      }
    }

    // Combos
    final combos = _parseList(service['combos']);
    if (combos.isNotEmpty) {
      final comboPrices = combos
          .map((c) => (c['price'] as num?) ?? 0)
          .where((p) => p > 0)
          .toList()
        ..sort();
      if (comboPrices.isNotEmpty) {
        final minCombo = comboPrices.first;
        final maxCombo = comboPrices.last;
        final comboText = comboPrices.length == 1
            ? '${_currencyFormatter.format(minCombo)} / combo'
            : '${_currencyFormatter.format(minCombo)} - ${_currencyFormatter.format(maxCombo)} / combo';
        priceWidgets.add(
          _buildPriceChip(
            theme,
            colorScheme,
            comboText,
            CupertinoIcons.square_stack_3d_up_fill,
            isHighlight: true,
          ),
        );
      }
    }

    // Tickets
    final tickets = _parseList(service['tickets']);
    if (tickets.isNotEmpty) {
      final ticketPrices = tickets
          .map((t) => (t['price'] as num?) ?? 0)
          .where((p) => p > 0)
          .toList()
        ..sort();
      if (ticketPrices.isNotEmpty) {
        final minTicket = ticketPrices.first;
        final maxTicket = ticketPrices.last;
        final ticketText = ticketPrices.length == 1
            ? '${_currencyFormatter.format(minTicket)} / vé'
            : '${_currencyFormatter.format(minTicket)} - ${_currencyFormatter.format(maxTicket)} / vé';
        priceWidgets.add(
          _buildPriceChip(
            theme,
            colorScheme,
            ticketText,
            CupertinoIcons.ticket,
            isHighlight: true,
          ),
        );
      }
    }

    // Options
    final options = _parseList(service['options']);
    if (options.isNotEmpty) {
      final optionPrices = options
          .map((o) => (o['price'] as num?) ?? 0)
          .where((p) => p > 0)
          .toList()
        ..sort();
      if (optionPrices.isNotEmpty) {
        final minOption = optionPrices.first;
        final maxOption = optionPrices.last;
        final optionText = optionPrices.length == 1
            ? 'Tùy chọn: ${_currencyFormatter.format(minOption)}'
            : 'Tùy chọn: ${_currencyFormatter.format(minOption)} - ${_currencyFormatter.format(maxOption)}';
        priceWidgets.add(
          _buildPriceChip(
            theme,
            colorScheme,
            optionText,
            CupertinoIcons.add_circled,
          ),
        );
      }
    }

    if (priceWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Giá dịch vụ',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: priceWidgets,
        ),
      ],
    );
  }

  Widget _buildPriceChip(
    ThemeData theme,
    ColorScheme colorScheme,
    String text,
    IconData icon, {
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isHighlight
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlight
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isHighlight
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isHighlight
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
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

  Widget _buildActionRow(
    BuildContext context,
    Map<String, dynamic> service,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FilledButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceDetailScreen(
                  serviceId: service['id'].toString(),
                  serviceName: service['name'] as String? ?? 'Dịch vụ',
                  categoryCode: widget.categoryCode,
                  categoryName: widget.categoryName,
                ),
              ),
            );
          },
          icon: const Icon(CupertinoIcons.arrow_right_circle_fill),
          label: const Text('Đặt dịch vụ'),
        ),
      ],
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


}

class _ServiceGlassCard extends StatelessWidget {
  const _ServiceGlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppColors.darkGlassLayerGradient()
                : AppColors.glassLayerGradient(),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.08),
            ),
            boxShadow: AppColors.subtleShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

