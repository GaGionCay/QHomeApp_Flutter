import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import 'package:intl/intl.dart';

class NewsDetailScreen extends StatefulWidget {
  final int id;
  const NewsDetailScreen({required this.id, super.key});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  final ApiClient api = ApiClient();
  Map<String, dynamic>? data;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      // ✅ Gọi API lấy tin
      final res = await api.dio.get('/news/${widget.id}');
      data = Map<String, dynamic>.from(res.data);

      // ✅ Nếu tin chưa đọc thì đánh dấu luôn
      if (data?['isRead'] != true) {
        await api.dio.post('/news/${widget.id}/read');
        data?['isRead'] = true;
      }
    } catch (e) {
      // ignore
    } finally {
      setState(() => loading = false);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết tin')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : data == null
              ? const Center(child: Text('Không tìm thấy tin tức'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data!['title'] ?? '',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (data!['createdAt'] != null)
                          Text(
                            _formatDate(data!['createdAt']),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          data!['content'] ?? '',
                          style: const TextStyle(fontSize: 16, height: 1.4),
                        ),
                        if (data!['attachments'] != null &&
                            (data!['attachments'] as List).isNotEmpty)
                          ...[
                            const SizedBox(height: 20),
                            const Text(
                              'Tệp đính kèm:',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: (data!['attachments'] as List)
                                  .map<Widget>((att) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          att['filename'] ?? '',
                                          style: const TextStyle(
                                              color: Colors.blueAccent),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
    );
  }
}
