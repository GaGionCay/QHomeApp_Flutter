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
    this.updatedAt,
    this.lastResentAt,
    this.resendAlertSent = false,
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
  final DateTime? updatedAt;
  final DateTime? lastResentAt;
  final bool resendAlertSent;

  factory CleaningRequestSummary.fromJson(Map<String, dynamic> json) {
    DateTime? scheduled;
    final dateString = json['cleaningDate']?.toString();
    final timeString = json['startTime']?.toString();
    if (dateString != null && timeString != null) {
      final cleanedTime = timeString.length == 5
          ? '$timeString:00'
          : timeString.length == 8
              ? timeString
              : timeString;
      final parsed = DateTime.tryParse('${dateString}T$cleanedTime');
      scheduled = parsed?.toLocal();
    }

    return CleaningRequestSummary(
      id: json['id']?.toString() ?? '',
      cleaningType: json['cleaningType']?.toString() ?? 'Không xác định',
      status: json['status']?.toString() ?? 'UNKNOWN',
      location: json['location']?.toString() ?? '—',
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now(),
      scheduledAt: scheduled,
      durationHours: (json['durationHours'] is num)
          ? (json['durationHours'] as num).toDouble()
          : double.tryParse(json['durationHours']?.toString() ?? ''),
      extraServices: (json['extraServices'] is List)
          ? (json['extraServices'] as List).whereType<String>().toList()
          : const [],
      note: json['note']?.toString(),
      updatedAt: _parseDateTime(json['updatedAt']),
      lastResentAt: _parseDateTime(json['lastResentAt']),
      resendAlertSent: _parseBool(json['resendAlertSent']),
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
    this.lastResentAt,
    this.resendAlertSent = false,
    this.callAlertSent = false,
    this.adminResponse,
    this.estimatedCost,
    this.respondedAt,
    this.responseStatus,
    this.attachments = const [],
  });

  final String id;
  final String category;
  final String title;
  final String status;
  final String location;
  final DateTime createdAt;
  final DateTime? preferredDatetime;
  final String? note;
  final DateTime? lastResentAt;
  final bool resendAlertSent;
  final bool callAlertSent;
  final String? adminResponse;
  final double? estimatedCost;
  final DateTime? respondedAt;
  final String? responseStatus;
  final List<String> attachments;

  factory MaintenanceRequestSummary.fromJson(Map<String, dynamic> json) {
    List<String> attachments = [];
    if (json['attachments'] != null) {
      if (json['attachments'] is List) {
        attachments = (json['attachments'] as List)
            .map((item) => item?.toString() ?? '')
            .where((url) => url.isNotEmpty)
            .toList();
      }
    }
    
    return MaintenanceRequestSummary(
      id: json['id']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Khác',
      title: json['title']?.toString() ?? 'Không xác định',
      status: json['status']?.toString() ?? 'UNKNOWN',
      location: json['location']?.toString() ?? '—',
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now(),
      preferredDatetime: _parseDateTime(json['preferredDatetime']),
      note: json['note']?.toString(),
      lastResentAt: _parseDateTime(json['lastResentAt']),
      resendAlertSent: _parseBool(json['resendAlertSent']),
      callAlertSent: _parseBool(json['callAlertSent']),
      adminResponse: json['adminResponse']?.toString(),
      estimatedCost: json['estimatedCost'] != null
          ? (json['estimatedCost'] is num
              ? (json['estimatedCost'] as num).toDouble()
              : double.tryParse(json['estimatedCost'].toString()))
          : null,
      respondedAt: _parseDateTime(json['respondedAt']),
      responseStatus: json['responseStatus']?.toString(),
      attachments: attachments,
    );
  }

  bool get hasPendingResponse =>
      responseStatus != null &&
      responseStatus!.toUpperCase() == 'PENDING_APPROVAL';
}

bool _parseBool(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().toLowerCase();
  return text == 'true';
}

DateTime? _parseDateTime(Object? value) {
  if (value == null) return null;
  final str = value.toString().trim();
  if (str.isEmpty) return null;

  try {
    final parsed = DateTime.tryParse(str);
    if (parsed == null) return null;

    // If parsed datetime is UTC, convert to local time
    // DateTime.tryParse already handles ISO 8601 with timezone correctly
    // But we need to ensure it's displayed in local time
    // If the string has timezone info (Z or +HH:MM), it will be parsed correctly
    // and DateTime in Dart is timezone-aware when parsed from ISO 8601
    return parsed.toLocal();
  } catch (_) {
    return null;
  }
}

class ServiceRequestPage<T> {
  const ServiceRequestPage({
    required this.requests,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<T> requests;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => total > offset + requests.length;
}

ServiceRequestPage<T> parseServiceRequestPage<T>(
  dynamic payload,
  T Function(Map<String, dynamic>) fromJson, {
  required int limit,
  required int offset,
}) {
  final items = _extractServiceRequestList(payload)
      .map<T>((item) => fromJson(Map<String, dynamic>.from(item)))
      .toList();

  final total = _extractIntValue(payload, 'total') ?? items.length;
  final serverLimit = _extractIntValue(payload, 'limit') ?? limit;
  final serverOffset = _extractIntValue(payload, 'offset') ?? offset;

  return ServiceRequestPage(
    requests: items,
    total: total,
    limit: serverLimit,
    offset: serverOffset,
  );
}

List<Map<String, dynamic>> _extractServiceRequestList(dynamic payload) {
  if (payload is List) {
    return payload
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  if (payload is Map<String, dynamic>) {
    final candidates = _searchListInMap(payload);
    if (candidates.isNotEmpty) {
      return candidates;
    }
  }

  return [];
}

List<Map<String, dynamic>> _searchListInMap(Map<String, dynamic> map) {
  for (final key in ['requests', 'content', 'items']) {
    final candidate = map[key];
    final normalized = _coerceToMapList(candidate);
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }

  final nested = map['data'];
  if (nested is List) {
    return _coerceToMapList(nested);
  }
  if (nested is Map<String, dynamic>) {
    return _searchListInMap(nested);
  }

  return [];
}

List<Map<String, dynamic>> _coerceToMapList(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }
  return [];
}

int? _extractIntValue(dynamic payload, String key) {
  if (payload is Map<String, dynamic>) {
    final rawValue = payload[key];
    final parsed = _coerceToInt(rawValue);
    if (parsed != null) {
      return parsed;
    }
    final nested = payload['data'];
    if (nested != null) {
      final nestedParsed = _extractIntValue(nested, key);
      if (nestedParsed != null) {
        return nestedParsed;
      }
    }
  }
  return null;
}

int? _coerceToInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
