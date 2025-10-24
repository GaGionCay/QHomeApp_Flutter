import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:animations/animations.dart';
import '../auth/api_client.dart';
import '../models/register_service_request.dart';

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

  void _goToPage(int page) {
    if (page < 1 || page > totalPages) return;
    _load(page: page);
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Scaffold(
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
                            child: OpenContainer(
                              transitionDuration:
                                  const Duration(milliseconds: 400),
                              closedElevation: 3,
                              closedShape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              closedColor: Colors.white,
                              openColor: Colors.white,
                              closedBuilder: (context, open) => _buildCard(item),
                              openBuilder: (context, close) =>
                                  _buildDetailPage(item),
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
      child: Row(
        children: [
          Hero(
            tag: 'vehicle-${s.id}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: _makeFullImageUrl(s.imageUrls?.first ?? ''),
                width: 100,
                height: 80,
                fit: BoxFit.cover,
                placeholder: (c, _) =>
                    _buildShimmerPlaceholder(width: 100, height: 80),
                errorWidget: (c, _, __) => Container(
                  width: 100,
                  height: 80,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.directions_car, color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
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
                _buildStatusChip(s.status),
                const SizedBox(height: 6),
                Text(
                  'Đăng ký: ${formatDate(s.createdAt)}',
                  style: const TextStyle(
                      fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDetailPage(RegisterServiceRequest s) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF26A69A),
        title: const Text('Chi tiết thẻ xe'),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Hero(
            tag: 'vehicle-${s.id}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: _makeFullImageUrl(s.imageUrls?.first ?? ''),
                height: 200,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    _buildShimmerPlaceholder(width: double.infinity, height: 200),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            s.licensePlate ?? 'Không rõ biển số',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
          ),
          const SizedBox(height: 8),
          _buildStatusChip(s.status),
          const Divider(height: 30),
          _detailRow('Hãng xe', s.vehicleBrand),
          _detailRow('Màu xe', s.vehicleColor),
          _detailRow('Loại phương tiện', s.vehicleType),
          _detailRow('Ghi chú', s.note),
          _detailRow('Ngày tạo', formatDate(s.createdAt)),
          const SizedBox(height: 20),
          if (s.imageUrls != null && s.imageUrls!.length > 1)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: s.imageUrls!.skip(1).map((url) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: _makeFullImageUrl(url),
                    width: 120,
                    height: 100,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        _buildShimmerPlaceholder(width: 120, height: 100),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
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
