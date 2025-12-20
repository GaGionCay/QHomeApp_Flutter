import 'dart:async';
import 'dart:typed_data';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import 'dart:io';

import '../auth/api_client.dart';
import '../profile/profile_service.dart';
import '../services/imagekit_service.dart';
import '../services/video_upload_service.dart';
import 'common_area_maintenance_request_service.dart';
import 'video_recorder_screen.dart';
import 'video_compression_service.dart';
import '../core/safe_state_mixin.dart';

class CommonAreaMaintenanceRequestScreen extends StatefulWidget {
  const CommonAreaMaintenanceRequestScreen({super.key});

  @override
  State<CommonAreaMaintenanceRequestScreen> createState() => _CommonAreaMaintenanceRequestScreenState();
}

class _AttachmentFile {
  _AttachmentFile({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    required this.isVideo,
    this.videoPath,
  });

  final List<int> bytes;
  final String mimeType;
  final String fileName;
  final bool isVideo;
  final String? videoPath;

  double get sizeInMB => bytes.length / (1024 * 1024);

  String get sizeFormatted {
    if (sizeInMB >= 1) {
      return '${sizeInMB.toStringAsFixed(1)} MB';
    } else {
      final sizeKB = bytes.length / 1024;
      return '${sizeKB.toStringAsFixed(1)} KB';
    }
  }
}

class _CommonAreaMaintenanceRequestScreenState 
    extends State<CommonAreaMaintenanceRequestScreen> 
    with SafeStateMixin<CommonAreaMaintenanceRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ApiClient _apiClient;
  late final CommonAreaMaintenanceRequestService _service;
  late final ProfileService _profileService;
  late final ImageKitService _imageKitService;
  late final VideoUploadService _videoUploadService;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedAreaType;
  final List<_AttachmentFile> _attachments = [];
  bool _loadingProfile = true;
  bool _submitting = false;

  static const _maxAttachments = 5;
  
  // Danh sách các loại khu vực chung
  static const _areaTypes = [
    'Hành lang',
    'Thang máy',
    'Đèn khu vực chung',
    'Bãi xe',
    'Cửa ra vào chung',
    'Cảnh quan',
    'Hệ thống nước chung',
    'Hệ thống điện chung',
    'Khác',
  ];

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _service = CommonAreaMaintenanceRequestService(_apiClient);
    _profileService = ProfileService(_apiClient.dio);
    _imageKitService = ImageKitService(_apiClient);
    _videoUploadService = VideoUploadService(_apiClient);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      if (!mounted) return;
      _contactNameController.text = profile['fullName']?.toString() ?? '';
      _contactPhoneController.text = profile['phoneNumber']?.toString() ?? '';
    } catch (_) {
      // allow manual overrides if needed
    } finally {
      if (mounted) {
        safeSetState(() => _loadingProfile = false);
      }
    }
  }

  Future<void> _pickMedia({required bool isVideo, required ImageSource source}) async {
    if (_attachments.length >= _maxAttachments) {
      _showMessage('Chỉ được chọn tối đa $_maxAttachments tệp.', color: Colors.orange);
      return;
    }

    // Sử dụng VideoRecorderScreen khi quay video từ camera
    if (isVideo && source == ImageSource.camera) {
      final videoFile = await Navigator.push<XFile>(
        context,
        MaterialPageRoute(
          builder: (_) => const VideoRecorderScreen(),
        ),
      );

      if (videoFile == null) return;

      // Hiển thị progress dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _VideoCompressionDialog(),
      );

      String finalVideoPath = videoFile.path;
      List<int> finalBytes;

      try {
        final compressedFile = await VideoCompressionService.instance.compressVideo(
          videoPath: videoFile.path,
          onProgress: (message) {
            debugPrint(message);
          },
        );

        if (compressedFile != null && await compressedFile.exists()) {
          finalBytes = await compressedFile.readAsBytes();
          finalVideoPath = compressedFile.path;
          
          try {
            final originalFile = File(videoFile.path);
            if (await originalFile.exists()) {
              await originalFile.delete();
            }
          } catch (e) {
            debugPrint('⚠️ Không thể xóa file gốc: $e');
          }
        } else {
          finalBytes = await videoFile.readAsBytes();
        }
      } catch (e) {
        debugPrint('⚠️ Lỗi nén video: $e');
        finalBytes = await videoFile.readAsBytes();
      } finally {
        if (mounted) {
          Navigator.pop(context);
        }
      }

      final mime = _detectMimeType(finalVideoPath, isVideo: true);
      
      if (!mounted) return;
      safeSetState(() {
        _attachments.add(
          _AttachmentFile(
            bytes: finalBytes,
            mimeType: mime,
            fileName: videoFile.name,
            isVideo: true,
            videoPath: finalVideoPath,
          ),
        );
      });
      return;
    }

    // Sử dụng image_picker cho ảnh và video từ gallery
    final picker = ImagePicker();
    final pickedFile = isVideo
        ? await picker.pickVideo(
            source: source,
            maxDuration: const Duration(minutes: 2),
          )
        : await picker.pickImage(source: source, imageQuality: 85);

    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();
    
    if (isVideo) {
      final fileSizeMB = bytes.length / (1024 * 1024);
      if (fileSizeMB > 50) {
        _showMessage(
          'Video có dung lượng ${fileSizeMB.toStringAsFixed(1)}MB, vượt quá giới hạn 50MB. '
          'Vui lòng chọn video khác hoặc quay video mới (tối đa 2 phút).',
          color: Colors.red,
        );
        return;
      } else if (fileSizeMB > 40) {
        _showMessage(
          'Video có dung lượng ${fileSizeMB.toStringAsFixed(1)}MB, gần giới hạn 50MB. '
          'Video sẽ được nén trước khi upload.',
          color: Colors.orange,
        );
      }
    }
    
    final mime = _detectMimeType(pickedFile.path, isVideo: isVideo);
    safeSetState(() {
      _attachments.add(
        _AttachmentFile(
          bytes: bytes,
          mimeType: mime,
          fileName: pickedFile.name,
          isVideo: isVideo,
          videoPath: isVideo ? pickedFile.path : null,
        ),
      );
    });
  }

  String _detectMimeType(String path, {required bool isVideo}) {
    final ext = path.split('.').last.toLowerCase();
    if (isVideo) {
      switch (ext) {
        case 'mp4':
        case 'm4v':
          return 'video/mp4';
        case 'mov':
          return 'video/quicktime';
        case 'avi':
          return 'video/x-msvideo';
        default:
          return 'video/mp4';
      }
    }
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  void _removeAttachment(int index) {
    safeSetState(() {
      _attachments.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedAreaType == null) {
      _showMessage('Vui lòng chọn loại khu vực chung.', color: Colors.red);
      return;
    }

    if (_submitting) return;
    
    safeSetState(() => _submitting = true);
    try {
      // Upload attachments
      final List<String> attachmentUrls = [];
      for (int i = 0; i < _attachments.length; i++) {
        final attachment = _attachments[i];
        try {
          File? tempFile;
          
          if (attachment.isVideo) {
            if (attachment.videoPath != null && File(attachment.videoPath!).existsSync()) {
              tempFile = File(attachment.videoPath!);
            } else {
              final tempDir = Directory.systemTemp;
              tempFile = File('${tempDir.path}/video_${DateTime.now().millisecondsSinceEpoch}_$i.mp4');
              await tempFile.writeAsBytes(attachment.bytes);
            }
            
            // Upload video lên backend
            try {
              final userId = await _apiClient.storage.readUserId();
              if (userId == null) {
                throw Exception('Không tìm thấy thông tin người dùng. Vui lòng đăng nhập lại.');
              }
              
              String? resolution;
              int? durationSeconds;
              int? width;
              int? height;
              
              try {
                final mediaInfo = await VideoCompress.getMediaInfo(tempFile.path);
                if (mediaInfo != null) {
                  if (mediaInfo.width != null && mediaInfo.height != null) {
                    width = mediaInfo.width;
                    height = mediaInfo.height;
                    if (height! <= 360) {
                      resolution = '360p';
                    } else if (height! <= 480) {
                      resolution = '480p';
                    } else if (height! <= 720) {
                      resolution = '720p';
                    } else {
                      resolution = '1080p';
                    }
                  }
                  if (mediaInfo.duration != null) {
                    durationSeconds = (mediaInfo.duration! / 1000).round();
                  }
                }
              } catch (e) {
                // Metadata extraction failed
              }
              
              final videoData = await _videoUploadService.uploadVideo(
                file: tempFile,
                category: 'common_area_maintenance',
                ownerId: null,
                uploadedBy: userId,
                resolution: resolution,
                durationSeconds: durationSeconds,
                width: width,
                height: height,
              );
              
              final videoUrl = videoData['fileUrl'] as String? ?? videoData['streamingUrl'] as String?;
              if (videoUrl != null) {
                attachmentUrls.add(videoUrl);
              }
            } catch (e) {
              if (!mounted) return;
              _showMessage('Lỗi khi upload video "${attachment.fileName}": ${e.toString()}', color: Colors.red);
              return;
            }
          } else {
            // Upload ảnh lên ImageKit
            if (attachment.videoPath != null && File(attachment.videoPath!).existsSync()) {
              tempFile = File(attachment.videoPath!);
            } else {
              final tempDir = Directory.systemTemp;
              final extension = attachment.fileName.contains('.') 
                  ? attachment.fileName.split('.').last 
                  : 'jpg';
              tempFile = File('${tempDir.path}/attachment_${DateTime.now().millisecondsSinceEpoch}_$i.$extension');
              await tempFile.writeAsBytes(attachment.bytes);
            }
            
            final imageUrl = await _imageKitService.uploadImage(
              file: tempFile,
              folder: 'common-area-maintenance/attachments',
            );
            attachmentUrls.add(imageUrl);
          }
          
          // Clean up temp file
          if (tempFile != null && 
              (attachment.videoPath == null || tempFile.path != attachment.videoPath)) {
            try {
              if (await tempFile.exists()) {
                await tempFile.delete();
              }
            } catch (e) {
              debugPrint('⚠️ Không thể xóa temp file: $e');
            }
          }
        } catch (e) {
          if (!mounted) return;
          _showMessage('Lỗi khi upload file "${attachment.fileName}": ${e.toString()}', color: Colors.red);
          return;
        }
      }

      await _service.createRequest(
        areaType: _selectedAreaType!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim(),
        contactName: _contactNameController.text.trim(),
        contactPhone: _contactPhoneController.text.trim(),
        attachments: attachmentUrls,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );
      
      if (!mounted) return;
      _showMessage('Yêu cầu bảo trì khu vực chung đã được gửi. Vui lòng chờ BQL liên hệ.', color: Colors.green);
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      String errorMessage;
      if (error is Exception) {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      } else {
        errorMessage = error.toString();
      }
      if (errorMessage.isEmpty) {
        errorMessage = 'Không thể gửi yêu cầu bảo trì khu vực chung. Vui lòng thử lại.';
      }
      _showMessage(errorMessage, color: Colors.red);
    } finally {
      if (mounted) {
        safeSetState(() => _submitting = false);
      }
    }
  }

  void _showMessage(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yêu cầu bảo trì khu vực chung'),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAreaTypeSection(theme),
                    _buildIssueDetailsSection(),
                    _buildLocationSection(),
                    _buildContactSection(),
                    _buildAttachmentsSection(theme),
                    _buildNoteSection(),
                  ],
                ),
              ),
            ),
          ),
          if (_loadingProfile)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.08),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: FilledButton.icon(
          onPressed: (_submitting || _loadingProfile) ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.build_outlined),
          label: const Text('Gửi yêu cầu bảo trì'),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.surface.withValues(alpha: 
      theme.brightness == Brightness.dark ? 0.75 : 0.98,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.4 : 0.08),
            offset: const Offset(0, 14),
            blurRadius: 32,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildAreaTypeSection(ThemeData theme) {
    return _buildSection(
      title: 'Loại khu vực chung',
      subtitle: 'Chọn loại khu vực cần bảo trì',
      child: DropdownButtonFormField<String>(
        value: _selectedAreaType,
        decoration: const InputDecoration(
          labelText: 'Loại khu vực',
          border: OutlineInputBorder(),
          hintText: 'Chọn loại khu vực',
        ),
        items: _areaTypes.map((type) {
          return DropdownMenuItem(
            value: type,
            child: Text(type),
          );
        }).toList(),
        onChanged: (value) {
          safeSetState(() {
            _selectedAreaType = value;
          });
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Vui lòng chọn loại khu vực chung';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildIssueDetailsSection() {
    return _buildSection(
      title: 'Chi tiết sự cố',
      subtitle: 'Mô tả rõ ràng về vấn đề cần bảo trì',
      child: Column(
        children: [
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Tiêu đề',
              hintText: 'Ví dụ: Đèn hành lang tầng 5 bị hỏng',
              border: OutlineInputBorder(),
            ),
            maxLength: 200,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập tiêu đề';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Mô tả chi tiết',
              hintText: 'Mô tả rõ ràng về sự cố, vị trí cụ thể...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 5,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập mô tả chi tiết';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    return _buildSection(
      title: 'Vị trí cụ thể',
      subtitle: 'Mô tả vị trí chính xác của khu vực cần bảo trì',
      child: TextFormField(
        controller: _locationController,
        decoration: const InputDecoration(
          labelText: 'Vị trí',
          hintText: 'Ví dụ: Tầng 5, hành lang A, gần thang máy số 2',
          border: OutlineInputBorder(),
        ),
        maxLines: 2,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Vui lòng nhập vị trí cụ thể';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildContactSection() {
    return _buildSection(
      title: 'Thông tin liên hệ',
      subtitle: 'Hệ thống tự động điền theo hồ sơ, bạn có thể chỉnh sửa nếu cần',
      child: Column(
        children: [
          TextFormField(
            controller: _contactNameController,
            decoration: const InputDecoration(
              labelText: 'Người liên hệ',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Không tìm thấy tên người liên hệ';
              }
              final trimmed = value.trim();
              if (!RegExp(r'^[\p{L}\s]+$', unicode: true).hasMatch(trimmed)) {
                return 'Họ và tên không được chứa ký tự đặc biệt hoặc số';
              }
              if (RegExp(r'\s{2,}').hasMatch(trimmed)) {
                return 'Họ và tên không được có quá nhiều khoảng cách';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _contactPhoneController,
            decoration: const InputDecoration(
              labelText: 'Số điện thoại',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Không tìm thấy số điện thoại';
              }
              final phoneDigits = value.trim().replaceAll(RegExp(r'[^0-9]'), '');
              if (phoneDigits.length != 10) {
                return 'Số điện thoại phải có đúng 10 chữ số';
              }
              if (RegExp(r'[^0-9]').hasMatch(value.trim())) {
                return 'Số điện thoại không được chứa ký tự đặc biệt và khoảng cách';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(ThemeData theme) {
    return _buildSection(
      title: 'Hình ảnh / Video minh họa',
      subtitle: 'Tùy chọn – tối đa $_maxAttachments tệp (ảnh hoặc video). Video: tối đa 2 phút hoặc 50MB.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildAttachmentAction(
                icon: Icons.photo_camera_outlined,
                label: 'Chụp ảnh',
                onTap: () => _pickMedia(isVideo: false, source: ImageSource.camera),
              ),
              _buildAttachmentAction(
                icon: Icons.photo_library_outlined,
                label: 'Chọn ảnh',
                onTap: () => _pickMedia(isVideo: false, source: ImageSource.gallery),
              ),
              _buildAttachmentAction(
                icon: Icons.videocam_outlined,
                label: 'Quay video',
                onTap: () => _pickMedia(isVideo: true, source: ImageSource.camera),
              ),
              _buildAttachmentAction(
                icon: Icons.video_library_outlined,
                label: 'Chọn video',
                onTap: () => _pickMedia(isVideo: true, source: ImageSource.gallery),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_attachments.isEmpty)
            Text(
              'Chưa có tệp đính kèm',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final screenWidth = constraints.maxWidth;
                final spacing = 12.0;
                const itemHeight = 180.0;
                
                int crossAxisCount;
                if (screenWidth < 400) {
                  crossAxisCount = 2;
                } else if (screenWidth < 600) {
                  crossAxisCount = 3;
                } else {
                  crossAxisCount = 4;
                }
                
                final itemSize = (screenWidth - (spacing * (crossAxisCount + 1))) / crossAxisCount;
                
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    childAspectRatio: itemSize / itemHeight,
                  ),
                  itemCount: _attachments.length,
                  itemBuilder: (context, index) {
                    return _buildAttachmentPreview(index, theme, itemSize);
                  },
                );
              },
            ),
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Đã chọn ${_attachments.length}/$_maxAttachments tệp',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttachmentAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildAttachmentPreview(int index, ThemeData theme, double size) {
    final attachment = _attachments[index];
    return Stack(
      children: [
        GestureDetector(
          onTap: () => _showFullscreenAttachment(index),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: attachment.isVideo
                ? _VideoPreviewWidget(
                    videoPath: attachment.videoPath,
                    containerWidth: size,
                    containerHeight: size,
                    sizeFormatted: attachment.sizeFormatted,
                    theme: theme,
                  )
                : _ImagePreviewWidget(
                    bytes: attachment.bytes,
                    containerWidth: size,
                    containerHeight: size,
                  ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: () => _removeAttachment(index),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(6),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ImagePreviewWidget({
    required List<int> bytes,
    required double containerWidth,
    required double containerHeight,
  }) {
    return SizedBox(
      width: containerWidth,
      height: containerHeight,
      child: Image.memory(
        Uint8List.fromList(bytes),
        fit: BoxFit.cover,
        width: containerWidth,
        height: containerHeight,
      ),
    );
  }

  void _showFullscreenAttachment(int index) {
    final attachment = _attachments[index];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullscreenAttachmentViewer(
          attachment: attachment,
          index: index,
          total: _attachments.length,
        ),
      ),
    );
  }

  Widget _buildNoteSection() {
    return _buildSection(
      title: 'Ghi chú thêm',
      subtitle: 'Tùy chọn – thông tin bổ sung nếu có',
      child: TextFormField(
        controller: _noteController,
        decoration: const InputDecoration(
          labelText: 'Ghi chú',
          hintText: 'Thông tin bổ sung về yêu cầu bảo trì...',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
        maxLines: 3,
      ),
    );
  }
}

// Video preview widget (reuse from repair_request_screen.dart structure)
class _VideoPreviewWidget extends StatefulWidget {
  final String? videoPath;
  final double containerWidth;
  final double containerHeight;
  final String sizeFormatted;
  final ThemeData theme;

  const _VideoPreviewWidget({
    required this.videoPath,
    required this.containerWidth,
    required this.containerHeight,
    required this.sizeFormatted,
    required this.theme,
  });

  @override
  State<_VideoPreviewWidget> createState() => _VideoPreviewWidgetState();
}

class _VideoPreviewWidgetState extends State<_VideoPreviewWidget> with SafeStateMixin<_VideoPreviewWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoPath != null) {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    try {
      final file = File(widget.videoPath!);
      if (!await file.exists()) {
        return;
      }

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();
      if (mounted) {
        safeSetState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi khởi tạo video player: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return Container(
        width: widget.containerWidth,
        height: widget.containerHeight,
        decoration: BoxDecoration(
          color: widget.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.videocam_outlined,
                color: widget.theme.colorScheme.primary,
                size: 32,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  widget.sizeFormatted,
                  style: widget.theme.textTheme.labelSmall?.copyWith(
                    color: widget.theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: widget.containerWidth,
      height: widget.containerHeight,
      decoration: const BoxDecoration(
        color: Colors.black,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.antiAlias,
        children: [
          Center(
            child: SizedBox(
              width: widget.containerWidth,
              height: widget.containerHeight,
              child: FittedBox(
                fit: BoxFit.contain,
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(12),
              child: const Icon(
                Icons.play_circle_filled,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.sizeFormatted,
                style: widget.theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 9,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Fullscreen attachment viewer (simplified version)
class _FullscreenAttachmentViewer extends StatelessWidget {
  final _AttachmentFile attachment;
  final int index;
  final int total;

  const _FullscreenAttachmentViewer({
    required this.attachment,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          attachment.isVideo ? 'Video' : 'Ảnh',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${index + 1}/$total',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: attachment.isVideo
            ? const Text(
                'Video preview - tap to play',
                style: TextStyle(color: Colors.white),
              )
            : InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.memory(
                  Uint8List.fromList(attachment.bytes),
                  fit: BoxFit.contain,
                ),
              ),
      ),
    );
  }
}

// Video compression dialog
class _VideoCompressionDialog extends StatelessWidget {
  const _VideoCompressionDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Đang nén video...'),
          SizedBox(height: 8),
          Text(
            'Vui lòng đợi trong giây lát',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
