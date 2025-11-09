import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/api_client.dart';
import '../auth/asset_maintenance_api_client.dart';
import '../models/invoice_category.dart';
import '../models/invoice_line.dart';
import '../models/unit_info.dart';
import '../service_registration/service_booking_service.dart';
import 'invoice_service.dart';

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

class _PaidInvoicesScreenState extends State<PaidInvoicesScreen> {
  late final ApiClient _apiClient;
  late final InvoiceService _invoiceService;
  late final AssetMaintenanceApiClient _assetMaintenanceApiClient;
  late final ServiceBookingService _bookingService;
  late Future<_PaidData> _futureData;
  String? _selectedCategoryCode;
  List<UnitInfo> _units = [];
  late String _selectedUnitId;
  static const String _allUnitsKey = 'ALL_UNITS';
  static const String _allMonthsKey = 'ALL';
  String _selectedMonthKey = _allMonthsKey;

  Future<_PaidData> _loadData() async {
    final String? unitFilter = _selectedUnitId == _allUnitsKey ? null : _selectedUnitId;
    final categoriesFuture = _invoiceService.getPaidInvoicesByCategory(unitId: unitFilter);
    final bookingsFuture = _bookingService.getPaidBookings();

    final categories = await categoriesFuture;
    final bookings = await bookingsFuture;

    return _PaidData(categories: categories, paidBookings: bookings);
  }

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _invoiceService = InvoiceService(_apiClient);
    _assetMaintenanceApiClient = AssetMaintenanceApiClient();
    _bookingService = ServiceBookingService(_assetMaintenanceApiClient);
    _units = widget.initialUnits != null
        ? List<UnitInfo>.from(widget.initialUnits!)
        : <UnitInfo>[];
    _selectedUnitId = _allUnitsKey;
    _selectedMonthKey = _allMonthsKey;
    _futureData = _loadData();
  }

  Future<void> _refresh() async {
    setState(() {
      _futureData = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: const Text('Hóa đơn đã thanh toán'),
        backgroundColor: const Color(0xFF26A69A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<_PaidData>(
        future: _futureData,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    '⚠️ Lỗi tải dữ liệu: ${snapshot.error}',
                    style: const TextStyle(fontSize: 16, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            );
          }

          final rawCategories = snapshot.data?.categories ?? [];
          final paidBookings = snapshot.data?.paidBookings ?? [];
          final monthOptions = _buildMonthOptions(rawCategories);

          if (_selectedMonthKey != _allMonthsKey &&
              !monthOptions.any((opt) => opt.key == _selectedMonthKey)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _selectedMonthKey = _allMonthsKey;
                _selectedCategoryCode = null;
              });
            });
          }

          final categories = _filterCategoriesByMonth(rawCategories, _selectedMonthKey);

          InvoiceCategory? selectedCategory;
          if (categories.isNotEmpty) {
            selectedCategory = categories.firstWhere(
              (c) => c.categoryCode == _selectedCategoryCode,
              orElse: () => categories.first,
            );
            if (_selectedCategoryCode != selectedCategory.categoryCode) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _selectedCategoryCode = selectedCategory?.categoryCode;
                });
              });
            }
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildUnitFilter(),
                const SizedBox(height: 16),
                _buildMonthFilter(monthOptions),
                const SizedBox(height: 16),
                if (categories.isEmpty)
                  _buildAllPaidState()
                else ...[
                  _buildCategorySelector(categories),
                  const SizedBox(height: 16),
                  if (selectedCategory != null) ...[
                    _buildCategorySummary(selectedCategory),
                    const SizedBox(height: 16),
                    if (selectedCategory.invoices.isEmpty)
                      _buildCategoryEmptyState(selectedCategory)
                    else
                      ...selectedCategory.invoices.map(_buildInvoiceCard),
                  ],
                ],
                const SizedBox(height: 32),
                _buildPaidBookingsSection(paidBookings),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonthFilter(List<_MonthOption> options) {
    if (options.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Text(
          'Chưa có hóa đơn đã thanh toán',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedMonthKey,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          items: options
              .map((option) => DropdownMenuItem<String>(
                    value: option.key,
                    child: Text(option.label),
                  ))
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedMonthKey = value;
              _selectedCategoryCode = null;
            });
          },
        ),
      ),
    );
  }

  Widget _buildCategorySelector(List<InvoiceCategory> categories) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((category) {
          final bool selected = category.categoryCode == _selectedCategoryCode;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('${category.categoryName} (${category.invoiceCount})'),
              selected: selected,
              onSelected: (value) {
                if (!value) return;
                setState(() {
                  _selectedCategoryCode = category.categoryCode;
                });
              },
              selectedColor: const Color(0xFF26A69A),
              labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: selected ? const Color(0xFF26A69A) : Colors.grey.shade300,
              ),
              elevation: selected ? 2 : 0,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUnitFilter() {
    final options = <_UnitOption>[
      const _UnitOption(_allUnitsKey, 'Tất cả căn hộ'),
      ..._units.map((unit) => _UnitOption(unit.id, unit.displayName)),
    ];

    final current = _selectedUnitId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lọc theo căn hộ',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((option) {
              final selected = current == option.id;
              return ChoiceChip(
                label: Text(option.label),
                selected: selected,
                onSelected: (value) {
                  if (!value) return;
                  if (_selectedUnitId == option.id) return;
                  setState(() {
                    _selectedUnitId = option.id;
                    _selectedCategoryCode = null;
                    _selectedMonthKey = _allMonthsKey;
                    _futureData = _loadData();
                  });
                },
              );
            }).toList(),
          ),
          if (_units.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Bạn chưa được gán vào căn hộ nào, hiển thị tất cả hóa đơn.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategorySummary(InvoiceCategory category) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category.categoryName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.payments, color: Color(0xFF26A69A)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tổng đã thanh toán: ${_formatMoney(category.totalAmount)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${category.invoiceCount} hóa đơn đã thanh toán',
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllPaidState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.celebration, color: Colors.green, size: 48),
          SizedBox(height: 12),
          Text(
            '🎉 Bạn đã thanh toán hết các hóa đơn',
            style: TextStyle(fontSize: 15, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryEmptyState(InvoiceCategory category) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.celebration, color: Colors.green, size: 48),
          const SizedBox(height: 12),
          Text(
            'Bạn đã thanh toán hết hóa đơn ${category.categoryName.toLowerCase()}',
            style: const TextStyle(fontSize: 15, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<_MonthOption> _buildMonthOptions(List<InvoiceCategory> categories) {
    final Map<String, String> monthMap = {};

    for (final category in categories) {
      for (final invoice in category.invoices) {
        final key = _monthKeyFromServiceDate(invoice.serviceDate);
        if (key == null) continue;
        monthMap.putIfAbsent(key, () => _formatMonthLabel(key));
      }
    }

    final sortedKeys = monthMap.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final options = <_MonthOption>[
      _MonthOption(_allMonthsKey, 'Tất cả tháng'),
      ...sortedKeys.map((key) => _MonthOption(key, monthMap[key]!)),
    ];

    return options;
  }

  List<InvoiceCategory> _filterCategoriesByMonth(List<InvoiceCategory> categories, String selectedMonth) {
    if (selectedMonth == _allMonthsKey) {
      return categories;
    }

    final List<InvoiceCategory> filtered = [];

    for (final category in categories) {
      final invoices = category.invoices
          .where((invoice) => _monthKeyFromServiceDate(invoice.serviceDate) == selectedMonth)
          .toList();

      if (invoices.isEmpty) continue;

      final total = invoices.fold<double>(0, (sum, item) => sum + item.lineTotal);

      filtered.add(InvoiceCategory(
        categoryCode: category.categoryCode,
        categoryName: category.categoryName,
        totalAmount: total,
        invoiceCount: invoices.length,
        invoices: invoices,
      ));
    }

    return filtered;
  }

  String? _formatServiceMonth(String serviceDate) {
    final key = _monthKeyFromServiceDate(serviceDate);
    if (key == null) return null;
    return _formatMonthLabel(key);
  }

  String _formatMonthLabel(String key) {
    try {
      final parts = key.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final date = DateTime(year, month);
      return DateFormat('MM/yyyy').format(date);
    } catch (_) {
      return key;
    }
  }

  String? _monthKeyFromServiceDate(String serviceDate) {
    if (serviceDate.isEmpty) return null;
    try {
      final date = DateTime.parse(serviceDate);
      final year = date.year.toString().padLeft(4, '0');
      final month = date.month.toString().padLeft(2, '0');
      return '$year-$month';
    } catch (_) {
      return null;
    }
  }

  Widget _buildInvoiceCard(InvoiceLineResponseDto invoice) {
    final serviceColor = _colorForServiceCode(invoice.serviceCode);
    final serviceIcon = _iconForServiceCode(invoice.serviceCode);
    final monthLabel = _formatServiceMonth(invoice.serviceDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: serviceColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(serviceIcon, color: serviceColor, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.serviceCodeDisplay,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        invoice.description,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (monthLabel != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.calendar_month, size: 14, color: Colors.black54),
                            const SizedBox(width: 4),
                            Text(
                              'Tháng: $monthLabel',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 14, color: Colors.black54),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(invoice.serviceDate),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '${invoice.quantity.toStringAsFixed(2)} ${invoice.unit}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatMoney(invoice.lineTotal),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF26A69A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '✅ Đã thanh toán',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorForServiceCode(String serviceCode) {
    switch (serviceCode.toUpperCase()) {
      case 'ELECTRIC':
      case 'ELECTRICITY':
        return Colors.orangeAccent;
      case 'WATER':
        return Colors.blueAccent;
      case 'INTERNET':
        return Colors.teal;
      case 'ELEVATOR':
      case 'ELEVATOR_CARD':
        return Colors.deepPurpleAccent;
      case 'PARKING':
      case 'CAR_PARK':
      case 'CARPARK':
      case 'VEHICLE_PARKING':
      case 'MOTORBIKE_PARK':
        return Colors.indigoAccent;
      default:
        return Colors.grey;
    }
  }

  IconData _iconForServiceCode(String serviceCode) {
    switch (serviceCode.toUpperCase()) {
      case 'ELECTRIC':
      case 'ELECTRICITY':
        return Icons.electric_bolt;
      case 'WATER':
        return Icons.water_drop;
      case 'INTERNET':
        return Icons.wifi;
      case 'ELEVATOR':
      case 'ELEVATOR_CARD':
        return Icons.elevator;
      case 'PARKING':
      case 'CAR_PARK':
      case 'CARPARK':
      case 'VEHICLE_PARKING':
      case 'MOTORBIKE_PARK':
        return Icons.local_parking;
      default:
        return Icons.receipt_long;
    }
  }

  String _formatMoney(double amount) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(amount);
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy', 'vi_VN').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  Widget _buildPaidBookingsSection(List<Map<String, dynamic>> bookings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dịch vụ đã thanh toán',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (bookings.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.event_available, color: Colors.green, size: 48),
                SizedBox(height: 12),
                Text(
                  'Chưa có dịch vụ nào đã thanh toán',
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ...bookings.map(_buildPaidBookingCard),
      ],
    );
  }

  Widget _buildPaidBookingCard(Map<String, dynamic> booking) {
    final serviceName = booking['serviceName']?.toString() ?? 'Dịch vụ';
    final categoryCode = booking['serviceCode']?.toString() ?? '';
    final totalAmount = (booking['totalAmount'] as num?)?.toDouble() ?? 0;
    final bookingDateStr = booking['bookingDate']?.toString();
    final startTime = booking['startTime']?.toString();
    final endTime = booking['endTime']?.toString();
    final paymentDateStr = booking['paymentDate']?.toString();
    final paymentStatus = booking['paymentStatus']?.toString() ?? '';
    final purpose = booking['purpose']?.toString();

    final bookingDateLabel =
        bookingDateStr != null ? _formatDate(bookingDateStr) : '—';
    final paymentDateLabel = _formatDateTime(paymentDateStr);
    final timeRangeLabel = _formatTimeRange(startTime, endTime);
    final amountLabel = _formatMoney(totalAmount);
    final paymentStatusLabel = _translatePaymentStatus(paymentStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF26A69A).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.event_available_outlined,
                    color: Color(0xFF26A69A),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        serviceName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (categoryCode.isNotEmpty)
                        Text(
                          categoryCode,
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    paymentStatusLabel,
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.black45),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ngày sử dụng: $bookingDateLabel'),
                      if (timeRangeLabel != null)
                        Text('Khung giờ: $timeRangeLabel'),
                      Text('Thanh toán lúc: $paymentDateLabel'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tổng tiền',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    Text(
                      amountLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF26A69A),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Trạng thái',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    Text(
                      paymentStatusLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (purpose != null && purpose.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Ghi chú: $purpose',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm', 'vi_VN').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  String? _formatTimeRange(String? start, String? end) {
    if ((start == null || start.isEmpty) && (end == null || end.isEmpty)) {
      return null;
    }

    String shorten(String value) {
      return value.length >= 5 ? value.substring(0, 5) : value;
    }

    if (start != null && end != null && start.isNotEmpty && end.isNotEmpty) {
      return '${shorten(start)} - ${shorten(end)}';
    }
    if (start != null && start.isNotEmpty) {
      return shorten(start);
    }
    if (end != null && end.isNotEmpty) {
      return shorten(end);
    }
    return null;
  }

  String _translatePaymentStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PAID':
        return 'Đã thanh toán';
      case 'PENDING':
        return 'Đang chờ xử lý';
      case 'UNPAID':
        return 'Chưa thanh toán';
      default:
        return status;
    }
  }
}

class _MonthOption {
  final String key;
  final String label;

  const _MonthOption(this.key, this.label);
}

class _PaidData {
  final List<InvoiceCategory> categories;
  final List<Map<String, dynamic>> paidBookings;

  const _PaidData({required this.categories, required this.paidBookings});
}

class _UnitOption {
  final String id;
  final String label;

  const _UnitOption(this.id, this.label);
}

