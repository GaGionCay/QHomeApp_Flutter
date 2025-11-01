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
  WebViewController? controller;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => isLoading = true),
          onPageFinished: (_) => setState(() => isLoading = false),
          onNavigationRequest: (req) {
            // ✅ Khi callback về app (deep link)
            if (req.url.startsWith('qhomeapp://vnpay-result') ||
                req.url.startsWith('qhomeapp://vnpay-registration-result')) {
              _handlePaymentCallback(req.url);
              return NavigationDecision.prevent;
            }

            // ✅ Cho phép backend redirect để xử lý callback
            if (req.url.contains('/vnpay/redirect') ||
                req.url.contains('/vnpay/return')) {
              debugPrint('✅ Cho phép redirect: ${req.url}');
              return NavigationDecision.navigate;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  Future<void> _handlePaymentCallback(String url) async {
    final uri = Uri.parse(url);
    final responseCode = uri.queryParameters['responseCode'];
    final registrationId = uri.queryParameters['registrationId'];
    final billId = uri.queryParameters['billId'];
    final invoiceId = uri.queryParameters['invoiceId'];

    debugPrint('✅ Payment callback: $url');

    // 🔒 Ngăn WebView bị crash khi back bằng cách load blank page trước khi pop
    try {
      await controller?.loadRequest(Uri.parse('about:blank'));
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('⚠️ Lỗi khi clear WebView: $e');
    }

    if (!mounted) return;

    Navigator.pop(context, {
      'billId': billId,
      'registrationId': registrationId,
      'invoiceId': invoiceId,
      'responseCode': responseCode,
    });
  }

  @override
  void dispose() {
    // ✅ Dọn WebView đúng cách tránh crash renderer
    controller?.clearCache();
    controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true, // ✅ Cho phép back vật lý hoạt động
      onPopInvoked: (didPop) async {
        if (!didPop && mounted) {
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
            try {
              await controller?.loadRequest(Uri.parse('about:blank'));
              await Future.delayed(const Duration(milliseconds: 200));
            } catch (_) {}
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
            if (controller != null) WebViewWidget(controller: controller!),
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
