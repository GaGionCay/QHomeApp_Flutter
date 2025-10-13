import 'package:flutter/material.dart';
import '../../auth/api_client.dart';
import 'dart:async';

class UnreadBadge extends StatefulWidget {
  const UnreadBadge({super.key});

  // cho phép các màn khác gọi refreshBadge
  static final _notifier = ValueNotifier<int>(0);

  static void refreshGlobal() {
    _notifier.value++;
  }

  @override
  State<UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<UnreadBadge> {
  final ApiClient api = ApiClient();
  int count = 0;
  Timer? t;

  @override
  void initState() {
    super.initState();
    _fetch();
    UnreadBadge._notifier.addListener(_fetch);
    t = Timer.periodic(const Duration(seconds: 30), (_) => _fetch());
  }

  Future<void> _fetch() async {
    try {
      final res = await api.dio.get('/news/unread-count');
      final val = res.data;
      setState(() => count = (val is int) ? val : int.tryParse(val.toString()) ?? 0);
    } catch (_) {}
  }

  @override
  void dispose() {
    t?.cancel();
    UnreadBadge._notifier.removeListener(_fetch);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Stack(
        children: [
          const Icon(Icons.notifications),
          if (count > 0)
            Positioned(
              right: 0,
              top: 0,
              child: CircleAvatar(
                radius: 8,
                backgroundColor: Colors.red,
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      onPressed: () async {
        // Khi bấm vào icon -> mở NotificationScreen
        if (context.mounted) {
          await Navigator.pushNamed(context, '/notifications');
          _fetch();
        }
      },
    );
  }
}
