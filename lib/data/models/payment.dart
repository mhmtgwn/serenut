class Payment {
  final int? id;
  final int orderId;
  final double amount;
  final String notes;
  final String method;
  final String date;
  final String createdAt;

  Payment({
    this.id,
    required this.orderId,
    required this.amount,
    required this.notes,
    required this.method,
    required this.date,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'orderId': orderId,
      'amount': amount,
      'notes': notes,
      'method': method,
      'date': date,
      'createdAt': createdAt,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'] as int?,
      orderId: map['orderId'] as int,
      amount: (map['amount'] as num).toDouble(),
      notes: map['notes'] as String? ?? '',
      method: map['method'] as String,
      date: map['date'] as String,
      createdAt: map['createdAt'] as String,
    );
  }
}
