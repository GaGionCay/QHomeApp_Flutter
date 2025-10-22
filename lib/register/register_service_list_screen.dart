import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../auth/api_client.dart';
import '../models/register_service_request.dart';

class RegisterServiceListScreen extends StatefulWidget {
  const RegisterServiceListScreen({super.key});

  @override
  State<RegisterServiceListScreen> createState() =>
      _RegisterServiceListScreenState();
}

class _RegisterServiceListScreenState extends State<RegisterServiceListScreen> {
  final ApiClient api = ApiClient();

  List<RegisterServiceRequest> list = [];
  bool loading = false;

  int currentPage = 1;
  final int pageSize = 10;
  int totalPages = 1;

  @override
  void initState() {
    super.initState();
    _load(page: currentPage);
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
    } catch (e) {
      debugPrint('❌ Lỗi load danh sách: $e');
    } finally {
      setState(() => loading = false);
    }
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
        color: Colors.white,
      ),
    );
  }

  void _goToPage(int page) {
    if (page < 1 || page > totalPages) return;
    _load(page: page);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Danh sách thẻ xe đã đăng ký')),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const Center(child: Text('Không có dữ liệu'))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (c, i) {
                          final s = list[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          s.serviceType ?? 'VEHICLE_REGISTRATION',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        s.status ?? 'PENDING',
                                        style: TextStyle(
                                          color: s.status == 'APPROVED'
                                              ? Colors.green
                                              : s.status == 'REJECTED'
                                                  ? Colors.red
                                                  : Colors.orange,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (s.licensePlate?.isNotEmpty ?? false)
                                    Text('Biển số: ${s.licensePlate}'),
                                  if (s.vehicleBrand?.isNotEmpty ?? false)
                                    Text('Hãng: ${s.vehicleBrand}'),
                                  if (s.vehicleColor?.isNotEmpty ?? false)
                                    Text('Màu: ${s.vehicleColor}'),
                                  if (s.vehicleType?.isNotEmpty ?? false)
                                    Text('Loại: ${s.vehicleType}'),
                                  if (s.note?.isNotEmpty ?? false)
                                    Text('Ghi chú: ${s.note}'),
                                  const SizedBox(height: 8),
                                  if (s.imageUrls != null && s.imageUrls!.isNotEmpty)
                                    SizedBox(
                                      height: 100,
                                      child: ListView(
                                        scrollDirection: Axis.horizontal,
                                        children: s.imageUrls!.map((url) {
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 8),
                                            child: CachedNetworkImage(
                                              imageUrl: _makeFullImageUrl(url),
                                              width: 120,
                                              height: 100,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) =>
                                                  _buildShimmerPlaceholder(
                                                      width: 120, height: 100),
                                              errorWidget: (context, url, error) =>
                                                  Container(
                                                width: 120,
                                                height: 100,
                                                color: Colors.grey.shade200,
                                                child: const Icon(Icons.broken_image,
                                                    color: Colors.red),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Text('Ngày đăng ký: ${formatDate(s.createdAt)}'),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          // Pagination controls
          if (!loading && totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                      icon: const Icon(Icons.first_page),
                      onPressed: currentPage > 1 ? () => _goToPage(1) : null),
                  IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: currentPage > 1
                          ? () => _goToPage(currentPage - 1)
                          : null),
                  Text('$currentPage / $totalPages'),
                  IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: currentPage < totalPages
                          ? () => _goToPage(currentPage + 1)
                          : null),
                  IconButton(
                      icon: const Icon(Icons.last_page),
                      onPressed: currentPage < totalPages
                          ? () => _goToPage(totalPages)
                          : null),
                ],
              ),
            )
        ],
      ),
    );
  }
}
