import 'package:flutter/material.dart';
import '../auth/api_client.dart';

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
      final res = await api.dio.get('/news/${widget.id}');
      data = Map<String, dynamic>.from(res.data);
    } catch (e) {}
    setState(() => loading = false);
  }

  Future<void> _markRead() async {
    try {
      await api.dio.post('/news/${widget.id}/read');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết tin')),
      body: loading ? const Center(child: CircularProgressIndicator()) : data == null ? const Center(child: Text('Không tìm thấy')) : Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(data!['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(data!['createdAt'] ?? ''),
            const SizedBox(height: 16),
            Text(data!['content'] ?? ''),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: () { _markRead(); Navigator.pop(context); }, child: const Text('Đánh dấu đã đọc')),
          ]),
        ),
      ),
    );
  }
}
