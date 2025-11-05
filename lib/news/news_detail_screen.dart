import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../auth/api_client.dart';
import '../models/resident_news.dart';

class NewsDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? news;
  final ResidentNews? residentNews;
  final String? id;

  const NewsDetailScreen({
    super.key,
    this.news,
    this.residentNews,
    this.id,
  }) : assert(
          news != null || residentNews != null || id != null,
          'Either news map, residentNews, or id must be provided',
        );

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  ResidentNews? _residentNews;
  bool _loading = true;

  static const Color _primaryColor = Color(0xFF26A69A);

  @override
  void initState() {
    super.initState();
    if (widget.residentNews != null) {
      _residentNews = widget.residentNews;
      _loading = false;
    } else if (widget.news != null) {
      _residentNews = _parseFromMap(widget.news!);
      _loading = false;
    } else {
      _fetchById(widget.id!);
    }
  }

  ResidentNews? _parseFromMap(Map<String, dynamic> map) {
    try {
      return ResidentNews.fromJson(map);
    } catch (e) {
      debugPrint('⚠️ Error parsing news from map: $e');
      return null;
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

  Future<void> _fetchById(String id) async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient().dio.get('/news/$id');
      final data = Map<String, dynamic>.from(res.data as Map<String, dynamic>);
      _residentNews = ResidentNews.fromJson(data);
    } catch (e) {
      debugPrint('⚠️ Fetch news failed: $e');
      // Create a dummy news object for error state
      _residentNews = ResidentNews(
        id: id,
        title: 'Không thể tải nội dung',
        summary: 'Đã có lỗi khi tải nội dung tin',
        bodyHtml: '',
        status: '',
        displayOrder: 0,
        viewCount: 0,
        images: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Chưa có';
    try {
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (_) {
      return 'Không hợp lệ';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_residentNews == null) {
      return const Scaffold(
        body: Center(child: Text('Không tìm thấy nội dung')),
      );
    }

    final news = _residentNews!;
    final String title = news.title;
    final String summary = news.summary;
    final String status = news.status;
    final String? rawCoverImageUrl = news.coverImageUrl;
    final String? finalCoverImageUrl = rawCoverImageUrl != null
        ? (rawCoverImageUrl.startsWith('http') ? rawCoverImageUrl : ApiClient.fileUrl(rawCoverImageUrl))
        : null;
    final bool showImage = _isValidImageUrl(finalCoverImageUrl);
    final DateTime? publishAt = news.publishAt;
    // Sort images by sortOrder
    final List<NewsImage> images = List.from(news.images)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

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
                tag: 'news_${news.id}',
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (showImage && finalCoverImageUrl != null)
                      CachedNetworkImage(
                        imageUrl: finalCoverImageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) {
                          debugPrint('⚠️ Image loading error: $error');
                          return Container(color: _primaryColor);
                        },
                        placeholder: (context, url) => Container(
                          color: _primaryColor,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
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
                  // Status chip
                  if (status.isNotEmpty)
                    Chip(
                      label: Text(
                        status,
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.teal,
                    ),
                  if (status.isNotEmpty) const SizedBox(height: 16),
                  
                  // Summary
                  if (summary.isNotEmpty) ...[
                    Text(
                      'Tóm tắt',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      summary,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Body HTML
                  if (news.bodyHtml.isNotEmpty) ...[
                    Text(
                      'Nội dung',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Html(
                      data: news.bodyHtml,
                      style: {
                        'body': Style(
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                        ),
                        'p': Style(
                          fontSize: FontSize(16),
                          lineHeight: const LineHeight(1.6),
                          color: Colors.black87,
                          margin: Margins.only(bottom: 12),
                        ),
                        'h2': Style(
                          fontSize: FontSize(20),
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          margin: Margins.only(bottom: 12, top: 16),
                        ),
                        'ul': Style(
                          margin: Margins.only(bottom: 12),
                        ),
                        'li': Style(
                          fontSize: FontSize(16),
                          lineHeight: const LineHeight(1.6),
                          color: Colors.black87,
                          margin: Margins.only(bottom: 6),
                        ),
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Images gallery
                  if (images.isNotEmpty) ...[
                    Text(
                      'Hình ảnh',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...images.map((img) => _buildImageItem(img)),
                    const SizedBox(height: 24),
                  ],
                  
                  // Divider
                  Divider(color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  
                  // Publish date
                  _infoRow(Icons.schedule, 'Ngày phát hành', _formatDate(publishAt)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageItem(NewsImage image) {
    final String? imageUrl = image.url.startsWith('http')
        ? image.url
        : ApiClient.fileUrl(image.url);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: CachedNetworkImage(
              imageUrl: imageUrl ?? '',
              fit: BoxFit.cover,
              height: 200,
              placeholder: (context, url) => Container(
                height: 200,
                color: Colors.grey[200],
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                height: 200,
                color: Colors.grey[300],
                child: const Icon(
                  Icons.broken_image,
                  size: 48,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          if (image.caption != null && image.caption!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                image.caption!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
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