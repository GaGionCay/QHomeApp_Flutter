import 'package:flutter/material.dart';

class NewsItemCard extends StatelessWidget {
  final String title;
  final String summary;
  final VoidCallback onTap;

  const NewsItemCard({super.key, required this.title, required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: ListTile(
        title: Text(title),
        subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
    );
  }
}
