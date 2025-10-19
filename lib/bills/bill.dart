class Bill {
  final int id;
  final String billType;
  final double amount;
  final String month;
  final String year;
  final bool paid;
  final String? dueDate;
  final String? paymentDate;

  Bill({
    required this.id,
    required this.billType,
    required this.amount,
    required this.month,
    required this.year,
    required this.paid,
    this.dueDate,
    this.paymentDate,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: json['id'],
      billType: json['billType'],
      amount: (json['amount'] is int)
          ? (json['amount'] as int).toDouble()
          : (json['amount'] ?? 0.0).toDouble(),
      month: json['month'] ?? '',
      year: json['year'] ?? '',
      paid: json['paid'] ?? false,
      dueDate: json['dueDate'],
      paymentDate: json['paymentDate'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'billType': billType,
        'amount': amount,
        'month': month,
        'year': year,
        'paid': paid,
        'dueDate': dueDate,
        'paymentDate': paymentDate,
      };
}
