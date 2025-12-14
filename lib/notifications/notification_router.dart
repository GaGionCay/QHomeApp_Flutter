import 'package:flutter/material.dart';
import '../models/resident_notification.dart';
import '../services/card_registrations_screen.dart';
import '../invoices/invoice_list_screen.dart';
import '../contracts/contract_service.dart';
import '../auth/api_client.dart';
import '../models/unit_info.dart';
import 'notification_detail_screen.dart';
import '../contracts/contract_list_screen.dart';
import '../contracts/contract_detail_screen.dart';
import '../service_registration/service_requests_overview_screen.dart';
import '../marketplace/post_detail_screen.dart';
import '../marketplace/marketplace_service.dart';
import '../models/marketplace_post.dart';

/// Service để điều hướng đến các screen tương ứng dựa trên notification type
class NotificationRouter {
  NotificationRouter._();

  /// Điều hướng đến screen phù hợp dựa trên notification type và referenceId
  static Future<void> navigateToNotificationScreen({
    required BuildContext context,
    required ResidentNotification notification,
    String? residentId,
  }) async {
    final type = notification.type.toUpperCase();

    // Nếu có actionUrl, ưu tiên mở URL đó
    if (notification.actionUrl != null && notification.actionUrl!.isNotEmpty) {
      // Có thể xử lý deep link hoặc URL ở đây nếu cần
      // Hiện tại fallback về detail screen
    }

    // Điều hướng dựa trên notification type
    switch (type) {
      case 'CARD_APPROVED':
      case 'CARD_REJECTED':
      case 'CARD_PENDING':
      case 'CARD_FEE_REMINDER':
        // Notification về thẻ đã duyệt/từ chối/chờ xử lý/nhắc phí
        // Capture navigator before awaiting to avoid using BuildContext across async gaps
        final navigator = Navigator.of(context);
        if (residentId == null || residentId.isEmpty) {
          navigator.push(MaterialPageRoute(
            builder: (_) => NotificationDetailScreen(
              notificationId: notification.id,
              residentId: residentId,
            ),
          ));
          return;
        }
        try {
          final apiClient = ApiClient();
          final contractService = ContractService(apiClient);
          final units = await contractService.getMyUnits();

          if (units.isEmpty) {
            navigator.push(MaterialPageRoute(
              builder: (_) => NotificationDetailScreen(
                notificationId: notification.id,
                residentId: residentId,
              ),
            ));
            return;
          }

          UnitInfo selectedUnit;
          if (notification.referenceId != null) {
            try {
              selectedUnit = units.firstWhere((unit) => unit.id == notification.referenceId);
            } catch (_) {
              selectedUnit = units.first;
            }
          } else {
            selectedUnit = units.first;
          }

          navigator.push(MaterialPageRoute(
            builder: (_) => CardRegistrationsScreen(
              residentId: residentId,
              unitId: selectedUnit.id,
              unitDisplayName: selectedUnit.displayName,
              units: units,
            ),
          ));
        } catch (e) {
          debugPrint('⚠️ Lỗi khi điều hướng đến CardRegistrationsScreen: $e');
          navigator.push(MaterialPageRoute(
            builder: (_) => NotificationDetailScreen(
              notificationId: notification.id,
              residentId: residentId,
            ),
          ));
        }
        return;

      case 'BILL':
      case 'PAYMENT':
      case 'ELECTRICITY':
      case 'WATER':
        // Notification về hóa đơn/thanh toán
        final navigator = Navigator.of(context);
        try {
          final apiClient = ApiClient();
          final contractService = ContractService(apiClient);
          final units = await contractService.getMyUnits();

          navigator.push(MaterialPageRoute(
            builder: (_) => InvoiceListScreen(
              initialUnitId: units.isNotEmpty ? units.first.id : null,
              initialUnits: units,
            ),
          ));
        } catch (e) {
          debugPrint('⚠️ Lỗi khi điều hướng đến InvoiceListScreen: $e');
          navigator.push(MaterialPageRoute(
            builder: (_) => NotificationDetailScreen(
              notificationId: notification.id,
              residentId: residentId,
            ),
          ));
        }
        return;

      case 'CONTRACT':
        // Notification về hợp đồng
        // Notification about contracts: navigate to contract list or detail
        final navigator = Navigator.of(context);
        try {
          if (notification.referenceId != null && notification.referenceId!.isNotEmpty) {
            navigator.push(MaterialPageRoute(
              builder: (_) => ContractDetailScreen(contractId: notification.referenceId!),
            ));
          } else {
            navigator.push(MaterialPageRoute(
              builder: (_) => const ContractListScreen(),
            ));
          }
        } catch (e) {
          debugPrint('⚠️ Lỗi khi điều hướng đến Contract screen: $e');
          navigator.push(MaterialPageRoute(
            builder: (_) => NotificationDetailScreen(
              notificationId: notification.id,
              residentId: residentId,
            ),
          ));
        }
        return;

      case 'REQUEST':
      case 'SERVICE':
        // Notification về yêu cầu/dịch vụ
        // Navigate to service requests overview
        final navigator = Navigator.of(context);
        try {
          navigator.push(MaterialPageRoute(
            builder: (_) => const ServiceRequestsOverviewScreen(),
          ));
        } catch (e) {
          debugPrint('⚠️ Lỗi khi điều hướng đến ServiceRequestsOverviewScreen: $e');
          navigator.push(MaterialPageRoute(
            builder: (_) => NotificationDetailScreen(
              notificationId: notification.id,
              residentId: residentId,
            ),
          ));
        }
        return;

      case 'MARKETPLACE_COMMENT':
        // Notification về comment trong marketplace post
        // Navigate to post detail screen và scroll đến comment
        final navigator = Navigator.of(context);
        try {
          // Get postId từ notification referenceId (đã được set từ main_shell.dart)
          final postId = notification.referenceId;
          
          if (postId == null || postId.isEmpty) {
            debugPrint('⚠️ Không có postId trong notification, mở notification detail');
            _navigateToDetail(context, notification, residentId);
            return;
          }

          // Fetch post từ API
          final marketplaceService = MarketplaceService();
          try {
            final post = await marketplaceService.getPostById(postId);
            
            // Get commentId từ notification actionUrl
            // FCM push notification sẽ có commentId trong data payload, được parse trong main_shell
            String? commentId;
            if (notification.actionUrl != null && notification.actionUrl!.contains('commentId=')) {
              commentId = notification.actionUrl!.split('commentId=')[1].split('&')[0];
            }
            
            // Navigate to post detail screen với commentId để scroll đến comment
            navigator.push(
              MaterialPageRoute(
                builder: (_) => PostDetailScreen(
                  post: post,
                  scrollToCommentId: commentId, // Pass commentId để scroll đến comment
                ),
              ),
            );
          } catch (e) {
            debugPrint('⚠️ Lỗi khi fetch post hoặc navigate: $e');
            _navigateToDetail(context, notification, residentId);
          }
        } catch (e) {
          debugPrint('⚠️ Lỗi khi điều hướng đến PostDetailScreen: $e');
          _navigateToDetail(context, notification, residentId);
        }
        return;

      case 'SYSTEM':
      case 'INFO':
      default:
        // Mặc định mở detail screen
        _navigateToDetail(context, notification, residentId);
        return;
    }
  }

  

  /// Điều hướng đến màn hình chi tiết notification
  static void _navigateToDetail(
    BuildContext context,
    ResidentNotification notification,
    String? residentId,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotificationDetailScreen(
          notificationId: notification.id,
          residentId: residentId,
        ),
      ),
    );
  }
}


