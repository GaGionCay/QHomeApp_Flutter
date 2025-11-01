import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:developer';
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../auth/api_client.dart';
import '../models/invoice_line.dart';
import 'invoice_service.dart';

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> with WidgetsBindingObserver {
  late final InvoiceService _service;
  late Future<List<InvoiceLineResponseDto>> _futureInvoices;
  StreamSubscription<Uri?>? _sub;
  final AppLinks _appLinks = AppLinks();
  final String _pendingInvoicePaymentKey = 'pending_invoice_payment';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = InvoiceService(ApiClient());
    _futureInvoices = _service.getMyInvoices();
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
    // Khi app resume từ background, check pending payment
    if (state == AppLifecycleState.resumed) {
      _checkPendingPayment();
    }
  }

  /// Kiểm tra payment status của invoice đang pending
  Future<void> _checkPendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingInvoiceId = prefs.getString(_pendingInvoicePaymentKey);
      
      if (pendingInvoiceId == null) return;

      // Check payment status với backend - cần tìm invoice trong list
      final invoices = await _futureInvoices;
      final invoice = invoices.firstWhere(
        (inv) => inv.invoiceId == pendingInvoiceId,
        orElse: () => throw Exception('Invoice not found'),
      );
      
      // Nếu đã thanh toán thành công, xóa pending và refresh
      if (invoice.status == 'PAID') {
        await prefs.remove(_pendingInvoicePaymentKey);
        if (mounted) {
          setState(() {
            _futureInvoices = _service.getMyInvoices();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Thanh toán hóa đơn đã hoàn tất'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } 
      // Nếu chưa thanh toán, hiển thị thông báo và cho phép thanh toán lại
      else if (invoice.status == 'UNPAID' || invoice.status == 'DRAFT') {
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
                  child: const Text('Thanh toán', style: TextStyle(color: Colors.teal)),
                ),
              ],
            ),
          );

          if (shouldPay == true && mounted) {
            // Thanh toán lại
            await _payInvoice(invoice);
          } else {
            // Xóa pending nếu user không muốn thanh toán
            await prefs.remove(_pendingInvoicePaymentKey);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi check pending invoice payment: $e');
      // Nếu có lỗi, xóa pending
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingInvoicePaymentKey);
      } catch (_) {}
    }
  }

  void _listenForPaymentResult() async {
    // Bắt link khi app đang chạy
    _sub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;
      log('🔗 Nhận deep link: $uri');

      if (uri.scheme == 'qhomeapp' && uri.host == 'vnpay-result') {
        final invoiceId = uri.queryParameters['invoiceId'];
        final responseCode = uri.queryParameters['responseCode'];

        if (!mounted) return;

        // Xóa pending payment vì đã có kết quả (thành công hoặc thất bại)
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_pendingInvoicePaymentKey);
        } catch (e) {
          debugPrint('❌ Lỗi xóa pending invoice payment: $e');
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
            _futureInvoices = _service.getMyInvoices();
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
      log('❌ Lỗi khi nhận deep link: $err');
    });

    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      log('🚀 App được mở từ link: $initialUri');
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
      default:
        return Colors.grey;
    }
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

    // Xác nhận thanh toán
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
      // Lưu invoiceId đang pending payment
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingInvoicePaymentKey, invoice.invoiceId);
      
      // Tạo VNPAY payment URL
      final paymentUrl = await _service.createVnpayPaymentUrl(invoice.invoiceId);
      
      // Mở VNPAY trong external browser
      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Xóa pending nếu không mở được browser
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
      // Xóa pending nếu có lỗi
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
      body: FutureBuilder<List<InvoiceLineResponseDto>>(
        future: _futureInvoices,
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
                        _futureInvoices = _service.getMyInvoices();
                      });
                    },
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            );
          }

          final invoices = snapshot.data ?? [];
          if (invoices.isEmpty) {
            return const Center(
              child: Text(
                '🎉 Không có hóa đơn nào!',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _futureInvoices = _service.getMyInvoices();
              });
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: invoices.length,
              itemBuilder: (context, index) {
                final invoice = invoices[index];
                final serviceColor = _colorForServiceCode(invoice.serviceCode);
                final serviceIcon = _iconForServiceCode(invoice.serviceCode);
                final statusColor = _statusColor(invoice.status);

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
                              child: Icon(serviceIcon,
                                  color: serviceColor, size: 28),
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
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                        if (!invoice.isPaid)
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
                                    color: Colors.white),
                              ),
                            ),
                          ),
                        if (invoice.isPaid)
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
              },
            ),
          );
        },
      ),
    );
  }
}

