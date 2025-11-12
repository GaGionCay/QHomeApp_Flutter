import 'dart:async';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/api_client.dart';
import '../common/layout_insets.dart';
import '../models/invoice_category.dart';
import '../models/invoice_line.dart';
import '../models/unit_info.dart';
import '../theme/app_colors.dart';
import 'invoice_service.dart';
import 'paid_invoices_screen.dart';

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

class _InvoicesGlassCard extends StatelessWidget {
  const _InvoicesGlassCard({
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
              color: theme.colorScheme.outline.withOpacity(0.08),
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
    debugPrint(
        '🧾 [InvoiceList] initState - initialUnit=${_selectedUnitId ?? 'null'}, initialUnits=${_units.length}');
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
    debugPrint(
        '🧾 [InvoiceList] _loadCategories() bắt đầu - units=${_units.length}, selectedUnit=$_selectedUnitId');
    if (_selectedUnitId == null) {
      final saved = await _getSavedUnitId();
      if (saved != null) {
        _selectedUnitId = saved;
        debugPrint(
            '🧾 [InvoiceList] Sử dụng unit từ SharedPreferences: $_selectedUnitId');
      } else {
        debugPrint(
            '⚠️ [InvoiceList] Chưa chọn căn hộ nào, trả về danh sách rỗng');
        return [];
      }
    }

    debugPrint(
        '🧾 [InvoiceList] Gọi API unpaid-by-category (unitId=$_selectedUnitId)');
    final result =
        await _service.getUnpaidInvoicesByCategory(unitId: _selectedUnitId);
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
        debugPrint(
            '⚠️ [InvoiceList] Không xác định được căn hộ khi kiểm tra thanh toán');
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
        final invoiceLabel = invoiceId ?? 'hóa đơn';
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
            SnackBar(
              content: Text('✅ $invoiceLabel đã được thanh toán thành công!'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _futureCategories = _loadCategories();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Thanh toán $invoiceLabel thất bại'),
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

  LinearGradient _backgroundGradient(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF050F1F),
          Color(0xFF0F1E33),
          Color(0xFF152B47),
        ],
      );
    }

    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFE8F4FF),
        Color(0xFFF2F6FF),
        Color(0xFFF9FBFF),
      ],
    );
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

  DateTime? _parseServiceDate(String value) {
    if (value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  Widget _buildSummaryStatTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final secondary = isDark
        ? Colors.white.withOpacity(0.7)
        : theme.colorScheme.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surface.withOpacity(0.12)
            : Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.08),
        ),
        boxShadow: AppColors.subtleShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  colors: [
                    accent.withOpacity(0.9),
                    accent.withOpacity(0.5),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppColors.subtleShadow,
              ),
              padding: const EdgeInsets.all(10),
              child: Icon(
                icon,
                size: 22,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                color: onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewHeader(List<InvoiceCategory> categories) {
    final unpaidInvoices = <InvoiceLineResponseDto>[];
    double totalAmount = 0;
    int totalInvoices = 0;

    for (final category in categories) {
      totalAmount += category.totalAmount;
      totalInvoices += category.invoiceCount;
      unpaidInvoices.addAll(
        category.invoices.where((invoice) => !invoice.isPaid),
      );
    }

    unpaidInvoices.sort((a, b) {
      final aDate = _parseServiceDate(a.serviceDate);
      final bDate = _parseServiceDate(b.serviceDate);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });

    final average =
        unpaidInvoices.isEmpty ? 0.0 : totalAmount / unpaidInvoices.length;
    final nextBillingDate = unpaidInvoices.isNotEmpty
        ? _parseServiceDate(unpaidInvoices.first.serviceDate)
        : null;

    final nextBillingText =
        (unpaidInvoices.isNotEmpty && nextBillingDate != null)
            ? DateFormat('dd/MM', 'vi_VN').format(nextBillingDate)
            : 'Không còn kỳ hạn';

    return _InvoicesGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tổng quan thanh toán',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSummaryStatTile(
                  label: 'Cần thanh toán',
                  value: _formatMoney(totalAmount),
                  icon: Icons.payments_rounded,
                  accent: AppColors.primaryEmerald,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildSummaryStatTile(
                  label: 'Số hóa đơn',
                  value: '$totalInvoices khoản',
                  icon: Icons.receipt_long_outlined,
                  accent: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildSummaryStatTile(
                  label: 'Bình quân mỗi hóa đơn',
                  value: _formatMoney(average),
                  icon: Icons.timeline_rounded,
                  accent: AppColors.skyMist,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildSummaryStatTile(
                  label: 'Kỳ thanh toán gần nhất',
                  value: nextBillingText,
                  icon: Icons.event_available_outlined,
                  accent: AppColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
  }) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surface.withOpacity(0.14)
            : Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: secondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitSummary() {
    if (_selectedUnitId == null) {
      return _InvoicesGlassCard(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: Row(
          children: [
            Container(
              height: 54,
              width: 54,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient(),
                borderRadius: BorderRadius.circular(18),
                boxShadow: AppColors.subtleShadow,
              ),
              child: const Icon(
                Icons.apartment_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                'Bạn chưa được gán vào căn hộ nào',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ],
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

    final theme = Theme.of(context);
    final textColor = theme.brightness == Brightness.dark
        ? Colors.white
        : AppColors.textPrimary;
    final secondaryColor = theme.colorScheme.onSurfaceVariant;

    return _InvoicesGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient(),
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppColors.subtleShadow,
            ),
            child: const Icon(
              Icons.home_work_outlined,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Căn hộ đang xem',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: secondaryColor,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  unitName!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (building.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Thuộc tòa $building',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryColor,
                    ),
                  ),
                ],
              ],
            ),
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

      final paymentUrl = await _service.createVnpayPaymentUrl(
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
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.categoryCode == _selectedCategoryCode;
          final accent = _colorForServiceCode(category.categoryCode);
          final icon = _iconForServiceCode(category.categoryCode);

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategoryCode = category.categoryCode;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: selected
                    ? accent.withOpacity(0.18)
                    : theme.brightness == Brightness.dark
                        ? theme.colorScheme.surface.withOpacity(0.12)
                        : Colors.white.withOpacity(0.74),
                border: Border.all(
                  color: selected
                      ? accent.withOpacity(0.7)
                      : theme.colorScheme.outline.withOpacity(0.16),
                ),
                boxShadow: selected ? AppColors.subtleShadow : const [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? accent
                        : theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${category.categoryName} (${category.invoiceCount})',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? accent
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategorySummary(InvoiceCategory category) {
    final theme = Theme.of(context);
    final accent = _colorForServiceCode(category.categoryCode);
    final icon = _iconForServiceCode(category.categoryCode);
    final secondary = theme.colorScheme.onSurfaceVariant;

    return _InvoicesGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [
                      accent.withOpacity(0.9),
                      accent.withOpacity(0.55),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: AppColors.subtleShadow,
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.categoryName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${category.invoiceCount} hóa đơn chưa thanh toán',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            color: secondary.withOpacity(0.1),
            height: 1,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Tổng cần thanh toán',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                ),
              ),
              const Spacer(),
              Text(
                _formatMoney(category.totalAmount),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllPaidState() {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return _InvoicesGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withOpacity(0.85),
                  AppColors.primaryEmerald.withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppColors.subtleShadow,
            ),
            child: const Icon(
              Icons.celebration,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Bạn đã hoàn tất tất cả hóa đơn chưa thanh toán',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Kiểm tra mục lịch sử để xem lại các giao dịch đã thanh toán.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryEmptyState(InvoiceCategory category) {
    final theme = Theme.of(context);
    final accent = _colorForServiceCode(category.categoryCode);
    final icon = _iconForServiceCode(category.categoryCode);
    final secondary = theme.colorScheme.onSurfaceVariant;

    return _InvoicesGlassCard(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withOpacity(0.85),
                  accent.withOpacity(0.55),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppColors.subtleShadow,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Không còn hóa đơn ${category.categoryName.toLowerCase()} chưa thanh toán',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Chúng tôi sẽ thông báo ngay khi có hóa đơn mới được phát hành.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
            ),
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

    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _InvoicesGlassCard(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 54,
                  width: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                      colors: [
                        serviceColor.withOpacity(0.92),
                        serviceColor.withOpacity(0.6),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: AppColors.subtleShadow,
                  ),
                  child: Icon(serviceIcon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              invoice.serviceCodeDisplay,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              invoice.status.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        invoice.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondary,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _buildMetaChip(
                            icon: Icons.calendar_today_outlined,
                            label: _formatDate(invoice.serviceDate),
                          ),
                          if (invoice.quantity > 0 && invoice.unit.isNotEmpty)
                            _buildMetaChip(
                              icon: Icons.align_horizontal_left_rounded,
                              label:
                                  '${invoice.quantity.toStringAsFixed(2)} ${invoice.unit}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Divider(color: secondary.withOpacity(0.12), height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  _formatMoney(invoice.lineTotal),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: serviceColor,
                  ),
                ),
                const Spacer(),
                if (!isPaid)
                  FilledButton.icon(
                    onPressed: () => _handlePayInvoice(invoice),
                    icon: const Icon(Icons.payment_rounded),
                    label: const Text('Thanh toán ngay'),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: AppColors.success,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Đã thanh toán',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaPadding = MediaQuery.of(context).padding;
    final topOffset = mediaPadding.top + kToolbarHeight + 18;
    final bottomPadding =
        LayoutInsets.bottomNavContentPadding(context, minimumGap: 28);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Hóa đơn & thanh toán'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: theme.brightness == Brightness.dark
            ? Colors.white
            : AppColors.textPrimary,
        actions: [
          IconButton(
            tooltip: 'Hóa đơn đã thanh toán',
            icon: const Icon(Icons.history_toggle_off_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PaidInvoicesScreen(
                    initialUnitId: _selectedUnitId,
                    initialUnits: _units,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _backgroundGradient(context),
        ),
        child: SafeArea(
          top: false,
          child: FutureBuilder<List<InvoiceCategory>>(
            future: _futureCategories,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                final error = snapshot.error;
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding:
                        EdgeInsets.fromLTRB(24, topOffset, 24, bottomPadding),
                    child: _InvoicesGlassCard(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 58,
                            width: 58,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.danger.withOpacity(0.88),
                                  Colors.redAccent.withOpacity(0.82),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: AppColors.subtleShadow,
                            ),
                            child: const Icon(
                              Icons.error_outline,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Không thể tải dữ liệu hóa đơn',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '$error',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: () {
                              setState(() {
                                _futureCategories = _loadCategories();
                              });
                            },
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final categories = snapshot.data ?? [];

              if (categories.isNotEmpty &&
                  (_selectedCategoryCode == null ||
                      categories.every(
                          (c) => c.categoryCode != _selectedCategoryCode))) {
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

              final content = <Widget>[
                _buildUnitSummary(),
                const SizedBox(height: 18),
              ];

              if (categories.isEmpty) {
                content.add(_buildAllPaidState());
              } else {
                content
                  ..add(_buildOverviewHeader(categories))
                  ..add(const SizedBox(height: 22))
                  ..add(
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Danh mục dịch vụ',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PaidInvoicesScreen(
                                  initialUnitId: _selectedUnitId,
                                  initialUnits: _units,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('Xem lịch sử'),
                        ),
                      ],
                    ),
                  )
                  ..add(const SizedBox(height: 16))
                  ..add(_buildCategorySelector(categories))
                  ..add(const SizedBox(height: 18))
                  ..add(_buildCategorySummary(selectedCategory!))
                  ..add(const SizedBox(height: 18));

                if (invoices.isEmpty) {
                  content.add(_buildCategoryEmptyState(selectedCategory));
                } else {
                  content.addAll(invoices.map(_buildInvoiceCard));
                }
              }

              return RefreshIndicator(
                edgeOffset: topOffset,
                color: theme.colorScheme.primary,
                onRefresh: () async {
                  setState(() {
                    _futureCategories = _loadCategories();
                  });
                },
                child: ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    24,
                    topOffset,
                    24,
                    bottomPadding,
                  ),
                  children: content,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
