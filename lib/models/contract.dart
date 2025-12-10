import 'package:intl/intl.dart';

class ContractDto {
  final String id;
  final String unitId;
  final String contractNumber;
  final String contractType;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? monthlyRent;
  final double? purchasePrice;
  final String? paymentMethod;
  final String? paymentTerms;
  final DateTime? purchaseDate;
  final String? notes;
  final String status;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? updatedBy;
  final DateTime? renewalReminderSentAt;
  final DateTime? renewalDeclinedAt;
  final String? renewalStatus; // PENDING, REMINDED, DECLINED
  final int? reminderCount; // 1, 2, or 3
  final bool? isFinalReminder; // true if reminderCount == 3
  final bool? needsRenewal; // true if contract is within 1 month before expiration (28-32 days, same as reminder 1)
  final double? totalRent; // Calculated total rent
  final String? renewedContractId; // ID of the new contract created when this contract is renewed successfully
  final List<ContractFileDto> files;

  ContractDto({
    required this.id,
    required this.unitId,
    required this.contractNumber,
    required this.contractType,
    required this.status,
    required this.createdBy,
    this.startDate,
    this.endDate,
    this.monthlyRent,
    this.purchasePrice,
    this.paymentMethod,
    this.paymentTerms,
    this.purchaseDate,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.updatedBy,
    this.renewalReminderSentAt,
    this.renewalDeclinedAt,
    this.renewalStatus,
    this.reminderCount,
    this.isFinalReminder,
    this.needsRenewal,
    this.totalRent,
    this.renewedContractId,
    this.files = const [],
  });

  factory ContractDto.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      try {
        return DateTime.parse(value.toString());
      } catch (_) {
        return null;
      }
    }

    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    List<ContractFileDto> parseFiles(dynamic value) {
      if (value is List) {
        return value
            .map((item) => ContractFileDto.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
      }
      return [];
    }

    return ContractDto(
      id: json['id']?.toString() ?? '',
      unitId: json['unitId']?.toString() ?? '',
      contractNumber: json['contractNumber']?.toString() ?? 'Không rõ',
      contractType: json['contractType']?.toString() ?? 'UNKNOWN',
      status: json['status']?.toString() ?? 'UNKNOWN',
      createdBy: json['createdBy']?.toString() ?? '',
      startDate: parseDate(json['startDate']),
      endDate: parseDate(json['endDate']),
      monthlyRent: parseDouble(json['monthlyRent']),
      purchasePrice: parseDouble(json['purchasePrice']),
      paymentMethod: json['paymentMethod']?.toString(),
      paymentTerms: json['paymentTerms']?.toString(),
      purchaseDate: parseDate(json['purchaseDate']),
      notes: json['notes']?.toString(),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      updatedBy: json['updatedBy']?.toString(),
      renewalReminderSentAt: parseDate(json['renewalReminderSentAt']),
      renewalDeclinedAt: parseDate(json['renewalDeclinedAt']),
      renewalStatus: json['renewalStatus']?.toString(),
      reminderCount: json['reminderCount'] is int
          ? json['reminderCount'] as int
          : int.tryParse(json['reminderCount']?.toString() ?? ''),
      isFinalReminder: json['isFinalReminder'] == true,
      needsRenewal: json['needsRenewal'] == true,
      totalRent: parseDouble(json['totalRent']),
      renewedContractId: json['renewedContractId']?.toString(),
      files: parseFiles(json['files']),
    );
  }

  bool get needsRenewalReminder => renewalStatus == 'REMINDED' && status == 'ACTIVE';
  bool get isRental => contractType == 'RENTAL';

  String get formattedStartDate {
    final date = startDate;
    if (date == null) return 'Chưa xác định';
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String get formattedEndDate {
    final date = endDate;
    if (date == null) return 'Không xác định';
    return DateFormat('dd/MM/yyyy').format(date);
  }
}

class ContractFileDto {
  final String id;
  final String contractId;
  final String fileName;
  final String originalFileName;
  final String fileUrl;
  final String contentType;
  final int? fileSize;
  final bool isPrimary;
  final int? displayOrder;
  final String uploadedBy;
  final DateTime? uploadedAt;

  ContractFileDto({
    required this.id,
    required this.contractId,
    required this.fileName,
    required this.originalFileName,
    required this.fileUrl,
    required this.contentType,
    required this.isPrimary,
    required this.uploadedBy,
    this.fileSize,
    this.displayOrder,
    this.uploadedAt,
  });

  factory ContractFileDto.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      try {
        return DateTime.parse(value.toString());
      } catch (_) {
        return null;
      }
    }

    return ContractFileDto(
      id: json['id']?.toString() ?? '',
      contractId: json['contractId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      originalFileName: json['originalFileName']?.toString() ?? '',
      fileUrl: json['fileUrl']?.toString() ?? '',
      contentType: json['contentType']?.toString() ?? 'application/octet-stream',
      fileSize: json['fileSize'] is int
          ? json['fileSize'] as int
          : int.tryParse(json['fileSize']?.toString() ?? ''),
      isPrimary: json['isPrimary'] == true,
      displayOrder: json['displayOrder'] is int
          ? json['displayOrder'] as int
          : int.tryParse(json['displayOrder']?.toString() ?? ''),
      uploadedBy: json['uploadedBy']?.toString() ?? '',
      uploadedAt: parseDate(json['uploadedAt']),
    );
  }
}

