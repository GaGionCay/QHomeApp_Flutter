import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';

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
  final _storageKey = 'register_resident_card_draft';
  final _pendingPaymentKey = 'pending_resident_card_payment';
  
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
  UnitInfo? _currentUnit;
  String? _residentId;
  
  Dio? _servicesCardDio;

  String? _defaultFullName;
  String? _defaultCitizenId;
  String? _defaultPhoneNumber;
  
  List<Map<String, dynamic>> _householdMembers = [];
  bool _loadingHouseholdMembers = false;

  Future<Dio> _servicesCardClient() async {
    if (_servicesCardDio == null) {
      _servicesCardDio = Dio(BaseOptions(
        baseUrl: ApiClient.buildServiceBase(port: 8083, path: '/api'),
        connectTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
        receiveTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(
        AppRoute.main.path,
        extra: MainShellArgs(
          initialIndex: 1,
          snackMessage: snackMessage,
        ),
      );
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

      final registrationId = pendingId;
      final client = await _servicesCardClient();
      final res = await client.get('/resident-card/$registrationId');
      final data = res.data;
      if (data is! Map<String, dynamic>) return;
      final paymentStatus = data['paymentStatus']?.toString();
      final status = data['status']?.toString();

      if (paymentStatus == 'PAID') {
        await prefs.remove(_pendingPaymentKey);
        if (mounted) {
          _navigateToServicesHome(
            snackMessage: 'Đăng ký thẻ cư dân đã được thanh toán.',
          );
        }
        return;
      }

      if (paymentStatus == 'UNPAID' || status == 'READY_FOR_PAYMENT') {
        await prefs.remove(_pendingPaymentKey);
      }
    } catch (e) {
      debugPrint('❌ Lỗi kiểm tra thanh toán đang chờ: $e');
    }
  }

  void _setupAutoSave() {
    _fullNameCtrl.addListener(_markUnsaved);
    _citizenIdCtrl.addListener(_markUnsaved);
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
        'fullName': _fullNameCtrl.text,
        'apartmentNumber': _apartmentNumberCtrl.text,
        'buildingName': _buildingNameCtrl.text,
        'citizenId': _citizenIdCtrl.text,
        'phoneNumber': _phoneNumberCtrl.text,
        'note': _noteCtrl.text,
        'residentId': _residentId,
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
        // Không tự động điền: fullName, apartmentNumber, buildingName, citizenId, phoneNumber
        _noteCtrl.text = data['note'] ?? _noteCtrl.text;
        _residentId = data['residentId']?.toString() ?? _residentId;
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
        _currentUnit = selectedUnit;
        if (selectedUnit != null) {
          _applyUnitContext(selectedUnit);
        }
        return;
      }

      setState(() {
        _selectedUnitId = selectedUnit?.id;
        _currentUnit = selectedUnit;
      });

      if (selectedUnit != null) {
        _applyUnitContext(selectedUnit);
        await prefs.setString(_selectedUnitPrefsKey, selectedUnit.id);
        // Load danh sách thành viên khi có unit
        _loadHouseholdMembers();
      }
    } catch (e) {
      debugPrint('❌ Lỗi tải thông tin căn hộ: $e');
    }
  }

  void _applyUnitContext(UnitInfo unit) {
    // Không tự động fill nữa, chỉ lưu thông tin unit
    _hasUnsavedChanges = false;
  }
  
  void _fillUnitContext(UnitInfo unit) {
    _apartmentNumberCtrl.text = unit.code;
    final building = (unit.buildingName?.isNotEmpty ?? false)
        ? unit.buildingName!
        : (unit.buildingCode ?? '');
    _buildingNameCtrl.text = building;
    _hasUnsavedChanges = true;
  }

  // Chỉ load data, không auto-fill
  Future<void> _loadResidentContextDataOnly() async {
    try {
      final profileService = ProfileService(api.dio);
      final profile = await profileService.getProfile();

      final candidateResidentId = profile['residentId']?.toString();
      final profileFullName =
          profile['fullName']?.toString() ?? profile['name']?.toString();
      final profileCitizenId = profile['citizenId']?.toString() ??
          profile['identityNumber']?.toString();
      final profilePhone =
          profile['phoneNumber']?.toString() ?? profile['phone']?.toString();

      setState(() {
        _defaultFullName = profileFullName;
        _defaultCitizenId = profileCitizenId;
        _defaultPhoneNumber = profilePhone;
        if (_residentId == null || _residentId!.isEmpty) {
          _residentId = candidateResidentId;
        }
      });

      if (_residentId == null || _residentId!.isEmpty) {
        final units = await _contractService.getMyUnits();
        for (final unit in units) {
          final candidate = unit.primaryResidentId?.toString();
          if (candidate != null && candidate.isNotEmpty) {
            setState(() {
              _residentId = candidate;
            });
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi tải thông tin cư dân: $e');
    }
  }
  
  // Load danh sách thành viên trong căn hộ
  Future<void> _loadHouseholdMembers() async {
    if (_selectedUnitId == null || _selectedUnitId!.isEmpty) {
      return;
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
        });
        debugPrint('✅ [ResidentCard] Đã tải ${_householdMembers.length} thành viên');
      }
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
    } finally {
      if (mounted) {
        setState(() => _loadingHouseholdMembers = false);
      }
    }
  }

  // Fill thông tin khi user click button
  Future<void> _fillPersonalInfo() async {
    // Nếu chưa có danh sách thành viên, load trước
    if (_householdMembers.isEmpty && _selectedUnitId != null) {
      await _loadHouseholdMembers();
      if (!mounted) return;
    }
    
    // Nếu vẫn không có thành viên hoặc không có unitId, chỉ điền thông tin của user hiện tại
    if (_householdMembers.isEmpty || _selectedUnitId == null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Điền thông tin cá nhân'),
          content: const Text(
            'Bạn có muốn tự động điền thông tin cá nhân của tài khoản đang đăng nhập vào các trường không?\n\n'
            'Các thông tin sẽ được điền vào:\n'
            '- Họ và tên\n'
            '- Số căn hộ\n'
            '- Tòa nhà\n'
            '- Số CCCD/CMND\n'
            '- Số điện thoại',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Điền thông tin', style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        _fillCurrentUserInfo();
      }
      return;
    }
    
    // Hiển thị dialog chọn thành viên
    final selectedMember = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Chọn thành viên'),
        content: SizedBox(
          width: double.maxFinite,
          child: _loadingHouseholdMembers
              ? const Center(child: CircularProgressIndicator())
              : _householdMembers.isEmpty
                  ? const Text('Không có thành viên nào trong căn hộ')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _householdMembers.length,
                      itemBuilder: (context, index) {
                        final member = _householdMembers[index];
                        final name = member['fullName']?.toString() ?? 'Không có tên';
                        final citizenId = member['citizenId']?.toString() ?? '';
                        final hasApprovedCard = member['hasApprovedCard'] == true;
                        final waitingApproval =
                            member['waitingForApproval'] == true;
                        final disabled = hasApprovedCard || waitingApproval;
                        return ListTile(
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
                          enabled: !disabled,
                          onTap: disabled ? null : () => Navigator.pop(context, member),
                        );
                      },
                    ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (selectedMember != null) {
      // Hiển thị popup xác nhận
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Điền thông tin cá nhân'),
          content: Text(
            'Bạn có muốn tự động điền thông tin của ${selectedMember['fullName'] ?? 'thành viên này'} vào các trường không?\n\n'
            'Các thông tin sẽ được điền vào:\n'
            '- Họ và tên\n'
            '- Số căn hộ\n'
            '- Tòa nhà\n'
            '- Số CCCD/CMND\n'
            '- Số điện thoại',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Điền thông tin', style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (confirm == true) {
        _fillMemberInfo(selectedMember);
      }
    }
  }
  
  void _fillCurrentUserInfo() {
    setState(() {
      if (_defaultFullName?.isNotEmpty ?? false) {
        _fullNameCtrl.text = _defaultFullName!;
      }
      if (_defaultCitizenId?.isNotEmpty ?? false) {
        _citizenIdCtrl.text = _defaultCitizenId!;
      }
      if (_defaultPhoneNumber?.isNotEmpty ?? false) {
        _phoneNumberCtrl.text = _defaultPhoneNumber!;
      }
      if (_currentUnit != null) {
        _fillUnitContext(_currentUnit!);
      }
      _hasUnsavedChanges = true;
    });
    _autoSave();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Đã điền thông tin cá nhân'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
  
  void _fillMemberInfo(Map<String, dynamic> member) {
    setState(() {
      final fullName = member['fullName']?.toString();
      final citizenId = member['citizenId']?.toString();
      final phoneNumber = member['phoneNumber']?.toString();
      final residentId = member['residentId']?.toString();
      
      if (fullName?.isNotEmpty ?? false) {
        _fullNameCtrl.text = fullName!;
      }
      if (citizenId?.isNotEmpty ?? false) {
        _citizenIdCtrl.text = citizenId!;
      }
      if (phoneNumber?.isNotEmpty ?? false) {
        _phoneNumberCtrl.text = phoneNumber!;
      }
      if (residentId?.isNotEmpty ?? false) {
        _residentId = residentId;
      }
      if (_currentUnit != null) {
        _fillUnitContext(_currentUnit!);
      }
      _hasUnsavedChanges = true;
    });
    _autoSave();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Đã điền thông tin của ${member['fullName'] ?? 'thành viên'}'),
          duration: const Duration(seconds: 2),
        ),
      );
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
    // Check initial link when app is opened from deep link
    _appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null &&
          uri.scheme == 'qhomeapp' &&
          uri.host == 'vnpay-resident-card-result') {
        _handleDeepLinkPayment(uri);
      }
    }).catchError((err) {
      debugPrint('❌ Lỗi khi lấy initial link: $err');
    });

    // Listen for subsequent deep links
    _paymentSub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;
      if (uri.scheme != 'qhomeapp' || uri.host != 'vnpay-resident-card-result') {
        return;
      }
      await _handleDeepLinkPayment(uri);
    }, onError: (err) {
      debugPrint('❌ Lỗi khi nhận deep link: $err');
    });
  }

  Future<void> _handleDeepLinkPayment(Uri uri) async {
    if (!mounted) return;

    final registrationId = uri.queryParameters['registrationId'];
    final responseCode = uri.queryParameters['responseCode'];
    final successParam = uri.queryParameters['success'];
    final message = uri.queryParameters['message'];

    final success =
        (successParam ?? '').toLowerCase() == 'true' || responseCode == '00';

    if (success) {
      await _finalizeSuccessfulPayment(registrationId);
    } else {
      await _handleFailedPayment(
        registrationId,
        message ?? 'Thanh toán thất bại. Vui lòng thử lại.',
      );
    }
  }

  Future<void> _finalizeSuccessfulPayment(String? registrationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingPaymentKey);
      if (registrationId != null && registrationId.isNotEmpty) {
        await _syncRegistrationStatus(registrationId);
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi khi xử lý thanh toán thành công: $e');
    }

    await _clearSavedData();

    if (!mounted) return;
    _navigateToServicesHome(
      snackMessage: 'Đăng ký thẻ cư dân đã được thanh toán thành công!',
    );
  }

  Future<void> _handleFailedPayment(
      String? registrationId, String message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingPaymentKey);
    } catch (e) {
      debugPrint('⚠️ Lỗi khi xoá pending payment: $e');
    }

    if (registrationId != null && registrationId.isNotEmpty) {
      await _cancelRegistration(registrationId);
    }

    if (!mounted) return;
    final trimmed = message.trim();
    final displayMessage = trimmed.startsWith('❌') ? trimmed : '❌ $trimmed';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(displayMessage),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _syncRegistrationStatus(String registrationId) async {
    try {
      final client = await _servicesCardClient();
      final res = await client.get('/resident-card/$registrationId');
      final data = res.data;
      if (data is! Map<String, dynamic>) return;
      final paymentStatus = data['paymentStatus']?.toString();
      if (paymentStatus != 'PAID') {
        debugPrint('⚠️ paymentStatus chưa cập nhật: $paymentStatus');
      }
    } on DioException catch (e) {
      // Handle 401 gracefully - don't auto-logout after payment
      if (e.response?.statusCode == 401) {
        debugPrint('⚠️ Token expired during payment sync. Status will update automatically.');
        // Don't throw - allow user to continue using app
        return;
      }
      debugPrint('⚠️ Không thể đồng bộ trạng thái đăng ký $registrationId: $e');
    } catch (e) {
      debugPrint('⚠️ Không thể đồng bộ trạng thái đăng ký $registrationId: $e');
    }
  }

  String _resolveErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final message = data['message'];
        if (message is String && message.isNotEmpty) return message;
      } else if (data is String && data.isNotEmpty) {
        return data;
      }
      if (error.message != null && error.message!.isNotEmpty) {
        return error.message!;
      }
    }
    // ignore: deprecated_member_use
    if (error is DioError) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final message = data['message'];
        if (message is String && message.isNotEmpty) return message;
      } else if (data is String && data.isNotEmpty) {
        return data;
      }
      if (error.message != null && error.message!.isNotEmpty) {
        return error.message!;
      }
    }
    return error.toString();
  }

  Map<String, dynamic> _collectPayload() => {
        'fullName': _fullNameCtrl.text,
        'apartmentNumber': _apartmentNumberCtrl.text,
        'buildingName': _buildingNameCtrl.text,
        'citizenId': _citizenIdCtrl.text,
        'phoneNumber': _phoneNumberCtrl.text,
        'note': _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
        'unitId': _selectedUnitId,
        'residentId': _residentId,
      };

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

    if (_residentId == null || _residentId!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Không tìm thấy thông tin cư dân. Vui lòng thử lại sau hoặc liên hệ quản trị.'),
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

    try {
      final payload = _collectPayload();
      final client = await _servicesCardClient();
      final res = await client.post('/resident-card/vnpay-url', data: payload);

      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Phản hồi không hợp lệ từ máy chủ');
      }

      registrationId = data['registrationId']?.toString();
      final paymentUrl = data['paymentUrl']?.toString();

      if (registrationId == null || registrationId.isEmpty) {
        throw Exception('Không nhận được mã đăng ký từ hệ thống');
      }
      if (paymentUrl == null || paymentUrl.isEmpty) {
        throw Exception('Không nhận được URL thanh toán');
      }

      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_pendingPaymentKey, registrationId);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $message')),
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
      _fullNameCtrl.clear();
      _citizenIdCtrl.clear();
      _phoneNumberCtrl.clear();
      _noteCtrl.clear();
      _confirmed = false;
      _editingField = null;
      _hasEditedAfterConfirm = false;
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
                    _buildAutoFillButton(),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _fullNameCtrl,
                      label: 'Họ tên cư dân',
                      hint: 'Nhập họ tên cư dân',
                      fieldKey: 'fullName',
                      icon: Icons.person_outline,
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Vui lòng nhập họ tên cư dân';
                        }
                        final trimmed = v.trim();
                        if (trimmed.isEmpty) {
                          return 'Họ tên cư dân không được chỉ chứa khoảng trắng';
                        }
                        if (trimmed.length > 100) {
                          return 'Họ tên cư dân không được vượt quá 100 ký tự';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
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
                      controller: _citizenIdCtrl,
                      label: 'Căn cước công dân',
                      hint: 'Nhập số căn cước công dân (12 số)',
                      fieldKey: 'citizenId',
                      icon: Icons.badge_outlined,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Vui lòng nhập căn cước công dân';
                        }
                        // Không cho phép dấu cách
                        if (RegExp(r'\s').hasMatch(v)) {
                          return 'Căn cước công dân không được chứa dấu cách';
                        }
                        final trimmed = v.trim().replaceAll(RegExp(r'[\s-]'), '');
                        if (trimmed.isEmpty) {
                          return 'Căn cước công dân không được chỉ chứa khoảng trắng hoặc dấu gạch ngang';
                        }
                        if (!RegExp(r'^[0-9]+$').hasMatch(trimmed)) {
                          return 'Căn cước công dân chỉ được chứa số';
                        }
                        if (trimmed.length != 13) {
                          return 'CCCD phải có đúng 13 số.';
                        }
                        if (trimmed.length > 20) {
                          return 'Căn cước công dân không được vượt quá 20 ký tự';
                        }
                        return null;
                      },
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

  Widget _buildAutoFillButton() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return OutlinedButton.icon(
      onPressed: _fillPersonalInfo,
      icon: Icon(Icons.auto_fix_high, color: colorScheme.primary),
      label: Text(
        'Điền thông tin cá nhân',
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
    );
  }

  Widget _buildFeeInfoCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return RegisterGlassPanel(
      padding: const EdgeInsets.all(22),
      child: Row(
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
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
                    : Text(
                        _formatVnd(_registrationFee.toInt()),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                const SizedBox(height: 8),
                Text(
                  'Sau khi gửi yêu cầu, bạn sẽ được chuyển tới cổng thanh toán VNPAY để hoàn tất thanh toán.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.68),
                    height: 1.45,
                  ),
                ),
              ],
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

