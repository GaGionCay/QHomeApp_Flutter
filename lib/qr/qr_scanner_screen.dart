import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_apps/device_apps.dart';
import 'dart:io' show Platform;
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
    // Stop camera synchronously but handle errors gracefully
    if (_isScannerStarted) {
      try {
        _controller.stop();
      } catch (e) {
        log('⚠️ Error stopping camera in dispose: $e');
      }
      _isScannerStarted = false;
    }
    try {
      _controller.dispose();
    } catch (e) {
      log('⚠️ Error disposing camera controller: $e');
    }
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

    // Don't stop camera immediately - let it finish processing current frame
    // Camera will be stopped later when navigating away or in dispose
    // This prevents "BufferQueue has been abandoned" errors

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

  /// Xử lý Bank QR: Flutter quét bank apps, sau đó truyền cho Android chooser
  /// Android chooser chỉ hiển thị những bank apps đã quét được
  Future<void> _handleBankQR(BankQRData bankData, {String? qrCodeString}) async {
    if (!mounted) return;
    
    log('💰 Handling Bank QR: BIN=${bankData.bin}, Account=${bankData.accountNumber}');
    
    final qrCode = qrCodeString ?? _lastScannedQRString ?? '';
    if (qrCode.isEmpty) {
      log('⚠️ QR code string is empty');
      _resetScanner();
      return;
    }
    
    // Copy QR code vào clipboard (silent, không thông báo)
    try {
      await Clipboard.setData(ClipboardData(text: qrCode));
      log('✅ Copied QR code to clipboard (silent)');
    } catch (e) {
      log('⚠️ Error copying QR to clipboard: $e');
    }
    
    // Flutter quét bank apps đã cài đặt (silent, không hiển thị thông báo)
    log('🔍 Scanning bank apps (silent)...');
    final installedApps = await _quickCheckBankApps();
    log('✅ Found ${installedApps.length} installed bank apps');
    
    if (installedApps.isEmpty) {
      log('⚠️ No bank apps found, using text chooser as fallback');
      // Nếu không có bank app nào, fallback về text chooser
      await _showBankQRChooser(qrCode);
      return;
    }
    
    // Truyền danh sách bank apps cho Android chooser
    // Android chooser sẽ chỉ hiển thị những app này
    await _showBankAppChooserWithList(installedApps, qrCode);
  }
  
  /// Quick check bank apps - chỉ check package names đã biết, không quét tất cả apps
  Future<List<String>> _quickCheckBankApps() async {
    final installedPackages = <String>[];
    
    if (!Platform.isAndroid) {
      return installedPackages;
    }
    
    try {
      // Lấy danh sách tất cả package names của bank apps từ BankQRParser
      final allBankPackages = BankQRParser.getAllSupportedBanks()
          .map((bank) => bank.packageName)
          .toList();
      
      // Thêm payment apps
      allBankPackages.addAll([
        'com.mservice.momotransfer',
        'vn.zalo.pay',
        'com.shopeemobile.omc',
        'com.viettelpay',
        'com.vnpay.wallet',
      ]);
      
      // Quick check từng package (nhanh hơn quét tất cả apps)
      for (final packageName in allBankPackages) {
        try {
          // Sử dụng DeviceApps.getApp để check nhanh
          final app = await DeviceApps.getApp(packageName, true);
          if (app != null) {
            installedPackages.add(packageName);
            log('✅ Found installed: $packageName');
          }
        } catch (e) {
          // Ignore errors for individual packages
        }
      }
    } catch (e) {
      log('⚠️ Error checking bank apps: $e');
    }
    
    return installedPackages;
  }
  
  /// Hiển thị Android chooser với danh sách bank apps đã quét được
  /// Android chooser sẽ chỉ hiển thị những app này
  Future<void> _showBankAppChooserWithList(List<String> packageNames, String qrCode) async {
    if (!mounted) return;
    
    log('💰 Showing Android chooser with ${packageNames.length} bank apps');
    
    try {
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
        log('✅ Successfully showed Android chooser with bank apps');
        // Đóng QR scanner ngay sau khi hiển thị chooser (không hiển thị thông báo)
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      } else {
        log('⚠️ Failed to show Android chooser, using text chooser as fallback');
        // Fallback: Dùng text chooser
        await _showBankQRChooser(qrCode);
      }
    } on PlatformException catch (e) {
      log('⚠️ Platform channel error: ${e.code} - ${e.message}');
      // Fallback: Dùng text chooser
      await _showBankQRChooser(qrCode);
    } catch (e, stackTrace) {
      log('❌ Error showing bank app chooser: $e');
      log('   Stack trace: $stackTrace');
      // Fallback: Dùng text chooser
      await _showBankQRChooser(qrCode);
    }
  }

  /// Xử lý URL QR: Flutter quét browser apps, sau đó truyền cho Android chooser
  /// Android chooser chỉ hiển thị những browser apps đã quét được
  Future<void> _handleUrlQR(Uri url) async {
    if (!mounted) return;
    
    log('🌐 Handling URL QR: $url');
    
    // Flutter quét browser apps đã cài đặt (silent, không hiển thị thông báo)
    log('🔍 Scanning browser apps (silent)...');
    final installedBrowsers = await _quickCheckBrowserApps();
    log('✅ Found ${installedBrowsers.length} installed browser apps');
    
    if (installedBrowsers.isEmpty) {
      log('⚠️ No browser apps found, using system chooser as fallback');
      // Nếu không có browser app nào, fallback về system chooser
      try {
        final canLaunch = await canLaunchUrl(url);
        if (canLaunch) {
          await launchUrl(
            url,
            mode: LaunchMode.externalApplication, // Mở app bên ngoài, không phải webview
          );
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        } else {
          _resetScanner();
        }
      } catch (e) {
        log('❌ Error opening URL: $e');
        _resetScanner();
      }
      return;
    }
    
    // Truyền danh sách browser apps cho Android chooser
    // Android chooser sẽ chỉ hiển thị những app này
    await _showBrowserChooserWithList(url, installedBrowsers);
  }
  
  /// Quick check browser apps - chỉ check package names đã biết, không quét tất cả apps
  Future<List<String>> _quickCheckBrowserApps() async {
    final installedPackages = <String>[];
    
    if (!Platform.isAndroid) {
      return installedPackages;
    }
    
    try {
      // Lấy danh sách browser package names từ BankQRParser
      final allBrowserPackages = [
        'com.android.chrome',
        'com.chrome.beta',
        'com.chrome.dev',
        'com.chrome.canary',
        'org.mozilla.firefox',
        'org.mozilla.firefox_beta',
        'org.mozilla.fennec_fdroid',
        'com.microsoft.emmx',
        'com.opera.browser',
        'com.opera.mini.native',
        'com.brave.browser',
        'com.vivaldi.browser',
        'com.duckduckgo.mobile.android',
        'com.uc.browser.en',
        'com.samsung.android.sbrowser',
        'com.mi.globalbrowser',
        'com.huawei.browser',
        'com.sec.android.app.sbrowser',
        'com.browser2345',
        'com.tencent.mtt',
      ];
      
      // Quick check từng package (nhanh hơn quét tất cả apps)
      for (final packageName in allBrowserPackages) {
        try {
          // Sử dụng DeviceApps.getApp để check nhanh
          final app = await DeviceApps.getApp(packageName, true);
          if (app != null) {
            installedPackages.add(packageName);
            log('✅ Found installed browser: $packageName');
          }
        } catch (e) {
          // Ignore errors for individual packages
        }
      }
    } catch (e) {
      log('⚠️ Error checking browser apps: $e');
    }
    
    return installedPackages;
  }
  
  /// Hiển thị Android chooser với danh sách browser apps đã quét được
  /// Android chooser sẽ chỉ hiển thị những app này
  Future<void> _showBrowserChooserWithList(Uri url, List<String> packageNames) async {
    if (!mounted) return;
    
    log('🌐 Showing Android chooser with ${packageNames.length} browser apps');
    
    try {
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
        log('✅ Successfully showed Android chooser with browser apps');
        // Đóng QR scanner ngay sau khi hiển thị chooser (không hiển thị thông báo)
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      } else {
        log('⚠️ Failed to show Android chooser, using system chooser as fallback');
        // Fallback: Dùng system chooser
        try {
          final canLaunch = await canLaunchUrl(url);
          if (canLaunch) {
            await launchUrl(
              url,
              mode: LaunchMode.externalApplication, // Mở app bên ngoài, không phải webview
            );
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted) {
                Navigator.of(context).pop();
              }
            });
          } else {
            _resetScanner();
          }
        } catch (e) {
          log('❌ Error in fallback: $e');
          _resetScanner();
        }
      }
    } on PlatformException catch (e) {
      log('⚠️ Platform channel error: ${e.code} - ${e.message}');
      // Fallback: Dùng system chooser
      try {
        final canLaunch = await canLaunchUrl(url);
        if (canLaunch) {
          await launchUrl(
            url,
            mode: LaunchMode.externalApplication, // Mở app bên ngoài, không phải webview
          );
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        } else {
          _resetScanner();
        }
      } catch (e2) {
        log('❌ Error in fallback: $e2');
        _resetScanner();
      }
    } catch (e, stackTrace) {
      log('❌ Error showing browser chooser: $e');
      log('   Stack trace: $stackTrace');
      _resetScanner();
    }
  }

  /// Hiển thị Android system chooser cho Bank QR code
  /// Android sẽ tự động nhận diện và hiển thị các app tương ứng
  Future<void> _showBankQRChooser(String qrCode) async {
    if (!mounted) return;
    
    log('💰 Showing Android chooser for Bank QR code');
    
    try {
      // Sử dụng platform channel để hiển thị Android chooser với Intent.ACTION_SEND
      // Android sẽ tự động nhận diện và hiển thị tất cả app có thể xử lý text/plain
      // (bao gồm bank apps, note apps, messaging apps, v.v.)
      const channel = MethodChannel('com.qhome.resident/app_launcher');
      final shown = await channel.invokeMethod<bool>(
        'showTextChooser',
        {
          'text': qrCode,
          'title': 'Chọn ứng dụng để xử lý mã QR ngân hàng',
          'hint': 'QR code đã được sao chép vào clipboard',
        },
      );
      
      if (shown == true) {
        log('✅ Successfully showed Android chooser for Bank QR');
        // Đóng QR scanner ngay sau khi hiển thị chooser (không hiển thị thông báo)
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      } else {
        log('⚠️ Failed to show Android chooser');
        // Đóng QR scanner nếu không thể hiển thị chooser
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } on PlatformException catch (e) {
      log('⚠️ Platform channel error: ${e.code} - ${e.message}');
      // Đóng QR scanner nếu có lỗi
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      log('❌ Error showing Bank QR chooser: $e');
      log('   Stack trace: $stackTrace');
      // Đóng QR scanner nếu có lỗi
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  /// Xử lý Unknown QR: Sử dụng Android system chooser
  Future<void> _handleUnknownQR(String code) async {
    if (!mounted) return;
    
    log('❓ Handling Unknown QR');
    
    // Copy QR code vào clipboard
    try {
      await Clipboard.setData(ClipboardData(text: code));
      log('✅ Copied QR code to clipboard');
    } catch (e) {
      log('⚠️ Error copying QR to clipboard: $e');
    }
    
    // Sử dụng Android system chooser để chọn app
    await _showUnknownQRChooser(code);
  }
  
  /// Hiển thị Android system chooser cho Unknown QR code
  Future<void> _showUnknownQRChooser(String code) async {
    if (!mounted) return;
    
    log('❓ Showing Android chooser for Unknown QR code');
    
    try {
      // Thử parse như URL trước
      final uri = Uri.tryParse(code);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        // Nếu là URL, dùng launchUrl với chooser
        final canLaunch = await canLaunchUrl(uri);
        if (canLaunch) {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
          return;
        }
      }
      
      // Nếu không phải URL, dùng platform channel để hiển thị chooser với text
      const channel = MethodChannel('com.qhome.resident/app_launcher');
      final shown = await channel.invokeMethod<bool>(
        'showTextChooser',
        {
          'text': code,
          'title': 'Chọn ứng dụng để xử lý mã QR',
          'hint': 'QR code đã được sao chép vào clipboard',
        },
      );
      
      if (shown == true) {
        log('✅ Successfully showed Android chooser for Unknown QR');
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      } else {
        log('⚠️ Failed to show Android chooser, showing info dialog');
        if (mounted) {
          _showAppChooserDialog(code);
        }
      }
    } on PlatformException catch (e) {
      log('⚠️ Platform channel error: ${e.code} - ${e.message}');
      if (mounted) {
        _showAppChooserDialog(code);
      }
    } catch (e, stackTrace) {
      log('❌ Error showing Unknown QR chooser: $e');
      log('   Stack trace: $stackTrace');
      if (mounted) {
        _showAppChooserDialog(code);
      }
    }
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
    // Don't stop/restart camera if it's already running
    // Just reset the processing state to allow new scans
    // Camera will continue running smoothly
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


