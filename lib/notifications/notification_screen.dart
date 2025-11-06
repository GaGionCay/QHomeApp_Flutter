import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../auth/api_client.dart';
import '../profile/profile_service.dart';
import '../models/resident_notification.dart';
import '../news/resident_service.dart';
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      appBar: AppBar(
        title: const Text('Thông báo hệ thống'),
        elevation: 2,
        backgroundColor: const Color(0xFF26A69A),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        color: const Color(0xFF26A69A),
        onRefresh: _fetch,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final notification = items[i];
                        final String date = DateFormat('dd/MM/yyyy HH:mm')
                            .format(notification.createdAt);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.only(
                                left: 16, top: 12, right: 16, bottom: 12),
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: _getTypeColor(notification.type)
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _getTypeIcon(notification.type),
                                color: _getTypeColor(notification.type),
                                size: 24,
                              ),
                            ),
                            title: Text(
                              notification.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF004D40),
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  notification.message,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  date,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              // Navigate to detail screen
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => NotificationDetailScreen(
                                    notificationId: notification.id,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toUpperCase()) {
      case 'SYSTEM':
        return const Color(0xFF26A69A);
      case 'PAYMENT':
        return Colors.blue;
      case 'SERVICE':
        return Colors.orange;
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.notifications_off_outlined,
              size: 80, color: Color(0xFFB0BEC5)),
          const SizedBox(height: 16),
          Text(
            'Không có thông báo nào',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Kéo xuống để làm mới danh sách',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

