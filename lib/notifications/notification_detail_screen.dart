// import 'package:flutter/material.dart';
// import '../auth/api_client.dart';

// class NotificationDetailScreen extends StatefulWidget {
//   final int id;
//   const NotificationDetailScreen({super.key, required this.id});

//   @override
//   State<NotificationDetailScreen> createState() => _NotificationDetailScreenState();
// }

// class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
//   final ApiClient api = ApiClient();
//   Map<String, dynamic>? news;
//   bool loading = false;

//   @override
//   void initState() {
//     super.initState();
//     _fetchDetail();
//   }

//   Future<void> _fetchDetail() async {
//     setState(() => loading = true);
//     try {
//       final res = await api.dio.get('/news/${widget.id}');
//       if (res.data != null) {
//         news = Map<String, dynamic>.from(res.data);
//       }
//     } catch (e) {
//       debugPrint('❌ Error fetching detail: $e');
//     } finally {
//       setState(() => loading = false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Chi tiết thông báo')),
//       body: loading
//           ? const Center(child: CircularProgressIndicator())
//           : news == null
//               ? const Center(child: Text('Không tìm thấy nội dung'))
//               : Padding(
//                   padding: const EdgeInsets.all(16),
//                   child: SingleChildScrollView(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           news!['title'] ?? 'Không có tiêu đề',
//                           style: const TextStyle(
//                             fontSize: 20,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                         const SizedBox(height: 12),
//                         Text(
//                           news!['createdAt'] ?? '',
//                           style: const TextStyle(color: Colors.grey, fontSize: 12),
//                         ),
//                         const Divider(height: 20),
//                         Text(
//                           news!['content'] ?? 'Không có nội dung',
//                           style: const TextStyle(fontSize: 16, height: 1.5),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//     );
//   }
// }
