import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
  final TextEditingController _citizenIdCtrl = TextEditingController();
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
  String? _defaultCitizenId;
  String? _defaultPhoneNumber;

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
      await _loadResidentContext();
    });
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
        'requestType': _requestType,
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
        _fullNameCtrl.text = data['fullName'] ?? '';
        _apartmentNumberCtrl.text = data['apartmentNumber'] ?? '';
        _buildingNameCtrl.text = data['buildingName'] ?? '';
        _requestType = data['requestType'] ?? 'NEW_CARD';
        _citizenIdCtrl.text = data['citizenId'] ?? '';
        _phoneNumberCtrl.text = data['phoneNumber'] ?? '';
        _noteCtrl.text = data['note'] ?? '';
        _residentId = data['residentId']?.toString() ?? _residentId;
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

  Future<void> _loadResidentContext() async {
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
        _defaultFullName = profileFullName ?? _defaultFullName;
        _defaultCitizenId = profileCitizenId ?? _defaultCitizenId;
        _defaultPhoneNumber = profilePhone ?? _defaultPhoneNumber;

        if (_fullNameCtrl.text.isEmpty &&
            (_defaultFullName?.isNotEmpty ?? false)) {
          _fullNameCtrl.text = _defaultFullName!;
        }
        if (_citizenIdCtrl.text.isEmpty &&
            (_defaultCitizenId?.isNotEmpty ?? false)) {
          _citizenIdCtrl.text = _defaultCitizenId!;
        }
        if (_phoneNumberCtrl.text.isEmpty &&
            (_defaultPhoneNumber?.isNotEmpty ?? false)) {
          _phoneNumberCtrl.text = _defaultPhoneNumber!;
        }
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
      _citizenIdCtrl.clear();
      _phoneNumberCtrl.clear();
      _noteCtrl.clear();
      _confirmed = false;
      _editingField = null;
      _hasEditedAfterConfirm = false;
    });
    _clearSavedData();
    if (_currentUnit != null) {
      _applyUnitContext(_currentUnit!);
    }
  }

  Map<String, dynamic> _collectPayload() => {
        'fullName': _fullNameCtrl.text,
        'apartmentNumber': _apartmentNumberCtrl.text,
        'buildingName': _buildingNameCtrl.text,
        'requestType': _requestType,
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
    if (_isAutoFilledField(field)) return;
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

  bool _isAutoFilledField(String field) =>
      field == 'apartmentNumber' || field == 'buildingName';

  bool _isEditable(String field) {
    if (_isAutoFilledField(field)) {
      return false;
    }
    return !_confirmed || _editingField == field;
  }

  Future<void> _saveAndPay() async {
    setState(() => _submitting = true);
    String? registrationId;

    try {
      final payload = _collectPayload();
      final client = await _servicesCardClient();
      final res = await client.post('/elevator-card/vnpay-url', data: payload);

      registrationId = res.data['registrationId']?.toString();
      final paymentUrl = res.data['paymentUrl'] as String;

      if (mounted && registrationId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_pendingPaymentKey, registrationId);
        _clearForm();

        final uri = Uri.parse(paymentUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
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
      if (registrationId != null) {
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
                    _buildTextField(
                      controller: _fullNameCtrl,
                      label: 'Họ và tên',
                      hint: 'Nhập họ và tên',
                      fieldKey: 'fullName',
                      icon: Icons.person_outline,
                      validator: (v) => v == null || v.isEmpty
                          ? 'Vui lòng nhập họ và tên'
                          : null,
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
                    _buildTextField(
                      controller: _citizenIdCtrl,
                      label: 'Căn cước công dân',
                      hint: 'Nhập số căn cước công dân',
                      fieldKey: 'citizenId',
                      icon: Icons.badge_outlined,
                      validator: (v) => v == null || v.isEmpty
                          ? 'Vui lòng nhập căn cước công dân'
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
                        if (!RegExp(r'^[0-9]{10,11}$').hasMatch(v)) {
                          return 'Số điện thoại không hợp lệ';
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
    final isAutoField = _isAutoFilledField(fieldKey);
    final canEdit = !isAutoField && isEditable;
    final isEditing = _editingField == fieldKey;
    final displayHint = _confirmed && !isEditable && !isAutoField
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
      readOnly: !canEdit,
      helperText:
          isEditing ? 'Đang chỉnh sửa... (Nhấn Done để hoàn tất)' : null,
      onDoubleTap: isAutoField ? null : () => _requestEditField(fieldKey),
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
