import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/api_client.dart';
import '../auth/asset_maintenance_api_client.dart';
import '../common/layout_insets.dart';
import '../models/invoice_category.dart';
import '../models/unit_info.dart';
import '../service_registration/service_booking_service.dart';
import '../service_registration/cleaning_request_service.dart';
import '../service_registration/maintenance_request_service.dart';
import '../theme/app_colors.dart';
import 'invoice_service.dart';

// Unified model for all paid items
enum PaidItemType {
  electricity,
  water,
  utility,
  cleaning,
  repair,
}

class PaidItem {
  final String id;
  final PaidItemType type;
  final String name;
  final double amount;
  final DateTime paymentDate;
  final String? description;
  final IconData icon;
  final Color iconColor;

  PaidItem({
    required this.id,
    required this.type,
    required this.name,
    required this.amount,
    required this.paymentDate,
    this.description,
    required this.icon,
    required this.iconColor,
  });
}

class PaidInvoicesScreen extends StatefulWidget {
  final String? initialUnitId;
  final List<UnitInfo>? initialUnits;

  const PaidInvoicesScreen({
    super.key,
    this.initialUnitId,
    this.initialUnits,
  });

  @override
  State<PaidInvoicesScreen> createState() => _PaidInvoicesScreenState();
}

class _PaidInvoicesGlassCard extends StatelessWidget {
  const _PaidInvoicesGlassCard({
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(28);
    final gradient = theme.brightness == Brightness.dark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: borderRadius,
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.08),
            ),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PaidInvoicesScreenState extends State<PaidInvoicesScreen>
    with SingleTickerProviderStateMixin {
  late final ApiClient _apiClient;
  late final InvoiceService _invoiceService;
  late final AssetMaintenanceApiClient _assetMaintenanceApiClient;
  late final ServiceBookingService _bookingService;
  late final CleaningRequestService _cleaningRequestService;
  late final MaintenanceRequestService _maintenanceRequestService;
  late Future<List<PaidItem>> _futureData;
  late TabController _tabController;

  List<UnitInfo> _units = [];
  String? _selectedUnitId;
  String _selectedMonth = 'This month';
  String _sortOption = 'Newest - Oldest';
  List<PaidItem> _allItems = [];
  bool _isLoading = false;
  bool _isSummaryExpanded = true;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _invoiceService = InvoiceService(_apiClient);
    _assetMaintenanceApiClient = AssetMaintenanceApiClient();
    _bookingService = ServiceBookingService(_assetMaintenanceApiClient);
    _cleaningRequestService = CleaningRequestService(_apiClient);
    _maintenanceRequestService = MaintenanceRequestService(_apiClient);
    _units = widget.initialUnits != null
        ? List<UnitInfo>.from(widget.initialUnits!)
        : <UnitInfo>[];
    _selectedUnitId = widget.initialUnitId;
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          // Trigger rebuild when tab changes
        });
      }
    });
    _futureData = _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  PaidItemType _getCategoryFromIndex(int index) {
    switch (index) {
      case 0:
        return PaidItemType.electricity; // All (will be filtered)
      case 1:
        return PaidItemType.electricity;
      case 2:
        return PaidItemType.water;
      case 3:
        return PaidItemType.utility;
      case 4:
        return PaidItemType.cleaning;
      case 5:
        return PaidItemType.repair;
      default:
        return PaidItemType.electricity;
    }
  }

  Future<List<PaidItem>> _loadData() async {
    setState(() => _isLoading = true);
    try {
      String? unitFilter = _selectedUnitId;
      if (unitFilter == null || unitFilter.isEmpty) {
        unitFilter = widget.initialUnitId;
      }
      if ((unitFilter == null || unitFilter.isEmpty) && _units.isNotEmpty) {
        unitFilter = _units.first.id;
      }

      final String unitIdForRequest = unitFilter ?? '';

      final categoriesFuture = unitIdForRequest.isNotEmpty
          ? _invoiceService.getPaidInvoicesByCategory(unitId: unitIdForRequest)
          : Future.value(<InvoiceCategory>[]);
      final bookingsFuture = _bookingService.getPaidBookings();
      final cleaningRequestsFuture = _cleaningRequestService.getPaidRequests();
      final maintenanceRequestsFuture = _maintenanceRequestService.getPaidRequests();

      final categories = await categoriesFuture;
      final bookings = await bookingsFuture;
      final cleaningRequests = await cleaningRequestsFuture;
      final maintenanceRequests = await maintenanceRequestsFuture;

      final List<PaidItem> items = [];

      // Process invoice categories
      for (final category in categories) {
        for (final invoice in category.invoices) {
          if (!invoice.isPaid) continue;

          PaidItemType? type;
          IconData icon;
          Color iconColor;

          switch (invoice.serviceCode.toUpperCase()) {
            case 'ELECTRIC':
            case 'ELECTRICITY':
              type = PaidItemType.electricity;
              icon = Icons.bolt;
              iconColor = const Color(0xFFFFD700);
              break;
            case 'WATER':
              type = PaidItemType.water;
              icon = Icons.water_drop;
              iconColor = const Color(0xFF4A90E2);
              break;
            default:
              type = PaidItemType.utility;
              icon = Icons.home;
              iconColor = const Color(0xFF7EC8E3);
          }

          final paymentDate = _parsePaymentDate(invoice.serviceDate);
          if (paymentDate != null) {
            items.add(PaidItem(
              id: invoice.invoiceId,
              type: type,
              name: invoice.serviceCodeDisplay,
              amount: invoice.lineTotal,
              paymentDate: paymentDate,
              description: invoice.description,
              icon: icon,
              iconColor: iconColor,
            ));
          }
        }
      }

      // Process cleaning requests
      for (final request in cleaningRequests) {
        if (request.status.toUpperCase() != 'DONE') continue;
        // Use createdAt as payment date if paymentDate is not available
        final paymentDate = request.createdAt;
        items.add(PaidItem(
          id: request.id,
          type: PaidItemType.cleaning,
          name: 'Dọn dẹp',
          amount: 0.0, // Cleaning requests may not have payment amount
          paymentDate: paymentDate,
          description: request.cleaningType,
          icon: Icons.cleaning_services,
          iconColor: const Color(0xFF24D1C4),
        ));
      }

      // Process maintenance requests
      for (final request in maintenanceRequests) {
        if (request.paymentStatus?.toUpperCase() != 'PAID') continue;
        final paymentDate = request.paymentDate ?? request.createdAt;
        items.add(PaidItem(
          id: request.id,
          type: PaidItemType.repair,
          name: 'Sửa chữa',
          amount: request.paymentAmount ?? 0.0,
          paymentDate: paymentDate,
          description: request.title,
          icon: Icons.handyman,
          iconColor: const Color(0xFFFF6B6B),
        ));
      }

      // Process bookings (utilities/amenities)
      for (final booking in bookings) {
        final paymentDate = _parseBookingPaymentDate(booking);
        if (paymentDate != null) {
          items.add(PaidItem(
            id: booking['id']?.toString() ?? '',
            type: PaidItemType.utility,
            name: booking['serviceName']?.toString() ?? 'Tiện ích',
            amount: (booking['totalPrice'] as num?)?.toDouble() ?? 0.0,
            paymentDate: paymentDate,
            description: booking['serviceName']?.toString(),
            icon: Icons.spa,
            iconColor: const Color(0xFF9B59B6),
          ));
        }
      }

      _allItems = items;
      return items;
    } catch (e) {
      debugPrint('Error loading paid items: $e');
      return [];
    } finally {
      setState(() => _isLoading = false);
    }
  }

  DateTime? _parsePaymentDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      return DateFormat('yyyy-MM-dd').parse(dateString);
    } catch (e) {
      return null;
    }
  }

  DateTime? _parseBookingPaymentDate(Map<String, dynamic> booking) {
    final dateStr = booking['paymentDate']?.toString() ??
        booking['createdAt']?.toString();
    if (dateStr == null) return null;
    try {
      return DateTime.parse(dateStr).toLocal();
    } catch (e) {
      return null;
    }
  }

  void _refresh() {
    setState(() {
      _futureData = _loadData();
    });
  }

  List<PaidItem> _getFilteredItems() {
    var items = List<PaidItem>.from(_allItems);

    // Filter by category (All = show all, index 0)
    if (_tabController.index != 0) {
      final category = _getCategoryFromIndex(_tabController.index);
      items = items.where((item) => item.type == category).toList();
    }

    // Filter by month
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final lastMonth = DateTime(now.year, now.month - 1);

    if (_selectedMonth == 'This month') {
      items = items.where((item) {
        final itemMonth = DateTime(
          item.paymentDate.year,
          item.paymentDate.month,
        );
        return itemMonth.isAtSameMomentAs(thisMonth);
      }).toList();
    } else if (_selectedMonth == 'Last month') {
      items = items.where((item) {
        final itemMonth = DateTime(
          item.paymentDate.year,
          item.paymentDate.month,
        );
        return itemMonth.isAtSameMomentAs(lastMonth);
      }).toList();
    }
    // Custom month filtering can be added later

    // Sort
    if (_sortOption == 'Newest - Oldest') {
      items.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    } else if (_sortOption == 'Oldest - Newest') {
      items.sort((a, b) => a.paymentDate.compareTo(b.paymentDate));
    } else if (_sortOption == 'Amount high - low') {
      items.sort((a, b) => b.amount.compareTo(a.amount));
    } else if (_sortOption == 'Amount low - high') {
      items.sort((a, b) => a.amount.compareTo(b.amount));
    }

    return items;
  }

  double _getTotalForThisMonth() {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    return _allItems
        .where((item) {
          final itemMonth = DateTime(
            item.paymentDate.year,
            item.paymentDate.month,
          );
          return itemMonth.isAtSameMomentAs(thisMonth);
        })
        .fold(0.0, (sum, item) => sum + item.amount);
  }

  Map<PaidItemType, double> _getBreakdownForThisMonth() {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final breakdown = <PaidItemType, double>{};

    for (final item in _allItems) {
      final itemMonth = DateTime(
        item.paymentDate.year,
        item.paymentDate.month,
      );
      if (itemMonth.isAtSameMomentAs(thisMonth)) {
        breakdown[item.type] = (breakdown[item.type] ?? 0.0) + item.amount;
      }
    }

    return breakdown;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final double bottomInset = LayoutInsets.bottomNavContentPadding(context);

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
        title: const Text('Đã thanh toán'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: FutureBuilder<List<PaidItem>>(
          future: _futureData,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting ||
                _isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: _PaidInvoicesGlassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Không thể tải dữ liệu',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot.error.toString(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.74),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final filteredItems = _getFilteredItems();
            final totalThisMonth = _getTotalForThisMonth();
            final breakdown = _getBreakdownForThisMonth();

            return Column(
              children: [
                // Summary Header
                _buildSummaryHeader(totalThisMonth, breakdown, theme),
                
                // Category Tabs
                _buildCategoryTabs(theme),
                
                // Filter Bar
                _buildFilterBar(theme),
                
                // Grid List
                Expanded(
                  child: filteredItems.isEmpty
                      ? _buildEmptyState(theme)
                      : _buildGridList(filteredItems, theme, bottomInset),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(
    double total,
    Map<PaidItemType, double> breakdown,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: _PaidInvoicesGlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with toggle button
            InkWell(
              onTap: () {
                setState(() {
                  _isSummaryExpanded = !_isSummaryExpanded;
                });
              },
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tổng tháng này',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            NumberFormat.currency(locale: 'vi_VN', symbol: '₫')
                                .format(total)
                                .replaceAll('.', ','),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    AnimatedRotation(
                      turns: _isSummaryExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Expandable breakdown section
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _isSummaryExpanded && breakdown.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: breakdown.entries.map((entry) {
                          final typeName = _getTypeName(entry.key);
                          return Chip(
                            label: Text(
                              '$typeName: ${NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(entry.value).replaceAll('.', ',')}',
                              style: theme.textTheme.bodySmall,
                            ),
                            backgroundColor: _getTypeColor(entry.key).withOpacity(0.1),
                            labelStyle: TextStyle(
                              color: _getTypeColor(entry.key),
                              fontSize: 12,
                            ),
                          );
                        }).toList(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: theme.colorScheme.surface.withValues(alpha: 0.3),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        indicatorColor: theme.colorScheme.primary,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.tab,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        tabs: const [
          Tab(text: 'Tất cả'),
          Tab(text: 'Điện'),
          Tab(text: 'Nước'),
          Tab(text: 'Tiện ích'),
          Tab(text: 'Dọn dẹp'),
          Tab(text: 'Sửa chữa'),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          // Month Selector
          Expanded(
            child: _PaidInvoicesGlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedMonth,
                  isExpanded: true,
                  icon: Icon(
                    Icons.calendar_today,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  style: theme.textTheme.bodyMedium,
                  items: const [
                    DropdownMenuItem(value: 'This month', child: Text('Tháng này')),
                    DropdownMenuItem(value: 'Last month', child: Text('Tháng trước')),
                    DropdownMenuItem(value: 'Custom', child: Text('Tùy chọn')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedMonth = value;
                      });
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Sort Button
          _PaidInvoicesGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: PopupMenuButton<String>(
              onSelected: (value) {
                setState(() {
                  _sortOption = value;
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'Newest - Oldest',
                  child: Text('Mới nhất - Cũ nhất'),
                ),
                const PopupMenuItem(
                  value: 'Oldest - Newest',
                  child: Text('Cũ nhất - Mới nhất'),
                ),
                const PopupMenuItem(
                  value: 'Amount high - low',
                  child: Text('Số tiền cao - thấp'),
                ),
                const PopupMenuItem(
                  value: 'Amount low - high',
                  child: Text('Số tiền thấp - cao'),
                ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sort,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _getSortDisplayText(),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridList(List<PaidItem> items, ThemeData theme, double bottomInset) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _buildPaidItemCard(items[index], theme);
      },
    );
  }

  Widget _buildPaidItemCard(PaidItem item, ThemeData theme) {
    return _PaidInvoicesGlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Icon and Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: item.iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  item.icon,
                  color: item.iconColor,
                  size: 24,
                ),
              ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Đã thanh toán',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          
          // Service Name
          Flexible(
            child: Text(
              item.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          
          // Amount
          Flexible(
            child: Text(
              NumberFormat.currency(locale: 'vi_VN', symbol: '₫')
                  .format(item.amount)
                  .replaceAll('.', ','),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          
          // Payment Date
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  DateFormat('dd/MM/yyyy').format(item.paymentDate),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: _PaidInvoicesGlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có giao dịch nào',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Các giao dịch đã thanh toán sẽ hiển thị tại đây',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _getTypeName(PaidItemType type) {
    switch (type) {
      case PaidItemType.electricity:
        return 'Điện';
      case PaidItemType.water:
        return 'Nước';
      case PaidItemType.utility:
        return 'Tiện ích';
      case PaidItemType.cleaning:
        return 'Dọn dẹp';
      case PaidItemType.repair:
        return 'Sửa chữa';
    }
  }

  Color _getTypeColor(PaidItemType type) {
    switch (type) {
      case PaidItemType.electricity:
        return const Color(0xFFFFD700);
      case PaidItemType.water:
        return const Color(0xFF4A90E2);
      case PaidItemType.utility:
        return const Color(0xFF7EC8E3);
      case PaidItemType.cleaning:
        return const Color(0xFF24D1C4);
      case PaidItemType.repair:
        return const Color(0xFFFF6B6B);
    }
  }

  String _getSortDisplayText() {
    switch (_sortOption) {
      case 'Newest - Oldest':
        return 'Mới nhất';
      case 'Oldest - Newest':
        return 'Cũ nhất';
      case 'Amount high - low':
        return 'Số tiền cao';
      case 'Amount low - high':
        return 'Số tiền thấp';
      default:
        return 'Mới nhất';
    }
  }
}
