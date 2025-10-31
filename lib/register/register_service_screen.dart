import 'dart:convert';
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
  bool _confirmed = false;
  String? _editingField;
  final ImagePicker _picker = ImagePicker();
  List<String> _uploadedImageUrls = [];
  
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
    final picked = await _picker.pickMultiImage(imageQuality: 75);
    if (picked.isEmpty) return;
    await _uploadImages(picked);
    await _autoSave();
  }

  Future<void> _takePhoto() async {
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
          SnackBar(content: Text('Đã tải lên ${urls.length} ảnh thành công!')),
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

  bool _isEditable(String field) => !_confirmed || _editingField == field;

  void _removeImageAt(int i) {
    setState(() => _uploadedImageUrls.removeAt(i));
    _autoSave();
  }

  void _toggleList() => setState(() => _showList = !_showList);

  // ==================== VALIDATION + CONFIRMATION ====================
  Future<void> _handleRegisterPressed() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xác nhận đăng ký'),
        content: const Text(
          'Bạn chắc chắn với thông tin đăng ký xe này chứ?\n\n'
          'Sau khi xác nhận, bạn sẽ cần thanh toán phí đăng ký 30.000 VNĐ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _confirmed = true);
      await _saveAndPay();
    }
  }

  Future<void> _requestEditField(String field) async {
    if (!_confirmed) return;
    final wantEdit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sửa thông tin'),
        content: const Text('Bạn có muốn chỉnh sửa thông tin này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );
    if (wantEdit == true) {
      setState(() => _editingField = field);
    }
  }

  // ==================== SAVE & PAYMENT ====================
  Future<void> _saveAndPay() async {
    setState(() => _submitting = true);
    try {
      final payload = _collectPayload();
      final res = await api.dio.post('/register-service', data: payload);
      
      final registrationId = res.data['id'] as int;
      
      if (mounted) {
        // Tạo VNPAY payment URL
        final paymentRes = await api.dio.post('/register-service/$registrationId/vnpay-url');
        final paymentUrl = paymentRes.data['paymentUrl'] as String;
        
        // Mở VNPAY payment screen
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VnpayPaymentScreen(
              paymentUrl: paymentUrl,
              billId: 0, // Không dùng billId, dùng registrationId
            ),
          ),
        );
        
        // Không cần clear form ở đây vì sẽ được xử lý trong callback
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
        setState(() => _confirmed = false);
      }
    } finally {
      setState(() => _submitting = false);
    }
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
                                  onChanged: _confirmed
                                      ? null
                                      : (v) {
                                          setState(() => _vehicleType = v ?? 'Car');
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
                          const Text(
                            'Ảnh xe của bạn',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                                    return Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.network(
                                            _makeFullImageUrl(_uploadedImageUrls[i]),
                                            width: 110,
                                            height: 110,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          child: GestureDetector(
                                            onTap: () => _removeImageAt(i),
                                            child: Container(
                                              decoration: const BoxDecoration(
                                                color: Colors.black54,
                                                shape: BoxShape.circle,
                                              ),
                                              padding: const EdgeInsets.all(4),
                                              child: const Icon(Icons.close, size: 16, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _confirmed
                                      ? null
                                      : _submitting
                                          ? null
                                          : _pickMultipleImages,
                                  icon: const Icon(Icons.photo_library),
                                  label: const Text('Chọn ảnh'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade400,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _confirmed
                                      ? null
                                      : _submitting
                                          ? null
                                          : _takePhoto,
                                  icon: const Icon(Icons.camera_alt),
                                  label: const Text('Chụp ảnh'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade600,
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
                                  : const Text(
                                      'Đăng ký và thanh toán (30.000 VNĐ)',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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

    return GestureDetector(
      onDoubleTap: () => _requestEditField(fieldKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          boxShadow: _editingField == fieldKey
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
              decoration: InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon),
                filled: true,
                fillColor: editable ? Colors.white : Colors.grey.shade200,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
