import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../auth/api_client.dart';
import '../models/invoice_line.dart';
import '../models/invoice_category.dart';
import '../models/unit_info.dart';
import 'invoice_service.dart';

class InvoiceListScreen extends StatefulWidget {
  final String? initialUnitId;
  final List<UnitInfo>? initialUnits;

  const InvoiceListScreen({
    super.key,
    this.initialUnitId,
    this.initialUnits,
  });

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen>
    with WidgetsBindingObserver {
  late final ApiClient _apiClient;
  late final InvoiceService _service;
  late Future<List<InvoiceCategory>> _futureCategories;
  String? _selectedCategoryCode;
  StreamSubscription<Uri?>? _sub;
  final AppLinks _appLinks = AppLinks();
  final String _pendingInvoicePaymentKey = 'pending_invoice_payment';
  static const _selectedUnitPrefsKey = 'selected_unit_id';
  List<UnitInfo> _units = [];
  String? _selectedUnitId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiClient = ApiClient();
    _service = InvoiceService(_apiClient);
    _units = widget.initialUnits != null
        ? List<UnitInfo>.from(widget.initialUnits!)
        : <UnitInfo>[];
    _selectedUnitId = widget.initialUnitId;
    debugPrint('🧾 [InvoiceList] initState - initialUnit=${_selectedUnitId ?? 'null'}, initialUnits=${_units.length}');
    _futureCategories = _loadCategories();
    _listenForPaymentResult();
    _checkPendingPayment();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingPayment();
    }
  }

  Future<List<InvoiceCategory>> _loadCategories() async {
    debugPrint('🧾 [InvoiceList] _loadCategories() bắt đầu - units=${_units.length}, selectedUnit=$_selectedUnitId');
    if (_selectedUnitId == null) {
      final saved = await _getSavedUnitId();
      if (saved != null) {
        _selectedUnitId = saved;
        debugPrint('🧾 [InvoiceList] Sử dụng unit từ SharedPreferences: $_selectedUnitId');
      } else {
        debugPrint('⚠️ [InvoiceList] Chưa chọn căn hộ nào, trả về danh sách rỗng');
        return [];
      }
    }

    debugPrint('🧾 [InvoiceList] Gọi API unpaid-by-category (unitId=$_selectedUnitId)');
    final result = await _service.getUnpaidInvoicesByCategory(unitId: _selectedUnitId);
    debugPrint('🧾 [InvoiceList] API trả về ${result.length} nhóm');
    return result;
  }

  Future<String?> _getSavedUnitId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedUnitPrefsKey);
  }

  Future<void> _checkPendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingInvoiceId = prefs.getString(_pendingInvoicePaymentKey);

      if (pendingInvoiceId == null) return;

      final unitId = _selectedUnitId ?? await _getSavedUnitId();
      if (unitId == null) {
        debugPrint('⚠️ [InvoiceList] Không xác định được căn hộ khi kiểm tra thanh toán');
        return;
      }

      final invoices = await _service.getMyInvoices(unitId: unitId);
      final invoice = invoices.firstWhere(
        (inv) => inv.invoiceId == pendingInvoiceId,
        orElse: () => throw Exception('Invoice not found'),
      );

      if (invoice.status == 'PAID') {
        await prefs.remove(_pendingInvoicePaymentKey);
        if (mounted) {
          setState(() {
            _futureCategories = _loadCategories();
          });
          debugPrint('🧾 [InvoiceList] Thanh toán xong, reload dữ liệu');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Thanh toán hóa đơn đã hoàn tất'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (invoice.status == 'UNPAID' || invoice.status == 'DRAFT') {
        if (mounted) {
          final shouldPay = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Thanh toán chưa hoàn tất'),
              content: Text(
                'Hóa đơn ${invoice.invoiceId} chưa được thanh toán.\n\n'
                'Bạn có muốn thanh toán ngay bây giờ không?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Hủy'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Thanh toán',
                      style: TextStyle(color: Colors.teal)),
                ),
              ],
            ),
          );

          if (shouldPay == true && mounted) {
            await _payInvoice(invoice);
          } else {
            await prefs.remove(_pendingInvoicePaymentKey);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi check pending invoice payment: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingInvoicePaymentKey);
      } catch (_) {}
    }
  }

  void _listenForPaymentResult() async {
    _sub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;
      debugPrint('🔗 [InvoiceList] Nhận deep link: $uri');

      if (uri.scheme == 'qhomeapp' && uri.host == 'vnpay-result') {
        final invoiceId = uri.queryParameters['invoiceId'];
        final responseCode = uri.queryParameters['responseCode'];

        if (!mounted) return;

        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_pendingInvoicePaymentKey);
        } catch (e) {
          debugPrint('❌ [InvoiceList] Lỗi xóa pending invoice payment: $e');
        }

        if (responseCode == '00') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Thanh toán hóa đơn thành công!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _futureCategories = _loadCategories();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Thanh toán hóa đơn thất bại'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }, onError: (err) {
      debugPrint('❌ [InvoiceList] Lỗi khi nhận deep link: $err');
    });

    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      debugPrint('🚀 [InvoiceList] App được mở từ link: $initialUri');
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

  Widget _buildUnitSummary() {
    if (_selectedUnitId == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Text(
          'Bạn chưa được gán vào căn hộ nào',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
      );
    }

    UnitInfo? unit;
    for (final u in _units) {
      if (u.id == _selectedUnitId) {
        unit = u;
        break;
      }
    }

    final unitName = unit?.displayName ?? _selectedUnitId;
    final building = unit?.buildingName ?? unit?.buildingCode ?? '';

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
            'Căn hộ đang xem',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            unitName!,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (building.isNotEmpty)
            Text(
              'Tòa: $building',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PAID':
        return Colors.green;
      case 'DRAFT':
        return Colors.orange;
      case 'PUBLISHED':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatMoney(double amount) {
    final formatter = NumberFormat("#,##0", "vi_VN");
    return '${formatter.format(amount)} VNĐ';
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy', 'vi_VN').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  Future<void> _handlePayInvoice(InvoiceLineResponseDto invoice) async {
    if (invoice.isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Hóa đơn này đã được thanh toán rồi'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận thanh toán'),
        content: Text(
          'Bạn có chắc chắn muốn thanh toán hóa đơn này?\n\n'
          'Mô tả: ${invoice.description}\n'
          'Số tiền: ${_formatMoney(invoice.lineTotal)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF26A69A),
            ),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _payInvoice(invoice);
  }

  Future<void> _payInvoice(InvoiceLineResponseDto invoice) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingInvoicePaymentKey, invoice.invoiceId);

      final paymentUrl =
          await _service.createVnpayPaymentUrl(
            invoice.invoiceId,
            unitId: _selectedUnitId,
          );

      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await prefs.remove(_pendingInvoicePaymentKey);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể mở trình duyệt thanh toán'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingInvoicePaymentKey);
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi thanh toán: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
              label:
                  Text('${category.categoryName} (${category.invoiceCount})'),
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
                color:
                    selected ? const Color(0xFF26A69A) : Colors.grey.shade300,
              ),
              elevation: selected ? 2 : 0,
            ),
          );
        }).toList(),
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
                      'Tổng cần thanh toán: ${_formatMoney(category.totalAmount)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${category.invoiceCount} hóa đơn chưa thanh toán',
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black54),
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
            '🎉 Bạn đã thanh toán hết các hóa đơn chưa thanh toán',
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

  Widget _buildInvoiceCard(InvoiceLineResponseDto invoice) {
    final serviceColor = _colorForServiceCode(invoice.serviceCode);
    final serviceIcon = _iconForServiceCode(invoice.serviceCode);
    final statusColor = _statusColor(invoice.status);
    final bool isPaid = invoice.isPaid;

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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              invoice.serviceCodeDisplay,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              invoice.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
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
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 14, color: Colors.black54),
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
            if (!isPaid)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF26A69A),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => _handlePayInvoice(invoice),
                  child: const Text(
                    'Thanh toán',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (isPaid)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: const Text('Hóa đơn'),
        backgroundColor: const Color(0xFF26A69A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<List<InvoiceCategory>>(
        future: _futureCategories,
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
                    onPressed: () {
                      setState(() {
                        _futureCategories = _loadCategories();
                      });
                    },
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            );
          }

          final categories = snapshot.data ?? [];

          if (categories.isNotEmpty &&
              (_selectedCategoryCode == null ||
                  categories
                      .every((c) => c.categoryCode != _selectedCategoryCode))) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _selectedCategoryCode = categories.first.categoryCode;
              });
            });
          }

          final selectedCategory = categories.isNotEmpty
              ? categories.firstWhere(
                  (c) => c.categoryCode == _selectedCategoryCode,
                  orElse: () => categories.first,
                )
              : null;
          final invoices = selectedCategory?.invoices ?? [];

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _futureCategories = _loadCategories();
              });
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildUnitSummary(),
                const SizedBox(height: 16),
                if (categories.isEmpty)
                  _buildAllPaidState()
                else ...[
                  _buildCategorySelector(categories),
                  const SizedBox(height: 16),
                  _buildCategorySummary(selectedCategory!),
                  const SizedBox(height: 16),
                  if (invoices.isEmpty)
                    _buildCategoryEmptyState(selectedCategory)
                  else
                    ...invoices.map(_buildInvoiceCard),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
