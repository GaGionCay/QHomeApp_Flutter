import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import '../models/register_service_request.dart';

class RegisterServiceListScreen extends StatefulWidget {
  const RegisterServiceListScreen({super.key});
  @override
  State<RegisterServiceListScreen> createState() => _RegisterServiceListScreenState();
}

class _RegisterServiceListScreenState extends State<RegisterServiceListScreen> {
  final ApiClient api = ApiClient();
  List<RegisterServiceRequest> list = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final res = await api.dio.get('/register-service/me');
      final data = res.data;
      if (data is List) {
        list = RegisterServiceRequest.listFromJson(data);
      } else if (data is Map && data['data'] is List) {
        list = RegisterServiceRequest.listFromJson(data['data']);
      } else {
        list = [];
      }
    } catch (e) {
      list = [];
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

  @override
  Widget build(BuildContext context) {
    // Xóa Scaffold, để body trực tiếp được MainShell hiển thị
    return RefreshIndicator(
      onRefresh: _load,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(child: Text('Không có dữ liệu'))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (c, i) {
                    final s = list[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                            fontWeight: FontWeight.bold))),
                                Text(s.status ?? 'PENDING',
                                    style: const TextStyle(color: Colors.orange)),
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
                                  children: s.imageUrls!
                                      .map((url) => Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: Image.network(
                                              _makeFullImageUrl(url),
                                              width: 120,
                                              fit: BoxFit.cover,
                                            ),
                                          ))
                                      .toList(),
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
    );
  }
}

