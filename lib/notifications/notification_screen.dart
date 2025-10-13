import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import '../news/widgets/unread_badge.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final ApiClient api = ApiClient();
  List<dynamic> notifs = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => loading = true);
    try {
      final res = await api.dio.get('/news?page=0&size=50');
      if (res.data != null && res.data['content'] is List) {
        notifs = List.from(res.data['content']);
      }
    } catch (_) {
      notifs = [];
    } finally {
      setState(() => loading = false);
      UnreadBadge.refreshGlobal();
    }
  }

  Future<void> _markAsRead(int id) async {
    try {
      await api.dio.post('/news/$id/read');
      setState(() {
        final idx = notifs.indexWhere((n) => n['id'] == id);
        if (idx != -1) notifs[idx]['read'] = true;
      });
      UnreadBadge.refreshGlobal();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thông báo')),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : notifs.isEmpty
                ? const Center(child: Text('Không có thông báo'))
                : ListView.builder(
                    itemCount: notifs.length,
                    itemBuilder: (context, index) {
                      final n = notifs[index];
                      final bool isRead = n['read'] == true;

                      return Card(
                        color: isRead ? Colors.grey[100] : Colors.white,
                        child: ListTile(
                          leading: Icon(
                            isRead
                                ? Icons.notifications_none
                                : Icons.notifications_active,
                            color: isRead ? Colors.grey : Colors.blue,
                          ),
                          title: Text(
                            n['title'] ?? 'Thông báo',
                            style: TextStyle(
                              fontWeight:
                                  isRead ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(n['summary'] ?? n['content'] ?? ''),
                          onTap: () => _markAsRead(n['id']),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
