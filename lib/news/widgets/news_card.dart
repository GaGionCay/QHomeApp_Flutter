import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../auth/api_client.dart';
import '../../models/resident_news.dart';
import '../news_detail_screen.dart';

class NewsCard extends StatefulWidget {
  final ResidentNews news;
  final bool isRead;
  final VoidCallback? onMarkedAsRead;

  const NewsCard({
    super.key,
    required this.news,
    required this.isRead,
    this.onMarkedAsRead,
  });

  @override
  State<NewsCard> createState() => _NewsCardState();
}

class _NewsCardState extends State<NewsCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateText = _formatDate(widget.news);
    final boxShadow = isDark
        ? <BoxShadow>[]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ];

    final backgroundColor = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.surface;

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.25)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.25);

    final titleColor = widget.isRead
        ? theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.8 : 0.7)
        : theme.colorScheme.onSurface;
    final subtitleColor = widget.isRead
        ? theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.5 : 0.45)
        : theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.7 : 0.6);

    return OpenContainer<bool>(
      transitionType: ContainerTransitionType.fadeThrough,
      openColor: theme.colorScheme.surface,
      closedColor: Colors.transparent,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      openBuilder: (context, _) {
        widget.onMarkedAsRead?.call();
        return NewsDetailScreen(residentNews: widget.news);
      },
      closedBuilder: (context, openContainer) {
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          tween: Tween<double>(
            begin: 1,
            end: _isPressed ? 0.97 : 1,
          ),
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            child: child,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: openContainer,
              onHighlightChanged: (value) {
                if (_isPressed != value) {
                  setState(() => _isPressed = value);
                }
              },
              child: Stack(
                children: [
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: boxShadow,
                      border: Border.all(
                        color: borderColor,
                        width: isDark ? 1.2 : 1,
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      widget.isRead ? 16 : 12,
                      12,
                      16,
                      12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _NewsCoverHero(
                          id: widget.news.id,
                          url: widget.news.coverImageUrl,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.news.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  letterSpacing: -0.1,
                                  color: titleColor,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.news.summary,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: subtitleColor,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 12,
                                    color: subtitleColor.withValues(alpha: 0.85),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    dateText,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: subtitleColor.withValues(alpha: 0.9),
                                      fontSize: 11.5,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.isRead)
                    Positioned(
                      top: 10,
                      right: 14,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: isDark ? 0.6 : 0.4),
                              blurRadius: 6,
                              spreadRadius: 0.2,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(ResidentNews news) {
    final date = news.publishAt ?? news.createdAt;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final newsDate = DateTime(date.year, date.month, date.day);

    try {
      if (newsDate.isAtSameMomentAs(today)) {
        return DateFormat('HH:mm').format(date);
      } else if (newsDate.isAtSameMomentAs(yesterday)) {
        return 'Hôm qua, ${DateFormat('HH:mm').format(date)}';
      } else {
        return DateFormat('dd/MM/yyyy, HH:mm').format(date);
      }
    } catch (e) {
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    }
  }
}

class _NewsCoverHero extends StatelessWidget {
  const _NewsCoverHero({required this.id, this.url});

  final String id;
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return _CoverImage(
        url: null,
        placeholder: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      );
    }

    return Hero(
      tag: 'news-cover-$id',
      child: _CoverImage(
        url: url,
        placeholder: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url, required this.placeholder});

  final String? url;
  final Color placeholder;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 110,
        height: 72,
        child: url == null
            ? Container(
                color: placeholder,
                child: Icon(
                  Icons.article_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : Image.network(
                ApiClient.fileUrl(url!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: placeholder,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
      ),
    );
  }
}
