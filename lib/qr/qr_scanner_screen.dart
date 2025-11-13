import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import 'qr_web_view_screen.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    autoStart: true,
  );

  bool _isProcessing = false;
  String? _lastScannedCode;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final Barcode barcode = barcodes.first;
    if (barcode.rawValue == null) return;

    final String code = barcode.rawValue!;
    
    // Prevent duplicate scans
    if (code == _lastScannedCode) return;
    _lastScannedCode = code;

    log('📱 QR Code scanned: $code');
    _isProcessing = true;

    // Stop scanner
    _controller.stop();

    // Validate and navigate
    _handleScannedCode(code);
  }

  Future<void> _handleScannedCode(String code) async {
    if (!mounted) return;

    final uri = Uri.tryParse(code);
    
    if (uri == null) {
      // Invalid QR code - cannot parse as URI
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mã QR không hợp lệ'),
          content: Text(
            'Mã QR này không chứa liên kết hợp lệ.\n\nMã quét được: $code',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _isProcessing = false;
                _lastScannedCode = null;
                _controller.start();
              },
              child: const Text('Quét lại'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      return;
    }
    
    // Check if it's a valid URL (http/https)
    final bool isValidUrl = uri.scheme == 'http' || uri.scheme == 'https';
    
    // Check if it's a deep link (app scheme)
    final bool isDeepLink = uri.scheme.isNotEmpty && 
        uri.scheme != 'http' && 
        uri.scheme != 'https' &&
        uri.scheme != 'file' &&
        uri.scheme != 'data';

    if (isValidUrl) {
      // Open in webview for HTTP/HTTPS URLs
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => QrWebViewScreen(url: code),
        ),
      );
    } else if (isDeepLink) {
      // Try to open deep link (app navigation)
      await _handleDeepLink(code, uri);
    } else {
      // Invalid QR code
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mã QR không hợp lệ'),
          content: Text(
            'Mã QR này không chứa liên kết hợp lệ.\n\nMã quét được: $code',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _isProcessing = false;
                _lastScannedCode = null;
                _controller.start();
              },
              child: const Text('Quét lại'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _handleDeepLink(String code, Uri uri) async {
    // Try to launch the deep link
    try {
      final canLaunch = await canLaunchUrl(uri);
      
      if (canLaunch) {
        // Launch the deep link (opens app or browser)
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        // Close QR scanner after launching
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        // Cannot launch - show error
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Không thể mở liên kết'),
            content: Text(
              'Không tìm thấy ứng dụng để mở liên kết này.\n\n'
              'Liên kết: $code',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _isProcessing = false;
                  _lastScannedCode = null;
                  _controller.start();
                },
                child: const Text('Quét lại'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      log('❌ Error launching deep link: $e');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lỗi'),
          content: Text(
            'Đã xảy ra lỗi khi mở liên kết.\n\n'
            'Lỗi: $e\n'
            'Liên kết: $code',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _isProcessing = false;
                _lastScannedCode = null;
                _controller.start();
              },
              child: const Text('Quét lại'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Quét mã QR',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: _hasError
          ? _buildErrorView(theme, media.size)
          : Stack(
              children: [
                // Camera view
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error, child) {
                    log('❌ Camera error: $error');
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _hasError = true;
                          _errorMessage = error.toString();
                        });
                      }
                    });
                    return const SizedBox.shrink();
                  },
                ),
                
                // Overlay with scanning frame
                _buildOverlay(media.size),
                
                // Instructions
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: _buildInstructions(theme),
                ),
              ],
            ),
    );
  }

  Widget _buildOverlay(Size size) {
    final scanArea = _getScanArea(size);
    const double cornerLength = 30;
    const double cornerWidth = 4;
    const Color cornerColor = AppColors.primaryAqua;

    return Stack(
      children: [
        // Dark overlay
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.5),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
                child: CustomPaint(
                  painter: _ScannerOverlayPainter(scanArea: scanArea),
                  size: size,
                ),
              ),
            ],
          ),
        ),
        
        // Scanning frame border
        Positioned(
          top: scanArea.top,
          left: scanArea.left,
          child: Container(
            width: scanArea.width,
            height: scanArea.height,
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.primaryAqua,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        
        // Corner indicators
        // Top-left
        Positioned(
          top: scanArea.top - cornerWidth / 2,
          left: scanArea.left - cornerWidth / 2,
          child: SizedBox(
            width: cornerLength + cornerWidth,
            height: cornerLength + cornerWidth,
            child: CustomPaint(
              painter: _CornerPainter(
                corner: _Corner.topLeft,
                length: cornerLength,
                width: cornerWidth,
                color: cornerColor,
              ),
            ),
          ),
        ),
        // Top-right
        Positioned(
          top: scanArea.top - cornerWidth / 2,
          right: size.width - scanArea.right - cornerWidth / 2,
          child: SizedBox(
            width: cornerLength + cornerWidth,
            height: cornerLength + cornerWidth,
            child: CustomPaint(
              painter: _CornerPainter(
                corner: _Corner.topRight,
                length: cornerLength,
                width: cornerWidth,
                color: cornerColor,
              ),
            ),
          ),
        ),
        // Bottom-left
        Positioned(
          bottom: size.height - scanArea.bottom - cornerWidth / 2,
          left: scanArea.left - cornerWidth / 2,
          child: SizedBox(
            width: cornerLength + cornerWidth,
            height: cornerLength + cornerWidth,
            child: CustomPaint(
              painter: _CornerPainter(
                corner: _Corner.bottomLeft,
                length: cornerLength,
                width: cornerWidth,
                color: cornerColor,
              ),
            ),
          ),
        ),
        // Bottom-right
        Positioned(
          bottom: size.height - scanArea.bottom - cornerWidth / 2,
          right: size.width - scanArea.right - cornerWidth / 2,
          child: SizedBox(
            width: cornerLength + cornerWidth,
            height: cornerLength + cornerWidth,
            child: CustomPaint(
              painter: _CornerPainter(
                corner: _Corner.bottomRight,
                length: cornerLength,
                width: cornerWidth,
                color: cornerColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Rect _getScanArea(Size size) {
    // Calculate scan area to be centered vertically and horizontally
    // Account for AppBar height, safe area, and instructions at bottom
    final media = MediaQuery.of(context);
    final appBarHeight = kToolbarHeight + media.padding.top;
    final bottomPadding = media.padding.bottom;
    final instructionsHeight = 120.0; // Height of instructions box
    final instructionsPadding = 24.0; // Padding below instructions
    
    // Available height for scanning area
    final availableHeight = size.height - 
        appBarHeight - 
        instructionsHeight - 
        instructionsPadding - 
        bottomPadding - 
        40; // Additional spacing
    
    // Calculate scan size (70% of screen width, but not larger than available height)
    final double scanSize = (size.width * 0.7)
        .clamp(200.0, availableHeight.clamp(200.0, double.infinity));
    
    // Center horizontally
    final double left = (size.width - scanSize) / 2;
    
    // Center vertically in available space
    // Position it in the middle of the space between AppBar and instructions
    final double top = appBarHeight + 
        ((size.height - appBarHeight - instructionsHeight - instructionsPadding - bottomPadding) - scanSize) / 2;
    
    return Rect.fromLTWH(left, top, scanSize, scanSize);
  }

  Widget _buildInstructions(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.qrcode_viewfinder,
            color: AppColors.primaryAqua,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            'Đưa mã QR vào khung quét',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Đảm bảo mã QR nằm trong khung và có đủ ánh sáng',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme, Size size) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.camera_fill,
              size: 64,
              color: AppColors.danger,
            ),
            const SizedBox(height: 16),
            Text(
              'Không thể truy cập camera',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Vui lòng cấp quyền truy cập camera để quét mã QR',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _errorMessage = null;
                });
                _controller.start();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAqua,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Đóng',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Corner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.corner,
    required this.length,
    required this.width,
    required this.color,
  });

  final _Corner corner;
  final double length;
  final double width;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (corner) {
      case _Corner.topLeft:
        canvas.drawLine(
          const Offset(0, 0),
          Offset(length, 0),
          paint,
        );
        canvas.drawLine(
          const Offset(0, 0),
          Offset(0, length),
          paint,
        );
        break;
      case _Corner.topRight:
        canvas.drawLine(
          Offset(size.width - length, 0),
          Offset(size.width, 0),
          paint,
        );
        canvas.drawLine(
          Offset(size.width, 0),
          Offset(size.width, length),
          paint,
        );
        break;
      case _Corner.bottomLeft:
        canvas.drawLine(
          Offset(0, size.height),
          Offset(length, size.height),
          paint,
        );
        canvas.drawLine(
          Offset(0, size.height - length),
          Offset(0, size.height),
          paint,
        );
        break;
      case _Corner.bottomRight:
        canvas.drawLine(
          Offset(size.width - length, size.height),
          Offset(size.width, size.height),
          paint,
        );
        canvas.drawLine(
          Offset(size.width, size.height - length),
          Offset(size.width, size.height),
          paint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter({required this.scanArea});

  final Rect scanArea;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..blendMode = BlendMode.clear;

    // Draw transparent rectangle for scan area
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanArea, const Radius.circular(20)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

