import 'dart:developer' as dev;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:device_apps/device_apps.dart';
import 'package:flutter/services.dart' show PlatformException, MethodChannel;
import 'package:shared_preferences/shared_preferences.dart';

/// Helper function để log với cả dev.log và print (để hiển thị trong logcat Android)
void _log(String message) {
  dev.log(message);
  if (kDebugMode) {
    print('Flutter QR Scanner: $message');
  }
}

/// Enum định nghĩa loại QR code
enum QRType {
  url,      // QR là URL (http/https)
  bankQr,   // QR là mã chuyển khoản ngân hàng (VietQR/Napas/EMVCo)
  unknown,  // QR không xác định được loại
}

/// Model kết quả scan QR code
class QRScanResult {
  final QRType type;
  final String originalCode;
  final BankQRData? bankData;  // Chỉ có khi type == QRType.bankQr
  final Uri? url;               // Chỉ có khi type == QRType.url

  QRScanResult({
    required this.type,
    required this.originalCode,
    this.bankData,
    this.url,
  });

  bool get isUrl => type == QRType.url;
  bool get isBankQr => type == QRType.bankQr;
  bool get isUnknown => type == QRType.unknown;
}

/// Model chứa thông tin QR ngân hàng đã parse theo chuẩn EMVCo
class BankQRData {
  final String? bin; // Bank Identification Number
  final String? accountNumber;
  final String? bankName;
  final double? amount;
  final String? addInfo; // Nội dung thanh toán
  final String? serviceCode; // Mã dịch vụ (nếu có)
  final String? merchantCode; // Mã merchant
  final String? merchantName; // Tên merchant
  final String? transactionCurrency;
  final String? countryCode;
  final String? qrType; // 'static' hoặc 'dynamic'
  final String? originalCode; // Mã QR gốc
  final Map<String, String>? additionalData; // Dữ liệu bổ sung từ EMVCo tags

  BankQRData({
    this.bin,
    this.accountNumber,
    this.bankName,
    this.amount,
    this.addInfo,
    this.serviceCode,
    this.merchantCode,
    this.merchantName,
    this.transactionCurrency,
    this.countryCode,
    this.qrType,
    this.originalCode,
    this.additionalData,
  });

  /// Kiểm tra xem QR có phải là QR động (có số tiền) không
  bool get isDynamic => amount != null && amount! > 0;

  /// Kiểm tra xem QR có đủ thông tin để thanh toán không
  bool get isValid => bin != null && accountNumber != null;

  @override
  String toString() {
    return 'BankQRData(bin: $bin, account: $accountNumber, bank: $bankName, amount: $amount, addInfo: $addInfo)';
  }
}

/// Thông tin ngân hàng để hiển thị trong dialog
class BankInfo {
  final String? bin; // BIN code (null cho payment apps như MoMo, ZaloPay...)
  final String name;
  final String packageName; // Package name trên Android
  final String? playStoreId; // ID trên Google Play Store
  final PaymentAppType type; // Loại app: bank hoặc payment

  const BankInfo({
    this.bin,
    required this.name,
    required this.packageName,
    this.playStoreId,
    this.type = PaymentAppType.bank,
  });

  /// Kiểm tra xem đây có phải là app ngân hàng không
  bool get isBank => type == PaymentAppType.bank && bin != null;

  /// Kiểm tra xem đây có phải là app payment không
  bool get isPaymentApp => type == PaymentAppType.payment;
  
  /// Kiểm tra xem đây có phải là app trình duyệt không
  bool get isBrowser => type == PaymentAppType.browser;
}

/// Loại app payment
enum PaymentAppType {
  bank, // App ngân hàng
  payment, // App payment như MoMo, ZaloPay, ShopeePay...
  browser, // App trình duyệt như Chrome, Firefox, Edge...
}

/// Parser cho QR code ngân hàng theo chuẩn EMVCo và VietQR
class BankQRParser {
  /// Danh sách package name các ngân hàng cần kiểm tra
  /// Lưu ý: Một số ngân hàng có nhiều package name variant
  static const List<String> _bankPackageNames = [
    // Danh sách chính theo yêu cầu
    'com.vietcombank.mobile',
    'com.mbmobile',
    'com.tpb.mobile',
    'com.techcombank',
    'com.sacombank',
    'com.bidv.smartbanking',  // BIDV Smart Banking (variant)
    'com.bidv',                // BIDV variant
    'com.vnpay.bidv',          // BIDV package name thực tế
    'com.vpbank.online',
    
    // Các variant package name (để phát hiện đầy đủ)
    'com.vietcombank',          // Vietcombank variant
    'vn.com.mbmobile',          // MB Bank variant
    'com.tpb.mb.gprsandroid',   // TPBank variant (package name thực tế)
    'com.vietinbank.vpb',       // VietinBank variant (cũ)
    'com.vietinbank.ipay',      // VietinBank iPay (package name thực tế)
    'com.agribank.mb',          // Agribank variant
    'com.vnpay.Agribank3g',     // Agribank package name thực tế
    'com.acb.fastbank',         // ACB
    'com.vpbank.mobile',        // VPBank variant
    'com.shb.mobilebanking',    // SHB
    'com.hsbc.hsbcvietnam',     // HSBC
    'com.vietbank.mobilebanking', // Vietbank
    'com.namabank.mobile',      // Nam A Bank
    'com.eximbank.mobile',      // Eximbank
    'com.ocb.omni',             // OCB
    'com.scb.digital',          // SCB
    'com.dongabank.mobile',     // DongA Bank
    'com.pvcombank.mobile',     // PVComBank
    'com.publicbank.mobile',    // PublicBank
    'com.ncb.mobile',           // NCB
  ];

  /// Danh sách package name các app payment (MoMo, ZaloPay, ShopeePay...)
  static const Map<String, BankInfo> _paymentApps = {
    'com.mservice.momotransfer': BankInfo(
      bin: null,
      name: 'MoMo',
      packageName: 'com.mservice.momotransfer',
      playStoreId: 'com.mservice.momotransfer',
      type: PaymentAppType.payment,
    ),
    'vn.zalo.pay': BankInfo(
      bin: null,
      name: 'ZaloPay',
      packageName: 'vn.zalo.pay',
      playStoreId: 'vn.zalo.pay',
      type: PaymentAppType.payment,
    ),
    'com.shopeemobile.omc': BankInfo(
      bin: null,
      name: 'ShopeePay',
      packageName: 'com.shopeemobile.omc',
      playStoreId: 'com.shopeemobile.omc',
      type: PaymentAppType.payment,
    ),
    'com.viettelpay': BankInfo(
      bin: null,
      name: 'ViettelPay',
      packageName: 'com.viettelpay',
      playStoreId: 'com.viettelpay',
      type: PaymentAppType.payment,
    ),
    'com.vnpay.wallet': BankInfo(
      bin: null,
      name: 'VNPay',
      packageName: 'com.vnpay.wallet',
      playStoreId: 'com.vnpay.wallet',
      type: PaymentAppType.payment,
    ),
  };

  /// Danh sách tất cả package name cần kiểm tra (bao gồm cả bank, payment và browser apps)
  static List<String> get _allPackageNames => [
    ..._bankPackageNames,
    ..._paymentApps.keys,
    ..._browserPackageNames,
  ];
  
  /// Danh sách tất cả package name browser để kiểm tra riêng
  static List<String> get _allBrowserPackageNames => _browserPackageNames;

  /// Key để lưu dynamic package name mapping vào SharedPreferences
  static const String _dynamicPackageMappingKey = 'bank_qr_dynamic_package_mapping';
  
  /// Cache cho dynamic package mapping (để tránh đọc SharedPreferences nhiều lần)
  static Map<String, String>? _dynamicPackageMappingCache;

  /// Map BIN code sang thông tin ngân hàng
  static const Map<String, BankInfo> _binToBankInfo = {
    '970436': BankInfo(
      bin: '970436',
      name: 'Vietcombank',
      packageName: 'com.vietcombank.mobile',
      playStoreId: 'com.vietcombank',
    ),
    '970415': BankInfo(
      bin: '970415',
      name: 'VietinBank',
      packageName: 'com.vietinbank.ipay', // Package name thực tế (VietinBank iPay)
      playStoreId: 'com.vietinbank.ipay',
    ),
    '970418': BankInfo(
      bin: '970418',
      name: 'BIDV',
      packageName: 'com.vnpay.bidv', // Package name thực tế (app đã cài)
      playStoreId: 'com.vnpay.bidv',
    ),
    '970405': BankInfo(
      bin: '970405',
      name: 'Agribank',
      packageName: 'com.agribank.mb',
      playStoreId: 'com.agribank.mb',
    ),
    '970407': BankInfo(
      bin: '970407',
      name: 'Techcombank',
      packageName: 'com.techcombank',
      playStoreId: 'com.techcombank.ebanking',
    ),
    '970416': BankInfo(
      bin: '970416',
      name: 'ACB',
      packageName: 'com.acb.fastbank',
      playStoreId: 'com.acb.fastbank',
    ),
    '970423': BankInfo(
      bin: '970423',
      name: 'TPBank',
      packageName: 'com.tpb.mb.gprsandroid',
      playStoreId: 'com.tpb.mb.gprsandroid',
    ),
    '970422': BankInfo(
      bin: '970422',
      name: 'MB Bank',
      packageName: 'com.mbmobile', // Package name thực tế (app đã cài)
      playStoreId: 'com.mbmobile',
    ),
    '970432': BankInfo(
      bin: '970432',
      name: 'VPBank',
      packageName: 'com.vpbank.online',
      playStoreId: 'com.vpbank.mobile',
    ),
    '970403': BankInfo(
      bin: '970403',
      name: 'Sacombank',
      packageName: 'com.sacombank',
      playStoreId: 'com.sacombank.stb',
    ),
    '970443': BankInfo(
      bin: '970443',
      name: 'SHB',
      packageName: 'com.shb.mobilebanking',
      playStoreId: 'com.shb.mobilebanking',
    ),
    '970421': BankInfo(
      bin: '970421',
      name: 'HSBC',
      packageName: 'com.hsbc.hsbcvietnam',
      playStoreId: 'com.hsbc.hsbcvietnam',
    ),
    '970427': BankInfo(
      bin: '970427',
      name: 'Vietbank',
      packageName: 'com.vietbank.mobilebanking',
      playStoreId: 'com.vietbank.mobilebanking',
    ),
    '970428': BankInfo(
      bin: '970428',
      name: 'Nam A Bank',
      packageName: 'com.namabank.mobile',
      playStoreId: 'com.namabank.mobile',
    ),
    '970441': BankInfo(
      bin: '970441',
      name: 'Eximbank',
      packageName: 'com.eximbank.mobile',
      playStoreId: 'com.eximbank.mobile',
    ),
    '970446': BankInfo(
      bin: '970446',
      name: 'OCB',
      packageName: 'com.ocb.omni',
      playStoreId: 'com.ocb.omni',
    ),
    '970448': BankInfo(
      bin: '970448',
      name: 'SCB',
      packageName: 'com.scb.digital',
      playStoreId: 'com.scb.digital',
    ),
    '970451': BankInfo(
      bin: '970451',
      name: 'DongA Bank',
      packageName: 'com.dongabank.mobile',
      playStoreId: 'com.dongabank.mobile',
    ),
    '970454': BankInfo(
      bin: '970454',
      name: 'PVComBank',
      packageName: 'com.pvcombank.mobile',
      playStoreId: 'com.pvcombank.mobile',
    ),
    '970457': BankInfo(
      bin: '970457',
      name: 'PublicBank',
      packageName: 'com.publicbank.mobile',
      playStoreId: 'com.publicbank.mobile',
    ),
    '970458': BankInfo(
      bin: '970458',
      name: 'NCB',
      packageName: 'com.ncb.mobile',
      playStoreId: 'com.ncb.mobile',
    ),
  };

  /// ============================================
  /// HÀM CHÍNH: Nhận diện và phân loại QR code
  /// ============================================
  /// 
  /// Luồng xử lý:
  /// 1. Kiểm tra nếu là URL (http/https) → trả về QRType.url
  /// 2. Kiểm tra nếu là VietQR/Napas/EMVCo → parse và trả về QRType.bankQr
  /// 3. Nếu không xác định được → trả về QRType.unknown
  static QRScanResult identifyAndParseQR(String qrCode) {
    if (qrCode.isEmpty) {
      _log('⚠️ QR code is empty');
      return QRScanResult(
        type: QRType.unknown,
        originalCode: qrCode,
      );
    }

    _log('🔍 Starting to identify QR code (length: ${qrCode.length})');
    _log('📄 QR code preview: ${qrCode.length > 100 ? qrCode.substring(0, 100) + "..." : qrCode}');

    try {
      // Bước 1: Kiểm tra nếu là URL (http/https)
      _log('🔍 Step 1: Checking if QR is URL format...');
      final urlResult = _checkIfUrl(qrCode);
      if (urlResult != null) {
        _log('✅ QR identified as URL: $urlResult');
        return QRScanResult(
          type: QRType.url,
          originalCode: qrCode,
          url: urlResult,
        );
      }

      // Bước 2: Kiểm tra nếu là VietQR/Napas/EMVCo
      _log('🔍 Step 2: Checking if QR is VietQR/Napas/EMVCo format...');
      final bankData = _parseBankQR(qrCode);
      if (bankData != null && bankData.isValid) {
        _log('✅ QR identified as Bank QR: BIN=${bankData.bin}, Account=${bankData.accountNumber}');
        return QRScanResult(
          type: QRType.bankQr,
          originalCode: qrCode,
          bankData: bankData,
        );
      }

      // Bước 3: Không xác định được loại
      _log('⚠️ QR code could not be identified, returning as UNKNOWN');
      return QRScanResult(
        type: QRType.unknown,
        originalCode: qrCode,
      );
    } catch (e, stackTrace) {
      _log('❌ CRITICAL: Unexpected error identifying QR code: $e');
      _log('   Error type: ${e.runtimeType}');
      _log('   Stack trace: $stackTrace');
      return QRScanResult(
        type: QRType.unknown,
        originalCode: qrCode,
      );
    }
  }

  /// Kiểm tra xem QR có phải là URL không
  static Uri? _checkIfUrl(String qrCode) {
    try {
      final uri = Uri.tryParse(qrCode);
      if (uri != null && 
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty) {
        return uri;
      }
      return null;
    } catch (e) {
      _log('   Error checking URL: $e');
      return null;
    }
  }

  /// Parse QR code ngân hàng (VietQR/Napas/EMVCo)
  static BankQRData? _parseBankQR(String qrCode) {
    try {
      // 1. Kiểm tra nếu là VietQR URL (https://img.vietqr.io/image/...)
      final vietQRUrlInfo = _parseVietQRUrl(qrCode);
      if (vietQRUrlInfo != null) {
        _log('   ✅ Parsed as VietQR URL');
        return vietQRUrlInfo;
      }

      // 2. Kiểm tra nếu là VietQR deep link (vietqr://...)
      final vietQRDeepLinkInfo = _parseVietQRDeepLink(qrCode);
      if (vietQRDeepLinkInfo != null) {
        _log('   ✅ Parsed as VietQR deep link');
        return vietQRDeepLinkInfo;
      }

      // 3. Kiểm tra nếu là EMVCo TLV (bắt đầu bằng 000201)
      if (qrCode.startsWith('000201')) {
        final emvCoInfo = _parseEMVCoTLV(qrCode);
        if (emvCoInfo != null && emvCoInfo.isValid) {
          _log('   ✅ Parsed as EMVCo TLV');
          return emvCoInfo;
        }
      }

      return null;
    } catch (e, stackTrace) {
      _log('❌ Error parsing bank QR: $e');
      _log('   Stack trace: $stackTrace');
      return null;
    }
  }

  /// Parse VietQR URL: https://img.vietqr.io/image/{bank}-{bin}-{acct}.png?...
  static BankQRData? _parseVietQRUrl(String qrCode) {
    try {
      final uri = Uri.tryParse(qrCode);
      if (uri == null || !uri.host.contains('vietqr.io')) {
        return null;
      }

      final pathSegments = uri.pathSegments;
      if (pathSegments.length < 2 || pathSegments[0] != 'image') {
        return null;
      }

      final imageName = pathSegments[1];
      final parts = imageName.split('-');
      if (parts.length < 3) {
        return null;
      }

      final bin = parts[1];
      final account = parts[2].replaceAll('.png', '');

      return BankQRData(
        bin: bin,
        accountNumber: account,
        bankName: _binToBankInfo[bin]?.name,
        qrType: 'static',
        originalCode: qrCode,
      );
    } catch (e) {
      return null;
    }
  }

  /// Parse VietQR deep link: vietqr://{bin}/{acct}?amount=...&addInfo=...
  static BankQRData? _parseVietQRDeepLink(String qrCode) {
    try {
      final uri = Uri.tryParse(qrCode);
      if (uri == null || uri.scheme != 'vietqr') {
        return null;
      }

      final pathSegments = uri.pathSegments;
      if (pathSegments.length < 2) {
        return null;
      }

      final bin = pathSegments[0];
      final account = pathSegments[1];
      final amount = uri.queryParameters['amount'];
      final addInfo = uri.queryParameters['addInfo'];

      return BankQRData(
        bin: bin,
        accountNumber: account,
        bankName: _binToBankInfo[bin]?.name,
        amount: amount != null ? double.tryParse(amount) : null,
        addInfo: addInfo,
        qrType: amount != null ? 'dynamic' : 'static',
        originalCode: qrCode,
      );
    } catch (e) {
      return null;
    }
  }

  /// Parse EMVCo TLV (Napas standard) - CHUẨN NAPAS/VietQR
  /// Format: Tag (2 chars) + Length (2 chars) + Value (variable length)
  static BankQRData? _parseEMVCoTLV(String qrCode) {
    try {
      if (!qrCode.startsWith('000201')) {
        return null;
      }

      _log('   Attempting to parse as EMVCo TLV...');
      
      final data = <String, String>{};
      int i = 6; // Bỏ qua header 000201
      int tagCount = 0;

      // Parse các tags theo chuẩn TLV
      while (i < qrCode.length) {
        if (i + 2 > qrCode.length) break;

        final tag = qrCode.substring(i, i + 2);
        i += 2;

        if (i + 2 > qrCode.length) break;

        final lengthStr = qrCode.substring(i, i + 2);
        final length = int.tryParse(lengthStr) ?? 0;
        i += 2;

        if (i + length > qrCode.length) break;

        final value = qrCode.substring(i, i + length);
        i += length;

        data[tag] = value;
        tagCount++;

        // Nested TLV (ví dụ: tag 62, 26, 38)
        if (tag == '62' || tag == '26' || tag == '38') {
          try {
            Map<String, String> nested;
            
            // Tag 38 có format đặc biệt: PNI (Payment Network Identifier) + nested TLV
            if (tag == '38' && value.length > 10) {
              String nestedData;
              if (value.startsWith('0010') && value.length > 14) {
                nestedData = value.substring(14); // Bỏ qua 0010 + PNI
              } else if (value.length > 10) {
                nestedData = value.substring(10); // Bỏ qua PNI
              } else {
                nestedData = value;
              }
              nested = _parseNestedTLV(nestedData);
            } else {
              nested = _parseNestedTLV(value);
            }
            
            data.addAll(nested.map((key, val) => MapEntry('$tag.$key', val)));
          } catch (e) {
            _log('   ⚠️ Error parsing nested TLV for tag $tag: $e');
          }
        }
      }

      _log('   ✅ Finished parsing EMVCo TLV: found $tagCount top-level tags');

      // Extract thông tin từ các tag chuẩn EMVCo
      String? bin;
      String? accountNumber;
      
      // Priority 1: Thử extract từ tag 38 (nested TLV)
      if (data.containsKey('38.01')) {
        final tag38_01 = data['38.01']!;
        final binMatch = RegExp(r'970\d{3}').firstMatch(tag38_01);
        if (binMatch != null) {
          bin = binMatch.group(0);
          final binIndex = tag38_01.indexOf(bin!);
          if (binIndex >= 0 && tag38_01.length > binIndex + 6) {
            final afterBin = tag38_01.substring(binIndex + 6);
            final accountMatch = RegExp(r'[0-9]+').firstMatch(afterBin);
            if (accountMatch != null) {
              accountNumber = accountMatch.group(0);
            }
          }
        }
      }
      
      // Priority 2: Thử từ tag 26
      if ((bin == null || accountNumber == null || accountNumber.isEmpty) && data.containsKey('26')) {
        final tag26 = data['26']!;
        if (tag26.length >= 6) {
          int binStart = 0;
          if (tag26.startsWith('0010') && tag26.length > 10) {
            binStart = 4;
          }
          if (tag26.length >= binStart + 6) {
            final potentialBin = tag26.substring(binStart, binStart + 6);
            if (RegExp(r'970\d{3}').hasMatch(potentialBin)) {
              if (bin == null) bin = potentialBin;
              if ((accountNumber == null || accountNumber.isEmpty) && tag26.length > binStart + 6) {
                accountNumber = tag26.substring(binStart + 6);
              }
            }
          }
        }
      }

      // Priority 3: Thử từ tag 62 hoặc các nguồn khác
      if (accountNumber == null || accountNumber.isEmpty) {
        if (data.containsKey('62')) {
          accountNumber = _extractAccountFrom62(data['62']!);
        }
        if (accountNumber == null || accountNumber.isEmpty) {
          accountNumber = _extractAccountNumber(data);
        }
      }
      
      // Priority 4: Nếu vẫn không tìm thấy BIN, tìm trong toàn bộ QR code
      if (bin == null) {
        final binPattern = RegExp(r'970\d{3}');
        final binMatch = binPattern.firstMatch(qrCode);
        if (binMatch != null) {
          bin = binMatch.group(0);
        }
      }

      // Parse các thông tin khác từ EMVCo tags
      final amount = data['54'] != null ? double.tryParse(data['54']!) : null;
      final addInfo = data['08'] ?? data['62.08'] ?? data['62.01'];
      final merchantName = data['59'];
      final merchantCode = data['26'];
      final currency = data['53'];
      final countryCode = data['58'];
      final serviceCode = data['62.05'];

      final result = BankQRData(
        bin: bin,
        accountNumber: accountNumber,
        bankName: bin != null ? _binToBankInfo[bin]?.name : null,
        amount: amount,
        addInfo: addInfo,
        merchantName: merchantName,
        merchantCode: merchantCode,
        transactionCurrency: currency,
        countryCode: countryCode,
        serviceCode: serviceCode,
        qrType: amount != null ? 'dynamic' : 'static',
        originalCode: qrCode,
        additionalData: data,
      );
      
      _log('   📊 Summary: BIN=$bin, Account=$accountNumber, Amount=$amount, Type=${result.qrType}');
      return result;
    } catch (e, stackTrace) {
      _log('❌ Error parsing EMVCo TLV: $e');
      _log('   Stack trace: $stackTrace');
      return null;
    }
  }

  /// Parse nested TLV (trong tag 62 hoặc 26)
  static Map<String, String> _parseNestedTLV(String value) {
    final data = <String, String>{};
    int i = 0;

    while (i < value.length) {
      if (i + 2 > value.length) break;

      final subTag = value.substring(i, i + 2);
      i += 2;

      if (i + 2 > value.length) break;

      final lengthStr = value.substring(i, i + 2);
      final length = int.tryParse(lengthStr) ?? 0;
      i += 2;

      if (i + length > value.length) break;

      final subValue = value.substring(i, i + length);
      i += length;

      data[subTag] = subValue;
    }

    return data;
  }

  /// Extract số tài khoản từ data
  static String? _extractAccountNumber(Map<String, String> data) {
    final tag26 = data['26'];
    if (tag26 != null && tag26.length > 6) {
      return tag26.substring(6);
    }

    final tag62_01 = data['62.01'];
    if (tag62_01 != null) {
      return tag62_01;
    }

    return null;
  }

  /// Extract số tài khoản từ tag 62
  static String? _extractAccountFrom62(String tag62) {
    try {
      final nested = _parseNestedTLV(tag62);
      return nested['01'];
    } catch (e) {
      return null;
    }
  }

  /// Từ khóa để tự động nhận diện app ngân hàng/payment
  /// Lưu ý: Loại trừ các từ khóa có thể gây nhầm lẫn (keyboard, inputmethod, etc.)
  static const List<String> _bankingKeywords = [
    'bank', 'banking', 'ngân hàng', 'vietcombank', 'vietinbank', 'bidv', 
    'techcombank', 'acb', 'agribank', 'sacombank', 'vpbank', 'tpbank', 
    'mb bank', 'mbbank', 'vietbank', 'hsbc', 'shb', 'nam a bank', 
    'eximbank', 'ocb', 'scb', 'dong a', 'pvcombank', 'publicbank', 'ncb',
  ];
  
  /// Từ khóa loại trừ - không phải bank app (tránh nhầm lẫn)
  static const List<String> _excludeKeywords = [
    'keyboard', 'bàn phím', 'inputmethod', 'ime', 'gboard', 'swiftkey',
    'labankey', 'vietkey', 'unikey', 'key', 'typing', 'input',
  ];
  
  static const List<String> _paymentKeywords = [
    'momo', 'zalopay', 'zalo pay', 'shopeepay', 'shopee pay', 
    'viettelpay', 'vnpay', 'pay', 'wallet', 'ví', 'thanh toán',
  ];
  
  /// Danh sách package name các trình duyệt phổ biến
  static const List<String> _browserPackageNames = [
    'com.android.chrome',           // Chrome
    'com.chrome.beta',              // Chrome Beta
    'com.chrome.dev',               // Chrome Dev
    'com.chrome.canary',            // Chrome Canary
    'org.mozilla.firefox',          // Firefox
    'org.mozilla.firefox_beta',     // Firefox Beta
    'org.mozilla.fennec_fdroid',    // Firefox Fennec
    'com.microsoft.emmx',           // Edge
    'com.opera.browser',            // Opera
    'com.opera.mini.native',        // Opera Mini
    'com.brave.browser',            // Brave
    'com.vivaldi.browser',          // Vivaldi
    'com.duckduckgo.mobile.android', // DuckDuckGo
    'com.uc.browser.en',            // UC Browser
    'com.samsung.android.sbrowser', // Samsung Internet
    'com.mi.globalbrowser',         // Mi Browser
    'com.huawei.browser',           // Huawei Browser
    'com.sec.android.app.sbrowser', // Samsung Browser variant
    'com.browser2345',              // 2345 Browser
    'com.tencent.mtt',              // QQ Browser
  ];
  
  static const List<String> _browserKeywords = [
    'browser', 'chrome', 'firefox', 'edge', 'opera', 'safari',
    'trình duyệt', 'webview', 'brave', 'vivaldi', 'duckduckgo',
    'internet', 'explorer', 'navigator', 'web', 'sbrowser', 'mi browser',
    'samsung internet', 'huawei browser', 'uc browser', 'qq browser',
  ];

  /// ============================================
  /// HÀM: Kiểm tra TẤT CẢ app payment/banking đã cài đặt
  /// ============================================
  /// 
  /// Quét TẤT CẢ app đã cài trên thiết bị (không cache, luôn quét mới nhất)
  /// Có 2 cách phát hiện:
  /// 1. Filter theo danh sách package name đã biết (_bankPackageNames + _paymentApps)
  /// 2. Tự động nhận diện theo tên app và keywords (để phát hiện app mới)
  /// Bao gồm cả app ngân hàng và app payment (MoMo, ZaloPay, ShopeePay...)
  /// Trả về danh sách TẤT CẢ app payment/banking đã được cài đặt
  static Future<List<BankInfo>> detectInstalledPaymentApps() async {
    _log('🔍 Starting to detect installed payment/banking apps (scanning all installed apps)...');
    
    final installedApps = <BankInfo>[];
    final allPackageNamesSet = _allPackageNames.toSet(); // Set để lookup nhanh hơn
    final foundPackageNames = <String>{}; // Track các package đã tìm thấy
    
    try {
      if (Platform.isAndroid) {
        // Cách 1: Quét TẤT CẢ app đã cài (hiệu quả và luôn mới nhất)
        try {
          _log('📱 Getting all installed applications...');
          final allApps = await DeviceApps.getInstalledApplications(
            includeAppIcons: false, // Không cần icon để nhanh hơn
            includeSystemApps: false, // Chỉ app user cài
            onlyAppsWithLaunchIntent: true, // Chỉ app có thể mở được
          );
          
          _log('📊 Found ${allApps.length} total installed apps');
          
          // Filter và map sang BankInfo
          for (final app in allApps) {
            final packageName = app.packageName;
            final appName = app.appName.toLowerCase();
            
            BankInfo? appInfo;
            
            // Cách 1: Kiểm tra theo package name đã biết
            if (allPackageNamesSet.contains(packageName)) {
              try {
                // Kiểm tra xem có phải payment app không
                if (_paymentApps.containsKey(packageName)) {
                  appInfo = _paymentApps[packageName];
                } else {
                  // Kiểm tra xem có phải bank app không
                  appInfo = _findBankByPackageName(packageName);
                }
              } catch (e) {
                _log('⚠️ Error processing known app $packageName: $e');
              }
            }
            
            // Cách 2: Tự động nhận diện theo tên app (nếu chưa tìm thấy)
            if (appInfo == null) {
              // Kiểm tra loại trừ trước - không phải app ngân hàng/payment
              final isExcluded = _excludeKeywords.any((keyword) =>
                appName.contains(keyword.toLowerCase()) ||
                packageName.contains(keyword.toLowerCase()));
              
              if (isExcluded) {
                // Đây là app không phải bank/payment (ví dụ: keyboard, inputmethod)
                continue; // Bỏ qua app này
              }
              
              // Kiểm tra xem tên app có chứa keywords ngân hàng/payment không
              final isBankingApp = _bankingKeywords.any((keyword) => 
                appName.contains(keyword.toLowerCase()) || 
                packageName.contains(keyword.toLowerCase()));
              
              final isPaymentApp = _paymentKeywords.any((keyword) => 
                appName.contains(keyword.toLowerCase()) || 
                packageName.contains(keyword.toLowerCase()));
              
              if (isBankingApp || isPaymentApp) {
                // Tự động tạo BankInfo từ app name
                final displayName = app.appName;
                final appType = isPaymentApp ? PaymentAppType.payment : PaymentAppType.bank;
                
                // Thử tìm BIN code từ package name hoặc app name
                String? bin;
                if (isBankingApp) {
                  // Tìm BIN code từ mapping - ưu tiên match theo tên ngân hàng
                  for (final entry in _binToBankInfo.entries) {
                    final bankInfo = entry.value;
                    final bankNameLower = bankInfo.name.toLowerCase();
                    
                    // Kiểm tra match theo tên ngân hàng (ưu tiên cao nhất)
                    if (appName.contains(bankNameLower) || 
                        bankNameLower.contains(appName) ||
                        packageName.contains(bankNameLower.replaceAll(' ', '').replaceAll('bank', ''))) {
                      bin = entry.key;
                      
                      // ✅ QUAN TRỌNG: Update package name thực tế vào BankInfo
                      // Tạo BankInfo mới với package name thực tế (từ app đã cài)
                      appInfo = BankInfo(
                        bin: bin,
                        name: bankInfo.name, // Giữ tên chuẩn từ mapping
                        packageName: packageName, // ✅ Dùng package name thực tế (app đã cài)
                        playStoreId: packageName, // ✅ Dùng package name thực tế
                        type: appType,
                      );
                      
                      _log('🔄 Auto-updated package name for ${bankInfo.name}: ${bankInfo.packageName} → $packageName');
                      
                      // ✅ Tự động lưu package name mới vào dynamic mapping
                      // Để persist giữa các lần chạy app và tự động update khi phát hiện thay đổi
                      _updatePackageNameIfChanged(bin, packageName);
                      
                      break;
                    }
                    
                    // Nếu không match tên, thử match theo package name pattern
                    if (packageName.contains(bankInfo.packageName.toLowerCase()) ||
                        _isPackageNameVariant(packageName, bankInfo.packageName)) {
                      bin = entry.key;
                      
                      appInfo = BankInfo(
                        bin: bin,
                        name: bankInfo.name,
                        packageName: packageName, // ✅ Dùng package name thực tế
                        playStoreId: packageName,
                        type: appType,
                      );
                      
                      _log('🔄 Auto-updated package name via pattern matching for ${bankInfo.name}: ${bankInfo.packageName} → $packageName');
                      
                      // ✅ Tự động lưu package name mới vào dynamic mapping
                      _updatePackageNameIfChanged(bin, packageName);
                      
                      break;
                    }
                  }
                  
                  // Nếu không tìm thấy trong mapping, thử tìm BIN từ package name variant
                  if (appInfo == null && bin == null) {
                    final foundBin = _findBinFromPackageName(packageName);
                    if (foundBin != null) {
                      bin = foundBin;
                      final baseBankInfo = _binToBankInfo[bin];
                      if (baseBankInfo != null) {
                        // Tạo BankInfo với package name thực tế
                        appInfo = BankInfo(
                          bin: bin,
                          name: baseBankInfo.name,
                          packageName: packageName, // ✅ Dùng package name thực tế
                          playStoreId: packageName,
                          type: appType,
                        );
                        _log('🔄 Auto-updated package name via package variant for ${baseBankInfo.name}: ${baseBankInfo.packageName} → $packageName');
                        
                        // ✅ Tự động lưu package name mới vào dynamic mapping
                        _updatePackageNameIfChanged(bin, packageName);
                      }
                    }
                  }
                  
                  // Nếu vẫn không tìm thấy, tạo mới (bank app không có trong mapping)
                  if (appInfo == null) {
                    appInfo = BankInfo(
                      bin: bin,
                      name: displayName,
                      packageName: packageName,
                      playStoreId: packageName,
                      type: appType,
                    );
                    _log('🆕 Auto-detected new bank app (not in mapping): $displayName ($packageName)');
                  }
                } else {
                  // Payment app
                  appInfo = BankInfo(
                    bin: null,
                    name: displayName,
                    packageName: packageName,
                    playStoreId: packageName,
                    type: appType,
                  );
                }
                
                _log('🔍 Auto-detected ${appType.name} app: $displayName ($packageName)${bin != null ? " [BIN: $bin]" : ""}');
              }
            }
            
            // Thêm vào danh sách nếu tìm thấy
            if (appInfo != null && !foundPackageNames.contains(packageName)) {
              _log('✅ Found installed: ${appInfo.name} ($packageName) - ${appInfo.type.name}');
              installedApps.add(appInfo);
              foundPackageNames.add(packageName);
            }
          }
        } catch (e) {
          _log('❌ Error getting all installed apps: $e');
          _log('   Falling back to individual package check...');
          
          // Cách 2: Fallback - Kiểm tra từng package name (chậm hơn nhưng đáng tin cậy)
          for (final packageName in _allPackageNames) {
            try {
              final isInstalled = await _isAppInstalled(packageName);
              if (isInstalled) {
                BankInfo? appInfo;
                
                if (_paymentApps.containsKey(packageName)) {
                  appInfo = _paymentApps[packageName];
                } else {
                  appInfo = _findBankByPackageName(packageName);
                }
                
                if (appInfo != null && !installedApps.any((app) => 
                  app.packageName == appInfo!.packageName)) {
                  _log('✅ Found installed (fallback): ${appInfo.name} ($packageName)');
                  installedApps.add(appInfo);
                }
              }
            } catch (e) {
              _log('⚠️ Error checking app $packageName: $e');
            }
          }
        }
      } else {
        _log('⚠️ Platform not supported: Only Android is supported');
      }
    } catch (e, stackTrace) {
      _log('❌ CRITICAL: Error detecting installed apps: $e');
      _log('   Stack trace: $stackTrace');
    }
    
    // Sắp xếp: Payment apps trước, sau đó bank apps (theo tên)
    installedApps.sort((a, b) {
      // Sắp xếp theo type trước (payment trước bank)
      if (a.type != b.type) {
        return a.type == PaymentAppType.payment ? -1 : 1;
      }
      // Sau đó sắp xếp theo tên
      return a.name.compareTo(b.name);
    });
    
    _log('📊 Final result: Found ${installedApps.length} installed payment/banking apps');
    return installedApps;
  }

  /// ============================================
  /// HÀM: Kiểm tra TẤT CẢ app trình duyệt đã cài đặt
  /// ============================================
  /// 
  /// Quét TẤT CẢ app đã cài trên thiết bị (không cache, luôn quét mới nhất)
  /// Có 2 cách phát hiện:
  /// 1. Filter theo danh sách package name đã biết (_browserPackageNames)
  /// 2. Tự động nhận diện theo tên app và keywords (để phát hiện browser mới)
  /// Trả về danh sách TẤT CẢ app trình duyệt đã được cài đặt
  static Future<List<BankInfo>> detectInstalledBrowserApps() async {
    _log('🌐 Starting to detect installed browser apps (scanning all installed apps)...');
    
    final installedBrowsers = <BankInfo>[];
    final browserPackageNamesSet = _allBrowserPackageNames.toSet();
    final foundPackageNames = <String>{};
    
    try {
      if (Platform.isAndroid) {
        // Cách 1: Quét TẤT CẢ app đã cài (hiệu quả và luôn mới nhất)
        try {
          _log('📱 Getting all installed applications...');
          final allApps = await DeviceApps.getInstalledApplications(
            includeAppIcons: false,
            includeSystemApps: false,
            onlyAppsWithLaunchIntent: true,
          );
          
          _log('📊 Found ${allApps.length} total installed apps');
          
          // Filter và map sang BankInfo
          for (final app in allApps) {
            final packageName = app.packageName;
            final appName = app.appName.toLowerCase();
            
            BankInfo? browserInfo;
            
            // Cách 1: Kiểm tra theo package name đã biết
            if (browserPackageNamesSet.contains(packageName)) {
              try {
                // Tạo BankInfo cho browser
                browserInfo = BankInfo(
                  bin: null,
                  name: app.appName,
                  packageName: packageName,
                  playStoreId: packageName,
                  type: PaymentAppType.browser,
                );
              } catch (e) {
                _log('⚠️ Error processing known browser $packageName: $e');
              }
            }
            
            // Cách 2: Tự động nhận diện theo tên app (nếu chưa tìm thấy)
            if (browserInfo == null) {
              // Kiểm tra xem tên app có chứa keywords browser không
              final isBrowserApp = _browserKeywords.any((keyword) => 
                appName.contains(keyword.toLowerCase()) || 
                packageName.contains(keyword.toLowerCase()));
              
              if (isBrowserApp) {
                // ✅ Tự động tạo BankInfo cho browser (tự động thêm vào hệ thống)
                // Package name sẽ tự động được thêm vào danh sách khi phát hiện
                browserInfo = BankInfo(
                  bin: null,
                  name: app.appName,
                  packageName: packageName, // ✅ Dùng package name thực tế (từ app đã cài)
                  playStoreId: packageName, // ✅ Dùng package name thực tế
                  type: PaymentAppType.browser,
                );
                
                _log('🔍 Auto-detected browser app: ${app.appName} ($packageName)');
                _log('   ✅ Auto-added package name to system: $packageName');
              }
            }
            
            // Cách 3: Kiểm tra intent filter (nếu app có thể xử lý URL http/https)
            // Điều này giúp phát hiện các browser không có keyword trong tên
            if (browserInfo == null) {
              // Kiểm tra xem package name có pattern giống browser không
              // Ví dụ: *.browser.*, *.webview.*, *.chrome.*
              final browserPatterns = [
                'browser', 'chrome', 'firefox', 'edge', 'opera', 'safari',
                'webview', 'web', 'internet', 'explorer', 'navigator'
              ];
              
              final hasBrowserPattern = browserPatterns.any((pattern) =>
                packageName.toLowerCase().contains(pattern) ||
                appName.contains(pattern));
              
              if (hasBrowserPattern) {
                // Tự động tạo BankInfo cho browser
                browserInfo = BankInfo(
                  bin: null,
                  name: app.appName,
                  packageName: packageName, // ✅ Dùng package name thực tế
                  playStoreId: packageName,
                  type: PaymentAppType.browser,
                );
                
                _log('🔍 Auto-detected browser app via pattern: ${app.appName} ($packageName)');
                _log('   ✅ Auto-added package name to system: $packageName');
              }
            }
            
            // Thêm vào danh sách nếu tìm thấy
            if (browserInfo != null && !foundPackageNames.contains(packageName)) {
              _log('✅ Found installed browser: ${browserInfo.name} ($packageName)');
              installedBrowsers.add(browserInfo);
              foundPackageNames.add(packageName);
            }
          }
        } catch (e) {
          _log('❌ Error getting all installed apps: $e');
          _log('   Falling back to individual package check...');
          
          // Cách 2: Fallback - Kiểm tra từng package name
          for (final packageName in _allBrowserPackageNames) {
            try {
              final isInstalled = await _isAppInstalled(packageName);
              if (isInstalled) {
                final browserInfo = BankInfo(
                  bin: null,
                  name: packageName.split('.').last, // Tạm thời dùng package name
                  packageName: packageName,
                  playStoreId: packageName,
                  type: PaymentAppType.browser,
                );
                
                if (!installedBrowsers.any((app) => 
                  app.packageName == browserInfo.packageName)) {
                  _log('✅ Found installed browser (fallback): ${browserInfo.name} ($packageName)');
                  installedBrowsers.add(browserInfo);
                }
              }
            } catch (e) {
              _log('⚠️ Error checking browser $packageName: $e');
            }
          }
        }
      } else {
        _log('⚠️ Platform not supported: Only Android is supported');
      }
    } catch (e, stackTrace) {
      _log('❌ CRITICAL: Error detecting installed browsers: $e');
      _log('   Stack trace: $stackTrace');
    }
    
    // Sắp xếp theo tên
    installedBrowsers.sort((a, b) => a.name.compareTo(b.name));
    
    _log('📊 Final result: Found ${installedBrowsers.length} installed browser apps');
    return installedBrowsers;
  }

  /// [DEPRECATED] Sử dụng detectInstalledPaymentApps thay thế
  @Deprecated('Use detectInstalledPaymentApps instead')
  static Future<List<BankInfo>> detectInstalledBanks() async {
    return detectInstalledPaymentApps();
  }

  /// Kiểm tra xem app có được cài đặt không
  /// Sử dụng device_apps package để kiểm tra chính xác
  static Future<bool> _isAppInstalled(String packageName) async {
    try {
      if (Platform.isAndroid) {
        // Cách 1: Sử dụng device_apps (chính xác nhất)
        try {
          final app = await DeviceApps.getApp(packageName, true);
          if (app != null) {
            _log('✅ App found using device_apps: $packageName (${app.appName})');
            return true;
          } else {
            _log('❌ App not found using device_apps: $packageName');
          }
        } catch (e) {
          // App không tồn tại hoặc không thể truy cập
          _log('⚠️ Error using device_apps for $packageName: $e');
        }
        
        // Cách 2: Fallback - Sử dụng intent URL (không chính xác 100%)
        try {
          final intentUrl = 'intent://#Intent;package=$packageName;end';
          final uri = Uri.parse(intentUrl);
          final canLaunch = await canLaunchUrl(uri);
          if (canLaunch) {
            _log('✅ App found using intent URL: $packageName');
            return true;
          }
        } catch (e) {
          _log('⚠️ Error using intent URL for $packageName: $e');
        }
      }
      
      return false;
    } catch (e) {
      _log('❌ Error checking app $packageName: $e');
      return false;
    }
  }

  /// Kiểm tra xem package name có phải là variant của base package name không
  /// Ví dụ: com.vietinbank.ipay vs com.vietinbank.vpb
  static bool _isPackageNameVariant(String packageName, String basePackageName) {
    // Lấy phần base (2-3 phần đầu) để so sánh
    final packageParts = packageName.split('.');
    final baseParts = basePackageName.split('.');
    
    if (packageParts.length < 2 || baseParts.length < 2) {
      return false;
    }
    
    // So sánh 2 phần đầu (ví dụ: com.vietinbank)
    final packageBase = packageParts.take(2).join('.');
    final basePackageBase = baseParts.take(2).join('.');
    
    if (packageBase == basePackageBase) {
      return true;
    }
    
    // Kiểm tra nếu một trong hai là substring của cái kia
    if (packageName.contains(basePackageName) || basePackageName.contains(packageName)) {
      return true;
    }
    
    return false;
  }

  /// Tìm BIN code từ package name variant
  /// Ví dụ: com.vietinbank.ipay → 970415
  static String? _findBinFromPackageName(String packageName) {
    // Kiểm tra trong package mapping trước
    final packageMapping = <String, String>{
      'com.mbmobile': '970422',
      'vn.com.mbmobile': '970422',
      'com.vietcombank': '970436',
      'com.vpbank.mobile': '970432',
      'com.bidv': '970418',
      'com.vietinbank.vpb': '970415',
      'com.vietinbank.ipay': '970415',
      'com.bidv.smartbanking': '970418',
      'com.vnpay.bidv': '970418',
      'com.agribank.mb': '970405',
      'com.vnpay.Agribank3g': '970405',
    };
    
    // Tìm trực tiếp
    if (packageMapping.containsKey(packageName)) {
      return packageMapping[packageName];
    }
    
    // Tìm theo pattern (ví dụ: package name chứa tên ngân hàng)
    for (final entry in _binToBankInfo.entries) {
      final bankInfo = entry.value;
      final bankNameParts = bankInfo.name.toLowerCase().split(' ');
      
      // Kiểm tra xem package name có chứa keyword của ngân hàng không
      for (final part in bankNameParts) {
        if (part.length > 3 && packageName.contains(part)) {
          return entry.key;
        }
      }
    }
    
    // Tìm theo base package (ví dụ: com.vietinbank.*)
    final packageBase = packageName.split('.').take(2).join('.');
    for (final entry in _binToBankInfo.entries) {
      final bankInfo = entry.value;
      final bankBasePackage = bankInfo.packageName.split('.').take(2).join('.');
      if (packageBase == bankBasePackage) {
        return entry.key;
      }
    }
    
    return null;
  }

  /// Tìm BankInfo theo package name
  static BankInfo? _findBankByPackageName(String packageName) {
    // Tìm trực tiếp
    for (final bankInfo in _binToBankInfo.values) {
      if (bankInfo.packageName == packageName) {
        return bankInfo;
      }
    }
    
    // Mapping thủ công cho các package name variant thường gặp
    final packageMapping = <String, String>{
      'com.mbmobile': '970422', // MB Bank variant
      'vn.com.mbmobile': '970422', // MB Bank variant
      'com.vietcombank': '970436', // Vietcombank variant
      'com.vpbank.mobile': '970432', // VPBank variant
      'com.bidv': '970418', // BIDV variant
      'com.vietinbank.vpb': '970415', // VietinBank variant (cũ)
      'com.vietinbank.ipay': '970415', // VietinBank iPay (package name thực tế)
      'com.bidv.smartbanking': '970418', // BIDV Smart Banking
      'com.vnpay.bidv': '970418', // BIDV package name thực tế
      'com.agribank.mb': '970405', // Agribank variant
      'com.vnpay.Agribank3g': '970405', // Agribank package name thực tế
    };
    
    final bin = packageMapping[packageName];
    if (bin != null) {
      return _binToBankInfo[bin];
    }
    
    // Tìm theo variant (ví dụ: com.vietcombank.mobile vs com.vietcombank)
    final basePackage = packageName.split('.').take(2).join('.');
    for (final bankInfo in _binToBankInfo.values) {
      final bankBasePackage = bankInfo.packageName.split('.').take(2).join('.');
      if (bankBasePackage == basePackage) {
        return bankInfo;
      }
    }
    
    return null;
  }

  /// ============================================
  /// HÀM: Lấy dynamic package name mapping từ SharedPreferences
  /// ============================================
  /// 
  /// Lưu mapping BIN → package name thực tế (từ app đã cài)
  /// Để tự động update khi package name thay đổi
  static Future<Map<String, String>> _getDynamicPackageMapping() async {
    // Nếu đã có cache, trả về cache
    if (_dynamicPackageMappingCache != null) {
      return _dynamicPackageMappingCache!;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingJson = prefs.getString(_dynamicPackageMappingKey);
      
      if (mappingJson != null && mappingJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(mappingJson);
        _dynamicPackageMappingCache = decoded.map((key, value) => MapEntry(key, value.toString()));
        _log('📦 Loaded dynamic package mapping: ${_dynamicPackageMappingCache!.length} entries');
        return _dynamicPackageMappingCache!;
      }
    } catch (e) {
      _log('⚠️ Error loading dynamic package mapping: $e');
    }
    
    _dynamicPackageMappingCache = <String, String>{};
    return _dynamicPackageMappingCache!;
  }

  /// ============================================
  /// HÀM: Lưu dynamic package name mapping vào SharedPreferences
  /// ============================================
  /// 
  /// Lưu mapping BIN → package name thực tế để persist giữa các lần chạy app
  static Future<void> _saveDynamicPackageMapping(Map<String, String> mapping) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingJson = jsonEncode(mapping);
      await prefs.setString(_dynamicPackageMappingKey, mappingJson);
      _dynamicPackageMappingCache = mapping; // Update cache
      _log('💾 Saved dynamic package mapping: ${mapping.length} entries');
    } catch (e) {
      _log('⚠️ Error saving dynamic package mapping: $e');
    }
  }

  /// ============================================
  /// HÀM: Update package name cho BIN nếu phát hiện thay đổi
  /// ============================================
  /// 
  /// So sánh package name thực tế với package name trong code
  /// Nếu khác nhau → tự động update và lưu vào SharedPreferences
  static Future<void> _updatePackageNameIfChanged(String bin, String actualPackageName) async {
    try {
      final baseBankInfo = _binToBankInfo[bin];
      if (baseBankInfo == null) return;
      
      final codePackageName = baseBankInfo.packageName;
      
      // Nếu package name thực tế khác với package name trong code
      if (actualPackageName != codePackageName) {
        _log('🔄 Package name changed detected for BIN $bin:');
        _log('   Code: $codePackageName');
        _log('   Actual: $actualPackageName');
        
        // Lưu vào dynamic mapping
        final dynamicMapping = await _getDynamicPackageMapping();
        dynamicMapping[bin] = actualPackageName;
        await _saveDynamicPackageMapping(dynamicMapping);
        
        _log('✅ Auto-updated package name mapping for BIN $bin');
      }
    } catch (e) {
      _log('⚠️ Error updating package name: $e');
    }
  }

  /// Lấy thông tin ngân hàng từ BIN
  /// Ưu tiên package name từ dynamic mapping (nếu có) thay vì từ code
  static Future<BankInfo?> getBankInfo(String? bin) async {
    if (bin == null) return null;
    
    final baseBankInfo = _binToBankInfo[bin];
    if (baseBankInfo == null) return null;
    
    // Kiểm tra xem có dynamic package name không (từ SharedPreferences)
    try {
      final dynamicMapping = await _getDynamicPackageMapping();
      final dynamicPackageName = dynamicMapping[bin];
      
      if (dynamicPackageName != null && dynamicPackageName != baseBankInfo.packageName) {
        // Có package name mới từ dynamic mapping → dùng nó
        _log('📦 Using dynamic package name for BIN $bin: $dynamicPackageName (instead of ${baseBankInfo.packageName})');
        return BankInfo(
          bin: bin,
          name: baseBankInfo.name,
          packageName: dynamicPackageName, // ✅ Dùng package name từ dynamic mapping
          playStoreId: dynamicPackageName,
          type: baseBankInfo.type,
        );
      }
    } catch (e) {
      _log('⚠️ Error getting dynamic package name: $e');
    }
    
    // Không có dynamic mapping → dùng từ code
    return baseBankInfo;
  }
  
  /// [DEPRECATED] Sử dụng getBankInfo async thay thế
  @Deprecated('Use getBankInfo async instead')
  static BankInfo? getBankInfoSync(String? bin) {
    if (bin == null) return null;
    return _binToBankInfo[bin];
  }

  /// Lấy tên ngân hàng từ BIN
  static String? getBankName(String? bin) {
    if (bin == null) return null;
    return _binToBankInfo[bin]?.name;
  }

  /// Lấy danh sách tất cả ngân hàng được hỗ trợ
  static List<BankInfo> getAllSupportedBanks() {
    return _binToBankInfo.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// [DEPRECATED] Sử dụng identifyAndParseQR thay thế
  @Deprecated('Use identifyAndParseQR instead')
  static BankQRData? parseQR(String qrCode) {
    final result = identifyAndParseQR(qrCode);
    return result.bankData;
  }

  /// [DEPRECATED] Sử dụng detectInstalledPaymentApps thay thế
  @Deprecated('Use detectInstalledPaymentApps instead')
  static Future<List<BankInfo>> getInstalledBanks() {
    return detectInstalledPaymentApps();
  }
}

/// Helper class để mở app ngân hàng bằng package name (Android Intent URL)
class BankAppLauncher {
  static const MethodChannel _channel = MethodChannel('com.qhome.resident/app_launcher');
  
  /// Mở app ngân hàng bằng package name
  /// Sử dụng Platform Channel để gọi Android API trực tiếp (đáng tin cậy hơn intent URL)
  /// Fallback: Mở Google Play Store nếu app chưa cài
  static Future<bool> openBankApp(String packageName, {String? playStoreId}) async {
    _log('🚀 Attempting to open bank app: $packageName');
    
    try {
      if (Platform.isAndroid) {
        // Cách 1: Thử dùng Platform Channel (chính xác nhất)
        try {
          final result = await _channel.invokeMethod<bool>('launchApp', {'packageName': packageName});
          if (result == true) {
            _log('✅ Successfully opened bank app using platform channel');
            return true;
          } else {
            _log('⚠️ Platform channel returned false, trying intent URL...');
          }
        } on PlatformException catch (e) {
          _log('⚠️ Platform channel error: ${e.code} - ${e.message}');
          // Tiếp tục thử cách khác
        } catch (e) {
          _log('⚠️ Error using platform channel: $e');
          // Tiếp tục thử cách khác
        }
        
        // Cách 2: Fallback - Thử dùng Intent URL (có thể không hoạt động)
        try {
          final intentUrl = 'intent://#Intent;package=$packageName;end';
          final uri = Uri.parse(intentUrl);
          _log('   Trying intent URL: $intentUrl');
          
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          
          if (launched) {
            _log('✅ Successfully opened bank app using intent URL');
            return true;
          } else {
            _log('⚠️ Intent URL returned false');
          }
        } on PlatformException catch (e) {
          _log('⚠️ Intent URL PlatformException: ${e.code} - ${e.message}');
        } catch (e) {
          _log('⚠️ Intent URL error: $e');
        }
        
        // Cách 3: Fallback cuối cùng - Mở Google Play Store
        _log('   All methods failed, opening Play Store...');
        return await _openPlayStore(playStoreId ?? packageName);
      } else if (Platform.isIOS) {
        // iOS: Thử mở bằng custom URL scheme (nếu có)
        _log('   iOS platform detected');
        // TODO: Implement iOS app opening logic
        return false;
      } else {
        _log('   Unsupported platform');
        return false;
      }
    } catch (e, stackTrace) {
      _log('❌ CRITICAL: Error opening bank app: $e');
      _log('   Stack trace: $stackTrace');
      return false;
    }
  }

  /// Mở Google Play Store để cài đặt app ngân hàng
  static Future<bool> _openPlayStore(String packageId) async {
    _log('📱 Opening Google Play Store for package: $packageId');
    
    try {
      final playStoreUrl = 'https://play.google.com/store/apps/details?id=$packageId';
      final uri = Uri.parse(playStoreUrl);
      
      _log('   Play Store URL: $playStoreUrl');
      
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _log('✅ Successfully opened Google Play Store');
        return true;
      } else {
        _log('❌ Cannot open Google Play Store');
        return false;
      }
    } catch (e, stackTrace) {
      _log('❌ Error opening Play Store: $e');
      _log('   Stack trace: $stackTrace');
      return false;
    }
  }
}
