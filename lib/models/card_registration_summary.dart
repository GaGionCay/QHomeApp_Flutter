class CardRegistrationSummary {
  final String id;
  final String cardType;
  final String? userId;
  final String? residentId;
  final String? unitId;
  final String? requestType;
  final String? status;
  final String? paymentStatus;
  final double? paymentAmount;
  final DateTime? paymentDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? displayName;
  final String? reference;
  final String? apartmentNumber;
  final String? buildingName;
  final String? note;

  const CardRegistrationSummary({
    required this.id,
    required this.cardType,
    this.userId,
    this.residentId,
    this.unitId,
    this.requestType,
    this.status,
    this.paymentStatus,
    this.paymentAmount,
    this.paymentDate,
    this.createdAt,
    this.updatedAt,
    this.displayName,
    this.reference,
    this.apartmentNumber,
    this.buildingName,
    this.note,
  });

  factory CardRegistrationSummary.fromJson(Map<String, dynamic> json) {
    return CardRegistrationSummary(
      id: json['id']?.toString() ?? '',
      cardType: json['cardType']?.toString() ?? 'UNKNOWN',
      userId: json['userId']?.toString(),
      residentId: json['residentId']?.toString(),
      unitId: json['unitId']?.toString(),
      requestType: json['requestType']?.toString(),
      status: json['status']?.toString(),
      paymentStatus: json['paymentStatus']?.toString(),
      paymentAmount: _parseDouble(json['paymentAmount']),
      paymentDate: _parseDateTime(json['paymentDate']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      displayName: json['displayName']?.toString(),
      reference: json['reference']?.toString(),
      apartmentNumber: json['apartmentNumber']?.toString(),
      buildingName: json['buildingName']?.toString(),
      note: json['note']?.toString(),
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
