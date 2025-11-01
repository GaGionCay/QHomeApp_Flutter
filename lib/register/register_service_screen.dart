import 'dart:convert';
import 'dart:developer';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import '../auth/api_client.dart';
import '../bills/vnpay_payment_screen.dart';
import 'register_guide_screen.dart';
import 'register_service_list_screen.dart';

class RegisterServiceScreen extends StatefulWidget {
  const RegisterServiceScreen({super.key});

  @override
  State<RegisterServiceScreen> createState() => _RegisterServiceScreenState();
}

class _RegisterServiceScreenState extends State<RegisterServiceScreen> with WidgetsBindingObserver {
  final ApiClient api = ApiClient();
  final _formKey = GlobalKey<FormState>();
  final _storageKey = 'register_service_draft';

  final TextEditingController _licenseCtrl = TextEditingController();
  final TextEditingController _brandCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _vehicleType = 'Car';
  bool _submitting = false;
  bool _showList = false;
  bool _confirmed = false; // Đã confirm để check thông tin
  String? _editingField; // Field đang được edit
  bool _hasEditedAfterConfirm = false; // Đã edit sau khi confirm
  final ImagePicker _picker = ImagePicker();
  List<String> _uploadedImageUrls = [];
  static const int maxImages = 6; // Giới hạn tối đa 6 ảnh
  
  // Auto-save tracking
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paymentSub?.cancel();
    _licenseCtrl.dispose();
    _brandCtrl.dispose();
    _colorCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Auto-save khi app bị minimize hoặc pause
      _autoSave();
    }
  }

  // ==================== AUTO-SAVE & LOAD ====================
  void _setupAutoSave() {
    // Auto-save khi user thay đổi text
    _licenseCtrl.addListener(_autoSave);
    _brandCtrl.addListener(_autoSave);
    _colorCtrl.addListener(_autoSave);
    _noteCtrl.addListener(_autoSave);
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
        content: const Text('Bạn có muốn thoát không? Dữ liệu đã nhập sẽ được lưu tự động.'),
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
      await _autoSave(); // Lưu trước khi thoát
    }

    return shouldExit ?? false;
  }

  // ==================== VNPAY INTEGRATION ====================
  void _listenForPaymentResult() {
    _paymentSub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri == null) return;
      
      if (uri.scheme == 'qhomeapp' && uri.host == 'vnpay-registration-result') {
        final registrationId = uri.queryParameters['registrationId'];
        final responseCode = uri.queryParameters['responseCode'];

        if (!mounted) return;

        if (responseCode == '00') {
          await _clearSavedData(); // Clear saved data sau khi thanh toán thành công
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Thanh toán thành công! Đăng ký xe đã được lưu.'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Chuyển sang danh sách
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const RegisterServiceListScreen()),
          );
        } else {
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

  // ==================== IMAGE UPLOAD ====================
  Future<void> _pickMultipleImages() async {
    // Kiểm tra số lượng ảnh hiện tại
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

    // Giới hạn số lượng ảnh có thể chọn
    final imagesToUpload = picked.take(remainingSlots).toList();
    if (picked.length > remainingSlots && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Chỉ có thể tải thêm $remainingSlots ảnh (tối đa $maxImages ảnh). Đã chọn $remainingSlots ảnh đầu tiên.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    await _uploadImages(imagesToUpload);
    await _autoSave();
  }

  Future<void> _takePhoto() async {
    // Kiểm tra số lượng ảnh hiện tại
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

    final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
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
          files.map((f) async => MultipartFile.fromFile(f.path, filename: f.name)),
        ),
      });
      final res = await api.dio.post('/register-service/upload-images', data: formData);
      final urls = (res.data['imageUrls'] as List?)?.map((e) => e.toString()).toList() ?? [];
      
      setState(() => _uploadedImageUrls.addAll(urls));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã tải lên ${urls.length} ảnh thành công! (${_uploadedImageUrls.length}/$maxImages)')),
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

  // ==================== LOGIC ====================
  String _makeFullImageUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    final base = ApiClient.BASE_URL.replaceFirst(RegExp(r'/api$'), '');
    return base + url;
  }

  Map<String, dynamic> _collectPayload() => {
        'serviceType': 'VEHICLE_REGISTRATION',
        'note': _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
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

  void _toggleList() => setState(() => _showList = !_showList);

  // ==================== VALIDATION + CONFIRMATION ====================
  Future<void> _handleRegisterPressed() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    // Kiểm tra số lượng ảnh
    if (_uploadedImageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Vui lòng tải lên ít nhất 1 ảnh xe'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Nếu chưa confirm lần nào → hiển thị thông báo check lại thông tin
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
              child: const Text('Đã kiểm tra', style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        setState(() {
          _confirmed = true;
          _editingField = null; // Reset editing field
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Vui lòng kiểm tra lại thông tin. Double-click vào field để chỉnh sửa.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      return;
    }

    // Đã confirm rồi:
    // - Nếu đã edit sau khi confirm → hiển thị lại thông báo check
    // - Nếu chưa edit → cho thanh toán luôn
    if (_hasEditedAfterConfirm) {
      // User đã edit → yêu cầu check lại
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
              child: const Text('Đã kiểm tra', style: TextStyle(color: Colors.teal)),
            ),
          ],
        ),
      );

      if (confirmAgain == true) {
        setState(() {
          _hasEditedAfterConfirm = false; // Reset flag
          _editingField = null; // Reset editing field
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Vui lòng kiểm tra lại thông tin. Double-click vào field để chỉnh sửa.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      return;
    }

    // Không có edit → cho thanh toán luôn
    await _saveAndPay();
  }

  Future<void> _requestEditField(String field) async {
    if (!_confirmed) return; // Chưa confirm thì không cần hỏi
    
    // Đang edit field khác thì hỏi trước
    if (_editingField != null && _editingField != field) {
      final wantSwitch = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Đang chỉnh sửa field khác'),
          content: const Text('Bạn đang chỉnh sửa một field khác. Bạn có muốn chuyển sang field này không?'),
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
        _hasEditedAfterConfirm = true; // Ghi nhớ đã edit
      });
    }
  }

  String _getFieldLabel(String fieldKey) {
    switch (fieldKey) {
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
    // Có thể xóa ảnh nếu:
    // - Chưa confirm, hoặc
    // - Đang edit ảnh đó (double click)
    return !_confirmed || _editingField == 'image_$index';
  }

  Future<void> _requestDeleteImage(int index) async {
    if (!_confirmed) {
      // Chưa confirm thì cho xóa luôn
      _removeImageAt(index);
      return;
    }

    // Đã confirm thì hỏi trước
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
      // Sau khi xóa, reset editingField sau 1 giây
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() => _editingField = null);
        }
      });
    }
  }

  bool _isEditable(String field) => !_confirmed || _editingField == field;

  // ==================== SAVE & PAYMENT ====================
  Future<void> _saveAndPay() async {
    setState(() => _submitting = true);
    int? registrationId; // Lưu để có thể hủy nếu user out
    
    try {
      final payload = _collectPayload();
      
      // Tạo temporary registration và VNPAY URL cùng lúc
      // Chỉ lưu vào DB khi thanh toán thành công
      final res = await api.dio.post('/register-service/vnpay-url', data: payload);
      
      registrationId = res.data['registrationId'] as int?;
      final paymentUrl = res.data['paymentUrl'] as String;
      
      if (mounted && registrationId != null) {
        // Mở VNPAY payment screen
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VnpayPaymentScreen(
              paymentUrl: paymentUrl,
              billId: 0, // Không dùng billId
              registrationId: registrationId, // Truyền registrationId để có thể hủy
            ),
          ),
        );
        
        // Kiểm tra kết quả thanh toán
        if (mounted) {
          if (result == null) {
            // User đã bấm back/out khỏi payment screen → update payment_status thành UNPAID
            // Registration vẫn được giữ lại trong DB để thanh toán sau
            await _cancelRegistration(registrationId);
            
            // Hiển thị thông báo thanh toán bị hủy
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Thanh toán đã bị hủy. Bạn có thể thanh toán lại từ danh sách thẻ xe.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          } else if (result is Map) {
            final responseCode = result['responseCode'] as String?;
            debugPrint('💰 [RegisterService] Payment result - ResponseCode: $responseCode, Result: $result');
            
            if (responseCode == '00') {
              // Thanh toán thành công
              debugPrint('✅ [RegisterService] Payment successful!');
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Đăng ký và thanh toán thành công!'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
              
              // Clear form và reset state
              _clearForm();
              _clearSavedData();
              
              // Sau khi thanh toán thành công, toggle sang list screen để hiển thị danh sách
              // Vẫn giữ mainshell (không pop, chỉ toggle)
              if (mounted) {
                setState(() {
                  _showList = true; // Hiển thị list screen
                });
              }
            } else {
              // Thanh toán thất bại
              debugPrint('❌ [RegisterService] Payment failed - ResponseCode: $responseCode');
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Thanh toán thất bại (Code: $responseCode)'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } else {
            debugPrint('⚠️ [RegisterService] Unexpected result type: ${result.runtimeType}');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
        
        // Nếu đã tạo temporary registration nhưng có lỗi → hủy
        if (registrationId != null) {
          await _cancelRegistration(registrationId);
        }
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  Future<void> _cancelRegistration(int registrationId) async {
    try {
      log('🗑️ [RegisterService] Hủy registration: $registrationId');
      await api.dio.delete('/register-service/$registrationId/cancel');
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
      _vehicleType = 'Car';
      _uploadedImageUrls.clear();
      _confirmed = false;
      _editingField = null;
      _hasEditedAfterConfirm = false;
      _hasUnsavedChanges = false;
    });
  }

  // ==================== UI ====================
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
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _showList
            ? Scaffold(
                key: const ValueKey('list'),
                appBar: AppBar(
                  title: const Text('Thẻ xe đã đăng ký'),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: _toggleList,
                  ),
                ),
                body: const RegisterServiceListScreen(),
              )
            : Scaffold(
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
                          MaterialPageRoute(builder: (_) => const RegisterGuideScreen()),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.list_alt_rounded),
                      tooltip: 'Danh sách thẻ xe',
                      onPressed: _toggleList,
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
                          // Info card về phí đăng ký
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
                                  value: _vehicleType,
                                  decoration: const InputDecoration(labelText: 'Loại phương tiện'),
                                  items: const [
                                    DropdownMenuItem(value: 'Car', child: Text('Ô tô')),
                                    DropdownMenuItem(value: 'Motorbike', child: Text('Xe máy')),
                                  ],
                                  onChanged: (_confirmed && _editingField != 'vehicleType')
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
                                _buildEditableField(
                                  label: 'Biển số xe',
                                  controller: _licenseCtrl,
                                  icon: _vehicleType == 'Car' 
                                      ? Icons.directions_car 
                                      : Icons.two_wheeler,
                                  fieldKey: 'license',
                                  validator: (v) => v!.isEmpty ? 'Vui lòng nhập biển số xe' : null,
                                ),
                                const SizedBox(height: 12),
                                _buildEditableField(
                                  label: 'Hãng xe',
                                  controller: _brandCtrl,
                                  icon: Icons.factory_outlined,
                                  fieldKey: 'brand',
                                  validator: (v) => v!.isEmpty ? 'Vui lòng nhập hãng xe' : null,
                                ),
                                const SizedBox(height: 12),
                                _buildEditableField(
                                  label: 'Màu xe',
                                  controller: _colorCtrl,
                                  icon: Icons.palette_outlined,
                                  fieldKey: 'color',
                                  validator: (v) => v!.isEmpty ? 'Vui lòng nhập màu xe' : null,
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
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${_uploadedImageUrls.length}/$maxImages',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _uploadedImageUrls.length >= maxImages ? Colors.orange : Colors.grey.shade700,
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
                                  children: List.generate(_uploadedImageUrls.length, (i) {
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
                                                _makeFullImageUrl(_uploadedImageUrls[i]),
                                                width: 110,
                                                height: 110,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                          // Chỉ hiển thị close button khi có thể xóa
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
                                                child: const Icon(Icons.close, size: 16, color: Colors.white),
                                              ),
                                            ),
                                          // Hiển thị hint khi đã confirm và không thể xóa
                                          if (_confirmed && !canRemove)
                                            Positioned(
                                              bottom: 0,
                                              left: 0,
                                              right: 0,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 2),
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
                                onPressed: _confirmed || _submitting || _uploadedImageUrls.length >= maxImages
                                    ? null
                                    : _pickMultipleImages,
                                icon: const Icon(Icons.photo_library),
                                label: Text(_uploadedImageUrls.length >= maxImages ? 'Đã đủ ($maxImages ảnh)' : 'Chọn ảnh'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade400,
                                  disabledBackgroundColor: Colors.grey.shade300,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _confirmed || _submitting || _uploadedImageUrls.length >= maxImages
                                    ? null
                                    : _takePhoto,
                                icon: const Icon(Icons.camera_alt),
                                label: Text(_uploadedImageUrls.length >= maxImages ? 'Đã đủ ($maxImages ảnh)' : 'Chụp ảnh'),
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
                              onPressed: _submitting
                                  ? null
                                  : _handleRegisterPressed,
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
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
  }) {
    final editable = _isEditable(fieldKey);
    final isEditing = _editingField == fieldKey;

    return GestureDetector(
      onDoubleTap: () => _requestEditField(fieldKey),
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
          opacity: editable ? 1.0 : 0.7,
          child: IgnorePointer(
            ignoring: !editable,
            child: TextFormField(
              controller: controller,
              readOnly: !editable,
              validator: validator,
              maxLines: maxLines,
              onTap: () {
                // Nếu đang edit field này, không làm gì
                if (isEditing) return;
                
                // Nếu đã confirm nhưng chưa được phép edit, hỏi user
                if (_confirmed && !editable) {
                  _requestEditField(fieldKey);
                }
              },
              onEditingComplete: () {
                // Khi user nhấn Done/Enter, finish editing
                if (isEditing && mounted) {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _editingField = null;
                  });
                  _autoSave();
                }
              },
              onFieldSubmitted: (_) {
                // Khi user submit field, finish editing
                if (isEditing && mounted) {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _editingField = null;
                  });
                  _autoSave();
                }
              },
              onChanged: (value) {
                // Ghi nhớ đã edit khi user thay đổi giá trị
                if (isEditing) {
                  _autoSave();
                }
              },
              decoration: InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon),
                filled: true,
                fillColor: editable ? Colors.white : Colors.grey.shade200,
                hintText: _confirmed && !editable ? 'Double-click để chỉnh sửa' : null,
                helperText: isEditing ? 'Đang chỉnh sửa... (Nhấn Done để hoàn tất)' : null,
                helperMaxLines: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
