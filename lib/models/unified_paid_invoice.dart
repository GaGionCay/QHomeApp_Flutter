class UnifiedPaidInvoice {
  final String id;
  final String category; // "ELECTRICITY", "SERVICE_BOOKING", "VEHICLE_REGISTRATION"
  final String categoryName; // Display name
  final String title;
  final String? description;
  final double amount;
  final DateTime paymentDate;
  final String? paymentGateway;
  final String? status;
  final String? reference;
  final String? invoiceCode;
  final String? serviceName;
  final String? licensePlate;
  final String? vehicleType;

  UnifiedPaidInvoice({
    required this.id,
    required this.category,
    required this.categoryName,
    required this.title,
    this.description,
    required this.amount,
    required this.paymentDate,
    this.paymentGateway,
    this.status,
    this.reference,
    this.invoiceCode,
    this.serviceName,
    this.licensePlate,
    this.vehicleType,
  });

  factory UnifiedPaidInvoice.fromJson(Map<String, dynamic> json) {
    return UnifiedPaidInvoice(
      id: json['id']?.toString() ?? '',
      category: json['category'] ?? '',
      categoryName: json['categoryName'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      paymentDate: json['paymentDate'] != null
          ? DateTime.parse(json['paymentDate'])
          : DateTime.now(),
      paymentGateway: json['paymentGateway'],
      status: json['status'],
      reference: json['reference'],
      invoiceCode: json['invoiceCode'],
      serviceName: json['serviceName'],
      licensePlate: json['licensePlate'],
      vehicleType: json['vehicleType'],
    );
  }

  // Helper method to get month-year key for grouping
  String get monthYearKey {
    return '${paymentDate.year}-${paymentDate.month.toString().padLeft(2, '0')}';
  }
}


