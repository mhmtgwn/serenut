// core_next/client_core/lib/domain/services/ledger_service.dart
import '../models/money_cents.dart';
import '../models/core_entities.dart';

abstract interface class ILedgerRepository {
  Future<CustomerEntity?> getCustomer(String customerId);
  Future<void> updateCustomerBalance(String customerId, MoneyCents newBalance);
  Future<void> insertLedgerEntry(LedgerEntryEntity entry);
}

/// Saf Dart Çift Taraflı Cari Defter Motoru (Double-Entry Ledger Engine).
/// 
/// SQLite Trigger'larını tamamen ortadan kaldırır.
/// Müşteri borç ve alacak hesaplamalarını veritabanı motorunun gizli SQL kodlarından alıp,
/// şeffaf, deterministik ve %100 test edilebilir Dart domain katmanına taşır.
class LedgerService {
  final ILedgerRepository _repository;

  const LedgerService(this._repository);

  /// Vadeli satış borç kaydı oluşturur.
  /// Müşterinin bakiyesi borç tutarı kadar azalır (negatife doğru gider).
  Future<LedgerEntryEntity> postDebitSale({
    required String entryId,
    required String customerId,
    required String saleId,
    required MoneyCents debtAmount,
    required String receiptNo,
    required DateTime timestamp,
  }) async {
    if (debtAmount.value <= 0) {
      throw ArgumentError.value(
          debtAmount, 'debtAmount', 'Vadeli borç tutarı pozitif olmalıdır.');
    }

    final customer = await _repository.getCustomer(customerId);
    if (customer == null) {
      throw StateError('Müşteri bulunamadı: ID $customerId');
    }

    // Yeni Bakiye = Eski Bakiye - Borç Tutarı
    final newBalance = customer.balance - debtAmount;

    // Kredi limiti kontrolü (Eğer limit tanımlıysa)
    if (customer.creditLimit.value > 0) {
      final totalDebt = -newBalance;
      if (totalDebt > customer.creditLimit) {
        throw StateError(
          'Müşteri kredi limiti aşıldı! Limit: ${customer.creditLimit.formatTL()}, İstenen Borç: ${totalDebt.formatTL()}',
        );
      }
    }

    final entry = LedgerEntryEntity(
      id: entryId,
      customerId: customerId,
      referenceSaleId: saleId,
      entryType: LedgerEntryType.debitSale,
      amount: debtAmount,
      balanceAfter: newBalance,
      description: 'Fiş #$receiptNo Vadeli Satış',
      createdAt: timestamp,
    );

    // İşlemleri kaydet
    await _repository.insertLedgerEntry(entry);
    await _repository.updateCustomerBalance(customerId, newBalance);

    return entry;
  }

  /// Müşteriden borç tahsilatı (Nakit / Havale / Kredi Kartı) kaydeder.
  /// Müşterinin bakiyesi tahsilat tutarı kadar artar (borcu kapanır).
  Future<LedgerEntryEntity> postCollection({
    required String entryId,
    required String customerId,
    required MoneyCents collectionAmount,
    required String description,
    required DateTime timestamp,
  }) async {
    if (collectionAmount.value <= 0) {
      throw ArgumentError.value(
          collectionAmount, 'collectionAmount', 'Tahsilat tutarı pozitif olmalıdır.');
    }

    final customer = await _repository.getCustomer(customerId);
    if (customer == null) {
      throw StateError('Müşteri bulunamadı: ID $customerId');
    }

    // Yeni Bakiye = Eski Bakiye + Tahsil Edilen Miktar
    final newBalance = customer.balance + collectionAmount;

    final entry = LedgerEntryEntity(
      id: entryId,
      customerId: customerId,
      entryType: LedgerEntryType.creditCollection,
      amount: collectionAmount,
      balanceAfter: newBalance,
      description: description,
      createdAt: timestamp,
    );

    await _repository.insertLedgerEntry(entry);
    await _repository.updateCustomerBalance(customerId, newBalance);

    return entry;
  }

  /// Ürün iadesi sonucu müşteriye alacak kaydı açar.
  Future<LedgerEntryEntity> postRefund({
    required String entryId,
    required String customerId,
    required String saleId,
    required MoneyCents refundAmount,
    required String description,
    required DateTime timestamp,
  }) async {
    if (refundAmount.value <= 0) {
      throw ArgumentError.value(
          refundAmount, 'refundAmount', 'İade tutarı pozitif olmalıdır.');
    }

    final customer = await _repository.getCustomer(customerId);
    if (customer == null) {
      throw StateError('Müşteri bulunamadı: ID $customerId');
    }

    final newBalance = customer.balance + refundAmount;

    final entry = LedgerEntryEntity(
      id: entryId,
      customerId: customerId,
      referenceSaleId: saleId,
      entryType: LedgerEntryType.creditRefund,
      amount: refundAmount,
      balanceAfter: newBalance,
      description: description,
      createdAt: timestamp,
    );

    await _repository.insertLedgerEntry(entry);
    await _repository.updateCustomerBalance(customerId, newBalance);

    return entry;
  }
}
