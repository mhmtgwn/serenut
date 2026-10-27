# SERENUT OS — STAGE 10.8.10 INDEPENDENT RUNTIME AUDIT REPORT

**Tarih:** 2026-10-15  
**Proje:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Aşama:** Stage 10.8.10 — Independent Runtime Audit, Full Data-Flow Verification & Cutover Readiness Gate  
**Nihai Değerlendirme:** **`READY_FOR_FURTHER_ISOLATED_TESTING`**  
*(Güvenlik ve Bütünlük Gerekçesi: Dört ana kusur [ADV-01..ADV-04] izole/köprü seviyesinde başarıyla giderilmiştir; ancak ürün kataloğu, cari defter ve iade akışlarının Core Next'e tam adaptasyonu tamamlanmadan körlemesine canlı cutover yapılamaz).*

---

## 1. YÖNETİCİ ÖZETİ VE MUTLAK GÜVENLİK GÜVENCELERİ

Stage 10.8.10 bağımsız denetimi, Stage 10.8.9'da giderildiği iddia edilen 4 kritik kusuru (ADV-01, ADV-02, ADV-03, ADV-04) bağımsız SQLite FFI testleriyle sınamış, ayrıca uygulamanın uçtan uca veri akış zincirini (`app_bootstrap` → `SalesController` → DB → UI Listesi → Ürün/Stok → Cari/Ledger → Fiş → Sync) kaynak kod düzeyinde denetlemiştir.

### Güvenlik Sınırları Uyumu
1. `coreNextSalesEngineEnabledProvider` varsayılan değeri kesinlikle `false` olarak korunmaktadır.
2. Üretim veritabanına (`serenut_pos.db`), canlı API'ye ve VPS sunucusuna dokunulmamıştır.
3. Gerçek kullanıcı verisi üzerinde migration veya rollback çalıştırılmamıştır; tüm denetimler izole geçici test veritabanlarında (`stage10_8_10_runtime_audit_test.dart`) yürütülmüştür.
4. Git commit, push, deploy veya canlı cutover yapılmamıştır.
5. Hiçbir test assertion'ı gevşetilmemiş veya silinmemiştir.

---

## 2. DÖRT KRİTİK KUSURUN BAĞIMSIZ DENETİMİ (ADV-01 – ADV-04)

### 2.1. ADV-01 — Migration UPSERT ve Veri Güncelliği
- **Denetim Bulgusu:** `MigrationBridgeEngine.dart` içerisindeki native `ON CONFLICT(id) DO UPDATE SET ...` (In-Place UPSERT) mantığı bağımsız test ile doğrulanmıştır.
- **Kanıt (`stage10_8_10_runtime_audit_test.dart` Test 1):**
  1. `prod-audit-1` (300 TL, stok 40) legacy DB'den Core Next'e taşındı.
  2. Core Next'te bu ürüne bağlı `sale_items` satırı (`item-audit-fk-1`) oluşturuldu (`FOREIGN KEY ON DELETE RESTRICT`).
  3. Legacy'de ürünün fiyatı 350 TL, stoğu 35, adı "Organik Zeytinyağı Sızma 1L" olarak güncellendi.
  4. İkinci migration çalıştırıldığında: SQLite `787 (FOREIGN KEY constraint failed)` hatası vermedi; hedef ürün silinmeden yerinde güncellendi (`price_cents = 35000`, `stock_quantity = 35`).
  5. Üçüncü migration çalıştırıldığında (idempotency): Veriler değişmedi, mükerrer kayıt oluşmadı.
- **Sonuç:** **`PASS`** (Kusur tamamen giderilmiştir).

### 2.2. ADV-02 — İade ve Rollback Idempotency
- **Denetim Bulgusu:** `ReverseMigrationEngine.rollbackToLegacy` akışında `refunded_amount` değerinin koşulsuz artım yerine `(SELECT COALESCE(SUM(amount), 0.0) FROM refunds WHERE sale_id = ?)` ile alt sorgu üzerinden hesaplanması doğrulanmıştır.
- **Kanıt (`stage10_8_10_runtime_audit_test.dart` Test 2):**
  1. 100 TL'lik satışa ait 40 TL'lik iade (`REF-REC-ORIG-100`) rollback edildi.
  2. Legacy `sales.refunded_amount` 40.0 TL oldu.
  3. Rollback ikinci kez (retry/crash recovery senaryosu) çalıştırıldı.
  4. Legacy `sales.refunded_amount` 80.0 TL'ye çıkmadı; tam 40.0 TL olarak korundu. Kalan net tutar 60.0 TL olarak doğrulandı.
- **Sonuç:** **`PASS`** (Kusur tamamen giderilmiştir).

### 2.3. ADV-03 — Çoklu ve Karma Ödeme Roundtrip Korunumu
- **Denetim Bulgusu:** Core Next `sale_payments` tablosundaki çoklu ödeme kalemlerinin, reverse migration ile legacy'de yapısal `sale_payments` tablosuna aktarılması ve ardından tekrar ileri migration yapıldığında kuruşu kuruşuna korunması doğrulanmıştır.
- **Kanıt (`stage10_8_10_runtime_audit_test.dart` Test 3):**
  1. 50 TL Nakit + 30 TL Kredi Kartı + 20 TL Vadeli = 100 TL satış Core Next'te oluşturuldu.
  2. Rollback sonrası legacy `sale_payments` tablosunda 3 satır (50.0 TL, 30.0 TL, 20.0 TL) olarak yapısal olarak saklandı.
  3. Core Next DB sıfırlanıp ileri migration çalıştırıldığında 3 ödeme kalemi (5.000 cents cash, 3.000 cents creditCard, 2.000 cents onAccount) eksiksiz geri yüklendi.
- **Sonuç:** **`PASS`** (Kusur tamamen giderilmiştir).

### 2.4. ADV-04 — Runtime Satış Repository Köprüsü
- **Denetim Bulgusu:** `coreNextSaleRepositoryProvider` ve `CoreNextSaleRepository` sınıfının `ISaleRepository` sözleşmesini `serenut_core_v2.db` üzerinde eksiksiz uyguladığı, `saleRepositoryProvider` üzerinden izleyen UI katmanının (`salesHistoryControllerProvider`, `saleDetailProvider`) Core Next satışlarını eksiksiz listelediği ve detaylandırdığı doğrulanmıştır.
- **Kanıt (`stage10_8_10_runtime_audit_test.dart` Test 4):**
  1. `CoreNextSaleRepository` provider container'a bağlandı.
  2. `saleRepositoryProvider.future.findAll()` çağrıldığında Core Next'e ait satış, kalemleri ve toplam tutarı (250.0 TL) anında okundu.
- **Sonuç:** **`PASS`** (Satış okuma köprüsü çalışmaktadır).

---

## 3. KRİTİK RUNTIME DENETİMİ: KALAN DUAL-DB SPLIT ALANLARI

Stage 10.8.10'un en önemli görevi, yalnızca satış repository'sinin yönlendirilmesini yeterli saymayıp tüm runtime akışını incelemektir. Yapılan kaynak kod denetiminde şu somut ayrışmalar tespit edilmiştir:

| Akış / Bileşen | Hangi DB'yi Kullanıyor? | Hangi Provider / Repository? | Core Next Aktifken Durum | Risk Derecesi |
|---|---|---|---|---|
| **Satış Yazma** (`SalesController.createSale`) | `serenut_core_v2.db` | `coreNextSaleExecutorProvider` | Yeni veritabanına yazar. | **GÜVENLİ** |
| **Satış Listesi / Detayı** (`SalesHistoryController`, `saleDetailProvider`) | `serenut_core_v2.db` | `saleRepositoryProvider` -> `CoreNextSaleRepository` | Yeni veritabanından okur. | **GÜVENLİ** |
| **Kasa Ekranı Ürün/Stok** (`ProductsController`, `salesProductsControllerProvider`) | `serenut_pos.db` | `productRepositoryProvider` -> `SqliteProductRepository` | **Legacy DB'den okur!** Satış Core Next'te stok düşerken POS ekranındaki stok `serenut_pos.db`'de kalır. | **YÜKSEK (Dual-DB Split)** |
| **Müşteri Bakiyesi / Cari** (`CustomersController`, `customerTransactionsProvider`) | `serenut_pos.db` | `customerRepositoryProvider` -> `SqliteCustomerRepository` | **Legacy DB'den okur!** Core Next'te vadeli satış `ledger_entries`'e yazılırken, cari kartı `serenut_pos.db`'deki eski bakiyeyi gösterir. | **YÜKSEK (Dual-DB Split)** |
| **İade / Ürün İadesi** (`SalesController.returnItems`) | `serenut_pos.db` | `_salesService.returnItems` -> `SqliteRefundMutationStore` | **Legacy DB'ye yazar!** Core Next'teki satışa ait iade legacy tablolara yazılır. | **YÜKSEK (Dual-DB Split)** |
| **Senkronizasyon (Sync V4)** | İstemci `syncProvider` `serenut_pos.db`'yi senkronize eder; `SyncV4PullWorker` ise `serenut_core_v2.db`'yi senkronize eder. | İki ayrı senkronizasyon motoru | İki veritabanı farklı kuyrukları izler. | **ORTA-YÜKSEK** |

### Bu Bulguların Anlamı Nedir?
- `coreNextSalesEngineEnabledProvider = true` yapıldığında satış okuma/yazma tutarlıdır; ANCAK stoklar, cari bakiyeler ve iade işlemleri legacy veritabanını kullanmaya devam etmektedir.
- **Sonuç:** Bütün uygulama tek yetkili Core Next veritabanına (`Single Source of Truth`) henüz tamamen geçmemiştir. Ürün ve cari repository'leri de `saleRepositoryProvider` gibi birer adaptör köprüsüyle Core Next DB'ye bağlanmadan veya uygulama açılışında tam migration çalıştırılmadan canlı cutover yapılamaz.

---

## 4. CANLIYA GEÇİŞİN (CUTOVER) ÖNÜNDEKİ SOMUT ENGELLER

1. **Ürün ve Cari Deposu Adaptasyonu:** `productRepositoryProvider` ve `customerRepositoryProvider` için de Core Next adaptörleri (`coreNextProductRepositoryProvider`, `coreNextCustomerRepositoryProvider`) bağlanmalıdır.
2. **Açılışta Otomatik Migration Tetikleyicisi:** `app_bootstrap.dart` içerisinde, eğer Core Next aktif edilmişse ve henüz veri taşınmamışsa `MigrationBridgeEngine.migrateFromLegacy()` işleminin otomatik yürütülmesi gerekmektedir.
3. **İade Akışı Yönlendirmesi:** `SalesController.returnItems` metodu, Core Next aktifken `RefundUseCase` motorunu çağırmalıdır.

---

## 5. ÇIKIŞ KARARI

### **`READY_FOR_FURTHER_ISOLATED_TESTING`**

- **Gerekçe:** ADV-01, ADV-02, ADV-03 ve ADV-04 izole testlerde %100 kanıtlanmış ve başarıyla geçmiştir. Ancak tam runtime veri akışı denetiminde ürün stokları, müşteri cari bakiyeleri ve iadelerin henüz Core Next DB'ye bağlanmadığı tespit edilmiştir. Sistem güvenli bir şekilde `false` bayrağıyla legacy çalışmaktadır; cutover öncesinde kalan 3 adaptasyonun izole testlerle tamamlanması gerekmektedir.
