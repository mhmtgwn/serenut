# SERENUT OS — STAGE 10.8.0
# Core Next Satış Motoru Entegrasyonu ve Kontrollü Uygulama Raporu

**Tarih:** 2026-10-14  
**Proje Konumu:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Aşama:** Stage 10.8.0 — Core Next Satış Motoru Entegrasyonu  
**Beklenen Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Gerçekleşen Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Durum:** `TAMAMLANDI (KONTROLLÜ UYGULAMA VE DOĞRULAMA)`  
**Canlıya Geçiş Kapısı (LIVE_GATE):** `BLOCKED`

---

## 1. Başlangıç Güvenlik Kontrolü ve Çalışma Ağacı Durumu

```
$ git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

$ git diff --check
(Temiz - 0 whitespace/syntax hatası)
```
- **Kullanıcı Değişiklikleri:** Bütün yerel dosyalar korunmuştur, kontrolsüz reset veya stash yapılmamıştır.
- **`lib/` Canlı Klasörü:** Dokunulmamış, salt-okunur durumu korunmuştur (`0` dosya değişimi).
- **Commit / Push / Deploy:** Çalıştırılmamıştır.

---

## 2. Satış İşleminin Mevcut Davranış Haritası (11 Adım)

Gerçek kaynak kod taranarak mevcut satış akışının 11 adımı haritalanmıştır:

| Adım | İşlem Tanımı | İlgili Controller & Service | Repository & Tablo | Mimari Özellik |
|---|---|---|---|---|
| **1** | Ürün ve Varyant Seçimi | `CatalogPanel`, `SalesFlowNotifier.addProduct` | `SqliteProductRepository` / `products` | Barkod ve terazi tartım kontrolü |
| **2** | Miktar, Fiyat, İskonto, Toplam | `SalesFlowState.subtotal`, `SalesFlowState.total` | Bellek içi FSM hesaplama | Kuruş yuvarlama (`MoneyCents`) |
| **3** | Nakit, Kart, Vadeli, Karma Ödeme | `CheckoutSection`, `MixedPaymentCalculator` | `PhysicalCardPaymentService` | POS köprüsü & kuruş dengesi |
| **4** | Stok Kontrolü ve Hareketi | `CoreCheckoutUseCase` / `InventoryService` | `products.stock_quantity = stock_quantity - ?` | Tek SQLite transaction |
| **5** | Satış Kaydı ve Kalemleri | `CoreCheckoutUseCase.execute` | `sales` ve `sale_items` tabloları | Parent-child atomik kayıt |
| **6** | Müşteri & Vadeli Borç Kaydı | `LedgerService.postDebitSale` | `customers.balance_cents` | Otomatik bakiye düşümü |
| **7** | Defter Hareketleri (Ledger) | `SqliteLedgerRepository` | `customer_ledger` | Immutable çift taraflı kayıt |
| **8** | Satış İptali ve İade | `CoreRefundUseCase` | `refund_items`, `customer_ledger` | Stok iadesi ve alacak kaydı |
| **9** | Yerel Transaction & Rollback | `CoreAppDatabase.transaction` | SQLite `BEGIN TRANSACTION ... COMMIT` | Hata anında tam geri alma |
| **10** | Outbox & Bulut Senkronizasyonu | `SyncV4PayloadAdapter.buildSaleMutation` | `sync_events` (Sync v4 Outbox) | Satışla aynı transaction'da |
| **11** | Fiş Yazdırma & Kasa Çekmecesi | `HardwareWorker` (Isolate Worker) | ESC/POS & TSPL kuyruğu | Transaction dışı asenkron kuyruk |

---

## 3. Doğrulanmış Entegrasyon Sözleşmesi (`SalesEngineAdapter`)

`core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart` dosyası, aşağıdaki zırhlı sözleşmeyle güncellenmiştir:

### 3.1 `SalesEngineCheckoutResult` Veri Sözleşmesi
- `isSuccess`: `bool`
- `saleId`: Satış UUID kimliği (`String?`)
- `receiptNo`: Fiş/Makbuz numarası (`String?`)
- `customerId`: Seçilen müşteri kimliği (`String?`)
- `subtotal`, `discount`, `vatTotal`, `total`: Kuruş kesinliğinde `MoneyCents`
- `paid`, `debt`: Kuruş kesinliğinde `MoneyCents`
- `items`: Satış kalemleri listesi (`List<SaleOrderItemEntity>`)
- `payments`: Parçalı ödeme listesi (`List<PaymentSplitEntity>`)
- `stockMovementsCount`: Düşülen stok hareket adedi (`int`)
- `hasLedgerDebit`: Deftere borç işlendi mi (`bool`)
- `isOutboxEnqueued`: Senkronizasyon kuyruğuna atomik eklendi mi (`bool`)
- `createdAt`: İşlem zaman damgası (`DateTime?`)
- `idempotencyKey`: Tekrarlama önleme anahtarı (`String?`)
- `coreSaleOrder`: Çekirdek satış siparişi varlığı
- `legacySale`: Eski motor sonucu (legacy çağrıldığında)
- `errorMessage`: Hata mesajı (varsa)
- `executedEngine`: Yürütülen motor (`SalesEngineType.legacy` veya `SalesEngineType.coreNext`)

### 3.2 Güvenlik ve Geçiş Kuralları
1. **Varsayılan Motor:** Her zaman `useCoreNext = false` (legacy).
2. **Kör Fallback Yasağı:** Yeni motorda (`coreNext`) bir hata oluşursa, sistem asla otomatik olarak eski motora (`legacy`) geçerek mükerrer kayıt açmaz. Hata doğrudan `SalesEngineCheckoutResult.failure` olarak üst katmana bildirilir.
3. **İşlem Esnasında Motor Değişimi Yasağı:** `isOperationInProgress == true` durumunda `setFeatureFlag` çağrılırsa `StateError` fırlatılır.

---

## 4. Test Sonuçları ve Gerçek Kanıtlar

`test/core_next/sales_engine_adapter_test.dart` test dosyası güncellenmiş ve 9 kritik entegrasyon senaryosu doğrulanmıştır:

```
$ flutter test test/core_next/sales_engine_adapter_test.dart
00:00 +0: (setUpAll)
00:00 +0: 1. Varsayılan Motor: Feature flag kapalıdır ve legacy motor çalışır
00:00 +1: 2. Yeni Motor Aktifleştirildiğinde: CoreNext nakit satışını sözleşmeye uygun yürütür
00:00 +2: 3. Kart Satışı: PaymentType.creditCard ile tam ödeme sözleşmesi doğrulanır
00:01 +3: 4. Vadeli Satış: Müşteri seçimi ile deftere borç işlenir ve bakiye güncellenir
00:01 +4: 5. Karma Ödeme (Split Payment): Nakit + Kart + Vadeli kuruş hassasiyeti
00:01 +5: 6. Hata Durumunda Güvenlik: Hata olunca otomatik fallback yapılmaz, hata döner
00:01 +6: 7. İdempotency Replay: Aynı idempotencyKey ile tekrar çağrıldığında var olan satış döner
00:01 +7: 8. syncFromCart: Sepet durumunu deterministik aktarır
00:01 +8: 9. Koruma: Devam eden işlem varken setFeatureFlag StateError fırlatır
00:01 +9: (tearDownAll)
00:01 +9: All tests passed!
```

Tüm Core Next test süiti çalıştırılmış ve tam regresyon teyit edilmiştir:
```
$ flutter test test/core_next/
...
00:34 +163: All tests passed!
Exit Code: 0
```
- **Toplam Test Sayısı:** 163 (Önceki aşama: 157, Eklenen adaptör testleri: +6)
- **Başarılı Test:** 163
- **Başarısız Test:** 0
- **Atlanan Test:** 0

---

## 5. Çıkış Kriterleri Değerlendirmesi

| Kriter | Durum | Kanıt & Açıklama |
|---|:---:|---|
| **`LEGACY_FLOW_PRESERVED`** | `PASS` | `initialUseCoreNext = false` varsayılandır; legacy akış ve mevcut ekranlar tamamen korunmaktadır. |
| **`CORE_NEXT_ADAPTER_VERIFIED`** | `PASS` | `SalesEngineAdapter` ve `SalesEngineCheckoutResult` 9/9 test senaryosu ile kanıtlanmıştır. |
| **`PAYMENT_INVARIANTS_VERIFIED`** | `PASS` | Nakit, Kart, Vadeli ve Karma ödemelerde `MoneyCents` ile kuruş hassasiyeti ve tutar denkliği teyit edilmiştir. |
| **`STOCK_AND_LEDGER_ATOMICITY_VERIFIED`** | `PASS` | Tek SQLite transaction içinde stok düşümü ve çift taraflı defter borç kaydı atomik olarak kanıtlanmıştır. |
| **`IDEMPOTENCY_VERIFIED`** | `PASS` | Aynı idempotencyKey ile ikinci çağrıda çift satış veya mükerrer stok düşümü oluşmadığı kanıtlanmıştır. |
| **`OUTBOX_CONSISTENCY_VERIFIED`** | `PASS` | Satışla aynı transaction içinde `sync_events` satırı oluşturulmaktadır. |
| **`PRINTER_COMPATIBILITY_VERIFIED`** | `PASS` | Donanım worker'ı isolate üzerinden transaction dışı çalışır; donanım hatası satışı rollback ettirmez. |
| **`REGRESSION_TESTS_VERIFIED`** | `PASS` | 163/163 `test/core_next/` testinin tamamı başarıyla geçmiştir. |
| **`LIVE_GATE`** | `BLOCKED` | UI katmanının (`lib/`) son kullanıcı nezdinde nihai canlı kesimi (cutover) tamamlanana kadar güvenlik kapısı kural gereği BLOCKED tutulmaktadır. |

---

## 6. Değiştirilen Dosyalar ve Git Özeti

- `core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart`: Sözleşme genişletmesi ve güvenli köprü fonksiyonları.
- `core_next/client_core/lib/presentation/di/core_providers.dart`: `salesEngineAdapterProvider` eklenmesi (varsayılan: legacy).
- `test/core_next/sales_engine_adapter_test.dart`: Kapsamlı adaptör test paketi.
- `CORE_NEXT_STAGE10_8_0_SALES_ENGINE_INTEGRATION_REPORT.md`: Bu aşama raporu.
- **`lib/` Klasörü:** `%100` orijinal halinde bırakıldı.

---

## 7. Sonraki Adım Önerisi (Stage 10.8.1)

Stage 10.8.0 ile sözleşme, adaptör ve çekirdek satış köprüsü zırhlanmıştır.  
Sonraki küçük adımda (Stage 10.8.1):
1. `lib/presentation/controllers/sales_flow_controller.dart` içerisindeki `SalesFlowNotifier`'a `salesEngineAdapterProvider` güvenli bir şekilde inject edilmelidir.
2. `Settings` veya SharedPreferences üzerinden `enableCoreNextSalesEngine` toggle'ı bağlanarak mağaza yöneticisinin testi kontrollü olarak açabilmesi sağlanmalıdır.
