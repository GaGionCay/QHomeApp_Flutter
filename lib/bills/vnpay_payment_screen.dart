import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class VnpayPaymentScreen extends StatefulWidget {
  final String paymentUrl;
  final int billId;

  const VnpayPaymentScreen({
    super.key,
    required this.paymentUrl,
    required this.billId,
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
          // Khi VNPAY redirect về deep link app
          if (req.url.startsWith('qhomeapp://vnpay-result')) {
            final uri = Uri.parse(req.url);
            final billId = uri.queryParameters['billId'];
            final responseCode = uri.queryParameters['responseCode'];

            debugPrint(
                '✅ Thanh toán hoàn tất - BillID: $billId, Code: $responseCode');

            Navigator.pop(context, {
              'billId': billId,
              'responseCode': responseCode,
            });
            return NavigationDecision.prevent;
          }

          if (req.url.contains('/vnpay/return')) {
            debugPrint(
                '✅ Redirect về return URL (trường hợp test nội bộ): ${req.url}');
            Navigator.pop(context, true);
            return NavigationDecision.prevent;
          }

          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
}
