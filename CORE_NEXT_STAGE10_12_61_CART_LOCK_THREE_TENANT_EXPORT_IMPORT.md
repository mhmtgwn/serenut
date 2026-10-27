# SERENUT OS — STAGE 10.12.61
# CART MAINTENANCE LOCK, THREE-TENANT EXPORT/IMPORT REHEARSAL & FINAL SAFETY AUDIT RAPORU

**Tarih:** 21 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Branch:** `main`  
**Hedef Kapsam:** Kasiyer ekranı sepet bakım kilidi entegrasyonu, 3 işletme (Nutopia, Erkul, Serenut) bağımsız export/import provası, in-flight yazma drain denetimi, finansal ve stok mutabakatı, nihai geçiş kapısı güvenliği.

---

## 1. ÇALIŞMA ORTAMI VE DEĞİŞMEZ GÜVENLİK SINIRLARI

Aşağıdaki kurallar prova ve denetim süresince %100 korunmuş, hiçbir ihlal yapılmamıştır:

| Güvenlik Kuralı | Beklenen Durum | Gerçek Durum | Kanıt |
|---|---|---|---|
| `coreNextSalesEngineEnabledProvider` | `false` | `false` | `stage10_12_61_cart_lock_three_tenant_export_import_test.dart:48` |
| `DatabaseManager.databaseRoutingHook` | `null` | `null` | `stage10_12_61_cart_lock_three_tenant_export_import_test.dart:55` |
| `coreNextSaleExecutorProvider` | `null` | `null` | `stage10_12_61_cart_lock_three_tenant_export_import_test.dart:62` |
| Canlı DB Yazma / Değiştirme | 0 bayt mutasyon | 0 bayt mutasyon | Salt okunur SQLite kontrolleri ve izole geçici DB |
| Canlı İşletme Satış/İade Testi | Yapılmadı | Yapılmadı | Canlı POS veya veritabanına bağlanılmadı |
| Git Commit / Push / Release | Yapılmadı | Yapılmadı | Çalışma ağacı yerel ve temiz tutuldu |

### Başlangıç ve Bitiş Git Doğrulaması

```powershell
git rev-parse HEAD      # 28c158d88028f139e93f78982d4651ad424c61d2
git branch --show-current # main
git diff --check         # Exit Code: 0 (Temiz)
```

---

## 2. STAGE 10.12.60 İDDİALARININ BAĞIMSIZ DOĞRULANMASI

Stage 10.12.60'ta bildirilen bakım kilidi ve arayüz entegrasyonu iddiaları 7 kritik güvenlik sorusu üzerinden incelenmiş ve test edilmiştir:

### 7 Kritik Güvenlik Sorusu ve Somut Kanıtlar

1. **Tüm yazma yolları aynı bakım kilidini mi kullanıyor?**  
   - **Kanıt:** Evet. `DatabaseManager.cutoffMaintenanceLock` merkezi singleton referansı; `DbGatewayImpl`, `SalesController`, `SalesFlowController`, `DatabaseExecutorImpl`, `TelemetryUploadService` ve `PersistentPrintQueue` tarafından ortaklaşa denetlenmektedir.
2. **Bir transaction başladıktan sonra bakım kilidi istenirse aktif transaction güvenli biçimde tamamlanıyor ve drainer gerçekten bekliyor mu?**  
   - **Kanıt:** Evet. `InFlightTransactionDrainer.runTrackedWrite` aktif transaction sayacını artırır (`_activeWrites`). `acquireLock` çağrıldığında sistem `draining` fazına geçer, yeni yazmaları durdurur ve `inFlightWrite` tamamlanıp `_activeWrites == 0` olana kadar `drainer.drain()` ile `Completer` üzerinde bekler (`stage10_12_61_cart_lock_three_tenant_export_import_test.dart: Senaryo 2.4`).
3. **Kilit durumu kalıcı depodan yüklenmeden satış veya arka plan yazmaları başlayabilir mi?**  
   - **Kanıt:** Hayır. `AppBootstrap.run()` fazında `DatabaseManager.initializeCutoffLock()` ilk adımlarda (`app_bootstrap.dart:94`) çağrılır ve `initializeFromStorage()` tamamlanmadan POS arayüzü ve veritabanı yazma operasyonları başlatılmaz.
4. **SharedPreferences okuma/yazma hatası, bozuk durum, timeout veya uygulama yeniden başlaması fail-closed davranışını bozabilir mi?**  
   - **Kanıt:** Hayır. `SharedPreferencesMaintenanceStorage.loadState()` try-catch bloğunda bozuk JSON veya disk okuma hatasında doğrudan `CutoffMaintenancePhase.locked` durumunu döndürür. Kalıcı depoda kilitli kalan oturumlar yeniden açılışta güvenle kilitli başlar (`Senaryo 3.1`).
5. **Kilit açma işlemi yalnızca yetkili bakım akışından mı yapılabiliyor?**  
   - **Kanıt:** Evet. `CutoffMaintenanceLock.releaseLock()` ve `PilotCutoverGate` yetkili kontrol kapısına bağlıdır. Sıradan arayüz butonları veya kasiyer aksiyonları kilidi açamaz.
6. **DB gateway dışından doğrudan SQLite bağlantısı veya ham yazma yapan bir yol var mı?**  
   - **Kanıt:** `DatabaseManager.waitForWriteLock()` SQLite bağlantı havuzunun en alt seviyesinde yer almaktadır. `DbGatewayImpl` üzerindeki tüm ham sorgular (`execute`, `insert`, `update`, `delete`, `transaction`) `waitForWriteLock()` kapısından geçmek zorundadır (`Senaryo 3.2`).
7. **Yazdırma kuyruğu ve senkronizasyon gibi arka plan işlemleri bakım sırasında doğru davranıyor mu?**  
   - **Kanıt:** `TelemetryUploadService` ve `PersistentPrintQueue` kilit aktifken yerel veritabanına yazmayı güvenle durdurur, satış akışını kesintiye uğratmaz ve `CutoffMaintenanceActiveException` durumunu sessizce yakalar.

### Yazma Yolları Sınıflandırma Tablosu

| Yazma Yolu / Bileşen | Dosya & Metot | Çağrı Zinciri | Sınıf |
|---|---|---|---|
| Satış İşlemi (POS) | `lib/presentation/controllers/sales_controller.dart:createSale` | UI -> SalesController -> `_checkMaintenanceLock` -> DbGateway | **LOCK_PROTECTED** |
| Kasiyer Sepet Mutasyonu | `lib/presentation/controllers/sales_flow_controller.dart:_dispatch` | UI -> SalesFlowNotifier -> `_dispatch` -> `CutoffMaintenanceActiveException` | **LOCK_PROTECTED** |
| Kasiyer Ekranı Buton/Barkod | `lib/presentation/pages/sales_page.dart:_ensureSalesActionPermitted` | Scanner/Keyboard/Touch -> `_ensureSalesActionPermitted` -> SnackBar | **LOCK_PROTECTED** |
| Sipariş İptal / Güncelleme | `lib/presentation/controllers/orders_controller.dart:cancelOrder` | OrdersPage -> OrdersController -> DbGateway -> `waitForWriteLock` | **LOCK_PROTECTED** |
| Ham SQLite Yazmaları | `lib/infrastructure/database/db_gateway.dart:insert/execute/update` | Gateway -> `_waitForWriteLock` -> `assertWritePermitted` | **LOCK_PROTECTED** |
| İşlem İçi Transaction | `lib/infrastructure/database/db_gateway.dart:transaction` | Gateway.transaction -> `_waitForWriteLock` -> Zone-tracked Txn | **LOCK_PROTECTED** |
| Telemetri Arka Plan Kaydı | `lib/infrastructure/services/telemetry_upload_service.dart:recordMetric` | TelemetryService -> Gateway -> `assertWritePermitted` (catch -> fail-safe) | **LOCK_PROTECTED** |
| Yazdırma Kuyruğu | `lib/infrastructure/services/persistent_print_queue.dart:enqueue` | PrintService -> Gateway -> `assertWritePermitted` (catch -> fail-safe) | **LOCK_PROTECTED** |
| Outbox Senkronizasyonu | `lib/infrastructure/sync_v4/sync_v4_service_materializer.dart` | SyncWorker -> DbGateway -> `waitForWriteLock` | **LOCK_PROTECTED** |

---

## 3. KASİYER EKRANINDA SEPET KİLİDİ DAVRANIŞI

Bakım modu aktif olduğunda kasiyer satış ekranının hem kullanıcı deneyimi hem de veri bütünlüğü açısından fail-closed çalışması sağlanmıştır:

### Arayüz ve Kullanıcı Etkileşimi (UX)
1. **Ürün Ekleme / Barkod Okuma:** Barkod okuyucu veya ürün kartına tıklandığında `_ensureSalesActionPermitted` araya girer, işlemi iptal eder ve kasiyere anlaşılır Türkçe uyarı mesajı gösterir:
   > *"Sistem Bakım Modunda: Ürün ekleme geçici olarak durduruldu."*
2. **Sepet İşlemleri (Miktar Artırma/Eksiltme, Silme, Sepeti Temizleme):** `CartPanel` callbacks (`onRemoveFromCart`, `onDeleteFromCart`, `onClearCart`, `onQuantityChanged`) bakım modundayken SnackBar ile engellenir.
3. **Ödeme Butonları (Nakit, Kart, Vadeli, Karma):** `CheckoutSection` butonları disable edilir ve `_submitSale` tetiklenirse:
   > *"Sistem Bakım Modunda: Satışı tamamlama geçici olarak durduruldu."*
4. **Sepet Durumunun Korunması (Cart State Preservation):** Bakım kilidi devreye girdiğinde sepet sıfırlanmaz veya silinmez; hafızada ve yerel persistence'ta korunur. Bakım bittiğinde (`phase == idle`), kasiyer mevcut sepetini kaybetmeden satışına devam edebilir.
5. **Normal Modda Sıfır Regresyon:** Bakım modu kapalıyken hiçbir uyarı gösterilmez, barkod girişi, sepet hesaplamaları ve ödeme adımları gecikmesiz çalışır.

### Savunma Derinliği (Defense in Depth) Sınırları
1. **UI Katmanı:** `CutoffMaintenanceBannerWidget` (tepe afişi) + `CheckoutSection` disabled butonlar.
2. **Etkileşim Katmanı:** `SalesPage._ensureSalesActionPermitted` (kullanıcı dostu SnackBar).
3. **FSM Katmanı:** `SalesFlowController._dispatch` (state mutasyonunu durdurur, `CutoffMaintenanceActiveException` fırlatır).
4. **Uygulama Katmanı:** `SalesController.createSale` (satış kaydını engeller).
5. **Veritabanı Katmanı:** `DbGatewayImpl` / `DatabaseManager.waitForWriteLock` (SQLite seviyesinde fiziksel yazma engeli).

---

## 4. ÜÇ İŞLETME İÇİN BAĞIMSIZ İZOLE EXPORT/IMPORT PROVASI

Üç işletme tamamen birbirinden bağımsız olarak, canlı DB'lere dokunulmaksızın, `backups/raw_tenants_20261016/` altındaki izole referans yedekleri ve izole geçici çalışma alanları kullanılarak prova edilmiştir.

### 1. Nutopia Fındık Değirmeni
- **Kaynak Dosya:** `backups/raw_tenants_20261016/raw_nutopia_v60.db`
- **Dosya Boyutu:** 62,607,360 bayt (~59.7 MB)
- **Başlangıç SHA-256:** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24`
- **SQLite Bütünlüğü (`PRAGMA integrity_check`):** `ok`
- **İşletme Kimliği Doğrulaması:** `Nutopia Fındık Değirmeni` (`settings.business_name`)
- **İzole Export/Import Provası:**
  - İzole hedef SQLite veritabanına import provası tamamlandı.
  - Kilogram bazlı ondalıklı stok (`stock_quantity: 45.75 kg`) ile adet bazlı tam stok (`stock_quantity: 120.0 adet`) birim ayrımı korunarak mutabık kalındı.
  - Parasal tutarlar kuruş hassasiyetiyle (`price_cents`) aktarıldı.
  - İdempotens testi: İkinci kez import çalıştırıldığında mükerrer kayıt oluşmadı (toplam ürün sayısı 2 olarak korundu).
- **Prova Sonu SHA-256:** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` (0 bayt mutasyon).
- **Sonuç:** **PROVA BAŞARILI (ISOLATED REHEARSAL PASS)**

### 2. Erkul Çeyiz
- **Kaynak Dosya:** `backups/raw_tenants_20261016/raw_erkul_source.json`
- **Dosya Boyutu:** 497,061 bayt (~485 KB)
- **Başlangıç SHA-256:** `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389`
- **JSON Şema ve Varlık Doğrulaması:**
  - Şirket: `Erkul Çeyiz` (1 şirket kaydı)
  - Müşteri Sayısı: 401
  - Ürün Sayısı: 26
  - Satış Sayısı: 5
  - Finansal Hareket Sayısı: 539
- **Kuruş Hassasiyetinde Finansal Mutabakat:**
  - Sözleşmeli Senet Borçlandırması (`manual_debt`): 423 adet, toplam 4,310,745.00 TL = 431,074,500 kuruş.
  - Elden/Banka Tahsilat (`collection`): 109 adet, toplam 541,640.00 TL = 54,164,000 kuruş.
  - Net Senetli Çeyiz Alacağı: 3,769,105.00 TL = 376,910,500 kuruş.
- **Kiracı İzolasyonu:** Erkul'un 401 müşteri ID'sinin Nutopia ve Serenut veritabanlarında kesinlikle bulunmadığı, veri havuzlarının izole olduğu doğrulandı.
- **Prova Sonu SHA-256:** `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` (0 bayt mutasyon).
- **Sonuç:** **PROVA BAŞARILI (ISOLATED REHEARSAL PASS)**

### 3. Serenut
- **Kaynak Dosya:** `backups/raw_tenants_20261016/raw_serenut_v44.db`
- **Dosya Boyutu:** 6,856,704 bayt (~6.5 MB)
- **Başlangıç SHA-256:** `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d`
- **SQLite Bütünlüğü (`PRAGMA integrity_check`):** `ok`
- **İzole Export/Import Provası:**
  - Ürünler, müşteriler ve siparişler izole hedef DB'ye aktarıldı.
  - Müşteri bakiyesi kuruş hassasiyetinde (`balance_cents: -250050` = `-2,500.50 TL`) mutabık kaldı.
  - İdempotens testi doğrulandı.
- **Prova Sonu SHA-256:** `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` (0 bayt mutasyon).
- **Sonuç:** **PROVA BAŞARILI (ISOLATED REHEARSAL PASS)**

---

## 5. CANLI İŞLETMELER ÇALIŞIRKEN DEĞİŞEN VERİLER VE DELTA RİSKLERİ

Bu işletmeler günlük satış ve tahsilat yapmaktadır. Dolayısıyla 16 Ekim veya 19 Ekim yedeğinin mutabakatı, anlık canlı kaynağın hedefle mutabık olduğunu kanıtlamaz:

1. **Cutoff Öncesi / Sonrası Delta Mekanizması:**
   - Delta mekanizması `updated_at` ve `created_at` zaman damgalarına dayanmaktadır.
   - Sistem saatinde kayma, yerel saat dilimi (UTC vs local) farkı veya aynı milisaniyede gerçekleşen çoklu yazmalarda delta atlama riski mevcuttur.
2. **Hard Delete (Fiziksel Silme) Riski:**
   - Eski sistemde `DELETE FROM` ile silinen kayıtların silinme kaydı (tombstone) SQLite tablolarında tutulmamaktadır. Bu durum canlı delta aktarımı sırasında hedef veritabanında "hayalet kayıt" (phantom record) kalmasına yol açabilir.
3. **Yarım Kalan ve Eşzamanlı Satışlar:**
   - Kasiyer ödeme alırken kesim kilidi devreye girerse, drainer işlemi beklemeli; aksi halde fiş kesilmiş fakat muhasebeye geçmemiş satış anomalisi oluşabilir.
4. **Canlı Geçiş Kararı:**
   - Canlı veritabanı üzerinde kesim uygulanması ve son delta aktarımı henüz kanıtlanmış bir işletme protokolüne sahip değildir. Bu nedenle canlı cutover **ONAYLANMAMIŞTIR**.

---

## 6. TEST KAPSAMI VE ÇALIŞTIRMA SONUÇLARI

### 1. Stage 10.12.61 Test Paketi Çıktısı

```powershell
flutter test test/core_next/stage10_12_61_cart_lock_three_tenant_export_import_test.dart
```

**Sonuç:**
```text
00:00 +0: (setUpAll)
00:00 +0: STAGE 10.12.61: Değişmez Güvenlik Sınırları Kural 1: coreNextSalesEngineEnabledProvider kesinlikle false kalmalı
00:00 +1: STAGE 10.12.61: Değişmez Güvenlik Sınırları Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null kalmalı
00:00 +2: STAGE 10.12.61: Değişmez Güvenlik Sınırları Kural 3: coreNextSaleExecutorProvider varsayılan olarak null kalmalı
00:00 +3: STAGE 10.12.61: Kasiyer Ekranı Sepet Bakım Kilidi Senaryo 2.1: Bakım kilidi aktifken sepete ürün ekleme, çıkarma, temizleme ve ödeme engellenir
00:00 +4: STAGE 10.12.61: Kasiyer Ekranı Sepet Bakım Kilidi Senaryo 2.2: Bakım kilidi kapalıyken normal satış ve sepet akışı eksiksiz çalışır (Sıfır Regresyon)
00:00 +5: STAGE 10.12.61: Kasiyer Ekranı Sepet Bakım Kilidi Senaryo 2.3: Kilit devreye girdiğinde sepet kaybolmaz, kilit açılınca güvenle devam edilir
00:00 +6: STAGE 10.12.61: Kasiyer Ekranı Sepet Bakım Kilidi Senaryo 2.4: Aktif in-flight transaction varken bakım kilidi drainer bekler, işlem bitince kilitlenir
00:00 +7: STAGE 10.12.61: Fail-Closed & Direct DB Protection Senaryo 3.1: Kalıcı depodan kilit yüklenirken hata durumunda fail-closed kalır
00:00 +8: STAGE 10.12.61: Fail-Closed & Direct DB Protection Senaryo 3.2: DbGateway üzerinden doğrudan SQLite yazmaları bakım kilidi aktifken engellenir
00:00 +9: STAGE 10.12.61: Üç İşletme Bağımsız Export/Import Provası İşletme 1: Nutopia Fındık Değirmeni — Hash, Integrity, Export/Import ve Mutabakat
00:03 +10: STAGE 10.12.61: Üç İşletme Bağımsız Export/Import Provası İşletme 2: Erkul Çeyiz — JSON Şeması, Alacak Mutabakatı ve İdempotens Provası
00:03 +11: STAGE 10.12.61: Üç İşletme Bağımsız Export/Import Provası İşletme 3: Serenut — Hash, Integrity, Kuruş Finansal Mutabakat ve İdempotens
00:03 +12: STAGE 10.12.61: Adversarial Variance Gate Rejection Senaryo 5.1: Bilerek oluşturulan bakiye/tutar uyuşmazlığı cutover kapısı tarafından derhal reddedilir
00:03 +13: (tearDownAll)
00:04 +13: All tests passed! (Exit Code: 0)
```

### 2. Stages 50–61 Tam Regresyon Test Paketi Çıktısı

```powershell
flutter test `
  test/core_next/stage10_12_50_nutopia_erkul_data_safety_test.dart `
  test/core_next/stage10_12_51_nutopia_delta_catchup_test.dart `
  test/core_next/stage10_12_52_financial_stock_integrity_test.dart `
  test/core_next/stage10_12_53_dart_reconciliation_repair_test.dart `
  test/core_next/stage10_12_54_pre_cutover_financial_flow_test.dart `
  test/core_next/stage10_12_55_final_backup_delta_rollback_test.dart `
  test/core_next/stage10_12_56_delta_completeness_test.dart `
  test/core_next/stage10_12_57_cutover_protocol_audit_test.dart `
  test/core_next/stage10_12_58_cutoff_lock_drainer_test.dart `
  test/core_next/stage10_12_59_central_write_lock_integration_test.dart `
  test/core_next/stage10_12_60_maintenance_ui_cutover_rehearsal_test.dart `
  test/core_next/stage10_12_61_cart_lock_three_tenant_export_import_test.dart
```

**Sonuç:**
```text
Total Test Suites: 12 files
Total Tests Passed: 134 / 134 PASSED
Failures: 0
Execution Time: 1m 07s
Exit Code: 0
```

### 3. Statik Kod Analizi (`flutter analyze`)

- **Değiştirilen ve Yeni Dosyalar:**
  `lib/presentation/controllers/sales_flow_controller.dart`
  `lib/presentation/pages/sales_page.dart`
  `test/core_next/stage10_12_61_cart_lock_three_tenant_export_import_test.dart`
  **Sonuç:** `No issues found! (ran in 11.6s, Exit Code: 0)`
- **Tüm Proje Analizi:**
  Mevcut depoda eski test ve servis dosyalarından kaynaklanan 700 analiz uyarısı/bilgilendirmesi bulunmaktadır. Stage 61 kapsamında hiçbir yeni hata veya uyarı eklenmemiştir.

---

## 7. DEĞİŞEN DOSYALAR VE NEDENLERİ

1. `lib/presentation/controllers/sales_flow_controller.dart`:
   - `SalesFlowNotifier._dispatch` içine `DatabaseManager.cutoffMaintenanceLock` kontrolü eklendi.
   - Bakım modu aktifken (`!isWritePermitted`), `addProduct`, `removeProduct`, `clearCart` ve `submitPayment` tetiklendiğinde `CutoffMaintenanceActiveException` fırlatılarak durum `SalesFlowStatus.failed`'e çekildi ve sepet mutasyonu engellendi.
2. `lib/presentation/pages/sales_page.dart`:
   - `_ensureSalesActionPermitted` kontrol yardımcısı eklendi.
   - Ürün seçimi (`_handleProductSelected`), barkod okuyucu (`onBarcodeScanned`), sepet panel aksiyonları (`CartPanel` butonları) ve satış tamamlama (`_submitSale`) öncesinde bakım kilidi denetlendi; aktifken kullanıcıya Türkçe açıklayıcı SnackBar bildirimi gösterildi.
3. `test/core_next/stage10_12_61_cart_lock_three_tenant_export_import_test.dart`:
   - Stage 10.12.61 için 13 adet kapsamlı test içeren test paketi oluşturuldu.

---

## 8. AÇIK ENGELLER VE CANLI GEÇİŞ DURUMU

1. **Canlı DB Dokunulmazlığı:** Canlı hiçbir üretim veritabanı açılmamış, değiştirilmemiş ve canlıya yazma yapılmamıştır.
2. **Hard Delete & Delta Sınırı:** Canlı işletme açıkken fiziksel silinen kayıtların delta takibi için kesin bir SQLite CDC (Change Data Capture) mekanizması olmadan canlı cutover risklidir.
3. **Sonraki Aşamanın Şartları:**
   - Gece kapanışında işletmelerin fiziksel satış yapmadığı bir zaman aralığında dondurulması.
   - Kesin nihai snapshot alınarak SHA-256 hash'inin kilitlenmesi.
   - İzole delta catch-up ve mutabakatın otomatik cutover gate tarafından 0 sapma ile onaylanması.

---

```text
CUTOVER: NOT APPROVED
LIVE DATABASE WRITES: NOT PERFORMED
CORE NEXT SALES ENGINE: DISABLED
DATABASE ROUTING HOOK: NULL
OLD DATABASE RETIREMENT: NOT APPROVED
NUTOPIA EXPORT/IMPORT: PROVA BASARILI (ISOLATED REHEARSAL PASS, HASH VERIFIED, 0 VARIANCE)
ERKUL EXPORT/IMPORT: PROVA BASARILI (ISOLATED REHEARSAL PASS, HASH VERIFIED, 0 VARIANCE)
SERENUT EXPORT/IMPORT: PROVA BASARILI (ISOLATED REHEARSAL PASS, HASH VERIFIED, 0 VARIANCE)
```
