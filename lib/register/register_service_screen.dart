import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/api_client.dart';
import 'register_service_list_screen.dart';

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
  bool _showList = false;
  List<String> _uploadedImageUrls = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _licenseCtrl.dispose();
    _brandCtrl.dispose();
    _colorCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ====== IMAGE HANDLERS ======
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
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tải lên ${urls.length} ảnh thành công')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload lỗi: $e')));
    } finally {
      setState(() => _submitting = false);
    }
  }

  // ====== REGISTER LOGIC ======
  String _makeFullImageUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    final base = ApiClient.BASE_URL.replaceFirst(RegExp(r'/api$'), '');
    return base + url;
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
    FocusScope.of(context).unfocus();
    if (_licenseCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập biển số')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final payload = _collectPayload();
      await api.dio.post('/register-service', data: payload);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đăng ký thành công!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Đăng ký thất bại: $e')));
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

  void _toggleList() {
    setState(() => _showList = !_showList);
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width > 600;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
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
              appBar: AppBar(
                title: const Text('Đăng ký thẻ xe'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.list_alt),
                    tooltip: 'Danh sách thẻ xe đã đăng ký',
                    onPressed: _toggleList,
                  ),
                ],
              ),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? width * 0.15 : 16, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Thông tin phương tiện',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _vehicleType,
                        decoration: const InputDecoration(
                            labelText: 'Loại phương tiện'),
                        items: const [
                          DropdownMenuItem(value: 'Car', child: Text('Ô tô')),
                          DropdownMenuItem(
                              value: 'Motorbike', child: Text('Xe máy')),
                        ],
                        onChanged: (v) =>
                            setState(() => _vehicleType = v ?? 'Car'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _licenseCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Biển số xe'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _brandCtrl,
                        decoration: const InputDecoration(labelText: 'Hãng xe'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _colorCtrl,
                        decoration: const InputDecoration(labelText: 'Màu xe'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _noteCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'Ghi chú'),
                      ),
                      const SizedBox(height: 20),
                      const Text('Ảnh xe',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _uploadedImageUrls.isEmpty
                          ? Container(
                              height: 120,
                              width: double.infinity,
                              color: Colors.grey.shade200,
                              child: const Center(child: Text('Chưa chọn ảnh')),
                            )
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  List.generate(_uploadedImageUrls.length, (i) {
                                return Stack(
                                  children: [
                                    Image.network(
                                      _makeFullImageUrl(_uploadedImageUrls[i]),
                                      width: 110,
                                      height: 110,
                                      fit: BoxFit.cover,
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
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed:
                                  _submitting ? null : _pickMultipleImages,
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Chọn ảnh'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _submitting ? null : _takePhoto,
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Chụp ảnh'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _submitting ? null : _register,
                            child: _submitting
                                ? const CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2)
                                : const Text('Đăng ký thẻ xe',
                                    style: TextStyle(fontSize: 16)),
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
}
