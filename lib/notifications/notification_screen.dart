import 'package:animations/animations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import '../models/resident_notification.dart';
import '../news/resident_service.dart';
import '../profile/profile_service.dart';
import '../theme/app_colors.dart';
import 'notification_detail_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final ApiClient _api = ApiClient();
  final ResidentService _residentService = ResidentService();

  List<ResidentNotification> items = [];
  bool loading = false;
  String? _residentId;
  String? _buildingId;

  @override
  void initState() {
    super.initState();
    _loadIdsAndFetch();
  }

  Future<void> _loadIdsAndFetch() async {
    try {
      final profileService = ProfileService(_api.dio);
      final profile = await profileService.getProfile();
      
      // Try multiple possible field names
      _residentId = profile['residentId']?.toString();
      _buildingId = profile['buildingId']?.toString();
      
      // If found in profile, use them directly
      if (_residentId != null && _residentId!.isNotEmpty && 
          _buildingId != null && _buildingId!.isNotEmpty) {
        debugPrint('✅ Tìm thấy residentId và buildingId trong profile: residentId=$_residentId, buildingId=$_buildingId');
        await _fetch();
        return;
      }
      
      // If not found in profile, try to get from backend API
      if (_residentId == null || _residentId!.isEmpty || _buildingId == null || _buildingId!.isEmpty) {
        try {
          debugPrint('🔍 Không tìm thấy residentId/buildingId trong profile, gọi API để lấy...');
          final response = await _api.dio.get('/residents/me/uuid');
          final data = response.data as Map<String, dynamic>;
          
          if (data['success'] == true) {
            final apiResidentId = data['residentId']?.toString();
            final apiBuildingId = data['buildingId']?.toString();
            
            if (apiResidentId != null && apiResidentId.isNotEmpty) {
              _residentId = _residentId ?? apiResidentId;
            }
            if (apiBuildingId != null && apiBuildingId.isNotEmpty) {
              _buildingId = _buildingId ?? apiBuildingId;
            }
            
            debugPrint('✅ Lấy được từ API: residentId=$_residentId, buildingId=$_buildingId');
          } else {
            debugPrint('⚠️ API trả về success=false: ${data['message']}');
            debugPrint('⚠️ Có thể endpoint admin API chưa tồn tại hoặc user chưa được gán vào căn hộ');
          }
        } catch (e) {
          debugPrint('⚠️ Lỗi gọi API lấy residentId/buildingId: $e');
          // Không throw để app vẫn hoạt động, chỉ không load notifications
        }
      }
      
      debugPrint('🔍 Profile data: ${profile.keys.toList()}');
      debugPrint('🔍 ResidentId found: $_residentId');
      debugPrint('🔍 BuildingId found: $_buildingId');
      
      if (_residentId == null || _residentId!.isEmpty) {
        debugPrint('⚠️ Không tìm thấy residentId. Profile keys: ${profile.keys}');
        if (mounted) {
          setState(() => loading = false);
        }
        return;
      }
      
      if (_buildingId == null || _buildingId!.isEmpty) {
        debugPrint('⚠️ Không tìm thấy buildingId. Profile keys: ${profile.keys}');
        if (mounted) {
          setState(() => loading = false);
        }
        return;
      }
      
      await _fetch();
    } catch (e) {
      debugPrint('⚠️ Lỗi lấy residentId/buildingId: $e');
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _fetch() async {
    if (_residentId == null || _buildingId == null) {
      debugPrint('⚠️ Không thể fetch: residentId hoặc buildingId null');
      return;
    }
    
    debugPrint('🔍 Bắt đầu fetch notifications với residentId=$_residentId, buildingId=$_buildingId');
    setState(() => loading = true);
    try {
      items = await _residentService.getResidentNotifications(
        _residentId!,
        _buildingId!,
      );
      debugPrint('✅ Loaded ${items.length} notifications');
      if (items.isEmpty) {
        debugPrint('⚠️ Không có notifications nào. Có thể admin service chưa có data hoặc UUID không đúng.');
      }
    } catch (e) {
      debugPrint('❌ Lỗi tải notifications: $e');
      if (e is DioException) {
        debugPrint('❌ DioException details: status=${e.response?.statusCode}, data=${e.response?.data}');
      }
      items = [];
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: theme.colorScheme.primary,
          onRefresh: _fetch,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? _buildEmptyState(theme)
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 24,
                        ),
                        children: [
                          _buildHeader(theme),
                          const SizedBox(height: 24),
                          Column(
                            children: [
                              for (final entry in items.asMap().entries)
                                TweenAnimationBuilder<double>(
                                  key: ValueKey(entry.value.id),
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: _NotificationCard(
                                      notification: entry.value,
                                      color: _getTypeColor(entry.value.type),
                                      icon: _getTypeIcon(entry.value.type),
                                    ),
                                  ),
                                  builder: (context, value, child) => Opacity(
                                    opacity: value,
                                    child: Transform.translate(
                                      offset: Offset(0, (1 - value) * 16),
                                      child: child,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toUpperCase()) {
      case 'SYSTEM':
        return AppColors.primaryEmerald;
      case 'PAYMENT':
        return AppColors.primaryBlue;
      case 'SERVICE':
        return AppColors.warning;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'SYSTEM':
        return Icons.info_outline;
      case 'PAYMENT':
        return Icons.payment;
      case 'SERVICE':
        return Icons.room_service;
      default:
        return Icons.notifications_outlined;
    }
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Thông báo hệ thống',
          style: theme.textTheme.displaySmall?.copyWith(fontSize: 30),
        ),
        const SizedBox(height: 8),
        Text(
          'Theo dõi các cập nhật mới nhất từ ban quản lý, thanh toán và dịch vụ cư dân.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined,
              size: 80, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            'Không có thông báo nào',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Kéo xuống để làm mới danh sách',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.color,
    required this.icon,
  });

  final ResidentNotification notification;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText =
        DateFormat('dd MMM yyyy, HH:mm').format(notification.createdAt);

    return OpenContainer<bool>(
      useRootNavigator: true,
      transitionType: ContainerTransitionType.fadeThrough,
      openColor: theme.colorScheme.surface,
      closedColor: theme.colorScheme.surface,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      openBuilder: (context, _) => NotificationDetailScreen(
        notificationId: notification.id,
      ),
      closedBuilder: (context, openContainer) {
        return InkWell(
          onTap: openContainer,
          borderRadius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(icon, color: color, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            notification.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Chip(
                      label: Text(
                        notification.type.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                        ),
                      ),
                      backgroundColor: color.withValues(alpha: 0.14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    Text(
                      dateText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
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
}

