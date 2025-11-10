class Household {
  Household({
    required this.id,
    required this.unitId,
    this.unitCode,
    this.kind,
    this.primaryResidentId,
    this.primaryResidentName,
    this.startDate,
    this.endDate,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String unitId;
  final String? unitCode;
  final String? kind;
  final String? primaryResidentId;
  final String? primaryResidentName;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Household.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      final text = value.toString();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    return Household(
      id: json['id']?.toString() ?? '',
      unitId: json['unitId']?.toString() ?? '',
      unitCode: json['unitCode']?.toString(),
      kind: json['kind']?.toString(),
      primaryResidentId: json['primaryResidentId']?.toString(),
      primaryResidentName: json['primaryResidentName']?.toString(),
      startDate: parseDate(json['startDate']),
      endDate: parseDate(json['endDate']),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  String get displayName {
    final code = unitCode;
    final kindName = kind;
    if ((code ?? '').isEmpty && (kindName ?? '').isEmpty) {
      return 'Hộ gia đình';
    }
    if ((code ?? '').isEmpty) {
      return 'Hộ $kindName';
    }
    if ((kindName ?? '').isEmpty) {
      return 'Hộ $code';
    }
    return 'Hộ $code • $kindName';
  }
}
