import 'dart:convert';
import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../auth/api_client.dart';
import '../core/event_bus.dart';
import '../common/main_shell.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedData();
    _listenForPaymentResult();
    _setupAutoSave();
    _checkPendingPayment();
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
      if (pendingId != null) {
        final registrationId = int.parse(pendingId);
        final res = await api.dio.get('/elevator-card/$registrationId');
        final data = res.data;
        if (data['paymentStatus'] == 'PAID') {
          await prefs.remove(_pendingPaymentKey);
          if (mounted) {
            AppEventBus().emit('show_payment_success', 'Đăng ký thẻ thang máy đã được thanh toán.');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi check pending payment: $e');
    }
  }

  void _setupAutoSave() {
    _fullNameCtrl.addListener(() => _markUnsaved());
    _apartmentNumberCtrl.addListener(() => _markUnsaved());
    _buildingNameCtrl.addListener(() => _markUnsaved());
    _citizenIdCtrl.addListener(() => _markUnsaved());
    _phoneNumberCtrl.addListener(() => _markUnsaved());
    _noteCtrl.addListener(() => _markUnsaved());
  }

  void _markUnsaved() {
    if (!_hasUnsavedChanges) {
      _hasUnsavedChanges = true;
      Future.delayed(const Duration(seconds: 2), () {
        if (_hasUnsavedChanges) {
          _autoSave();
        }
      });
    }
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
      debugPrint('❌ Lỗi auto-save: $e');
    }
  }

  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      if (saved != null) {
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

        debugPrint('✅ Đã load lại dữ liệu đã lưu');
      }
    } catch (e) {
      debugPrint('❌ Lỗi load saved data: $e');
    }
  }

  Future<void> _clearSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      _hasUnsavedChanges = false;
    } catch (e) {
      debugPrint('❌ Lỗi clear saved data: $e');
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Thanh toán thành công! ${message ?? "Đăng ký thẻ thang máy đã được lưu."}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
    
    _paymentSub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;

      if (uri.scheme == 'qhomeapp' && uri.host == 'vnpay-elevator-card-result') {
        final registrationId = uri.queryParameters['registrationId'];
        final responseCode = uri.queryParameters['responseCode'];

        if (!mounted) return;

        if (responseCode == '00') {
          await _clearSavedData();

          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(_pendingPaymentKey);
          } catch (e) {
            debugPrint('❌ Lỗi xóa pending payment: $e');
          }

          if (!mounted) return;

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => const MainShell(initialIndex: 2),
            ),
            (route) => false,
          );

          AppEventBus().emit('show_payment_success',
              'Đăng ký thẻ thang máy đã được thanh toán thành công!');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Thanh toán thất bại'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  void _clearForm() {
    setState(() {
      _fullNameCtrl.clear();
      _apartmentNumberCtrl.clear();
      _buildingNameCtrl.clear();
      _requestType = 'NEW_CARD';
      _citizenIdCtrl.clear();
      _phoneNumberCtrl.clear();
      _noteCtrl.clear();
      _confirmed = false;
      _editingField = null;
      _hasEditedAfterConfirm = false;
    });
    _clearSavedData();
  }

  Map<String, dynamic> _collectPayload() => {
        'fullName': _fullNameCtrl.text,
        'apartmentNumber': _apartmentNumberCtrl.text,
        'buildingName': _buildingNameCtrl.text,
        'requestType': _requestType,
        'citizenId': _citizenIdCtrl.text,
        'phoneNumber': _phoneNumberCtrl.text,
        'note': _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
      };

  Future<void> _handleRegisterPressed() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (!_confirmed) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Vui lòng check lại thông tin'),
          content: const Text(
            'Vui lòng kiểm tra lại các thông tin đã nhập.\n\n'
            'Sau khi xác nhận, các thông tin sẽ không thể chỉnh sửa trừ khi bạn double-click vào field.',
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
                  '✅ Vui lòng kiểm tra lại thông tin. Double-click vào field để chỉnh sửa.'),
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
          title: const Text('Vui lòng check lại thông tin'),
          content: const Text(
            'Bạn đã chỉnh sửa thông tin. Vui lòng kiểm tra lại các thông tin đã nhập.\n\n'
            'Nếu cần chỉnh sửa, double-click vào field.',
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
                  '✅ Vui lòng kiểm tra lại thông tin. Double-click vào field để chỉnh sửa.'),
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
          title: const Text('Đang chỉnh sửa field khác'),
          content: const Text(
              'Bạn đang chỉnh sửa một field khác. Bạn có muốn chuyển sang field này không?'),
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

  bool _isEditable(String field) => !_confirmed || _editingField == field;

  Future<void> _saveAndPay() async {
    setState(() => _submitting = true);
    int? registrationId;

    try {
      final payload = _collectPayload();

      final res =
          await api.dio.post('/elevator-card/vnpay-url', data: payload);

      registrationId = res.data['registrationId'] as int?;
      final paymentUrl = res.data['paymentUrl'] as String;

      if (mounted && registrationId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_pendingPaymentKey, registrationId.toString());
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );

        if (registrationId != null) {
          await _cancelRegistration(registrationId);
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(_pendingPaymentKey);
          } catch (e) {
            debugPrint('❌ Lỗi xóa pending payment: $e');
          }
        }
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  Future<void> _cancelRegistration(int registrationId) async {
    try {
      log('🗑️ [RegisterElevatorCard] Hủy registration: $registrationId');
      await api.dio.delete('/elevator-card/$registrationId/cancel');
      log('✅ [RegisterElevatorCard] Đã hủy registration thành công');
    } catch (e) {
      log('❌ [RegisterElevatorCard] Lỗi khi hủy registration: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && context.mounted) {
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
          actions: [],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTextField(
                  controller: _fullNameCtrl,
                  label: 'Họ và tên',
                  hint: 'Nhập họ và tên',
                  fieldKey: 'fullName',
                  icon: Icons.person,
                  validator: (v) => v == null || v.isEmpty
                      ? 'Vui lòng nhập họ và tên'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _apartmentNumberCtrl,
                  label: 'Số căn hộ',
                  hint: 'Nhập số căn hộ',
                  fieldKey: 'apartmentNumber',
                  icon: Icons.home,
                  validator: (v) => v == null || v.isEmpty
                      ? 'Vui lòng nhập số căn hộ'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _buildingNameCtrl,
                  label: 'Tòa nhà',
                  hint: 'Nhập tên tòa nhà',
                  fieldKey: 'buildingName',
                  icon: Icons.business,
                  validator: (v) => v == null || v.isEmpty
                      ? 'Vui lòng nhập tên tòa nhà'
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
                  icon: Icons.badge,
                  validator: (v) => v == null || v.isEmpty
                      ? 'Vui lòng nhập căn cước công dân'
                      : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _phoneNumberCtrl,
                  label: 'Số điện thoại',
                  hint: 'Nhập số điện thoại',
                  fieldKey: 'phoneNumber',
                  icon: Icons.phone,
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
                  hint: 'Nhập ghi chú (nếu có)',
                  fieldKey: 'note',
                  icon: Icons.note,
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
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
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
          value: _requestType,
          decoration: InputDecoration(
            labelText: 'Loại yêu cầu',
            prefixIcon: const Icon(Icons.category, color: Color(0xFF26A69A)),
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
          onChanged: isEditable ? (value) {
            setState(() {
              _requestType = value ?? 'NEW_CARD';
              if (_confirmed) {
                _editingField = 'requestType';
                _hasEditedAfterConfirm = true;
              }
            });
            _autoSave();
          } : null,
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
    return GestureDetector(
      onDoubleTap: () => _requestEditField(fieldKey),
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
          enabled: isEditable,
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
            fillColor: isEditable ? Colors.white : Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }
}

