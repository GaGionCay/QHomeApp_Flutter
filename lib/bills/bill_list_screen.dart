import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/api_client.dart';
import 'bill_detail_screen.dart';
import 'bill_service.dart';

class BillListScreen extends StatefulWidget {
  const BillListScreen({super.key});

  @override
  State<BillListScreen> createState() => _BillListScreenState();
}

class _BillListScreenState extends State<BillListScreen>
    with WidgetsBindingObserver {
  late final BillService _service;
  late Future<List<BillDto>> _futureBills;
  StreamSubscription<Uri?>? _sub;
  final AppLinks _appLinks = AppLinks();
  final String _pendingBillPaymentKey = 'pending_bill_payment';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = BillService(ApiClient());
    _futureBills = _service.getUnpaidBills();

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

  Future<void> _checkPendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingBillId = prefs.getString(_pendingBillPaymentKey);

      if (pendingBillId == null) return;

      final billId = int.tryParse(pendingBillId);
      if (billId == null) {
        await prefs.remove(_pendingBillPaymentKey);
        return;
      }

      final bill = await _service.getBillDetail(billId);

      if (bill.status == 'PAID') {
        await prefs.remove(_pendingBillPaymentKey);
        if (mounted) {
          setState(() {
            _futureBills = _service.getUnpaidBills();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Thanh toán hóa đơn đã hoàn tất'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (bill.status == 'UNPAID') {
        if (mounted) {
          final shouldPay = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Thanh toán chưa hoàn tất'),
              content: Text(
                'Hóa đơn #$billId chưa được thanh toán.\n\n'
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
            await _payBill(billId);
          } else {
            await prefs.remove(_pendingBillPaymentKey);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi check pending bill payment: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingBillPaymentKey);
      } catch (_) {}
    }
  }

  Future<void> _payBill(int billId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingBillPaymentKey, billId.toString());

      final paymentUrl = await _service.createVnpayPaymentUrl(billId);

      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await prefs.remove(_pendingBillPaymentKey);
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
        await prefs.remove(_pendingBillPaymentKey);
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi thanh toán: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _listenForPaymentResult() async {
    _sub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;
      debugPrint('🔗 Nhận deep link: $uri');

      if (uri.scheme == 'qhomeapp' && uri.host == 'vnpay-result') {
        final billId = uri.queryParameters['billId'];
        final responseCode = uri.queryParameters['responseCode'];

        if (!mounted) return;

        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_pendingBillPaymentKey);
        } catch (e) {
          debugPrint('❌ Lỗi xóa pending bill payment: $e');
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
            _futureBills = _service.getUnpaidBills();
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
      debugPrint('❌ Lỗi khi nhận deep link: $err');
    });

    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      debugPrint('🚀 App được mở từ link: $initialUri');
    }
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'điện':
        return Icons.electric_bolt;
      case 'nước':
        return Icons.water_drop;
      case 'internet':
        return Icons.wifi;
      default:
        return Icons.receipt_long;
    }
  }

  Color _colorForType(String type) {
    switch (type.toLowerCase()) {
      case 'điện':
        return Colors.orangeAccent;
      case 'nước':
        return Colors.blueAccent;
      case 'internet':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatMoney(double amount) {
    final formatter = NumberFormat("#,##0", "vi_VN");
    return '${formatter.format(amount)} VNĐ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: const Text('Hóa đơn cần thanh toán'),
        backgroundColor: const Color(0xFF26A69A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<List<BillDto>>(
        future: _futureBills,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('⚠️ Lỗi tải dữ liệu: ${snapshot.error}'),
            );
          }

          final bills = snapshot.data ?? [];
          if (bills.isEmpty) {
            return const Center(
              child: Text(
                '🎉 Không có hóa đơn cần thanh toán!',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _futureBills = _service.getUnpaidBills();
              });
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: bills.length,
              itemBuilder: (context, index) {
                final bill = bills[index];
                final color = _colorForType(bill.billType);
                final icon = _iconForType(bill.billType);

                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BillDetailScreen(billId: bill.id),
                    ),
                  ),
                  child: Container(
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
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: color, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bill.billType,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tháng ${bill.billingMonth}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _formatMoney(bill.amount),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF26A69A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF26A69A),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => _payBill(bill.id),
                            child: const Text(
                              'Thanh toán',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
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
