class InvoiceLineResponseDto {
  final String payerUnitId;
  final String invoiceId;
  final String serviceDate;
  final String description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double taxAmount;
  final double lineTotal;
  final String serviceCode;
  final String status;

  InvoiceLineResponseDto({
    required this.payerUnitId,
    required this.invoiceId,
    required this.serviceDate,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.taxAmount,
    required this.lineTotal,
    required this.serviceCode,
    required this.status,
  });

  factory InvoiceLineResponseDto.fromJson(Map<String, dynamic> json) {
    return InvoiceLineResponseDto(
      payerUnitId: json['payerUnitId'] ?? '',
      invoiceId: json['invoiceId'] ?? '',
      serviceDate: json['serviceDate'] ?? '',
      description: json['description'] ?? '',
      quantity: (json['quantity'] is num) ? json['quantity'].toDouble() : 0.0,
      unit: json['unit'] ?? '',
      unitPrice: (json['unitPrice'] is num) ? json['unitPrice'].toDouble() : 0.0,
      taxAmount: (json['taxAmount'] is num) ? json['taxAmount'].toDouble() : 0.0,
      lineTotal: (json['lineTotal'] is num) ? json['lineTotal'].toDouble() : 0.0,
      serviceCode: json['serviceCode'] ?? '',
      status: json['status'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'payerUnitId': payerUnitId,
        'invoiceId': invoiceId,
        'serviceDate': serviceDate,
        'description': description,
        'quantity': quantity,
        'unit': unit,
        'unitPrice': unitPrice,
        'taxAmount': taxAmount,
        'lineTotal': lineTotal,
        'serviceCode': serviceCode,
        'status': status,
      };

  bool get isPaid => status.toUpperCase() == 'PAID';
  bool get isDraft => status.toUpperCase() == 'DRAFT';
  bool get isPublished => status.toUpperCase() == 'PUBLISHED';

  String get serviceCodeDisplay {
    switch (serviceCode.toUpperCase()) {
      case 'ELECTRIC':
      case 'ELECTRICITY':
        return 'Điện';
      case 'WATER':
        return 'Nước';
      case 'INTERNET':
        return 'Internet';
      case 'ELEVATOR':
      case 'ELEVATOR_CARD':
        return 'Vé thang máy';
      case 'PARKING':
      case 'CAR_PARK':
      case 'CARPARK':
      case 'VEHICLE_PARKING':
      case 'MOTORBIKE_PARK':
        return 'Vé gửi xe';
      case 'RESIDENT_CARD':
        return 'Thẻ cư dân';
      case 'VEHICLE_CARD':
        return 'Thẻ xe';
      default:
        return serviceCode;
    }
  }
}

