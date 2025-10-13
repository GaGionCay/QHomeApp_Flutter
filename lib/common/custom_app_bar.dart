import 'package:flutter/material.dart';
import '../../notifications/notification_screen.dart';
import '../news/widgets/unread_badge.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onHomeTap;

  const CustomAppBar({
    super.key,
    required this.title,
    this.onHomeTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      actions: [
        IconButton(
          icon: const Icon(Icons.home),
          onPressed: onHomeTap,
        ),
        IconButton(
          icon: const UnreadBadge(),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
