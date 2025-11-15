class Expense {
  final int? id;
  final String title;
  final double amount;
  final String category;
  final String? notes;
  final String date;
  final String createdAt;

  Expense({
    this.id,
    required this.title,
    required this.amount,
    required this.category,
    this.notes,
    required this.date,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'category': category,
      'notes': notes,
      'date': date,
      'createdAt': createdAt,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String,
      notes: map['notes'] as String?,
      date: map['date'] as String,
      createdAt: map['createdAt'] as String,
    );
  }
}
