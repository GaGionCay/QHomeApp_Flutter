import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/api_client.dart';
import '../common/main_shell.dart';
import '../contracts/contract_service.dart';
import '../core/event_bus.dart';
import '../models/unit_info.dart';
import 'register_guide_screen.dart';

class RegisterVehicleScreen extends StatefulWidget {
  const RegisterVehicleScreen({super.key});

  @override
  State<RegisterVehicleScreen> createState() => _RegisterServiceScreenState();
}

class _RegisterServiceScreenState extends State<RegisterVehicleScreen>
    with WidgetsBindingObserver {
  final ApiClient api = ApiClient();
  Dio? _servicesCardDio;
  final _formKey = GlobalKey<FormState>();
  final _storageKey = 'register_service_draft';
  final _pendingPaymentKey = 'pending_registration_payment';

  final TextEditingController _licenseCtrl = TextEditingController();
  final TextEditingController _brandCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _apartmentNumberCtrl = TextEditingController();
  final TextEditingController _buildingNameCtrl = TextEditingController();

  String _vehicleType = 'Car';
  String _requestType = 'NEW_CARD'; // Default to 'Làm thẻ mới'
  bool _submitting = false;
  bool _confirmed = false;
  String? _editingField;
  bool _hasEditedAfterConfirm = false;
  final ImagePicker _picker = ImagePicker();
  List<String> _uploadedImageUrls = [];
  static const int maxImages = 6;
  String? _selectedUnitId;
  static const _selectedUnitPrefsKey = 'selected_unit_id';
  late final ContractService _contractService;
  UnitInfo? _currentUnit;

  bool _hasUnsavedChanges = false;
  StreamSubscription<Uri?>? _paymentSub;
  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _contractService = ContractService(api);
    _loadSavedData();
    _loadUnitContext();
    _listenForPaymentResult();
    _setupAutoSave();
    _checkPendingPayment();
  }

  void _listenForPaymentResult() {
    AppEventBus().on('show_payment_success', (message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Thanh toán thành công! ${message ?? "Đăng ký xe đã được lưu."}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    _paymentSub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;

      if (uri.scheme == 'qhomeapp' && uri.host == 'vnpay-registration-result') {
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
              builder: (_) => const MainShell(initialIndex: 1),
            ),
            (route) => false,
          ).then((_) {
            Future.delayed(const Duration(milliseconds: 100), () {
              AppEventBus()
                  .emit('show_payment_success', 'Đăng ký xe đã được lưu');
            });
          });
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Thanh toán thất bại. Vui lòng thử lại.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }, onError: (err) {
      debugPrint('❌ Lỗi khi nhận deep link: $err');
    });
  }

  Future<Dio> _servicesCardClient() async {
    if (_servicesCardDio == null) {
      _servicesCardDio = Dio(BaseOptions(
        baseUrl: 'http://${ApiClient.HOST_IP}:8083/api',
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
        logPrint: (obj) => print('🔍 DIO LOG: $obj'),
      ));
    }

    final token = await api.storage.readAccessToken();
    if (token != null) {
      _servicesCardDio!.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _servicesCardDio!.options.headers.remove('Authorization');
    }
    return _servicesCardDio!;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paymentSub?.cancel();
    AppEventBus().off('show_payment_success');
    _licenseCtrl.dispose();
    _brandCtrl.dispose();
    _colorCtrl.dispose();
    _noteCtrl.dispose();
    _apartmentNumberCtrl.dispose();
    _buildingNameCtrl.dispose();
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
  }

  Future<void> _checkPendingPayment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final registrationId = prefs.getString(_pendingPaymentKey);

      if (registrationId == null || registrationId.isEmpty) return;

      final client = await _servicesCardClient();
      final res = await client.get('/register-service/$registrationId');
      final data = res.data;
      final paymentStatus = data['paymentStatus'] as String?;

      if (paymentStatus == 'PAID') {
        await prefs.remove(_pendingPaymentKey);
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => const MainShell(initialIndex: 1),
            ),
            (route) => false,
          ).then((_) {
            Future.delayed(const Duration(milliseconds: 100), () {
              AppEventBus()
                  .emit('show_payment_success', 'Thanh toán đã hoàn tất');
            });
          });
        }
      } else if (paymentStatus == 'UNPAID') {
        if (mounted) {
          final shouldPay = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Thanh toán chưa hoàn tất'),
              content: Text(
                'Đăng ký xe #$registrationId chưa được thanh toán.\n\n'
                'Bạn có muốn thanh toán ngay bây giờ không?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Hủy'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Thanh toán',
                      style: TextStyle(color: Colors.teal)),
                ),
              ],
            ),
          );

          if (shouldPay == true && mounted) {
            AppEventBus().emit('pay_registration', registrationId);
          } else {
            await prefs.remove(_pendingPaymentKey);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi check pending payment: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingPaymentKey);
      } catch (_) {}
    }
  }

  void _setupAutoSave() {
    _licenseCtrl.addListener(_autoSave);
    _brandCtrl.addListener(_autoSave);
    _colorCtrl.addListener(_autoSave);
    _noteCtrl.addListener(_autoSave);
    _apartmentNumberCtrl.addListener(_autoSave);
    _buildingNameCtrl.addListener(_autoSave);
  }

  Future<void> _autoSave() async {
    if (!_hasUnsavedChanges) {
      _hasUnsavedChanges = true;
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'vehicleType': _vehicleType,
        'requestType': _requestType,
        'licensePlate': _licenseCtrl.text,
        'vehicleBrand': _brandCtrl.text,
        'vehicleColor': _colorCtrl.text,
        'note': _noteCtrl.text,
        'unitId': _selectedUnitId,
        'apartmentNumber': _apartmentNumberCtrl.text,
        'buildingName': _buildingNameCtrl.text,
        'imageUrls': _uploadedImageUrls,
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
          _vehicleType = data['vehicleType'] ?? 'Car';
          _requestType = data['requestType'] ?? 'NEW_CARD';
          _licenseCtrl.text = data['licensePlate'] ?? '';
          _brandCtrl.text = data['vehicleBrand'] ?? '';
          _colorCtrl.text = data['vehicleColor'] ?? '';
          _noteCtrl.text = data['note'] ?? '';
          _uploadedImageUrls = List<String>.from(data['imageUrls'] ?? []);
          _selectedUnitId = data['unitId']?.toString() ?? _selectedUnitId;
          _apartmentNumberCtrl.text =
              data['apartmentNumber']?.toString() ?? _apartmentNumberCtrl.text;
          _buildingNameCtrl.text =
              data['buildingName']?.toString() ?? _buildingNameCtrl.text;
        });

        debugPrint('✅ Đã load lại dữ liệu đã lưu');
      }
    } catch (e) {
      debugPrint('❌ Lỗi load saved data: $e');
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
      debugPrint('⚠️ [RegisterService] Không đọc được thông tin căn hộ: $e');
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

  Future<void> _pickMultipleImages() async {
    final remainingSlots = maxImages - _uploadedImageUrls.length;
    if (remainingSlots <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Bạn chỉ được tải tối đa $maxImages ảnh'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final picked = await _picker.pickMultiImage(imageQuality: 75);
    if (picked.isEmpty) return;

    final imagesToUpload = picked.take(remainingSlots).toList();
    if (picked.length > remainingSlots && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '⚠️ Chỉ có thể tải thêm $remainingSlots ảnh (tối đa $maxImages ảnh). Đã chọn $remainingSlots ảnh đầu tiên.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    await _uploadImages(imagesToUpload);
    await _autoSave();
  }

  Future<void> _takePhoto() async {
    if (_uploadedImageUrls.length >= maxImages) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Bạn chỉ được tải tối đa $maxImages ảnh'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final photo =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (photo != null) {
      await _uploadImages([photo]);
      await _autoSave();
    }
  }

  Future<void> _uploadImages(List<XFile> files) async {
    setState(() => _submitting = true);
    try {
      final formData = FormData.fromMap({
        'files': await Future.wait(
          files.map(
              (f) async => MultipartFile.fromFile(f.path, filename: f.name)),
        ),
      });
      final client = await _servicesCardClient();
      final res = await client.post('/register-service/upload-images', data: formData);
      final urls =
          (res.data['imageUrls'] as List?)?.map((e) => e.toString()).toList() ??
              [];

      setState(() => _uploadedImageUrls.addAll(urls));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Đã tải lên ${urls.length} ảnh thành công! (${_uploadedImageUrls.length}/$maxImages)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload lỗi: $e')),
        );
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  String _makeFullImageUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    const base = 'http://${ApiClient.HOST_IP}:8083';
    return base + url;
  }

  Map<String, dynamic> _collectPayload() => {
        'serviceType': 'VEHICLE_REGISTRATION',
        'requestType': _requestType,
        'note': _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
        'unitId': _selectedUnitId,
        'apartmentNumber': _apartmentNumberCtrl.text,
        'buildingName': _buildingNameCtrl.text,
        'vehicleType': _vehicleType,
        'licensePlate': _licenseCtrl.text,
        'vehicleBrand': _brandCtrl.text,
        'vehicleColor': _colorCtrl.text,
        'imageUrls': _uploadedImageUrls,
      };

  void _removeImageAt(int i) {
    setState(() => _uploadedImageUrls.removeAt(i));
    _autoSave();
  }

  Future<void> _handleRegisterPressed() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_selectedUnitId == null || _selectedUnitId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Không xác định được căn hộ hiện tại. Vui lòng quay lại màn hình chính.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_apartmentNumberCtrl.text.isEmpty || _buildingNameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng kiểm tra lại số căn hộ và tòa nhà.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_uploadedImageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Vui lòng tải lên ít nhất 1 ảnh xe'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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
    if (_isAutoFilledField(field)) return;
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
      case 'requestType':
        return 'loại yêu cầu';
      case 'apartmentNumber':
        return 'số căn hộ';
      case 'buildingName':
        return 'tòa nhà';
      case 'license':
        return 'biển số xe';
      case 'brand':
        return 'hãng xe';
      case 'color':
        return 'màu xe';
      case 'note':
        return 'ghi chú';
      default:
        return 'thông tin';
    }
  }

  bool _isAutoFilledField(String field) =>
      field == 'apartmentNumber' || field == 'buildingName';

  bool _canRemoveImage(int index) {
    return !_confirmed || _editingField == 'image_$index';
  }

  Future<void> _requestDeleteImage(int index) async {
    if (!_confirmed) {
      _removeImageAt(index);
      return;
    }

    final wantDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa ảnh'),
        content: const Text('Bạn có muốn xóa ảnh này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (wantDelete == true) {
      setState(() {
        _editingField = 'image_$index';
        _hasEditedAfterConfirm = true;
      });
      _removeImageAt(index);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() => _editingField = null);
        }
      });
    }
  }

  bool _isEditable(String field) =>
      !_isAutoFilledField(field) && (!_confirmed || _editingField == field);

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

  Future<void> _saveAndPay() async {
    setState(() => _submitting = true);
    String? registrationId;

    try {
      final payload = _collectPayload();

      final client = await _servicesCardClient();
      final res = await client.post('/register-service/vnpay-url', data: payload);

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

  Future<void> _cancelRegistration(String registrationId) async {
    try {
      log('🗑️ [RegisterService] Hủy registration: $registrationId');
      final client = await _servicesCardClient();
      await client.delete('/register-service/$registrationId/cancel');
      log('✅ [RegisterService] Đã hủy registration thành công');
    } catch (e) {
      log('❌ [RegisterService] Lỗi khi hủy registration: $e');
    }
  }

  void _clearForm() {
    setState(() {
      _licenseCtrl.clear();
      _brandCtrl.clear();
      _colorCtrl.clear();
      _noteCtrl.clear();
      _apartmentNumberCtrl.clear();
      _buildingNameCtrl.clear();
      _vehicleType = 'Car';
      _requestType = 'NEW_CARD';
      _uploadedImageUrls.clear();
      _confirmed = false;
      _editingField = null;
      _hasEditedAfterConfirm = false;
      _hasUnsavedChanges = false;
    });
    if (_currentUnit != null) {
      _applyUnitContext(_currentUnit!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        key: const ValueKey('form'),
        backgroundColor: const Color(0xFFF5F7F9),
        appBar: AppBar(
          backgroundColor: const Color(0xFF26A69A),
          title: const Text('Đăng ký thẻ xe'),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: 'Hướng dẫn đăng ký',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RegisterGuideScreen()),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Phí đăng ký thẻ xe: 30.000 VNĐ',
                            style: TextStyle(
                              color: Colors.blue.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _vehicleType,
                          decoration: const InputDecoration(
                              labelText: 'Loại phương tiện'),
                          items: const [
                            DropdownMenuItem(value: 'Car', child: Text('Ô tô')),
                            DropdownMenuItem(
                                value: 'Motorbike', child: Text('Xe máy')),
                          ],
                          onChanged:
                              (_confirmed && _editingField != 'vehicleType')
                                  ? null
                                  : (v) {
                                      setState(() {
                                        _vehicleType = v ?? 'Car';
                                        if (_confirmed) {
                                          _editingField = 'vehicleType';
                                          _hasEditedAfterConfirm = true;
                                        }
                                      });
                                      _autoSave();
                                    },
                        ),
                        const SizedBox(height: 12),
                        _buildRequestTypeDropdown(),
                        const SizedBox(height: 12),
                        _buildEditableField(
                          label: 'Số căn hộ',
                          controller: _apartmentNumberCtrl,
                          icon: Icons.home_outlined,
                          fieldKey: 'apartmentNumber',
                          validator: (v) => v!.isEmpty
                              ? 'Vui lòng kiểm tra lại số căn hộ'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _buildEditableField(
                          label: 'Tòa nhà',
                          controller: _buildingNameCtrl,
                          icon: Icons.apartment_outlined,
                          fieldKey: 'buildingName',
                          validator: (v) => v!.isEmpty
                              ? 'Vui lòng kiểm tra lại tòa nhà'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _buildEditableField(
                          label: 'Biển số xe',
                          controller: _licenseCtrl,
                          icon: _vehicleType == 'Car'
                              ? Icons.directions_car
                              : Icons.two_wheeler,
                          fieldKey: 'license',
                          validator: (v) =>
                              v!.isEmpty ? 'Vui lòng nhập biển số xe' : null,
                        ),
                        const SizedBox(height: 12),
                        _buildEditableField(
                          label: 'Hãng xe',
                          controller: _brandCtrl,
                          icon: Icons.factory_outlined,
                          fieldKey: 'brand',
                          validator: (v) =>
                              v!.isEmpty ? 'Vui lòng nhập hãng xe' : null,
                        ),
                        const SizedBox(height: 12),
                        _buildEditableField(
                          label: 'Màu xe',
                          controller: _colorCtrl,
                          icon: Icons.palette_outlined,
                          fieldKey: 'color',
                          validator: (v) =>
                              v!.isEmpty ? 'Vui lòng nhập màu xe' : null,
                        ),
                        const SizedBox(height: 12),
                        _buildEditableField(
                          label: 'Ghi chú thêm',
                          controller: _noteCtrl,
                          icon: Icons.note_alt_outlined,
                          fieldKey: 'note',
                          maxLines: 2,
                          validator: (_) => null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Ảnh xe của bạn',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${_uploadedImageUrls.length}/$maxImages',
                        style: TextStyle(
                          fontSize: 14,
                          color: _uploadedImageUrls.length >= maxImages
                              ? Colors.orange
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _uploadedImageUrls.isEmpty
                      ? Container(
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(child: Text('Chưa chọn ảnh xe')),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              List.generate(_uploadedImageUrls.length, (i) {
                            final canRemove = _canRemoveImage(i);
                            return GestureDetector(
                              onDoubleTap: () => _requestDeleteImage(i),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Opacity(
                                      opacity: canRemove ? 1.0 : 0.7,
                                      child: Image.network(
                                        _makeFullImageUrl(
                                            _uploadedImageUrls[i]),
                                        width: 110,
                                        height: 110,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  if (canRemove)
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: const Icon(Icons.close,
                                            size: 16, color: Colors.white),
                                      ),
                                    ),
                                  if (_confirmed && !canRemove)
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: const BorderRadius.only(
                                            bottomLeft: Radius.circular(10),
                                            bottomRight: Radius.circular(10),
                                          ),
                                        ),
                                        child: const Text(
                                          'Double-tap để xóa',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                        ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _confirmed ||
                                  _submitting ||
                                  _uploadedImageUrls.length >= maxImages
                              ? null
                              : _pickMultipleImages,
                          icon: const Icon(Icons.photo_library),
                          label: Text(_uploadedImageUrls.length >= maxImages
                              ? 'Đã đủ ($maxImages ảnh)'
                              : 'Chọn ảnh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade400,
                            disabledBackgroundColor: Colors.grey.shade300,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _confirmed ||
                                  _submitting ||
                                  _uploadedImageUrls.length >= maxImages
                              ? null
                              : _takePhoto,
                          icon: const Icon(Icons.camera_alt),
                          label: Text(_uploadedImageUrls.length >= maxImages
                              ? 'Đã đủ ($maxImages ảnh)'
                              : 'Chụp ảnh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade600,
                            disabledBackgroundColor: Colors.grey.shade300,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _handleRegisterPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF26A69A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 3,
                      ),
                      child: _submitting
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            )
                          : Text(
                              _confirmed
                                  ? (_hasEditedAfterConfirm
                                      ? 'Xác nhận và thanh toán'
                                      : 'Đăng ký và thanh toán (30.000 VNĐ)')
                                  : 'Đăng ký và thanh toán (30.000 VNĐ)',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String fieldKey,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    final isAutoField = _isAutoFilledField(fieldKey);
    final editable = _isEditable(fieldKey);
    final canEdit = editable && !isAutoField;
    final isEditing = _editingField == fieldKey;

    return GestureDetector(
      onDoubleTap: isAutoField ? null : () => _requestEditField(fieldKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          boxShadow: isEditing
              ? [
                  BoxShadow(
                    color: Colors.teal.withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: canEdit ? 1.0 : 0.7,
          child: IgnorePointer(
            ignoring: !canEdit,
            child: TextFormField(
              controller: controller,
              readOnly: !canEdit,
              validator: validator,
              maxLines: maxLines,
              onTap: () {
                if (isEditing) return;

                if (_confirmed && !canEdit && !isAutoField) {
                  _requestEditField(fieldKey);
                }
              },
              onEditingComplete: () {
                if (isEditing && mounted) {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _editingField = null;
                  });
                  _autoSave();
                }
              },
              onFieldSubmitted: (_) {
                if (isEditing && mounted) {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _editingField = null;
                  });
                  _autoSave();
                }
              },
              onChanged: (value) {
                if (isEditing) {
                  _autoSave();
                }
              },
              decoration: InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon),
                filled: true,
                fillColor: editable ? Colors.white : Colors.grey.shade200,
                hintText: _confirmed && !editable
                    ? 'Double-click để chỉnh sửa'
                    : null,
                helperText: isEditing
                    ? 'Đang chỉnh sửa... (Nhấn Done để hoàn tất)'
                    : null,
                helperMaxLines: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
