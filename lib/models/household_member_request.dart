import 'package:intl/intl.dart';

class HouseholdMemberRequest {
  HouseholdMemberRequest({
    required this.id,
    required this.householdId,
    required this.unitId,
    required this.status,
    this.householdCode,
    this.unitCode,
    this.requestedResidentFullName,
    this.requestedResidentPhone,
    this.requestedResidentEmail,
    this.requestedResidentNationalId,
    this.requestedResidentDob,
    this.relation,
    this.note,
    this.proofOfRelationImageUrl,
    this.createdAt,
    this.approvedAt,
    this.rejectedAt,
    this.approvedByName,
    this.rejectedByName,
    this.rejectionReason,
  });

  final String id;
  final String householdId;
  final String unitId;
  final String status;
  final String? householdCode;
  final String? unitCode;
  final String? requestedResidentFullName;
  final String? requestedResidentPhone;
  final String? requestedResidentEmail;
  final String? requestedResidentNationalId;
  final DateTime? requestedResidentDob;
  final String? relation;
  final String? note;
  final String? proofOfRelationImageUrl;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final String? approvedByName;
  final String? rejectedByName;
  final String? rejectionReason;

  factory HouseholdMemberRequest.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      final text = value.toString();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    return HouseholdMemberRequest(
      id: json['id']?.toString() ?? '',
      householdId: json['householdId']?.toString() ?? '',
      unitId: json['unitId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
      householdCode: json['householdCode']?.toString(),
      unitCode: json['unitCode']?.toString(),
      requestedResidentFullName: json['requestedResidentFullName']?.toString(),
      requestedResidentPhone: json['requestedResidentPhone']?.toString(),
      requestedResidentEmail: json['requestedResidentEmail']?.toString(),
      requestedResidentNationalId:
          json['requestedResidentNationalId']?.toString(),
      requestedResidentDob: parseDate(json['requestedResidentDob']),
      relation: json['relation']?.toString(),
      note: json['note']?.toString(),
      proofOfRelationImageUrl: json['proofOfRelationImageUrl']?.toString(),
      createdAt: parseDate(json['createdAt']),
      approvedAt: parseDate(json['approvedAt']),
      rejectedAt: parseDate(json['rejectedAt']),
      approvedByName: json['approvedByName']?.toString(),
      rejectedByName: json['rejectedByName']?.toString(),
      rejectionReason: json['rejectionReason']?.toString(),
    );
  }

  bool get isPending => status == 'PENDING';

  String get statusLabel {
    switch (status) {
      case 'APPROVED':
        return 'Đã duyệt';
      case 'REJECTED':
        return 'Bị từ chối';
      case 'CANCELLED':
        return 'Đã hủy';
      default:
        return 'Đang chờ duyệt';
    }
  }

  String? get formattedCreatedAt {
    if (createdAt == null) return null;
    return DateFormat('dd/MM/yyyy HH:mm').format(createdAt!.toLocal());
  }
}

