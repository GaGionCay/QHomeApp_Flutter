import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';
import 'package:go_router/go_router.dart';

import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../core/app_router.dart';
import '../models/unit_info.dart';
import '../profile/profile_service.dart';
import '../services/card_pricing_service.dart';
import '../theme/app_colors.dart';
import 'widgets/register_glass_inputs.dart';

class RegisterResidentCardScreen extends StatefulWidget {
  const RegisterResidentCardScreen({super.key});

  @override
  State<RegisterResidentCardScreen> createState() =>
      _RegisterResidentCardScreenState();
}

class _RegisterResidentCardScreenState extends State<RegisterResidentCardScreen>
    with WidgetsBindingObserver {
  final ApiClient api = ApiClient();
  final _formKey = GlobalKey<FormState>();
  static const _storageKey = 'register_resident_card_draft';
  static const _pendingPaymentKey = 'pending_resident_card_payment';
  
  // Card pricing
  double _registrationFee = 30000.0; // Default fallback
  bool _loadingPrice = false;
  late final CardPricingService _cardPricingService;

  final TextEditingController _fullNameCtrl = TextEditingController();
  final TextEditingController _apartmentNumberCtrl = TextEditingController();
  final TextEditingController _buildingNameCtrl = TextEditingController();
  final TextEditingController _citizenIdCtrl = TextEditingController();
  final TextEditingController _phoneNumberCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  bool _submitting = false;
  bool _confirmed = false;
  String? _editingField;
  bool _hasEditedAfterConfirm = false;

  bool _hasUnsavedChanges = false;
  StreamSubscription<Uri?>? _paymentSub;
  final AppLinks _appLinks = AppLinks();
  late final ContractService _contractService;
  String? _selectedUnitId;
  
  Dio? _servicesCardDio;

  String? _defaultPhoneNumber;
  
  // Danh sách cư dân đã chọn
  List<Map<String, dynamic>> _selectedResidents = [];
  List<Map<String, dynamic>> _householdMembers = [];
  bool _loadingHouseholdMembers = false;
  bool _isOwner = false; // Track xem user có phải OWNER không

  Future<Dio> _servicesCardClient() async {
    if (_servicesCardDio == null) {
      _servicesCardDio = Dio(BaseOptions(
        baseUrl: ApiClient.buildServiceBase(port: 8083, path: '/api'),
        connectTimeout: const Duration(seconds: ApiClient.connectTimeoutSeconds),
        receiveTimeout: const Duration(seconds: ApiClient.receiveTimeoutSeconds),
        sendTimeout: const Duration(seconds: ApiClient.sendTimeoutSeconds),
      ));
      _servicesCardDio!.interceptors.add(LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: true,
        responseBody: true,
        error: true,
      ));
      final token = await api.storage.readAccessToken();
      if (token != null && token.isNotEmpty) {
        _servicesCardDio!.options.headers['Authorization'] = 'Bearer $token';
      }
    }
    // Update token in case it changed
    final token = await api.storage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      _servicesCardDio!.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _servicesCardDio!.options.headers.remove('Authorization');
    }
    return _servicesCardDio!;
  }

  static const _selectedUnitPrefsKey = 'selected_unit_id';
  bool _isNavigatingToMain = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _contractService = ContractService(api);
    _cardPricingService = CardPricingService(api.dio);
    _initialize();
    _listenForPaymentResult();
    _setupAutoSave();
    _checkPendingPayment();
    _loadCardPrice();
  }

  void _navigateToServicesHome({String? snackMessage}) {
    if (!mounted || _isNavigatingToMain) return;
    _isNavigatingToMain = true;
    
    // Simply pop back to previous screen (MainShell) instead of using context.go
    // This prevents creating a new MainShell instance and losing authentication state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      // Pop back to MainShell if possible
      if (Navigator.of(context, rootNavigator: false).canPop()) {
        Navigator.of(context, rootNavigator: false).popUntil((route) {
          // Stop at MainShell or first route
          return route.settings.name == AppRoute.main.name || 
                 route.settings.name == AppRoute.main.path ||
                 route.isFirst;
        });
        
        // Show snackbar after navigation
        if (snackMessage != null && snackMessage.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(snackMessage),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          });
        }
      } else {
        // If can't pop, navigate to MainShell (fallback)
        context.go(
          AppRoute.main.path,
          extra: MainShellArgs(
            initialIndex: 1,
            snackMessage: snackMessage,
          ),
        );
      }
    });
  }

  void _initialize() {
    Future.microtask(() async {
      await _loadSavedData();
      await _loadUnitContext();
      // Không tự động load resident context nữa, chỉ load khi user click button
      await _loadResidentContextDataOnly(); // Chỉ load data, không auto-fill
    });
  }

  Future<void> _loadCardPrice() async {
    setState(() => _loadingPrice = true);
    try {
      final price = await _cardPricingService.getCardPrice('RESIDENT');
      if (mounted) {
        setState(() {
          _registrationFee = price;
          _loadingPrice = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [ResidentCard] Lỗi tải giá thẻ: $e');
      if (mounted) {
        setState(() => _loadingPrice = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paymentSub?.cancel();

    _fullNameCtrl.dispose();
    _apartmentNumberCtrl.dispose();
    _buildingNameCtrl.dispose();
    _citizenIdCtrl.dispose();
    _phoneNumberCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _autoSave();
    }
    if (state == AppLifecycleState.resumed) {
      _checkPendingPayment();
    }
    super.didChangeAppLifecycleState(state);
  }

  Future<void> _checkPendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingId = prefs.getString(_pendingPaymentKey);
      if (pendingId == null) return;

      debugPrint('🔍 [ResidentCard] Kiểm tra pending payment: $pendingId');
      final registrationId = pendingId;
      final client = await _servicesCardClient();
      final res = await client.get('/resident-card/$registrationId');
      final data = res.data;
      if (data is! Map<String, dynamic>) return;
      final paymentStatus = data['paymentStatus']?.toString();
      final status = data['status']?.toString();

      debugPrint('🔍 [ResidentCard] Payment status: $paymentStatus, status: $status');

      if (paymentStatus == 'PAID') {
        await prefs.remove(_pendingPaymentKey);
        await _clearSavedData();
        
        // Delay một chút để đảm bảo widget đã được rebuild nếu cần
        await Future.delayed(const Duration(milliseconds: 300));
        
        debugPrint('✅ [ResidentCard] Đang navigate về màn hình chính từ _checkPendingPayment');
        _navigateToServicesHome(
          snackMessage: 'Đăng ký thẻ cư dân đã được thanh toán.',
        );
        return;
      }

      if (paymentStatus == 'UNPAID' || status == 'READY_FOR_PAYMENT') {
        await prefs.remove(_pendingPaymentKey);
      }
    } catch (e) {
      debugPrint('❌ [ResidentCard] Lỗi kiểm tra thanh toán đang chờ: $e');
      // Không xóa pending payment nếu có lỗi, để có thể retry
    }
  }

  void _setupAutoSave() {
    _phoneNumberCtrl.addListener(_markUnsaved);
    _noteCtrl.addListener(_markUnsaved);
  }

  void _markUnsaved() {
    if (_hasUnsavedChanges) return;
    _hasUnsavedChanges = true;
    Future.delayed(const Duration(seconds: 2), () {
      if (_hasUnsavedChanges) {
        _autoSave();
      }
    });
  }

  Future<void> _autoSave() async {
    if (!_hasUnsavedChanges) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'apartmentNumber': _apartmentNumberCtrl.text,
        'buildingName': _buildingNameCtrl.text,
        'phoneNumber': _phoneNumberCtrl.text,
        'note': _noteCtrl.text,
        'unitId': _selectedUnitId,
      };
      await prefs.setString(_storageKey, jsonEncode(data));
    } catch (e) {
      debugPrint('❌ Lỗi lưu nháp tự động: $e');
    }
  }

  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      if (saved == null) return;

      final data = jsonDecode(saved) as Map<String, dynamic>;
      setState(() {
        // Chỉ load các field không phải thông tin cá nhân
        // Không tự động điền: apartmentNumber, buildingName, phoneNumber
        _noteCtrl.text = data['note'] ?? _noteCtrl.text;
        _selectedUnitId = data['unitId']?.toString() ?? _selectedUnitId;
      });
    } catch (e) {
      debugPrint('❌ Lỗi khôi phục dữ liệu nháp: $e');
    }
  }

  Future<void> _loadUnitContext() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUnitId = prefs.getString(_selectedUnitPrefsKey);
      final units = await _contractService.getMyUnits();

      UnitInfo? selectedUnit;
      if (units.isNotEmpty) {
        if (savedUnitId != null) {
          try {
            selectedUnit = units.firstWhere((unit) => unit.id == savedUnitId);
          } catch (_) {}
        }
        selectedUnit ??= units.first;
      }

      if (!mounted) {
        _selectedUnitId = selectedUnit?.id;
        if (selectedUnit != null) {
          _applyUnitContext(selectedUnit);
        }
        return;
      }

      setState(() {
        _selectedUnitId = selectedUnit?.id;
      });

      if (selectedUnit != null) {
        _applyUnitContext(selectedUnit);
        await prefs.setString(_selectedUnitPrefsKey, selectedUnit.id);
        // Load danh sách thành viên khi có unit và check OWNER
        final isOwner = await _loadHouseholdMembers();
        // Nếu không phải OWNER, tự động điền thông tin của chính user
        if (!isOwner) {
          await _loadResidentContextDataOnly();
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi tải thông tin căn hộ: $e');
    }
  }

  void _applyUnitContext(UnitInfo unit) {
    _apartmentNumberCtrl.text = unit.code;
    final building = (unit.buildingName?.isNotEmpty ?? false)
        ? unit.buildingName!
        : (unit.buildingCode ?? '');
    _buildingNameCtrl.text = building;
    _hasUnsavedChanges = false;
  }

  // Chỉ load data, không auto-fill
  Future<void> _loadResidentContextDataOnly() async {
    try {
      final profileService = ProfileService(api.dio);
      final profile = await profileService.getProfile();

      final profilePhone =
          profile['phoneNumber']?.toString() ?? profile['phone']?.toString();
      final profileFullName = profile['fullName']?.toString() ?? '';
      final profileCitizenId = profile['citizenId']?.toString() ?? 
                               profile['identityNumber']?.toString() ?? '';
      final profileResidentId = profile['residentId']?.toString();

      setState(() {
        _defaultPhoneNumber = profilePhone;
        if ((_phoneNumberCtrl.text.isEmpty) &&
            (_defaultPhoneNumber?.isNotEmpty ?? false)) {
          _phoneNumberCtrl.text = _defaultPhoneNumber!;
        }
      });
      
      // Nếu không phải OWNER, tự động điền thông tin và set selectedResidents
      if (!_isOwner && profileResidentId != null && profileResidentId.isNotEmpty) {
        // Tự động điền thông tin của chính user
        if (_fullNameCtrl.text.isEmpty && profileFullName.isNotEmpty) {
          _fullNameCtrl.text = profileFullName;
        }
        if (_citizenIdCtrl.text.isEmpty && profileCitizenId.isNotEmpty) {
          _citizenIdCtrl.text = profileCitizenId;
        }
        
        // Tự động set selectedResidents với chính user
        if (_selectedResidents.isEmpty) {
          setState(() {
            _selectedResidents = [{
              'residentId': profileResidentId,
              'fullName': profileFullName,
              'citizenId': profileCitizenId,
            }];
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi tải thông tin cư dân: $e');
    }
  }
  
  // Load danh sách thành viên trong căn hộ (chỉ OWNER mới được xem)
  Future<bool> _loadHouseholdMembers() async {
    if (_selectedUnitId == null || _selectedUnitId!.isEmpty) {
      return false;
    }
    
    setState(() => _loadingHouseholdMembers = true);
    
    try {
      final client = await _servicesCardClient();
      final res = await client.get(
        '/resident-card/household-members',
        queryParameters: {'unitId': _selectedUnitId},
      );
      
      if (res.statusCode == 200 && res.data is List) {
        setState(() {
          _householdMembers = List<Map<String, dynamic>>.from(res.data);
          _isOwner = true; // User là OWNER
        });
        debugPrint('✅ [ResidentCard] Đã tải ${_householdMembers.length} thành viên');
        return true; // User là OWNER
      }
      return false;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        // User không phải OWNER
        debugPrint('⚠️ [ResidentCard] User không phải OWNER, không thể xem danh sách thành viên');
        setState(() {
          _isOwner = false;
        });
        // Không hiển thị snackbar nữa vì đây là behavior mong muốn
        return false; // User không phải OWNER
      }
      debugPrint('❌ [ResidentCard] Lỗi tải danh sách thành viên: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể tải danh sách thành viên: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint('❌ [ResidentCard] Lỗi tải danh sách thành viên: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể tải danh sách thành viên: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _loadingHouseholdMembers = false);
      }
    }
  }

  // Hiển thị dialog chọn cư dân (chỉ OWNER mới được chọn nhiều người)
  Future<void> _showSelectResidentsDialog() async {
    // Nếu chưa có danh sách thành viên, load trước
    if (_householdMembers.isEmpty && _selectedUnitId != null) {
      final isOwner = await _loadHouseholdMembers();
      if (!mounted) return;
      
      // Nếu không phải OWNER, không hiển thị dialog
      if (!isOwner) {
        return;
      }
    }
    
    // Nếu vẫn không có thành viên
    if (_householdMembers.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không có thành viên nào trong căn hộ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Tạo Set để track các cư dân đã chọn
    final Set<String> selectedResidentIds = _selectedResidents
        .map((r) => r['residentId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    
    if (!mounted) return;
    final List<Map<String, dynamic>>? result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Chọn cư dân đăng ký thẻ'),
            content: SizedBox(
              width: double.maxFinite,
              child: _loadingHouseholdMembers
                  ? const Center(child: CircularProgressIndicator())
                  : _householdMembers.isEmpty
                      ? const Text('Không có thành viên nào trong căn hộ')
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Chọn các cư dân cần đăng ký thẻ cư dân:',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            Flexible(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _householdMembers.length,
                                itemBuilder: (context, index) {
                                  final member = _householdMembers[index];
                                  final residentId = member['residentId']?.toString() ?? '';
                                  final name = member['fullName']?.toString() ?? 'Không có tên';
                                  final citizenId = member['citizenId']?.toString() ?? '';
                                  final hasApprovedCard = member['hasApprovedCard'] == true;
                                  final waitingApproval = member['waitingForApproval'] == true;
                                  final isSelected = selectedResidentIds.contains(residentId);
                                  final disabled = hasApprovedCard || waitingApproval;
                                  
                                  return CheckboxListTile(
                                    title: Text(name),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (citizenId.isNotEmpty) Text('CCCD: $citizenId'),
                                        if (hasApprovedCard)
                                          const Text(
                                            'Đã có thẻ được duyệt',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        if (!hasApprovedCard && waitingApproval)
                                          const Text(
                                            'Đợi ban quản lý duyệt',
                                            style: TextStyle(
                                              color: Colors.blueGrey,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                    value: isSelected,
                                    enabled: !disabled,
                                    onChanged: disabled
                                        ? null
                                        : (bool? value) {
                                            setDialogState(() {
                                              if (value == true) {
                                                selectedResidentIds.add(residentId);
                                              } else {
                                                selectedResidentIds.remove(residentId);
                                              }
                                            });
                                          },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
              TextButton(
                onPressed: () {
                  final selected = _householdMembers
                      .where((member) => selectedResidentIds.contains(
                          member['residentId']?.toString() ?? ''))
                      .toList();
                  Navigator.pop(context, selected);
                },
                child: const Text('Xác nhận', style: TextStyle(color: Colors.teal)),
              ),
            ],
          );
        },
      ),
    );

    if (!mounted) return;
    if (result != null) {
      setState(() {
        _selectedResidents = result;
        _hasUnsavedChanges = true;
      });
      _autoSave();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã chọn ${result.length} cư dân'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
  

  Future<void> _clearSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      _hasUnsavedChanges = false;
    } catch (e) {
      debugPrint('❌ Lỗi xoá dữ liệu nháp: $e');
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges && !_confirmed) return true;

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Thoát màn hình?'),
        content: const Text(
            'Bạn có muốn thoát không? Dữ liệu đã nhập sẽ được lưu tự động.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ở lại'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Thoát', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      await _autoSave();
    }
    return shouldExit ?? false;
  }

  void _listenForPaymentResult() {
    _paymentSub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;
      debugPrint('🔗 [ResidentCard] Nhận deep link: $uri');

      if (uri.scheme == 'qhomeapp' && uri.host == 'vnpay-resident-card-result') {
        final responseCode = uri.queryParameters['responseCode'];
        final successParam = uri.queryParameters['success'];
        final message = uri.queryParameters['message'];

        debugPrint('🔗 [ResidentCard] responseCode: $responseCode, success: $successParam');

        if (responseCode == '00' || (successParam ?? '').toLowerCase() == 'true') {
          await _clearSavedData();

          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(_pendingPaymentKey);
          } catch (e) {
            debugPrint('❌ [ResidentCard] Lỗi xóa pending payment: $e');
          }

          debugPrint('✅ [ResidentCard] Đang navigate về màn hình chính');
          _navigateToServicesHome(
            snackMessage: 'Đăng ký thẻ cư dân đã được thanh toán thành công!',
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message ?? '❌ Thanh toán thất bại. Vui lòng thử lại.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }, onError: (err) {
      debugPrint('❌ [ResidentCard] Lỗi khi nhận deep link: $err');
    });
  }

  String _resolveErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      String? message;
      if (data is Map<String, dynamic>) {
        message = data['message']?.toString();
      } else if (data is String && data.isNotEmpty) {
        message = data;
      }
      
      // Kiểm tra và format message về việc chưa được duyệt thành viên
      if (message != null && message.isNotEmpty) {
        if (message.contains('chưa được duyệt thành thành viên') || 
            message.contains('chưa được duyệt') ||
            message.contains('đợi admin duyệt')) {
          return '⚠️ $message\n\nVui lòng đợi admin duyệt yêu cầu tạo tài khoản trước khi đăng ký thẻ cư dân.';
        }
        return message;
      }
      
      if (error.message != null && error.message!.isNotEmpty) {
        return error.message!;
      }
    }
    // ignore: deprecated_member_use
    if (error is DioError) {
      final data = error.response?.data;
      String? message;
      if (data is Map<String, dynamic>) {
        message = data['message']?.toString();
      } else if (data is String && data.isNotEmpty) {
        message = data;
      }
      
      // Kiểm tra và format message về việc chưa được duyệt thành viên
      if (message != null && message.isNotEmpty) {
        if (message.contains('chưa được duyệt thành thành viên') || 
            message.contains('chưa được duyệt') ||
            message.contains('đợi admin duyệt')) {
          return '⚠️ $message\n\nVui lòng đợi admin duyệt yêu cầu tạo tài khoản trước khi đăng ký thẻ cư dân.';
        }
        return message;
      }
      
      if (error.message != null && error.message!.isNotEmpty) {
        return error.message!;
      }
    }
    // Handle Exception with message
    if (error is Exception) {
      final message = error.toString();
      // Remove "Exception: " prefix if present
      if (message.startsWith('Exception: ')) {
        return message.substring(11);
      }
      return message;
    }
    return error.toString();
  }

  Map<String, dynamic> _collectPayload(Map<String, dynamic> resident) {
    final citizenId = resident['citizenId']?.toString() ?? '';
    
    // Validate CCCD: phải có ít nhất 12 số
    if (citizenId.isNotEmpty) {
      // Normalize: loại bỏ tất cả ký tự không phải số
      final normalizedCitizenId = citizenId.replaceAll(RegExp(r'[^0-9]'), '');
      if (normalizedCitizenId.length < 12) {
        throw Exception('CCCD/CMND phải có ít nhất 12 số');
      }
    }
    
    return {
      'fullName': resident['fullName']?.toString() ?? '',
      'apartmentNumber': _apartmentNumberCtrl.text,
      'buildingName': _buildingNameCtrl.text,
      'citizenId': citizenId,
      'phoneNumber': _phoneNumberCtrl.text,
      'note': _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
      'unitId': _selectedUnitId,
      'residentId': resident['residentId']?.toString(),
    };
  }

  Future<void> _handleRegisterPressed() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_selectedUnitId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Không xác định được căn hộ hiện tại. Vui lòng quay lại màn hình chính.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Kiểm tra đã chọn cư dân chưa
    // Nếu không phải OWNER, _selectedResidents đã được tự động set với chính user
    if (_selectedResidents.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isOwner 
              ? 'Vui lòng chọn ít nhất một cư dân để đăng ký thẻ'
              : 'Vui lòng kiểm tra lại thông tin cá nhân'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_confirmed) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Vui lòng kiểm tra lại thông tin'),
          content: const Text(
            'Vui lòng kiểm tra lại các thông tin đã nhập.\n\n'
            'Sau khi xác nhận, các thông tin sẽ không thể chỉnh sửa trừ khi bạn double-tap vào trường.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Đã kiểm tra',
                  style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        setState(() {
          _confirmed = true;
          _editingField = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '✅ Vui lòng kiểm tra lại thông tin. Double-tap vào trường để chỉnh sửa nếu cần.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      return;
    }

    if (_hasEditedAfterConfirm) {
      final confirmAgain = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Vui lòng kiểm tra lại thông tin'),
          content: const Text(
            'Bạn vừa chỉnh sửa thông tin sau khi đã xác nhận. Vui lòng kiểm tra lại trước khi tiếp tục.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Đã kiểm tra',
                  style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );

      if (confirmAgain == true) {
        setState(() {
          _hasEditedAfterConfirm = false;
          _editingField = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '✅ Vui lòng kiểm tra lại thông tin. Double-tap vào trường để chỉnh sửa nếu cần.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      return;
    }

    await _saveAndPay();
  }

  Future<void> _requestEditField(String field) async {
    if (!_confirmed) return;

    if (_editingField != null && _editingField != field) {
      final wantSwitch = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Đang chỉnh sửa trường khác'),
          content: const Text(
              'Bạn đang chỉnh sửa một trường khác. Bạn có muốn chuyển sang chỉnh sửa trường này không?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Chuyển', style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );
      if (wantSwitch != true) return;
      if (!mounted) return;
    }

    final wantEdit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Chỉnh sửa ${_getFieldLabel(field)}'),
        content: const Text('Bạn có muốn chỉnh sửa thông tin này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Có', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );

    if (wantEdit == true) {
      setState(() {
        _editingField = field;
        _hasEditedAfterConfirm = true;
      });
    }
  }

  String _getFieldLabel(String fieldKey) {
    switch (fieldKey) {
      case 'fullName':
        return 'họ tên cư dân';
      case 'apartmentNumber':
        return 'số căn hộ';
      case 'buildingName':
        return 'tòa nhà';
      case 'citizenId':
        return 'căn cước công dân';
      case 'phoneNumber':
        return 'số điện thoại';
      case 'note':
        return 'ghi chú';
      default:
        return 'thông tin';
    }
  }

  bool _isEditable(String field) {
    if (field == 'note') {
      return !_confirmed || _editingField == field;
    }
    return false;
  }

  Future<void> _saveAndPay() async {
    setState(() => _submitting = true);
    String? registrationId;
    List<String> registrationIds = [];
    String? paymentUrl;

    try {
      final client = await _servicesCardClient();
      
      // Nếu chỉ có 1 cư dân, sử dụng flow cũ (tạo và thanh toán ngay)
      if (_selectedResidents.length == 1) {
        final resident = _selectedResidents[0];
        final residentId = resident['residentId']?.toString();
        
        if (residentId == null || residentId.isEmpty) {
          throw Exception('Thiếu thông tin cư dân');
        }
        
        final payload = _collectPayload(resident);
        final res = await client.post('/resident-card/vnpay-url', data: payload);
        registrationId = res.data['registrationId']?.toString();
        paymentUrl = res.data['paymentUrl']?.toString();
        
        if (registrationId == null || paymentUrl == null) {
          throw Exception('Không thể tạo đăng ký thẻ');
        }
      } else {
        // Nếu có nhiều cư dân, tạo registrations trước (không thanh toán), sau đó gọi batch payment
        for (int i = 0; i < _selectedResidents.length; i++) {
          final resident = _selectedResidents[i];
          final residentId = resident['residentId']?.toString();
          
          if (residentId == null || residentId.isEmpty) {
            continue;
          }
          
          final payload = _collectPayload(resident);
          
          // Tạo registration trước (không thanh toán)
          final res = await client.post('/resident-card', data: payload);
          final regId = res.data['id']?.toString();
          
          if (regId != null) {
            registrationIds.add(regId);
            if (i == 0) {
              registrationId = regId;
            }
          }
        }

        if (registrationIds.isEmpty || _selectedUnitId == null) {
          throw Exception('Không thể tạo đăng ký thẻ');
        }

        // Gọi batch payment với tất cả registration IDs
        final batchPayload = {
          'unitId': _selectedUnitId,
          'registrationIds': registrationIds,
        };
        
        final batchRes = await client.post('/resident-card/batch-payment', data: batchPayload);
        paymentUrl = batchRes.data['paymentUrl']?.toString();
        
        if (paymentUrl == null || paymentUrl.isEmpty) {
          throw Exception('Không thể tạo URL thanh toán');
        }
      }

      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        if (registrationId != null) {
          await prefs.setString(_pendingPaymentKey, registrationId);
        }
        _clearForm();

        final uri = Uri.parse(paymentUrl);
        bool launched = false;
        if (!kIsWeb && Platform.isAndroid) {
          try {
            // Luôn dùng chooser của Android để hiển thị tất cả app hỗ trợ VIEW http(s)
            final intent = AndroidIntent(
              action: 'action_view',
              data: paymentUrl,
            );
            debugPrint('🪟 Launching Android chooser for payment URL');
            await intent.launchChooser('Chọn trình duyệt để thanh toán');
            launched = true;
          } catch (e) {
            debugPrint('⚠️ Không thể mở chooser, fallback url_launcher: $e');
          }
        }
        if (!launched) {
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            launched = true;
          }
        }
        if (!launched) {
          await prefs.remove(_pendingPaymentKey);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể mở trình duyệt thanh toán'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      final message = _resolveErrorMessage(e);
      if (registrationId != null && registrationId.isNotEmpty) {
        await _cancelRegistration(registrationId);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_pendingPaymentKey);
        } catch (err) {
          debugPrint('❌ Lỗi xoá pending payment: $err');
        }
      }

      if (mounted) {
        // Hiển thị thông báo với duration dài hơn nếu là lỗi về việc chưa được duyệt
        final isApprovalError = message.contains('chưa được duyệt') || 
                                message.contains('đợi admin duyệt');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $message'),
            backgroundColor: isApprovalError ? Colors.orange.shade700 : Colors.red,
            duration: isApprovalError ? const Duration(seconds: 6) : const Duration(seconds: 4),
            action: isApprovalError ? SnackBarAction(
              label: 'Đóng',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ) : null,
          ),
        );
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  Future<void> _cancelRegistration(String registrationId) async {
    try {
      log('🗑️ [RegisterResidentCard] Hủy đăng ký: $registrationId');
      final client = await _servicesCardClient();
      await client.delete('/resident-card/$registrationId/cancel');
      log('✅ [RegisterResidentCard] Đã hủy đăng ký thành công');
    } catch (e) {
      log('❌ [RegisterResidentCard] Lỗi khi hủy đăng ký: $e');
    }
  }

  void _clearForm() {
    setState(() {
      _phoneNumberCtrl.clear();
      _noteCtrl.clear();
      _confirmed = false;
      _editingField = null;
      _hasEditedAfterConfirm = false;
      _selectedResidents = [];
    });
    _clearSavedData();
    // Không tự động apply unit context và fill thông tin nữa
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);

    final backgroundGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF050F1F),
              Color(0xFF10243E),
              Color(0xFF050B14),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE7F3FF),
              Color(0xFFF5FAFF),
              Colors.white,
            ],
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(
            'Đăng ký thẻ cư dân',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: colorScheme.onSurface,
          flexibleSpace: DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF07121F),
                        Color(0x3307121F),
                      ],
                    )
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xE6FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                    ),
            ),
          ),
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: backgroundGradient),
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                20,
                24,
                20,
                media.padding.bottom + 36,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFeeInfoCard(),
                    const SizedBox(height: 20),
                    _buildSelectResidentsButton(),
                    if (_selectedResidents.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildSelectedResidentsList(),
                    ],
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _apartmentNumberCtrl,
                      label: 'Số căn hộ',
                      hint: 'Hệ thống tự điền theo căn hộ đang chọn',
                      fieldKey: 'apartmentNumber',
                      icon: Icons.home_outlined,
                      validator: (v) => v == null || v.isEmpty
                          ? 'Vui lòng kiểm tra lại số căn hộ'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    _buildTextField(
                      controller: _buildingNameCtrl,
                      label: 'Tòa nhà',
                      hint: 'Hệ thống tự điền theo căn hộ đang chọn',
                      fieldKey: 'buildingName',
                      icon: Icons.apartment_outlined,
                      validator: (v) => v == null || v.isEmpty
                          ? 'Vui lòng kiểm tra lại tòa nhà'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    _buildTextField(
                      controller: _phoneNumberCtrl,
                      label: 'Số điện thoại',
                      hint: 'Nhập số điện thoại liên hệ',
                      fieldKey: 'phoneNumber',
                      icon: Icons.phone_iphone,
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Vui lòng nhập số điện thoại';
                        }
                        // Không cho phép dấu cách trong số điện thoại
                        if (RegExp(r'\s').hasMatch(v)) {
                          return 'Số điện thoại không được chứa dấu cách';
                        }
                        final trimmed = v.trim().replaceAll(RegExp(r'[\s()-]'), '');
                        if (trimmed.isEmpty) {
                          return 'Số điện thoại không được chỉ chứa khoảng trắng hoặc ký tự đặc biệt';
                        }
                        // Allow digits, +, -, spaces, parentheses (backend pattern: ^[0-9+\-\\s()]+$)
                        if (!RegExp(r'^[0-9+\-()\s]+$').hasMatch(v)) {
                          return 'Số điện thoại không hợp lệ';
                        }
                        // Check if it's a valid Vietnamese phone number (10-11 digits when cleaned)
                        if (!RegExp(r'^[0-9]{10,11}$').hasMatch(trimmed)) {
                          return 'Số điện thoại phải có 10 hoặc 11 số';
                        }
                        // Check if starts with 0 for Vietnamese numbers
                        if (!trimmed.startsWith('0') && !trimmed.startsWith('+84')) {
                          return 'Số điện thoại Việt Nam phải bắt đầu bằng 0 hoặc +84';
                        }
                        if (v.length > 20) {
                          return 'Số điện thoại không được vượt quá 20 ký tự';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    _buildTextField(
                      controller: _noteCtrl,
                      label: 'Ghi chú',
                      hint: 'Nhập ghi chú nếu có',
                      fieldKey: 'note',
                      icon: Icons.notes,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _submitting ? null : _handleRegisterPressed,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: _submitting
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.onPrimary,
                                ),
                              ),
                            )
                          : Text(
                              'Gửi yêu cầu và thanh toán',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectResidentsButton() {
    // Chỉ hiển thị button chọn thành viên nếu là OWNER
    if (!_isOwner) {
      return const SizedBox.shrink();
    }
    
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return RegisterGlassPanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.people_outline,
                color: colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Chọn cư dân đăng ký thẻ',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _showSelectResidentsDialog,
            icon: Icon(Icons.person_add_outlined, color: colorScheme.primary),
            label: Text(
              _selectedResidents.isEmpty
                  ? 'Chọn cư dân'
                  : 'Đã chọn ${_selectedResidents.length} cư dân',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedResidentsList() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return RegisterGlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Danh sách cư dân đã chọn:',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ..._selectedResidents.map((resident) {
            final name = resident['fullName']?.toString() ?? 'Không có tên';
            final citizenId = resident['citizenId']?.toString() ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.person,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (citizenId.isNotEmpty)
                          Text(
                            'CCCD: $citizenId',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(alpha: 0.68),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tổng tiền:',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _formatVnd((_registrationFee * _selectedResidents.length).toInt()),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeeInfoCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalAmount = _selectedResidents.isEmpty
        ? _registrationFee
        : _registrationFee * _selectedResidents.length;
    
    return RegisterGlassPanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient(),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A0B4F6C),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.payments_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phí đăng ký thẻ cư dân',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _loadingPrice
                        ? SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.primary,
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_selectedResidents.isNotEmpty) ...[
                                Text(
                                  '${_formatVnd(_registrationFee.toInt())} × ${_selectedResidents.length} thẻ',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurface.withValues(alpha: 0.68),
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ],
                              Text(
                                _formatVnd(totalAmount.toInt()),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Sau khi gửi yêu cầu, bạn sẽ được chuyển tới cổng thanh toán VNPAY để hoàn tất thanh toán.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.68),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String fieldKey,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    final bool systemLocked = fieldKey != 'note';
    final editable = _isEditable(fieldKey);
    final isEditing = _editingField == fieldKey;

    final displayHint = systemLocked
        ? 'Hệ thống tự động điền, không thể chỉnh sửa'
        : (_confirmed && !editable ? 'Nhấn đúp để yêu cầu chỉnh sửa' : hint);

    return RegisterGlassTextField(
      controller: controller,
      label: label,
      hint: displayHint,
      icon: icon,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: true,
      readOnly: systemLocked || !editable,
      helperText: !systemLocked && isEditing
          ? 'Đang chỉnh sửa... (Nhấn Done để hoàn tất)'
          : null,
      onDoubleTap: systemLocked ? null : () => _requestEditField(fieldKey),
    );
  }

  String _formatVnd(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      final remaining = digits.length - i - 1;
      if (remaining % 3 == 0 && remaining != 0) {
        buffer.write('.');
      }
    }
    buffer.write(' VND');
    return buffer.toString();
  }
}


