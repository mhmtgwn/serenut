// lib/infrastructure/repositories/sqlite_installment_repository.dart
// Serenut OS — SQLite Customer Installment Repository

import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/models/installment_models.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';

abstract class IInstallmentRepository {
  Future<CustomerInstallmentPlanEntity> createPlan({
    required String customerId,
    required double totalAmount,
    double downPayment = 0.0,
    String downPaymentMethod = 'cash',
    required int installmentCount,
    required DateTime firstDueDate,
    String description = '',
    List<double>? customAmounts,
    List<DateTime>? customDueDates,
  });

  Future<List<CustomerInstallmentPlanEntity>> getPlansForCustomer(String customerId);
  Future<List<CustomerInstallmentEntity>> getInstallmentsForCustomer(String customerId);
  Future<List<CustomerInstallmentEntity>> getInstallmentsForPlan(String planId);
  Future<List<CustomerInstallmentEntity>> getDueOrOverdueInstallments({int daysAhead = 7});
  Future<Map<String, int>> getDueSummary();

  Future<void> payInstallment({
    required String installmentId,
    required double amount,
    required String paymentMethod,
    String? note,
  });

  Future<void> cancelPlan(String planId);
}

class SqliteInstallmentRepository implements IInstallmentRepository {
  final DbGateway _gateway;
  static const _uuid = Uuid();

  SqliteInstallmentRepository(this._gateway);

  DbExecutor get _executor => _gateway;

  @override
  Future<CustomerInstallmentPlanEntity> createPlan({
    required String customerId,
    required double totalAmount,
    double downPayment = 0.0,
    String downPaymentMethod = 'cash',
    required int installmentCount,
    required DateTime firstDueDate,
    String description = '',
    List<double>? customAmounts,
    List<DateTime>? customDueDates,
  }) async {
    if (totalAmount <= 0) {
      throw ArgumentError('Toplam tutar sıfırdan büyük olmalıdır.');
    }
    if (installmentCount < 1) {
      throw ArgumentError('Taksit sayısı en az 1 olmalıdır.');
    }
    if (downPayment >= totalAmount) {
      throw ArgumentError('Peşinat toplam tutardan küçük olmalıdır.');
    }

    final financed = (totalAmount - downPayment).clamp(0.0, double.infinity);
    final planId = 'plan-${_uuid.v4()}';
    final now = DateTime.now();

    final plan = CustomerInstallmentPlanEntity(
      id: planId,
      customerId: customerId,
      totalAmount: totalAmount,
      downPayment: downPayment,
      installmentCount: installmentCount,
      description: description,
      status: 'active',
      createdAt: now,
      updatedAt: now,
      isSynced: 0,
    );

    // Taksit tutarları ve vadeleri hesaplama
    final installments = <CustomerInstallmentEntity>[];
    if (customAmounts != null && customAmounts.length == installmentCount) {
      for (int i = 0; i < installmentCount; i++) {
        final d = (customDueDates != null && customDueDates.length == installmentCount)
            ? customDueDates[i]
            : _addMonths(firstDueDate, i);
        installments.add(CustomerInstallmentEntity(
          id: 'inst-${_uuid.v4()}',
          planId: planId,
          customerId: customerId,
          installmentNo: i + 1,
          amount: customAmounts[i],
          paidAmount: 0.0,
          dueDate: DateFormat('yyyy-MM-dd').format(d),
          status: 'pending',
          createdAt: now,
          updatedAt: now,
          isSynced: 0,
        ));
      }
    } else {
      // Taksitler yuvarlak olsun, küsuratlar son taksite bağlansın
      double baseAmount = (financed / installmentCount).floorToDouble();
      if (baseAmount < 1.0 && financed > 0) {
        baseAmount = (financed / installmentCount * 100).floor() / 100.0;
      }

      double allocatedTotal = 0.0;
      for (int i = 0; i < installmentCount; i++) {
        final d = _addMonths(firstDueDate, i);
        final isLast = (i == installmentCount - 1);
        final amt = isLast
            ? double.parse((financed - allocatedTotal).toStringAsFixed(2))
            : baseAmount;
        allocatedTotal += amt;

        installments.add(CustomerInstallmentEntity(
          id: 'inst-${_uuid.v4()}',
          planId: planId,
          customerId: customerId,
          installmentNo: i + 1,
          amount: amt,
          paidAmount: 0.0,
          dueDate: DateFormat('yyyy-MM-dd').format(d),
          status: 'pending',
          createdAt: now,
          updatedAt: now,
          isSynced: 0,
        ));
      }
    }

    await _gateway.transaction(() async {
      // 1. Taksit Planını Ekle
      await _executor.insert('customer_installment_plans', plan.toMap());

      // 2. Taksit Satırlarını Ekle
      for (final inst in installments) {
        await _executor.insert('customer_installments', inst.toMap());
      }

      // 3. Müşteriye Borç Hareketi Yaz (financial_transactions)
      final debtTxId = 'trans-debt-${_uuid.v4()}';
      final debtDesc = description.isNotEmpty
          ? 'Taksitli Borç: $description ($installmentCount Taksit)'
          : 'Taksitli Borç ($installmentCount Taksit)';

      await _executor.insert('financial_transactions', {
        'id': debtTxId,
        'type': 'manual_debt',
        'customer_id': customerId,
        'amount': financed,
        'paid_amount': 0.0,
        'debt_amount': financed,
        'reference_id': planId,
        'description': debtDesc,
        'payment_method': 'veresiye',
        'is_deleted': 0,
        'is_synced': 0,
        'created_at': now.toIso8601String(),
      });

      await SyncOutboxV4.enqueue(
        _executor,
        entityType: 'financial_transaction',
        entityId: debtTxId,
        operation: 'UPSERT',
        payload: {
          'id': debtTxId,
          'type': 'manual_debt',
          'customer_id': customerId,
          'amount': financed,
          'paid_amount': 0.0,
          'debt_amount': financed,
          'reference_id': planId,
          'description': debtDesc,
          'payment_method': 'veresiye',
          'created_at': now.toIso8601String(),
        },
      );

      // 4. Varsa Peşinat Tahsilatını Yaz
      if (downPayment > 0.0) {
        final colTxId = 'trans-col-${_uuid.v4()}';
        final colDesc = description.isNotEmpty
            ? 'Taksit Peşinatı: $description'
            : 'Taksit Peşinatı';

        await _executor.insert('financial_transactions', {
          'id': colTxId,
          'type': 'collection',
          'customer_id': customerId,
          'amount': downPayment,
          'paid_amount': downPayment,
          'debt_amount': 0.0,
          'reference_id': planId,
          'description': colDesc,
          'payment_method': downPaymentMethod,
          'is_deleted': 0,
          'is_synced': 0,
          'created_at': now.toIso8601String(),
        });

        await SyncOutboxV4.enqueue(
          _executor,
          entityType: 'financial_transaction',
          entityId: colTxId,
          operation: 'UPSERT',
          payload: {
            'id': colTxId,
            'type': 'collection',
            'customer_id': customerId,
            'amount': downPayment,
            'paid_amount': downPayment,
            'debt_amount': 0.0,
            'reference_id': planId,
            'description': colDesc,
            'payment_method': downPaymentMethod,
            'created_at': now.toIso8601String(),
          },
        );
      }
    });

    return plan;
  }

  @override
  Future<List<CustomerInstallmentPlanEntity>> getPlansForCustomer(String customerId) async {
    final rows = await _executor.query(
      'customer_installment_plans',
      where: 'customer_id = ? AND is_deleted = 0',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => CustomerInstallmentPlanEntity.fromMap(r)).toList();
  }

  @override
  Future<List<CustomerInstallmentEntity>> getInstallmentsForCustomer(String customerId) async {
    final rows = await _executor.query(
      'customer_installments',
      where: 'customer_id = ? AND is_deleted = 0',
      whereArgs: [customerId],
      orderBy: 'due_date ASC, installment_no ASC',
    );
    return rows.map((r) => CustomerInstallmentEntity.fromMap(r)).toList();
  }

  @override
  Future<List<CustomerInstallmentEntity>> getInstallmentsForPlan(String planId) async {
    final rows = await _executor.query(
      'customer_installments',
      where: 'plan_id = ? AND is_deleted = 0',
      whereArgs: [planId],
      orderBy: 'installment_no ASC',
    );
    return rows.map((r) => CustomerInstallmentEntity.fromMap(r)).toList();
  }

  @override
  Future<List<CustomerInstallmentEntity>> getDueOrOverdueInstallments({int daysAhead = 7}) async {
    final now = DateTime.now();
    final thresholdDate = now.add(Duration(days: daysAhead));
    final thresholdStr = DateFormat('yyyy-MM-dd').format(thresholdDate);

    final rows = await _executor.query(
      'customer_installments',
      where: "status != 'paid' AND is_deleted = 0 AND due_date <= ?",
      whereArgs: [thresholdStr],
      orderBy: 'due_date ASC',
    );
    return rows.map((r) => CustomerInstallmentEntity.fromMap(r)).toList();
  }

  @override
  Future<Map<String, int>> getDueSummary() async {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final weekStr = DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 7)));

    final overdueRows = await _executor.rawQuery(
      "SELECT COUNT(*) as count FROM customer_installments WHERE status != 'paid' AND is_deleted = 0 AND due_date < ?",
      [todayStr],
    );
    final todayRows = await _executor.rawQuery(
      "SELECT COUNT(*) as count FROM customer_installments WHERE status != 'paid' AND is_deleted = 0 AND due_date = ?",
      [todayStr],
    );
    final upcomingRows = await _executor.rawQuery(
      "SELECT COUNT(*) as count FROM customer_installments WHERE status != 'paid' AND is_deleted = 0 AND due_date > ? AND due_date <= ?",
      [todayStr, weekStr],
    );

    return {
      'overdue': (overdueRows.first['count'] as num?)?.toInt() ?? 0,
      'today': (todayRows.first['count'] as num?)?.toInt() ?? 0,
      'upcoming': (upcomingRows.first['count'] as num?)?.toInt() ?? 0,
    };
  }

  @override
  Future<void> payInstallment({
    required String installmentId,
    required double amount,
    required String paymentMethod,
    String? note,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Tahsilat tutarı sıfırdan büyük olmalıdır.');
    }

    final rows = await _executor.query(
      'customer_installments',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [installmentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Taksit bulunamadı.');
    }

    final inst = CustomerInstallmentEntity.fromMap(rows.first);
    final newPaid = inst.paidAmount + amount;
    final isFullyPaid = newPaid >= (inst.amount - 0.01);
    final newStatus = isFullyPaid ? 'paid' : 'partial';
    final now = DateTime.now();
    final colTxId = 'trans-col-${_uuid.v4()}';
    final colDesc = note?.trim().isNotEmpty == true
        ? '${inst.installmentNo}. Taksit Tahsilatı (${note!.trim()})'
        : '${inst.installmentNo}. Taksit Tahsilatı';

    await _gateway.transaction(() async {
      // 1. Taksiti güncelle
      await _executor.update(
        'customer_installments',
        {
          'paid_amount': newPaid,
          'status': newStatus,
          'paid_at': isFullyPaid ? now.toIso8601String() : inst.paidAt?.toIso8601String(),
          'financial_transaction_id': colTxId,
          'updated_at': now.toIso8601String(),
          'is_synced': 0,
        },
        where: 'id = ?',
        whereArgs: [installmentId],
      );

      // 2. Tahsilat Fişini Kasaya ve Cari Hesaba İşle
      await _executor.insert('financial_transactions', {
        'id': colTxId,
        'type': 'collection',
        'customer_id': inst.customerId,
        'amount': amount,
        'paid_amount': amount,
        'debt_amount': 0.0,
        'reference_id': installmentId,
        'description': colDesc,
        'payment_method': paymentMethod,
        'is_deleted': 0,
        'is_synced': 0,
        'created_at': now.toIso8601String(),
      });

      await SyncOutboxV4.enqueue(
        _executor,
        entityType: 'financial_transaction',
        entityId: colTxId,
        operation: 'UPSERT',
        payload: {
          'id': colTxId,
          'type': 'collection',
          'customer_id': inst.customerId,
          'amount': amount,
          'paid_amount': amount,
          'debt_amount': 0.0,
          'reference_id': installmentId,
          'description': colDesc,
          'payment_method': paymentMethod,
          'created_at': now.toIso8601String(),
        },
      );

      // 3. Plandaki tüm taksitler ödendi mi kontrol et
      final remainingInPlan = await _executor.rawQuery(
        "SELECT COUNT(*) as count FROM customer_installments WHERE plan_id = ? AND status != 'paid' AND is_deleted = 0",
        [inst.planId],
      );
      final remainingCount = (remainingInPlan.first['count'] as num?)?.toInt() ?? 0;
      if (remainingCount == 0) {
        await _executor.update(
          'customer_installment_plans',
          {
            'status': 'completed',
            'updated_at': now.toIso8601String(),
            'is_synced': 0,
          },
          where: 'id = ?',
          whereArgs: [inst.planId],
        );
      }
    });
  }

  @override
  Future<void> cancelPlan(String planId) async {
    final now = DateTime.now();
    await _gateway.transaction(() async {
      await _executor.update(
        'customer_installment_plans',
        {
          'status': 'cancelled',
          'is_deleted': 1,
          'updated_at': now.toIso8601String(),
          'is_synced': 0,
        },
        where: 'id = ?',
        whereArgs: [planId],
      );
      await _executor.update(
        'customer_installments',
        {
          'status': 'cancelled',
          'is_deleted': 1,
          'updated_at': now.toIso8601String(),
          'is_synced': 0,
        },
        where: 'plan_id = ?',
        whereArgs: [planId],
      );
    });
  }

  DateTime _addMonths(DateTime date, int months) {
    var year = date.year;
    var month = date.month + months;
    while (month > 12) {
      year++;
      month -= 12;
    }
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final day = date.day > daysInMonth ? daysInMonth : date.day;
    return DateTime(year, month, day);
  }
}
