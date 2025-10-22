import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../auth/api_client.dart';
import '../common/main_shell.dart'; // để dùng NewsAttachmentDto

class NewsDetailScreen extends StatefulWidget {
  final int id;
  const NewsDetailScreen({super.key, required this.id});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  Map<String, dynamic>? news;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchNews();
  }

  Future<void> _fetchNews() async {
    try {
      final client = ApiClient();
      final res = await client.dio.get('/news/${widget.id}');
      setState(() {
        news = res.data;
        loading = false;
      });
      await client.dio.post('/news/${widget.id}/read');
    } catch (e) {
      debugPrint('❌ Lỗi tải chi tiết: $e');
      setState(() => loading = false);
    }
  }

  Future<void> _handleAttachment(String url) async {
    final filename = url.split('/').last;
    final fullUrl = ApiClient.fileUrl(url);

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Tải về máy'),
              onTap: () async {
                Navigator.pop(context);
                final dir = await getApplicationDocumentsDirectory();
                final filePath = '${dir.path}/$filename';
                final response = await http.get(Uri.parse(fullUrl));
                final file = File(filePath);
                await file.writeAsBytes(response.bodyBytes);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã tải về $filename')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text('Xem trực tiếp'),
              onTap: () async {
                Navigator.pop(context);
                final tempDir = await getTemporaryDirectory();
                final filePath = '${tempDir.path}/$filename';
                final response = await http.get(Uri.parse(fullUrl));
                final file = File(filePath);
                await file.writeAsBytes(response.bodyBytes);
                await OpenFile.open(filePath);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (news == null) {
      return const Scaffold(
        body: Center(child: Text('Không tìm thấy tin')),
      );
    }

    final attachmentsData = news!['attachments'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(news!['title'] ?? '')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(news!['summary'] ?? '', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            Text(news!['content'] ?? ''),
            const SizedBox(height: 20),
            if (attachmentsData.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: attachmentsData.map((a) {
                  final attachment = NewsAttachmentDto.fromJson(a);
                  return TextButton.icon(
                    icon: const Icon(Icons.attach_file),
                    label: Text(attachment.filename),
                    onPressed: () => _handleAttachment(attachment.url),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
