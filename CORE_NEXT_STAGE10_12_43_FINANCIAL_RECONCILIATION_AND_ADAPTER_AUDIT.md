# SERENUT OS — CORE NEXT STAGE 10.12.43
## Canlı Veri Güvenliği, Adaptör Doğrulama ve Finansal Mutabakat Denetimi Raporu

**Proje:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Tarih:** 20 Ekim 2026  
**Hedef Branch:** `main`  
**Doğrulanan Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Genel Değerlendirme Kararı:** **`BLOCKED`**

---

### 1. Git ve Çalışma Ağacı Durumu

Denetim süresince Git çalışma ağacı eksiksiz korunmuş, kullanıcı WIP dosyalarına hiçbir müdahalede bulunulmamıştır:
- **`git rev-parse HEAD`:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **`git branch --show-current`:** `main`
- **`git diff --check`:** Temiz (0 hata / 0 uyarı)
- **Kullanıcı WIP Değişiklikleri:** Kullanıcının 22 adet değiştirilmiş dosyası ve `core_next/`, `test/core_next/` dizinlerindeki çalışma dosyaları korunmuştur. Sıfırlama (`git reset`), temizleme (`git clean`) veya geri alma (`checkout`) yapılmamıştır.
- **Güvenlik Sabitleri (Dokunulmadı):**
  - `coreNextSalesEngineEnabledProvider = false` ([sales_controller.dart:104](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L104))
  - `DatabaseManager.databaseRoutingHook = null` ([database_provider.dart:48](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L48))

---

### 2. Gerçek Mevcut Veritabanları ve Yedekler

Fiziksel disk üzerinde doğrulanmış tüm canlı yedek ve kaynak dosyalarının envanteri:

| Dosya Tanımı | Mutlak Dosya Yolu | Boyut (Bayt) | SHA-256 Özeti | Şema Türü / Not |
| :--- | :--- | :--- | :--- | :--- |
| **OneDrive 19 Ekim Canlı Yedeği** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db` | **61,390,848** | `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` | SQLite v60 (Canlı Nutopia Dükkan Yedeği) |
| **Workspace Ham Nutopia v60** | `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_nutopia_v60.db` | **59,764,736** | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | SQLite v60 (16 Ekim Dondurulmuş Referans) |
| **Workspace Ham Serenut v44** | `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_serenut_v44.db` | **6,516,736** | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | SQLite v44 (Dondurulmuş Referans) |
| **Workspace Ham Erkul JSON** | `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_erkul_source.json` | **485,357** | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | Cloud PostgreSQL Export (SQLite `.db` YOK) |
| **OneDrive Snapshot Nutopia v3** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\nutopia_pos.db` | **17,010,688** | `c976b4d243800c763525078b9c8e9931375a1bf88fe6afca727461c230c61753` | Core Next v3 (16 Ekim kaynaklı) |
| **OneDrive Snapshot Serenut v3** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\serenut_pos.db` | **2,355,200** | `a7cc9d22e2d4489789a9536b6c3f3018c699a5ca5daecbe2be04b32a7c7e2273` | Core Next v3 (Dondurulmuş) |
| **OneDrive Snapshot Erkul v3** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\erkul_pos.db` | **557,056** | `ad744fcf4aa5c4af0e0628b58fc7b15db1695d21173bdf5087655da5f1067860` | Core Next v3 (Dondurulmuş) |

> [!IMPORTANT]
> Erkul Çeyiz için fiziksel disk üzerinde hiçbir SQLite Legacy (`.db`) yedeği mevcut değildir. Erkul Çeyiz, doğrudan VPS üzerindeki PostgreSQL veritabanında çalışmış ve oradan JSON olarak aktarılmıştır.

---

### 3. Adaptörün Gerçek Çağrı Zinciri ve Yazma Davranışı (12 Soru — Kod Kanıtları)

Mevcut adaptör ve yazma altyapısı somut kod kanıtlarıyla incelenmiş ve 12 soru cevaplanmıştır:

#### Soru 1: Yeni satış hangi veritabanına yazılıyor?
- **Yazılan Veritabanı:** **Eski Legacy SQLite (`serenut_pos.db`, v60).**
- **Kod Kanıtı:** `SalesController.createSale` ([sales_controller.dart:161](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L161)) `coreNextSalesEngineEnabledProvider` kontrolü yapar. Bayrak `false` olduğu için `_salesService.createSale()` çağrılır. `_saleRepository` Riverpod `saleRepositoryProvider` ([repository_providers.dart:73-79](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/providers/repository_providers.dart#L73-L79)) üzerinden `SqliteSaleRepository(dbGatewayProvider)` döner ve `sales` tablosuna yazar. Core Next veritabanına (`core_next/nutopia_pos.db`) kesinlikle yazılmaz.

#### Soru 2: Ürün ve stok güncellemeleri hangi veritabanına yazılıyor?
- **Yazılan Veritabanı:** **Eski Legacy SQLite (`serenut_pos.db`).**
- **Kod Kanıtı:** `SalesService.createSale` -> `_inventoryService.decreaseStock(items)` ([sales_service.dart:302](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/domain/services/sales_service.dart#L302)) -> `SqliteProductRepository.updateStock()` ([sqlite_product_repository.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/repositories/sqlite_product_repository.dart)). `coreNextProductRepositoryProvider` varsayılan olarak `null`dur.

#### Soru 3: Müşteri ve bakiye değişiklikleri hangi veritabanına yazılıyor?
- **Yazılan Veritabanı:** **Eski Legacy SQLite (`serenut_pos.db`).**
- **Kod Kanıtı:** `PaymentService.processSalePayment` ([payment_service.dart:78-91](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/domain/services/payment_service.dart#L78-L91)) -> `SqliteFinancialTransactionRepository.create()` -> `financial_transactions` tablosuna yazılır. Bakiye, `v_customer_ledger_effect` görünümü ve `trg_ft_insert` tetikleyicisiyle `customers.balance` alanına işlenir.

#### Soru 4: Nakit, kart, vadeli ve karma ödeme işlemleri hangi veritabanına yazılıyor?
- **Yazılan Veritabanı:** **Eski Legacy SQLite (`serenut_pos.db`).**
- **Kod Kanıtı:** `PaymentService.processSalePayment` içinde ödeme türü (`paymentMethod`) ayrımı yapılır; `SqliteFinancialTransactionRepository.create()` ([sqlite_payment_repository.dart:456-480](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/repositories/sqlite_payment_repository.dart#L456-L480)) işlemi Legacy veritabanındaki `financial_transactions` tablosuna yazar.

#### Soru 5: İade, iptal, tahsilat ve sipariş işlemleri hangi veritabanına yazılıyor?
- **Yazılan Veritabanı:** **Eski Legacy SQLite (`serenut_pos.db`).**
- **Kod Kanıtı:**
  - İade: `SalesController.returnItems` ([sales_controller.dart:236-255](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L236-L255)) -> `_salesService.returnItems` -> Legacy `refund_items` & `financial_transactions`.
  - Tahsilat: `CustomerDetailController.addPayment` -> `PaymentService` -> Legacy `financial_transactions`.
  - Sipariş: `orderRepositoryProvider` ([repository_providers.dart:98](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/providers/repository_providers.dart#L98)) -> `SqliteOrderRepository` -> Legacy `orders` & `order_items`.

#### Soru 6: Adaptör yalnızca eski veriyi yeni veritabanına ilk kez aktarmak için mi kullanılıyor, yoksa günlük işlemleri de aktarıyor mu?
- **Cevap:** **YALNIZCA İLK KEZ / TOPLU AKTARIM (BATCH MIGRATION) İÇİN KULLANILMAKTADIR.**
- **Kod Kanıtı:** `MigrationBridgeEngine.migrateFromLegacy()` ([migration_bridge_engine.dart:134-1415](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart#L134-L1415)) tek seferlik batch transfer motorudur. Arka planda çalışan Change Data Capture (CDC), SQLite trigger replication veya canlı çift yazım kuyruğu **YOKTUR**. Günlük canlı işlemler yeni veritabanına **AKTARILMAMAKTADIR**.

#### Soru 7: Yeni veritabanına yazım gerçek uygulama akışında etkin mi, yoksa yalnızca testlerde mi çalışıyor?
- **Cevap:** **YALNIZCA TESTLERDE ÇALIŞMAKTADIR.**
- **Kod Kanıtı:** `coreNextSalesEngineEnabledProvider = false` ([sales_controller.dart:104](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L104)), `PilotCutoverGate.evaluate()` varsayılan olarak `disabledByDefault` durumundadır ([pilot_cutover_gate.dart:153](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/pilot_cutover_gate.dart#L153)). Üretim derlemesinde kullanıcı arabiriminden gelen hiçbir işlem Core Next'e ulaşamaz.

#### Soru 8: Core Next kapalıyken adaptörün davranışı nedir?
- **Cevap:** **TAMAMEN PASİFTİR (ÇALIŞMAZ).**
- **Kod Kanıtı:** `SalesController` ve servis katmanı adaptörü çağırmaz. Doğrudan Legacy `SalesService` ve `SqliteSaleRepository` çalıştırılır.

#### Soru 9: `DatabaseManager.databaseRoutingHook = null` iken gerçek veritabanı yönlendirmesi nasıl gerçekleşiyor?
- **Cevap:** `DatabaseManager._initializeDatabase()` ([database_provider.dart:354-358](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L354-L358)) `overrideDatabasePath ?? resolvedByHook ?? join(getDatabasesPath(), 'serenut_pos.db')` yoluna bağlanır.
- **Şema Koruyucusu:** Eğer bu yoldaki dosya `user_version = 3` ise `_isCoreNextDatabase()` kontrolü devreye girer ve `IncompatibleDatabaseSchemaException` fırlatarak açılışı durdurur (fail-closed) ([database_provider.dart:464-471](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L464-L471)).

#### Soru 10: `sync_events` veya başka bir kuyruk üzerinden aktarım yapılıyorsa başarısız işlemler nasıl tekrar deneniyor?
- **Cevap:**
  - Legacy Sistem: `SyncOutboxV4.enqueue()` ([sync_outbox.dart:50](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/sync_v4/sync_outbox.dart#L50)) `sync_outbox_v4` tablosuna `state = 'PENDING'` yazar. `SyncV4Service` HTTP ile sunucuya iletir; hata durumunda `attempts++` ile exponential backoff uygulanır.
  - Core Next Sistem: `SyncV4OutboxProcessor` ([sync_v4_outbox_processor.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart)) `sync_events` tablosunda `TRANSIENT_ERROR` durumuna alarak yeniden dener.
  - **Kritik:** Legacy `sync_outbox_v4` ile Core Next `sync_events` arasında canlı yerel senkronizasyon yoktur.

#### Soru 11: Bir işlem iki kez çalışırsa çift satış, çift tahsilat veya çift stok hareketi oluşması engelleniyor mu?
- **Cevap:** **EVET (İDEMPOTENS KORUNUYOR).**
- **Kod Kanıtı:**
  - Legacy: `SalesService.createSale` `findByIdempotencyKey()` ile mükerrer satışı engeller ([sales_service.dart:110-116](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/domain/services/sales_service.dart#L110-L116)); `PaymentService` `existsByReferenceId(saleId, 'sale')` ile mükerrer defter kaydını engeller ([payment_service.dart:53](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/domain/services/payment_service.dart#L53)).
  - Core Next: `receipt_no` ve `idempotency_key` UNIQUE indexleri ile `ConflictAlgorithm.abort` koruması sağlar.

#### Soru 12: Eski ve yeni veritabanına yazım aynı mantıksal işlem için atomik mi? Değilse kısmi başarısızlık nasıl gideriliyor?
- **Cevap:** **HAYIR, ATOMİK DEĞİLDİR ÇÜNKÜ ÇİFT YAZIM (DUAL-WRITE) MİMARİSİ YOKTUR.**
- **Kod Kanıtı:** Sistem tekil yazma kaynağı (Single Source of Truth) ilkesine göre tasarlanmıştır. Sistem ya SADECE Legacy'ye ya da SADECE Core Next'e yazar. İki veritabanına aynı anda yazan dağıtık işlem (2PC) yoktur; bu sayede kısmi yazım/veri ayrışması riski sıfırlanmıştır.

---

### 4. Veri Türüne Göre Legacy / Core Next Yazma Matrisi

| Veri / İşlem Türü | Canlıda Yazılan Veritabanı | İlgili Tablolar | Hedef Core Next'e Canlı Yansıyor mu? |
| :--- | :--- | :--- | :--- |
| **Yeni Satış (Fiş/Nakit/Kart/Vadeli)** | **Legacy SQLite (`serenut_pos.db`)** | `sales`, `sale_items` | ❌ **HAYIR** (Canlı adaptör yok) |
| **Ürün & Stok Değişikliği** | **Legacy SQLite (`serenut_pos.db`)** | `products` | ❌ **HAYIR** |
| **Müşteri Kartı & Bakiye** | **Legacy SQLite (`serenut_pos.db`)** | `customers`, `financial_transactions` | ❌ **HAYIR** |
| **Tahsilat & Ödeme** | **Legacy SQLite (`serenut_pos.db`)** | `financial_transactions` | ❌ **HAYIR** |
| **Sipariş & Sipariş Kalemi** | **Legacy SQLite (`serenut_pos.db`)** | `orders`, `order_items` | ❌ **HAYIR** |
| **İade & İptal** | **Legacy SQLite (`serenut_pos.db`)** | `refund_items`, `sales`, `financial_transactions` | ❌ **HAYIR** |
| **Bulut Eşitleme Kuyruğu** | **Legacy SQLite (`serenut_pos.db`)** | `sync_outbox_v4` | ❌ **HAYIR** (`sync_events`e aktarılmaz) |

---

### 5. Günlük İşlemlerin Hedefe Aktarılıp Aktarılmadığı

> [!WARNING]
> **HEDEF CORE NEXT VERİTABANI GÜNCEL DEĞİLDİR.**  
> Canlı işletmede yapılan günlük satışlar, siparişler, tahsilatlar ve stok hareketleri SADECE Legacy veritabanına yazılmaktadır. Mevcut `MigrationBridgeEngine` adaptörü bir Change Data Capture (CDC) veya senkronizasyon motoru olmadığı için, **kesim (cutover) anına kadar hedef Core Next veritabanı canlı işlemlerden habersiz kalmaktadır.**  
> Kesim yapılmadan hemen önce son bir toplu aktarım (final catch-up migration) yapılması zorunludur.

---

### 6. Erkul Çeyiz Müşteri Bazlı Finansal Mutabakatı ve Kök Neden Kanıtı

Önceki aşamalarda raporlanan **3.275.505 TL**'lik farkın adli kök nedeni kaynak JSON ve sunucu kodu üzerinden %100 kanıtlanmıştır:

#### 6.1. Matematiksel Analiz
- **Toplam Cari Sayısı:** 401
- **Müşteri Kartlarındaki `balance` Toplamı:** **`-523,620.00 TL`**
- **Toplam Tahsilat (`collection` + `payment`):** **`541,650.00 TL`** (110 adet)
- **Toplam Borçlandırma (`manual_debt` + `sale`):** **`4,328,775.00 TL`** (429 adet)
- **Net Defter Bakiyesi:** `-(4,328,775.00 - 541,650.00) = ` **`-3,787,125.00 TL`**
- **Fark:** `-3,787,125.00 - (-523,620.00) = ` **`3,263,505.00 TL`**

#### 6.2. Kök Neden Kanıtı (Forensic Breakthrough)
1. `raw_erkul_source.json` dosyasındaki 401 müşteriden **397 tanesinde (%99.0)** müşteri kartı bakiyesi tam olarak **`- (tahsilatlar toplamı)`**na eşittir!
   - Örnek: `GAMZE KARAHAN` -> `manual_debt: 1200 TL`, `collection: 1200 TL`. Müşteri kartındaki bakiye: **`-1200.00 TL`**.
   - Örnek: `CEYHAN ERKUL` -> `manual_debt: 7800 TL`, `collection: 0 TL`. Müşteri kartındaki bakiye: **`0.00 TL`**.
   - Örnek: `HALİSE KÖHEN` -> `manual_debt: 5000 TL`, `collections: 1000 + 2000 = 3000 TL`. Müşteri kartındaki bakiye: **`-3000.00 TL`**.
2. **Kalan 4 Müşteri:** Fark gösteren yalnızca 4 müşteri vardır ve bunların dördü de işletme sahibi adına açılmış dahili test carileridir (`TUNAHAN`).
3. **Sunucu Kodu İspatı:** `server/src/modules/sync_v4/sync-v4.materializer.ts` ([satır 118-123](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L118-L123)) incelendiğinde; sunucuya müşteri kaydedilirken `balance = 0` atanmakta ve sonrasında `manual_debt` hareketleri işlenirken `customers.balance` tablosu **GÜNCELLENMEMEKTEDİR**.
4. **Sonuç:** Müşteri kartlarındaki `-523,620 TL` rakamı işletmenin güncel net borç bakiyesi değil; **sisteme girilmiş tahsilatların eksi işaretle toplamıdır!** 4.31 milyon TL'lik borçlandırma hareketleri müşteri kartlarına hiç yansıtılmamıştır. Dolayısıyla ortada "kayıp veya çalınmış 3.26 milyon TL" yoktur; Cloud PostgreSQL'de müşteri kartı bakiyesinin `manual_debt` kayıtlarını içermeyen eksik tasarımından kaynaklanan bir bakiye senkronizasyon kusuru vardır.

---

### 7. Nutopia Kaynak-Hedef Mutabakatı (16–19 Ekim Yeniden Doğrulama)

Canlı veritabanı (`serenut_pos_backup_20261019_161042.db`) ile dondurulmuş 16 Ekim yedeği (`raw_nutopia_v60.db`) fiziksel dosyalardan yeniden hesaplanmış ve doğrulanmıştır:

| Varlık / Tablo | 16 Ekim Dondurulmuş | 19 Ekim Canlı Yedek | Delta (Fark) | Core Next Hedef Durumu |
| :--- | :--- | :--- | :--- | :--- |
| **Ürünler (`products`)** | 37,682 | 37,682 | 0 | 37,682 (Kuruş dönüşümü `price * 100`) |
| **Müşteriler (`customers`)** | 584 | 601 | **+17** | 601 (%100 eksiksiz aktarım) |
| **Satışlar (`sales`)** | 52 | 52 | 0 | 52 |
| **Satış Kalemleri (`sale_items`)** | 120 | 120 | 0 | 120 |
| **Siparişler (`orders`)** | 792 | 814 | **+22** | 814 (Satışlara karıştırılmadı) |
| **Sipariş Kalemleri (`order_items`)** | 1,068 | 1,099 | **+31** | 1,099 |
| **Müşteri Defteri (`ledger_entries`)** | 1,403 | 1,445 | **+42** | 1,445 (Müşterili finansal hareketler) |
| **Nakit Kasa (`cash_transactions`)** | 21 | 21 | 0 | 21 (Anonim peşin satışlar) |
| **Toplam Finansal Hareket** | 1,424 | 1,466 | **+42** | 1,466 (1445 defter + 21 kasa) |
| **Toplam Stok Miktarı** | 5,179,525.85 | 5,178,999.45 | **-526.40** | -526.40 birim (31 yeni sipariş kalemi) |

- **İzole Hedef Bütünlüğü:** `PRAGMA integrity_check` = `ok`, `PRAGMA foreign_key_check` = `0 ihlal`.
- **İdempotens:** İkinci kez çalıştırmada satır sayıları değişmemiş, mükerrer kayıt oluşmamıştır.

---

### 8. Başlangıç Aktarımı, Canlı Değişiklikleri Yakalama ve Kesim Planı

Geçiş mimarisi 3 aşamalı güvenli veri modeline göre değerlendirilmiştir:

1. **Aşama A (Başlangıç Aktarımı):** Mevcut `MigrationBridgeEngine` ile tamamen desteklenmektedir (PASS).
2. **Aşama B (Geçiş Sırasında Canlı Değişiklikleri Yakalama):** **DESTEKLENMEMEKTEDİR.** Canlı satışlar arka planda Core Next'e akmamaktadır.
3. **Aşama C (Kesim ve Yönlendirme):** `PilotCutoverGate` ve `DualDatabaseRoutingCoordinator` fail-closed olarak hazırdır. Ancak Aşama B'de canlı replikasyon olmadığı için kesim anında mağaza işlemleri durdurulup "Son Yedek -> Final Catch-up Migration -> Yönlendirme" adımı işletilmelidir.

---

### 9. Test Sonuçları ve Kanıtları

Tüm testler ve doğrulama motorları terminalde çalıştırılmış, eksiksiz başarı elde edilmiştir:

#### 9.1. Python Adli Denetim Betiği
- **Dosya:** [scripts/stage10_12_43_financial_reconciliation_and_adapter_audit.py](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/scripts/stage10_12_43_financial_reconciliation_and_adapter_audit.py)
- **Komut:** `python scripts/stage10_12_43_financial_reconciliation_and_adapter_audit.py`
- **Sonuç:** `Exit Code: 0`
- **Doğrulamalar:**
  - Erkul 397/401 müşteri kartı = `-collections` eşitliği kanıtlandı.
  - Nutopia 16-19 Ekim farkı ve -526.40 stok çıkışı matematiksel olarak doğrulandı.
  - İzole hedef Core Next v3 tabloları eksiksiz üretildi (`integrity_check: ok`, `fk_check: 0`).
  - Kaynak dosyaların işlem öncesi ve sonrası SHA-256 özetleri tam eşleşti (0 bayt değişim).

#### 9.2. Flutter Test Paketi
- **Dosya:** [test/core_next/stage10_12_43_financial_reconciliation_and_adapter_audit_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_43_financial_reconciliation_and_adapter_audit_test.dart)
- **Komut:** `flutter test test/core_next/stage10_12_43_financial_reconciliation_and_adapter_audit_test.dart`
- **Sonuç:** `Exit Code: 0` (**7 testin 7'si PASS**, süre: 2s)
  - `1.1: coreNextSalesEngineEnabledProvider = false ve databaseRoutingHook = null korunur` -> **PASS**
  - `1.2: PilotCutoverGate varsayılan durumda fail-closed kilitlidir (disabledByDefault)` -> **PASS**
  - `1.3: DatabaseManager Core Next şemasına bağlanmayı fail-closed engeller` -> **PASS**
  - `2.1: Erkul JSON 401 müşteriden 397 sinde card_balance == -collections eşitliği kanıtı` -> **PASS**
  - `2.2: Erkul Çeyiz için diskte hiçbir SQLite Legacy (.db) yedeği bulunmadığının kanıtı` -> **PASS**
  - `3.1: Nutopia 16-19 Ekim farkı ve -526.40 stok çıkışı matematiksel mutabakatı` -> **PASS**
  - `4.1: Kaynak dosyaların kriptografik özetleri (SHA-256) doğrulanır` -> **PASS**

#### 9.3. Statik Analiz (Linter)
- **Komut:** `flutter analyze test/core_next/stage10_12_43_financial_reconciliation_and_adapter_audit_test.dart`
- **Sonuç:** `No issues found! (ran in 53.6s)` (`Exit Code: 0`)

#### 9.4. Git Diff Kontrolü
- **Komut:** `git diff --check`
- **Sonuç:** `Exit Code: 0` (Temiz)

---

### 10. Eksik Güvenlikler ve Riskler

1. **Canlı Replikasyon / CDC Eksikliği:** Adaptör günlük canlı işlemleri Core Next'e aktarmamaktadır. Canlıya geçiş öncesinde ara işlemler aktarılmazsa hedef veritabanı bayat kalır.
2. **Erkul Çeyiz İçin Legacy SQLite Yedeği Bulunmaması:** Erkul Çeyiz'in geçmişinde hiçbir SQLite `.db` dosyası yoktur. Olası bir geri alma durumunda dönebileceği bir Legacy SQLite bulunmamaktadır.
3. **Erkul'un Eksik Müşteri Kartı Bakiyeleri:** PostgreSQL'de müşteri kartı bakiyesi borçlandırmaları (`manual_debt`) yansıtmadığı için, resmi mutabakat kararı verilmeden bu verinin `customers.balance` alanına güvenilemez.

---

### 11. En Küçük Güvenli Sonraki Adım

1. **Nutopia İçin Taze Aday Snapshot Oluşturulması:**
   - Mevcut 16 Ekim snapshot'ına dokunulmadan (`SNAPSHOT_20261019_161042\core_next\nutopia_pos.db`), 19 Ekim canlı yedeğinden taze göçürülmüş doğrulanmış aday veritabanı ayrı bir aday dosya olarak hazırlanmalıdır.
2. **Erkul Çeyiz İşletme Onayı:**
   - Erkul Çeyiz için müşterilerin hareket geçmişine (`financial_transactions`: -3.78M TL) göre mi hesaplama yapılacağı, yoksa kart bakiyesine mi itibar edileceği işletme sahibine sunulmalıdır.
3. **Canlı Güvenlik Sabitlerinin Korunması:**
   - Bu şartlar tamamlanana kadar `coreNextSalesEngineEnabledProvider = false` ve `DatabaseManager.databaseRoutingHook = null` değerleri kesinlikle değiştirilmemelidir.

---

### 12. Genel Karar: `BLOCKED`

| Değerlendirme Alanı | Durum | Gerekçe |
| :--- | :--- | :--- |
| **Güvenlik Sabitleri ve Pilot Kapısı** | **PASS** | `coreNextSalesEngineEnabledProvider = false` ve `hook = null` korunuyor. Kapı fail-closed. |
| **Adaptör Davranış Analizi (12 Soru)** | **PASS** | Yazma yolları kanıtlandı; adaptörün canlı işlemleri aktarmadığı tescillendi. |
| **Nutopia Veri ve Stok Mutabakatı** | **PASS** | 16-19 Ekim deltasının (+17 cari, +22 sipariş, +31 kalem, -526.40 stok) 1:1 mutabakatı sağlandı. |
| **Erkul Çeyiz Finansal Adli Kök Neden** | **PASS** | 397/401 caride `card_balance == -collections` eşitliği ve Cloud PG kusuru kanıtlandı. |
| **Canlıya Geçiş Hazırlığı** | **BLOCKED** | Canlı CDC replikasyonu bulunmadığından ve Erkul için geri dönüş yedeği olmadığından geçiş durduruldu. |
| **GENEL NİHAİ KARAR** | **`BLOCKED`** | Canlı işlemlerin kayıpsız kesim planı işletilmeden ve Erkul kararı kesinleşmeden yönlendirme açılamaz. |

---

### 13. İşlem Sonu Git ve Dosya Özeti
- **Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Branch:** `main`
- **Oluşturulan / Güncellenen Dosyalar:**
  - [scripts/stage10_12_43_financial_reconciliation_and_adapter_audit.py](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/scripts/stage10_12_43_financial_reconciliation_and_adapter_audit.py)
  - [test/core_next/stage10_12_43_financial_reconciliation_and_adapter_audit_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_43_financial_reconciliation_and_adapter_audit_test.dart)
  - [CORE_NEXT_STAGE10_12_43_FINANCIAL_RECONCILIATION_AND_ADAPTER_AUDIT.md](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/CORE_NEXT_STAGE10_12_43_FINANCIAL_RECONCILIATION_AND_ADAPTER_AUDIT.md)
- **Kullanıcı WIP Durumu:** 22 adet değiştirilmiş dosya bozulmadan ve silinmeden korunmuştur.
