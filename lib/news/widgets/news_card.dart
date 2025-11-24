import 'package:animations/animations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
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
        return 'Hôm nay';
      } else if (newsDate.isAtSameMomentAs(yesterday)) {
        return 'Hôm qua';
      } else {
        return DateFormat('dd/MM/yyyy').format(date);
      }
    } catch (e) {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }
}

class _NewsCoverHero extends StatelessWidget {
  const _NewsCoverHero({required this.id, this.url});

  final String id;
  final String? url;

  @override
  Widget build(BuildContext context) {
    // Check for null, empty string, or whitespace-only string
    final isValidUrl = url != null && url!.trim().isNotEmpty;
    if (!isValidUrl) {
      return _CoverImage(
        url: null,
        placeholder: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      );
    }

    return Hero(
      tag: 'news-cover-$id',
      child: _CoverImage(
        url: url!.trim(),
        placeholder: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url, required this.placeholder});

  final String? url;
  final Color placeholder;

  /// Get image URL - if URL is already a full URL (starts with http/https), 
  /// check if it contains localhost and replace with actual host IP if needed.
  /// Otherwise, use ApiClient.fileUrl() to construct the full URL
  String _getImageUrl(String url) {
    // If URL already starts with http:// or https://
    if (url.startsWith('http://') || url.startsWith('https://')) {
      // If URL contains localhost or 127.0.0.1, use ApiClient.fileUrl() to replace with actual IP
      if (url.contains('localhost') || url.contains('127.0.0.1')) {
        return ApiClient.fileUrl(url);
      }
      // External URL (like https://i.ibb.co/...) - use directly
      return url;
    }
    // Relative path - use ApiClient.fileUrl() to construct the full URL
    return ApiClient.fileUrl(url);
  }

  /// Check if URL is a valid image URL
  bool _isValidImageUrl(String url) {
    if (url.isEmpty) return false;
    
    // Check if URL has image extension
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg'];
    final lowerUrl = url.toLowerCase();
    return imageExtensions.any((ext) => lowerUrl.contains(ext));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 110,
        height: 72,
        child: (url == null || url!.trim().isEmpty)
            ? Container(
                color: placeholder,
                child: Icon(
                  Icons.article_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : CachedNetworkImage(
                imageUrl: _getImageUrl(url!.trim()),
                fit: BoxFit.cover,
                httpHeaders: const {
                  'Accept': 'image/*',
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
                },
                memCacheWidth: 220, // 110 * 2 for retina
                memCacheHeight: 144, // 72 * 2 for retina
                maxWidthDiskCache: 220,
                maxHeightDiskCache: 144,
                placeholder: (context, url) => Container(
                  color: placeholder,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) {
                  final imageUrl = _getImageUrl(url.trim());
                  
                  // Determine error type for better logging
                  String errorType = 'Unknown';
                  String errorMessage = error.toString();
                  bool isImageLoadError = false;
                  
                  // Check error type from error string
                  final errorString = error.toString().toLowerCase();
                  
                  if (errorString.contains('404') || errorString.contains('not found')) {
                    errorType = 'HTTP 404';
                    errorMessage = 'File not found';
                    isImageLoadError = true;
                  } else if (errorString.contains('403') || errorString.contains('forbidden')) {
                    errorType = 'HTTP 403';
                    errorMessage = 'Access forbidden';
                    isImageLoadError = true;
                  } else if (errorString.contains('500') || errorString.contains('server error')) {
                    errorType = 'HTTP 500';
                    errorMessage = 'Server error';
                    isImageLoadError = true;
                  } else if (errorString.contains('socketexception') || 
                             errorString.contains('connection')) {
                    errorType = 'Connection Error';
                    errorMessage = 'Cannot connect to server';
                    isImageLoadError = true;
                  } else if (errorString.contains('timeout')) {
                    errorType = 'Timeout';
                    errorMessage = 'Request timeout';
                    isImageLoadError = true;
                  } else if (errorString.contains('failed host lookup')) {
                    errorType = 'DNS Error';
                    errorMessage = 'Cannot resolve host';
                    isImageLoadError = true;
                  } else if (errorString.contains('format') || 
                             errorString.contains('invalid image') ||
                             errorString.contains('not a valid image')) {
                    errorType = 'Invalid Image Format';
                    errorMessage = 'URL is not a valid image';
                    isImageLoadError = true;
                  }
                  
                  // Check if URL is not a valid image URL
                  final isValidImageUrl = _isValidImageUrl(url);
                  
                  // Only log errors in debug mode to avoid spam in production
                  if (kDebugMode) {
                    debugPrint('❌ Error loading news cover image');
                    debugPrint('   Original URL: $url');
                    debugPrint('   Processed URL: $imageUrl');
                    debugPrint('   Error Type: $errorType');
                    debugPrint('   Error Message: $errorMessage');
                    debugPrint('   Is Valid Image URL: $isValidImageUrl');
                    debugPrint('   Is Image Load Error: $isImageLoadError');
                  }
                  
                  // If image cannot be loaded or URL is not a valid image URL,
                  // show the same placeholder as when there's no URL (article icon)
                  // instead of broken image icon
                  if (isImageLoadError || !isValidImageUrl) {
                    return Container(
                      color: placeholder,
                      child: Icon(
                        Icons.article_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    );
                  }
                  
                  // For other errors, show broken image icon
                  return Container(
                    color: placeholder,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                      size: 32,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
