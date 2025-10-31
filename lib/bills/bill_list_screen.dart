import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import '../auth/api_client.dart';
import 'bill_detail_screen.dart';
import 'bill_service.dart';
import 'vnpay_payment_screen.dart';

class BillListScreen extends StatefulWidget {
  const BillListScreen({super.key});

  @override
  State<BillListScreen> createState() => _BillListScreenState();
}

class _BillListScreenState extends State<BillListScreen> {
  late final BillService _service;
  late Future<List<BillDto>> _futureBills;
  StreamSubscription<Uri?>? _sub;
  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    _service = BillService(ApiClient());
    _futureBills = _service.getUnpaidBills();

    _listenForPaymentResult();
  }

  void _listenForPaymentResult() async {
    // ✅ Bắt link khi app đang chạy
    _sub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;
      print('🔗 Nhận deep link: $uri');

      if (uri.scheme == 'qhomeapp' && uri.host == 'vnpay-result') {
        final billId = uri.queryParameters['billId'];
        final responseCode = uri.queryParameters['responseCode'];

        if (!mounted) return;

        if (responseCode == '00') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Thanh toán hóa đơn #$billId thành công!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          setState(() {
            _futureBills = _service.getUnpaidBills();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Thanh toán hóa đơn #$billId thất bại'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }, onError: (err) {
      print('❌ Lỗi khi nhận deep link: $err');
    });

    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      print('🚀 App được mở từ link: $initialUri');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
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
                            onPressed: () async {
                              try {
                                final paymentUrl = await _service
                                    .createVnpayPaymentUrl(bill.id);
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => VnpayPaymentScreen(
                                      paymentUrl: paymentUrl,
                                      billId: bill.id,
                                    ),
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('❌ Lỗi thanh toán: $e')),
                                );
                              }
                            },
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
