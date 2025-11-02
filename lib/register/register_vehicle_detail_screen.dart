import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer';
import '../auth/api_client.dart';
import 'register_vehicle_request.dart';
import 'package:app_links/app_links.dart';

class RegisterServiceDetailScreen extends StatefulWidget {
  final RegisterServiceRequest registration;

  const RegisterServiceDetailScreen({
    super.key,
    required this.registration,
  });

  @override
  State<RegisterServiceDetailScreen> createState() =>
      _RegisterServiceDetailScreenState();
}

class _RegisterServiceDetailScreenState
    extends State<RegisterServiceDetailScreen> with WidgetsBindingObserver {
  final ApiClient api = ApiClient();
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri?>? _paymentSub;
  final String _pendingPaymentKey = 'pending_registration_payment';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForPaymentResult();
    _checkPendingPayment();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paymentSub?.cancel();
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
      final pendingRegistrationId = prefs.getString(_pendingPaymentKey);
      
      if (pendingRegistrationId == null) return;
      
      final registrationId = int.tryParse(pendingRegistrationId);
      if (registrationId == null || registrationId != widget.registration.id) {
        return;
      }

      final res = await api.dio.get('/register-service/$registrationId');
      final data = res.data;
      final paymentStatus = data['paymentStatus'] as String?;
      
      if (paymentStatus == 'PAID') {
        await prefs.remove(_pendingPaymentKey);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Thanh toán đã hoàn tất'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); 
        }
      } 
      else if (paymentStatus == 'UNPAID') {
        if (mounted) {
          final shouldPay = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Thanh toán chưa hoàn tất'),
              content: Text(
                'Đăng ký xe #$registrationId chưa được thanh toán.\n\n'
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
            await _payRegistration(widget.registration);
          } else {
            await prefs.remove(_pendingPaymentKey);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi check pending payment: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingPaymentKey);
      } catch (_) {}
    }
  }

  void _listenForPaymentResult() {
    _paymentSub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;
      
      if (uri.scheme == 'qhomeapp' && uri.host == 'vnpay-registration-result') {
        final registrationId = uri.queryParameters['registrationId'];
        final responseCode = uri.queryParameters['responseCode'];

        if (!mounted) return;

        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_pendingPaymentKey);
        } catch (e) {
          debugPrint('❌ Lỗi xóa pending payment: $e');
        }

        if (responseCode == '00') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Thanh toán thành công!'),
              backgroundColor: Colors.green,
            ),
          );
          if (mounted) {
            Navigator.pop(context, true);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Thanh toán thất bại'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    });
  }

  String formatDate(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('dd/MM/yyyy HH:mm').format(dt.toLocal());
  }

  String _makeFullImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return '';
    if (imageUrl.startsWith('http')) return imageUrl;
    final base = ApiClient.BASE_URL.replaceFirst(RegExp(r'/api$'), '');
    return base + imageUrl;
  }

  Widget _buildShimmerPlaceholder({double width = 120, double height = 100}) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String? status) {
    Color color;
    IconData icon;
    String label = status ?? 'Đang xử lý';

    switch (status) {
      case 'APPROVED':
        color = Colors.green.shade600;
        icon = Icons.check_circle_outline;
        label = 'Đã duyệt';
        break;
      case 'REJECTED':
        color = Colors.red.shade600;
        icon = Icons.cancel_outlined;
        label = 'Từ chối';
        break;
      default:
        color = Colors.orange.shade600;
        icon = Icons.hourglass_bottom;
        label = 'Đang chờ';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStatusChip(String? paymentStatus) {
    Color color;
    IconData icon;
    String label;

    if (paymentStatus == 'PAID') {
      color = Colors.green.shade600;
      icon = Icons.payment;
      label = 'Đã thanh toán';
    } else {
      color = Colors.red.shade600;
      icon = Icons.payment_outlined;
      label = 'Chưa thanh toán';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _payRegistration(RegisterServiceRequest registration) async {
    if (registration.id == null) return;

    try {
      log('💳 [RegisterDetail] Tạo VNPAY URL cho registration: ${registration.id}');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingPaymentKey, registration.id.toString());
      
      final res = await api.dio.post('/register-service/${registration.id}/vnpay-url');
      
      if (res.statusCode != 200) {
        await prefs.remove(_pendingPaymentKey);
        throw Exception(res.data['message'] ?? 'Lỗi tạo URL thanh toán');
      }

      final paymentUrl = res.data['paymentUrl'] as String;
      
      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await prefs.remove(_pendingPaymentKey);
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
      log('❌ [RegisterDetail] Lỗi thanh toán: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingPaymentKey);
      } catch (_) {}
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi thanh toán: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _detailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, color: Colors.black87))),
          Expanded(
              flex: 3,
              child: Text(value?.isNotEmpty == true ? value! : '—',
                  style: const TextStyle(color: Colors.black54))),
        ],
      ),
    );
  }

  void _showImageDetail(BuildContext context, List<String> images, int initialIndex) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final pageController = PageController(initialPage: initialIndex);
        int currentIndex = initialIndex;
        
        return PopScope(
          canPop: true,
          onPopInvoked: (didPop) {
            if (!didPop && Navigator.canPop(dialogContext)) {
              Navigator.of(dialogContext).pop();
            }
          },
          child: StatefulBuilder(
            builder: (context, setState) {
              return Dialog(
                backgroundColor: Colors.black87,
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: pageController,
                      itemCount: images.length,
                      onPageChanged: (index) {
                        setState(() => currentIndex = index);
                      },
                      itemBuilder: (context, index) {
                        return InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 3.0,
                          child: Center(
                            child: CachedNetworkImage(
                              imageUrl: _makeFullImageUrl(images[index]),
                              fit: BoxFit.contain,
                              placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white),
                              errorWidget: (context, url, error) => const Icon(Icons.error_outline, color: Colors.white, size: 48),
                            ),
                          ),
                        );
                      },
                    ),
                    Positioned(
                      top: 40,
                      right: 20,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${currentIndex + 1} / ${images.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.registration;
    final images = s.imageUrls ?? [];
    
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF26A69A),
          title: const Text('Chi tiết thẻ xe'),
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              s.licensePlate ?? 'Không rõ biển số',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _buildStatusChip(s.status),
                _buildPaymentStatusChip(s.paymentStatus),
              ],
            ),
            if (s.paymentStatus == 'UNPAID') ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _payRegistration(s),
                  icon: const Icon(Icons.payment),
                  label: const Text('Thanh toán (30.000 VNĐ)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF26A69A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
            const Divider(height: 30),
            _detailRow('Hãng xe', s.vehicleBrand),
            _detailRow('Màu xe', s.vehicleColor),
            _detailRow('Loại phương tiện', s.vehicleType),
            _detailRow('Ghi chú', s.note),
            _detailRow('Ngày tạo', formatDate(s.createdAt)),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Ảnh xe',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 250,
                child: PageView.builder(
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () {
                        _showImageDetail(context, images, index);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: _makeFullImageUrl(images[index]),
                            fit: BoxFit.contain,
                            placeholder: (context, url) =>
                                _buildShimmerPlaceholder(width: double.infinity, height: 250),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${images.length} ảnh - Vuốt để xem thêm, chạm để xem chi tiết',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

