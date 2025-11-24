import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import 'bank_qr_parser.dart';

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
  String? _lastScannedQRString;
  bool _hasError = false;
  String? _errorMessage;
  bool _isScannerStarted = false;

  @override
  void initState() {
    super.initState();
    // Track that scanner will auto-start
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _isScannerStarted = true;
      }
    });
  }

  @override
  void dispose() {
    // Properly stop and dispose camera
    if (_isScannerStarted) {
      _controller.stop();
      _isScannerStarted = false;
    }
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
    if (_isScannerStarted) {
      _controller.stop();
      _isScannerStarted = false;
    }

    // Validate and navigate
    _handleScannedCode(code);
  }

  /// ============================================
  /// HÀM CHÍNH: Xử lý QR code đã quét
  /// ============================================
  /// 
  /// Luồng xử lý theo yêu cầu:
  /// 1. Nhận diện loại QR: URL, Bank QR, hoặc Unknown
  /// 2. Nếu là Bank QR → Kiểm tra app đã cài → Hiển thị dialog chọn ngân hàng
  /// 3. Nếu là URL → Hiển thị dialog chọn app để mở URL
  /// 4. Nếu là Unknown → Hiển thị dialog xử lý generic
  Future<void> _handleScannedCode(String code) async {
    if (!mounted) return;

    log('📱 Handling scanned QR code...');
    
    // Trim and clean the scanned code
    final cleanedCode = code.trim();
    _lastScannedQRString = cleanedCode;
    
    if (cleanedCode.isEmpty) {
      log('⚠️ Scanned code is empty after trimming');
      _showInvalidCodeDialog(code);
      return;
    }

    log('📝 Cleaned QR code length: ${cleanedCode.length}');
    log('📝 QR code preview: ${cleanedCode.length > 100 ? '${cleanedCode.substring(0, 100)}...' : cleanedCode}');

    try {
      // Bước 1: Nhận diện và phân loại QR code
      log('🔍 Step 1: Identifying QR code type...');
      final qrResult = BankQRParser.identifyAndParseQR(cleanedCode);
      
      log('✅ QR identified as: ${qrResult.type}');
      
      // Bước 2: Xử lý theo từng loại QR
      if (qrResult.isBankQr) {
        // QR là mã chuyển khoản ngân hàng
        log('💰 Processing Bank QR...');
        await _handleBankQR(qrResult.bankData!, qrCodeString: _lastScannedQRString);
      } else if (qrResult.isUrl) {
        // QR là URL
        log('🌐 Processing URL QR...');
        await _handleUrlQR(qrResult.url!);
      } else {
        // QR không xác định được loại
        log('❓ Processing Unknown QR...');
        await _handleUnknownQR(cleanedCode);
      }
    } catch (e, stackTrace) {
      log('❌ CRITICAL ERROR while processing QR code: $e');
      log('   Error type: ${e.runtimeType}');
      log('   Stack trace: $stackTrace');
      
      if (!mounted) return;
      
      // Show error dialog with details
      _showParsingErrorDialog(cleanedCode, e.toString(), stackTrace.toString());
      _resetScanner();
    }
  }

  /// Xử lý Bank QR: Kiểm tra app đã cài → Hiển thị dialog chọn ngân hàng
  Future<void> _handleBankQR(BankQRData bankData, {String? qrCodeString}) async {
    if (!mounted) return;
    
    log('💰 Handling Bank QR: BIN=${bankData.bin}, Account=${bankData.accountNumber}');
    
    // Hiển thị loading dialog trong khi kiểm tra app đã cài
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Đang kiểm tra ứng dụng ngân hàng...',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
    
    // Kiểm tra TẤT CẢ app payment/banking đã cài đặt (bao gồm cả MoMo, ZaloPay...)
    List<BankInfo> installedApps;
    try {
      log('🔍 Detecting installed payment/banking apps...');
      installedApps = await BankQRParser.detectInstalledPaymentApps();
      log('✅ Found ${installedApps.length} installed payment/banking apps');
    } catch (e, stackTrace) {
      log('❌ Error detecting installed apps: $e');
      log('   Stack trace: $stackTrace');
      // Fallback: Hiển thị tất cả (nếu có)
      installedApps = [];
    } finally {
      // Đóng loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
    
    // Lấy thông tin ngân hàng được phát hiện từ QR (nếu có)
    // ✅ Sử dụng async getBankInfo để lấy package name từ dynamic mapping (nếu có)
    BankInfo? detectedBank;
    if (bankData.bin != null) {
      try {
        detectedBank = await BankQRParser.getBankInfo(bankData.bin!);
      } catch (e) {
        log('⚠️ Error getting bank info: $e');
        // detectedBank remains null if async fails
      }
    }
    
    // Ưu tiên hiển thị ngân hàng được phát hiện ở đầu danh sách (nếu có và đã cài)
    if (detectedBank != null) {
      // Thêm ngân hàng được phát hiện vào danh sách nếu chưa có
      if (!installedApps.any((app) => 
        app.bin != null && detectedBank != null && 
        app.bin == detectedBank.bin && 
        app.packageName == detectedBank.packageName)) {
        installedApps.insert(0, detectedBank);
        log('✅ Added detected bank to list: ${detectedBank.name}');
      } else {
        // Di chuyển ngân hàng được phát hiện lên đầu
        installedApps.removeWhere((app) => 
          app.bin != null && detectedBank != null && 
          app.bin == detectedBank.bin && 
          app.packageName == detectedBank.packageName);
        installedApps.insert(0, detectedBank);
      }
    }
    
    // Nếu không có app nào được cài, thông báo cho user
    if (installedApps.isEmpty) {
      log('⚠️ No payment/banking apps installed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không tìm thấy app thanh toán/ngân hàng nào đã cài đặt'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
        _resetScanner();
      }
      return;
    }
    
    // Hiển thị Android system chooser để chọn app payment/banking
    await _showBankAppChooser(bankData, installedApps, qrCodeString: qrCodeString);
  }

  /// Xử lý URL QR: Quét browser apps → Hiển thị dialog chọn trình duyệt
  Future<void> _handleUrlQR(Uri url) async {
    if (!mounted) return;
    
    log('🌐 Handling URL QR: $url');
    
    // Hiển thị loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Đang tìm trình duyệt...',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
    
    // Kiểm tra TẤT CẢ app trình duyệt đã cài đặt
    List<BankInfo> installedBrowsers;
    try {
      log('🔍 Detecting installed browser apps...');
      installedBrowsers = await BankQRParser.detectInstalledBrowserApps();
      log('✅ Found ${installedBrowsers.length} installed browser apps');
    } catch (e, stackTrace) {
      log('❌ Error detecting installed browsers: $e');
      log('   Stack trace: $stackTrace');
      installedBrowsers = [];
    } finally {
      // Đóng loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
    
    // Nếu không có browser nào, fallback mở URL trực tiếp
    if (installedBrowsers.isEmpty) {
      log('⚠️ No browser apps installed, opening URL directly...');
      try {
        final canLaunch = await canLaunchUrl(url);
        if (canLaunch) {
          await launchUrl(url, mode: LaunchMode.platformDefault);
          log('✅ Successfully opened URL');
          if (mounted) {
            Navigator.of(context).pop(); // Đóng QR scanner
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Không thể mở URL này'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } catch (e) {
        log('❌ Error opening URL: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi khi mở URL: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      return;
    }
    
    // Hiển thị Android system chooser để chọn trình duyệt
    await _showBrowserChooser(url, installedBrowsers);
  }

  /// ============================================
  /// UI: Hiển thị Android system chooser để chọn trình duyệt
  /// ============================================
  Future<void> _showBrowserChooser(Uri url, List<BankInfo> availableBrowsers) async {
    if (!mounted) return;
    
    log('🌐 Showing Android chooser for URL: $url');
    log('   Available browsers: ${availableBrowsers.length}');
    
    try {
      // Lấy danh sách package names
      final packageNames = availableBrowsers.map((browser) => browser.packageName).toList();
      
      // Gọi platform channel để hiển thị Android chooser
      const channel = MethodChannel('com.qhome.resident/app_launcher');
      final shown = await channel.invokeMethod<bool>(
        'showAppChooser',
        {
          'url': url.toString(),
          'packageNames': packageNames,
          'title': 'Chọn trình duyệt để mở URL',
        },
      );
      
      if (shown == true) {
        log('✅ Successfully showed Android chooser');
        // Đóng QR scanner sau khi hiển thị chooser
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      } else {
        log('⚠️ Failed to show Android chooser, falling back to system chooser');
        // Fallback: Sử dụng system chooser
        try {
          final canLaunch = await canLaunchUrl(url);
          if (canLaunch) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
            if (mounted) {
              Navigator.of(context).pop();
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Không thể mở URL này'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        } catch (e) {
          log('❌ Error in fallback: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lỗi khi mở URL: $e'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } on PlatformException catch (e) {
      log('⚠️ Platform channel error: ${e.code} - ${e.message}');
      // Fallback: Sử dụng system chooser
      try {
        final canLaunch = await canLaunchUrl(url);
        if (canLaunch) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      } catch (e2) {
        log('❌ Error in fallback: $e2');
      }
    } catch (e, stackTrace) {
      log('❌ Error showing browser chooser: $e');
      log('   Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi hiển thị danh sách trình duyệt: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _resetScanner();
    }
  }

  /// Xử lý Unknown QR: Hiển thị dialog xử lý generic
  Future<void> _handleUnknownQR(String code) async {
    if (!mounted) return;
    
    log('❓ Handling Unknown QR');
    
    // Hiển thị dialog xử lý generic
    await _showAppChooserDialog(code);
  }

  void _showParsingErrorDialog(String code, String error, String stackTrace) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text('Lỗi parse QR code')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Đã xảy ra lỗi khi parse QR code. Chi tiết lỗi:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lỗi: $error',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.red,
                      ),
                    ),
                    if (stackTrace.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ExpansionTile(
                        title: const Text(
                          'Stack trace (chi tiết kỹ thuật)',
                          style: TextStyle(fontSize: 11),
                        ),
                        children: [
                          SelectableText(
                            stackTrace,
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Mã QR đã quét:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey,
                ),
                maxLines: 10,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: 'Error: $error\n\nQR Code: $code\n\nStack trace:\n$stackTrace',
              ));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã sao chép thông tin lỗi'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Sao chép lỗi'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  /// ============================================
  /// UI: Hiển thị Android system chooser để chọn app ngân hàng
  /// ============================================
  Future<void> _showBankAppChooser(BankQRData qrData, List<BankInfo> availableBanks, {String? qrCodeString}) async {
    if (!mounted) return;
    
    log('💰 Showing Android chooser for bank apps');
    log('   Available banks: ${availableBanks.length}');
    
    // Copy QR code to clipboard first
    final qrCode = qrCodeString ?? _lastScannedQRString;
    if (qrCode != null) {
      try {
        await Clipboard.setData(ClipboardData(text: qrCode));
        log('✅ Copied QR code to clipboard');
      } catch (e) {
        log('⚠️ Error copying QR to clipboard: $e');
      }
    }
    
    try {
      // Lấy danh sách package names
      final packageNames = availableBanks.map((bank) => bank.packageName).toList();
      
      // Gọi platform channel để hiển thị Android chooser
      const channel = MethodChannel('com.qhome.resident/app_launcher');
      final shown = await channel.invokeMethod<bool>(
        'showBankAppChooser',
        {
          'packageNames': packageNames,
          'qrCode': qrCode,
          'title': 'Chọn ứng dụng ngân hàng',
        },
      );
      
      if (shown == true) {
        log('✅ Successfully showed Android bank app chooser');
        // Hiển thị thông báo hướng dẫn
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '✅ QR code đã được sao chép vào clipboard\n'
                'Sau khi đăng nhập vào app ngân hàng, dán QR code vào ô tìm kiếm',
                style: TextStyle(fontSize: 13),
              ),
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        // Đóng QR scanner sau khi hiển thị chooser
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      } else {
        log('⚠️ Failed to show Android bank app chooser');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể hiển thị danh sách ứng dụng ngân hàng'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        _resetScanner();
      }
    } on PlatformException catch (e) {
      log('⚠️ Platform channel error: ${e.code} - ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi hiển thị danh sách ứng dụng: ${e.message}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _resetScanner();
    } catch (e, stackTrace) {
      log('❌ Error showing bank app chooser: $e');
      log('   Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi hiển thị danh sách ứng dụng: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _resetScanner();
    }
  }

  Future<void> _showAppChooserDialog(String code) async {
    if (!mounted) return;
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mã QR đã quét'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chọn ứng dụng để mở mã QR:'),
            const SizedBox(height: 12),
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              maxLines: 5,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop('open_app');
            },
            child: const Text('Mở với ứng dụng'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop('copy');
            },
            child: const Text('Sao chép'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop('cancel');
            },
            child: const Text('Huỷ'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    switch (result) {
      case 'open_app':
        // Try to parse as URI and launch with app chooser
        await _launchWithAppChooser(code);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: code));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã sao chép'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        _resetScanner();
      case 'cancel':
      default:
        _resetScanner();
    }
  }

  Future<void> _launchWithAppChooser(String code) async {
    if (!mounted) return;
    
    log('🔍 Attempting to launch QR code with app chooser...');
    log('   QR code length: ${code.length}');
    log('   QR code preview: ${code.length > 100 ? '${code.substring(0, 100)}...' : code}');
    
    Uri? uriToLaunch;
    
    // Priority 1: Try to parse the code as URI directly
    log('🔍 Priority 2: Trying to parse as URI...');
    final uri = Uri.tryParse(code);
    
    if (uri != null && uri.scheme.isNotEmpty) {
      log('✅ Parsed as URI: $uri');
      log('   Scheme: ${uri.scheme}');
      try {
        final canLaunch = await canLaunchUrl(uri);
        log('   Can launch: $canLaunch');
        if (canLaunch) {
          uriToLaunch = uri;
          log('✅ Will use direct URI');
        }
      } catch (e, stackTrace) {
        log('❌ Error checking canLaunchUrl for direct URI: $e');
        log('   Stack trace: $stackTrace');
      }
    } else {
      log('   Could not parse as URI (scheme: ${uri?.scheme ?? "null"})');
    }
    
    // Priority 2: Try to construct URL with https:// scheme
    if (uriToLaunch == null) {
      log('🔍 Priority 3: Trying to construct URL with https://...');
      if (code.startsWith('www.') || 
          code.contains('.com') || 
          code.contains('.vn') ||
          code.contains('.org') ||
          code.contains('.net')) {
        final urlWithScheme = Uri.tryParse('https://$code');
        if (urlWithScheme != null) {
          log('✅ Constructed URL: $urlWithScheme');
          try {
            final canLaunch = await canLaunchUrl(urlWithScheme);
            log('   Can launch: $canLaunch');
            if (canLaunch) {
              uriToLaunch = urlWithScheme;
              log('✅ Will use constructed URL');
            }
          } catch (e, stackTrace) {
            log('❌ Error checking canLaunchUrl for constructed URL: $e');
            log('   Stack trace: $stackTrace');
          }
        }
      }
    }
    
    // Note: Không còn thử deep link cho bank QR vì app ngân hàng không hỗ trợ
    // Bank QR sẽ được xử lý ở _handleScannedCode và hiển thị dialog chọn ngân hàng
    
    // Launch with app chooser
    if (uriToLaunch != null) {
      try {
        log('🚀 Launching URI with app chooser: $uriToLaunch');
        await launchUrl(
          uriToLaunch,
          mode: LaunchMode.platformDefault, // Shows app chooser dialog
        );
        log('✅ Successfully launched URI');
        // Close QR scanner after launching
        if (mounted) {
          Navigator.of(context).pop();
        }
      } catch (e, stackTrace) {
        log('❌ CRITICAL: Error launching URI: $e');
        log('   Error type: ${e.runtimeType}');
        log('   Stack trace: $stackTrace');
        log('   URI: $uriToLaunch');
        if (!mounted) return;
        _showErrorDialog('Không thể mở mã QR. Lỗi: ${e.toString()}\n\nVui lòng thử lại hoặc sao chép nội dung.');
        _resetScanner();
      }
    } else {
      // If we can't create a launchable URI, show detailed error
      log('❌ FAILED: Could not find any method to launch QR code');
      log('   Tried: Direct URI, Constructed URL');
      log('   QR code: ${code.length > 200 ? '${code.substring(0, 200)}...' : code}');
      
      if (!mounted) return;
      
      // Show more helpful error dialog
      _showDetailedLaunchErrorDialog(code);
      _resetScanner();
    }
  }

  void _showDetailedLaunchErrorDialog(String code) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text('Không thể mở mã QR')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Không tìm thấy ứng dụng để mở mã QR này. Có thể:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('• Mã QR không hợp lệ'),
              const Text('• Chưa cài đặt ứng dụng liên quan'),
              const Text('• Định dạng mã QR không được hỗ trợ'),
              const SizedBox(height: 12),
              const Text(
                'Mã QR đã quét:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey,
                ),
                maxLines: 10,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã sao chép mã QR'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Sao chép mã QR'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }


  void _showInvalidCodeDialog(String code) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mã QR không hợp lệ'),
        content: Text(
          'Không thể đọc nội dung từ mã QR này.\n\nMã quét được: $code',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetScanner();
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

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lỗi'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetScanner();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _resetScanner() {
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _lastScannedCode = null;
    });
    // Stop scanner first, then restart after a delay
    if (_isScannerStarted) {
      _controller.stop();
      _isScannerStarted = false;
    }
    // Restart scanner after a short delay to allow camera resources to be released
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_hasError && !_isScannerStarted) {
        try {
          _controller.start();
          _isScannerStarted = true;
        } catch (e) {
          log('❌ Error starting scanner: $e');
          // If start fails, reset flag and try again later
          _isScannerStarted = false;
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && !_isScannerStarted) {
              try {
                _controller.start();
                _isScannerStarted = true;
              } catch (e2) {
                log('❌ Error restarting scanner: $e2');
              }
            }
          });
        }
      }
    });
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

    return Stack(
      children: [
        // Dark overlay
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.5),
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
        
        // Scanning frame border (rounded corners only, no sharp corner indicators)
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
      ],
    );
  }

  Rect _getScanArea(Size size) {
    // Calculate scan area to be centered vertically and horizontally
    // Account for AppBar height, safe area, and instructions at bottom
    final media = MediaQuery.of(context);
    final appBarHeight = kToolbarHeight + media.padding.top;
    final bottomPadding = media.padding.bottom;
    const instructionsHeight = 120.0; // Height of instructions box
    const instructionsPadding = 24.0; // Padding below instructions
    
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
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
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
              color: Colors.white.withValues(alpha: 0.7),
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
                color: Colors.white.withValues(alpha: 0.7),
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
                _resetScanner();
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

