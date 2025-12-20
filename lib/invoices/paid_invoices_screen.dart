import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/api_client.dart';
import '../auth/asset_maintenance_api_client.dart';
import '../common/layout_insets.dart';
import '../models/invoice_line.dart';
import '../models/unit_info.dart';
import '../service_registration/service_booking_service.dart';
import '../service_registration/maintenance_request_service.dart';
import '../theme/app_colors.dart';
import '../core/logger.dart';
import 'invoice_service.dart';

import '../core/safe_state_mixin.dart';
enum PaidItemType {
  electricity,
  water,
  utility,
  cleaning,
  repair,
  contractRenewal,
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
  final String? unitId;
  final DateTime? paidAt; 

  PaidItem({
    required this.id,
    required this.type,
    required this.name,
    required this.amount,
    required this.paymentDate,
    this.description,
    required this.icon,
    required this.iconColor,
    this.unitId,
    this.paidAt, 
  });
  
  DateTime get effectivePaymentDate => paidAt ?? paymentDate;
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
    with SingleTickerProviderStateMixin, SafeStateMixin<PaidInvoicesScreen> {
  late final ApiClient _apiClient;
  late final InvoiceService _invoiceService;
  late final AssetMaintenanceApiClient _assetMaintenanceApiClient;
  late final ServiceBookingService _bookingService;
  late final MaintenanceRequestService _maintenanceRequestService;
  late Future<List<PaidItem>> _futureData;
  late TabController _tabController;

  List<UnitInfo> _units = [];
  String? _selectedUnitId;
  String _selectedMonth = 'All time';
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
    // Cleaning request removed - no longer used
    // _cleaningRequestService = CleaningRequestService(_apiClient);
    _maintenanceRequestService = MaintenanceRequestService(_apiClient);
    _units = widget.initialUnits != null
        ? List<UnitInfo>.from(widget.initialUnits!)
        : <UnitInfo>[];
    _selectedUnitId = widget.initialUnitId;
    _tabController = TabController(length: 7, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        safeSetState(() {
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
      case 6:
        return PaidItemType.contractRenewal;
      default:
        return PaidItemType.electricity;
    }
  }

  Future<List<PaidItem>> _loadData() async {
    safeSetState(() => _isLoading = true);
    try {
      String? unitFilter = _selectedUnitId;
      if (unitFilter == null || unitFilter.isEmpty) {
        unitFilter = widget.initialUnitId;
      }
      if ((unitFilter == null || unitFilter.isEmpty) && _units.isNotEmpty) {
        unitFilter = _units.first.id;
      }

      final String unitIdForRequest = unitFilter ?? '';

      // ✅ Use new API: getPaidInvoicesForCurrentMonth (includes all paid invoices in current month)
      final paidInvoicesFuture = unitIdForRequest.isNotEmpty
          ? _invoiceService.getPaidInvoicesForCurrentMonth(unitId: unitIdForRequest)
          : Future.value(<dynamic>[]);
      final bookingsFuture = _bookingService.getPaidBookings();
      // Cleaning request removed - no longer used
      final cleaningRequestsFuture = Future.value(<dynamic>[]);
      final maintenanceRequestsFuture = _maintenanceRequestService.getPaidRequests();

      final paidInvoices = await paidInvoicesFuture;
      final bookings = await bookingsFuture;
      await cleaningRequestsFuture;
      final maintenanceRequests = await maintenanceRequestsFuture;


      final List<PaidItem> items = [];

      // ✅ Group invoice lines by invoiceId to avoid duplicates
      // Map: invoiceId -> List of invoice lines
      final Map<String, List<InvoiceLineResponseDto>> invoiceGroups = {};
      for (final invoice in paidInvoices) {
        final invoiceId = invoice.invoiceId;
        if (!invoiceGroups.containsKey(invoiceId)) {
          invoiceGroups[invoiceId] = [];
        }
        invoiceGroups[invoiceId]!.add(invoice);
      }


      for (final entry in invoiceGroups.entries) {
        final invoiceId = entry.key;
        final invoiceLines = entry.value;
        
        final firstInvoice = invoiceLines.first;

        double totalAmount = 0.0;
        for (final line in invoiceLines) {
          totalAmount += (line.totalAfterTax ?? line.lineTotal ?? 0.0);
        }

        PaidItemType? type;
        IconData icon;
        Color iconColor;

        final serviceCodeUpper = firstInvoice.serviceCode.toUpperCase();
        
        switch (serviceCodeUpper) {
          case 'ELECTRIC':
          case 'ELECTRICITY':
            type = PaidItemType.electricity;
            icon = Icons.bolt;
            iconColor = const Color(0xFFFFD700);
          case 'WATER':
            type = PaidItemType.water;
            icon = Icons.water_drop;
            iconColor = const Color(0xFF4A90E2);
          case 'CONTRACT_RENEWAL':
          case 'CONTRACT':
            type = PaidItemType.contractRenewal;
            icon = Icons.description;
            iconColor = const Color(0xFF9B59B6);
          case 'VEHICLE_CARD':
          case 'ELEVATOR_CARD':
          case 'RESIDENT_CARD':
            type = PaidItemType.utility;
            if (serviceCodeUpper.contains('VEHICLE')) {
              icon = Icons.directions_car;
            } else if (serviceCodeUpper.contains('ELEVATOR')) {
              icon = Icons.elevator;
            } else if (serviceCodeUpper.contains('RESIDENT')) {
              icon = Icons.badge;
            } else {
              icon = Icons.credit_card;
            }
            iconColor = const Color(0xFF7EC8E3);
          default:
            type = PaidItemType.utility;
            icon = Icons.home;
            iconColor = const Color(0xFF7EC8E3);
        }

        final paidAt = firstInvoice.paidAt;
        final paymentDate = paidAt ?? _parsePaymentDate(firstInvoice.serviceDate);
        
        if (paymentDate != null) {
          final displayName = _mapServiceCodeToDisplayName(
            firstInvoice.serviceCode,
            firstInvoice.serviceCodeDisplay,
          );
          
          // Combine descriptions from all lines if multiple lines exist
          String? combinedDescription;
          if (invoiceLines.length > 1) {
            final descriptions = invoiceLines
                .map((line) => line.description ?? '')
                .where((desc) => desc.isNotEmpty)
                .toSet()
                .toList();
            combinedDescription = descriptions.join(', ');
          } else {
            combinedDescription = firstInvoice.description;
          }
          
          
          items.add(PaidItem(
            id: invoiceId,
            type: type,
            name: displayName,
            amount: totalAmount,
            paymentDate: paymentDate,
            description: combinedDescription,
            icon: icon,
            iconColor: iconColor,
            unitId: unitIdForRequest.isNotEmpty ? unitIdForRequest : null,
            paidAt: paidAt,
          ));
        } else {
          debugPrint('⚠️ [PaidInvoices] Skipping invoice $invoiceId - paymentDate is null');
        }
      }

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
          unitId: unitIdForRequest.isNotEmpty ? unitIdForRequest : null,
        ));
      }

      for (final booking in bookings) {
        final paymentDate = _parseBookingPaymentDate(booking);
        if (paymentDate != null) {
          final amount = (booking['totalPrice'] as num?)?.toDouble() ??
                        (booking['amount'] as num?)?.toDouble() ??
                        (booking['totalAmount'] as num?)?.toDouble() ??
                        (booking['price'] as num?)?.toDouble() ??
                        (booking['paymentAmount'] as num?)?.toDouble() ??
                        0.0;
          
          // Get service name and map serviceCode if available
          String serviceName = booking['serviceName']?.toString() ?? 'Tiện ích';
          final serviceCode = booking['serviceCode']?.toString();
          if (serviceCode != null) {
            serviceName = _mapServiceCodeToDisplayName(serviceCode, serviceName);
          }
          
          items.add(PaidItem(
            id: booking['id']?.toString() ?? '',
            type: PaidItemType.utility,
            name: serviceName,
            amount: amount,
            paymentDate: paymentDate,
            description: booking['serviceName']?.toString(),
            icon: Icons.spa,
            iconColor: const Color(0xFF9B59B6),
            unitId: unitIdForRequest.isNotEmpty ? unitIdForRequest : null,
          ));
        }
      }

      items.sort((a, b) => b.effectivePaymentDate.compareTo(a.effectivePaymentDate));

      _allItems = items;
      return items;
    } catch (e) {
      debugPrint('Error loading paid items: $e');
      return [];
    } finally {
      safeSetState(() => _isLoading = false);
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
    safeSetState(() {
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
          item.effectivePaymentDate.year,
          item.effectivePaymentDate.month,
        );
        final matches = itemMonth.isAtSameMomentAs(thisMonth);
        if (!matches) {
        }
        return matches;
      }).toList();
    } else if (_selectedMonth == 'Last month') {
      items = items.where((item) {
        final itemMonth = DateTime(
          item.effectivePaymentDate.year,
          item.effectivePaymentDate.month,
        );
        final matches = itemMonth.isAtSameMomentAs(lastMonth);
        if (!matches) {
        }
        return matches;
      }).toList();
    } else if (_selectedMonth == 'All time') {
    }
    if (_sortOption == 'Newest - Oldest') {
      items.sort((a, b) => b.effectivePaymentDate.compareTo(a.effectivePaymentDate));
    } else if (_sortOption == 'Oldest - Newest') {
      items.sort((a, b) => a.effectivePaymentDate.compareTo(b.effectivePaymentDate));
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
          // Use effectivePaymentDate (prefers paidAt over paymentDate)
          final itemMonth = DateTime(
            item.effectivePaymentDate.year,
            item.effectivePaymentDate.month,
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
      // Use effectivePaymentDate (prefers paidAt over paymentDate)
      // Include all types: electricity, water, contract renewal, cards, utility, etc.
      final itemMonth = DateTime(
        item.effectivePaymentDate.year,
        item.effectivePaymentDate.month,
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
                safeSetState(() {
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
                            backgroundColor: _getTypeColor(entry.key).withValues(alpha: 0.1),
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
          Tab(text: 'Gia hạn hợp đồng'),
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
                    DropdownMenuItem(value: 'All time', child: Text('Tất cả thời gian')),
                    DropdownMenuItem(value: 'This month', child: Text('Tháng này')),
                    DropdownMenuItem(value: 'Last month', child: Text('Tháng trước')),
                    DropdownMenuItem(value: 'Custom', child: Text('Tùy chọn')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      safeSetState(() {
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
                safeSetState(() {
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
    return InkWell(
      onTap: () => _showPaidItemDetail(context, item),
      borderRadius: BorderRadius.circular(28),
      child: _PaidInvoicesGlassCard(
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
                    color: item.iconColor.withValues(alpha: 0.15),
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
                      color: AppColors.success.withValues(alpha: 0.15),
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
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ) ?? TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
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
      ),
    );
  }

  void _showPaidItemDetail(BuildContext context, PaidItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      isDismissible: true,
      enableDrag: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Stack(
            children: [
              // Backdrop - tap to dismiss
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              // Sheet content - prevent tap propagation
              Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {}, // Prevent tap from propagating to backdrop
                  child: _PaidItemDetailSheet(
                    item: item,
                    invoiceService: _invoiceService,
                    bookingService: _bookingService,
                    // Cleaning request removed - no longer used
                    // cleaningRequestService: _cleaningRequestService,
                    maintenanceRequestService: _maintenanceRequestService,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
      case PaidItemType.contractRenewal:
        return 'Gia hạn hợp đồng';
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
      case PaidItemType.contractRenewal:
        return const Color(0xFF9B59B6);
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

  /// Map serviceCode to Vietnamese display name
  String _mapServiceCodeToDisplayName(String serviceCode, String fallback) {
    switch (serviceCode.toUpperCase()) {
      case 'RESIDENT_CARD':
        return 'Thẻ cư dân';
      case 'VEHICLE_CARD':
        return 'Thẻ xe';
      default:
        return fallback;
    }
  }
}

class _PaidItemDetailSheet extends StatefulWidget {
  const _PaidItemDetailSheet({
    required this.item,
    required this.invoiceService,
    required this.bookingService,
    // Cleaning request removed - no longer used
    // required this.cleaningRequestService,
    required this.maintenanceRequestService,
  });

  final PaidItem item;
  final InvoiceService invoiceService;
  final ServiceBookingService bookingService;
  // Cleaning request removed - no longer used
  // final CleaningRequestService cleaningRequestService;
  final MaintenanceRequestService maintenanceRequestService;

  @override
  State<_PaidItemDetailSheet> createState() => _PaidItemDetailSheetState();
}

class _PaidItemDetailSheetState extends State<_PaidItemDetailSheet> with SafeStateMixin<_PaidItemDetailSheet> {
  Map<String, dynamic>? _detailData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    AppLogger.info('[PaidInvoicesDetail] Bắt đầu load chi tiết cho item: ${widget.item.type.name} (ID: ${widget.item.id})');
    
    safeSetState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      switch (widget.item.type) {
        case PaidItemType.electricity:
        case PaidItemType.water:
        case PaidItemType.contractRenewal:
          // Load invoice detail for electricity/water
          if (widget.item.unitId != null && widget.item.unitId!.isNotEmpty) {
            try {
              final invoices = await widget.invoiceService.getPaidInvoicesByCategory(
                unitId: widget.item.unitId!,
              );
              for (final category in invoices) {
                for (final invoice in category.invoices) {
                  if (invoice.invoiceId == widget.item.id) {
                    // Get full invoice detail to get paidAt
                    final invoiceDetail = await widget.invoiceService.getInvoiceDetailById(invoice.invoiceId);
                    
                    
                    final paidAt = invoiceDetail?['paidAt'];

                    final quantityDisplay = _formatQuantity(invoice.quantity);
                    if (paidAt != null) {
                      final paidAtDate = DateTime.parse(paidAt.toString());
                    } else {
                      AppLogger.warning('   - Payment Date: ${widget.item.paymentDate.toString()} (từ serviceDate, paidAt không có trong response)');
                      AppLogger.warning('   - Invoice Status: ${invoiceDetail?['status']}');
                    }
                    safeSetState(() {
                      _detailData = {
                        'type': 'invoice',
                        'invoiceId': invoice.invoiceId,
                        'serviceCode': invoice.serviceCode,
                        'description': invoice.description,
                        'serviceDate': invoice.serviceDate,
                        'lineTotal': invoice.lineTotal,
                        'quantity': invoice.quantity == invoice.quantity.toInt() 
                            ? invoice.quantity.toInt() 
                            : invoice.quantity,
                        'unit': invoice.unit,
                        'unitPrice': invoice.unitPrice,
                        'taxAmount': invoice.taxAmount,
                        'paidAt': paidAt,
                      };
                    });
                    return;
                  }
                }
              }
              AppLogger.warning('[PaidInvoicesDetail] ⚠️ Không tìm thấy invoice với ID: ${widget.item.id}');
            } catch (e) {
              AppLogger.error('[PaidInvoicesDetail] ❌ Lỗi khi load invoice detail', e);
            }
          } else {
            AppLogger.warning('[PaidInvoicesDetail] ⚠️ unitId không có, không thể load invoice detail');
          }
        case PaidItemType.utility:
          try {
            final booking = await widget.bookingService.getBookingById(widget.item.id);
            if (booking['bookingDate'] != null) {
              AppLogger.info('   - Booking Date: ${booking['bookingDate']}');
            }
            if (booking['startTime'] != null && booking['endTime'] != null) {
              AppLogger.info('   - Time: ${booking['startTime']} - ${booking['endTime']}');
            }
            safeSetState(() {
              _detailData = {
                'type': 'booking',
                ...booking,
              };
            });
          } catch (e) {
            // Check if error is "Booking not found" - this is expected, silently fallback to invoice
            final errorMessage = e.toString().toLowerCase();
            final isNotFoundError = errorMessage.contains('booking not found') ||
                errorMessage.contains('not found') ||
                errorMessage.contains('không tìm thấy');
            
            if (isNotFoundError) {
              AppLogger.info('[PaidInvoicesDetail] ℹ️ Booking không tồn tại (mong đợi), đang fallback sang invoice...');
            } else {
              AppLogger.error('[PaidInvoicesDetail] ❌ Lỗi khi load booking detail, đang thử invoice', e);
            }
            
            // Fallback to invoice if unitId is available
            if (widget.item.unitId != null && widget.item.unitId!.isNotEmpty) {
              try {
                AppLogger.debug('[PaidInvoicesDetail] Gọi API getPaidInvoicesByCategory để tìm invoice (unitId: ${widget.item.unitId})');
                final invoices = await widget.invoiceService.getPaidInvoicesByCategory(
                  unitId: widget.item.unitId!,
                );
                AppLogger.debug('[PaidInvoicesDetail] Nhận được ${invoices.length} categories, đang tìm invoice với ID: ${widget.item.id}');
                for (final category in invoices) {
                  for (final invoice in category.invoices) {
                    if (invoice.invoiceId == widget.item.id) {
                      final invoiceDetail = await widget.invoiceService.getInvoiceDetailById(invoice.invoiceId);
                      final paidAt = invoiceDetail?['paidAt'];
                      final quantityDisplay = _formatQuantity(invoice.quantity);
                      if (paidAt != null) {
                        final paidAtDate = DateTime.parse(paidAt.toString());
                      } else {
                        AppLogger.warning('   - Payment Date: ${widget.item.paymentDate.toString()} (từ serviceDate, có thể không chính xác về thời gian)');
                      }
                      safeSetState(() {
                        _detailData = {
                          'type': 'invoice',
                          'invoiceId': invoice.invoiceId,
                          'serviceCode': invoice.serviceCode,
                          'description': invoice.description,
                          'serviceDate': invoice.serviceDate,
                          'lineTotal': invoice.lineTotal,
                          'quantity': invoice.quantity == invoice.quantity.toInt() 
                              ? invoice.quantity.toInt() 
                              : invoice.quantity,
                          'unit': invoice.unit,
                          'unitPrice': invoice.unitPrice,
                          'taxAmount': invoice.taxAmount,
                          'paidAt': paidAt,
                        };
                      });
                      return;
                    }
                  }
                }
                AppLogger.warning('[PaidInvoicesDetail] ⚠️ Không tìm thấy invoice với ID: ${widget.item.id} sau khi fallback');
              } catch (e2) {
                AppLogger.error('[PaidInvoicesDetail] ❌ Lỗi khi load invoice detail (fallback)', e2);
              }
            } else {
              AppLogger.warning('[PaidInvoicesDetail] ⚠️ unitId không có, không thể fallback sang invoice');
            }
          }
        case PaidItemType.cleaning:
          AppLogger.warning('[PaidInvoicesDetail] ⚠️ Cleaning request feature đã bị gỡ bỏ');

          try {
            throw Exception('Cleaning request feature has been removed');
          } catch (e) {
            AppLogger.error('[PaidInvoicesDetail] ❌ Lỗi khi load cleaning detail', e);
          }
        case PaidItemType.repair:
          try {
            final requests = await widget.maintenanceRequestService.getPaidRequests();
            final request = requests.firstWhere(
              (r) => r.id == widget.item.id,
              orElse: () => throw Exception('Not found'),
            );
            final paymentAmount = request.paymentAmount ?? widget.item.amount;
            final paymentDate = request.paymentDate ?? widget.item.paymentDate;
            if (request.note != null && request.note!.isNotEmpty) {
              AppLogger.info('   - Note: ${request.note}');
            }
            safeSetState(() {
              _detailData = {
                'type': 'repair',
                'id': request.id,
                'title': request.title,
                'note': request.note,
                'location': request.location,
                'createdAt': request.createdAt,
                'paymentDate': request.paymentDate,
                'paymentAmount': request.paymentAmount,
                'status': request.status,
              };
            });
          } catch (e) {
            AppLogger.error('[PaidInvoicesDetail] ❌ Lỗi khi load repair detail', e);
          }
      }
    } catch (e) {
      AppLogger.error('[PaidInvoicesDetail] ❌ Lỗi tổng quát khi load detail', e);
      safeSetState(() {
        _error = e.toString();
      });
    } finally {
      AppLogger.info('[PaidInvoicesDetail] Hoàn thành load detail (isLoading: false)');
      safeSetState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0F213A)
                : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.item.iconColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        widget.item.icon,
                        color: widget.item.iconColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Đã thanh toán',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 48,
                                    color: colorScheme.error,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Không thể tải chi tiết',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _error!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            children: [
                              _buildDetailContent(theme, colorScheme, isDark),
                            ],
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Helper method to format payment date from detailData or fallback to widget.item.paymentDate
  String _formatQuantity(dynamic quantity) {
    if (quantity == null) return '0';
    final qty = quantity is num ? quantity : double.tryParse(quantity.toString()) ?? 0.0;
    // If quantity is a whole number, display without decimal (e.g., 1 instead of 1.0)
    if (qty == qty.toInt()) {
      return qty.toInt().toString();
    }
    return qty.toString();
  }

  String _formatPaymentDate(Map<String, dynamic> data) {
    if (data['paidAt'] != null) {
      try {
        final paidAtStr = data['paidAt'].toString();
        final paidAtDate = DateTime.parse(paidAtStr);
        return DateFormat('dd/MM/yyyy HH:mm').format(paidAtDate.toLocal());
      } catch (e) {
      }
    }
    return DateFormat('dd/MM/yyyy HH:mm').format(widget.item.paymentDate);
  }

  Widget _buildDetailContent(ThemeData theme, ColorScheme colorScheme, bool isDark) {
    if (_detailData == null) {
      return _buildBasicInfo(theme, colorScheme, isDark);
    }

    final type = _detailData!['type'] as String?;
    switch (type) {
      case 'invoice':
        return _buildInvoiceDetail(theme, colorScheme, isDark);
      case 'booking':
        return _buildBookingDetail(theme, colorScheme, isDark);
      case 'cleaning':
        return _buildCleaningDetail(theme, colorScheme, isDark);
      case 'repair':
        return _buildRepairDetail(theme, colorScheme, isDark);
      default:
        return _buildBasicInfo(theme, colorScheme, isDark);
    }
  }

  Widget _buildBasicInfo(ThemeData theme, ColorScheme colorScheme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.attach_money,
          'Số tiền',
          NumberFormat.currency(locale: 'vi_VN', symbol: '₫')
              .format(widget.item.amount)
              .replaceAll('.', ','),
        ),
        const SizedBox(height: 16),
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.calendar_today,
          'Ngày thanh toán',
          _formatPaymentDate(_detailData!),
        ),
        if (widget.item.description != null) ...[
          const SizedBox(height: 16),
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.description,
            'Mô tả',
            widget.item.description!,
          ),
        ],
      ],
    );
  }

  Widget _buildInvoiceDetail(ThemeData theme, ColorScheme colorScheme, bool isDark) {
    final data = _detailData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.receipt_long,
          'Mã hóa đơn',
          data['invoiceId']?.toString() ?? widget.item.id,
        ),
        const SizedBox(height: 16),
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.attach_money,
          'Tổng tiền',
          NumberFormat.currency(locale: 'vi_VN', symbol: '₫')
              .format(data['lineTotal'] ?? widget.item.amount)
              .replaceAll('.', ','),
        ),
        if (data['quantity'] != null && data['unitPrice'] != null) ...[
          const SizedBox(height: 16),
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.numbers,
            'Số lượng',
            '${_formatQuantity(data['quantity'])} ${data['unit'] ?? ''}',
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.price_check,
            'Đơn giá',
            NumberFormat.currency(locale: 'vi_VN', symbol: '₫')
                .format(data['unitPrice'])
                .replaceAll('.', ','),
          ),
        ],
        if (data['taxAmount'] != null && (data['taxAmount'] as num) > 0) ...[
          const SizedBox(height: 16),
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.receipt,
            'Thuế',
            NumberFormat.currency(locale: 'vi_VN', symbol: '₫')
                .format(data['taxAmount'])
                .replaceAll('.', ','),
          ),
        ],
        const SizedBox(height: 16),
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.calendar_today,
          'Ngày dịch vụ',
          data['serviceDate']?.toString() ?? DateFormat('dd/MM/yyyy').format(widget.item.paymentDate),
        ),
        const SizedBox(height: 16),
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.calendar_today,
          'Ngày thanh toán',
          _formatPaymentDate(data),
        ),
        if (data['description'] != null && data['description'].toString().isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.description,
            'Mô tả',
            data['description'].toString(),
          ),
        ],
      ],
    );
  }

  Widget _buildBookingDetail(ThemeData theme, ColorScheme colorScheme, bool isDark) {
    final data = _detailData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.attach_money,
          'Tổng tiền',
          NumberFormat.currency(locale: 'vi_VN', symbol: '₫')
              .format(data['totalPrice'] ?? data['amount'] ?? widget.item.amount)
              .replaceAll('.', ','),
        ),
        const SizedBox(height: 16),
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.calendar_today,
          'Ngày đặt',
          data['createdAt'] != null
              ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(data['createdAt'].toString()).toLocal())
              : DateFormat('dd/MM/yyyy').format(widget.item.paymentDate),
        ),
        const SizedBox(height: 16),
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.calendar_today,
          'Ngày thanh toán',
          _formatPaymentDate(data),
        ),
        if (data['serviceName'] != null) ...[
          const SizedBox(height: 16),
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.spa,
            'Dịch vụ',
            data['serviceName'].toString(),
          ),
        ],
        if (data['purpose'] != null && data['purpose'].toString().isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.description,
            'Mục đích',
            data['purpose'].toString(),
          ),
        ],
      ],
    );
  }

  Widget _buildCleaningDetail(ThemeData theme, ColorScheme colorScheme, bool isDark) {
    final data = _detailData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.cleaning_services,
          'Loại dọn dẹp',
          data['cleaningType']?.toString() ?? 'Dọn dẹp',
        ),
        const SizedBox(height: 16),
        if (data['location'] != null && data['location'].toString().isNotEmpty) ...[
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.location_on,
            'Địa điểm',
            data['location'].toString(),
          ),
          const SizedBox(height: 16),
        ],
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.calendar_today,
          'Ngày tạo',
          data['createdAt'] != null
              ? DateFormat('dd/MM/yyyy HH:mm').format(data['createdAt'] as DateTime)
              : DateFormat('dd/MM/yyyy').format(widget.item.paymentDate),
        ),
        if (data['note'] != null && data['note'].toString().isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.description,
            'Ghi chú',
            data['note'].toString(),
          ),
        ],
      ],
    );
  }

  Widget _buildRepairDetail(ThemeData theme, ColorScheme colorScheme, bool isDark) {
    final data = _detailData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.handyman,
          'Tiêu đề',
          data['title']?.toString() ?? 'Sửa chữa',
        ),
        const SizedBox(height: 16),
        if (data['location'] != null && data['location'].toString().isNotEmpty) ...[
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.location_on,
            'Địa điểm',
            data['location'].toString(),
          ),
          const SizedBox(height: 16),
        ],
        if (data['paymentAmount'] != null) ...[
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.attach_money,
            'Số tiền',
            NumberFormat.currency(locale: 'vi_VN', symbol: '₫')
                .format(data['paymentAmount'])
                .replaceAll('.', ','),
          ),
          const SizedBox(height: 16),
        ],
        _buildInfoRow(
          theme,
          colorScheme,
          isDark,
          Icons.calendar_today,
          'Ngày tạo',
          data['createdAt'] != null
              ? DateFormat('dd/MM/yyyy HH:mm').format(data['createdAt'] as DateTime)
              : DateFormat('dd/MM/yyyy').format(widget.item.paymentDate),
        ),
        if (data['paymentDate'] != null) ...[
          const SizedBox(height: 16),
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.calendar_today,
            'Ngày thanh toán',
            DateFormat('dd/MM/yyyy HH:mm').format(data['paymentDate'] as DateTime),
          ),
        ],
        if (data['note'] != null && data['note'].toString().isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildInfoRow(
            theme,
            colorScheme,
            isDark,
            Icons.description,
            'Ghi chú',
            data['note'].toString(),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
    IconData icon,
    String label,
    String value,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.item.iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: widget.item.iconColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


