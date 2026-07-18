import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:serenutos/domain/services/math_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/events/domain_event.dart';
import 'package:serenutos/domain/events/event_publisher.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/audit_log_service.dart';

class PaymentService {
  final ICustomerRepository _customerRepository;
  final IFinancialTransactionRepository _transactionRepository;
  final EventPublisher _eventPublisher;
  final AuditLogService? _auditLogService;

  PaymentService({
    required ICustomerRepository customerRepository,
    required IFinancialTransactionRepository transactionRepository,
    required EventPublisher eventPublisher,
    AuditLogService? auditLogService,
  })  : _customerRepository = customerRepository,
        _transactionRepository = transactionRepository,
        _eventPublisher = eventPublisher,
        _auditLogService = auditLogService;

  final _random = Random();
  String _generateTxId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}${_random.nextInt(10000).toString().padLeft(4, '0')}';

  Future<bool> _isDuplicateTransaction(String referenceId, String type) async {
    if (referenceId.isEmpty) return false;
    // İSTEK 3 DÜZELTMESİ: findAll().any() yerine existsByReferenceId() SQL sorgusu.
    // Tüm transaction geçmişi RAM'e yüklenmiyor; COUNT(*) ile O(1) duplicate check.
    return _transactionRepository.existsByReferenceId(referenceId, type);
  }

  /// Processes payments for a sale.
  /// Updates customer balance (decreases it if debt is incurred) and records transaction.
  Future<void> processSalePayment({
    required String saleId,
    required String customerId,
    required double totalAmount,
    required double paidAmount,
    required String paymentMethod,
  }) async {
    if (await _isDuplicateTransaction(saleId, 'sale')) {
      return; // Idempotency check: Already processed
    }

    // Update successful sale timestamp and max timestamp seen for time travel checks
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setString('last_successful_sale', now.toIso8601String());
      final maxTimeStr = prefs.getString('max_timestamp_seen');
      if (maxTimeStr != null) {
        final currentMax = DateTime.tryParse(maxTimeStr);
        if (currentMax != null && now.isAfter(currentMax)) {
          await prefs.setString('max_timestamp_seen', now.toIso8601String());
        }
      } else {
        await prefs.setString('max_timestamp_seen', now.toIso8601String());
      }
    } catch (e) {
      debugPrint('[PaymentService] Timestamp güncelleme hatası: $e');
    }

    final debt = totalAmount - paidAmount;

    final transactionId = _generateTxId('trans');
    await _transactionRepository.create(
      FinancialTransactionEntity(
        id: transactionId,
        type: 'sale',
        customerId: customerId,
        amount: totalAmount,
        paidAmount: paidAmount,
        debtAmount: debt > 0 ? debt : 0,
        date: DateTime.now(),
        referenceId: saleId,
      ),
    );

    if (paidAmount > 0) {
      int parsedPaymentId = 0;
      try {
        parsedPaymentId =
            int.parse(transactionId.replaceAll(RegExp(r'[^0-9]'), ''));
      } catch (e) {
        debugPrint('[PaymentService] ID parse hatası: $e');
      }

      _eventPublisher.publish(PaymentRecordedEvent(
        paymentId: parsedPaymentId,
        customerId: 0, // aggregate field compatibility
        amount: paidAmount,
      ));
    }
  }

  /// Records a partial payment against an existing sale.
  /// Updates customer balance (increases it by paid amount) and records payment transaction.
  Future<void> recordPartialPayment({
    required String saleId,
    required String customerId,
    required double amount,
    required String method,
    required double currentPaidAmount,
    required double totalAmount,
  }) async {
    final newPaidAmount = currentPaidAmount + amount;
    // DÜZELTME: .abs() kaldırıldı — fazla ödeme (overpayment) borç olarak kayıt edilmemeliydi.
    // remaining > 0  → hâlâ borç var
    // remaining <= 0 → ya tam ödeme ya da fazla ödeme (alacak)
    final remaining = totalAmount - newPaidAmount;
    final remainingDebt = remaining > 0 ? remaining : 0.0;
    final overpayment = remaining < 0 ? remaining.abs() : 0.0;

    final transactionId = _generateTxId('trans');
    await _transactionRepository.create(
      FinancialTransactionEntity(
        id: transactionId,
        type: 'payment',
        customerId: customerId,
        amount: amount,
        paidAmount: amount,
        debtAmount: remainingDebt,
        date: DateTime.now(),
        referenceId: saleId,
        metadata: overpayment > 0 ? {'overpayment': overpayment} : null,
      ),
    );

    int parsedPaymentId = 0;
    try {
      parsedPaymentId =
          int.parse(transactionId.replaceAll(RegExp(r'[^0-9]'), ''));
    } catch (e) {
      debugPrint('[PaymentService] ID parse hatası (partial): $e');
    }

    _eventPublisher.publish(PaymentRecordedEvent(
      paymentId: parsedPaymentId,
      customerId: 0,
      amount: amount,
    ));
  }

  Future<void> processSaleCancellation({
    required String saleId,
    required String customerId,
    required double totalAmount,
    required double paidAmount,
  }) async {
    if (await _isDuplicateTransaction(saleId, 'cancellation')) {
      return; // Idempotency check: Already processed
    }

    final debt = totalAmount - paidAmount;

    await _transactionRepository.create(
      FinancialTransactionEntity(
        id: _generateTxId('trans-cancel'),
        type: 'cancellation',
        customerId: customerId,
        amount: totalAmount,
        paidAmount: paidAmount,
        debtAmount: debt,
        date: DateTime.now(),
        referenceId: saleId,
      ),
    );

    await _auditLogService?.log(
      action: 'sale_cancelled',
      details: jsonEncode({
        'saleId': saleId,
        'customerId': customerId,
        'totalAmount': totalAmount,
        'paidAmount': paidAmount,
      }),
    );
  }

  /// Revises an order payment without mutating the append-only ledger.
  /// The old debt is reversed and the revised debt is recorded as a new sale.
  Future<void> reviseOrderPayment({
    required String orderId,
    required String oldCustomerId,
    required String newCustomerId,
    required double totalAmount,
    required double paidAmount,
  }) async {
    final oldTransactions =
        await _transactionRepository.getByCustomerId(oldCustomerId);
    final oldSales = oldTransactions.where(
      (tx) => tx.referenceId == orderId && tx.type == 'sale',
    );

    if (oldSales.isNotEmpty) {
      final oldSale = oldSales.last;
      await _transactionRepository.create(FinancialTransactionEntity(
        id: _generateTxId('trans-revision-reverse'),
        type: 'cancellation',
        customerId: oldSale.customerId,
        amount: oldSale.amount,
        paidAmount: oldSale.paidAmount,
        debtAmount: oldSale.debtAmount,
        date: DateTime.now(),
        referenceId: orderId,
        metadata: {'reason': 'order_revision', 'reverses': oldSale.id},
      ));
    }

    final debt = MathEngine.calculateDebt(totalAmount, paidAmount);
    await _transactionRepository.create(FinancialTransactionEntity(
      id: _generateTxId('trans-revision-sale'),
      type: 'sale',
      customerId: newCustomerId,
      amount: totalAmount,
      paidAmount: paidAmount,
      debtAmount: debt,
      date: DateTime.now(),
      referenceId: orderId,
      metadata: {'reason': 'order_revision'},
    ));
  }

  /// Records general customer collection (tahsilat).
  /// Increases customer balance (meaning decreases debt).
  Future<void> recordCollection({
    required String customerId,
    required double amount,
    required String method,
    String? notes,
  }) async {
    final transactionId = _generateTxId('trans-coll');
    await _transactionRepository.create(
      FinancialTransactionEntity(
        id: transactionId,
        type: 'collection',
        customerId: customerId,
        amount: amount,
        paidAmount: amount,
        debtAmount: 0,
        date: DateTime.now(),
        metadata: notes != null ? {'notes': notes} : null,
      ),
    );

    int parsedPaymentId = 0;
    try {
      parsedPaymentId =
          int.parse(transactionId.replaceAll(RegExp(r'[^0-9]'), ''));
    } catch (e) {
      debugPrint('[PaymentService] ID parse hatası (collection): $e');
    }

    _eventPublisher.publish(PaymentRecordedEvent(
      paymentId: parsedPaymentId,
      customerId: 0,
      amount: amount,
    ));

    // Fetch updated customer to compute remaining debt for the domain event
    double remainingDebt = 0.0;
    try {
      final customer = await _customerRepository.findById(customerId);
      if (customer != null && customer.balance < 0) {
        remainingDebt = customer.balance.abs();
      }
    } catch (e) {
      debugPrint('[PaymentService] Müşteri bakiye sorgulama hatası: $e');
    }

    _eventPublisher.publish(CollectionRecordedEvent(
      collectionIdStr: transactionId,
      customerIdStr: customerId,
      amount: amount,
      remainingDebt: remainingDebt,
    ));
  }

  /// Processes refund for returned items.
  /// Credites customer balance or cash refund transaction.
  Future<void> processRefund({
    required String saleId,
    required String customerId,
    required double refundTotal,
    required String refundMethod,
  }) async {
    if (await _isDuplicateTransaction(saleId, 'refund')) {
      return; // Idempotency check: Already processed
    }

    await _transactionRepository.create(
      FinancialTransactionEntity(
        id: _generateTxId('trans-refund'),
        type: 'refund',
        customerId: customerId,
        amount: refundTotal,
        paidAmount: refundMethod == 'cash' ? refundTotal : 0,
        debtAmount: 0,
        date: DateTime.now(),
        referenceId: saleId,
      ),
    );
  }
}
