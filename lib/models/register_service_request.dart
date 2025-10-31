class RegisterServiceRequest {
  final int? id;
  final String? serviceType;
  final String? note;
  final String? status; // PENDING, DRAFT - trạng thái xử lý của admin
  final String? paymentStatus; // PAID, UNPAID - trạng thái thanh toán
  final String? vehicleType;
  final String? licensePlate;
  final String? vehicleBrand;
  final String? vehicleColor;
  final List<String>? imageUrls;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? paymentDate;
  final String? paymentGateway;
  final String? vnpayTransactionRef;

  RegisterServiceRequest({
    this.id,
    this.serviceType,
    this.note,
    this.status,
    this.paymentStatus,
    this.vehicleType,
    this.licensePlate,
    this.vehicleBrand,
    this.vehicleColor,
    this.imageUrls,
    this.createdAt,
    this.updatedAt,
    this.paymentDate,
    this.paymentGateway,
    this.vnpayTransactionRef,
  });

  factory RegisterServiceRequest.fromJson(Map<String, dynamic> json) {
    return RegisterServiceRequest(
      id: json['id'] is int
          ? json['id'] as int
          : (json['id'] is num ? (json['id'] as num).toInt() : null),
      serviceType: json['serviceType']?.toString(),
      note: json['note']?.toString(),
      status: json['status']?.toString(),
      paymentStatus: json['paymentStatus']?.toString(),
      vehicleType: json['vehicleType']?.toString(),
      licensePlate: json['licensePlate']?.toString(),
      vehicleBrand: json['vehicleBrand']?.toString(),
      vehicleColor: json['vehicleColor']?.toString(),
      imageUrls: (json['imageUrls'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
      paymentDate: json['paymentDate'] != null
          ? DateTime.tryParse(json['paymentDate'].toString())
          : null,
      paymentGateway: json['paymentGateway']?.toString(),
      vnpayTransactionRef: json['vnpayTransactionRef']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'serviceType': serviceType,
      'note': note,
      'status': status,
      'vehicleType': vehicleType,
      'licensePlate': licensePlate,
      'vehicleBrand': vehicleBrand,
      'vehicleColor': vehicleColor,
      'imageUrls': imageUrls ?? [],
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  static List<RegisterServiceRequest> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .map((e) => RegisterServiceRequest.fromJson(
              Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }
}
