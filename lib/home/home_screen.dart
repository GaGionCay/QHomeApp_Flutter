import 'dart:convert';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:dio/dio.dart';
import '../auth/api_client.dart';
import '../core/event_bus.dart';
import '../news/news_screen.dart';
import '../profile/profile_service.dart';
import '../contracts/contract_service.dart';
import '../contracts/contract_reminder_popup.dart';
import '../models/contract.dart';
import '../invoices/invoice_list_screen.dart';
import '../invoices/paid_invoices_screen.dart';
import '../invoices/invoice_service.dart';
import '../models/unit_info.dart';
import '../news/resident_service.dart';
import '../notifications/notification_screen.dart';
import '../notifications/notification_read_store.dart';
import '../residents/household_member_request_screen.dart';
import '../residents/household_member_request_status_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import '../residents/household_member_registration_screen.dart';
import '../residents/account_request_status_screen.dart';
import '../auth/asset_maintenance_api_client.dart';
import '../service_registration/service_booking_service.dart';
// Cleaning request removed - no longer used
// import '../service_registration/cleaning_request_service.dart';
import '../service_registration/unpaid_service_bookings_screen.dart';
import '../feedback/feedback_screen.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../common/layout_insets.dart';
import '../services/card_registrations_screen.dart';
import '../settings/settings_screen.dart';
import '../register/register_vehicle_screen.dart';
import '../register/register_elevator_card_screen.dart';
import '../register/register_resident_card_screen.dart';
import '../qr/qr_scanner_screen.dart';
import '../service_registration/service_requests_overview_screen.dart';
// Cleaning request removed - no longer used
// import '../models/service_requests.dart';
import '../chat/group_list_screen.dart';
import '../chat/chat_service.dart';

import '../core/safe_state_mixin.dart';
class HomeScreen extends StatefulWidget {
  final void Function(int)? onNavigateToTab;
  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SafeStateMixin<HomeScreen> {
  late final ApiClient _apiClient;
  late final ContractService _contractService;
  late final AssetMaintenanceApiClient _assetMaintenanceClient;
  late final ServiceBookingService _serviceBookingService;
  final ResidentService _residentService = ResidentService();
  final _eventBus = AppEventBus();
  late AppLinks _appLinks;
  StreamSubscription? _paymentSub;
  // Cleaning request removed - no longer used
  // late final CleaningRequestService _cleaningRequestService;

  Map<String, dynamic>? _profile;
  // Removed: List<NewsItem> _notifications = []; - now using ResidentNews from admin API
  List<UnitInfo> _units = [];
  String? _selectedUnitId;
  int _unpaidBookingCount = 0;
  int _unpaidInvoiceCount = 0;
  int _unreadNotificationCount = 0;
  bool _isWeatherLoading = true;
  _WeatherSnapshot? _weatherSnapshot;
  String? _weatherError;
  bool _hasGroupChatActivity = false; // Badge for group chat
  final ChatService _chatService = ChatService();

  // Error states
  String? _unpaidServicesError;
  String? _unpaidInvoicesError;
  String? _notificationsError;
  static _WeatherSnapshot? _cachedWeatherSnapshot;
  static DateTime? _cachedWeatherFetchedAt;
  static const Duration _weatherRefreshInterval = Duration(minutes: 30);

  static const _selectedUnitPrefsKey = 'selected_unit_id';

  bool _loading = true;
  bool _isLoadingData = false; // Prevent duplicate API calls
  // Cleaning request removed - no longer used
  // CleaningRequestSummary? _pendingCleaningRequest;
  // Timer? _resendVisibilityTimer;
  // Timer? _cleaningRequestRefreshTimer;
  // bool _isResendInProgress = false;
  // Duration? _resendCancelWindow;
  // Duration? _noResendCancelWindow;

  // Cleaning request removed - no longer used
  // static const Duration _resendButtonThreshold = Duration.zero;
  // static const Duration _defaultResendCancelWindow = Duration(hours: 5); // Fallback
  // static const Duration _defaultNoResendCancelWindow = Duration(hours: 6); // Fallback
  // static const int _serviceRequestPageSize = 8;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _contractService = ContractService(_apiClient);
    _assetMaintenanceClient = AssetMaintenanceApiClient();
    _serviceBookingService = ServiceBookingService(_assetMaintenanceClient);
    // Cleaning request removed - no longer used
    // _cleaningRequestService = CleaningRequestService(_apiClient);
    _appLinks = AppLinks();
    _initialize();
    _listenForPaymentResult();
    _loadWeatherSnapshot();

    _eventBus.on('news_update', (_) async {
      debugPrint('🔔 HomeScreen nhận event news_update -> reload dữ liệu...');
      await _refreshAll();
    });
    _eventBus.on('notifications_update', (_) async {
      debugPrint(
          '🔔 HomeScreen nhận event notifications_update -> cập nhật quick alerts...');
      await _loadUnreadNotifications();
      // Also refresh cleaning request state to update resend button visibility
      // Cleaning request removed - no longer used
    // await _loadCleaningRequestState();
    });
    _eventBus.on('contract_cancelled', (_) async {
      debugPrint('🔔 HomeScreen nhận event contract_cancelled -> refresh units và data...');
      // Refresh units to update _ownerUnits (units where user is primary resident)
      // After contract cancellation, household is deactivated, so unit won't be in _ownerUnits anymore
      await _loadUnitContext();
      await _refreshAll();
    });
    // Listen for new incoming notifications via WebSocket - update count immediately without API call
    _eventBus.on('notifications_incoming', (data) async {
      debugPrint(
          '🔔 HomeScreen nhận event notifications_incoming -> cập nhật unread count...');
      if (mounted) {
        // Check if this is a deletion event
        final eventData = data is Map<String, dynamic> ? data : <String, dynamic>{};
        final eventType = (eventData['eventType']?.toString() ?? '').toUpperCase();
        
        safeSetState(() {
          if (eventType == 'NOTIFICATION_DELETED') {
            // Decrease count when notification is deleted
            if (_unreadNotificationCount > 0) {
              _unreadNotificationCount = _unreadNotificationCount - 1;
            }
            debugPrint('✅ Đã giảm unread notification count: $_unreadNotificationCount');
          } else {
            // For NOTIFICATION_CREATED or NOTIFICATION_UPDATED, check if notification is unread
            // Only increase count if notification is not read
            // Note: Read status is tracked client-side via NotificationReadStore
            // New notifications from WebSocket are always unread (isRead = false or null)
            final isRead = eventData['isRead'] as bool?;
            final readAt = eventData['readAt'];
            
            // Check if notification is unread:
            // - isRead is null or false
            // - readAt is null or empty
            // - For NOTIFICATION_CREATED, always consider as unread (new notification)
            final isUnread = (isRead == null || !isRead) && 
                            (readAt == null || readAt.toString().isEmpty) &&
                            (eventType == 'NOTIFICATION_CREATED' || eventType.isEmpty);
            
            if (isUnread) {
              // Increase count for new unread notifications
              _unreadNotificationCount = _unreadNotificationCount + 1;
              debugPrint('✅ Đã tăng unread notification count: $_unreadNotificationCount (notification is unread, eventType: $eventType)');
            } else {
              debugPrint('ℹ️ Notification đã được đọc hoặc không phải NOTIFICATION_CREATED, không tăng count. isRead: $isRead, readAt: $readAt, eventType: $eventType');
            }
          }
        });
      }
      // Cleaning request removed - no longer used
      // unawaited(_loadCleaningRequestState());
    });
    _eventBus.on('unit_context_changed', (data) {
      if (!mounted) return;
      final unitId = (data is String && data.isNotEmpty) ? data : null;
      unawaited(_onUnitChanged(unitId));
    });
    // Listen for chat activity updates
    _eventBus.on('chat_activity_updated', (_) async {
      await _loadGroupChatActivity();
    });
    // Listen for direct chat activity updates
    _eventBus.on('direct_chat_activity_updated', (_) async {
      await _loadGroupChatActivity();
    });
    // Listen for chat notifications to update badge
    _eventBus.on('chat_notification_received', (_) async {
      await _loadGroupChatActivity();
    });
  }

  Future<void> _initialize() async {
    await _loadUnitContext();
    await _loadAllData();
    await _initRealTime();
  }

  Future<void> _loadUnitContext() async {
    try {
      // Small delay to ensure token is ready (especially after hot reload)
      await Future.delayed(const Duration(milliseconds: 100));
      final units = await _contractService.getMyUnits();
      final prefs = await SharedPreferences.getInstance();
      final savedUnitId = prefs.getString(_selectedUnitPrefsKey);

      String? nextSelected;
      if (units.isNotEmpty) {
        final exists = units.any((unit) => unit.id == savedUnitId);
        if (exists && savedUnitId != null) {
          nextSelected = savedUnitId;
        } else {
          nextSelected = units.first.id;
        }
      }

      if (mounted) {
        safeSetState(() {
          _units = units;
          _selectedUnitId = nextSelected;
        });
      }

      if (nextSelected != null && nextSelected != savedUnitId) {
        await prefs.setString(_selectedUnitPrefsKey, nextSelected);
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      
      // Handle 401 Unauthorized - token expired, will be handled by ApiClient interceptor
      // But if it reaches here, it means refresh failed or no refresh token
      if (statusCode == 401) {
        debugPrint('⚠️ [HomeScreen] Load unit context: 401 Unauthorized - Token expired');
        debugPrint('⚠️ [HomeScreen] ApiClient interceptor should handle this, but if it reaches here, refresh failed');
        if (mounted) {
          safeSetState(() {
            _units = [];
            _selectedUnitId = null;
          });
        }
        // Don't show snackbar here - AuthProvider will handle logout and navigation
        return;
      }
      
      // Handle 403 Forbidden - could be token expired or permission issue
      // If all APIs fail with 403, it's likely token expired
      if (statusCode == 403) {
        debugPrint('⚠️ [HomeScreen] Load unit context: 403 Forbidden');
        debugPrint('⚠️ [HomeScreen] If all APIs return 403, token may be expired');
        if (mounted) {
          safeSetState(() {
            _units = [];
            _selectedUnitId = null;
          });
          // Show user-friendly message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      debugPrint('⚠️ Load unit context error: $e');
      if (mounted) {
        safeSetState(() {
          _units = [];
          _selectedUnitId = null;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Load unit context error: $e');
      if (mounted) {
        safeSetState(() {
          _units = [];
          _selectedUnitId = null;
        });
      }
    }
  }

  Future<void> _initRealTime() async {
    // WebSocket connection is handled in MainShell
    // This method is kept for compatibility but does nothing
  }

  Future<void> _loadAllData() async {
    // Prevent duplicate API calls
    if (_isLoadingData) {
      return;
    }
    _isLoadingData = true;
    
    safeSetState(() => _loading = true);

    final invoiceService = InvoiceService(_apiClient);

    // Load profile (required)
    try {
      final profile = await ProfileService(_apiClient.dio).getProfile();
      if (mounted) {
        safeSetState(() {
          _profile = profile;
        });
      }
    } catch (e) {
      // Continue even if profile fails - not critical
    }

    try {
      // DEV LOCAL mode: Load APIs sequentially to avoid backend overload
      // Critical APIs must not be called in parallel
      await _loadUnpaidServices();
      await _loadUnpaidInvoices(invoiceService);
      await _loadUnreadNotifications();
      await _loadGroupChatActivity();

      // Check for contract renewal reminders after loading
      await _checkContractReminders();
    } finally {
      // Always reset loading flag, even if error occurs
      if (mounted) {
        safeSetState(() {
          _loading = false;
          _isLoadingData = false;
        });
      }
    }

    // Cleaning request removed - no longer used
    // await _loadCleaningRequestState();
  }

  // REMOVED: _hasShownPopupForContract and _markPopupAsShown
  // Reminder state is now managed entirely by backend contract status.
  // No caching in SharedPreferences - always refetch from backend.
  // Final reminders will persist until contract status changes (RENEWED or CANCELLED).

  /// Check and show contract reminders
  /// IMPORTANT: This method ALWAYS refetches from backend - no caching of reminder state.
  /// Reminder will only disappear when backend confirms contract status has changed
  /// (RENEWED or CANCELLED). Final reminders persist until status changes.
  /// 
  /// [skipRenewalReminder] - Set to true when user is in cancel/renew contract screen
  /// to prevent reminder popup from showing
  Future<void> _checkContractReminders({bool skipRenewalReminder = false}) async {
    if (_selectedUnitId == null) {
      debugPrint('⚠️ [ContractReminder] _selectedUnitId is null, skipping check');
      return;
    }

    debugPrint('🔍 [ContractReminder] Checking reminders for unitId: $_selectedUnitId (always refetching from backend), skipRenewalReminder: $skipRenewalReminder');

    try {
      // ALWAYS refetch from backend - no cache, no SharedPreferences check
      // Backend will only return contracts with status=ACTIVE and renewalStatus=REMINDED
      // If contract status changed to RENEWED or CANCELLED, it won't be in this list
      final contractsNeedingPopup = await _contractService.getContractsNeedingPopup(
        _selectedUnitId!,
        skipRenewalReminder: skipRenewalReminder,
      );
      debugPrint('🔍 [ContractReminder] Found ${contractsNeedingPopup.length} contract(s) needing popup');
      
      if (contractsNeedingPopup.isNotEmpty) {
        for (var contract in contractsNeedingPopup) {
          debugPrint('📋 [ContractReminder] Contract: ${contract.contractNumber}, status: ${contract.status}, renewalStatus: ${contract.renewalStatus}, reminderSentAt: ${contract.renewalReminderSentAt}, isFinalReminder: ${contract.isFinalReminder}');
        }
      }
      
      // Show popup for first contract needing reminder
      // No filtering by "shown" state - backend status is source of truth
      if (contractsNeedingPopup.isNotEmpty && mounted) {
        final contract = contractsNeedingPopup.first;
        debugPrint('✅ [ContractReminder] Showing popup for contract: ${contract.contractNumber} (isFinalReminder: ${contract.isFinalReminder})');
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            debugPrint('🎯 [ContractReminder] About to show dialog for contract: ${contract.contractNumber}');
            try {
              showDialog(
                context: context,
                barrierDismissible: contract.isFinalReminder != true,
                builder: (dialogContext) {
                  debugPrint('🎯 [ContractReminder] Dialog builder called for contract: ${contract.contractNumber}');
                  return ContractReminderPopup(
                    contract: contract,
                    contractService: _contractService,
                    onDismiss: () {
                      debugPrint('🎯 [ContractReminder] Popup dismissed for contract: ${contract.contractNumber}');
                      // After dismissing, refetch from backend to check if status changed
                      // If status changed (RENEWED/CANCELLED), reminder won't show again
                      // If status unchanged, reminder will show again (especially for final reminders)
                      _checkContractReminders();
                    },
                    onDismissWithSkip: ({bool skipRenewalReminder = false}) {
                      debugPrint('✅✅✅ [ContractReminder] onDismissWithSkip CALLED! skipRenewalReminder=$skipRenewalReminder for contract: ${contract.contractNumber}');
                      // ✅ Skip renewal reminder when returning from cancel/renew screen
                      _checkContractReminders(skipRenewalReminder: skipRenewalReminder);
                    },
                  );
                },
              ).then((_) {
                debugPrint('🎯 [ContractReminder] Dialog closed for contract: ${contract.contractNumber}');
              }).catchError((error) {
                debugPrint('❌ [ContractReminder] Error showing dialog: $error');
                debugPrint('❌ [ContractReminder] Stack trace: ${StackTrace.current}');
              });
            } catch (e) {
              debugPrint('❌ [ContractReminder] Exception when calling showDialog: $e');
              debugPrint('❌ [ContractReminder] Stack trace: ${StackTrace.current}');
            }
          } else {
            debugPrint('⚠️ [ContractReminder] Widget not mounted, cannot show dialog');
          }
        });
      } else {
        debugPrint('⚠️ [ContractReminder] No contracts needing popup (all contracts either renewed/cancelled or not in reminder phase)');
      }
    } catch (e) {
      debugPrint('❌ [ContractReminder] Error checking contract reminders: $e');
      debugPrint('❌ [ContractReminder] Stack trace: ${StackTrace.current}');
    }
  }

  // Cleaning request removed - no longer used
  // Future<void> _loadCleaningRequestState() async {
  //   // Implementation removed
  // }

  // Cleaning request removed - no longer used
  // void _updatePendingCleaningRequest(List<CleaningRequestSummary> requests) {
  //   // Implementation removed
  // }

  Future<void> _refreshAll() async {
    await _loadAllData();
  }

  // Cleaning request removed - no longer used
  // bool _isPendingCleaningRequest(CleaningRequestSummary request) {
  //   // Implementation removed
  // }

  // DateTime _resendReferenceTimestamp(CleaningRequestSummary request) =>
  //     request.lastResentAt ?? request.updatedAt ?? request.createdAt;

  // void _scheduleResendButton(CleaningRequestSummary? request) {
  //   // Implementation removed
  // }

  // void _clearResendTimer() {
  //   // Implementation removed
  // }

  // void _scheduleCleaningRequestRefresh(CleaningRequestSummary? request) {
  //   // Implementation removed
  // }

  // void _clearCleaningRequestRefreshTimer() {
  //   // Implementation removed
  // }

  Future<void> _loadUnpaidServices() async {
    try {
      final bookings = await _serviceBookingService.getUnpaidBookings();
      if (mounted) {
        // Only count bookings that are not CANCELLED for home screen notification
        // CANCELLED bookings are still shown in the list but don't trigger notifications
        final activeUnpaidCount = bookings.where((booking) {
          final status = booking['status']?.toString() ?? '';
          return status.toUpperCase() != 'CANCELLED';
        }).length;
        safeSetState(() {
          _unpaidBookingCount = activeUnpaidCount;
          _unpaidServicesError = null;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Không thể tải dịch vụ chưa thanh toán: $e');
      if (mounted) {
        safeSetState(() {
          _unpaidBookingCount = 0;
          _unpaidServicesError = e.toString();
        });
      }
    }
  }

  Future<void> _loadUnpaidInvoices(InvoiceService invoiceService) async {
    try {
      final unitId =
          _selectedUnitId ?? (_units.isNotEmpty ? _units.first.id : null);
      if (unitId == null || unitId.isEmpty) {
        if (mounted) {
          safeSetState(() {
            _unpaidInvoiceCount = 0;
            _unpaidInvoicesError = null;
          });
        }
        return;
      }

      final categories =
          await invoiceService.getUnpaidInvoicesByCategory(unitId: unitId);
      final total = categories.fold<int>(
          0, (sum, category) => sum + category.invoiceCount);
      if (mounted) {
        safeSetState(() {
          _unpaidInvoiceCount = total;
          _unpaidInvoicesError = null;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Không thể tải hóa đơn chưa thanh toán: $e');
      if (mounted) {
        safeSetState(() {
          _unpaidInvoiceCount = 0;
          _unpaidInvoicesError = e.toString();
        });
      }
    }
  }

  Future<void> _loadGroupChatActivity() async {
    try {
      // Get all groups and calculate total unread messages
      final groupsResponse = await _chatService.getMyGroups(page: 0, size: 100);
      int totalUnreadMessages = 0;
      for (final group in groupsResponse.content) {
        totalUnreadMessages += group.unreadCount ?? 0;
      }

      // Get pending invitations count (group chat)
      final pendingInvitations = await _chatService.getMyPendingInvitations();
      final pendingInvitationsCount = pendingInvitations.length;

      // Get direct chat activity (unread messages + pending invitations)
      int directChatUnreadCount = 0;
      int directChatPendingInvitations = 0;
      try {
        final conversations = await _chatService.getConversations();
        for (final conversation in conversations) {
          directChatUnreadCount += conversation.unreadCount ?? 0;
        }
        directChatPendingInvitations = await _chatService.countPendingDirectInvitations();
      } catch (e) {
        debugPrint('⚠️ Không thể tải direct chat activity: $e');
      }

      // Show badge if there are unread messages or pending invitations (group or direct)
      final hasActivity = totalUnreadMessages > 0 || 
                         pendingInvitationsCount > 0 ||
                         directChatUnreadCount > 0 ||
                         directChatPendingInvitations > 0;

      if (mounted) {
        safeSetState(() {
          _hasGroupChatActivity = hasActivity;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Không thể tải hoạt động group chat: $e');
      // Don't show badge on error
      if (mounted) {
        safeSetState(() {
          _hasGroupChatActivity = false;
        });
      }
    }
  }

  Future<void> _loadUnreadNotifications() async {
    final residentId = _profile?['residentId']?.toString();
    if (residentId == null || residentId.isEmpty) {
      if (mounted) {
        safeSetState(() => _unreadNotificationCount = 0);
      }
      return;
    }

    UnitInfo? selectedUnit;
    if (_selectedUnitId != null) {
      for (final unit in _units) {
        if (unit.id == _selectedUnitId) {
          selectedUnit = unit;
          break;
        }
      }
    }
    selectedUnit ??= _units.isNotEmpty ? _units.first : null;

    String? targetBuildingId =
        selectedUnit?.buildingId ?? _profile?['buildingId']?.toString();

    if (targetBuildingId == null || targetBuildingId.isEmpty) {
      if (mounted) {
        safeSetState(() => _unreadNotificationCount = 0);
      }
      return;
    }

    try {
      // Get total count of all notifications (not just page 0)
      final totalCount = await _residentService.getResidentNotificationsCount(
        residentId,
        targetBuildingId,
      );
      
      // Get read IDs from local storage
      final readIds = await NotificationReadStore.load(residentId);
      
      // Fetch all notifications across all pages to get accurate unread count
      // Limit to reasonable number to avoid performance issues
      int unread;
      if (totalCount <= 200) {
        // Fetch all notifications if count is reasonable
        final allNotifications = await _residentService.getAllResidentNotifications(
          residentId,
          targetBuildingId,
        );
        
        unread = allNotifications
            .where((notification) => !readIds.contains(notification.id))
            .length;
        
        debugPrint('✅ [HomeScreen] Total notifications: $totalCount, Fetched: ${allNotifications.length}, Unread: $unread');
      } else {
        // For very large counts (>200), fetch first 200 and estimate
        // This assumes notifications are sorted by createdAt DESC (newest first)
        final sampleNotifications = await _residentService.getAllResidentNotifications(
          residentId,
          targetBuildingId,
          maxPages: 29, // 29 pages * 7 = ~200 notifications
        );
        
        final unreadInSample = sampleNotifications
            .where((notification) => !readIds.contains(notification.id))
            .length;
        
        // Estimate: assume the ratio of unread in sample applies to total
        final unreadRatio = sampleNotifications.isNotEmpty
            ? unreadInSample / sampleNotifications.length
            : 0.0;
        unread = (totalCount * unreadRatio).round();
        
        debugPrint('✅ [HomeScreen] Total: $totalCount, Sample: ${sampleNotifications.length}, Unread in sample: $unreadInSample, Estimated unread: $unread');
      }
      
      if (mounted) {
        safeSetState(() {
          _unreadNotificationCount = unread;
          _notificationsError = null;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Không thể tải thông báo chưa đọc: $e');
      if (mounted) {
        safeSetState(() {
          _unreadNotificationCount = 0;
          _notificationsError = e.toString();
        });
      }
    }
  }

  Future<void> _loadWeatherSnapshot({bool force = false}) async {
    if (!force &&
        _cachedWeatherSnapshot != null &&
        _cachedWeatherFetchedAt != null &&
        DateTime.now().difference(_cachedWeatherFetchedAt!) <
            _weatherRefreshInterval) {
      if (mounted) {
        safeSetState(() {
          _weatherSnapshot = _cachedWeatherSnapshot;
          _weatherError = null;
          _isWeatherLoading = false;
        });
      }
      return;
    }

    safeSetState(() {
      _isWeatherLoading = true;
      _weatherError = null;
    });

    try {
      double? latitude;
      double? longitude;
      String? city;

      final position = await _getDevicePosition();
      if (position != null) {
        latitude = position.latitude;
        longitude = position.longitude;
        city = await _resolveLocality(latitude, longitude);
      }

      if (latitude == null || longitude == null) {
        final locationResponse =
            await http.get(Uri.parse('https://ipapi.co/json/')).timeout(
                  const Duration(seconds: 6),
                );

        if (locationResponse.statusCode == 429) {
          throw _WeatherRateLimitException(source: 'ipapi.co');
        }

        if (locationResponse.statusCode != 200) {
          throw Exception(
              'Location lookup failed with status ${locationResponse.statusCode}');
        }

        final locationJson =
            jsonDecode(locationResponse.body) as Map<String, dynamic>;
        latitude = (locationJson['latitude'] as num?)?.toDouble();
        longitude = (locationJson['longitude'] as num?)?.toDouble();
        city = (locationJson['city'] as String?) ?? 'Khu dân cư của bạn';

        if (latitude == null || longitude == null) {
          throw Exception('Missing geolocation data');
        }
      }

      final double lat = latitude;
      final double lon = longitude;

      final weatherUri = Uri.https(
        'api.open-meteo.com',
        '/v1/forecast',
        <String, String>{
          'latitude': lat.toString(),
          'longitude': lon.toString(),
          'current_weather': 'true',
          'hourly': 'relativehumidity_2m',
          'timezone': 'auto',
        },
      );

      final weatherResponse =
          await http.get(weatherUri).timeout(const Duration(seconds: 6));

      if (weatherResponse.statusCode == 429) {
        throw _WeatherRateLimitException(source: 'open-meteo.com');
      }

      if (weatherResponse.statusCode != 200) {
        throw Exception(
            'Weather fetch failed with status ${weatherResponse.statusCode}');
      }

      final weatherJson =
          jsonDecode(weatherResponse.body) as Map<String, dynamic>;
      final current = weatherJson['current_weather'] as Map<String, dynamic>?;
      if (current == null) throw Exception('Missing current weather payload');

      final timezone = weatherJson['timezone'] as String?;
      final derivedCity = city ??
          (() {
            if (timezone == null) return null;
            if (!timezone.contains('/')) return timezone;
            final parts = timezone.split('/');
            return parts.last.replaceAll('_', ' ');
          })();

      final temperature = (current['temperature'] as num?)?.toDouble();
      final windSpeed = (current['windspeed'] as num?)?.toDouble();
      final weatherCode = current['weathercode'] as int? ?? 0;
      final humiditySeries = (weatherJson['hourly']
          as Map<String, dynamic>?)?['relativehumidity_2m'] as List<dynamic>?;
      final humidity = (humiditySeries != null && humiditySeries.isNotEmpty)
          ? (humiditySeries.first as num?)?.toDouble()
          : null;

      final descriptor = _describeWeatherCode(weatherCode);
      final fallbackLat = lat.toStringAsFixed(2);
      final fallbackLon = lon.toStringAsFixed(2);
      final snapshot = _WeatherSnapshot(
        city: derivedCity ?? 'Lat $fallbackLat, Lon $fallbackLon',
        temperatureCelsius: temperature ?? 0,
        weatherLabel: descriptor.label,
        weatherIcon: descriptor.icon,
        windSpeed: windSpeed,
        humidity: humidity,
        fetchedAt: DateTime.now(),
      );

      _cachedWeatherSnapshot = snapshot;
      _cachedWeatherFetchedAt = snapshot.fetchedAt;

      if (mounted) {
        safeSetState(() {
          _weatherSnapshot = snapshot;
          _isWeatherLoading = false;
        });
      }
    } on _WeatherRateLimitException catch (e) {
      debugPrint(
          '⚠️ Weather rate limited by ${e.source}. Using cached data when available.');
      if (mounted) {
        safeSetState(() {
          _weatherError =
              'Máy chủ thời tiết đang tạm giới hạn. Thử lại sau ít phút.';
          _isWeatherLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('⚠️ Không thể tải thời tiết: $e');
      debugPrint('↪ Weather stack trace: $stack');
      if (mounted) {
        safeSetState(() {
          _weatherError = 'Không thể cập nhật thời tiết';
          _isWeatherLoading = false;
        });
      }
    }
  }

  Future<Position?> _getDevicePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('ℹ️ Location services disabled. Falling back to IP lookup.');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        debugPrint(
            'ℹ️ Location permission not granted. Falling back to IP lookup.');
        return null;
      }

      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
    } catch (e, stack) {
      debugPrint('⚠️ Failed to obtain device location: $e');
      debugPrint('↪ Location stack trace: $stack');
      return null;
    }
  }

  Future<String?> _resolveLocality(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);

      for (final placemark in placemarks) {
        final seen = <String>{};
        final ordered = <String>[];

        void addCandidate(String? value) {
          final trimmed = value?.trim();
          if (trimmed == null || trimmed.isEmpty || seen.contains(trimmed)) {
            return;
          }
          seen.add(trimmed);
          ordered.add(trimmed);
        }

        addCandidate(placemark.subLocality);
        addCandidate(placemark.locality);
        addCandidate(placemark.subAdministrativeArea);
        addCandidate(placemark.administrativeArea);
        addCandidate(placemark.country);

        if (ordered.isNotEmpty) {
          final display = ordered.take(3).join(', ');
          return display;
        }
      }
    } catch (e) {
      // Failed to reverse geocode - silent fail
    }
    return null;
  }

  Future<void> _onUnitChanged(String? unitId) async {
    if (unitId == null || unitId == _selectedUnitId) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedUnitPrefsKey, unitId);

    if (mounted) {
      safeSetState(() {
        _selectedUnitId = unitId;
      });
    }

    await _loadAllData();
  }

  List<UnitInfo> get _ownerUnits {
    final residentId = _profile?['residentId']?.toString();
    if (residentId == null || residentId.isEmpty) return [];
    return _units.where((unit) => unit.isPrimaryResident(residentId)).toList();
  }

  // Removed: int get unreadCount => _notifications.where((n) => !n.isRead).length; - now using ResidentNews from admin API
  int get unreadCount =>
      0; // Placeholder - notifications now come from admin API

  Widget _buildUnpaidSummaryCard(BuildContext context) {
    if (_unpaidBookingCount <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return _HomeGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _openUnpaidBookingsScreen,
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                CupertinoIcons.timer,
                color: AppColors.warning,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dịch vụ chưa thanh toán',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bạn có $_unpaidBookingCount dịch vụ cần xử lý.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              CupertinoIcons.right_chevron,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUnpaidBookingsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const UnpaidServiceBookingsScreen(),
      ),
    );
    await _loadUnpaidServices();
  }

  Future<void> _openCardRegistrationScreen() async {
    final residentId = _profile?['residentId']?.toString();
    final unitId =
        _selectedUnitId ?? (_units.isNotEmpty ? _units.first.id : null);

    if (residentId == null ||
        residentId.isEmpty ||
        unitId == null ||
        unitId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Không xác định được cư dân hoặc căn hộ để hiển thị thẻ'),
        ),
      );
      return;
    }

    final unitName = _unitDisplayName(unitId);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CardRegistrationsScreen(
          residentId: residentId,
          unitId: unitId,
          unitDisplayName: unitName,
          units: _units,
        ),
      ),
    );
  }

  String? _unitDisplayName(String? unitId) {
    if (unitId == null || unitId.isEmpty) return null;
    for (final unit in _units) {
      if (unit.id == unitId) {
        return unit.displayName;
      }
    }
    return null;
  }

  Future<void> _openUnpaidInvoicesScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceListScreen(
          initialUnitId: _selectedUnitId,
          initialUnits: _units,
        ),
      ),
    );
    final invoiceService = InvoiceService(_apiClient);
    await _loadUnpaidInvoices(invoiceService);
  }

  Future<void> _openNotificationsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NotificationScreen(),
      ),
    );
    await _loadUnreadNotifications();
  }

  void _listenForPaymentResult() {
    _paymentSub = _appLinks.uriLinkStream.listen((Uri uri) {
      if (uri.scheme == 'qhomeapp' && uri.host == 'service-booking-result') {
        final status = uri.queryParameters['status'];

        if (status == 'success') {
          _refreshAll();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Thanh toán thành công!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    // Cleaning request removed - no longer used
    // _clearResendTimer();
    // _clearCleaningRequestRefreshTimer();
    _paymentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final themeController = context.watch<ThemeController>();
    final double bottomNavInset = LayoutInsets.bottomNavContentPadding(
      context,
      extra: -LayoutInsets.navBarHeight + 60,
      minimumGap: 16,
    );

    // Ưu tiên fullName, fallback về username, cuối cùng là "Cư dân"
    final name = _profile?['fullName']?.toString().trim().isNotEmpty == true
        ? _profile!['fullName'].toString().trim()
        : (_profile?['username']?.toString().trim().isNotEmpty == true
            ? _profile!['username'].toString().trim()
            : 'Cư dân');

    final backgroundGradient = theme.brightness == Brightness.dark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF020A16),
              Color(0xFF0D1E36),
              Color(0xFF041018),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEAF5FF),
              Color(0xFFF8FBFF),
              Colors.white,
            ],
          );

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: backgroundGradient,
              ),
            ),
          ),
          Positioned(
            top: -media.size.width * 0.25,
            right: -media.size.width * 0.1,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                width: media.size.width * 0.7,
                height: media.size.width * 0.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: _loading
                  ? const _HomeLoadingState()
                  : RefreshIndicator(
                      onRefresh: () async {
                        debugPrint('🔄 [HomeScreen] Pull-to-refresh triggered');
                        await _refreshAll();
                        // Also check for contract reminders after refresh
                        await _checkContractReminders();
                      },
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                        SliverPadding(
                          padding: EdgeInsets.symmetric(
                            horizontal: media.size.width > 900
                                ? media.size.width * 0.18
                                : 24,
                            vertical: 24,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate.fixed(
                              [
                                _buildGreetingSection(
                                  context: context,
                                  name: name,
                                  themeController: themeController,
                                ),
                                const SizedBox(height: 24),
                                _buildWeatherAndAlerts(context),
                                const SizedBox(height: 24),
                                _buildGroupChatCard(context),
                                const SizedBox(height: 24),
                                _buildPriorityAlertsCard(context),
                                const SizedBox(height: 24),
                                _buildFeatureGrid(media.size),
                                const SizedBox(height: 24),
                                _buildServiceDeck(context),
                                const SizedBox(height: 24),
                                if (_unpaidBookingCount > 0)
                                  _buildUnpaidSummaryCard(context),
                                if (_unpaidBookingCount > 0)
                                const SizedBox(height: 24),
                                if (_ownerUnits.isNotEmpty)
                                  _buildHouseholdManagementCard(media.size),
                                if (_ownerUnits.isNotEmpty)
                                  const SizedBox(height: 24),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(height: bottomNavInset),
                        ),
                      ],
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGreetingSection({
    required BuildContext context,
    required String name,
    required ThemeController themeController,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final now = DateTime.now();
    final isDark = themeController.isDark;

    // Get selected unit information
    UnitInfo? selectedUnit;
    if (_units.isNotEmpty) {
      if (_selectedUnitId != null) {
        try {
          selectedUnit = _units.firstWhere(
            (unit) => unit.id == _selectedUnitId,
          );
        } catch (e) {
          // If selected unit not found, use first unit
          selectedUnit = _units.first;
        }
      } else {
        selectedUnit = _units.first;
      }
    }

    // Get greeting text and icon
    final greetingPeriodText = _getGreetingPeriodText(now);
    final timeIcon = _getTimeOfDayIcon(now);

    // Get unit information
    final apartmentName = selectedUnit?.code ?? 'Căn hộ mặc định';
    final buildingName = selectedUnit?.buildingName ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: AppColors.heroBackdropGradient(isDark: isDark),
        boxShadow: AppColors.elevatedShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: Greeting with icon on left, Notification button on right
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting with icon
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Time of day icon with greeting text
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Time of day icon
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            timeIcon,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Greeting period text (smaller)
                        Flexible(
                          child: Text(
                            greetingPeriodText,
                            style: textTheme.titleMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // QR Scanner button
              _buildQrScannerButton(context, theme, isDark),
              const SizedBox(width: 12),
              // Notification button
              _buildNotificationButton(context, theme, isDark),
            ],
          ),
          const SizedBox(height: 20),
          // Unit information (tapable) - only show if unit exists
          if (selectedUnit != null)
            GestureDetector(
              onTap: () {
                // Navigate to settings screen to view unit details
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.house_alt_fill,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            apartmentName,
                            style: textTheme.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          if (buildingName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              buildingName,
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds QR scanner button
  Widget _buildQrScannerButton(
      BuildContext context, ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const QrScannerScreen(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Icon(
          CupertinoIcons.qrcode_viewfinder,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }

  /// Builds notification button with badge for unread notifications
  Widget _buildNotificationButton(
      BuildContext context, ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: _openNotificationsScreen,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Icon(
              CupertinoIcons.bell_fill,
              color: Colors.white,
              size: 22,
            ),
          ),
          // Badge for unread notifications
          if (_unreadNotificationCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF0A1D33) : Colors.white,
                    width: 2,
                  ),
                ),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                child: Center(
                  child: Text(
                    _unreadNotificationCount > 99
                        ? '99+'
                        : '$_unreadNotificationCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  _WeatherDescriptor _describeWeatherCode(int code) {
    if (code == 0) {
      return const _WeatherDescriptor(
          'Trời quang', CupertinoIcons.sun_max_fill);
    } else if (<int>{1, 2}.contains(code)) {
      return const _WeatherDescriptor('Ít mây', CupertinoIcons.cloud_sun_fill);
    } else if (code == 3) {
      return const _WeatherDescriptor('Nhiều mây', CupertinoIcons.cloud_fill);
    } else if (<int>{45, 48}.contains(code)) {
      return const _WeatherDescriptor(
          'Sương mù', CupertinoIcons.cloud_fog_fill);
    } else if (<int>{51, 53, 55, 56, 57}.contains(code)) {
      return const _WeatherDescriptor(
          'Mưa phùn nhẹ', CupertinoIcons.cloud_drizzle_fill);
    } else if (<int>{61, 63, 65}.contains(code)) {
      return const _WeatherDescriptor(
          'Mưa rào', CupertinoIcons.cloud_rain_fill);
    } else if (<int>{66, 67, 80, 81, 82}.contains(code)) {
      return const _WeatherDescriptor(
          'Mưa lớn', CupertinoIcons.cloud_heavyrain_fill);
    } else if (<int>{71, 73, 75, 77, 85, 86}.contains(code)) {
      return const _WeatherDescriptor('Tuyết', CupertinoIcons.cloud_snow_fill);
    } else if (<int>{95, 96, 99}.contains(code)) {
      return const _WeatherDescriptor(
          'Dông', CupertinoIcons.cloud_bolt_rain_fill);
    }
    return const _WeatherDescriptor(
        'Thời tiết ổn định', CupertinoIcons.cloud_fill);
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${diff.inDays} ngày trước';
  }

  Widget _buildPriorityAlertsCard(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    // Calculate total alerts
    final totalAlerts =
        _unpaidInvoiceCount + _unreadNotificationCount + _unpaidBookingCount;

    // Don't show if no alerts and no errors
    if (totalAlerts == 0 &&
        _unpaidServicesError == null &&
        _unpaidInvoicesError == null &&
        _notificationsError == null) {
      return const SizedBox.shrink();
    }

    // Build alert items
    final alertItems = <_AlertItem>[];

    if (_unpaidInvoiceCount > 0) {
      alertItems.add(_AlertItem(
        icon: Icons.receipt_long,
        label: 'Hóa đơn',
        value: '$_unpaidInvoiceCount',
        color: AppColors.warning,
        onTap: _openUnpaidInvoicesScreen,
      ));
    }

    if (_unreadNotificationCount > 0) {
      alertItems.add(_AlertItem(
        icon: Icons.notifications_none,
        label: 'Thông báo',
        value: '$_unreadNotificationCount',
        color: AppColors.primaryBlue,
        onTap: _openNotificationsScreen,
      ));
    }

    if (_unpaidBookingCount > 0) {
      alertItems.add(_AlertItem(
        icon: Icons.pending_actions_outlined,
        label: 'Dịch vụ',
        value: '$_unpaidBookingCount',
        color: AppColors.primaryEmerald,
        onTap: _openUnpaidBookingsScreen,
      ));
    }

    // Add error items
    if (_unpaidInvoicesError != null) {
      alertItems.add(_AlertItem(
        icon: Icons.error_outline,
        label: 'Lỗi hóa đơn',
        value: '!',
        color: AppColors.danger,
        onTap: () async {
          final invoiceService = InvoiceService(_apiClient);
          await _loadUnpaidInvoices(invoiceService);
        },
      ));
    }

    if (_notificationsError != null) {
      alertItems.add(_AlertItem(
        icon: Icons.error_outline,
        label: 'Lỗi thông báo',
        value: '!',
        color: AppColors.danger,
        onTap: () async {
          await _loadUnreadNotifications();
        },
      ));
    }

    if (_unpaidServicesError != null) {
      alertItems.add(_AlertItem(
        icon: Icons.error_outline,
        label: 'Lỗi dịch vụ',
        value: '!',
        color: AppColors.danger,
        onTap: () async {
          await _loadUnpaidServices();
        },
      ));
    }

    if (alertItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return _HomeGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cảnh báo quan trọng',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: alertItems.map((item) {
              final alertItem = item;
              return InkWell(
                onTap: alertItem.onTap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: alertItem.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: alertItem.color.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        alertItem.icon,
                        size: 16,
                        color: alertItem.color,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        alertItem.label,
                        style: textTheme.labelMedium?.copyWith(
                          color: alertItem.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: alertItem.color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          alertItem.value,
                          style: textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherAndAlerts(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final snapshot = _weatherSnapshot;

    return _HomeGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            height: 58,
            width: 58,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient(),
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppColors.subtleShadow,
            ),
            child: Icon(
              snapshot?.weatherIcon ?? CupertinoIcons.sparkles,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              child: _isWeatherLoading
                  ? Row(
                      key: const ValueKey('weather-loading'),
                      children: [
                        SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Đang cập nhật khí hậu...',
                            style: textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    )
                  : (_weatherError != null || snapshot == null)
                      ? Text(
                          _weatherError ?? 'Không lấy được thời tiết',
                          key: const ValueKey('weather-error'),
                          style: textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        )
                      : Column(
                          key: ValueKey(snapshot.city),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              snapshot.city,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${snapshot.temperatureCelsius.toStringAsFixed(1)}°C • ${snapshot.weatherLabel}',
                              style: textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            if (snapshot.windSpeed != null ||
                                snapshot.humidity != null)
                              Text(
                                [
                                  if (snapshot.windSpeed != null)
                                    'Gió ${snapshot.windSpeed?.toStringAsFixed(0)} km/h',
                                  if (snapshot.humidity != null)
                                    'Độ ẩm ${snapshot.humidity?.toStringAsFixed(0)}%',
                                ].join(' · '),
                                style: textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            const SizedBox(height: 2),
                            Text(
                              'Cập nhật ${_formatTime(snapshot.fetchedAt)}',
                              style: textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.45),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Làm mới',
            child: IconButton(
              onPressed: _isWeatherLoading
                  ? null
                  : () => _loadWeatherSnapshot(force: true),
              icon: Icon(
                CupertinoIcons.refresh_bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupChatCard(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return _HomeGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const GroupListScreen(),
            ),
          );
          // Refresh badge when returning from group list
          await _loadGroupChatActivity();
        },
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 56,
                  width: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryBlue,
                        AppColors.primaryBlue.withValues(alpha: 0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: AppColors.subtleShadow,
                  ),
                  child: const Icon(
                    CupertinoIcons.chat_bubble_2_fill,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                // Badge (red dot)
                if (_hasGroupChatActivity)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trò chuyện',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Nhóm chat và trò chuyện trực tiếp',
                    style: textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              CupertinoIcons.right_chevron,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildServiceDeck(BuildContext context) {
    final items = _serviceItems(context);
    return _HomeGlassCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Dịch vụ dành cho bạn',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => widget.onNavigateToTab?.call(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              for (final entry in items.asMap().entries)
                TweenAnimationBuilder<double>(
                  key: ValueKey(entry.value.title),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: entry.key == items.length - 1 ? 0 : 12,
                    ),
                    child: _ServiceCard(data: entry.value),
                  ),
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 20),
                      child: child,
                    ),
                  ),
                ),
            ],
          ),
          // Cleaning request removed - no longer used
          // if (_shouldShowResendCleaningPrompt) ...[
          //   const SizedBox(height: 14),
          //   _buildCleaningResendPrompt(),
          // ],
        ],
      ),
    );
  }

  // Cleaning request removed - no longer used
  // bool get _shouldShowResendCleaningPrompt {
  //   return false;
  // }

  // Duration _timeSinceReference(CleaningRequestSummary request) =>
  //     DateTime.now().difference(_resendReferenceTimestamp(request));

  // Duration _timeUntilAutoCancel(CleaningRequestSummary request) {
  //   // Implementation removed
  // }

  // String _formatDurationLabel(Duration duration) {
  //   // Implementation removed
  // }

  // Widget _buildCleaningResendPrompt() {
  //   // Implementation removed
  // }

  // Future<void> _onSendCleaningRequestAgain() async {
  //   // Implementation removed
  // }

  Widget _buildHouseholdManagementCard(Size size) {
    final ownerUnits = _ownerUnits;
    if (ownerUnits.isEmpty) return const SizedBox.shrink();

    final defaultUnitId = ownerUnits.any((unit) => unit.id == _selectedUnitId)
        ? (_selectedUnitId ?? ownerUnits.first.id)
        : ownerUnits.first.id;
    final selectedOwnerUnit = ownerUnits.firstWhere(
      (unit) => unit.id == defaultUnitId,
      orElse: () => ownerUnits.first,
    );

    final residentName = _profile?['fullName']?.toString() ??
        _profile?['username']?.toString() ??
        'Bạn';

    final theme = Theme.of(context);

    return _HomeGlassCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quản lý hộ gia đình',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '$residentName là chủ hộ của ${ownerUnits.length} căn hộ.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          _HomeActionTile(
            icon: Icons.person_add_outlined,
            accentColor: AppColors.primaryAqua,
            title: 'Đăng ký thành viên mới',
            subtitle: const [
              'Gửi yêu cầu thêm thành viên vào hộ gia đình của bạn.',
            ],
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HouseholdMemberRequestScreen(
                    unit: selectedOwnerUnit,
                  ),
                ),
              );
            },
            actionLabel: 'Gửi yêu cầu',
          ),
          const Divider(),
          _HomeActionTile(
            icon: Icons.group_add_outlined,
            accentColor: AppColors.primaryEmerald,
            title: 'Đăng ký tài khoản cho thành viên',
            subtitle: const [
              'Gửi lời mời tạo tài khoản cho người thân trong hộ gia đình.',
            ],
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HouseholdMemberRegistrationScreen(
                    unit: selectedOwnerUnit,
                  ),
                ),
              );
            },
            actionLabel: 'Tạo yêu cầu',
          ),
          const Divider(),
          _HomeActionTile(
            icon: Icons.assignment_turned_in_outlined,
            accentColor: AppColors.warning,
            title: 'Theo dõi đăng ký thành viên',
            subtitle: const [
              'Xem trạng thái các yêu cầu thêm thành viên đã gửi.',
            ],
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HouseholdMemberRequestStatusScreen(
                    unit: selectedOwnerUnit,
                  ),
                ),
              );
            },
            actionLabel: 'Xem danh sách',
          ),
          const Divider(),
          _HomeActionTile(
            icon: Icons.history_rounded,
            accentColor: AppColors.primaryBlue,
            title: 'Theo dõi trạng thái yêu cầu',
            subtitle: const [
              'Kiểm tra các yêu cầu đã gửi và cập nhật kết quả nhanh chóng.',
            ],
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AccountRequestStatusScreen(
                    unit: selectedOwnerUnit,
                  ),
                ),
              );
            },
            actionLabel: 'Xem danh sách',
          ),
        ],
      ),
    );
  }

  /// Returns greeting period based on time of day:
  /// Morning (5:00 - 11:59): "sáng"
  /// Afternoon (12:00 - 17:59): "chiều"
  /// Evening (18:00 - 4:59): "tối"
  String _getGreetingPeriod(DateTime now) {
    final hour = now.hour;
    if (hour >= 5 && hour < 12) {
      return 'sáng';
    } else if (hour >= 12 && hour < 18) {
      return 'chiều';
    } else {
      return 'tối';
    }
  }

  /// Returns greeting period text based on time of day:
  /// Morning (5:00 - 11:59): "sáng"
  /// Afternoon (12:00 - 17:59): "chiều"
  /// Evening (18:00 - 4:59): "tối"
  String _getGreetingPeriodText(DateTime now) {
    final period = _getGreetingPeriod(now);
    return 'Chào buổi $period';
  }

  /// Returns icon for time of day:
  /// Morning (5:00 - 11:59): sun_max_fill
  /// Afternoon (12:00 - 17:59): cloud_sun_fill
  /// Evening (18:00 - 4:59): moon_stars_fill
  IconData _getTimeOfDayIcon(DateTime now) {
    final hour = now.hour;
    if (hour >= 5 && hour < 12) {
      return CupertinoIcons.sun_max_fill;
    } else if (hour >= 12 && hour < 18) {
      return CupertinoIcons.cloud_sun_fill;
    } else {
      return CupertinoIcons.moon_stars_fill;
    }
  }

  List<_ServiceCardData> _serviceItems(BuildContext context) {
    return [
      _ServiceCardData(
        title: 'Gửi xe',
        subtitle: 'Đăng ký thẻ xe, quản lý bãi đỗ',
        icon: Icons.local_parking_outlined,
        accent: AppColors.primaryBlue,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RegisterVehicleScreen(),
            ),
          );
        },
      ),
      _ServiceCardData(
        title: 'Phản ánh',
        subtitle: 'Phản ánh về tiện ích nội khu sau khi sử dụng',
        icon: Icons.support_agent_outlined,
        accent: AppColors.warning,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FeedbackScreen(),
            ),
          );
        },
      ),
      _ServiceCardData(
        title: 'Thẻ thang máy',
        subtitle: 'Đăng ký và quản lý thẻ thang máy',
        icon: Icons.elevator,
        accent: AppColors.primaryAqua,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RegisterElevatorCardScreen(),
            ),
          );
        },
      ),
      _ServiceCardData(
        title: 'Thẻ cư dân',
        subtitle: 'Đăng ký và quản lý thẻ cư dân',
        icon: CupertinoIcons.person_fill,
        accent: AppColors.primaryEmerald,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RegisterResidentCardScreen(),
            ),
          );
        },
      ),
      _ServiceCardData(
        title: 'Yêu cầu dịch vụ',
        subtitle: 'Theo dõi dọn dẹp & sửa chữa',
        icon: Icons.cleaning_services_outlined,
        accent: AppColors.skyMist,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ServiceRequestsOverviewScreen(),
            ),
          );
        },
      ),
    ];
  }

  Widget _buildFeatureGrid(Size size) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final items = [
      _ServiceCardData(
        title: 'Hóa đơn mới',
        subtitle: 'Xem và thanh toán hóa đơn',
        icon: Icons.description_outlined,
        accent: AppColors.primaryBlue,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InvoiceListScreen(
                initialUnitId: _selectedUnitId,
                initialUnits: _units,
              ),
            ),
          );
        },
      ),
      _ServiceCardData(
        title: 'Đã thanh toán',
        subtitle: 'Lịch sử thanh toán của bạn',
        icon: Icons.verified_outlined,
        accent: AppColors.primaryEmerald,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaidInvoicesScreen(
                initialUnitId: _selectedUnitId,
                initialUnits: _units,
              ),
            ),
          );
        },
      ),
      _ServiceCardData(
        title: 'Tin tức',
        subtitle: 'Cập nhật thông báo & tin tức',
        icon: Icons.newspaper_outlined,
        accent: AppColors.warning,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NewsScreen(),
            ),
          );
        },
      ),
      _ServiceCardData(
        title: 'Quản lý thẻ',
        subtitle: 'Thẻ cư dân & thẻ máy',
        icon: CupertinoIcons.creditcard_fill,
        accent: AppColors.primaryAqua,
        onTap: _openCardRegistrationScreen,
      ),
    ];

    const spacing = 16.0;

    return _HomeGlassCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final tileWidth = (availableWidth - spacing) / 2;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: items.map((data) {
              return SizedBox(
                width: tileWidth,
                child: _FeatureGridTile(
                  data: data,
                  isDark: isDark,
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _FeatureGridTile extends StatefulWidget {
  const _FeatureGridTile({required this.data, required this.isDark});

  final _ServiceCardData data;
  final bool isDark;

  @override
  State<_FeatureGridTile> createState() => _FeatureGridTileState();
}

class _FeatureGridTileState extends State<_FeatureGridTile> with SafeStateMixin<_FeatureGridTile> {
  bool _hover = false;
  bool _pressed = false;

  void _onEnter(bool hover) => safeSetState(() => _hover = hover);
  void _onPressed(bool pressed) => safeSetState(() => _pressed = pressed);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.14)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.6);

    final scale = _pressed ? 0.98 : (_hover ? 1.02 : 1.0);

    return MouseRegion(
      onEnter: (_) => _onEnter(true),
      onExit: (_) => _onEnter(false),
      child: GestureDetector(
        onTapDown: (_) => _onPressed(true),
        onTapUp: (_) {
          _onPressed(false);
          widget.data.onTap();
        },
        onTapCancel: () => _onPressed(false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 2),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: widget.data.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.data.icon, color: widget.data.accent),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.data.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.data.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeGlassCard extends StatelessWidget {
  const _HomeGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(28);
    final gradient = theme.brightness == Brightness.dark
        ? AppColors.darkGlassLayerGradient()
        : AppColors.glassLayerGradient();

    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.08)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.2);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: borderRadius,
            border: Border.all(
              color: borderColor,
            ),
            boxShadow: AppColors.subtleShadow,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

class _AlertItem {
  const _AlertItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;
}

class _ServiceCardData {
  const _ServiceCardData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.data});

  final _ServiceCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _HomeGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: InkWell(
          onTap: data.onTap,
          borderRadius: BorderRadius.circular(22),
          child: Row(
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  color: data.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(data.icon, color: data.accent, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeActionTile extends StatelessWidget {
  const _HomeActionTile({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    required this.actionLabel,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final List<String> subtitle;
  final VoidCallback onPressed;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    ...subtitle.map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          line,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.56),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeLoadingState extends StatelessWidget {
  const _HomeLoadingState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Đang chuẩn bị không gian sống của bạn...',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _WeatherSnapshot {
  const _WeatherSnapshot({
    required this.city,
    required this.temperatureCelsius,
    required this.weatherLabel,
    required this.weatherIcon,
    required this.fetchedAt,
    this.windSpeed,
    this.humidity,
  });

  final String city;
  final double temperatureCelsius;
  final String weatherLabel;
  final IconData weatherIcon;
  final double? windSpeed;
  final double? humidity;
  final DateTime fetchedAt;
}

class _WeatherDescriptor {
  const _WeatherDescriptor(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _WeatherRateLimitException implements Exception {
  const _WeatherRateLimitException({required this.source});

  final String source;
}


