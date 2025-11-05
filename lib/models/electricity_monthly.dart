class ElectricityMonthly {
  final String month; // "YYYY-MM"
  final String monthDisplay; // "MM/yyyy"
  final double amount;
  final int year;
  final int monthNumber; // 1-12

  ElectricityMonthly({
    required this.month,
    required this.monthDisplay,
    required this.amount,
    required this.year,
    required this.monthNumber,
  });

  factory ElectricityMonthly.fromJson(Map<String, dynamic> json) {
    return ElectricityMonthly(
      month: json['month'] ?? '',
      monthDisplay: json['monthDisplay'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      year: json['year'] ?? DateTime.now().year,
      monthNumber: json['monthNumber'] ?? DateTime.now().month,
    );
  }

  DateTime get dateTime => DateTime(year, monthNumber);
}

