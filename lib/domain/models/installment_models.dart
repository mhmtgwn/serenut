// lib/domain/models/installment_models.dart
// Serenut OS — Customer Installment Plans and Tracking Models

import '../utils/safe_money.dart';

class CustomerInstallmentPlanEntity {
  final String id;
  final String customerId;
  final double totalAmount;
  final double downPayment;
  final int installmentCount;
  final String description;
  final String status; // active | completed | cancelled
  final DateTime createdAt;
  final DateTime updatedAt;
  final int isSynced;
  final int isDeleted;

  CustomerInstallmentPlanEntity({
    required this.id,
    required this.customerId,
    required this.totalAmount,
    this.downPayment = 0.0,
    required this.installmentCount,
    this.description = '',
    this.status = 'active',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = 0,
    this.isDeleted = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get financedAmount => (totalAmount - downPayment).clamp(0.0, double.infinity);

  Map<String, dynamic> toMap() => {
        'id': id,
        'customer_id': customerId,
        'total_amount': totalAmount,
        'down_payment': downPayment,
        'installment_count': installmentCount,
        'description': description,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced,
        'is_deleted': isDeleted,
      };

  factory CustomerInstallmentPlanEntity.fromMap(Map<String, dynamic> map) {
    return CustomerInstallmentPlanEntity(
      id: map['id']?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      downPayment: (map['down_payment'] as num?)?.toDouble() ?? 0.0,
      installmentCount: (map['installment_count'] as num?)?.toInt() ?? 1,
      description: map['description']?.toString() ?? '',
      status: map['status']?.toString() ?? 'active',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isSynced: (map['is_synced'] as num?)?.toInt() ?? 0,
      isDeleted: (map['is_deleted'] as num?)?.toInt() ?? 0,
    );
  }
}

class CustomerInstallmentEntity {
  final String id;
  final String planId;
  final String customerId;
  final int installmentNo;
  final double amount;
  final double paidAmount;
  final String dueDate; // YYYY-MM-DD
  final String status; // pending | paid | partial | cancelled
  final DateTime? paidAt;
  final String? financialTransactionId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int isSynced;
  final int isDeleted;

  CustomerInstallmentEntity({
    required this.id,
    required this.planId,
    required this.customerId,
    required this.installmentNo,
    required this.amount,
    this.paidAmount = 0.0,
    required this.dueDate,
    this.status = 'pending',
    this.paidAt,
    this.financialTransactionId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = 0,
    this.isDeleted = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get remainingAmount =>
      SafeMoney.subtract(amount, paidAmount).clamp(0.0, double.infinity);
  bool get isPaid => status == 'paid' || SafeMoney.isZero(remainingAmount);

  DateTime? get parsedDueDate => DateTime.tryParse(dueDate);

  bool get isOverdue {
    if (isPaid) return false;
    final d = parsedDueDate;
    if (d == null) return false;
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    final dueMidnight = DateTime(d.year, d.month, d.day);
    return dueMidnight.isBefore(todayMidnight);
  }

  bool get isDueToday {
    if (isPaid) return false;
    final d = parsedDueDate;
    if (d == null) return false;
    final today = DateTime.now();
    return d.year == today.year && d.month == today.month && d.day == today.day;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'plan_id': planId,
        'customer_id': customerId,
        'installment_no': installmentNo,
        'amount': amount,
        'paid_amount': paidAmount,
        'due_date': dueDate,
        'status': status,
        'paid_at': paidAt?.toIso8601String(),
        'financial_transaction_id': financialTransactionId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced,
        'is_deleted': isDeleted,
      };

  factory CustomerInstallmentEntity.fromMap(Map<String, dynamic> map) {
    return CustomerInstallmentEntity(
      id: map['id']?.toString() ?? '',
      planId: map['plan_id']?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      installmentNo: (map['installment_no'] as num?)?.toInt() ?? 1,
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0.0,
      dueDate: map['due_date']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      paidAt: map['paid_at'] != null ? DateTime.tryParse(map['paid_at'].toString()) : null,
      financialTransactionId: map['financial_transaction_id']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isSynced: (map['is_synced'] as num?)?.toInt() ?? 0,
      isDeleted: (map['is_deleted'] as num?)?.toInt() ?? 0,
    );
  }
}
