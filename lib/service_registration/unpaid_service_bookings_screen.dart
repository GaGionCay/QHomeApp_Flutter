import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/asset_maintenance_api_client.dart';
import '../theme/app_colors.dart';
import 'service_booking_service.dart';

import '../core/safe_state_mixin.dart';
class UnpaidServiceBookingsScreen extends StatefulWidget {
  const UnpaidServiceBookingsScreen({super.key});

  @override
  State<UnpaidServiceBookingsScreen> createState() =>
      _UnpaidServiceBookingsScreenState();
}

class _UnpaidServiceBookingsScreenState
    extends State<UnpaidServiceBookingsScreen> 
    with SafeStateMixin<UnpaidServiceBookingsScreen> {
  late final ServiceBookingService _bookingService;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri?>? _paymentSub;

  static const String _pendingPaymentKey = 'pending_service_booking_payment';

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bookings = const [];
  bool _localeReady = false;

  @override
  void initState() {
    super.initState();
    _bookingService = ServiceBookingService(AssetMaintenanceApiClient());
    _prepareLocale();
    _loadBookings();
    _listenForPaymentResult();
  }

  @override
  void dispose() {
    _paymentSub?.cancel();
    super.dispose();
  }

  Future<void> _prepareLocale() async {
    try {
      await initializeDateFormatting('vi_VN');
    } catch (e) {
      debugPrint('⚠️ Không thể khởi tạo dữ liệu ngôn ngữ: $e');
    } finally {
      if (mounted) {
        safeSetState(() {
          _localeReady = true;
        });
      }
    }
  }

  Future<void> _loadBookings() async {
    safeSetState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await _bookingService.getUnpaidBookings();
      if (!mounted) return;
      safeSetState(() {
        _bookings = bookings;
      });
    } catch (e) {
      if (!mounted) return;
      safeSetState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        safeSetState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _launchVnpayPayment(String bookingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingPaymentKey, bookingId);

      final response = await _bookingService.createVnpayPaymentUrl(bookingId);
      final paymentUrl = response['paymentUrl']?.toString();

      if (paymentUrl == null || paymentUrl.isEmpty) {
        throw Exception('Không nhận được URL thanh toán từ hệ thống.');
      }

      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đang chuyển tới cổng VNPAY, vui lòng hoàn tất thanh toán.'),
          ),
        );
      } else {
        throw Exception('Không thể mở cổng thanh toán.');
      }
    } catch (e) {
      await _clearPendingPayment();
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _cancelBooking(String bookingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hủy đặt dịch vụ?'),
        content: const Text(
          'Bạn chắc chắn muốn hủy yêu cầu đặt dịch vụ này không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Để sau'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hủy dịch vụ'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _bookingService.cancelBooking(bookingId);
      if (!mounted) return;
      _showMessage('Đã hủy đặt dịch vụ.');
      await _loadBookings();
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  void _listenForPaymentResult() {
    _paymentSub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;

      if (uri.scheme == 'qhomeapp' &&
          uri.host == 'vnpay-service-booking-result') {
        final bookingId = uri.queryParameters['bookingId'];
        final responseCode = uri.queryParameters['responseCode'];
        final successParam = uri.queryParameters['success'];
        final message = uri.queryParameters['message'];
        
        // Decode message if it exists (URL encoded)
        final decodedMessage = message != null ? Uri.decodeComponent(message) : null;

        await _clearPendingPayment();
        if (!mounted) return;

        // Determine success status: use 'success' parameter if available, otherwise check responseCode
        final isSuccess = successParam == 'true' || responseCode == '00';

        if (isSuccess) {
          // Use message from backend if available, otherwise fallback to default with email notification
          final successMessage = decodedMessage ?? 
              (bookingId != null 
                  ? '✅ Đơn đặt dịch vụ $bookingId đã được thanh toán thành công!\n📧 Email xác nhận đã được gửi đến hộp thư của bạn.'
                  : '✅ Thanh toán dịch vụ thành công!\n📧 Email xác nhận đã được gửi đến hộp thư của bạn.');
          _showMessage(successMessage, isError: false);
          await _loadBookings();
        } else {
          // Use message from backend if available, otherwise fallback to default
          final errorMessage = decodedMessage ?? 
              (bookingId != null 
                  ? '❌ Thanh toán đơn đặt dịch vụ $bookingId thất bại'
                  : '❌ Thanh toán thất bại. Vui lòng thử lại.');
          _showMessage(errorMessage, isError: true);
        }
      }
    }, onError: (err) {
      debugPrint('❌ Lỗi khi nhận liên kết thanh toán: $err');
    });
  }

  Future<void> _clearPendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingPaymentKey);
    } catch (e) {
      debugPrint('⚠️ Không thể xóa trạng thái thanh toán: $e');
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dịch vụ chưa thanh toán'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadBookings,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Không thể tải danh sách dịch vụ.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(_error!),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loadBookings,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_bookings.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 56),
          Icon(Icons.celebration_outlined, size: 72, color: Colors.green),
          SizedBox(height: 16),
          Center(
            child: Text(
              'Tuyệt vời! Bạn không có dịch vụ nào đang chờ thanh toán.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(height: 24),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      itemCount: _bookings.length,
      itemBuilder: (context, index) {
        final booking = _bookings[index];
        return _buildBookingCard(booking);
      },
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final serviceName = booking['serviceName']?.toString() ??
        booking['service']?['name']?.toString() ??
        'Dịch vụ';
    final totalAmount = booking['totalAmount'] as num? ?? 0;
    final bookingDate = booking['bookingDate'] != null
        ? DateTime.tryParse(booking['bookingDate'].toString())
        : null;
    final startTime = booking['startTime']?.toString();
    final endTime = booking['endTime']?.toString();
    final purpose = booking['purpose']?.toString();
    final bookingId = booking['id']?.toString() ?? '';
    final status = booking['status']?.toString() ?? '';
    final isCancelled = status.toUpperCase() == 'CANCELLED';

    final formattedAmount = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    ).format(totalAmount);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 4,
      color: isCancelled ? Colors.grey.shade100 : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCancelled ? Icons.cancel_outlined : Icons.pending_actions,
                  color: isCancelled ? Colors.grey : AppColors.warning,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    serviceName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isCancelled ? Colors.grey : null,
                      decoration: isCancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCancelled
                        ? Colors.grey.withValues(alpha: 0.16)
                        : AppColors.warning.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isCancelled ? 'Đã hủy' : 'Chờ thanh toán',
                    style: TextStyle(
                      color: isCancelled ? Colors.grey : AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (bookingDate != null)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_outlined),
                title: Text(
                  (_localeReady
                          ? DateFormat('EEEE, dd/MM/yyyy', 'vi_VN')
                          : DateFormat('dd/MM/yyyy'))
                      .format(bookingDate),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (startTime != null && endTime != null)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: Text(
                  '${startTime.substring(0, 5)} - ${endTime.substring(0, 5)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.payments_outlined),
              title: Text(
                formattedAmount,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.warning,
                ),
              ),
            ),
            if (purpose != null && purpose.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Ghi chú: $purpose',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            const SizedBox(height: 18),
            if (isCancelled) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dịch vụ này đã bị hủy. Bạn không thể thực hiện bất kỳ hành động nào.',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: bookingId.isEmpty
                          ? null
                          : () => _cancelBooking(bookingId),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Hủy dịch vụ'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: bookingId.isEmpty
                          ? null
                          : () => _launchVnpayPayment(bookingId),
                      icon: const Icon(Icons.payment),
                      label: const Text('Thanh toán'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}



