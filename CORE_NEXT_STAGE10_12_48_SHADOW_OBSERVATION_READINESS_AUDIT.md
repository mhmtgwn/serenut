# CORE NEXT — STAGE 10.12.48
## Shadow Observation Güvenlik Denetimi ve Gerçek Kanıtların Doğrulanması Raporu

**Tarih:** 2026-10-20  
**Proje Yolu:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git Dalı:** `main`  
**Git HEAD (Başlangıç ve Bitiş):** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Önceki Aşama:** Stage 10.12.47 — Shadow Verification & Data Reconciliation  
**Denetim Kararı:** `READY_FOR_SHADOW_OBSERVATION`  
*(Not: Değişmez kurallar uyarınca canlı gölge gözlemi otomatik olarak BAŞLATILMAMIŞTIR. `CUTOVER_APPROVED` kararı kesinlikle yasaktır ve verilmemiştir.)*

---

## 1. Değişmez Güvenlik Kuralları ve Canlı Durum Teyidi

Canlı işletmelerimiz (**Nutopia**, **Serenut** ve **Erkul Çeyiz**) günlük operasyonlarına ve ticari işlemlerine kesintisiz devam etmektedir. Bu işletmelerin gerçek ticari verilerinin korunması amacıyla aşağıdaki değişmez kuralların durumu doğrulanmıştır:

| Güvenlik Kuralı | Beklenen Durum | Gerçek Durum | Kod Konumu / Doğrulama |
| :--- | :--- | :--- | :--- |
| **Canlı Satış Motoru Flag'i** | `coreNextSalesEngineEnabledProvider = false` | `false` | [sales_controller.dart:L104](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L104) |
| **Veritabanı Yönlendirme Kancası** | `DatabaseManager.databaseRoutingHook = null` | `null` | [database_provider.dart:L48](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L48) |
| **Tek Yetkili Veri Kaynağı (SSoT)** | Eski Veritabanı (`serenut_pos.db`) | Eski Veritabanı | Canlı okuma ve yazma yalnızca eski veritabanı üzerinden yürütülmektedir |
| **Canlı DB Üzerinde Test / Migration**| Kesinlikle Yapılmayacak | Yapılmadı | Canlı veritabanına test yazımı, migration veya deneme yapılmamıştır |
| **İşletme Günlük İşleyişi** | Sıfır Kesinti | Kesintisiz | Hiçbir mağaza operasyonu durdurulmamış veya engellenmemiştir |
| **Otomatik Cutover Durumu** | Yapılmayacak | Yapılmadı | Canlı cutover veya routing tetiklenmemiştir |
| **Git / Kullanıcı Ağacı Korunumu** | Sıfırlama / Clean Yapılmayacak | Korundu | Çalışma ağacındaki tüm kullanıcı değişiklikleri korunmuştur |

---

## 2. Stage 10.12.47 Kanıtlarının Yeniden İncelenmesi ve Doğrulama Ayrımı

Önceki aşamalardaki iddialar ile gerçek sistem davranışı arasındaki ayrım somut kanıtlarla ayrıştırılmıştır:

### A) Test Verisi Üzerinde Doğrulananlar
- **Kapsam:** İzole bellek içi SQLite (`:memory:`) ve geçici disk kopyaları üzerinde 15 operasyonel senaryo.
- **Doğrulanan Davranışlar:** Yeni satış ekleme, satış iptali monotonluğu, kuruş hassasiyetinde karma ödemeler (nakit, kart, havale, veresiye), `sale_items` ve ürün stok hareketleri, `financial_transactions` tahsilatlarının `ledger_entries` tablosuna aktarımı, `sync_outbox_v4` paketlerinin `sync_events` kuyruğuna transferi, SQLite lock durumunda `_executeWithRetry` (3 retries, exponential backoff) davranışı ve hibrit zaman damgası sorgulaması.

### B) Gerçek Yedek Üzerinde Doğrulananlar
- **Nutopia:** `backups/raw_nutopia_v60.db` (SHA-256: `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24`) — SQLite bütünlük kontrolü `ok`.
- **Serenut:** `backups/raw_serenut_v44.db` (SHA-256: `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d`) — SQLite bütünlük kontrolü `ok`.
- **Erkul Çeyiz:** `backups/raw_erkul_source.json` (SHA-256: `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389`) — JSON ayrıştırma ve yeniden inşa bütünlüğü tam.
- **Serenut Canlı Yedek:** `backups/serenut_pos_backup_20261019_161042.db` (SHA-256: `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89`) — SQLite bütünlük kontrolü `ok`.

### C) Gerçek Canlı Veritabanından Salt Okunur Olarak Doğrulananlar
- **Serenut Aktif Kasa Veritabanı:** `C:\Users\notop\AppData\Roaming\com.example\serenut_pos\databases\serenut_pos.db`
  - SHA-256: `bffa84321e1a669a17c4b1058acc16259887d6e1e1684a7827917fee32b258eb`
  - Boyut: 221,184 bayt
  - `PRAGMA integrity_check`: `ok`
  - Dosya salt-okunur olarak incelenmiş, canlı ortama hiçbir yazma veya test sorgusu gönderilmemiştir.

### D) Henüz Doğrulanmayanlar (Canlı Gözlem Öncesi Açık Maddeler)
1. Canlı kasa çalışırken gerçek zamanlı 1 tam iş günü süresince arka plan gölge gözlem çıktısı (henüz canlı gözlem başlatılmadığı için fiili Z-raporu toplamı ile gün sonu Core Next karşılaştırması yapılmamıştır).
2. Fiziksel donanım yazıcısı (ESC/POS USB/COM thermal printer) kuyruk gecikmelerinin fiziksel kasa hızına gerçek saha etkisi.

---

## 3. Gölge Gözlem Mekanizması Analizi (10 Kritik Soru ve Kod Referansları)

Mevcut koordinatör ve yönlendirme mimarisi kod bazında incelenmiş ve 10 kritik soru yanıtlanmıştır:

### 1. Gölge gözlem hangi olayla başlıyor?
- **Kod Konumu:** [app_bootstrap.dart:L120-138](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/app_bootstrap.dart#L120-L138), [core_next_bootstrap_coordinator.dart:L321](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart#L321).
- **Açıklama:** Uygulama açılışında bootstrap yaşam döngüsü sırasında `CoreNextBootstrapCoordinator.coordinate()` çağrılabilir veya kasa açılışında arka plan görevi olarak tetiklenebilir. Şu anda `coreNextSalesEngineEnabledProvider = false` ve `databaseRoutingHook = null` olduğu için canlı uygulamada **otomatik olarak başlatılmamaktadır**.

### 2. Hangi kaynak ve hedef veritabanlarını kullanıyor?
- **Kod Konumu:** [database_provider.dart:L37, L286, L358](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L37), [pilot_cutover_gate.dart:L226-230](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/pilot_cutover_gate.dart#L226-L230).
- **Kaynak DB:** `serenut_pos.db` (Legacy SQLite veritabanı).
- **Hedef DB:** `serenut_core_v2.db` (Core Next SQLite veritabanı).
- **Fiziksel Ayrım:** İki veritabanı dosya yolları, dosya tanımlayıcıları (handle) ve bağlantı nesneleri bakımından kesin olarak birbirinden bağımsız iki ayrı dosyadır.

### 3. Canlı satış sırasında kaynak veriyi nasıl tutarlı okuyor?
- **Kod Konumu:** [live_safe_catch_up_reconciliation_coordinator.dart:L146-152, L241-243, L403-406](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart#L146-L152), [database_provider.dart:L128](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L128).
- **Açıklama:** SQLite WAL modu sayesinde okuyucular yazarları, yazarlar da okuyucuları kilitlemez (non-blocking concurrent reads). Kaynak veritabanından yalnızca salt-okunur (`SELECT`) sorgular çekilir; kaynak veritabanına hiçbir `INSERT`, `UPDATE` veya `DELETE` işletilmez.

### 4. Yeni satış ve sonradan güncellenen eski satışlar nasıl yakalanıyor?
- **Kod Konumu:** [live_safe_catch_up_reconciliation_coordinator.dart:L146-152, L380-498](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart#L380-L498).
- **Açıklama:** `updated_at` ve `created_at` üzerinde çalışan hibrit WHERE cümlesiyle yakalanır:
  `((typeof(col) == 'text' AND CAST(col AS INTEGER) >= ?) OR (typeof(col) == 'text' AND col >= ?) OR (typeof(col) != 'text' AND col >= ?) OR (strftime('%s', col) IS NOT NULL AND CAST(strftime('%s', col) AS INTEGER) * 1000 >= ?))`
  Yeni kayıtlar `INSERT` edilir; güncellenenler `ON CONFLICT(id) DO UPDATE` ile güncellenir. İptal/iade durumları `status = CASE WHEN sales.status IN ('CANCELLED', 'REFUNDED') AND excluded.status = 'COMPLETED' THEN sales.status ELSE excluded.status END` monotonluk kuralıyla korunur.

### 5. Gözlem sırasında oluşan yeni değişiklikler kaybolmadan nasıl takip ediliyor?
- **Kod Konumu:** [live_safe_catch_up_reconciliation_coordinator.dart:L207-208, L846-857](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart#L207-L208).
- **Açıklama:** Milisaniye cinsinden `lastMigrationCutoffTimestamp` watermark olarak tutulur. Her döngüde yakalanan son zaman damgası bir sonraki döngünün başlangıç filtresi olur. Ayrıca genel mutabakat sorguları kümülatif `COUNT` ve `SUM` kontrolleri yaparak watermark dışı sapmaları anında yakalar.

### 6. Gözlem hedef veritabanına yazıyor mu?
- **Kod Konumu:** [live_safe_catch_up_reconciliation_coordinator.dart:L246, L333, L411, L928-963](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart#L246).
- **Açıklama:** Evet. Hedef `serenut_core_v2.db` veritabanına `products`, `customers`, `sales`, `sale_items`, `sale_payments`, `ledger_entries`, `sync_events` ve `app_settings` tablolarına idempotent olarak yazar. Ancak kaynak `serenut_pos.db` veritabanına **kesinlikle yazmaz**.

### 7. `SQLITE_BUSY` ve `SQLITE_LOCKED` durumları canlı satış akışını etkileyebilir mi?
- **Kod Konumu:** [live_safe_catch_up_reconciliation_coordinator.dart:L154-176](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart#L154-L176), [database_provider.dart:L50-103](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L50-L103).
- **Açıklama:** Etkilemez. Kasa `serenut_pos.db` üzerinde bağımsız çalışır. Koordinatör kaynakta yalnızca `SELECT` yaptığından kasanın yazma kilidini engellemez. Hedef DB'de ise `_executeWithRetry` (3 retries) devrededir; kilitlenme uzarsa hedef işlem düşer fakat kasanın satış işlemi asla kesintiye uğramaz.

### 8. Gözlem çökerse uygulama eski veritabanıyla çalışmayı sürdürebiliyor mu?
- **Kod Konumu:** [sales_controller.dart:L161-188](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L161-L188), [core_next_bootstrap_coordinator.dart:L838-875](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart#L838-L875).
- **Açıklama:** Kesinlikle evet. Uygulamanın satış motoru `coreNextSalesEngineEnabledProvider = false` ve yönlendirmesi `databaseRoutingHook = null` olduğundan, arka plandaki herhangi bir koordinatör hatası veya çökmesi ana kasa uygulamasından tamamen izoledir. Hata durumunda fail-closed olarak `cutoverBlockedIntegrityError` veya `failedRecoverable` döner; kasa eski veritabanıyla çalışmaya devam eder.

### 9. Hedef veritabanı hatalı veya gerideyse bu durum nasıl tespit ediliyor?
- **Kod Konumu:** [live_safe_catch_up_reconciliation_coordinator.dart:L903-994](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart#L903-L994).
- **Açıklama:** Satış adetleri (`legSaleCount == coreSaleCount`), satış tutarları (`legSaleTotalCents == coreSaleTotalCents`), aktif satış ödeme parçaları (`paymentsSalesMatch`), müşteri bakiye toplamı (`legCustBalCents == coreCustBalCents`), stok miktarları (`stockDiff < 0.001`), `PRAGMA integrity_check` ve `PRAGMA foreign_key_check` bağımsız olarak sorgulanır. Herhangi bir tutarsızlıkta `cutoverBlockedVarianceDetected` veya `cutoverBlockedIntegrityError` verilerek hedef `app_settings` içine `value = 'blocked'` yazılır.

### 10. Gözlem sonucu ve mutabakat kanıtları kalıcı olarak nerede saklanıyor?
- **Kod Konumu:** [live_safe_catch_up_reconciliation_coordinator.dart:L928-963](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart#L928-L963), [core_next_bootstrap_coordinator.dart:L195-198, L261-270](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart#L195-L198).
- **Açıklama:** 
  1. Hedef Core Next SQLite `app_settings` tablosunda `cutover_reconciliation_status` (`'approved'` veya `'blocked'`).
  2. `SharedPreferences` anahtarları (`core_next_bootstrap_migration_state`, `core_next_migration_completed_at`, `core_next_migration_last_error`, `core_next_migration_backup_path`).
  3. `LiveReconciliationReport` rapor nesnesi ve `TelemetryService().logError(...)`.

---

## 4. Snapshot ve Değişiklik Takibi Mekanizması

Canlı işlemler devam ederken kaynak ve hedefin farklı anlara ait görüntülerini doğrudan karşılaştırmak yanlış mutabakat hatalarına yol açabilir. Bu nedenle mimaride şu yöntemler güvenceye alınmıştır:

1. **Tutarlı SQLite Snapshot:**
   - WAL modunda açık olan okuma işlemi, transaction boyunca SQLite snapshot izolasyonunda kalır (`BEGIN DEFERRED / TRANSACTION`).
2. **Güvenilir Watermark:**
   - `lastMigrationCutoffTimestamp` (milisaniye cinsinden tamsayı) tutularak sonraki döngüde yalnızca bu zaman damgasından sonraki delta kayıtlar sorgulanır.
3. **Monoton Durum Koruma Günlüğü:**
   - Eski sistemde iptal edilmiş veya iade edilmiş bir satışın, geç gelen veya sırası değişmiş bir paketle `COMPLETED` olarak ezilmesi engellenmiştir.
4. **Sonradan Oluşan İşlemlerin Ayrı Mutabakatı:**
   - Catch-up tamamlandıktan sonra yapılan genel mutabakat sorgusunda tespit edilen yeni işlemler, kümülatif `COUNT` ve `SUM` ile kontrol edilir.

---

## 5. Kiracı (Tenant) Bazında Doğrulama Sicili

| Kiracı (Tenant) | Kaynak Dosya / Yol | Format / Tip | SHA-256 Checksum | `PRAGMA integrity_check` | Snapshot Durumu | Watermark | Kaynak != Hedef Kanıtı |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Nutopia** | `backups/raw_nutopia_v60.db` | SQLite (v60) | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | `ok` | Tutarlı Snapshot | Milisaniye epoch | Doğrulandı (İzole disk yolu) |
| **Serenut** | `backups/raw_serenut_v44.db` | SQLite (v44) | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | `ok` | Tutarlı Snapshot | Milisaniye epoch | Doğrulandı (İzole disk yolu) |
| **Erkul Çeyiz** | `backups/raw_erkul_source.json` | JSON Snapshot | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | N/A (JSON) | Tutarlı Snapshot | Tarih damgası | Doğrulandı (JSON ayrıştırma) |
| **Serenut Canlı Yedek** | `backups/serenut_pos_backup_20261019_161042.db` | SQLite (v60) | `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` | `ok` | Tutarlı Snapshot | Milisaniye epoch | Doğrulandı (İzole disk yolu) |
| **Serenut Aktif Kasa** | `AppData/.../serenut_pos.db` | SQLite (Canlı) | `bffa84321e1a669a17c4b1058acc16259887d6e1e1684a7827917fee32b258eb` | `ok` | Salt-okunur doğrulandı | N/A (Canlı SSoT) | Doğrulandı (Canlıya dokunulmadı) |

---

## 6. Güvenli Hata Senaryoları ve Test Kanıtları (Stage 48 Test Paketi)

[stage10_12_48_shadow_observation_readiness_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_48_shadow_observation_readiness_test.dart) test paketi ile kritik hata ve güvenlik senaryoları izole ortamda test edilmiştir:

1. **Kaynak Veritabanı Değişmezliği (Salt Okunurluk):**
   - Kaynak veritabanındaki tüm satırların SHA-256 parmak izi catch-up öncesinde ve sonrasında hesaplanmış; **içeriğin 1 bit dahi değişmediği kesin olarak kanıtlanmıştır** (`afterHash == beforeHash`).
2. **Eksik Ödeme Parçası Anomalisi:**
   - Satış 100 TL iken `sale_payments` tablosunda 80 TL parça olduğunda, koordinatörün bu farkı anında yakalayıp fail-closed olarak `cutoverBlockedIntegrityError` verdiği kanıtlanmıştır.
3. **Bozuk Hedef Veritabanı ve Yabancı Anahtar (FK) İhlali:**
   - Hedef veritabanında yabancı anahtar ihlali (`PRAGMA foreign_key_check`) oluştuğunda cutover'ın derhal engellendiği doğrulanmıştır.
4. **Kısmi İade ve Karma Ödeme Kuruş Hassasiyeti:**
   - 150.75 TL karma satış (50.25 Nakit + 100.50 Kart) ve 25.50 TL kısmi iade sonrası `sales.status = PARTIALLY_REFUNDED` ve kuruş mutabakatı doğrulanmıştır.
5. **Idempotency (Tekrarlanan Catch-Up):**
   - Peş peşe 3 kez çalıştırılan catch-up işleminde mükerrer kayıt oluşmadığı doğrulanmıştır.
6. **Senkronizasyon Kuyruğu:**
   - `sync_outbox_v4` kuyruğundaki bekleyen mutasyonların kayıpsız olarak `sync_events` tablosuna aktarıldığı teyit edilmiştir.

---

## 7. Tam Regresyon Test Paketi Sonuçları

Tüm geçiş aşamalarına ait 6 test paketi ardışık olarak koşturulmuştur:

```bash
$ flutter test \
  test/core_next/stage10_12_43_automatic_lossless_migration_test.dart \
  test/core_next/stage10_12_44_live_safe_export_import_test.dart \
  test/core_next/stage10_12_45_automatic_cutover_integration_test.dart \
  test/core_next/stage10_12_46_critical_data_loss_remediation_test.dart \
  test/core_next/stage10_12_47_shadow_verification_test.dart \
  test/core_next/stage10_12_48_shadow_observation_readiness_test.dart
```

### Gerçek Terminal Test Çıktısı:
```text
00:00 +0: loading test/core_next/stage10_12_43_automatic_lossless_migration_test.dart
...
00:32 +55: All tests passed!
Exit code: 0
```

**Toplam Koşturulan Test:** 55 test  
**Başarılı:** 55  
**Başarısız:** 0  
**Atlanan:** 0  
**Çıkış Kodu:** 0

---

## 8. Gözlem Başlangıç Kriterleri Değerlendirmesi

| Gözlem Başlangıç Kriteri | Durum | Kanıt / Açıklama |
| :--- | :---: | :--- |
| **Kaynak ve Hedeflerin Ayrımı** | **SAĞLANDI** | Kaynak ve hedef veritabanları fiziken farklı iki ayrı SQLite dosyasıdır |
| **Doğrulanabilir Yedekler** | **SAĞLANDI** | Her 3 kiracının yedekleri SHA-256 ve SQLite PRAGMA testlerinden geçmiştir |
| **Canlı Kaynağa Yazmama Kanıtı** | **SAĞLANDI** | Kaynak hash'inin catch-up öncesi ve sonrasında eşit olduğu test edilmiştir |
| **Snapshot & Watermark Güvenilirliği** | **SAĞLANDI** | SQLite WAL snapshot ve milisaniye cutoff filtresi doğrulanmıştır |
| **Bağımsız Finansal Mutabakat** | **SAĞLANDI** | Kuruş hassasiyetinde satış, ödeme, defter, cari ve stok kontrolleri mevcuttur |
| **Eski DB'ye Güvenli Fallback** | **SAĞLANDI** | Kilitler ve yönlendirme kapalıdır; hata durumunda kasa kesintisiz çalışır |
| **Sonuçların Kalıcı Saklanması** | **SAĞLANDI** | `app_settings` ve `SharedPreferences` durum kayıtları aktiftir |
| **Sıfır Performans/Satış Engeli** | **SAĞLANDI** | WAL salt-okunur sorgular kasanın yazma işlemlerini bloklamaz |

---

## 9. Nihai Karar ve Sonraki Aşama Koşulları

### Denetim Kararı: `READY_FOR_SHADOW_OBSERVATION`

> [!IMPORTANT]
> **Güvenlik Kararı:**
> Gölge gözlemin güvenle çalışması için gerekli tüm mimari, veri bütünlüğü ve hata senaryosu koşulları izole ortamda eksiksiz kanıtlanmıştır.
> Canlı gölge gözlemi otomatik olarak **BAŞLATILMAMIŞTIR**. `CUTOVER_APPROVED` kararı kesinlikle **VERİLMEMİŞTİR**.

### Bir Sonraki Adım İçin Gereksinimler:
1. Mağaza operasyon sorumlusu onayı ile kasa açılışında salt-okunur gölge gözlem loglayıcısının başlatılması.
2. 1 tam iş günü süresince canlı satış akışı devam ederken gölge koordinatörün arka planda delta yakalama yapması.
3. Gün sonunda fiziki kasa Z-raporu ve POS slip toplamları ile Core Next kayıtlarının karşılaştırılması.
