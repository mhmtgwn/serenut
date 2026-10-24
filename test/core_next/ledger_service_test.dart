// test/core_next/ledger_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';

class MockLedgerRepository implements ILedgerRepository {
  final Map<String, CustomerEntity> customers = {};
  final List<LedgerEntryEntity> entries = [];

  @override
  Future<CustomerEntity?> getCustomer(String customerId) async {
    return customers[customerId];
  }

  @override
  Future<void> updateCustomerBalance(
      String customerId, MoneyCents newBalance) async {
    final existing = customers[customerId]!;
    customers[customerId] = CustomerEntity(
      id: existing.id,
      name: existing.name,
      balance: newBalance,
      creditLimit: existing.creditLimit,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> insertLedgerEntry(LedgerEntryEntity entry) async {
    entries.add(entry);
  }
}

void main() {
  group('MoneyCents Value Object Tests', () {
    test('TL to Kuruş ve Kuruş to TL dönüşümünde sıfır kayıp olmalıdır', () {
      final m1 = MoneyCents.fromLira(12.50);
      expect(m1.value, 1250);
      expect(m1.toLira(), 12.50);
      expect(m1.formatTL(), '12,50 ₺');
    });

    test('Float yuvarlama hataları olmamalıdır (0.1 + 0.2 problemi)', () {
      final a = MoneyCents.fromLira(0.10); // 10 kuruş
      final b = MoneyCents.fromLira(0.20); // 20 kuruş
      final sum = a + b;
      expect(sum.value, 30);
      expect(sum.formatTL(), '0,30 ₺');
    });

    test('KDV yüzde hesabı kuruş hassasiyetinde doğru yuvarlamalıdır', () {
      final price = MoneyCents(10055); // 100.55 TL
      final vat = price.percentage(20); // %20 KDV
      expect(vat.value, 2011); // 20.11 TL
    });

    test('formatTL negatif ve pozitif tutarları doğru Türkçe formatında göstermelidir', () {
      final expectations = {
        -101: '-1,01 ₺',
        -100: '-1,00 ₺',
        -99: '-0,99 ₺',
        -50: '-0,50 ₺',
        -1: '-0,01 ₺',
        0: '0,00 ₺',
        1: '0,01 ₺',
        50: '0,50 ₺',
        99: '0,99 ₺',
        100: '1,00 ₺',
        101: '1,01 ₺',
      };

      for (final entry in expectations.entries) {
        final formatted = MoneyCents(entry.key).formatTL();
        expect(formatted, entry.value,
            reason: '${entry.key} kuruş için formatTL çıktısı hatalı!');
      }
    });
  });


  group('LedgerService (Trigger-Free Double Entry Accounting) Tests', () {
    late MockLedgerRepository repo;
    late LedgerService service;

    setUp(() {
      repo = MockLedgerRepository();
      service = LedgerService(repo);

      // Başlangıçta 0 bakiyeli, 1000 TL limitli müşteri
      repo.customers['cust-1'] = CustomerEntity(
        id: 'cust-1',
        name: 'Ahmet Yılmaz',
        balance: MoneyCents.zero,
        creditLimit: MoneyCents.fromLira(1000.0), // 100,000 kuruş limit
        updatedAt: DateTime.now(),
      );
    });

    test('Vadeli satış yapıldığında müşteri bakiyesi tam kuruş olarak azalmalı ve defter kaydı oluşmalıdır', () async {
      final entry = await service.postDebitSale(
        entryId: 'entry-1',
        customerId: 'cust-1',
        saleId: 'sale-100',
        debtAmount: MoneyCents.fromLira(150.50), // 15050 kuruş
        receiptNo: '2026-001',
        timestamp: DateTime.now(),
      );

      expect(entry.balanceAfter.value, -15050);
      expect(repo.customers['cust-1']!.balance.value, -15050);
      expect(repo.entries.length, 1);
      expect(repo.entries.first.entryType, LedgerEntryType.debitSale);
    });

    test('Borç tahsilatı yapıldığında bakiye düzelmelidir', () async {
      // Önce 100 TL borçlandır
      await service.postDebitSale(
        entryId: 'entry-1',
        customerId: 'cust-1',
        saleId: 'sale-100',
        debtAmount: MoneyCents.fromLira(100.0),
        receiptNo: '2026-001',
        timestamp: DateTime.now(),
      );

      // Sonra 60 TL tahsil et
      final colEntry = await service.postCollection(
        entryId: 'entry-2',
        customerId: 'cust-1',
        collectionAmount: MoneyCents.fromLira(60.0),
        description: 'Kısmi Nakit Tahsilat',
        timestamp: DateTime.now(),
      );

      expect(colEntry.balanceAfter.value, -4000); // Kalan borç 40 TL (-4000 kuruş)
      expect(repo.customers['cust-1']!.balance.value, -4000);
      expect(repo.entries.length, 2);
    });

    test('Kredi limiti aşıldığında işlem hata vermeli ve veritabanı kirlenmemelidir', () async {
      expect(
        () => service.postDebitSale(
          entryId: 'entry-overflow',
          customerId: 'cust-1',
          saleId: 'sale-999',
          debtAmount: MoneyCents.fromLira(1500.0), // 1000 TL limit üstü
          receiptNo: '2026-999',
          timestamp: DateTime.now(),
        ),
        throwsA(isA<StateError>()),
      );

      // Bakiye bozulmamalı
      expect(repo.customers['cust-1']!.balance.value, 0);
      expect(repo.entries.isEmpty, true);
    });
  });
}
