class CleaningRequestSummary {
  CleaningRequestSummary({
    required this.id,
    required this.cleaningType,
    required this.status,
    required this.location,
    required this.createdAt,
    this.scheduledAt,
    this.durationHours,
    this.extraServices = const [],
    this.note,
  });

  final String id;
  final String cleaningType;
  final String status;
  final String location;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final double? durationHours;
  final List<String> extraServices;
  final String? note;

  factory CleaningRequestSummary.fromJson(Map<String, dynamic> json) {
    DateTime? scheduled;
    final dateString = json['cleaningDate']?.toString();
    final timeString = json['startTime']?.toString();
    if (dateString != null && timeString != null) {
      final cleanedTime = timeString.length == 5
          ? '$timeString:00'
          : timeString.length == 8
              ? timeString
              : '$timeString';
      scheduled = DateTime.tryParse('${dateString}T$cleanedTime');
    }

    return CleaningRequestSummary(
      id: json['id']?.toString() ?? '',
      cleaningType: json['cleaningType']?.toString() ?? 'Không xác định',
      status: json['status']?.toString() ?? 'UNKNOWN',
      location: json['location']?.toString() ?? '—',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      scheduledAt: scheduled,
      durationHours: (json['durationHours'] is num)
          ? (json['durationHours'] as num).toDouble()
          : double.tryParse(json['durationHours']?.toString() ?? ''),
      extraServices: (json['extraServices'] is List)
          ? (json['extraServices'] as List)
              .whereType<String>()
              .toList()
          : const [],
      note: json['note']?.toString(),
    );
  }
}

class MaintenanceRequestSummary {
  MaintenanceRequestSummary({
    required this.id,
    required this.category,
    required this.title,
    required this.status,
    required this.location,
    required this.createdAt,
    this.preferredDatetime,
    this.note,
  });

  final String id;
  final String category;
  final String title;
  final String status;
  final String location;
  final DateTime createdAt;
  final DateTime? preferredDatetime;
  final String? note;

  factory MaintenanceRequestSummary.fromJson(Map<String, dynamic> json) {
    return MaintenanceRequestSummary(
      id: json['id']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Khác',
      title: json['title']?.toString() ?? 'Không xác định',
      status: json['status']?.toString() ?? 'UNKNOWN',
      location: json['location']?.toString() ?? '—',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      preferredDatetime:
          DateTime.tryParse(json['preferredDatetime']?.toString() ?? ''),
      note: json['note']?.toString(),
    );
  }
}

