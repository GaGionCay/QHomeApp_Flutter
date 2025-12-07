import 'package:intl/intl.dart';

class ResidentWithoutAccount {
  final String id;
  final String? fullName;
  final String? phone;
  final String? email;
  final String? nationalId;
  final DateTime? dob;
  final String? status;
  final String? relation;
  final bool isPrimary;

  ResidentWithoutAccount({
    required this.id,
    this.fullName,
    this.phone,
    this.email,
    this.nationalId,
    this.dob,
    this.status,
    this.relation,
    required this.isPrimary,
  });

  factory ResidentWithoutAccount.fromJson(Map<String, dynamic> json) {
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

    return ResidentWithoutAccount(
      id: json['id']?.toString() ?? '',
      fullName: json['fullName']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      nationalId: json['nationalId']?.toString(),
      dob: parseDate(json['dob']),
      status: json['status']?.toString(),
      relation: json['relation']?.toString(),
      isPrimary: json['isPrimary'] == true,
    );
  }

  String get formattedDob {
    if (dob == null) return '';
    return DateFormat('dd/MM/yyyy').format(dob!);
  }
}


