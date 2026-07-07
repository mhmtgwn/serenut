// lib/domain/services/data_integrity_service.dart
import 'package:flutter/foundation.dart' show compute;
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

class DataIntegrityService {
  final ICustomerRepository _customerRepository;
  final IFinancialTransactionRepository _transactionRepository;
  final IDatabaseHealthRepository? _healthRepository;
  final TelemetryService _telemetryService;

  DataIntegrityService({
    required ICustomerRepository customerRepository,
    required IFinancialTransactionRepository transactionRepository,
    IDatabaseHealthRepository? healthRepository,
    TelemetryService? telemetryService,
  })  : _customerRepository = customerRepository,
        _transactionRepository = transactionRepository,
        _healthRepository = healthRepository,
        _telemetryService = telemetryService ?? TelemetryService();

  Future<DatabaseHealthReport> checkDatabaseHealth() async {
    if (_healthRepository == null) {
      return const DatabaseHealthReport(
        orphanedSaleItemsCount: 0,
        orphanedOrderItemsCount: 0,
        orphanedOrderPaymentsCount: 0,
        orphanedTransactionsCount: 0,
        negativeStockProductsCount: 0,
        customerBalanceDriftsCount: 0,
        duplicateUuidsCount: 0,
      );
    }
    return _healthRepository!.checkHealth();
  }

  Future<void> repairDatabaseHealth() async {
    if (_healthRepository != null) {
      await _healthRepository!.repairHealth();
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Verify that customer's actual balance matches the mathematically expected
  /// balance derived from the financial transaction ledger entries.
  ///
  /// Returns `true` when the invariant holds.
  /// On drift detection, logs a `silent_data_corruption_alarm` telemetry event.
  Future<bool> verifyLedgerInvariant(String customerId) async {
    final customer = await _customerRepository.findById(customerId);
    if (customer == null) return true;

    final transactions = await _transactionRepository.getByCustomerId(customerId);
    final expectedBalance = calculateExpectedBalance(transactions);

    // Floating-point tolerance: 0.01 TL
    final diff = (customer.balance - expectedBalance).abs();
    if (diff > 0.01) {
      await _telemetryService.logStructured(
        event: 'silent_data_corruption_alarm',
        level: LogLevel.critical,
        metadata: {
          'customerId': customerId,
          'actualBalance': customer.balance,
          'expectedBalance': expectedBalance,
          'drift': diff,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      return false;
    }
    return true;
  }

  /// Rebuilds customer balance from the financial transaction log (State Replay).
  /// Writes the corrected value back to the database.
  Future<double> rebuildCustomerBalance(String customerId) async {
    final transactions = await _transactionRepository.getByCustomerId(customerId);
    final expectedBalance = calculateExpectedBalance(transactions);

    final customer = await _customerRepository.findById(customerId);
    if (customer != null) {
      final updated = CustomerEntity(
        id: customer.id,
        name: customer.name,
        email: customer.email,
        phone: customer.phone,
        balance: expectedBalance,
        createdAt: customer.createdAt,
      );
      await _customerRepository.update(updated);
    }
    return expectedBalance;
  }

  /// Explains customer balance chronologically, detailing exact ledger transitions.
  Future<List<BalanceExplanationRecord>> explainCustomerBalance(String customerId) async {
    final transactions = await _transactionRepository.getByCustomerId(customerId);
    final chronoTxs = List<FinancialTransactionEntity>.from(transactions).reversed.toList();

    double running = 0.0;
    final List<BalanceExplanationRecord> records = [];

    for (final tx in chronoTxs) {
      String desc = '';
      if (tx.type == 'sale') {
        running -= tx.debtAmount;
        desc = '${tx.amount.toStringAsFixed(2)} TL değerinde satış yapıldı (Ödenen: ${tx.paidAmount.toStringAsFixed(2)} TL, Borç: ${tx.debtAmount.toStringAsFixed(2)} TL).';
      } else if (tx.type == 'payment') {
        running += tx.paidAmount;
        desc = '${tx.amount.toStringAsFixed(2)} TL kısmi ödeme alındı.';
      } else if (tx.type == 'cancellation') {
        running += tx.debtAmount;
        desc = '${tx.amount.toStringAsFixed(2)} TL değerinde satış iptal edildi (Müşteri borcu düşüldü: ${tx.debtAmount.toStringAsFixed(2)} TL).';
      } else if (tx.type == 'collection') {
        running += tx.paidAmount;
        desc = '${tx.amount.toStringAsFixed(2)} TL tahsilat alındı.';
      } else if (tx.type == 'refund') {
        if (tx.paidAmount == 0) {
          running += tx.amount;
        }
        desc = '${tx.amount.toStringAsFixed(2)} TL iade kaydı oluşturuldu (Yöntem: ${tx.paidAmount == 0 ? "Bakiye" : "Nakit"}).';
      } else {
        desc = 'İşlem tipi: ${tx.type}, Tutar: ${tx.amount.toStringAsFixed(2)} TL.';
      }

      records.add(BalanceExplanationRecord(
        transactionId: tx.id,
        type: tx.type,
        amount: tx.amount,
        paidAmount: tx.paidAmount,
        debtAmount: tx.debtAmount,
        date: tx.date,
        referenceId: tx.referenceId,
        runningBalance: running,
        description: desc,
      ));
    }

    return records;
  }

  /// Checks every customer for balance drift and auto-corrects them.
  ///
  /// Uses **adaptive chunking** to balance isolate throughput vs. memory pressure:
  ///
  /// | Dataset size | Chunk size | Rationale                        |
  /// |-------------|-----------|----------------------------------|
  /// | < 1,000     | 1,000     | Small — single batch, max speed   |
  /// | 1,000–5,000 | 500       | Medium — balanced                 |
  /// | 5,001–20,000| 300       | Large — memory-conscious          |
  /// | > 20,000    | 100       | Very large — tight memory guard   |
  Future<Map<String, double>> runGlobalDriftCheck({int? chunkSize}) async {
    final customers = await _customerRepository.findAll();
    final Map<String, double> correctedDrifts = {};

    // Adaptive chunk size based on total customer count
    final effectiveChunk = chunkSize ?? _adaptiveChunkSize(customers.length);
    // Process in chunks to bound per-batch isolate memory pressure
    for (var start = 0; start < customers.length; start += effectiveChunk) {
      final chunk = customers.sublist(
        start,
        (start + effectiveChunk).clamp(0, customers.length),
      );

      for (final customer in chunk) {
        final transactions =
            await _transactionRepository.getByCustomerId(customer.id);

        // Off-main-thread calculation — only serialized maps cross the isolate boundary
        final expectedBalance = await compute(
          _calculateBalanceInIsolate,
          transactions.map((tx) => tx.toMap()).toList(),
        );

        final diff = (customer.balance - expectedBalance).abs();
        if (diff > 0.01) {
          await _telemetryService.logStructured(
            event: 'silent_data_corruption_alarm',
            level: LogLevel.critical,
            metadata: {
              'customerId': customer.id,
              'actualBalance': customer.balance,
              'expectedBalance': expectedBalance,
              'drift': diff,
              'timestamp': DateTime.now().toIso8601String(),
            },
          );

          final updated = CustomerEntity(
            id: customer.id,
            name: customer.name,
            email: customer.email,
            phone: customer.phone,
            balance: expectedBalance,
            createdAt: customer.createdAt,
          );
          await _customerRepository.update(updated);
          correctedDrifts[customer.id] = expectedBalance;
        }
      }
    }

    return correctedDrifts;
  }

  // ── Static helpers ──────────────────────────────────────────────────────────

  /// Returns an adaptive chunk size based on the total record count.
  /// Smaller chunks for large datasets reduce per-isolate memory copy overhead.
  static int _adaptiveChunkSize(int totalCount) {
    if (totalCount <= 1000)  return 1000; // Small  — single pass, max speed
    if (totalCount <= 5000)  return 500;  // Medium — balanced
    if (totalCount <= 20000) return 300;  // Large  — memory-conscious
    return 100;                           // Very large — tight memory guard
  }

  /// Top-level function required by [compute] — operates on plain serialized
  /// maps so it can be sent safely across isolate message boundaries.
  static double _calculateBalanceInIsolate(List<Map<String, dynamic>> txMaps) {
    double calculated = 0.0;
    final sorted = txMaps.toList()
      ..sort((a, b) =>
          (a['created_at'] as String).compareTo(b['created_at'] as String));

    for (final tx in sorted) {
      final type   = tx['type']        as String? ?? '';
      final debt   = (tx['debt_amount']  as num?)?.toDouble() ?? 0.0;
      final paid   = (tx['paid_amount']  as num?)?.toDouble() ?? 0.0;
      final amount = (tx['amount']       as num?)?.toDouble() ?? 0.0;

      if (type == 'sale') {
        calculated -= debt;
      } else if (type == 'payment') {
        calculated += paid;
      } else if (type == 'cancellation') {
        calculated += debt;
      } else if (type == 'collection') {
        calculated += paid;
      } else if (type == 'refund' && paid == 0) {
        calculated += amount;
      }
    }
    return calculated;
  }

  /// In-process (lightweight) balance calculation from entity objects.
  /// Used by [verifyLedgerInvariant] and [rebuildCustomerBalance].
  static double calculateExpectedBalance(
      List<FinancialTransactionEntity> transactions) {
    double calculated = 0.0;
    // Reversed → oldest first
    final chronoTxs =
        List<FinancialTransactionEntity>.from(transactions).reversed.toList();

    for (final tx in chronoTxs) {
      if (tx.type == 'sale') {
        calculated -= tx.debtAmount;
      } else if (tx.type == 'payment') {
        calculated += tx.paidAmount;
      } else if (tx.type == 'cancellation') {
        calculated += tx.debtAmount;
      } else if (tx.type == 'collection') {
        calculated += tx.paidAmount;
      } else if (tx.type == 'refund') {
        if (tx.paidAmount == 0) calculated += tx.amount;
      }
    }
    return calculated;
  }
}

class BalanceExplanationRecord {
  final String transactionId;
  final String type;
  final double amount;
  final double paidAmount;
  final double debtAmount;
  final DateTime date;
  final String? referenceId;
  final double runningBalance;
  final String description;

  BalanceExplanationRecord({
    required this.transactionId,
    required this.type,
    required this.amount,
    required this.paidAmount,
    required this.debtAmount,
    required this.date,
    this.referenceId,
    required this.runningBalance,
    required this.description,
  });
}
