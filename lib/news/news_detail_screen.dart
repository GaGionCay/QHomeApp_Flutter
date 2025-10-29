import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';

class NewsDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? news;
  final String? id;

  const NewsDetailScreen({super.key, this.news, this.id})
      : assert(news != null || id != null, 'Either news map or id must be provided');

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  Map<String, dynamic>? _news;
  bool _loading = true;

  static const Color _primaryColor = Color(0xFF26A69A); 

  @override
  void initState() {
    super.initState();
    if (widget.news != null) {
      _news = _normalizeNews(widget.news!);
      _loading = false;
    } else {
      _fetchById(widget.id!);
    }
  }
  bool _isValidImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final String lower = url.toLowerCase();
    if (!lower.startsWith('http')) return false;
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  Map<String, dynamic> _normalizeNews(Map<String, dynamic> map) {
    return {
      'id': map['id']?.toString() ?? map['newsUuid']?.toString() ?? '',
      'title': map['title'] ?? map['headline'] ?? '',
      'summary': map['summary'] ?? map['body'] ?? map['content'] ?? '',
      'status': map['status'] ?? '',
      'coverImageUrl': map['coverImageUrl'] ?? map['image'] ?? '',
      'publishAt': map['publishAt'] ?? map['publishAtIso'] ?? '',
      'receivedAt': map['receivedAt'] ?? '',
    };
  }

  Future<void> _fetchById(String id) async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient().dio.get('/news/$id');
      final data = Map<String, dynamic>.from(res.data as Map<String, dynamic>);
      _news = _normalizeNews(data);
    } catch (e) {
      debugPrint('⚠️ Fetch news failed: $e');
      _news = {
        'id': id,
        'title': 'Không thể tải nội dung',
        'summary': 'Đã có lỗi khi tải nội dung tin',
        'status': '',
        'coverImageUrl': '',
        'publishAt': '',
        'receivedAt': '',
      };
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final news = _news ?? {};
    final String title = news['title'] ?? '';
    final String summary = news['summary'] ?? '';
    final String status = news['status'] ?? '';
    final String rawCoverImageUrl = news['coverImageUrl'] ?? '';

    final String finalCoverImageUrl = ApiClient.fileUrl(rawCoverImageUrl);
    final bool showImage = _isValidImageUrl(finalCoverImageUrl);

    final String publishAt = news['publishAt'] ?? '';
    final String receivedAt = news['receivedAt'] ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: showImage ? 260 : 100,
            backgroundColor: _primaryColor,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'news_${news['id'] ?? news['newsUuid']}',
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (showImage)
                      Image.network(
                        finalCoverImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                            debugPrint('⚠️ Image loading error: $error');
                            return Container(color: _primaryColor);
                        },
                      )
                    else
                      Container(color: _primaryColor), 
                      
                    Container(
                      color: Colors.black.withOpacity(0.35),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 30,
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              blurRadius: 8,
                              color: Colors.black54,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Chip(
                    label: Text(
                      status,
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: Colors.teal,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    summary,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  _infoRow(Icons.schedule, 'Ngày phát hành', _formatDate(publishAt)),
                  const SizedBox(height: 6),
                  _infoRow(Icons.mark_email_read, 'Nhận lúc', _formatDate(receivedAt)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.grey[800],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: Colors.grey[700]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}