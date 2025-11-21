import 'dart:developer' as dev;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:device_apps/device_apps.dart';
import 'package:flutter/services.dart' show PlatformException, MethodChannel;
import 'package:shared_preferences/shared_preferences.dart';

void _log(String message) {
  dev.log(message);
  if (kDebugMode) {
    print('Flutter QR Scanner: $message');
  }
}

enum QRType {
  url,
  bankQr,
  unknown,
}

class QRScanResult {
  final QRType type;
  final String originalCode;
  final BankQRData? bankData;
  final Uri? url;

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

class BankQRData {
  final String? bin;
  final String? accountNumber;
  final String? bankName;
  final double? amount;
  final String? addInfo;
  final String? serviceCode;
  final String? merchantCode;
  final String? merchantName;
  final String? transactionCurrency;
  final String? countryCode;
  final String? qrType;
  final String? originalCode;
  final Map<String, String>? additionalData;

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

  bool get isDynamic => amount != null && amount! > 0;

  bool get isValid => bin != null && accountNumber != null;

  @override
  String toString() {
    return 'BankQRData(bin: $bin, account: $accountNumber, bank: $bankName, amount: $amount, addInfo: $addInfo)';
  }
}

class BankInfo {
  final String? bin;
  final String name;
  final String packageName;
  final String? playStoreId;
  final PaymentAppType type;

  const BankInfo({
    this.bin,
    required this.name,
    required this.packageName,
    this.playStoreId,
    this.type = PaymentAppType.bank,
  });

  bool get isBank => type == PaymentAppType.bank && bin != null;

  bool get isPaymentApp => type == PaymentAppType.payment;
  
  bool get isBrowser => type == PaymentAppType.browser;
}

enum PaymentAppType {
  bank,
  payment,
  browser,
}

class BankQRParser {
  static const List<String> _bankPackageNames = [
    'com.vietcombank.mobile',
    'com.mbmobile',
    'com.tpb.mobile',
    'com.techcombank',
    'com.sacombank',
    'com.bidv.smartbanking',
    'com.bidv',
    'com.vnpay.bidv',
    'com.vpbank.online',
    
    'com.vietcombank',
    'vn.com.mbmobile',
    'com.tpb.mb.gprsandroid',
    'com.vietinbank.vpb',
    'com.vietinbank.ipay',
    'com.agribank.mb',
    'com.vnpay.Agribank3g',
    'com.acb.fastbank',
    'com.vpbank.mobile',
    'com.shb.mobilebanking',
    'com.hsbc.hsbcvietnam',
    'com.vietbank.mobilebanking',
    'com.namabank.mobile',
    'com.eximbank.mobile',
    'com.ocb.omni',
    'com.scb.digital',
    'com.dongabank.mobile',
    'com.pvcombank.mobile',
    'com.publicbank.mobile',
    'com.ncb.mobile',
  ];

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

  static List<String> get _allPackageNames => [
    ..._bankPackageNames,
    ..._paymentApps.keys,
    ..._browserPackageNames,
  ];
  
  static List<String> get _allBrowserPackageNames => _browserPackageNames;

  static const String _dynamicPackageMappingKey = 'bank_qr_dynamic_package_mapping';
  
  static Map<String, String>? _dynamicPackageMappingCache;

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
      packageName: 'com.vietinbank.ipay',
      playStoreId: 'com.vietinbank.ipay',
    ),
    '970418': BankInfo(
      bin: '970418',
      name: 'BIDV',
      packageName: 'com.vnpay.bidv',
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
      packageName: 'com.mbmobile',
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

  static BankQRData? _parseBankQR(String qrCode) {
    try {
      final vietQRUrlInfo = _parseVietQRUrl(qrCode);
      if (vietQRUrlInfo != null) {
        _log('   ✅ Parsed as VietQR URL');
        return vietQRUrlInfo;
      }

      final vietQRDeepLinkInfo = _parseVietQRDeepLink(qrCode);
      if (vietQRDeepLinkInfo != null) {
        _log('   ✅ Parsed as VietQR deep link');
        return vietQRDeepLinkInfo;
      }

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

  static BankQRData? _parseEMVCoTLV(String qrCode) {
    try {
      if (!qrCode.startsWith('000201')) {
        return null;
      }

      _log('   Attempting to parse as EMVCo TLV...');
      
      final data = <String, String>{};
      int i = 6;
      int tagCount = 0;

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

        if (tag == '62' || tag == '26' || tag == '38') {
          try {
            Map<String, String> nested;
            
            if (tag == '38' && value.length > 10) {
              String nestedData;
              if (value.startsWith('0010') && value.length > 14) {
                nestedData = value.substring(14);
              } else if (value.length > 10) {
                nestedData = value.substring(10);
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

      String? bin;
      String? accountNumber;
      
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
              bin ??= potentialBin;
              if ((accountNumber == null || accountNumber.isEmpty) && tag26.length > binStart + 6) {
                accountNumber = tag26.substring(binStart + 6);
              }
            }
          }
        }
      }

      if (accountNumber == null || accountNumber.isEmpty) {
        if (data.containsKey('62')) {
          accountNumber = _extractAccountFrom62(data['62']!);
        }
        if (accountNumber == null || accountNumber.isEmpty) {
          accountNumber = _extractAccountNumber(data);
        }
      }
      
      if (bin == null) {
        final binPattern = RegExp(r'970\d{3}');
        final binMatch = binPattern.firstMatch(qrCode);
        if (binMatch != null) {
          bin = binMatch.group(0);
        }
      }

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

  static String? _extractAccountFrom62(String tag62) {
    try {
      final nested = _parseNestedTLV(tag62);
      return nested['01'];
    } catch (e) {
      return null;
    }
  }

  static const List<String> _bankingKeywords = [
    'bank', 'banking', 'ngân hàng', 'vietcombank', 'vietinbank', 'bidv', 
    'techcombank', 'acb', 'agribank', 'sacombank', 'vpbank', 'tpbank', 
    'mb bank', 'mbbank', 'vietbank', 'hsbc', 'shb', 'nam a bank', 
    'eximbank', 'ocb', 'scb', 'dong a', 'pvcombank', 'publicbank', 'ncb',
    'vcb', 'vib', 'tcb', 'sgb', 'abb', 'abbank', 'abbank mobile',
    'pvfc', 'pvfcbank', 'lienvietpostbank', 'lpbank', 'postbank',
    'seabank', 'vietbank', 'baoviet', 'vietcapital', 'vietcombank',
    'savings', 'deposit', 'credit', 'finance', 'financial', 'ebank',
    'mobilebank', 'mobile bank', 'smartbank', 'smart bank', 'digital bank',
    'app ngân hàng', 'ngân hàng điện tử', 'ngân hàng số', 'mobile banking',
  ];
  
  static const List<String> _excludeKeywords = [
    'keyboard', 'bàn phím', 'inputmethod', 'ime', 'gboard', 'swiftkey',
    'labankey', 'vietkey', 'unikey', 'key', 'typing', 'input',
  ];
  
  static const List<String> _paymentKeywords = [
    'momo', 'zalopay', 'zalo pay', 'shopeepay', 'shopee pay', 
    'viettelpay', 'vnpay', 'pay', 'wallet', 'ví', 'thanh toán',
  ];
  
  static const List<String> _browserPackageNames = [
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
  
  static const List<String> _browserKeywords = [
    'browser', 'chrome', 'firefox', 'edge', 'opera', 'safari',
    'brave', 'vivaldi', 'duckduckgo', 'tor', 'tor browser',
    
    'trình duyệt', 'webview', 'internet', 'explorer', 'navigator', 'web',
    
    'sbrowser', 'mi browser', 'samsung internet', 'huawei browser', 
    'uc browser', 'qq browser', 'yandex', 'baidu',
    
    'surf', 'navigate', 'view', 'link', 'url', 'html', 'http', 'https',
    'www', 'domain', 'site', 'page', 'tab', 'bookmark', 'history',
    'adblock', 'privacy', 'incognito', 'private', 'secure',
  ];

  static Future<List<BankInfo>> detectInstalledPaymentApps() async {
    _log('🔍 Starting to detect installed payment/banking apps (scanning all installed apps)...');
    
    final installedApps = <BankInfo>[];
    final allPackageNamesSet = _allPackageNames.toSet();
    final foundPackageNames = <String>{};
    
    try {
      if (Platform.isAndroid) {
        try {
          _log('📱 Getting all installed applications...');
          final allApps = await DeviceApps.getInstalledApplications(
            includeAppIcons: false,
            includeSystemApps: false,
            onlyAppsWithLaunchIntent: true,
          );
          
          _log('📊 Found ${allApps.length} total installed apps');
          
          for (final app in allApps) {
            final packageName = app.packageName;
            final appName = app.appName.toLowerCase();
            
            BankInfo? appInfo;
            
            if (allPackageNamesSet.contains(packageName)) {
              try {
                if (_paymentApps.containsKey(packageName)) {
                  appInfo = _paymentApps[packageName];
                } else {
                  appInfo = _findBankByPackageName(packageName);
                }
              } catch (e) {
                _log('⚠️ Error processing known app $packageName: $e');
              }
            }
            
            if (appInfo == null) {
              final isExcluded = _excludeKeywords.any((keyword) =>
                appName.contains(keyword.toLowerCase()) ||
                packageName.contains(keyword.toLowerCase()));
              
              if (isExcluded) {
                continue;
              }
              
              final isBankingApp = _bankingKeywords.any((keyword) => 
                appName.contains(keyword.toLowerCase()) || 
                packageName.contains(keyword.toLowerCase()));
              
              final isPaymentApp = _paymentKeywords.any((keyword) => 
                appName.contains(keyword.toLowerCase()) || 
                packageName.contains(keyword.toLowerCase()));
              
              if (isBankingApp || isPaymentApp) {
                final displayName = app.appName;
                final appType = isPaymentApp ? PaymentAppType.payment : PaymentAppType.bank;
                
                String? bin;
                if (isBankingApp) {
                  for (final entry in _binToBankInfo.entries) {
                    final bankInfo = entry.value;
                    final bankNameLower = bankInfo.name.toLowerCase();
                    
                    if (appName.contains(bankNameLower) || 
                        bankNameLower.contains(appName) ||
                        packageName.contains(bankNameLower.replaceAll(' ', '').replaceAll('bank', ''))) {
                      bin = entry.key;
                      
                      appInfo = BankInfo(
                        bin: bin,
                        name: bankInfo.name,
                        packageName: packageName,
                        playStoreId: packageName,
                        type: appType,
                      );
                      
                      _log('🔄 Auto-updated package name for ${bankInfo.name}: ${bankInfo.packageName} → $packageName');
                      
                      _updatePackageNameIfChanged(bin, packageName);
                      
                      break;
                    }
                    
                    final bankPackageLower = bankInfo.packageName.toLowerCase();
                    final packageNameLower = packageName.toLowerCase();
                    
                    if (packageNameLower == bankPackageLower ||
                        packageNameLower.startsWith(bankPackageLower + '.') ||
                        bankPackageLower.startsWith(packageNameLower + '.')) {
                      bin = entry.key;
                      
                      appInfo = BankInfo(
                        bin: bin,
                        name: bankInfo.name,
                        packageName: packageName,
                        playStoreId: packageName,
                        type: appType,
                      );
                      
                      _log('🔄 Auto-updated package name via pattern matching for ${bankInfo.name}: ${bankInfo.packageName} → $packageName');
                      
                      _updatePackageNameIfChanged(bin, packageName);
                      
                      break;
                    }
                    
                    if (_isPackageNameVariant(packageName, bankInfo.packageName) &&
                        !_isExcludedPackage(packageName, bankInfo.name)) {
                      bin = entry.key;
                      
                      appInfo = BankInfo(
                        bin: bin,
                        name: bankInfo.name,
                        packageName: packageName,
                        playStoreId: packageName,
                        type: appType,
                      );
                      
                      _log('🔄 Auto-updated package name via package variant for ${bankInfo.name}: ${bankInfo.packageName} → $packageName');
                      
                      _updatePackageNameIfChanged(bin, packageName);
                      
                      break;
                    }
                  }
                  
                  if (appInfo == null && bin == null) {
                    final foundBin = _findBinFromPackageName(packageName);
                    if (foundBin != null) {
                      bin = foundBin;
                      final baseBankInfo = _binToBankInfo[bin];
                      if (baseBankInfo != null) {
                        appInfo = BankInfo(
                          bin: bin,
                          name: baseBankInfo.name,
                          packageName: packageName,
                          playStoreId: packageName,
                          type: appType,
                        );
                        _log('🔄 Auto-updated package name via package variant for ${baseBankInfo.name}: ${baseBankInfo.packageName} → $packageName');
                        
                        _updatePackageNameIfChanged(bin, packageName);
                      }
                    }
                  }
                  
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
            
            if (appInfo != null && !foundPackageNames.contains(packageName)) {
              _log('✅ Found installed: ${appInfo.name} ($packageName) - ${appInfo.type.name}');
              installedApps.add(appInfo);
              foundPackageNames.add(packageName);
            }
          }
        } catch (e) {
          _log('❌ Error getting all installed apps: $e');
          _log('   Falling back to individual package check...');
          
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
    
    installedApps.sort((a, b) {
      if (a.type != b.type) {
        return a.type == PaymentAppType.payment ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    
    _log('📊 Final result: Found ${installedApps.length} installed payment/banking apps');
    return installedApps;
  }

  static Future<List<BankInfo>> detectInstalledBrowserApps() async {
    _log('🌐 Starting to detect installed browser apps (scanning all installed apps)...');
    
    final installedBrowsers = <BankInfo>[];
    final browserPackageNamesSet = _allBrowserPackageNames.toSet();
    final foundPackageNames = <String>{};
    
    try {
      if (Platform.isAndroid) {
        try {
          _log('📱 Getting all installed applications...');
          final allApps = await DeviceApps.getInstalledApplications(
            includeAppIcons: false,
            includeSystemApps: false,
            onlyAppsWithLaunchIntent: true,
          );
          
          _log('📊 Found ${allApps.length} total installed apps');
          
          for (final app in allApps) {
            final packageName = app.packageName;
            final appName = app.appName.toLowerCase();
            
            BankInfo? browserInfo;
            
            if (browserPackageNamesSet.contains(packageName)) {
              try {
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
            
            if (browserInfo == null) {
              final isBrowserApp = _browserKeywords.any((keyword) => 
                appName.contains(keyword.toLowerCase()) || 
                packageName.contains(keyword.toLowerCase()));
              
              if (isBrowserApp) {
                browserInfo = BankInfo(
                  bin: null,
                  name: app.appName,
                  packageName: packageName,
                  playStoreId: packageName,
                  type: PaymentAppType.browser,
                );
                
                _log('🔍 Auto-detected browser app: ${app.appName} ($packageName)');
                _log('   ✅ Auto-added package name to system: $packageName');
              }
            }
            
            if (browserInfo == null) {
              final browserPatterns = [
                'browser', 'chrome', 'firefox', 'edge', 'opera', 'safari',
                'webview', 'web', 'internet', 'explorer', 'navigator',
                'surf', 'navigate', 'view', 'link', 'url', 'html', 'http',
                'www', 'domain', 'site', 'page', 'tab', 'adblock', 'privacy',
              ];
              
              final packageNameLower = packageName.toLowerCase();
              final hasBrowserPattern = browserPatterns.any((pattern) {
                final patternLower = pattern.toLowerCase();
                if (packageNameLower.contains(patternLower)) {
                  if (patternLower == 'web') {
                    return packageNameLower.contains('browser') ||
                           packageNameLower.contains('webview') ||
                           packageNameLower.contains('website') ||
                           packageNameLower.contains('webapp');
                  }
                  return true;
                }
                return appName.contains(patternLower);
              });
              
              if (hasBrowserPattern) {
                browserInfo = BankInfo(
                  bin: null,
                  name: app.appName,
                  packageName: packageName,
                  playStoreId: packageName,
                  type: PaymentAppType.browser,
                );
                
                _log('🔍 Auto-detected browser app via pattern: ${app.appName} ($packageName)');
                _log('   ✅ Auto-added package name to system: $packageName');
              }
            }
            
            if (browserInfo != null && !foundPackageNames.contains(packageName)) {
              _log('✅ Found installed browser: ${browserInfo.name} ($packageName)');
              installedBrowsers.add(browserInfo);
              foundPackageNames.add(packageName);
            }
          }
        } catch (e) {
          _log('❌ Error getting all installed apps: $e');
          _log('   Falling back to individual package check...');
          
          for (final packageName in _allBrowserPackageNames) {
            try {
              final isInstalled = await _isAppInstalled(packageName);
              if (isInstalled) {
                final browserInfo = BankInfo(
                  bin: null,
                  name: packageName.split('.').last,
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
    
    installedBrowsers.sort((a, b) => a.name.compareTo(b.name));
    
    _log('📊 Final result: Found ${installedBrowsers.length} installed browser apps');
    return installedBrowsers;
  }

  @Deprecated('Use detectInstalledPaymentApps instead')
  static Future<List<BankInfo>> detectInstalledBanks() async {
    return detectInstalledPaymentApps();
  }

  static Future<bool> _isAppInstalled(String packageName) async {
    try {
      if (Platform.isAndroid) {
        try {
          final app = await DeviceApps.getApp(packageName, true);
          if (app != null) {
            _log('✅ App found using device_apps: $packageName (${app.appName})');
            return true;
          } else {
            _log('❌ App not found using device_apps: $packageName');
          }
        } catch (e) {
          _log('⚠️ Error using device_apps for $packageName: $e');
        }
        
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

  static bool _isPackageNameVariant(String packageName, String basePackageName) {
    final packageParts = packageName.split('.');
    final baseParts = basePackageName.split('.');
    
    if (packageParts.length < 3 || baseParts.length < 3) {
      return false;
    }
    
    final packageBase = packageParts.take(3).join('.');
    final basePackageBase = baseParts.take(3).join('.');
    
    if (packageBase == basePackageBase) {
      return true;
    }
    
    final packageDomain = packageParts.take(2).join('.');
    final baseDomain = baseParts.take(2).join('.');
    
    if (packageDomain == baseDomain && 
        packageParts.length >= 3 && baseParts.length >= 3) {
      final packageThird = packageParts[2].toLowerCase();
      final baseThird = baseParts[2].toLowerCase();
      
      if (packageThird == baseThird || 
          packageThird.contains(baseThird) || 
          baseThird.contains(packageThird)) {
        return true;
      }
    }
    
    return false;
  }
  
  static bool _isExcludedPackage(String packageName, String bankName) {
    final packageLower = packageName.toLowerCase();
    final bankNameLower = bankName.toLowerCase();
    
    final exclusionRules = [
      packageLower.contains('vpbank') && !bankNameLower.contains('vpbank'),
      packageLower.contains('vpbankonline') && bankNameLower.contains('bidv'),
      packageLower.contains('vietinbank') && bankNameLower.contains('vietcombank'),
      packageLower.contains('techcombank') && bankNameLower.contains('acb'),
    ];
    
    return exclusionRules.any((rule) => rule == true);
  }

  static String? _findBinFromPackageName(String packageName) {
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
    
    if (packageMapping.containsKey(packageName)) {
      return packageMapping[packageName];
    }
    
    for (final entry in _binToBankInfo.entries) {
      final bankInfo = entry.value;
      final bankNameParts = bankInfo.name.toLowerCase().split(' ');
      
      for (final part in bankNameParts) {
        if (part.length > 3 && packageName.contains(part)) {
          return entry.key;
        }
      }
    }
    
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

  static BankInfo? _findBankByPackageName(String packageName) {
    for (final bankInfo in _binToBankInfo.values) {
      if (bankInfo.packageName == packageName) {
        return bankInfo;
      }
    }
    
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
    
    final bin = packageMapping[packageName];
    if (bin != null) {
      return _binToBankInfo[bin];
    }
    
    final basePackage = packageName.split('.').take(2).join('.');
    for (final bankInfo in _binToBankInfo.values) {
      final bankBasePackage = bankInfo.packageName.split('.').take(2).join('.');
      if (bankBasePackage == basePackage) {
        return bankInfo;
      }
    }
    
    return null;
  }

  static Future<Map<String, String>> _getDynamicPackageMapping() async {
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

  static Future<void> _saveDynamicPackageMapping(Map<String, String> mapping) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingJson = jsonEncode(mapping);
      await prefs.setString(_dynamicPackageMappingKey, mappingJson);
      _dynamicPackageMappingCache = mapping;
      _log('💾 Saved dynamic package mapping: ${mapping.length} entries');
    } catch (e) {
      _log('⚠️ Error saving dynamic package mapping: $e');
    }
  }

  static Future<void> _updatePackageNameIfChanged(String bin, String actualPackageName) async {
    try {
      final baseBankInfo = _binToBankInfo[bin];
      if (baseBankInfo == null) return;
      
      final codePackageName = baseBankInfo.packageName;
      
      if (actualPackageName != codePackageName) {
        _log('🔄 Package name changed detected for BIN $bin:');
        _log('   Code: $codePackageName');
        _log('   Actual: $actualPackageName');
        
        final dynamicMapping = await _getDynamicPackageMapping();
        dynamicMapping[bin] = actualPackageName;
        await _saveDynamicPackageMapping(dynamicMapping);
        
        _log('✅ Auto-updated package name mapping for BIN $bin');
      }
    } catch (e) {
      _log('⚠️ Error updating package name: $e');
    }
  }

  static Future<BankInfo?> getBankInfo(String? bin) async {
    if (bin == null) return null;
    
    final baseBankInfo = _binToBankInfo[bin];
    if (baseBankInfo == null) return null;
    
    try {
      final dynamicMapping = await _getDynamicPackageMapping();
      final dynamicPackageName = dynamicMapping[bin];
      
      if (dynamicPackageName != null && dynamicPackageName != baseBankInfo.packageName) {
        _log('📦 Using dynamic package name for BIN $bin: $dynamicPackageName (instead of ${baseBankInfo.packageName})');
        return BankInfo(
          bin: bin,
          name: baseBankInfo.name,
          packageName: dynamicPackageName,
          playStoreId: dynamicPackageName,
          type: baseBankInfo.type,
        );
      }
    } catch (e) {
      _log('⚠️ Error getting dynamic package name: $e');
    }
    
    return baseBankInfo;
  }
  
  @Deprecated('Use getBankInfo async instead')
  static BankInfo? getBankInfoSync(String? bin) {
    if (bin == null) return null;
    return _binToBankInfo[bin];
  }

  static String? getBankName(String? bin) {
    if (bin == null) return null;
    return _binToBankInfo[bin]?.name;
  }

  static List<BankInfo> getAllSupportedBanks() {
    return _binToBankInfo.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @Deprecated('Use identifyAndParseQR instead')
  static BankQRData? parseQR(String qrCode) {
    final result = identifyAndParseQR(qrCode);
    return result.bankData;
  }

  @Deprecated('Use detectInstalledPaymentApps instead')
  static Future<List<BankInfo>> getInstalledBanks() {
    return detectInstalledPaymentApps();
  }
}

class BankAppLauncher {
  static const MethodChannel _channel = MethodChannel('com.qhome.resident/app_launcher');
  
  
  static Future<bool> openBankApp(
    String packageName, {
    String? playStoreId,
    BankQRData? bankQRData,
    String? qrCodeString,
  }) async {
    _log('🚀 Attempting to open bank app: $packageName');
    if (bankQRData != null) {
      _log('   With QR data: BIN=${bankQRData.bin}, Account=${bankQRData.accountNumber}, Amount=${bankQRData.amount}');
    }
    
    try {
      if (Platform.isAndroid) {
        try {
          final Map<String, dynamic> arguments = {
            'packageName': packageName,
          };
          
          if (qrCodeString != null) {
            arguments['qrCode'] = qrCodeString;
          }
          
          if (bankQRData != null) {
            arguments['qrData'] = {
              'bin': bankQRData.bin,
              'accountNumber': bankQRData.accountNumber,
              'amount': bankQRData.amount?.toString(),
              'addInfo': bankQRData.addInfo,
              'bankName': bankQRData.bankName,
            };
          }
          
          final result = await _channel.invokeMethod<bool>('launchAppWithQR', arguments);
          if (result == true) {
            _log('✅ Successfully opened bank app with QR data using platform channel');
            return true;
          } else {
            _log('⚠️ Platform channel returned false, trying without QR data...');
          }
        } on PlatformException catch (e) {
          _log('⚠️ Platform channel error: ${e.code} - ${e.message}');
        } catch (e) {
          _log('⚠️ Error using platform channel: $e');
        }
        
        try {
          final result = await _channel.invokeMethod<bool>('launchApp', {'packageName': packageName});
          if (result == true) {
            _log('✅ Successfully opened bank app using platform channel');
            
            if (qrCodeString != null) {
              try {
                await _copyQRToClipboard(qrCodeString);
                _log('✅ Copied QR code to clipboard');
              } catch (e) {
                _log('⚠️ Error copying QR to clipboard: $e');
              }
            }
            
            return true;
          } else {
            _log('⚠️ Platform channel returned false, trying intent URL...');
          }
        } on PlatformException catch (e) {
          _log('⚠️ Platform channel error: ${e.code} - ${e.message}');
        } catch (e) {
          _log('⚠️ Error using platform channel: $e');
        }
        
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
            
            if (qrCodeString != null) {
              try {
                await _copyQRToClipboard(qrCodeString);
                _log('✅ Copied QR code to clipboard');
              } catch (e) {
                _log('⚠️ Error copying QR to clipboard: $e');
              }
            }
            
            return true;
          } else {
            _log('⚠️ Intent URL returned false');
          }
        } on PlatformException catch (e) {
          _log('⚠️ Intent URL PlatformException: ${e.code} - ${e.message}');
        } catch (e) {
          _log('⚠️ Intent URL error: $e');
        }
        
        _log('   All methods failed, opening Play Store...');
        return await _openPlayStore(playStoreId ?? packageName);
      } else if (Platform.isIOS) {
        _log('   iOS platform detected');
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
  
  static Future<void> _copyQRToClipboard(String qrCode) async {
    try {
      await _channel.invokeMethod('copyToClipboard', {'text': qrCode});
    } catch (e) {
      _log('⚠️ Error copying to clipboard: $e');
      rethrow;
    }
  }

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
