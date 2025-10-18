import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';

class RegisterServiceListScreen extends StatefulWidget {
  const RegisterServiceListScreen({super.key});
  @override
  State<RegisterServiceListScreen> createState() => _RegisterServiceListScreenState();
}

class _RegisterServiceListScreenState extends State<RegisterServiceListScreen> {
  final ApiClient api = ApiClient();
  List<dynamic> list = [];
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
      if (res.data is List) {
        list = List.from(res.data);
      } else if (res.data is Map && res.data['data'] != null) {
        list = List.from(res.data['data']);
      }
    } catch (e) {
      list = [];
    } finally {
      setState(() => loading = false);
    }
  }

  String formatDate(String? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal(); // Chuyển sang giờ máy (Asia/Ho_Chi_Minh)
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : list.isEmpty
                ? const Center(child: Text('Không có dữ liệu'))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final s = Map<String, dynamic>.from(list[i]);
                      final type = s['serviceType'] ?? s['serviceCode'] ?? 'Không rõ';
                      final note = s['note'] ?? '';
                      final status = s['status'] ?? 'PENDING';
                      final created = formatDate(s['createdAt']?.toString());

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          title: Text(type, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (note.isNotEmpty) Text('Ghi chú: $note'),
                              Text('Trạng thái: $status'),
                              Text('Ngày đăng ký: $created'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}