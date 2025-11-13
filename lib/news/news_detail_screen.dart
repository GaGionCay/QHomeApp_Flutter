import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../core/event_bus.dart';
import '../models/resident_news.dart';
import '../profile/profile_service.dart';
import '../theme/app_colors.dart';
import 'resident_service.dart';
import 'news_read_store.dart';

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
  String? _residentId;
  final AppEventBus _bus = AppEventBus();

  final ApiClient _api = ApiClient();
  late final ContractService _contractService;

  @override
  void initState() {
    super.initState();
    _contractService = ContractService(_api);
    if (widget.residentNews != null) {
      _residentNews = widget.residentNews;
      _loading = false;
      _scheduleMarkRead();
    } else if (widget.news != null) {
      _residentNews = _parseFromMap(widget.news!);
      _loading = false;
      _scheduleMarkRead();
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
    if (mounted) {
      setState(() => _loading = true);
    } else {
      _loading = true;
    }
    ResidentNews? loadedNews;
    try {
      final residentService = ResidentService();
      final residentId = await _getResidentId();
      if (residentId != null && residentId.isNotEmpty) {
        final allNews = await residentService.getResidentNews(residentId, size: 1000);
        loadedNews = allNews.firstWhere(
          (n) => n.id == id,
          orElse: () => throw Exception('News not found'),
        );
      } else {
        throw Exception('Resident ID not found');
      }
    } catch (e) {
      debugPrint('⚠️ Fetch news failed: $e');
      loadedNews ??= ResidentNews(
        id: id,
        title: 'Không thể tải nội dung',
        summary: 'Đã có lỗi khi tải nội dung tin',
        bodyHtml: '',
        status: '',
        displayOrder: 0,
        viewCount: 0,
        images: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _residentNews = loadedNews;
        _loading = false;
      });
      if (_residentNews != null) {
        _scheduleMarkRead();
      }
    }
  }

  void _scheduleMarkRead() {
    if (!mounted || _residentNews == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markCurrentAsRead();
    });
  }

  Future<void> _markCurrentAsRead() async {
    if (_residentNews == null) return;
    final residentId = await _getResidentId();
    if (residentId == null || residentId.isEmpty) return;
    final updated = await NewsReadStore.markRead(residentId, _residentNews!.id);
    if (updated) {
      _bus.emit('news_read_status_updated', _residentNews!.id);
    }
  }

  Future<String?> _getResidentId() async {
    if (_residentId != null && _residentId!.isNotEmpty) {
      return _residentId;
    }
    try {
      final profile = await ProfileService(_api.dio).getProfile();
      final profileResident = profile['residentId']?.toString();
      if (profileResident != null && profileResident.isNotEmpty) {
        _residentId = profileResident;
        return _residentId;
      }

      final units = await _contractService.getMyUnits();
      for (final unit in units) {
        final candidate = unit.primaryResidentId?.toString();
        if (candidate != null && candidate.isNotEmpty) {
          _residentId = candidate;
          return _residentId;
        }
      }

      if (units.isNotEmpty) {
        final fallback = units.firstWhere(
          (unit) => (unit.primaryResidentId ?? '').isNotEmpty,
          orElse: () => units.first,
        );
        if ((fallback.primaryResidentId ?? '').isNotEmpty) {
          _residentId = fallback.primaryResidentId;
          return _residentId;
        }
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ Error getting residentId: $e');
      return null;
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
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: const Center(
          child: CupertinoActivityIndicator(radius: 16),
        ),
      );
    }

    final news = _residentNews;
    if (news == null) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.info_circle,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Không tìm thấy nội dung',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    final String summary = news.summary;
    final String status = news.status;
    final String? rawCoverImageUrl = news.coverImageUrl;
    final String? finalCoverImageUrl = rawCoverImageUrl != null
        ? (rawCoverImageUrl.startsWith('http')
            ? rawCoverImageUrl
            : ApiClient.fileUrl(rawCoverImageUrl))
        : null;
    final bool showImage = _isValidImageUrl(finalCoverImageUrl);
    final DateTime? publishAt = news.publishAt;
    final List<NewsImage> images = List.from(news.images)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final backgroundGradient = theme.brightness == Brightness.dark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF040D1F),
              Color(0xFF0D1E33),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF4F7FE),
              Color(0xFFFFFFFF),
            ],
          );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: theme.colorScheme.onSurface,
              elevation: 0,
              pinned: true,
              stretch: true,
              leadingWidth: 66,
              expandedHeight: showImage ? 320 : 220,
              title: Text(
                'Chi tiết thông tin',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              centerTitle: true,
              leading: Padding(
                padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
                child: _buildFrostedIconButton(
                  icon: CupertinoIcons.chevron_left,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: _buildHeroHeader(
                  context: context,
                  news: news,
                  imageUrl: finalCoverImageUrl,
                  showImage: showImage,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _glassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (status.isNotEmpty) ...[
                            _buildStatusChip(context, status),
                            const SizedBox(height: 18),
                          ],
                          Text(
                            summary.isNotEmpty
                                ? summary
                                : 'Không có tóm tắt cho thông tin này.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.6,
                              color: theme.brightness == Brightness.dark
                                  ? Colors.white.withOpacity(0.82)
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildMetaRow(
                            icon: CupertinoIcons.time,
                            label: 'Ngày phát hành',
                            value: _formatDate(publishAt ?? news.createdAt),
                          ),
                        ],
                      ),
                    ),
                    if (news.bodyHtml.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _glassPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nội dung chi tiết',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Html(
                              data: news.bodyHtml,
                              style: {
                                'body': Style(
                                  margin: Margins.zero,
                                  padding: HtmlPaddings.zero,
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.white.withOpacity(0.86)
                                      : AppColors.textPrimary,
                                  fontSize: FontSize(16),
                                  lineHeight: const LineHeight(1.65),
                                ),
                                'p': Style(
                                  margin: Margins.only(bottom: 14),
                                ),
                                'li': Style(
                                  margin: Margins.only(bottom: 8),
                                ),
                                'h2': Style(
                                  margin: Margins.only(top: 18, bottom: 12),
                                  fontSize: FontSize(20),
                                  fontWeight: FontWeight.bold,
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (images.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _glassPanel(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thư viện hình ảnh',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.brightness == Brightness.dark
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...images
                                .map((img) => _buildImageItem(context, img))
                                .toList(),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(24),
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gradient = isDark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();
    final borderColor = (isDark ? AppColors.navyOutline : AppColors.neutralOutline)
        .withOpacity(0.45);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, String status) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.28 : 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(isDark ? 0.8 : 0.45)),
      ),
      child: Text(
        status.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ) ??
            TextStyle(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
      ),
    );
  }

  Widget _buildMetaRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(isDark ? 0.22 : 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : AppColors.textSecondary,
              ) ??
              TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : AppColors.textSecondary,
              ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ) ??
                TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageItem(BuildContext context, NewsImage image) {
    final theme = Theme.of(context);
    final imageUrl = image.url.startsWith('http')
        ? image.url
        : ApiClient.fileUrl(image.url);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                  child: const Center(
                    child: CupertinoActivityIndicator(),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  child: Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    color: theme.colorScheme.error,
                    size: 32,
                  ),
                ),
              ),
            ),
            if (image.caption != null && image.caption!.isNotEmpty)
              Container(
                color: theme.brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.4)
                    : Colors.white.withOpacity(0.7),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  image.caption!,
                  style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.brightness == Brightness.dark
                            ? Colors.white70
                            : AppColors.textSecondary,
                      ) ??
                      TextStyle(
                        fontStyle: FontStyle.italic,
                        color: theme.brightness == Brightness.dark
                            ? Colors.white70
                            : AppColors.textSecondary,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrostedIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: isDark
              ? Colors.white.withOpacity(0.12)
              : Colors.white.withOpacity(0.75),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                icon,
                size: 20,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader({
    required BuildContext context,
    required ResidentNews news,
    required String? imageUrl,
    required bool showImage,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Hero(
          tag: 'news_${news.id}',
          child: showImage && imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.heroBackdropGradient(isDark: isDark),
                    ),
                    child: const Center(
                      child: CupertinoActivityIndicator(),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.heroBackdropGradient(isDark: isDark),
                    ),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.heroBackdropGradient(isDark: isDark),
                  ),
                ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x66000000),
                Color(0x22000000),
                Color(0xAA000000),
              ],
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 36,
          child: Text(
            news.title,
            style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  letterSpacing: -0.3,
                ) ??
                const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  letterSpacing: -0.3,
                ),
          ),
        ),
      ],
    );
  }
}