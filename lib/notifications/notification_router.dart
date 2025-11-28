import 'package:flutter/material.dart';
import '../models/resident_notification.dart';
import '../services/card_registrations_screen.dart';
import '../invoices/invoice_list_screen.dart';
import '../contracts/contract_service.dart';
import '../auth/api_client.dart';
import '../models/unit_info.dart';
import 'notification_detail_screen.dart';

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
        await _navigateToCardRegistrations(
          context: context,
          notification: notification,
          residentId: residentId,
        );
        break;

      case 'BILL':
      case 'PAYMENT':
      case 'ELECTRICITY':
      case 'WATER':
        // Notification về hóa đơn/thanh toán
        await _navigateToInvoices(
          context: context,
          notification: notification,
          residentId: residentId,
        );
        break;

      case 'CONTRACT':
        // Notification về hợp đồng
        // TODO: Navigate to contract screen when available
        _navigateToDetail(context, notification, residentId);
        break;

      case 'REQUEST':
      case 'SERVICE':
        // Notification về yêu cầu/dịch vụ
        // TODO: Navigate to service request screen when available
        _navigateToDetail(context, notification, residentId);
        break;

      case 'SYSTEM':
      case 'INFO':
      default:
        // Mặc định mở detail screen
        _navigateToDetail(context, notification, residentId);
        break;
    }
  }

  /// Điều hướng đến màn hình danh sách thẻ đăng ký
  static Future<void> _navigateToCardRegistrations({
    required BuildContext context,
    required ResidentNotification notification,
    String? residentId,
  }) async {
    if (residentId == null || residentId.isEmpty) {
      // Nếu không có residentId, mở detail screen
      _navigateToDetail(context, notification, residentId);
      return;
    }

    try {
      // Lấy danh sách units của resident
      final apiClient = ApiClient();
      final contractService = ContractService(apiClient);
      final units = await contractService.getMyUnits();

      if (units.isEmpty) {
        _navigateToDetail(context, notification, residentId);
        return;
      }

      // Tìm unit phù hợp (có thể dựa vào referenceId hoặc lấy unit đầu tiên)
      UnitInfo selectedUnit;
      if (notification.referenceId != null) {
        // Có thể tìm unit dựa trên referenceId nếu cần
        try {
          selectedUnit = units.firstWhere(
            (unit) => unit.id == notification.referenceId,
          );
        } catch (_) {
          selectedUnit = units.first;
        }
      } else {
        selectedUnit = units.first;
      }

      if (!context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CardRegistrationsScreen(
            residentId: residentId,
            unitId: selectedUnit.id,
            unitDisplayName: selectedUnit.displayName,
            units: units,
          ),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Lỗi khi điều hướng đến CardRegistrationsScreen: $e');
      // Fallback về detail screen nếu có lỗi
      if (context.mounted) {
        _navigateToDetail(context, notification, residentId);
      }
    }
  }

  /// Điều hướng đến màn hình danh sách hóa đơn
  static Future<void> _navigateToInvoices({
    required BuildContext context,
    required ResidentNotification notification,
    String? residentId,
  }) async {
    try {
      // Lấy danh sách units của resident
      final apiClient = ApiClient();
      final contractService = ContractService(apiClient);
      final units = await contractService.getMyUnits();

      if (!context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvoiceListScreen(
            initialUnitId: units.isNotEmpty ? units.first.id : null,
            initialUnits: units,
          ),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Lỗi khi điều hướng đến InvoiceListScreen: $e');
      // Fallback về detail screen nếu có lỗi
      if (context.mounted) {
        _navigateToDetail(context, notification, residentId);
      }
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

