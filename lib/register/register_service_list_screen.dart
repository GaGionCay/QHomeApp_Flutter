import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:animations/animations.dart';
import 'dart:developer';
import '../auth/api_client.dart';
import '../models/register_service_request.dart';
import '../bills/vnpay_payment_screen.dart';

class RegisterServiceListScreen extends StatefulWidget {
  const RegisterServiceListScreen({super.key});

  @override
  State<RegisterServiceListScreen> createState() =>
      _RegisterServiceListScreenState();
}

class _RegisterServiceListScreenState extends State<RegisterServiceListScreen>
    with SingleTickerProviderStateMixin {
  final ApiClient api = ApiClient();

  List<RegisterServiceRequest> list = [];
  bool loading = false;

  int currentPage = 1;
  final int pageSize = 10;
  int totalPages = 1;

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _load(page: currentPage);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _load({required int page}) async {
    setState(() => loading = true);
    try {
      final res =
          await api.dio.get('/register-service/me/paginated', queryParameters: {
        'page': page,
        'size': pageSize,
      });

      final data = res.data;
      List<dynamic> items = [];
      if (data is Map && data['data'] is List) {
        items = data['data'];
      }

      list = RegisterServiceRequest.listFromJson(items);

      if (data is Map) {
        totalPages = data['totalPages'] ?? 1;
        currentPage = data['currentPage'] ?? 1;
      }

      _animController.forward(from: 0);
    } catch (e) {
      debugPrint('❌ Lỗi load danh sách: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _refresh() async => _load(page: currentPage);

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
      log('💳 [RegisterList] Tạo VNPAY URL cho registration: ${registration.id}');
      
      // Tạo VNPAY payment URL cho registration đã tồn tại
      final res = await api.dio.post('/register-service/${registration.id}/vnpay-url');
      
      if (res.statusCode != 200) {
        throw Exception(res.data['message'] ?? 'Lỗi tạo URL thanh toán');
      }

      final paymentUrl = res.data['paymentUrl'] as String;
      
      // Mở VNPAY payment screen
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VnpayPaymentScreen(
            paymentUrl: paymentUrl,
            billId: 0,
            registrationId: registration.id,
          ),
        ),
      );

      // Refresh danh sách sau khi thanh toán
      if (mounted) {
        if (result is Map && result['responseCode'] == '00') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Thanh toán thành công!'),
              backgroundColor: Colors.green,
            ),
          );
          _refresh();
        } else if (result == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Thanh toán đã bị hủy'),
              backgroundColor: Colors.orange,
            ),
          );
          _refresh();
        }
      }
    } catch (e) {
      log('❌ [RegisterList] Lỗi thanh toán: $e');
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

  void _goToPage(int page) {
    if (page < 1 || page > totalPages) return;
    _load(page: page);
  }

  @override
  Widget build(BuildContext context) {

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        // Khi hardware back button được nhấn từ register_service_list_screen,
        // hiển thị dialog hỏi có muốn thoát ứng dụng không
        if (!didPop && mounted) {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Thoát ứng dụng'),
              content: const Text('Bạn có muốn thoát ứng dụng không?'),
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
          
          if (shouldExit == true && mounted) {
            // Thoát ứng dụng
            // Import dart:io để sử dụng exit
            // Cần import 'dart:io' nếu chưa có
            Navigator.of(context).popUntil((route) => route.isFirst);
            // Hoặc có thể dùng SystemNavigator.pop() để thoát app
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          elevation: 0,
          title: const Text('Danh sách thẻ xe'),
          backgroundColor: const Color(0xFF26A69A),
          foregroundColor: Colors.white,
        ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: Colors.teal,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: loading
              ? ListView.builder(
                  key: const ValueKey('loading'),
                  padding: const EdgeInsets.all(16),
                  itemCount: 6,
                  itemBuilder: (context, i) =>
                      _buildShimmerPlaceholder(width: double.infinity, height: 140),
                )
              : list.isEmpty
                  ? const Center(
                      key: ValueKey('empty'),
                      child: Text(
                        'Chưa có thẻ xe nào được đăng ký.',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      key: const ValueKey('list'),
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final item = list[i];
                        final anim = CurvedAnimation(
                          parent: _animController,
                          curve: Interval((i / list.length), 1.0,
                              curve: Curves.easeOutCubic),
                        );

                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.2),
                              end: Offset.zero,
                            ).animate(anim),
                            child: InkWell(
                              onTap: () {
                                // Dùng Navigator.push thay vì OpenContainer để control navigation tốt hơn
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _buildDetailPage(item),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: _buildCard(item),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ),
      bottomNavigationBar: !loading && totalPages > 1
          ? Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.first_page),
                    onPressed: currentPage > 1 ? () => _goToPage(1) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed:
                        currentPage > 1 ? () => _goToPage(currentPage - 1) : null,
                  ),
                  Text('$currentPage / $totalPages',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: currentPage < totalPages
                        ? () => _goToPage(currentPage + 1)
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.last_page),
                    onPressed: currentPage < totalPages
                        ? () => _goToPage(totalPages)
                        : null,
                  ),
                ],
              ),
            )
          : null,
      ),
    );
  }

  Widget _buildCard(RegisterServiceRequest s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
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
            s.licensePlate ?? 'Không rõ biển số',
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text('${s.vehicleBrand ?? '—'} - ${s.vehicleColor ?? '—'}'),
          const SizedBox(height: 4),
          // Sử dụng Wrap để tránh overflow khi màn hình nhỏ
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildStatusChip(s.status),
              _buildPaymentStatusChip(s.paymentStatus),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Đăng ký: ${formatDate(s.createdAt)}',
            style: const TextStyle(
                fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPage(RegisterServiceRequest s) {
    final images = s.imageUrls ?? [];
    
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        // Khi hardware back button được nhấn từ detail page,
        // không pop về register_service_screen nữa mà coi như muốn thoát app
        if (!didPop && mounted) {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Thoát ứng dụng'),
              content: const Text('Bạn có muốn thoát ứng dụng không?'),
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
          
          if (shouldExit == true && mounted) {
            // Pop detail page và về list screen trước
            Navigator.pop(context);
            // Sau đó thoát ứng dụng
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            });
          }
        }
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
            // Hiển thị button thanh toán nếu chưa thanh toán
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
            // Hiển thị ảnh ở dưới với PageView để swipe
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
                        // Xem chi tiết ảnh khi tap
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
              // Indicator để hiển thị số ảnh
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
}
