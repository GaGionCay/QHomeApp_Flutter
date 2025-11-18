import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../core/app_router.dart';
import '../models/unit_info.dart';
import '../profile/profile_service.dart';
import '../theme/app_colors.dart';
import 'widgets/register_glass_inputs.dart';

class RegisterElevatorCardScreen extends StatefulWidget {
  const RegisterElevatorCardScreen({super.key});

  @override
  State<RegisterElevatorCardScreen> createState() =>
      _RegisterElevatorCardScreenState();
}

class _RegisterElevatorCardScreenState extends State<RegisterElevatorCardScreen>
    with WidgetsBindingObserver {
  final ApiClient api = ApiClient();
  final _formKey = GlobalKey<FormState>();
  final _storageKey = 'register_elevator_card_draft';
  final _pendingPaymentKey = 'pending_elevator_card_payment';
  static const int _registrationFee = 30000;

  final TextEditingController _fullNameCtrl = TextEditingController();
  final TextEditingController _apartmentNumberCtrl = TextEditingController();
  final TextEditingController _buildingNameCtrl = TextEditingController();
  final TextEditingController _phoneNumberCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _requestType = 'NEW_CARD';
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
  String? _defaultPhoneNumber;
  
  // Số lượng thẻ có thể đăng ký
  int _cardQuantity = 1;
  int _maxCards = 0;
  int _registeredCards = 0;
  bool _loadingMaxCards = false;

  static const _selectedUnitPrefsKey = 'selected_unit_id';
  bool _isNavigatingToMain = false;

  Future<Dio> _servicesCardClient() async {
    if (_servicesCardDio == null) {
      _servicesCardDio = Dio(BaseOptions(
        baseUrl: ApiClient.buildServiceBase(port: 8083, path: '/api'),
        connectTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
        receiveTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _contractService = ContractService(api);
    _initialize();
    _listenForPaymentResult();
    _setupAutoSave();
    _checkPendingPayment();
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paymentSub?.cancel();

    _fullNameCtrl.dispose();
    _apartmentNumberCtrl.dispose();
    _buildingNameCtrl.dispose();
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
      final res = await client.get('/elevator-card/$registrationId');
      final data = res.data;
      if (data is! Map<String, dynamic>) return;
      final paymentStatus = data['paymentStatus']?.toString();
      final status = data['status']?.toString();

      if (paymentStatus == 'PAID') {
        await prefs.remove(_pendingPaymentKey);
        if (mounted) {
          _navigateToServicesHome(
            snackMessage: 'Đăng ký thẻ thang máy đã được thanh toán.',
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
        'requestType': _requestType,
        'phoneNumber': _phoneNumberCtrl.text,
        'note': _noteCtrl.text,
        'residentId': _residentId,
        'unitId': _selectedUnitId,
        'cardQuantity': _cardQuantity,
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
        // Không tự động điền: fullName, apartmentNumber, buildingName, phoneNumber
        _requestType = data['requestType'] ?? 'NEW_CARD';
        _noteCtrl.text = data['note'] ?? '';
        _residentId = data['residentId']?.toString() ?? _residentId;
        _cardQuantity = data['cardQuantity'] ?? 1;
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
        // Load max cards info when unit changes
        await _loadMaxCardsInfo();
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

  Future<void> _loadMaxCardsInfo() async {
    if (_selectedUnitId == null) {
      debugPrint('⚠️ [ElevatorCard] Không có unitId để load max cards info');
      return;
    }
    
    setState(() => _loadingMaxCards = true);
    try {
      final client = await _servicesCardClient();
      debugPrint('🔍 [ElevatorCard] Đang gọi API max-cards với unitId: $_selectedUnitId');
      
      final res = await client.get('/elevator-card/max-cards', queryParameters: {
        'unitId': _selectedUnitId,
      });
      
      debugPrint('✅ [ElevatorCard] Response từ API max-cards: ${res.data}');
      
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        final maxCards = (data['maxCards'] as num?)?.toInt();
        final registeredCards = (data['registeredCards'] as num?)?.toInt() ?? 0;
        final remainingSlots = (data['remainingSlots'] as num?)?.toInt() ?? 0;
        
        debugPrint('📊 [ElevatorCard] maxCards: $maxCards, registeredCards: $registeredCards, remainingSlots: $remainingSlots');
        
        if (maxCards == null || maxCards <= 0) {
          debugPrint('⚠️ [ElevatorCard] maxCards không hợp lệ ($maxCards), không cập nhật');
          // Không cập nhật nếu giá trị không hợp lệ
          return;
        }
        
        setState(() {
          _maxCards = maxCards;
          _registeredCards = registeredCards;
          // Set card quantity to remaining slots if available, otherwise 1
          if (_cardQuantity > remainingSlots && remainingSlots > 0) {
            _cardQuantity = remainingSlots;
          } else if (_cardQuantity < 1) {
            _cardQuantity = 1;
          }
          // Đảm bảo không vượt quá remaining slots
          if (_cardQuantity > remainingSlots && remainingSlots > 0) {
            _cardQuantity = remainingSlots;
          }
        });
        
        debugPrint('✅ [ElevatorCard] Đã cập nhật: maxCards=$_maxCards, registeredCards=$_registeredCards, cardQuantity=$_cardQuantity');
      } else {
        debugPrint('⚠️ [ElevatorCard] Response không phải Map: ${res.data.runtimeType}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [ElevatorCard] Lỗi tải thông tin số lượng thẻ tối đa: $e');
      debugPrint('❌ [ElevatorCard] Stack trace: $stackTrace');
      
      // Không set fallback 999 nữa, để user biết có lỗi
      // Chỉ reset về giá trị mặc định hợp lý (0 hoặc giữ nguyên giá trị cũ)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Không thể tải thông tin số lượng thẻ tối đa. Vui lòng thử lại.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMaxCards = false);
      }
    }
  }

  // Chỉ load data, không auto-fill
  Future<void> _loadResidentContextDataOnly() async {
    try {
      final profileService = ProfileService(api.dio);
      final profile = await profileService.getProfile();

      final candidateResidentId = profile['residentId']?.toString();
      final profileFullName =
          profile['fullName']?.toString() ?? profile['name']?.toString();
      final profilePhone =
          profile['phoneNumber']?.toString() ?? profile['phone']?.toString();

      setState(() {
        _defaultFullName = profileFullName;
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
  
  // Fill thông tin khi user click button
  Future<void> _fillPersonalInfo() async {
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
      setState(() {
        if (_defaultFullName?.isNotEmpty ?? false) {
          _fullNameCtrl.text = _defaultFullName!;
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
          uri.host == 'vnpay-elevator-card-result') {
        _handleDeepLinkPayment(uri);
      }
    }).catchError((err) {
      debugPrint('❌ Lỗi khi lấy initial link: $err');
    });

    // Listen for subsequent deep links
    _paymentSub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;
      if (uri.scheme != 'qhomeapp' || uri.host != 'vnpay-elevator-card-result')
        return;
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
      if (registrationId != null) {
        await _syncRegistrationStatus(registrationId);
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi khi xử lý thanh toán thành công: $e');
    }

    await _clearSavedData();

    if (!mounted) return;
    _navigateToServicesHome(
      snackMessage: 'Đăng ký thẻ thang máy đã được thanh toán thành công!',
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

    if (registrationId != null) {
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
      final res = await client.get('/elevator-card/$registrationId');
      final data = res.data;
      if (data is! Map<String, dynamic>) return;
      final paymentStatus = data['paymentStatus']?.toString();
      if (paymentStatus != 'PAID') {
        debugPrint('⚠️ paymentStatus chưa cập nhật: $paymentStatus');
      }
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

  void _clearForm() {
    setState(() {
      _fullNameCtrl.clear();
      _requestType = 'NEW_CARD';
      _phoneNumberCtrl.clear();
      _noteCtrl.clear();
      _confirmed = false;
      _editingField = null;
      _hasEditedAfterConfirm = false;
      _cardQuantity = 1;
    });
    _clearSavedData();
    // Không tự động apply unit context nữa
  }

  Map<String, dynamic> _collectPayload() => {
        'fullName': _fullNameCtrl.text,
        'apartmentNumber': _apartmentNumberCtrl.text,
        'buildingName': _buildingNameCtrl.text,
        'requestType': _requestType,
        'phoneNumber': _phoneNumberCtrl.text,
        'note': _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
        'unitId': _selectedUnitId,
        'residentId': _residentId,
      };

  Future<void> _handleRegisterPressed() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_selectedUnitId == null) {
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
          content: const Text('''Vui lòng kiểm tra lại các thông tin đã nhập.

Sau khi xác nhận, các thông tin sẽ không thể chỉnh sửa trừ khi bạn double-tap vào trường.'''),
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
        return 'họ và tên';
      case 'apartmentNumber':
        return 'số căn hộ';
      case 'buildingName':
        return 'tòa nhà';
      case 'requestType':
        return 'loại yêu cầu';
      case 'phoneNumber':
        return 'số điện thoại';
      case 'note':
        return 'ghi chú';
      default:
        return 'thông tin';
    }
  }

  bool _isEditable(String field) {
    return !_confirmed || _editingField == field;
  }

  Future<void> _saveAndPay() async {
    setState(() => _submitting = true);
    String? registrationId;
    List<String> registrationIds = [];
    String? paymentUrl;

    try {
      final payload = _collectPayload();
      final client = await _servicesCardClient();
      
      // Tạo nhiều registration nếu quantity > 1
      // Lưu ý: Backend chỉ hỗ trợ tạo 1 registration mỗi lần, nên cần gọi nhiều lần
      for (int i = 0; i < _cardQuantity; i++) {
        final res = await client.post('/elevator-card/vnpay-url', data: payload);
        final regId = res.data['registrationId']?.toString();
        final payUrl = res.data['paymentUrl']?.toString();
        if (regId != null) {
          registrationIds.add(regId);
          // Chỉ lấy paymentUrl và registrationId từ registration đầu tiên
          if (i == 0) {
            registrationId = regId;
            paymentUrl = payUrl;
          }
        }
      }

      if (registrationId == null || registrationIds.isEmpty || paymentUrl == null) {
        throw Exception('Không thể tạo đăng ký thẻ');
      }

      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_pendingPaymentKey, registrationId);
        _clearForm();

        final uri = Uri.parse(paymentUrl);
        bool launched = false;
        if (!kIsWeb && Platform.isAndroid) {
          try {
            final intent = AndroidIntent(
              action: 'action_view',
              data: paymentUrl,
            );
            await intent.launchChooser('Chọn trình duyệt để thanh toán');
            launched = true;
          } catch (e) {
            debugPrint('⚠️ Không thể mở chooser, fallback url_launcher: $e');
          }
        }
        if (!launched && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          launched = true;
        }
        if (!launched) {
          await prefs.remove(_pendingPaymentKey);
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
      // Cancel all created registrations if error occurs
      for (final regId in registrationIds) {
        await _cancelRegistration(regId);
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingPaymentKey);
      } catch (err) {
        debugPrint('❌ Lỗi xoá pending payment: $err');
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
      log('🗑️ [RegisterElevatorCard] Hủy đăng ký: $registrationId');
      final client = await _servicesCardClient();
      await client.delete('/elevator-card/$registrationId/cancel');
      log('✅ [RegisterElevatorCard] Đã hủy đăng ký thành công');
    } catch (e) {
      log('❌ [RegisterElevatorCard] Lỗi khi hủy đăng ký: $e');
    }
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
          if (shouldPop && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(
            'Đăng ký thẻ thang máy',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: colorScheme.onSurface,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF07121F),
                        Color(0x4407121F),
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
                      label: 'Họ và tên',
                      hint: 'Nhập họ và tên',
                      fieldKey: 'fullName',
                      icon: Icons.person_outline,
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Vui lòng nhập họ và tên';
                        }
                        final trimmed = v.trim();
                        if (trimmed.isEmpty) {
                          return 'Họ và tên không được chỉ chứa khoảng trắng';
                        }
                        if (trimmed.length > 100) {
                          return 'Họ và tên không được vượt quá 100 ký tự';
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
                    _buildRequestTypeDropdown(),
                    const SizedBox(height: 18),
                    _buildCardQuantitySelector(),
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
        side: BorderSide(color: colorScheme.primary.withOpacity(0.5)),
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
                  size: 26,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phí đăng ký thẻ thang máy',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatVnd(_registrationFee),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Sau khi gửi yêu cầu, bạn sẽ được chuyển tới cổng thanh toán VNPAY để hoàn tất thanh toán. Vui lòng chuẩn bị thông tin thanh toán trước khi tiếp tục.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.68),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTypeDropdown() {
    final isEditable = _isEditable('requestType');
    return RegisterGlassDropdown<String>(
      value: _requestType,
      label: 'Loại yêu cầu',
      hint: 'Chọn loại thẻ',
      icon: Icons.category_outlined,
      enabled: isEditable,
      validator: (v) => v == null ? 'Vui lòng chọn loại yêu cầu' : null,
      items: const [
        DropdownMenuItem(
          value: 'NEW_CARD',
          child: Text('Làm thẻ mới'),
        ),
        DropdownMenuItem(
          value: 'REPLACE_CARD',
          child: Text('Cấp lại thẻ bị mất'),
        ),
      ],
      onChanged: isEditable
          ? (value) {
              setState(() {
                _requestType = value ?? 'NEW_CARD';
                if (_confirmed) {
                  _editingField = 'requestType';
                  _hasEditedAfterConfirm = true;
                }
              });
              _autoSave();
            }
          : null,
      onDoubleTap: isEditable ? null : () => _requestEditField('requestType'),
    );
  }

  Widget _buildCardQuantitySelector() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final remainingSlots = _maxCards > 0 ? _maxCards - _registeredCards : 0;
    final maxSelectable = remainingSlots > 0 ? remainingSlots : 1;
    
    return RegisterGlassPanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.credit_card_outlined,
                color: colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Số lượng thẻ đăng ký',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_loadingMaxCards)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_maxCards > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Căn hộ này có thể đăng ký tối đa $_maxCards thẻ (đã đăng ký $_registeredCards thẻ, còn lại $remainingSlots slot)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.68),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                onPressed: _cardQuantity > 1
                    ? () {
                        setState(() {
                          _cardQuantity--;
                          _hasUnsavedChanges = true;
                        });
                        _autoSave();
                      }
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                style: IconButton.styleFrom(
                  backgroundColor: _cardQuantity > 1
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '$_cardQuantity',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: _cardQuantity < maxSelectable
                    ? () {
                        setState(() {
                          _cardQuantity++;
                          _hasUnsavedChanges = true;
                        });
                        _autoSave();
                      }
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                style: IconButton.styleFrom(
                  backgroundColor: _cardQuantity < maxSelectable
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceVariant,
                ),
              ),
              const Spacer(),
              if (_maxCards > 0 && remainingSlots <= 0)
                Text(
                  'Đã đạt giới hạn',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
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
    final isEditable = _isEditable(fieldKey);
    final isEditing = _editingField == fieldKey;
    final displayHint = _confirmed && !isEditable
        ? 'Nhấn đúp để yêu cầu chỉnh sửa'
        : hint;

    return RegisterGlassTextField(
      controller: controller,
      label: label,
      hint: displayHint,
      icon: icon,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: true,
      readOnly: !isEditable,
      helperText:
          isEditing ? 'Đang chỉnh sửa... (Nhấn Done để hoàn tất)' : null,
      onDoubleTap: () => _requestEditField(fieldKey),
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
