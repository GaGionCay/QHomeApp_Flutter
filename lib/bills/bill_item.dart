import 'package:intl/intl.dart';

class BillItem {
  final int id;
  final String billType;
  final double amount;
  final DateTime billingMonth;
  final String status;
  final String? description;
  final DateTime? paymentDate;

  BillItem({
    required this.id,
    required this.billType,
    required this.amount,
    required this.billingMonth,
    required this.status,
    this.description,
    this.paymentDate,
  });

  factory BillItem.fromJson(Map<String, dynamic> json) {
    return BillItem(
      id: json['id'],
      billType: json['billType'] ?? '',
      amount: (json['amount'] as num).toDouble(),
      billingMonth: DateTime.parse(json['billingMonth']),
      status: json['status'] ?? 'UNPAID',
      description: json['description'],
      paymentDate: json['paymentDate'] != null
          ? DateTime.parse(json['paymentDate'])
          : null,
    );
  }

  String formattedAmount() {
    final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
    return formatter.format(amount);
  }

  String formattedBillingMonth() {
    final formatter = DateFormat('MM/yyyy');
    return formatter.format(billingMonth);
  }
}
