import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Màn hình quay video với khả năng tự động dừng khi đạt 50MB hoặc 2 phút
class VideoRecorderScreen extends StatefulWidget {
  const VideoRecorderScreen({super.key});

  @override
  State<VideoRecorderScreen> createState() => _VideoRecorderScreenState();
}

class _VideoRecorderScreenState extends State<VideoRecorderScreen> {
  CameraController? _controller;
  bool _isRecording = false;
  bool _isInitialized = false;
  int _recordedDuration = 0; // Thời gian đã quay (giây)
  Timer? _durationTimer;
  Timer? _sizeCheckTimer;
  static const int _maxFileSizeMB = 50; // Giới hạn 50MB
  static const int _maxDurationSeconds = 120; // Tối đa 2 phút

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          _showError('Không tìm thấy camera');
        }
        return;
      }

      // Chọn camera với image stabilization nếu có
      // Lưu ý: Image stabilization thường được xử lý ở cấp độ hardware/OS
      // Camera package của Flutter không hỗ trợ trực tiếp, nhưng camera có EIS/OIS
      // sẽ tự động được sử dụng nếu thiết bị hỗ trợ
      final camera = cameras.first;
      
      _controller = CameraController(
        camera,
        ResolutionPreset.high, // Sử dụng high để có chất lượng tốt, sẽ compress sau
        enableAudio: true, // Bật ghi âm
      );

      await _controller!.initialize();
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        _showError('Lỗi khởi tạo camera: $e');
      }
    }
  }

  Future<void> _startRecording() async {
    if (!_isInitialized || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    try {
      await _controller!.startVideoRecording();
      
      setState(() {
        _isRecording = true;
        _recordedDuration = 0;
      });

      // Bắt đầu đếm thời gian
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordedDuration++;
          });
          
          // Tự động dừng nếu quá 2 phút
          if (_recordedDuration >= _maxDurationSeconds) {
            _stopRecording();
          }
        }
      });

      // Tự động dừng khi đạt 2 phút hoặc ước tính > 50MB
      // Ước tính: với high quality, trung bình ~25-30MB/phút
      _sizeCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (!_isRecording) {
          timer.cancel();
          return;
        }

        // Ước tính kích thước dựa trên thời gian quay
        // Với ResolutionPreset.high, trung bình ~25-30MB/phút
        final estimatedSizeMB = (_recordedDuration / 60) * 27.5; // Ước tính 27.5MB/phút

        // Tự động dừng khi đạt 2 phút
        if (_recordedDuration >= _maxDurationSeconds) {
          if (mounted) {
            _stopRecording();
          }
          timer.cancel();
          return;
        }

        // Tự động dừng nếu ước tính > 50MB
        if (estimatedSizeMB >= _maxFileSizeMB) {
          if (mounted) {
            _stopRecording();
            _showMessage(
              'Video đã đạt giới hạn ${_maxFileSizeMB}MB (ước tính). Đã tự động dừng quay.',
              color: Colors.orange,
            );
          }
          timer.cancel();
        }
      });
    } catch (e) {
      if (mounted) {
        _showError('Lỗi bắt đầu quay video: $e');
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _controller == null) return;

    try {
      _durationTimer?.cancel();
      _sizeCheckTimer?.cancel();

      final XFile videoFile = await _controller!.stopVideoRecording();
      
      setState(() {
        _isRecording = false;
      });

      // Kiểm tra kích thước file cuối cùng
      final file = File(videoFile.path);
      if (await file.exists()) {
        final fileSizeMB = await file.length() / (1024 * 1024);
        
        // Nếu > 50MB, vẫn lưu file và cho phép upload (chỉ thông báo cảnh báo)
        if (fileSizeMB > _maxFileSizeMB) {
          if (mounted) {
            _showMessage(
              'Video có dung lượng ${fileSizeMB.toStringAsFixed(1)}MB, vượt quá giới hạn ${_maxFileSizeMB}MB. '
              'File vẫn được lưu và có thể upload, nhưng quá trình upload có thể mất thời gian.',
              color: Colors.orange,
            );
          }
        }
        // Nếu <= 50MB, không cần thông báo (file đã được lưu và sẽ được thêm vào attachment)
      }

      if (mounted) {
        // Trả về XFile để tương thích với image_picker
        final xFile = XFile(videoFile.path);
        Navigator.pop(context, xFile);
      }
    } catch (e) {
      if (mounted) {
        _showError('Lỗi dừng quay video: $e');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showMessage(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _sizeCheckTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Quay video'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Quay video'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Camera preview
          Positioned.fill(
            child: CameraPreview(_controller!),
          ),
          
          // Overlay thông tin
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thời gian: ${_formatDuration(_recordedDuration)} / ${_formatDuration(_maxDurationSeconds)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Giới hạn: ${_maxFileSizeMB}MB hoặc ${_maxDurationSeconds}s (tự động dừng)',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Video sẽ được nén xuống 720p/480p sau khi quay',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Nút điều khiển
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_isRecording)
                  ElevatedButton.icon(
                    onPressed: _startRecording,
                    icon: const Icon(Icons.videocam),
                    label: const Text('Bắt đầu quay'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.stop),
                    label: const Text('Dừng quay'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

