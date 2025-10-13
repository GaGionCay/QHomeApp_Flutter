import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import 'news_detail_screen.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});
  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final ApiClient _api = ApiClient();
  List<dynamic> items = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => loading = true);
    try {
      final res = await _api.dio.get('/news');
      if (res.data is Map && res.data['content'] != null) {
        items = List.from(res.data['content']);
      } else if (res.data is List) {
        items = List.from(res.data);
      }
    } catch (e) {
      // ignore
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _fetch,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('Không có tin nào'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final n = items[i];
                    return ListTile(
                      title: Text(n['title'] ?? ''),
                      subtitle: Text(n['summary'] ?? ''),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NewsDetailScreen(id: n['id']),
                          ),
                        );
                        _fetch();
                      },
                    );
                  },
                ),
    );
  }
}
