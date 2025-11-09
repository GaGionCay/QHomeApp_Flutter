import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/api_client.dart';
import '../common/main_shell.dart';
import '../contracts/contract_service.dart';
import '../core/event_bus.dart';
import '../models/unit_info.dart';

class RegisterElevatorCardScreen extends StatefulWidget {
  const RegisterElevatorCardScreen({super.key});

  @override
  State<RegisterElevatorCardScreen> createState() => _RegisterElevatorCardScreenState();
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

  static const _selectedUnitPrefsKey = 'selected_unit_id';

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

  void _initialize() {
    Future.microtask(() async {
      await _loadSavedData();
      await _loadUnitContext();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paymentSub?.cancel();
    AppEventBus().off('show_payment_success');

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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
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
      final res = await api.dio.get('/elevator-card/$registrationId');
      final data = res.data;
      if (data is! Map<String, dynamic>) return;
      final paymentStatus = data['paymentStatus']?.toString();
      final status = data['status']?.toString();

      if (paymentStatus == 'PAID') {
        await prefs.remove(_pendingPaymentKey);
        if (mounted) {
          AppEventBus().emit(
            'show_payment_success',
            'Đăng ký thẻ thang máy đã được thanh toán.',
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
    AppEventBus().on('show_payment_success', (message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✅ Thanh toán thành công! ${message ?? "Đăng ký thẻ thang máy đã được lưu."}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    });

    _paymentSub = _appLinks.uriLinkStream.listen((uri) async {
      if (uri.scheme != 'qhomeapp' || uri.host != 'vnpay-elevator-card-result') return;
      await _handleDeepLinkPayment(uri);
    });
  }

  Future<void> _handleDeepLinkPayment(Uri uri) async {
    final registrationId = uri.queryParameters['registrationId'];
    final responseCode = uri.queryParameters['responseCode'];
    final successParam = uri.queryParameters['success'];
    final message = uri.queryParameters['message'];

    final success = (successParam ?? '').toLowerCase() == 'true' || responseCode == '00';

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

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const MainShell(initialIndex: 1),
      ),
      (route) => false,
    );

    AppEventBus().emit(
      'show_payment_success',
      'Đăng ký thẻ thang máy đã được thanh toán thành công!',
    );
  }

  Future<void> _handleFailedPayment(String? registrationId, String message) async {
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
      final res = await api.dio.get('/elevator-card/$registrationId');
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
      };

  Future<void> _handleRegisterPressed() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_selectedUnitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không xác định được căn hộ hiện tại. Vui lòng quay lại màn hình chính.'),
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
              child: const Text('Đã kiểm tra', style: TextStyle(color: Colors.teal)),
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
              content: Text('✅ Vui lòng kiểm tra lại thông tin. Double-tap vào trường để chỉnh sửa nếu cần.'),
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
              child: const Text('Đã kiểm tra', style: TextStyle(color: Colors.teal)),
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
              content: Text('✅ Vui lòng kiểm tra lại thông tin. Double-tap vào trường để chỉnh sửa nếu cần.'),
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
      final res = await api.dio.post('/elevator-card/vnpay-url', data: payload);

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
      await api.dio.delete('/elevator-card/$registrationId/cancel');
      log('✅ [RegisterElevatorCard] Đã hủy đăng ký thành công');
    } catch (e) {
      log('❌ [RegisterElevatorCard] Lỗi khi hủy đăng ký: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
        backgroundColor: const Color(0xFFF5F7F9),
        appBar: AppBar(
          title: const Text(
            'Đăng ký thẻ thang máy',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF26A69A),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFeeInfoCard(),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                _buildRequestTypeDropdown(),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _noteCtrl,
                  label: 'Ghi chú',
                  hint: 'Nhập ghi chú nếu có',
                  fieldKey: 'note',
                  icon: Icons.notes,
                  maxLines: 3,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _submitting ? null : _handleRegisterPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF26A69A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Gửi yêu cầu và thanh toán',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeeInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0x1A26A69A),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.payments_outlined,
              color: Color(0xFF26A69A),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phí đăng ký thẻ thang máy',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2933),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatVnd(_registrationFee),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF26A69A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sau khi gửi yêu cầu, bạn sẽ được chuyển tới cổng thanh toán VNPAY để hoàn tất thanh toán.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF617079),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTypeDropdown() {
    final isEditable = _isEditable('requestType');
    return GestureDetector(
      onDoubleTap: () => _requestEditField('requestType'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: DropdownButtonFormField<String>(
          initialValue: _requestType,
          decoration: InputDecoration(
            labelText: 'Loại yêu cầu',
            prefixIcon: const Icon(Icons.category_outlined, color: Color(0xFF26A69A)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: isEditable ? Colors.white : Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
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
          validator: (v) => v == null ? 'Vui lòng chọn loại yêu cầu' : null,
        ),
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
    final isAutoField = _isAutoFilledField(fieldKey);
    final canEdit = !isAutoField && isEditable;
    return GestureDetector(
      onDoubleTap: isAutoField ? null : () => _requestEditField(fieldKey),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextFormField(
          controller: controller,
          enabled: isAutoField ? true : isEditable,
          readOnly: !canEdit,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF26A69A)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: canEdit ? Colors.white : Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ),
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
