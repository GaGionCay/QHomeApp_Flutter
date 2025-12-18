// ignore_for_file: use_build_context_synchronously
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
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../core/app_router.dart';
import '../core/safe_state_mixin.dart';
import '../models/unit_info.dart';
import '../services/card_pricing_service.dart';
import '../services/imagekit_service.dart';
import 'register_guide_screen.dart';
import '../theme/app_colors.dart';
import 'widgets/register_glass_inputs.dart';

class RegisterVehicleScreen extends StatefulWidget {
  const RegisterVehicleScreen({super.key});

  @override
  State<RegisterVehicleScreen> createState() => _RegisterServiceScreenState();
}

class _RegisterServiceScreenState extends State<RegisterVehicleScreen>
    with WidgetsBindingObserver, SafeStateMixin<RegisterVehicleScreen> {
  final ApiClient api = ApiClient();
  Dio? _servicesCardDio;
  final _formKey = GlobalKey<FormState>();
  static const _storageKey = 'register_service_draft';
  static const _pendingPaymentKey = 'pending_registration_payment';
  
  // Card pricing
  double _registrationFee = 30000.0; // Default fallback
  bool _loadingPrice = false;
  late final CardPricingService _cardPricingService;
  late final ImageKitService _imageKitService;

  final TextEditingController _licenseCtrl = TextEditingController();
  final TextEditingController _brandCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _apartmentNumberCtrl = TextEditingController();
  final TextEditingController _buildingNameCtrl = TextEditingController();

  String _vehicleType = 'Car';
  bool _submitting = false;
  bool _confirmed = false;
  String? _editingField;
  bool _hasEditedAfterConfirm = false;
  double? _uploadProgress;
  final ImagePicker _picker = ImagePicker();
  List<String> _uploadedImageUrls = [];
  static const int maxImages = 6;
  String? _selectedUnitId;
  static const _selectedUnitPrefsKey = 'selected_unit_id';
  late final ContractService _contractService;

  bool _hasUnsavedChanges = false;
  StreamSubscription<Uri?>? _paymentSub;
  final AppLinks _appLinks = AppLinks();
  bool _isNavigatingToMain = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Register all TextEditingControllers with SafeStateMixin
    registerControllers([
      _licenseCtrl,
      _brandCtrl,
      _colorCtrl,
      _noteCtrl,
      _apartmentNumberCtrl,
      _buildingNameCtrl,
    ]);
    
    _contractService = ContractService(api);
    _cardPricingService = CardPricingService(api.dio);
    _imageKitService = ImageKitService(api);
    _loadSavedData();
    _loadUnitContext();
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

  void _listenForPaymentResult() {
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
          _navigateToServicesHome(
            snackMessage: 'Đăng ký xe đã được thanh toán thành công!',
          );
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
        baseUrl: ApiClient.buildServiceBase(port: 8083),
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
    
    // SafeStateMixin will automatically dispose all registered controllers
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
          _navigateToServicesHome(
            snackMessage: 'Thanh toán đăng ký xe đã hoàn tất.',
          );
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
            await _resumePendingPayment(registrationId);
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

  Future<void> _resumePendingPayment(String registrationId) async {
    try {
      final client = await _servicesCardClient();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingPaymentKey, registrationId);

      final res =
          await client.post('/register-service/$registrationId/vnpay-url');

      if (res.statusCode != 200) {
        await prefs.remove(_pendingPaymentKey);
        final message =
            res.data is Map<String, dynamic> ? res.data['message'] : null;
        throw Exception(message ?? 'Không thể tạo liên kết thanh toán');
      }

      final paymentUrl = res.data['paymentUrl']?.toString();
      if (paymentUrl == null || paymentUrl.isEmpty) {
        await prefs.remove(_pendingPaymentKey);
        throw Exception('Không nhận được đường dẫn thanh toán');
      }

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
      if (!launched) {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          launched = true;
        }
      }
      if (!launched) {
        await prefs.remove(_pendingPaymentKey);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể mở trình duyệt thanh toán'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    } catch (e) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingPaymentKey);
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể tiếp tục thanh toán: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
      }
    } catch (e) {
      debugPrint('⚠️ [RegisterService] Không đọc được thông tin căn hộ: $e');
    }
  }

  void _applyUnitContext(UnitInfo unit) {
    _fillUnitContext(unit, markUnsaved: false);
  }
  
  void _fillUnitContext(UnitInfo unit, {bool markUnsaved = true}) {
    _apartmentNumberCtrl.text = unit.code;
    final building = (unit.buildingName?.isNotEmpty ?? false)
        ? unit.buildingName!
        : (unit.buildingCode ?? '');
    _buildingNameCtrl.text = building;
    if (markUnsaved) {
      _hasUnsavedChanges = true;
    }
  }

  Future<void> _loadCardPrice() async {
    setState(() => _loadingPrice = true);
    try {
      final price = await _cardPricingService.getCardPrice('VEHICLE');
      if (mounted) {
        setState(() {
          _registrationFee = price;
          _loadingPrice = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [VehicleCard] Lỗi tải giá thẻ: $e');
      if (mounted) {
        setState(() => _loadingPrice = false);
      }
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

  Future<void> _pickMultipleImages() async {
    if (_submitting) return;
    
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

    try {
      final picked = await _picker.pickMultiImage(imageQuality: 75);
      if (picked.isEmpty || !mounted) return;

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
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Không thể chọn ảnh';
        if (e.toString().contains('Permission')) {
          errorMessage = 'Vui lòng cấp quyền truy cập ảnh trong cài đặt';
        } else if (e.toString().contains('cancel')) {
          // User cancelled, no need to show error
          return;
        } else {
          errorMessage = 'Lỗi khi chọn ảnh: ${e.toString()}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    if (_submitting) return;
    
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

    try {
      final photo =
          await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (photo != null && mounted) {
        await _uploadImages([photo]);
        await _autoSave();
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Không thể chụp ảnh';
        if (e.toString().contains('Permission') || e.toString().contains('permission')) {
          errorMessage = 'Vui lòng cấp quyền truy cập camera trong cài đặt';
        } else if (e.toString().contains('cancel')) {
          // User cancelled, no need to show error
          return;
        } else {
          errorMessage = 'Lỗi khi chụp ảnh: ${e.toString()}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadImages(List<XFile> files) async {
    if (files.isEmpty || !mounted) return;
    
    setState(() {
      _submitting = true;
      _uploadProgress = 0.0;
    });
    
    try {
      // Validate file sizes (max 10MB per file)
      const maxFileSize = 10 * 1024 * 1024; // 10MB
      for (final file in files) {
        final fileSize = await file.length();
        if (fileSize > maxFileSize) {
          throw Exception(
              'File "${file.name}" quá lớn (${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB). Kích thước tối đa là 10MB');
        }
        if (fileSize == 0) {
          throw Exception('File "${file.name}" không hợp lệ hoặc đã bị hỏng');
        }
      }
      
      // Upload to ImageKit with folder "vehicle-registration"
      final urls = await _imageKitService.uploadImages(
        files: files,
        folder: 'vehicle-registration',
      );

      if (urls.isEmpty) {
        throw Exception('Không nhận được URL ảnh từ ImageKit');
      }

      setState(() {
        _uploadedImageUrls.addAll(urls);
        _uploadProgress = null; // Reset progress
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Đã tải lên ${urls.length} ảnh thành công! (${_uploadedImageUrls.length}/$maxImages)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadProgress = null); // Reset progress on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploadProgress = null;
        });
      }
    }
  }

  String _makeFullImageUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    final base = ApiClient.buildServiceBase(port: 8083);
    return base + url;
  }

  Map<String, dynamic> _collectPayload() => {
        'serviceType': 'VEHICLE_REGISTRATION',
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
      !_confirmed || _editingField == field;

  Widget _buildFeeNoticeCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return RegisterGlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 52,
            width: 52,
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
              Icons.local_parking,
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
                  'Phí đăng ký thẻ xe',
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
                    : Text(
                        _formatVnd(_registrationFee.toInt()),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                        ),
                      ),
                const SizedBox(height: 8),
                Text(
                  'Phí áp dụng cho mỗi thẻ phương tiện. Bạn sẽ được chuyển tới VNPAY để hoàn tất thanh toán ngay sau khi gửi yêu cầu.',
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

  Widget _buildVehicleFormCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canEditVehicleType = !_confirmed || _editingField == 'vehicleType';

    return RegisterGlassPanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.qr_code_2,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Thông tin đăng ký',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          RegisterGlassDropdown<String>(
            value: _vehicleType,
            label: 'Loại phương tiện',
            hint: 'Chọn loại phương tiện',
            icon: _vehicleType == 'Car'
                ? Icons.directions_car
                : Icons.two_wheeler,
            enabled: canEditVehicleType,
            onDoubleTap: canEditVehicleType
                ? null
                : () => _requestEditField('vehicleType'),
            onChanged: canEditVehicleType
                ? (value) {
                    setState(() {
                      _vehicleType = value ?? 'Car';
                      if (_confirmed) {
                        _editingField = 'vehicleType';
                        _hasEditedAfterConfirm = true;
                      }
                    });
                    _autoSave();
                  }
                : null,
            validator: (_) => null,
            items: const [
              DropdownMenuItem(value: 'Car', child: Text('Ô tô')),
              DropdownMenuItem(value: 'Motorbike', child: Text('Xe máy')),
            ],
          ),
          const SizedBox(height: 16),
          _buildEditableField(
            label: 'Số căn hộ',
            controller: _apartmentNumberCtrl,
            icon: Icons.home_outlined,
            fieldKey: 'apartmentNumber',
            validator: (v) => v == null || v.isEmpty
                ? 'Vui lòng kiểm tra lại số căn hộ'
                : null,
            hint: 'Hệ thống tự điền từ căn hộ đã chọn',
            locked: true,
            lockedHint: 'Hệ thống tự điền từ căn hộ đang chọn',
          ),
          const SizedBox(height: 16),
          _buildEditableField(
            label: 'Tòa nhà',
            controller: _buildingNameCtrl,
            icon: Icons.apartment_outlined,
            fieldKey: 'buildingName',
            validator: (v) =>
                v == null || v.isEmpty ? 'Vui lòng kiểm tra lại tòa nhà' : null,
            hint: 'Hệ thống tự điền theo căn hộ tương ứng',
            locked: true,
            lockedHint: 'Hệ thống tự điền, không thể chỉnh sửa',
          ),
          const SizedBox(height: 16),
          _buildEditableField(
            label: 'Biển số xe',
            controller: _licenseCtrl,
            icon: _vehicleType == 'Car'
                ? Icons.directions_car
                : Icons.two_wheeler,
            fieldKey: 'license',
            validator: (v) {
              if (v == null || v.isEmpty) {
                return 'Vui lòng nhập biển số xe';
              }
              final trimmed = v.trim().toUpperCase();
              if (trimmed.isEmpty) {
                return 'Biển số xe không được chỉ chứa khoảng trắng';
              }
              
              // Remove all spaces for validation
              final noSpaces = trimmed.replaceAll(RegExp(r'\s+'), '');
              if (noSpaces != trimmed) {
                return 'Biển số xe không được chứa dấu cách';
              }
              
              if (_vehicleType == 'Car') {
                // Format cho ô tô: 30A74374 (7-8 ký tự, 2 số đầu + 1 chữ cái + số)
                // Pattern: ^\d{2}[A-Z]\d{4,5}$
                if (!RegExp(r'^\d{2}[A-Z]\d{4,5}$').hasMatch(noSpaces)) {
                  return 'Biển số ô tô không hợp lệ. Ví dụ: 30A74374 (2 số + 1 chữ cái + 4-5 số)';
                }
                if (noSpaces.length < 7 || noSpaces.length > 8) {
                  return 'Biển số ô tô phải có 7-8 ký tự';
                }
              } else {
                // Format cho xe máy: 29BN05944 (8-9 ký tự, 2 số đầu + 2 chữ cái + số)
                // Pattern: ^\d{2}[A-Z]{2}\d{4,5}$
                if (!RegExp(r'^\d{2}[A-Z]{2}\d{4,5}$').hasMatch(noSpaces)) {
                  return 'Biển số xe máy không hợp lệ. Ví dụ: 29BN05944 (2 số + 2 chữ cái + 4-5 số)';
                }
                if (noSpaces.length < 8 || noSpaces.length > 9) {
                  return 'Biển số xe máy phải có 8-9 ký tự';
                }
              }
              
              return null;
            },
            hint: _vehicleType == 'Car'
                ? 'Ví dụ: 30A74374 (2 số + 1 chữ + 4-5 số)'
                : 'Ví dụ: 29BN05944 (2 số + 2 chữ + 4-5 số)',
          ),
          const SizedBox(height: 16),
          _buildEditableField(
            label: 'Hãng xe',
            controller: _brandCtrl,
            icon: Icons.factory_outlined,
            fieldKey: 'brand',
            validator: (v) {
              if (v == null || v.isEmpty) {
                return 'Vui lòng nhập hãng xe';
              }
              final trimmed = v.trim();
              if (trimmed.isEmpty) {
                return 'Hãng xe không được chỉ chứa khoảng trắng';
              }
              
              // Kiểm tra nhiều dấu cách liền kề (chỉ cho phép 1 dấu cách)
              if (RegExp(r'\s{2,}').hasMatch(v)) {
                return 'Hãng xe không được chứa nhiều dấu cách liền kề';
              }
              
              // Kiểm tra ký tự đặc biệt và số (chỉ cho phép chữ cái, dấu cách đơn, dấu gạch ngang)
              if (!RegExp(r'^[a-zA-ZÀ-ỹ\s\-]+$').hasMatch(v)) {
                return 'Hãng xe không được chứa ký tự đặc biệt hoặc số';
              }
              
              if (trimmed.length > 100) {
                return 'Hãng xe không được vượt quá 100 ký tự';
              }
              return null;
            },
            hint: 'Ví dụ: VinFast, Toyota, Honda...',
          ),
          const SizedBox(height: 16),
          _buildEditableField(
            label: 'Màu xe',
            controller: _colorCtrl,
            icon: Icons.palette_outlined,
            fieldKey: 'color',
            validator: (v) {
              if (v == null || v.isEmpty) {
                return 'Vui lòng nhập màu xe';
              }
              final trimmed = v.trim();
              if (trimmed.isEmpty) {
                return 'Màu xe không được chỉ chứa khoảng trắng';
              }
              
              // Kiểm tra nhiều dấu cách liền kề (chỉ cho phép 1 dấu cách)
              if (RegExp(r'\s{2,}').hasMatch(v)) {
                return 'Màu xe không được chứa nhiều dấu cách liền kề';
              }
              
              // Kiểm tra ký tự đặc biệt và số (chỉ cho phép chữ cái, dấu cách đơn, dấu gạch ngang)
              if (!RegExp(r'^[a-zA-ZÀ-ỹ\s\-]+$').hasMatch(v)) {
                return 'Màu xe không được chứa ký tự đặc biệt hoặc số';
              }
              
              if (trimmed.length > 50) {
                return 'Màu xe không được vượt quá 50 ký tự';
              }
              return null;
            },
            hint: 'Ví dụ: Đỏ, Xanh dương, Trắng...',
          ),
          const SizedBox(height: 16),
          _buildEditableField(
            label: 'Ghi chú thêm',
            controller: _noteCtrl,
            icon: Icons.note_alt_outlined,
            fieldKey: 'note',
            maxLines: 2,
            validator: (_) => null,
            hint: 'Thông tin bổ sung cho ban quản lý (nếu có)',
          ),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final reachedLimit = _uploadedImageUrls.length >= maxImages;

    return RegisterGlassPanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Ảnh xe của bạn',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${_uploadedImageUrls.length}/$maxImages',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: reachedLimit
                      ? AppColors.warning
                      : colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_uploadedImageUrls.isEmpty)
            Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: colorScheme.surface.withValues(alpha: isDark ? 0.22 : 0.58),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.08),
                ),
              ),
              child: Center(
                child: Text(
                  'Chưa chọn ảnh xe',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(
                _uploadedImageUrls.length,
                (index) => _buildImagePreview(index),
              ),
            ),
          if (_submitting && _uploadProgress != null) ...[
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Đang tải ảnh lên...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${(_uploadProgress! * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      colorScheme.primary,
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _confirmed ||
                          _submitting ||
                          _uploadedImageUrls.length >= maxImages
                      ? null
                      : _pickMultipleImages,
                  icon: _submitting && _uploadProgress == null
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        )
                      : const Icon(Icons.photo_library),
                  label: Text(
                    reachedLimit
                        ? 'Đã đủ ($maxImages ảnh)'
                        : _submitting && _uploadProgress == null
                            ? 'Đang xử lý...'
                            : 'Chọn ảnh',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _confirmed ||
                          _submitting ||
                          _uploadedImageUrls.length >= maxImages
                      ? null
                      : _takePhoto,
                  icon: _submitting && _uploadProgress == null
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        )
                      : const Icon(Icons.camera_alt),
                  label: Text(
                    reachedLimit
                        ? 'Đã đủ ($maxImages ảnh)'
                        : _submitting && _uploadProgress == null
                            ? 'Đang xử lý...'
                            : 'Chụp ảnh',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(int index) {
    final theme = Theme.of(context);
    final url = _makeFullImageUrl(_uploadedImageUrls[index]);
    final canRemove = _canRemoveImage(index);
    final isHighlight = _editingField == 'image_$index';

    return GestureDetector(
      onDoubleTap: () => _requestDeleteImage(index),
      child: RegisterGlassPanel(
        padding: EdgeInsets.zero,
        borderRadius: 22,
        child: SizedBox(
          height: 116,
          width: 116,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Opacity(
                  opacity: canRemove ? 1 : 0.7,
                  child: Image.network(
                    url,
                    height: 116,
                    width: 116,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              if (canRemove)
                Positioned(
                  top: 8,
                  right: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (_confirmed && !canRemove)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(22),
                        bottomRight: Radius.circular(22),
                      ),
                    ),
                    child: Text(
                      'Nhấn đúp để xóa',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (isHighlight)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
      final res =
          await client.post('/register-service/vnpay-url', data: payload);

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
      if (mounted) {
        String errorMessage = 'Không thể đăng ký thẻ xe. Vui lòng thử lại.';
        
        if (e is DioException) {
          final statusCode = e.response?.statusCode;
          final errorData = e.response?.data;
          
          // Handle specific error codes first (priority)
          if (statusCode == 409) {
            // Conflict - biển số đã tồn tại
            errorMessage = 'Đã có biển số được đăng ký trong hệ thống.';
          } else if (statusCode == 400) {
            // Bad request - validation error
            if (errorData is Map<String, dynamic>) {
              if (errorData['message'] != null) {
                errorMessage = errorData['message'].toString();
              } else if (errorData['error'] != null) {
                errorMessage = errorData['error'].toString();
              }
            } else if (errorData is String && errorData.isNotEmpty) {
              errorMessage = errorData;
            }
          } else if (statusCode == 500) {
            errorMessage = 'Lỗi server. Vui lòng thử lại sau.';
          } else if (e.type == DioExceptionType.connectionTimeout ||
                     e.type == DioExceptionType.receiveTimeout) {
            errorMessage = 'Kết nối timeout. Vui lòng kiểm tra kết nối mạng và thử lại.';
          } else if (e.type == DioExceptionType.connectionError) {
            errorMessage = 'Không thể kết nối tới server. Vui lòng kiểm tra kết nối mạng.';
          }
        } else if (e is Exception) {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
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
      _uploadedImageUrls.clear();
      _confirmed = false;
      _editingField = null;
      _hasEditedAfterConfirm = false;
      _hasUnsavedChanges = false;
    });
    // Không tự động apply unit context nữa
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
              Color(0xFF061426),
              Color(0xFF10273F),
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
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        key: const ValueKey('form'),
        extendBody: true,
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          centerTitle: false,
          title: Text(
            'Đăng ký thẻ xe',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.help_outline_rounded,
                color: colorScheme.primary,
              ),
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
                media.padding.bottom + 40,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFeeNoticeCard(),
                    const SizedBox(height: 20),
                    _buildVehicleFormCard(),
                    const SizedBox(height: 24),
                    _buildImageSection(),
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
                              _confirmed
                                  ? (_hasEditedAfterConfirm
                                      ? 'Xác nhận và thanh toán'
                                      : 'Đăng ký và thanh toán (${_formatVnd(_registrationFee.toInt())})')
                                  : 'Đăng ký và thanh toán (${_formatVnd(_registrationFee.toInt())})',
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

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String fieldKey,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? hint,
    bool locked = false,
    String? lockedHint,
  }) {
    final baseEditable = _isEditable(fieldKey);
    final effectiveEditable = !locked && baseEditable;
    final isEditing = effectiveEditable && _editingField == fieldKey;

    final displayHint = locked
        ? (lockedHint ?? 'Hệ thống tự động điền, không thể chỉnh sửa')
        : (_confirmed && !effectiveEditable
            ? 'Nhấn đúp để yêu cầu chỉnh sửa'
            : (hint ?? 'Nhập $label'));

    return RegisterGlassTextField(
      controller: controller,
      label: label,
      hint: displayHint,
      icon: icon,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: true,
      readOnly: !effectiveEditable,
      helperText:
          isEditing ? 'Đang chỉnh sửa... (Nhấn Done để hoàn tất)' : null,
      onDoubleTap: locked ? null : () => _requestEditField(fieldKey),
      onChanged: effectiveEditable
          ? (value) {
              if (isEditing) {
                _autoSave();
              }
            }
          : null,
      onEditingComplete: effectiveEditable
          ? () {
              if (isEditing && mounted) {
                FocusScope.of(context).unfocus();
                setState(() {
                  _editingField = null;
                });
                _autoSave();
              }
            }
          : null,
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


