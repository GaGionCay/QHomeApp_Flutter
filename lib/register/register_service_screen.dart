import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/api_client.dart';
import '../common/main_shell.dart';
import '../models/register_service_request.dart';

class RegisterServiceScreen extends StatefulWidget {
  const RegisterServiceScreen({super.key});

  @override
  State<RegisterServiceScreen> createState() => _RegisterServiceScreenState();
}

class _RegisterServiceScreenState extends State<RegisterServiceScreen> {
  final ApiClient api = ApiClient();
  final TextEditingController _licenseCtrl = TextEditingController();
  final TextEditingController _brandCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _vehicleType = 'Car';
  bool _submitting = false;
  bool _isRegistered = false;
  bool _isEditing = false;
  int? _registeredId;

  List<String> _uploadedImageUrls = []; // ảnh đã upload (server)
  List<XFile> _pickedFiles = []; // ảnh trong local

  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _licenseCtrl.dispose();
    _brandCtrl.dispose();
    _colorCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<bool> _confirmLeaveWithoutSaving() async {
    if (_isEditing ||
        (!_isRegistered &&
            (_licenseCtrl.text.isNotEmpty ||
                _pickedFiles.isNotEmpty ||
                _uploadedImageUrls.isNotEmpty))) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rời khỏi trang'),
          content: const Text(
              'Bạn có chắc muốn rời khỏi mà không lưu thay đổi không?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ở lại'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Rời khỏi'),
            ),
          ],
        ),
      );
      return confirm == true;
    }
    return true;
  }

  String _makeFullImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return '';
    if (imageUrl.startsWith('http')) return imageUrl;
    final base = ApiClient.BASE_URL.replaceFirst(RegExp(r'/api$'), '');
    return base + imageUrl;
  }

  Future<void> _pickMultipleImages() async {
    final List<XFile> picked = await _picker.pickMultiImage(imageQuality: 75);
    if (picked.isEmpty) return;
    await _uploadImages(picked); 
  }

  Future<void> _takePhoto() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (photo != null) {
      await _uploadImages([photo]);
    }
  }

  Future<void> _uploadImages(List<XFile> pickedFiles) async {
    setState(() => _submitting = true);
    try {
      final formData = FormData.fromMap({
        'files': await Future.wait(
          pickedFiles.map(
            (f) async => MultipartFile.fromFile(f.path, filename: f.name),
          ),
        ),
      });

      final res =
          await api.dio.post('/register-service/upload-images', data: formData);
      final urls =
          (res.data['imageUrls'] as List?)?.map((e) => e.toString()).toList() ??
              [];

      setState(() {
        _uploadedImageUrls.addAll(urls);
        _pickedFiles.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tải lên ${urls.length} ảnh thành công')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload lỗi: $e')),
      );
    } finally {
      setState(() => _submitting = false);
    }
  }

  void _removeImageAt(int index) {
    setState(() {
      if (index >= 0 && index < _uploadedImageUrls.length) {
        _uploadedImageUrls.removeAt(index);
      }
    });
  }

  Map<String, dynamic> _collectPayload() {
    return {
      'serviceType': 'VEHICLE_REGISTRATION',
      'note': _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
      'vehicleType': _vehicleType,
      'licensePlate': _licenseCtrl.text,
      'vehicleBrand': _brandCtrl.text,
      'vehicleColor': _colorCtrl.text,
      'imageUrls': _uploadedImageUrls,
    };
  }

  Future<void> _register() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_licenseCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Vui lòng nhập biển số')));
      return;
    }

    setState(() => _submitting = true);
    try {
      final payload = _collectPayload();
      final res = await api.dio.post('/register-service', data: payload);
      final data = Map<String, dynamic>.from(res.data ?? {});
      final created = RegisterServiceRequest.fromJson(data);

      setState(() {
        _isRegistered = true;
        _isEditing = false;
        _registeredId = created.id;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Đăng ký thành công, vui lòng kiểm tra lại thông tin')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đăng ký thất bại: $e')),
      );
    } finally {
      setState(() => _submitting = false);
    }
  }

  Future<void> _confirmAndSaveInfo() async {
    FocusScope.of(context).unfocus();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận lưu'),
        content:
            const Text('Bạn có chắc muốn lưu thông tin phương tiện này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      FocusScope.of(context).requestFocus(FocusNode());
    });

    if (confirm == true) {
      await _saveInfo();
    }
  }

  Future<void> _confirmAndUpdateInfo() async {
    FocusScope.of(context).unfocus();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận cập nhật'),
        content: const Text(
            'Bạn có chắc muốn cập nhật thông tin phương tiện này không?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cập nhật')),
        ],
      ),
    );

    if (confirm == true) {
      await _updateInfo();
    }
  }

  Future<void> _updateInfo() async {
    if (_registeredId == null) return;

    setState(() => _submitting = true);
    try {
      final payload = _collectPayload();
      await api.dio.put('/register-service/$_registeredId', data: payload);

      setState(() {
        _isEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật thông tin thành công')));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 2)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Cập nhật thất bại: $e')));
    } finally {
      setState(() => _submitting = false);
    }
  }

  Future<void> _saveInfo() async {
    if (_registeredId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa có đăng ký để lưu')));
      return;
    }

    setState(() => _submitting = true);
    try {
      final payload = _collectPayload();
      await api.dio.put('/register-service/$_registeredId', data: payload);

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lưu thông tin thành công')));
      _resetForm();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 2)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lưu thất bại: $e')));
    } finally {
      setState(() => _submitting = false);
    }
  }

  void _resetForm() {
    _licenseCtrl.clear();
    _brandCtrl.clear();
    _colorCtrl.clear();
    _noteCtrl.clear();
    _vehicleType = 'Car';
    _pickedFiles.clear();
    _uploadedImageUrls.clear();
    _isRegistered = false;
    _isEditing = false;
    _registeredId = null;
  }

  List<String> get allImages => _uploadedImageUrls;

  bool get _editable => !_isRegistered || _isEditing;

  void _toggleEdit() {
    if (!_isRegistered) return;

    setState(() {
      _isEditing = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chỉnh sửa thông tin phương tiện')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _confirmLeaveWithoutSaving,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Đăng ký thẻ xe'),
          actions: [
            if (_isRegistered)
              IconButton(
                icon: Icon(_isEditing ? Icons.check : Icons.edit),
                tooltip: _isEditing
                    ? 'Hoàn tất chỉnh sửa'
                    : 'Chỉnh sửa lại thông tin',
                onPressed: _submitting ? null : _toggleEdit,
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ Chỉ vùng nhập liệu bị khóa khi readonly
              IgnorePointer(
                ignoring: !_editable,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Thông tin phương tiện',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration:
                          const InputDecoration(labelText: 'Loại phương tiện'),
                      child: DropdownButton<String>(
                        value: _vehicleType,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'Car', child: Text('Ô tô')),
                          DropdownMenuItem(
                              value: 'Motorbike', child: Text('Xe máy')),
                        ],
                        onChanged: _editable
                            ? (v) => setState(() => _vehicleType = v ?? 'Car')
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _licenseCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Biển số')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _brandCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Hãng xe')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _colorCtrl,
                        decoration: const InputDecoration(labelText: 'Màu xe')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _noteCtrl,
                        decoration: const InputDecoration(labelText: 'Ghi chú'),
                        maxLines: 3),
                    const SizedBox(height: 16),
                    const Text('Ảnh xe',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    allImages.isEmpty
                        ? Container(
                            height: 100,
                            width: double.infinity,
                            color: Colors.grey.shade200,
                            child: const Center(child: Text('Chưa chọn ảnh')),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(allImages.length, (i) {
                              final isNetwork = i < _uploadedImageUrls.length;
                              return Stack(
                                children: [
                                  isNetwork
                                      ? Image.network(
                                          _makeFullImageUrl(allImages[i]),
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.cover,
                                        )
                                      : Image.file(
                                          File(allImages[i]),
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.cover,
                                        ),
                                  if (_editable)
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
                                          child: const Icon(Icons.close,
                                              size: 18, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            }),
                          ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _submitting || !_editable
                                ? null
                                : _pickMultipleImages,
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Chọn ảnh'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _submitting || !_editable ? null : _takePhoto,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Chụp ảnh'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ✅ Button luôn hoạt động (trừ khi đang submitting)
              ElevatedButton(
                onPressed: _submitting
                    ? null
                    : (_isRegistered && _isEditing
                        ? _confirmAndUpdateInfo
                        : (_isRegistered ? _confirmAndSaveInfo : _register)),
                child: _submitting
                    ? const CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)
                    : Text(_isRegistered ? 'Lưu thông tin' : 'Đăng ký'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
