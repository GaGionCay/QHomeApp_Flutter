import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class VnpayPaymentScreen extends StatefulWidget {
  final String paymentUrl;
  final int billId;
  final int? registrationId;

  const VnpayPaymentScreen({
    super.key,
    required this.paymentUrl,
    required this.billId,
    this.registrationId,
  });

  @override
  State<VnpayPaymentScreen> createState() => _VnpayPaymentScreenState();
}

class _VnpayPaymentScreenState extends State<VnpayPaymentScreen> {
  bool isLoading = true;
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => isLoading = true),
        onPageFinished: (_) => setState(() => isLoading = false),
        onNavigationRequest: (req) {
          if (req.url.startsWith('qhomeapp://vnpay-result')) {
            final uri = Uri.parse(req.url);
            final billId = uri.queryParameters['billId'];
            final invoiceId = uri.queryParameters['invoiceId'];
            final responseCode = uri.queryParameters['responseCode'];

            debugPrint('✅ Thanh toán hoàn tất - BillID: $billId, InvoiceID: $invoiceId, Code: $responseCode');

            Navigator.pop(context, {
              'billId': billId,
              'invoiceId': invoiceId,
              'responseCode': responseCode,
            });
            return NavigationDecision.prevent;
          }

          if (req.url.startsWith('qhomeapp://vnpay-registration-result')) {
            final uri = Uri.parse(req.url);
            final registrationId = uri.queryParameters['registrationId'];
            final responseCode = uri.queryParameters['responseCode'];

            debugPrint('✅ Thanh toán đăng ký xe hoàn tất - RegistrationID: $registrationId, Code: $responseCode');
            debugPrint('✅ Backend đã xử lý callback và redirect về deep link');

            Future.microtask(() async {
              if (mounted) {
                try {
                  await controller.loadRequest(Uri.parse('about:blank'));
                  debugPrint('✅ WebView đã load blank page');
                } catch (e) {
                  debugPrint('⚠️ Lỗi khi load blank page: $e');
                }
              }
            });

            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted) {
                setState(() => isLoading = false);
                debugPrint('✅ Navigating back with payment result');
                Navigator.pop(context, {
                  'registrationId': registrationId,
                  'responseCode': responseCode,
                });
              }
            });
            return NavigationDecision.prevent;
          }

          if (req.url.contains('/vnpay/redirect') || req.url.contains('/vnpay/return')) {
            debugPrint('✅ Redirect về return URL (cho phép load để backend xử lý callback): ${req.url}');
            
            try {
              final uri = Uri.parse(req.url);
              final params = uri.queryParameters;
              
              final responseCode = params['vnp_ResponseCode'] ?? '99';
              final transactionStatus = params['vnp_TransactionStatus'] ?? '99';
              final txnRef = params['vnp_TxnRef'] ?? '';
              
              debugPrint('✅ Parsed params - ResponseCode: $responseCode, TransactionStatus: $transactionStatus, TxnRef: $txnRef');
              
              String? registrationId;
              String? invoiceId;
              String? billId;
              
              if (txnRef.isNotEmpty && txnRef.contains('_')) {
                final idStr = txnRef.split('_')[0];
                
                try {
                  final id = int.parse(idStr);
                  if (widget.registrationId != null) {
                    registrationId = widget.registrationId.toString();
                    debugPrint('✅ Using registrationId from context: $registrationId (txnRef ID: $id)');
                  } else {
                    registrationId = id.toString();
                    debugPrint('✅ Using registrationId from txnRef: $registrationId');
                  }
                  if (widget.billId > 0 && registrationId == null) {
                    billId = widget.billId.toString();
                  }
                } catch (e) {
                  invoiceId = idStr;
                  debugPrint('✅ Using invoiceId from txnRef: $invoiceId');
                }
              } else if (widget.registrationId != null) {
                registrationId = widget.registrationId.toString();
                debugPrint('✅ Using registrationId from context (no txnRef): $registrationId');
              }
              
              debugPrint('✅ Extracted - RegistrationID: $registrationId, InvoiceID: $invoiceId, BillID: $billId');
              
              Map<String, dynamic> resultData;
              if (registrationId != null) {
                resultData = {
                  'registrationId': registrationId,
                  'responseCode': responseCode,
                  'transactionStatus': transactionStatus,
                };
              } else if (invoiceId != null) {
                resultData = {
                  'invoiceId': invoiceId,
                  'responseCode': responseCode,
                };
              } else if (billId != null) {
                resultData = {
                  'billId': billId,
                  'responseCode': responseCode,
                };
              } else {
                resultData = {
                  'responseCode': responseCode,
                  'success': responseCode == '00',
                };
              }
              
              return NavigationDecision.navigate;
            } catch (e) {
              debugPrint('❌ Lỗi khi parse redirect URL: $e');
              return NavigationDecision.navigate;
            }
          }

          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Hủy thanh toán'),
              content: const Text('Bạn có chắc chắn muốn hủy thanh toán?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Không'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Có', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );

          if (confirm == true && mounted) {
            Navigator.pop(context, null);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Thanh toán qua VNPAY'),
          backgroundColor: const Color(0xFF26A69A),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: controller),
            if (isLoading)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF26A69A)),
              ),
          ],
        ),
      ),
    );
  }
}
