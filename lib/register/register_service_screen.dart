import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/api_client.dart';
import 'register_guide_screen.dart';
import 'register_service_list_screen.dart';

class RegisterServiceScreen extends StatefulWidget {
  const RegisterServiceScreen({super.key});

  @override
  State<RegisterServiceScreen> createState() => _RegisterServiceScreenState();
}

class _RegisterServiceScreenState extends State<RegisterServiceScreen> {
  final ApiClient api = ApiClient();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _licenseCtrl = TextEditingController();
  final TextEditingController _brandCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _vehicleType = 'Car';
  bool _submitting = false;
  bool _showList = false;
  bool _confirmed = false; // chuyển nút sau khi xác nhận
  String? _editingField; // field đang được chỉnh sửa
  final ImagePicker _picker = ImagePicker();
  List<String> _uploadedImageUrls = [];

  @override
  void dispose() {
    _licenseCtrl.dispose();
    _brandCtrl.dispose();
    _colorCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ==================== IMAGE UPLOAD ====================
  Future<void> _pickMultipleImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 75);
    if (picked.isEmpty) return;
    await _uploadImages(picked);
  }

  Future<void> _takePhoto() async {
    final photo =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (photo != null) await _uploadImages([photo]);
  }

  Future<void> _uploadImages(List<XFile> files) async {
    setState(() => _submitting = true);
    try {
      final formData = FormData.fromMap({
        'files': await Future.wait(
          files.map(
            (f) async => MultipartFile.fromFile(f.path, filename: f.name),
          ),
        ),
      });
      final res =
          await api.dio.post('/register-service/upload-images', data: formData);
      final urls =
          (res.data['imageUrls'] as List?)?.map((e) => e.toString()).toList() ??
              [];
      setState(() => _uploadedImageUrls.addAll(urls));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã tải lên ${urls.length} ảnh thành công!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload lỗi: $e')));
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

  bool _isEditable(String field) =>
      !_confirmed || _editingField == field; // kiểm tra field có bị khóa không

  void _removeImageAt(int i) {
    setState(() => _uploadedImageUrls.removeAt(i));
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
        content: const Text('Bạn chắc chắn với thông tin đăng ký xe này chứ?'),
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

    if (confirm == true) {
      setState(() => _confirmed = true);
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

  Future<void> _saveInformation() async {
    setState(() => _submitting = true);
    try {
      final payload = _collectPayload();
      await api.dio.post('/register-service', data: payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Lưu thông tin thành công!')),
        );

        // reset form
        _formKey.currentState?.reset();
        _licenseCtrl.clear();
        _brandCtrl.clear();
        _colorCtrl.clear();
        _noteCtrl.clear();
        _uploadedImageUrls.clear();
        _confirmed = false;
        _editingField = null;

        // chuyển sang danh sách
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RegisterServiceListScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lưu thất bại: $e')));
    } finally {
      setState(() => _submitting = false);
    }
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width > 600;
    final vehicleIcon =
        _vehicleType == 'Car' ? Icons.directions_car : Icons.two_wheeler;

    return AnimatedSwitcher(
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
                        MaterialPageRoute(
                            builder: (_) => const RegisterGuideScreen()),
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
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? width * 0.15 : 16,
                    vertical: 20,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                decoration: const InputDecoration(
                                    labelText: 'Loại phương tiện'),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'Car', child: Text('Ô tô')),
                                  DropdownMenuItem(
                                      value: 'Motorbike',
                                      child: Text('Xe máy')),
                                ],
                                onChanged: _confirmed
                                    ? null
                                    : (v) => setState(
                                        () => _vehicleType = v ?? 'Car'),
                              ),
                              const SizedBox(height: 12),

                              // FIELD MẪU (áp dụng cho các field khác)
                              _buildEditableField(
                                label: 'Biển số xe',
                                controller: _licenseCtrl,
                                icon: vehicleIcon,
                                fieldKey: 'license',
                                validator: (v) => v!.isEmpty
                                    ? 'Vui lòng nhập biển số xe'
                                    : null,
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
                        const Text('Ảnh xe của bạn',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),

                        _uploadedImageUrls.isEmpty
                            ? Container(
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                    child: Text('Chưa chọn ảnh xe')),
                              )
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: List.generate(
                                    _uploadedImageUrls.length, (i) {
                                  return Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          _makeFullImageUrl(
                                              _uploadedImageUrls[i]),
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
                                            child: const Icon(Icons.close,
                                                size: 16, color: Colors.white),
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

                        // === BUTTON ANIMATION ===
                        Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.3),
                                  end: Offset.zero,
                                ).animate(anim),
                                child: child,
                              ),
                            ),
                            child: SizedBox(
                              key: ValueKey(_confirmed ? 'save' : 'register'),
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _submitting
                                    ? null
                                    : _confirmed
                                        ? _saveInformation
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
                                        color: Colors.white, strokeWidth: 2)
                                    : Text(
                                        _confirmed
                                            ? 'Lưu thông tin'
                                            : 'Đăng ký thẻ xe',
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600),
                                      ),
                              ),
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

  // ==================== Helper Widget ====================
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
