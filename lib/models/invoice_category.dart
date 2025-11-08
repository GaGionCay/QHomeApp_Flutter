import 'invoice_line.dart';

class InvoiceCategory {
  final String categoryCode;
  final String categoryName;
  final double totalAmount;
  final int invoiceCount;
  final List<InvoiceLineResponseDto> invoices;

  InvoiceCategory({
    required this.categoryCode,
    required this.categoryName,
    required this.totalAmount,
    required this.invoiceCount,
    required this.invoices,
  });

  factory InvoiceCategory.fromJson(Map<String, dynamic> json) {
    final List<dynamic> invoiceList = json['invoices'] ?? [];
    return InvoiceCategory(
      categoryCode: json['categoryCode'] ?? '',
      categoryName: json['categoryName'] ?? '',
      totalAmount: (json['totalAmount'] is num) ? json['totalAmount'].toDouble() : 0.0,
      invoiceCount: json['invoiceCount'] is int
          ? json['invoiceCount'] as int
          : (json['invoiceCount'] is num)
              ? (json['invoiceCount'] as num).toInt()
              : invoiceList.length,
      invoices: invoiceList
          .map((item) => InvoiceLineResponseDto.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'categoryCode': categoryCode,
        'categoryName': categoryName,
        'totalAmount': totalAmount,
        'invoiceCount': invoiceCount,
        'invoices': invoices.map((e) => e.toJson()).toList(),
      };

  bool get hasInvoices => invoices.isNotEmpty;
}

