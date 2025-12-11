import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../models/unit_info.dart';
import '../profile/profile_service.dart';
import '../services/imagekit_service.dart';
import 'maintenance_request_service.dart';
import 'video_recorder_screen.dart';
import 'video_compression_service.dart';
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import 'dart:io';

class RepairRequestScreen extends StatefulWidget {
  const RepairRequestScreen({super.key});

  @override
  State<RepairRequestScreen> createState() => _RepairRequestScreenState();
}

class _AttachmentFile {
  _AttachmentFile({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    required this.isVideo,
    this.videoPath, // Đường dẫn file video để preview (chỉ cho video)
  });

  final List<int> bytes;
  final String mimeType;
  final String fileName;
  final bool isVideo;
  final String? videoPath; // Đường dẫn file video để preview

  /// Lấy kích thước file dưới dạng MB
  double get sizeInMB => bytes.length / (1024 * 1024);

  /// Lấy kích thước file dưới dạng chuỗi định dạng
  String get sizeFormatted {
    if (sizeInMB >= 1) {
      return '${sizeInMB.toStringAsFixed(1)} MB';
    } else {
      final sizeKB = bytes.length / 1024;
      return '${sizeKB.toStringAsFixed(1)} KB';
    }
  }
}

class _RepairRequestScreenState extends State<RepairRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ApiClient _apiClient;
  late final MaintenanceRequestService _service;
  late final ProfileService _profileService;
  late final ContractService _contractService;
  late final ImageKitService _imageKitService;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedCategory;
  DateTime? _preferredDate;
  TimeOfDay? _preferredTime;
  String? _preferredDateError;
  String? _preferredTimeError;

  final List<_AttachmentFile> _attachments = []; // Giữ nguyên thứ tự người dùng chọn
  bool _loadingProfile = true;
  bool _loadingUnit = true;
  bool _submitting = false;
  UnitInfo? _selectedUnit;

  static const _selectedUnitPrefsKey = 'selected_unit_id';
  static const _maxAttachments = 5;
  // Working hours: 8:00 AM - 8:00 PM (20:00)
  static const TimeOfDay _workingStart = TimeOfDay(hour: 8, minute: 0);
  static const TimeOfDay _workingEnd = TimeOfDay(hour: 20, minute: 0);

  final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy');

  static const _categories = [
    'Điện',
    'Nước',
    'Máy lạnh',
    'Nội thất',
    'Khác',
  ];

  bool get _isLoading => _loadingProfile || _loadingUnit;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _service = MaintenanceRequestService(_apiClient);
    _profileService = ProfileService(_apiClient.dio);
    _contractService = ContractService(_apiClient);
    _imageKitService = ImageKitService(_apiClient);
    _loadUnitContext();
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
        setState(() => _loadingProfile = false);
      }
    }
  }

  Future<void> _loadUnitContext() async {
    try {
      final units = await _contractService.getMyUnits();
      String? selectedUnitId;
      try {
        final prefs = await SharedPreferences.getInstance();
        selectedUnitId = prefs.getString(_selectedUnitPrefsKey);
      } catch (_) {
        selectedUnitId = null;
      }

      UnitInfo? unit;
      if (selectedUnitId != null) {
        for (final candidate in units) {
          if (candidate.id == selectedUnitId) {
            unit = candidate;
            break;
          }
        }
      }
      unit ??= units.isNotEmpty ? units.first : null;

      if (unit != null) {
        _locationController.text = unit.displayName;
      }

      if (mounted) {
        setState(() => _selectedUnit = unit);
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Không thể tải thông tin căn hộ. Vui lòng thử lại.', color: Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingUnit = false);
      }
    }
  }

  Future<void> _pickMedia({required bool isVideo, required ImageSource source}) async {
    if (_attachments.length >= _maxAttachments) {
      _showMessage('Chỉ được chọn tối đa $_maxAttachments tệp.', color: Colors.orange);
      return;
    }

    // Sử dụng VideoRecorderScreen tùy chỉnh khi quay video từ camera
    if (isVideo && source == ImageSource.camera) {
      final videoFile = await Navigator.push<XFile>(
        context,
        MaterialPageRoute(
          builder: (_) => const VideoRecorderScreen(),
        ),
      );

      if (videoFile == null) return;

      // Tự động nén video sau khi quay xong (trước khi upload)
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
        // Tự động nén video xuống 720p hoặc 480p
        final compressedFile = await VideoCompressionService.instance.compressVideo(
          videoPath: videoFile.path,
          onProgress: (message) {
            debugPrint(message);
          },
        );

        if (compressedFile != null && await compressedFile.exists()) {
          finalBytes = await compressedFile.readAsBytes();
          finalVideoPath = compressedFile.path;
          
          // Xóa file gốc sau khi nén thành công
          try {
            final originalFile = File(videoFile.path);
            if (await originalFile.exists()) {
              await originalFile.delete();
            }
          } catch (e) {
            debugPrint('⚠️ Không thể xóa file gốc: $e');
          }
        } else {
          // Nếu nén thất bại, dùng file gốc
          finalBytes = await videoFile.readAsBytes();
        }
      } catch (e) {
        debugPrint('⚠️ Lỗi nén video: $e');
        // Nếu có lỗi, dùng file gốc
        finalBytes = await videoFile.readAsBytes();
      } finally {
        if (mounted) {
          Navigator.pop(context); // Đóng progress dialog
        }
      }

      final mime = _detectMimeType(finalVideoPath, isVideo: true);
      
      if (!mounted) return;
      setState(() {
        // Thêm vào cuối theo thứ tự người dùng chọn (giữ nguyên thứ tự)
        _attachments.add(
          _AttachmentFile(
            bytes: finalBytes,
            mimeType: mime,
            fileName: videoFile.name,
            isVideo: true,
            videoPath: finalVideoPath, // Lưu path để preview
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
    
    // Kiểm tra kích thước file để cảnh báo nếu quá lớn (chỉ cho video từ gallery)
    if (isVideo) {
      final fileSizeMB = bytes.length / (1024 * 1024);
      if (fileSizeMB > 50) {
        // Nếu video từ gallery > 50MB, từ chối và yêu cầu chọn lại
        _showMessage(
          'Video có dung lượng ${fileSizeMB.toStringAsFixed(1)}MB, vượt quá giới hạn 50MB. '
          'Vui lòng chọn video khác hoặc quay video mới (tối đa 2 phút).',
          color: Colors.red,
        );
        return;
      } else if (fileSizeMB > 40) {
        // Cảnh báo nhẹ nếu video từ gallery > 40MB nhưng vẫn cho phép
        _showMessage(
          'Video có dung lượng ${fileSizeMB.toStringAsFixed(1)}MB, gần giới hạn 50MB. '
          'Video sẽ được nén trước khi upload.',
          color: Colors.orange,
        );
      }
      
      // Kiểm tra và xử lý rotation cho video từ gallery
      // Video sẽ được xử lý rotation khi nén trước khi upload
      try {
        final mediaInfo = await VideoCompress.getMediaInfo(pickedFile.path);
        if (mediaInfo?.orientation != null && mediaInfo!.orientation != 0) {
          debugPrint('📹 Video từ gallery có rotation: ${mediaInfo.orientation}°');
          // Rotation sẽ được xử lý khi nén video trước khi upload
        }
      } catch (e) {
        debugPrint('⚠️ Không thể kiểm tra rotation của video: $e');
      }
    }
    
    final mime = _detectMimeType(pickedFile.path, isVideo: isVideo);
    setState(() {
      final newAttachment = _AttachmentFile(
          bytes: bytes,
          mimeType: mime,
          fileName: pickedFile.name,
          isVideo: isVideo,
          videoPath: isVideo ? pickedFile.path : null, // Lưu path cho video để preview
      );
      
      // Thêm vào cuối theo thứ tự người dùng chọn (giữ nguyên thứ tự)
      _attachments.add(newAttachment);
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
    setState(() {
      _attachments.removeAt(index);
    });
  }

  // Widget để preview ảnh với kích thước cố định
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
        fit: BoxFit.cover, // Center crop để fit trong container
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

  void _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _preferredDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null) return;
    setState(() {
      _preferredDate = date;
      _preferredDateError = null;
      _preferredTimeError = _preferredTime == null
          ? 'Vui lòng chọn khung giờ xử lý'
          : _validatePreferredDateTime(_preferredDate, _preferredTime);
    });
  }

  void _pickTime() async {
    final initial = _preferredTime ?? const TimeOfDay(hour: 9, minute: 0);
    final time = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (time == null) return;
    setState(() {
      _preferredTime = time;
      _preferredTimeError = _validatePreferredDateTime(_preferredDate, time);
    });
    if (_preferredTimeError != null) {
      _showMessage(_preferredTimeError!, color: Colors.orange);
    }
  }

  String? _validatePreferredDateTime(DateTime? date, TimeOfDay? time) {
    if (date == null) return 'Vui lòng chọn ngày xử lý';
    if (time == null) return 'Vui lòng chọn khung giờ xử lý';

    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final now = DateTime.now();
    if (combined.isBefore(now)) {
      return 'Thời gian mong muốn không thể trước hiện tại';
    }
    if (!_isWithinWorkingHours(time)) {
      return 'Chỉ tiếp nhận từ ${_formatTimeOfDay(_workingStart)} đến ${_formatTimeOfDay(_workingEnd)}';
    }
    return null;
  }

  bool _isWithinWorkingHours(TimeOfDay time) {
    final minutes = time.hour * 60 + time.minute;
    return minutes >= _toMinutes(_workingStart) && minutes <= _toMinutes(_workingEnd);
  }

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final scheduleError = _validatePreferredDateTime(_preferredDate, _preferredTime);
    setState(() {
      _preferredDateError = _preferredDate == null ? 'Vui lòng chọn ngày xử lý' : null;
      _preferredTimeError = scheduleError;
    });
    if (scheduleError != null) return;

    if (_selectedUnit == null) {
      _showMessage('Không tìm thấy thông tin căn hộ. Vui lòng thử lại.', color: Colors.red);
      return;
    }

    if (_submitting) return;
    
    setState(() => _submitting = true);
    try {
      // Upload attachments to ImageKit
      final List<String> attachmentUrls = [];
      for (int i = 0; i < _attachments.length; i++) {
        final attachment = _attachments[i];
        try {
          File? tempFile;
          
          if (attachment.isVideo) {
            // Xử lý video: nén và fix rotation nếu cần
            if (attachment.videoPath != null && File(attachment.videoPath!).existsSync()) {
              // Video đã được nén từ camera hoặc cần nén từ gallery
              final videoFile = File(attachment.videoPath!);
              
              // Kiểm tra rotation metadata
              bool hasRotation = false;
              try {
                final mediaInfo = await VideoCompress.getMediaInfo(attachment.videoPath!);
                hasRotation = mediaInfo?.orientation != null && mediaInfo!.orientation != 0;
                if (hasRotation) {
                  debugPrint('📹 Video có rotation: ${mediaInfo.orientation}° - cần xử lý');
                }
              } catch (e) {
                debugPrint('⚠️ Không thể kiểm tra rotation: $e');
              }
              
              // Kiểm tra xem video có cần nén lại không
              final fileSizeMB = await videoFile.length() / (1024 * 1024);
              final needsCompression = fileSizeMB > 10 || hasRotation; // Nén nếu > 10MB hoặc có rotation
              
              if (needsCompression) {
                // Hiển thị progress cho video đang nén
                if (mounted) {
                  _showMessage('Đang xử lý video ${i + 1}/${_attachments.length}${hasRotation ? ' (sửa rotation)' : ''}...', color: Colors.blue);
                }
                
                // Nén video và xử lý rotation
                final compressedFile = await VideoCompressionService.instance.compressVideo(
                  videoPath: attachment.videoPath!,
                  onProgress: (message) {
                    debugPrint('Video compression: $message');
                  },
                );
                
                if (compressedFile != null && await compressedFile.exists()) {
                  tempFile = compressedFile;
                } else {
                  // Nếu nén thất bại, dùng file gốc
                  tempFile = videoFile;
                }
              } else {
                // Video nhỏ và không có rotation, dùng file gốc
                tempFile = videoFile;
              }
            } else {
              // Video không có path (từ bytes), tạo temp file và nén
              final tempDir = Directory.systemTemp;
              final tempInputFile = File('${tempDir.path}/video_input_${DateTime.now().millisecondsSinceEpoch}_$i.mp4');
              await tempInputFile.writeAsBytes(attachment.bytes);
              
              // Kiểm tra rotation metadata
              bool hasRotation = false;
              try {
                final mediaInfo = await VideoCompress.getMediaInfo(tempInputFile.path);
                hasRotation = mediaInfo?.orientation != null && mediaInfo!.orientation != 0;
                if (hasRotation) {
                  debugPrint('📹 Video từ bytes có rotation: ${mediaInfo.orientation}° - cần xử lý');
                }
              } catch (e) {
                debugPrint('⚠️ Không thể kiểm tra rotation: $e');
              }
              
              // Nén video và xử lý rotation (luôn nén để xử lý rotation nếu có)
              if (mounted) {
                _showMessage('Đang xử lý video ${i + 1}/${_attachments.length}${hasRotation ? ' (sửa rotation)' : ''}...', color: Colors.blue);
              }
              
              final compressedFile = await VideoCompressionService.instance.compressVideo(
                videoPath: tempInputFile.path,
                onProgress: (message) {
                  debugPrint('Video compression: $message');
                },
              );
              
              // Xóa temp input file
              try {
                if (await tempInputFile.exists()) {
                  await tempInputFile.delete();
                }
              } catch (e) {
                debugPrint('⚠️ Không thể xóa temp input file: $e');
              }
              
              if (compressedFile != null && await compressedFile.exists()) {
                tempFile = compressedFile;
              } else {
                // Nếu nén thất bại, tạo temp file từ bytes
                tempFile = File('${tempDir.path}/video_${DateTime.now().millisecondsSinceEpoch}_$i.mp4');
                await tempFile.writeAsBytes(attachment.bytes);
              }
            }
          } else {
            // Xử lý ảnh: không cần nén
            if (attachment.videoPath != null && File(attachment.videoPath!).existsSync()) {
              tempFile = File(attachment.videoPath!);
            } else {
              // Create temporary file for upload
              final tempDir = Directory.systemTemp;
              final extension = attachment.fileName.contains('.') 
                  ? attachment.fileName.split('.').last 
                  : 'jpg';
              tempFile = File('${tempDir.path}/attachment_${DateTime.now().millisecondsSinceEpoch}_$i.$extension');
              await tempFile.writeAsBytes(attachment.bytes);
            }
          }
          
          String url;
          if (attachment.isVideo) {
            // Upload video lên backend database thay vì ImageKit
            try {
              // Lấy userId từ storage
              final userId = await _apiClient.storage.readUserId();
              if (userId == null) {
                throw Exception('Không tìm thấy thông tin người dùng. Vui lòng đăng nhập lại.');
              }
              
              // Lấy video metadata nếu có thể
              String? resolution;
              int? durationSeconds;
              int? width;
              int? height;
              
              try {
                final mediaInfo = await VideoCompress.getMediaInfo(tempFile.path);
                if (mediaInfo != null) {
                  // Xác định resolution từ width/height
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
                  // Lấy duration nếu có
                  if (mediaInfo.duration != null) {
                    durationSeconds = (mediaInfo.duration! / 1000).round(); // Convert từ milliseconds
                  }
                }
              } catch (e) {
                debugPrint('⚠️ Không thể lấy video metadata: $e');
                // Vẫn tiếp tục upload nếu không lấy được metadata
              }
              
              // Upload video lên backend
              final videoData = await _imageKitService.uploadVideo(
                file: tempFile,
                category: 'repair_request',
                ownerId: null, // Sẽ được set sau khi tạo request
                uploadedBy: userId,
                resolution: resolution,
                durationSeconds: durationSeconds,
                width: width,
                height: height,
              );
              
              url = videoData['fileUrl'] as String;
              debugPrint('✅ Video uploaded to backend: $url');
            } catch (e) {
              if (!mounted) return;
              _showMessage('Lỗi khi upload video "${attachment.fileName}": ${e.toString()}', color: Colors.red);
              return;
            }
          } else {
            // Upload ảnh lên ImageKit như cũ
            url = await _imageKitService.uploadImage(
              file: tempFile,
              folder: 'repair-requests/attachments',
            );
          }
          attachmentUrls.add(url);
          
          // Clean up temp file if it was created for compression
          if (attachment.isVideo && tempFile != null) {
            try {
              // Chỉ xóa nếu là file nén (không phải file gốc từ videoPath)
              if (attachment.videoPath == null || tempFile.path != attachment.videoPath) {
                if (await tempFile.exists()) {
                  await tempFile.delete();
                }
              }
            } catch (e) {
              debugPrint('⚠️ Không thể xóa temp file: $e');
            }
          } else if (!attachment.isVideo && attachment.videoPath == null && tempFile != null) {
            // Xóa temp file cho ảnh nếu được tạo
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
        unitId: _selectedUnit!.id,
        category: _selectedCategory!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim(),
        contactName: _contactNameController.text.trim(),
        contactPhone: _contactPhoneController.text.trim(),
        preferredDateTime: DateTime(
          _preferredDate!.year,
          _preferredDate!.month,
          _preferredDate!.day,
          _preferredTime!.hour,
          _preferredTime!.minute,
        ),
        attachments: attachmentUrls,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );
      if (!mounted) return;
      _showMessage('Yêu cầu sửa chữa đã được gửi. Vui lòng chờ BQL liên hệ.', color: Colors.green);
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''), color: Colors.red);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
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
        title: const Text('Tạo yêu cầu sửa chữa'),
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
                    _buildUnitSection(theme),
                    _buildIssueDetailsSection(),
                    _buildScheduleSection(),
                    _buildContactSection(),
                    _buildAttachmentsSection(theme),
                    _buildNoteSection(),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
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
          onPressed: (_submitting || _isLoading) ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.handyman_outlined),
          label: const Text('Gửi yêu cầu sửa chữa'),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    String? subtitle,
    required Widget child,
    String? errorText,
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
          if (errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              errorText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnitSection(ThemeData theme) {
    final unit = _selectedUnit;
    return _buildSection(
      title: 'Căn hộ yêu cầu',
      subtitle: 'Tự đồng điền theo căn hộ bạn đang quản lý',
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.apartment_outlined, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: unit == null
                    ? const Text('Không tìm thấy căn hộ phù hợp')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(unit.displayName, style: theme.textTheme.titleMedium),
                          if ((unit.buildingName ?? '').isNotEmpty)
                            Text(
                              unit.buildingName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _locationController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Địa điểm sửa chữa',
              hintText: 'Hệ thống tự động điền theo căn hộ',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.lock_outline, size: 18),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Không xác định được địa điểm sửa chữa';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIssueDetailsSection() {
    return _buildSection(
      title: 'Thông tin sự cố',
      subtitle: 'Giúp ban quản lý hiểu vấn đề cụ thể',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'Loại yêu cầu',
              border: OutlineInputBorder(),
            ),
            initialValue: _selectedCategory,
            items: _categories
                .map((category) => DropdownMenuItem(value: category, child: Text(category)))
                .toList(),
            onChanged: (value) => setState(() => _selectedCategory = value),
            validator: (value) => value == null || value.isEmpty ? 'Vui lòng chọn loại yêu cầu' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Tiêu đề yêu cầu',
              border: OutlineInputBorder(),
            ),
            maxLength: 200,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập tiêu đề';
              }
              if (value.trim().length < 5) {
                return 'Tiêu đề cần tối thiểu 5 ký tự';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Mô tả chi tiết',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng mô tả chi tiết vấn đề';
              }
              if (value.trim().length < 10) {
                return 'Mô tả cần tối thiểu 10 ký tự';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection() {
    final dateText =
        _preferredDate == null ? 'Chưa chọn' : _dateFormatter.format(_preferredDate!);
    final timeText = _preferredTime == null ? 'Chưa chọn' : _preferredTime!.format(context);

    return _buildSection(
      title: 'Thời gian mong muốn',
      subtitle: 'Khung giờ hỗ trợ 08:00 - 20:00 hằng ngày',
      errorText: _preferredTimeError,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ngày xử lý', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(dateText, style: Theme.of(context).textTheme.titleMedium),
                    if (_preferredDateError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _preferredDateError!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _pickDate,
                child: const Text('Chọn ngày'),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Khung giờ xử lý', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(timeText, style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
              TextButton(
                onPressed: _pickTime,
                child: const Text('Chọn giờ'),
              ),
            ],
          ),
        ],
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
              // Validate: không có ký tự đặc biệt, không có quá nhiều khoảng cách
              final trimmed = value.trim();
              // Check for special characters or numbers (only allow letters and spaces)
              if (!RegExp(r'^[\p{L}\s]+$', unicode: true).hasMatch(trimmed)) {
                return 'Họ và tên không được chứa ký tự đặc biệt hoặc số';
              }
              // Check for multiple consecutive spaces
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
              // Remove all non-digit characters for validation
              final phoneDigits = value.trim().replaceAll(RegExp(r'[^0-9]'), '');
              // Validate: phải đúng 10 số
              if (phoneDigits.length != 10) {
                return 'Số điện thoại phải có đúng 10 chữ số';
              }
              // Check if original value contains special characters or spaces
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
      subtitle: 'Tùy chọn – tối đa $_maxAttachments tệp (ảnh hoặc video). Video: tối đa 2 phút hoặc 50MB, có ghi âm. Video sẽ được nén xuống 720p/480p sau khi quay.',
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
                label: 'Quay video (tối đa 2 phút)',
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
                // Tính toán số cột dựa trên width màn hình - responsive
                final screenWidth = constraints.maxWidth;
                final spacing = 12.0;
                const itemHeight = 180.0; // Height cố định
                
                // Responsive: 2-4 cột tùy màn hình
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
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: _buildAttachmentPreview(index, theme, itemSize),
                      key: ValueKey(_attachments[index].hashCode),
                    );
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
      label: Text(
        label,
        style: const TextStyle(fontSize: 13),
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview(int index, ThemeData theme, double itemWidth) {
    final attachment = _attachments[index];
    const double itemHeight = 180.0; // Height cố định
    
    return Stack(
      clipBehavior: Clip.antiAlias,
      children: [
        // Card container với shadow và border radius
        GestureDetector(
          onTap: () => _showFullscreenAttachment(index),
          child: Container(
            width: itemWidth,
            height: itemHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: attachment.isVideo
                  ? _VideoPreviewWidget(
                      videoPath: attachment.videoPath,
                      sizeFormatted: attachment.sizeFormatted,
                      theme: theme,
                      containerWidth: itemWidth,
                      containerHeight: itemHeight,
                    )
                  : _ImagePreviewWidget(
                      bytes: attachment.bytes,
                      containerWidth: itemWidth,
                      containerHeight: itemHeight,
                    ),
            ),
          ),
        ),
        // Close button
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _removeAttachment(index),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
        // Video indicator badge
        if (attachment.isVideo)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_circle_outline,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Video',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // File size warning badge
        if (attachment.sizeInMB > 50)
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'File lớn',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNoteSection() {
    return _buildSection(
      title: 'Ghi chú bổ sung',
      subtitle: 'Nhập hướng dẫn cho kỹ thuật viên (tùy chọn)',
      child: TextFormField(
        controller: _noteController,
        maxLines: 4,
        maxLength: 500,
        decoration: const InputDecoration(
          hintText: 'Ví dụ: Liên hệ trước 15 phút, có thú cưng trong nhà...',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Widget để preview video trong attachment list
class _VideoPreviewWidget extends StatefulWidget {
  final String? videoPath;
  final String sizeFormatted;
  final ThemeData theme;
  final double containerWidth;
  final double containerHeight;

  const _VideoPreviewWidget({
    required this.videoPath,
    required this.sizeFormatted,
    required this.theme,
    required this.containerWidth,
    required this.containerHeight,
  });

  @override
  State<_VideoPreviewWidget> createState() => _VideoPreviewWidgetState();
}

class _VideoPreviewWidgetState extends State<_VideoPreviewWidget> {
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
      // Chỉ hiển thị frame đầu tiên (thumbnail), không play video
      if (mounted) {
        setState(() {
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
      // Hiển thị placeholder khi chưa khởi tạo được
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

    // Tính toán aspect ratio của video để scale thumbnail phù hợp
    final videoAspectRatio = _controller!.value.aspectRatio;
    final containerAspectRatio = widget.containerWidth / widget.containerHeight;
    
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
          // Video thumbnail (frame đầu tiên) với auto-scale để fit trong container
          // Không play video, chỉ hiển thị thumbnail
          Center(
            child: SizedBox(
              width: widget.containerWidth,
              height: widget.containerHeight,
              child: FittedBox(
                fit: BoxFit.contain, // Contain để fit toàn bộ video trong container, giữ aspect ratio
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
          // Play icon overlay ở giữa để chỉ ra đây là video
          Center(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: const Icon(
                Icons.play_circle_filled,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          // Size label ở góc dưới
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

/// Dialog hiển thị tiến trình nén video
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

/// Fullscreen viewer cho ảnh và video
class _FullscreenAttachmentViewer extends StatefulWidget {
  final _AttachmentFile attachment;
  final int index;
  final int total;

  const _FullscreenAttachmentViewer({
    required this.attachment,
    required this.index,
    required this.total,
  });

  @override
  State<_FullscreenAttachmentViewer> createState() => _FullscreenAttachmentViewerState();
}

class _FullscreenAttachmentViewerState extends State<_FullscreenAttachmentViewer> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoPlaying = false;
  bool _showControls = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.isVideo && widget.attachment.videoPath != null) {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    try {
      final file = File(widget.attachment.videoPath!);
      if (!await file.exists()) {
        return;
      }

      _videoController = VideoPlayerController.file(file);
      await _videoController!.initialize();
      
      // Thêm listener để update UI khi video playing/paused
      _videoController!.addListener(_videoListener);
      
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
        // Tự động play video khi khởi tạo xong
        _videoController!.play();
        _isVideoPlaying = true;
        // Tự động ẩn controls sau 3 giây
        _startControlsTimer();
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi khởi tạo video player: $e');
    }
  }

  void _videoListener() {
    if (_videoController == null) return;
    
    final isPlaying = _videoController!.value.isPlaying;
    if (isPlaying != _isVideoPlaying && mounted) {
      setState(() {
        _isVideoPlaying = isPlaying;
      });
    }
    
    // Update UI khi video kết thúc
    if (_videoController!.value.position >= _videoController!.value.duration &&
        _videoController!.value.duration > Duration.zero) {
      if (mounted) {
        setState(() {
          _isVideoPlaying = false;
        });
      }
    }
  }

  void _togglePlayPause() {
    if (_videoController == null || !_isVideoInitialized) return;

    if (_isVideoPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
      _startControlsTimer(); // Reset timer khi play
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isVideoPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: widget.attachment.isVideo && isLandscape,
      appBar: AppBar(
        backgroundColor: widget.attachment.isVideo && isLandscape 
            ? Colors.transparent 
            : Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.attachment.isVideo ? 'Video' : 'Ảnh',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${widget.index + 1}/${widget.total}',
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
      body: widget.attachment.isVideo
          ? GestureDetector(
              onTap: _toggleControls,
              child: _buildVideoView(theme, isLandscape),
            )
          : Center(
              child: _buildImageView(theme),
            ),
    );
  }

  Widget _buildImageView(ThemeData theme) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Image.memory(
        Uint8List.fromList(widget.attachment.bytes),
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildVideoView(ThemeData theme, bool isLandscape) {
    if (!_isVideoInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Đang tải video...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video player - fullscreen với aspect ratio, hỗ trợ cả portrait và landscape
        Center(
          child: FittedBox(
            fit: BoxFit.contain, // Giữ aspect ratio, fit trong màn hình
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          ),
        ),
        // Controls overlay với animation mượt mà
        AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _showControls
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    // Tap to hide overlay
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _toggleControls,
                        child: Container(
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                    // Center play/pause button với animation
                    Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: _showControls ? 1.0 : 0.0),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        builder: (context, value, child) {
                          // Clamp opacity để đảm bảo trong phạm vi [0.0, 1.0]
                          final clampedOpacity = value.clamp(0.0, 1.0);
                          return Transform.scale(
                            scale: value.clamp(0.0, 1.0), // Clamp scale cũng để tránh lỗi
                            child: Opacity(
                              opacity: clampedOpacity,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _togglePlayPause,
                                  borderRadius: BorderRadius.circular(50),
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.7),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.5),
                                          blurRadius: 12,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      _isVideoPlaying ? Icons.pause : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 48,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        // Bottom controls bar với animation slide up/down
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          bottom: _showControls ? 0 : -120,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 20,
              bottom: MediaQuery.of(context).padding.bottom + 20,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.9),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress bar với scrubbing - cải thiện touch area
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  child: VideoProgressIndicator(
                    _videoController!,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.grey,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Controls row với spacing tốt hơn
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Play/Pause button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _togglePlayPause,
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            _isVideoPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Time display
                    Text(
                      _formatDuration(_videoController!.value.position),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text(
                      ' / ',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      _formatDuration(_videoController!.value.duration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

