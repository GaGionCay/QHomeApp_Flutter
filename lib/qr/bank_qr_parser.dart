import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';

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
    _log('📄 QR code preview: ${qrCode.length > 100 ? '${qrCode.substring(0, 100)}...' : qrCode}');

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


  static BankInfo? getBankInfo(String? bin) {
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

}
