class UnitInfo {
  final String id;
  final String? buildingId;
  final String? buildingCode;
  final String? buildingName;
  final String code;
  final int? floor;
  final double? areaM2;
  final int? bedrooms;
  final String? status;
  final String? primaryResidentId;

  UnitInfo({
    required this.id,
    required this.code,
    this.buildingId,
    this.buildingCode,
    this.buildingName,
    this.floor,
    this.areaM2,
    this.bedrooms,
    this.status,
    this.primaryResidentId,
  });

  factory UnitInfo.fromJson(Map<String, dynamic> json) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return UnitInfo(
      id: json['id']?.toString() ?? '',
      buildingId: json['buildingId']?.toString(),
      buildingCode: json['buildingCode']?.toString(),
      buildingName: json['buildingName']?.toString(),
      code: json['code']?.toString() ?? '',
      floor: json['floor'] is int ? json['floor'] as int : int.tryParse(json['floor']?.toString() ?? ''),
      areaM2: parseDouble(json['areaM2']),
      bedrooms: json['bedrooms'] is int
          ? json['bedrooms'] as int
          : int.tryParse(json['bedrooms']?.toString() ?? ''),
      status: json['status']?.toString(),
      primaryResidentId: json['primaryResidentId']?.toString(),
    );
  }

  String get displayName {
    if ((buildingCode ?? '').isNotEmpty) {
      return '$buildingCode • $code';
    }
    if ((buildingName ?? '').isNotEmpty) {
      return '$buildingName • $code';
    }
    return code;
  }

  bool isPrimaryResident(String? residentId) {
    if (residentId == null || residentId.isEmpty) return false;
    return primaryResidentId != null &&
        primaryResidentId!.toLowerCase() == residentId.toLowerCase();
  }
}

