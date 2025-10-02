class MonthlyBillSummary {
  final int month;
  final int year;
  final double totalAmount;

  MonthlyBillSummary({
    required this.month,
    required this.year,
    required this.totalAmount,
  });

  factory MonthlyBillSummary.fromJson(Map<String, dynamic> json) {
    return MonthlyBillSummary(
      month: json['month'],
      year: json['year'],
      totalAmount: (json['totalAmount'] as num).toDouble(),
    );
  }
}