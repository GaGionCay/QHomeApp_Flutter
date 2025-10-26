import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../auth/api_client.dart';
import '../common/main_shell.dart';

class NewsDetailScreen extends StatefulWidget {
  final int id;
  const NewsDetailScreen({super.key, required this.id});

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  Map<String, dynamic>? news;
  bool loading = true;
  double scrollOffset = 0.0;

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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              // Bỏ ListTile tải về máy
              // ListTile(
              //   leading: const Icon(Icons.download, color: Color(0xFF26A69A)),
              //   title: const Text('Tải về máy'),
              //   onTap: () async { ... },
              // ),
              ListTile(
                leading: const Icon(Icons.visibility, color: Color(0xFF26A69A)),
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
          ),
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

    final attachments = news!['attachments'] as List<dynamic>? ?? [];
    final dateStr = news!['createdDate'] != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(news!['createdDate']))
        : '';
    final thumbnail =
        news!['thumbnailUrl'] ?? news!['image'] ?? news!['thumbnail'] ?? null;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      body: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          setState(() {
            scrollOffset = scrollInfo.metrics.pixels;
          });
          return false;
        },
        child: CustomScrollView(
          slivers: [
            // 🖼 Banner có hiệu ứng co giãn khi cuộn
            SliverAppBar(
              expandedHeight: thumbnail != null ? 180 : kToolbarHeight + 10,
              pinned: true,
              stretch: true,
              backgroundColor: const Color(0xFF26A69A),
              foregroundColor: Colors.white,
              elevation: 1,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding:
                    const EdgeInsetsDirectional.only(start: 16, bottom: 16),
                title: AnimatedOpacity(
                  opacity: scrollOffset > 100 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    news!['title'] ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                background: thumbnail != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            ApiClient.fileUrl(thumbnail),
                            fit: BoxFit.cover,
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.25),
                                  Colors.black.withOpacity(0.55),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 28,
                            child: Text(
                              news!['title'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    blurRadius: 6,
                                    color: Colors.black38,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(color: Colors.transparent),
              ),
            ),

            // 📄 Nội dung chi tiết
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🧭 Ngày đăng
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          dateStr,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // 📖 Nội dung
                    Text(
                      news!['content'] ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 📎 File đính kèm
                    if (attachments.isNotEmpty) ...[
                      const Text(
                        "Tệp đính kèm",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Color(0xFF004D40),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...attachments.map((a) {
                        final attachment = NewsAttachmentDto.fromJson(a);
                        final ext =
                            attachment.filename.split('.').last.toLowerCase();
                        final icon = _iconForExtension(ext);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.teal.withOpacity(0.15),
                              child: Icon(icon, color: const Color(0xFF26A69A)),
                            ),
                            title: Text(
                              attachment.filename,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios,
                                size: 14, color: Colors.grey),
                            onTap: () => _handleAttachment(attachment.url),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForExtension(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'xlsx':
      case 'xls':
        return Icons.table_chart;
      default:
        return Icons.attach_file;
    }
  }
}
