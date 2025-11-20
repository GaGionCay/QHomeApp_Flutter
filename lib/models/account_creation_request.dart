import 'package:intl/intl.dart';

class AccountCreationRequest {
  final String id;
  final String? residentId;
  final String? residentName;
  final String? residentEmail;
  final String? residentPhone;
  final String? householdId;
  final String? unitId;
  final String? unitCode;
  final String? relation;
  final String? requestedBy;
  final String? requestedByName;
  final String? username;
  final String? email;
  final bool autoGenerate;
  final String status;
  final String? approvedBy;
  final String? approvedByName;
  final String? rejectedBy;
  final String? rejectedByName;
  final String? rejectionReason;
  final List<String> proofOfRelationImageUrls;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final DateTime? createdAt;

  AccountCreationRequest({
    required this.id,
    required this.status,
    required this.autoGenerate,
    this.residentId,
    this.residentName,
    this.residentEmail,
    this.residentPhone,
    this.householdId,
    this.unitId,
    this.unitCode,
    this.relation,
    this.requestedBy,
    this.requestedByName,
    this.username,
    this.email,
    this.approvedBy,
    this.approvedByName,
    this.rejectedBy,
    this.rejectedByName,
    this.rejectionReason,
    this.proofOfRelationImageUrls = const [],
    this.approvedAt,
    this.rejectedAt,
    this.createdAt,
  });

  factory AccountCreationRequest.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      try {
        if (value is DateTime) return value;
        if (value is String && value.isNotEmpty) {
          return DateTime.parse(value);
        }
      } catch (_) {}
      return null;
    }

    return AccountCreationRequest(
      id: json['id']?.toString() ?? '',
      residentId: json['residentId']?.toString(),
      residentName: json['residentName']?.toString(),
      residentEmail: json['residentEmail']?.toString(),
      residentPhone: json['residentPhone']?.toString(),
      householdId: json['householdId']?.toString(),
      unitId: json['unitId']?.toString(),
      unitCode: json['unitCode']?.toString(),
      relation: json['relation']?.toString(),
      requestedBy: json['requestedBy']?.toString(),
      requestedByName: json['requestedByName']?.toString(),
      username: json['username']?.toString(),
      email: json['email']?.toString(),
      autoGenerate: json['autoGenerate'] == true,
      status: json['status']?.toString() ?? 'UNKNOWN',
      approvedBy: json['approvedBy']?.toString(),
      approvedByName: json['approvedByName']?.toString(),
      rejectedBy: json['rejectedBy']?.toString(),
      rejectedByName: json['rejectedByName']?.toString(),
      rejectionReason: json['rejectionReason']?.toString(),
      proofOfRelationImageUrls: (json['proofOfRelationImageUrls'] as List?)
              ?.map((item) => item?.toString() ?? '')
              .where((value) => value.isNotEmpty)
              .toList() ??
          const [],
      approvedAt: parseDate(json['approvedAt']),
      rejectedAt: parseDate(json['rejectedAt']),
      createdAt: parseDate(json['createdAt']),
    );
  }

  String get statusLabel {
    switch (status.toUpperCase()) {
      case 'APPROVED':
        return 'Đã duyệt';
      case 'REJECTED':
        return 'Từ chối';
      case 'CANCELLED':
        return 'Đã hủy';
      case 'PENDING':
        return 'Đang chờ duyệt';
      default:
        return status;
    }
  }

  String get formattedCreatedAt {
    if (createdAt == null) return '';
    return DateFormat('dd/MM/yyyy HH:mm').format(createdAt!.toLocal());
  }

  String get formattedApprovedAt {
    if (approvedAt == null) return '';
    return DateFormat('dd/MM/yyyy HH:mm').format(approvedAt!.toLocal());
  }

  String get formattedRejectedAt {
    if (rejectedAt == null) return '';
    return DateFormat('dd/MM/yyyy HH:mm').format(rejectedAt!.toLocal());
  }

  bool get hasProofImages => proofOfRelationImageUrls.isNotEmpty;

  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isApproved => status.toUpperCase() == 'APPROVED';
  bool get isRejected => status.toUpperCase() == 'REJECTED';
  bool get isCancelled => status.toUpperCase() == 'CANCELLED';
}

