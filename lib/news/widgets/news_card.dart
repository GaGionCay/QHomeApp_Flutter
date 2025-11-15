import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/resident_news.dart';
import '../news_detail_screen.dart';

class NewsCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = _formatDate(news);

    return OpenContainer<bool>(
      transitionType: ContainerTransitionType.fadeThrough,
      openColor: theme.colorScheme.surface,
      closedColor: theme.colorScheme.surface,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      openBuilder: (context, _) {
        onMarkedAsRead?.call();
        return NewsDetailScreen(
          residentNews: news,
        );
      },
      closedBuilder: (context, openContainer) {
        return InkWell(
          onTap: openContainer,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isRead
                    ? theme.colorScheme.outline.withValues(alpha: 0.1)
                    : theme.colorScheme.primary.withValues(alpha: 0.3),
                width: isRead ? 1 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isRead) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            news.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: isRead ? FontWeight.w600 : FontWeight.w700,
                              fontSize: 15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            news.summary,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: isRead ? 0.6 : 0.75,
                              ),
                              fontSize: 13,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dateText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (news.coverImageUrl != null)
                      Container(
                        width: 60,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: NetworkImage(news.coverImageUrl!),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
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

