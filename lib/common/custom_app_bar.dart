// import 'package:flutter/material.dart';
// import '../../notifications/notification_screen.dart';
// import '../news/widgets/unread_badge.dart';
// import '../../profile/profile_screen.dart';

// class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
//   final String title;
//   final VoidCallback? onHomeTap;
//   final bool showHomeIcon; 

//   const CustomAppBar({
//     super.key,
//     required this.title,
//     this.onHomeTap,
//     this.showHomeIcon = false,
//   });

//   @override
//   Size get preferredSize => const Size.fromHeight(kToolbarHeight);

//   @override
//   Widget build(BuildContext context) {
//     return AppBar(
//       automaticallyImplyLeading: false, 
//       title: Text(
//         title,
//         style: const TextStyle(fontWeight: FontWeight.bold),
//       ),
//       centerTitle: true,
//       leading: showHomeIcon
//           ? IconButton(
//               icon: const Icon(Icons.home),
//               tooltip: 'Trang chủ',
//               onPressed: onHomeTap ??
//                   () {
//                     Navigator.popUntil(context, (route) => route.isFirst);
//                   },
//             )
//           : null,
//       actions: [
//         IconButton(
//           icon: const Icon(Icons.person_outline),
//           tooltip: 'Hồ sơ',
//           onPressed: () {
//             Navigator.push(
//               context,
//               MaterialPageRoute(builder: (_) => const ProfileScreen()),
//             );
//           },
//         ),
//         IconButton(
//           icon: const UnreadBadge(),
//           tooltip: 'Thông báo',
//           onPressed: () {
//             Navigator.push(
//               context,
//               MaterialPageRoute(builder: (_) => const NotificationScreen()),
//             );
//           },
//         ),
//         const SizedBox(width: 8),
//       ],
//     );
//   }
// }
