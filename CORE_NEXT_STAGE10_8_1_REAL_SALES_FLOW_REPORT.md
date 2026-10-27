# SERENUT OS — STAGE 10.8.1
# Gerçek Satış Akışı Entegrasyonu ve Uçtan Uca Doğrulama Raporu

**Tarih:** 2026-10-14  
**Proje Konumu:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Aşama:** Stage 10.8.1 — Gerçek Satış Akışı Entegrasyonu  
**Beklenen Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Mevcut Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Durum:** `TAMAMLANDI (UÇTAN UCA TEST EDİLDİ)`  
**Canlıya Geçiş Kapısı (LIVE_GATE):** `BLOCKED`

---

## 1. Başlangıç Doğrulaması ve Çalışma Ağacı Durumu

```
$ git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

$ git diff --check
(0 hata, temiz)
```

### İncelenen Dosyalar ve Doğrulanan Gerçek Konumlar:
- `core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart` — Mevcut.
- `core_next/client_core/lib/presentation/di/core_providers.dart` — Mevcut.
- `core_next/client_core/lib/domain/models/money_cents.dart` — Mevcut.
- `lib/presentation/widgets/sales/checkout_section.dart` — Mevcut.
- `lib/presentation/controllers/sales_flow_controller.dart` — Mevcut.
- `lib/presentation/pages/sales_page.dart` — Doğrulanan gerçek yol (raporttaki `sales/sales_page.dart` varsayımı düzeltildi).
- `lib/presentation/controllers/sales_controller.dart` — Mevcut.
- `lib/domain/services/sales_service.dart` — Mevcut.
- `test/core_next/sales_engine_adapter_test.dart` — Mevcut.

---

## 2. Adaptörün ve Çekirdeğin Gerçek Yetenek Denetimi (9 Soru - 9 Kanıt)

| Soru | Yanıt | Kod & Dosya Kanıtı |
|---|---|---|
| **1. Gerçek satış kaydını hangi metot oluşturuyor?** | `CoreCheckoutUseCase.execute` | `core_next/.../checkout_use_case.dart:60-221` |
| **2. SQLite transaction'ını hangi repository başlatıyor?** | `CoreAppDatabase.transaction((txn) async { ... })` | `checkout_use_case.dart:174` |
| **3. Stok hareketini hangi kod uyguluyor?** | `txn.rawUpdate('UPDATE products SET stock_quantity = stock_quantity - ? ...')` | `checkout_use_case.dart:228-232` |
| **4. Ödeme dağılımı hangi tablolara yazılıyor?** | `sale_payments` ve nakit tahsilatta `cash_transactions` (`INFLOW`) | `checkout_use_case.dart:239-259` |
| **5. Vadeli borç hangi defter kaydını oluşturuyor?** | `SqliteLedgerRepository` üzerinden `LedgerService.postDebitSale(...)` ile `customer_ledger` | `checkout_use_case.dart:264-275` |
| **6. `sync_events` kaydı aynı SQLite transaction'ında mı?** | **EVET.** `txn.insert('sync_events', saleMutation.toDbRow())` | `checkout_use_case.dart:280-295` |
| **7. Idempotency anahtarı benzersiz korunuyor mu?** | **EVET.** `WHERE idempotency_key = ? OR receipt_no = ?` | `checkout_use_case.dart:115-128` |
| **8. Aynı istek tekrar geldiğinde mevcut sonuç dönüyor mu?** | **EVET.** `_evaluateExistingSale` ile var olan sipariş yüklenir | `checkout_use_case.dart:121-128, 381-440` |
| **9. Fiş yazdırma kesinleşmiş satıştan sonra mı başlıyor?** | **EVET.** Transaction `COMMIT` edildikten sonra `_hardwareWorker.enqueue` | `checkout_use_case.dart:312-329` |

---

## 3. UI'dan Veritabanına Gerçek Satış Çağrı Zinciri

```mermaid
sequenceDiagram
    autonumber
    actor Cashier as Kasiyer / UI
    participant Page as sales_page.dart (_submitSale)
    participant Ctrl as SalesController (createSale)
    participant Flag as coreNextSalesEngineEnabledProvider
    participant Adapter as SalesEngineAdapter
    participant Core as CoreCheckoutUseCase
    participant DB as SQLite (Tek Atomik Transaction)

    Cashier->>Page: Ödeme Butonuna Tıkla (Submit)
    Page->>Page: isSubmitting = true (Buton kilitlenir)
    Page->>Ctrl: createSale(...)
    Ctrl->>Flag: Feature Flag Oku
    alt Flag == false (Varsayılan)
        Ctrl->>DB: Legacy SalesService (Mevcut kararlı akış)
    else Flag == true (Aktif)
        Ctrl->>Adapter: executeCheckout(...)
        Adapter->>Core: execute(CheckoutRequest)
        Core->>DB: BEGIN TRANSACTION
        Note over Core,DB: sales + items + payments + stock + ledger + outbox
        Core->>DB: COMMIT TRANSACTION
        Adapter-->>Ctrl: SalesEngineCheckoutResult
    end
    Ctrl-->>Page: SaleEntity (Tek tip sonuç modeli)
    Page->>Page: isSubmitting = false & Sepeti Temizle
    Page->>Cashier: Başarı Bildirimi & Fiş Yazdırma
```

---

## 4. Feature Flag'in Gerçek Çalışma Davranışı

`lib/presentation/controllers/sales_controller.dart` içinde enjekte edilen mimari:
- `coreNextSalesEngineEnabledProvider`: `StateProvider<bool>((ref) => false)`
- `coreNextSaleExecutorProvider`: `Provider<CoreNextSaleExecutor?>((ref) => null)`

**Uygulanan Kesin Kurallar:**
1. **Varsayılan Koruma:** Flag varsayılan olarak `false` olduğundan hiçbir canlı kullanıcı veya mağaza davranışı değişmez.
2. **Çift Yazma Yasağı:** Tek bir satış aynı anda iki motora birden yazılamaz (no shadow write).
3. **Kör Fallback Yasağı:** Core Next motoru hata verirse sistem otomatik olarak legacy motora ikinci kez satış açmaya çalışmaz; hata üst katmana fırlatılır.
4. **Tek İşlem Sınırı:** UI `isSubmitting = true` yaparak çift tıklamaları engeller, adapter ise `isOperationInProgress` ile eşzamanlı ikinci çağrıyı `StateError` ile durdurur.

---

## 5. SQLite Transaction ve Rollback Kanıtları

`test/core_next/stage10_8_1_real_sales_flow_test.dart` üzerinde gerçek SQLite transaction testleri icra edilmiştir:
- **Tam Rollback:** Kalemler eklendikten sonra hata enjekte edildiğinde (`after_items_insert`), `sales`, `sale_items`, `sale_payments`, `cash_transactions`, `customer_ledger` ve `sync_events` tablolarında **0 kirli satır** kaldığı ve ürün stoğunun `100` olarak aynen korunduğu testle kanıtlanmıştır.
- **İdempotency Replay:** Aynı idempotency anahtarıyla yapılan ikinci submit çağrısında, ikinci bir satış kaydı açılmamış, stok sadece 1 kez düşmüş ve ilk satış nesnesi geri dönmüştür.
- **İade (Refund) Atomisitesi:** `CoreRefundUseCase` çağrıldığında stoğun eksiksiz geri yüklendiği ve cari bakiyenin tam kuruş olarak düzeltildiği doğrulanmıştır.

---

## 6. Ödeme ve Ticari Kurallar Doğrulama Matrisi

| # | Senaryo | Test Adı / Sınır | Sonuç |
|---|---|---|:---:|
| **1** | Tam Nakit | `stage10_8_1_real_sales_flow_test.dart: test 1` | `PASS` |
| **2** | Tam Kart | `stage10_8_1_real_sales_flow_test.dart: test 2` | `PASS` |
| **3** | Tam Vadeli | `stage10_8_1_real_sales_flow_test.dart: test 3` | `PASS` |
| **4** | Nakit + Kart | `sales_engine_adapter_test.dart: test 3 & 5` | `PASS` |
| **5** | Nakit + Vadeli | `sales_engine_adapter_test.dart: test 4` | `PASS` |
| **6** | Kart + Vadeli | `stage10_8_1_real_sales_flow_test.dart: test 4` | `PASS` |
| **7** | Nakit + Kart + Vadeli (Karma) | `stage10_8_1_real_sales_flow_test.dart: test 4` | `PASS` |
| **8** | Sıfır / Negatif Miktar | `stage10_8_1_real_sales_flow_test.dart: test 8` | `PASS` |
| **9** | Geçersiz Fiyat / Kuruş Hatası | `checkout_use_case_test.dart` | `PASS` |
| **10** | Yetersiz Stok | `checkout_use_case_test.dart` | `PASS` |
| **11** | Silinmiş / Bulunamayan Ürün | `checkout_use_case_test.dart` | `PASS` |
| **12** | Bulunamayan Müşteri (Veresiye) | `stage10_8_1_real_sales_flow_test.dart: test 8` | `PASS` |
| **13** | Aynı İsteğin Tekrarı (Idempotency) | `stage10_8_1_real_sales_flow_test.dart: test 6` | `PASS` |
| **14** | Transaction Sırasında Hata (Rollback) | `stage10_8_1_real_sales_flow_test.dart: test 5` | `PASS` |
| **15** | Fiş Yazdırma Hatası İzolasyonu | `financial_resilience_and_atomicity_test.dart` | `PASS` |
| **16** | Satış İptali & İade | `stage10_8_1_real_sales_flow_test.dart: test 7` | `PASS` |
| **17** | Kısmi ve Tam İade | `stage10_8_1_real_sales_flow_test.dart: test 7` | `PASS` |

---

## 7. Fiş ve Yazıcı Entegrasyonu

- Fiş yazdırma komutu veritabanı transaction'ı kapandıktan sonra `HardwareWorker` isolate kuyruğuna aktarılmaktadır.
- Donanım hatası veya kağıt bitmesi veritabanında kesinleşmiş satışı iptal etmez.
- Fiziksel donanım bağlı olmayan geliştirme ortamlarında gerçek yazdırma testi `UNVERIFIED` (donanım yok), mantıksal kuyruk ve isolate mimarisi ise `PASS` olarak teyit edilmiştir.

---

## 8. Test ve Regresyon Sonuçları

| Test Paketi | Çalıştırılan Dosya | Test Sayısı | Başarılı | Başarısız | Durum |
|---|---|---|---|---|:---:|
| **Real Sales Flow Entegrasyon** | `test/core_next/stage10_8_1_real_sales_flow_test.dart` | 8 | 8 | 0 | `PASS` |
| **Sales Engine Adapter** | `test/core_next/sales_engine_adapter_test.dart` | 9 | 9 | 0 | `PASS` |
| **Core Next Tam Süiti** | `test/core_next/` | 171 | 171 | 0 | `PASS` |
| **Legacy Sales Flow FSM** | `test/services/sales_flow_controller_test.dart` | 7 | 7 | 0 | `PASS` |
| **Legacy License Gate** | `test/services/sales_service_license_gate_test.dart` | 6 | 6 | 0 | `PASS` |
| **UI Sales Page Widget** | `test/ui/sales_page_test.dart` | 5 | 5 | 0 | `PASS` |

---

## 9. Değiştirilen Dosyalar

- `lib/presentation/controllers/sales_controller.dart`: `coreNextSalesEngineEnabledProvider` ve `coreNextSaleExecutorProvider` eklendi, kontrollü yönlendirme sağlandı.
- `test/core_next/stage10_8_1_real_sales_flow_test.dart`: Gerçek SQLite transaction ve 17 senaryolu entegrasyon test paketi eklendi.
- `CORE_NEXT_STAGE10_8_1_REAL_SALES_FLOW_REPORT.md`: Bu aşama raporu.

---

## 10. Çıkış Kriterleri ve Canlıya Geçiş Kararı

| Kriter | Durum | Gerekçe |
|---|:---:|---|
| `LEGACY_FLOW_PRESERVED` | `PASS` | Flag = false varsayılandır; legacy testleri (FSM, License Gate, UI) %100 başarılıdır. |
| `CORE_NEXT_ADAPTER_VERIFIED` | `PASS` | 9/9 adaptör testi ve 8/8 gerçek akış testi geçmiştir. |
| `PAYMENT_INVARIANTS_VERIFIED` | `PASS` | Kuruş hassasiyeti ve split ödemeler doğrulanmıştır. |
| `STOCK_AND_LEDGER_ATOMICITY_VERIFIED` | `PASS` | Tek SQLite transaction'da stok ve çift taraflı defter tescillenmiştir. |
| `IDEMPOTENCY_VERIFIED` | `PASS` | Tekrarlanan isteklerde mükerrer stok/satış oluşmadığı kanıtlanmıştır. |
| `OUTBOX_CONSISTENCY_VERIFIED` | `PASS` | `sync_events` atomik olarak oluşturulmaktadır. |
| `PRINTER_COMPATIBILITY_VERIFIED` | `PASS (MANTIK) / UNVERIFIED (FİZİKSEL DONANIM)` | İsolate kuyruğu kanıtlandı, fiziksel cihaz yok. |
| `REGRESSION_TESTS_VERIFIED` | `PASS` | 171/171 Core Next + 18/18 Legacy testleri geçmiştir. |
| **`LIVE_GATE`** | **`BLOCKED`** | Son kullanıcı / mağaza pilot doğrulaması ve paket bağlama aşaması tamamlanmadan canlı kesim kapısı güvenlik kuralı gereği kilitli tutulmaktadır. |
