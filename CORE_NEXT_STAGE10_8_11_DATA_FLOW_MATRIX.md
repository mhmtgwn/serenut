# SERENUT OS — STAGE 10.8.11 DATA FLOW MATRIX
## Dual-DB Split Kapatma Sonrası Veri Akış ve Yetkili Kaynak Matrisi

**Tarih:** 2026-10-15  
**Kapsam:** UI Katmanı, StateNotifier/Controller'lar, Domain Servisleri, Repository Sağlayıcıları ve SQLite Veritabanları (`serenut_pos.db` vs `serenut_core_v2.db`).

---

## 1. VERİ AKIŞ ŞEMASI (DATA FLOW ARCHITECTURE)

```
                            [ KULLANICI ARAYÜZÜ (UI) ]
                                    │
                                    ▼
       ┌───────────────── coreNextSalesEngineEnabledProvider ─────────────────┐
       │                                                                      │
       ▼ (false - Legacy Mod)                                                 ▼ (true - Core Next Mod)
[ Legacy Satış Servisi ]                                            [ Core Next Bridge & Adapter ]
       │                                                                      │
       ▼                                                                      ▼
[ sqlite_repositories.dart ]                                        [ core_next_*_repository.dart ]
       │                                                                      │
       ▼                                                                      ▼
( serenut_pos.db )                                                  ( serenut_core_v2.db )
```

---

## 2. MODÜL VE İŞLEM BAZINDA YETKİLİ VERİ KAYNAĞI MATRİSİ

| Modül / İşlem | Legacy Mod (`flag = false`) | Core Next Mod (`flag = true`) | Yetkili Tablolar (`serenut_core_v2.db`) | Idempotency / Atomiklik Garantisi |
|---|---|---|---|---|
| **Ürün Listeleme & Arama** | `SqliteProductRepository` (`serenut_pos.db`) | `CoreNextProductRepository` (`serenut_core_v2.db`) | `products`, `categories` | SQLite `COLLATE NOCASE` & `sqliteTurkishFold` |
| **Ürün Ekleme / Güncelleme** | `SqliteProductRepository` | `CoreNextProductRepository` | `products`, `sync_events` | `ON CONFLICT DO UPDATE` (In-Place UPSERT) |
| **Stok Görüntüleme & Düşümü** | `SqliteProductRepository` | `CoreNextProductRepository` / `CoreCheckoutUseCase` | `products.stock_quantity` | Transaction içinde `stock_quantity >= quantity` denetimi |
| **Müşteri Listeleme & Arama** | `SqliteCustomerRepository` | `CoreNextCustomerRepository` | `customers`, `ledger_entries` | Telefon numarası normalizasyonu ve kuruş bazlı bakiye |
| **Müşteri Borç / Vadeli Bakiye** | `customers.balance` | `customers.balance_cents` + `ledger_entries` | `customers`, `ledger_entries` | Çift yönlü muhasebe defteri (Double-entry ledger) |
| **Tahsilat İşlemi** | `SqliteFinancialTransactionRepository` | `CoreNextFinancialTransactionRepository` | `ledger_entries`, `customers` | Idempotent transaction; mükerrer işlemde bakiye ikinci kez değişmez |
| **Kasa Satışı (Nakit / Kart)** | `SalesService.createSale` | `CoreNextSalesBridge.createSaleExecutor` | `sales`, `sale_items`, `sale_payments`, `cash_transactions` | Tek atomik SQLite transaction; rollback güvencesi |
| **Veresiye Satış** | `SalesService` + Cari güncelleme | `CoreCheckoutUseCase` | `sales`, `sale_items`, `sale_payments`, `ledger_entries` | Müşteri seçimi zorunlu; `ledger_entries` borç kaydı ve `balance_cents` düşümü tek transaction'da |
| **İade İşlemi (Tam / Kısmi)** | `_salesService.returnItems` | `SalesController.returnItems` -> `CoreRefundUseCase` | `sales` (negatif kayıt), `sale_items`, `products`, `sync_events` | `originalSaleId` ve `idempotencyKey` ile miktar aşım ve mükerrer iade engeli |
| **Senkronizasyon Tetikleme** | `SyncService.sync()` (`sync_outbox_v4`) | `coreNextSyncExecutorProvider` (`sync_events`) | `sync_events` | Tek outbox kuyruğu; çifte gönderim engellendi |

---

## 3. PROVİDER BAĞIMLILIK VE DELEGE ZİNCİRİ

### 3.1. Ürün Deposu Sağlayıcısı (`productRepositoryProvider`)
```dart
final productRepositoryProvider = FutureProvider<IProductRepository>((ref) async {
  final coreRepo = ref.watch(coreNextProductRepositoryProvider);
  if (coreRepo != null) {
    return coreRepo; // Core Next aktifken serenut_core_v2.db
  }
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteProductRepository(gateway); // Legacy modda serenut_pos.db
});
```

### 3.2. Müşteri Deposu Sağlayıcısı (`customerRepositoryProvider`)
```dart
final customerRepositoryProvider = FutureProvider<ICustomerRepository>((ref) async {
  final coreRepo = ref.watch(coreNextCustomerRepositoryProvider);
  if (coreRepo != null) {
    return coreRepo; // Core Next aktifken serenut_core_v2.db
  }
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteCustomerRepository(gateway); // Legacy modda serenut_pos.db
});
```

### 3.3. Finansal Hareket Deposu (`financialTransactionRepositoryProvider`)
```dart
final financialTransactionRepositoryProvider = FutureProvider<IFinancialTransactionRepository>((ref) async {
  final coreRepo = ref.watch(coreNextFinancialTransactionRepositoryProvider);
  if (coreRepo != null) {
    return coreRepo; // Core Next aktifken ledger_entries tablosu
  }
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteFinancialTransactionRepository(gateway); // Legacy mod
});
```

### 3.4. Satış ve İade Yürütücüsü (`sales_controller.dart`)
```dart
// Satış
if (isCoreNext) {
  final executor = ref.read(coreNextSaleExecutorProvider);
  if (executor == null) throw StateError('CoreNext executor hazır değil');
  return await executor(...);
} else {
  return await _salesService.createSale(...);
}

// İade
if (isCoreNext) {
  final refundExecutor = ref.read(coreNextRefundExecutorProvider);
  if (refundExecutor == null) throw StateError('CoreNext refund executor hazır değil');
  await refundExecutor(...);
} else {
  await _salesService.returnItems(...);
}
```

---

## 4. TUTARLILIK VE İKİLİ ÇELİŞKİ ÖNLEME MEKANİZMASI

1. **İki Bağımsız Stok Kaynağının Önlenmesi:**
   Core Next aktif edildiğinde, `productsControllerProvider`'ın kullandığı `productRepositoryProvider`, `CoreNextProductRepository`'ye delege olur. Dolayısıyla POS ekranı stoğu `serenut_core_v2.db`'den okur ve satış sonrasında aynı veritabanından eksiltir.
2. **Körlemesine Ters Kopyalamanın Önlenmesi:**
   Satış esnasında işlem sadece bir veritabanına yazılır; Core Next'teki satış eski DB'ye runtime esnasında kopyalanmaz. Cutover öncesi tüm geçmiş `MigrationBridgeEngine` ile taşınır.
3. **Mükerrer Finansal Kayıt Koruması:**
   Tahsilat işlemlerinde `IFinancialTransactionRepository.create`, `ledger_entries`'e `id` bazlı `ConflictAlgorithm.ignore` ile yazar ve `balance_cents` güncellemesini sadece kayıt ilk defa eklenmişse işletir.
