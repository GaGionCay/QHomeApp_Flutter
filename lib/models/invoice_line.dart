class InvoiceLineResponseDto {
  final String payerUnitId;
  final String invoiceId;
  final String? invoiceCode;
  final String serviceDate;
  final String description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double taxAmount;
  final double lineTotal;
  final double? totalAfterTax;
  final String serviceCode;
  final String status;
  final DateTime? paidAt;
  final String? paymentGateway;
  
  // Permission fields
  final bool? isOwner; // true if current user is OWNER or TENANT of the unit
  final bool? canPay; // true if user can pay this invoice
  final String? permissionMessage; // Message to display if user doesn't have permission

  InvoiceLineResponseDto({
    required this.payerUnitId,
    required this.invoiceId,
    this.invoiceCode,
    required this.serviceDate,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.taxAmount,
    required this.lineTotal,
    this.totalAfterTax,
    required this.serviceCode,
    required this.status,
    this.paidAt,
    this.paymentGateway,
    this.isOwner,
    this.canPay,
    this.permissionMessage,
  });

  factory InvoiceLineResponseDto.fromJson(Map<String, dynamic> json) {
    return InvoiceLineResponseDto(
      payerUnitId: json['payerUnitId'] ?? '',
      invoiceId: json['invoiceId'] ?? '',
      invoiceCode: json['invoiceCode']?.toString(),
      serviceDate: json['serviceDate'] ?? '',
      description: json['description'] ?? '',
      quantity: (json['quantity'] is num) ? json['quantity'].toDouble() : 0.0,
      unit: json['unit'] ?? '',
      unitPrice: (json['unitPrice'] is num) ? json['unitPrice'].toDouble() : 0.0,
      taxAmount: (json['taxAmount'] is num) ? json['taxAmount'].toDouble() : 0.0,
      lineTotal: (json['lineTotal'] is num) ? json['lineTotal'].toDouble() : 0.0,
      totalAfterTax: (json['totalAfterTax'] is num) ? json['totalAfterTax'].toDouble() : null,
      serviceCode: json['serviceCode'] ?? '',
      status: json['status'] ?? '',
      paidAt: json['paidAt'] != null ? DateTime.parse(json['paidAt']) : null,
      paymentGateway: json['paymentGateway']?.toString(),
      isOwner: json['isOwner'] == true,
      canPay: json['canPay'] == true,
      permissionMessage: json['permissionMessage']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'payerUnitId': payerUnitId,
        'invoiceId': invoiceId,
        'invoiceCode': invoiceCode,
        'serviceDate': serviceDate,
        'description': description,
        'quantity': quantity,
        'unit': unit,
        'unitPrice': unitPrice,
        'taxAmount': taxAmount,
        'lineTotal': lineTotal,
        'totalAfterTax': totalAfterTax,
        'serviceCode': serviceCode,
        'status': status,
        'paidAt': paidAt?.toIso8601String(),
        'paymentGateway': paymentGateway,
        'isOwner': isOwner,
        'canPay': canPay,
        'permissionMessage': permissionMessage,
      };

  bool get isPaid => status.toUpperCase() == 'PAID';
  bool get isDraft => status.toUpperCase() == 'DRAFT';
  bool get isPublished => status.toUpperCase() == 'PUBLISHED';
  bool get isUnpaid => status.toUpperCase() == 'UNPAID';

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

  /// Format amount for display
  String get formattedAmount {
    final amount = totalAfterTax ?? lineTotal;
    return '${amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    )} đ';
  }

  /// Format paid date
  String get formattedPaidDate {
    if (paidAt == null) return '';
    return '${paidAt!.day.toString().padLeft(2, '0')}/${paidAt!.month.toString().padLeft(2, '0')}/${paidAt!.year}';
  }

  /// Get service icon
  String get serviceIcon {
    switch (serviceCode.toUpperCase()) {
      case 'ELECTRIC':
      case 'ELECTRICITY':
        return '⚡';
      case 'WATER':
        return '💧';
      case 'PARKING':
      case 'CAR_PARK':
      case 'CARPARK':
      case 'VEHICLE_PARKING':
      case 'MOTORBIKE_PARK':
      case 'PARKING_CAR':
      case 'PARKING_MOTORBIKE':
      case 'PARKING_PRORATA':
        return '🅿️';
      case 'ELEVATOR_CARD':
      case 'RESIDENT_CARD':
      case 'VEHICLE_CARD':
        return '🎫';
      default:
        if (serviceCode.toUpperCase().contains('MAINTENANCE')) return '🔧';
        if (serviceCode.toUpperCase().contains('CLEANING')) return '🧹';
        return '📋';
    }
  }
}


