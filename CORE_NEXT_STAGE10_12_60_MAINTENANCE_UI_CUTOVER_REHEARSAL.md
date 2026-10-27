# SERENUT OS — STAGE 10.12.60
## MAINTENANCE UI, WRITE-LOCK VERIFICATION & ISOLATED CUTOVER REHEARSAL RAPORU

**Tarih:** 2026-10-21  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Branch:** `main`  
**Mevcut HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Aşama Kararı:** `MAINTENANCE_UI_PASS_ISOLATED_ONLY` & `ISOLATED_CUTOVER_REHEARSAL_PASS`  

---

## 1. BAŞLANGIÇ VE BİTİŞ GİT DURUMU

### Başlangıç Git Doğrulaması
```powershell
git rev-parse HEAD
# Çıktı: 28c158d88028f139e93f78982d4651ad424c61d2

git branch --show-current
# Çıktı: main

git log -5 --oneline
# 28c158d8 fix(test): align splash screen error title expectation and bump version to 1.3.143+298
# 8c6d7682 feat(observability): mask internal errors from users, route fatal events to sentry/telemetry with correlation reference, and bump to v1.3.143+297
# 206557f3 fix(db): drop immutability triggers before migrations and bump version to 1.3.143+296
# fa704af1 chore(release): bump version to 1.3.143+295 for production deployment
# 567680fa fix(server): resolve TS18048 undefined activation check in billing bank-transfer routes
```

### Bitiş Git Durumu
- **HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Değişmedi, commit/push/release yapılmadı)
- **Branch:** `main`
- **`git diff --check`:** Temiz, hiçbir whitespace veya biçim hatası yok (Exit Code: 0).
- **Mevcut Değişiklik Koruması:** Kullanıcının önceki çalışmaları ve değiştirilmiş dosyaları korunmuştur.

---

## 2. DEĞİŞMEZ ÜRETİM GÜVENLİĞİ DENETİMİ

Nutopia Fındık Değirmeni, Erkul Çeyiz ve Serenut aktif üretim ortamında çalışan işletmelerdir.

| Güvenlik Parametresi | Beklenen Değer | Gerçekleşen Değer | Durum |
| :--- | :--- | :--- | :---: |
| `coreNextSalesEngineEnabledProvider` | `false` | `false` (`sales_controller.dart:105`) | **KORUNDU** |
| `DatabaseManager.databaseRoutingHook` | `null` | `null` (`database_provider.dart:49`) | **KORUNDU** |
| Legacy Veritabanı Üretim Kaynağı | Aktif Üretim Kaynağı | Aktif, hiçbir yönlendirme yapılmadı | **KORUNDU** |
| Canlı DB Üzerinde Yazma / Delta / Geçiş | Kesinlikle Yasak | 0 canlı yazma, 0 canlı delta | **KORUNDU** |
| Canlı Veritabanı Dosyaları (Nutopia / Erkul / Serenut) | Değiştirilemez | Dokunulmadı, silinmedi, taşınmadı | **KORUNDU** |
| Canlı Test Satış / Tahsilat / Stok İşlemi | Yapılmayacak | Yalnızca geçici izole test DB'leri kullanıldı | **KORUNDU** |
| Otomatik Commit / Push / Release | Yasak | 0 commit, 0 push, 0 tag, 0 release | **KORUNDU** |

---

## 3. STAGE 10.12.59 İDDİALARININ BAĞIMSIZ DOĞRULAMA SONUCU

Stage 10.12.60 kapsamında Stage 10.12.59 iddiaları 8 kritik soru altında kod tabanında bağımsız olarak denetlenmiştir:

1. **Kilit Dosyasının Konumu:**
   - Üretim kodunda kullanılan yetkili dosya `lib/infrastructure/migration/cutoff_maintenance_lock.dart` olup, `core_next/client_core/lib/infrastructure/migration/cutoff_maintenance_lock.dart` ile senkronize tutulmaktadır. Proje içi bağımlılıklar standart `package:serenutos/infrastructure/migration/cutoff_maintenance_lock.dart` üzerinden bağlanmıştır.
2. **Kilit Nesnesinin Tekil (Singleton) Ömrü:**
   - Bütün servisler (`DbGatewayImpl`, `SalesController`, `OrdersController`, `PersistentPrintQueue`, `TelemetryUploadService`, `SyncNotifier`, `AppBootstrap`), `DatabaseManager.cutoffMaintenanceLock` statik nesnesini referans almaktadır. Ayrı/çelişen kilit instance'ı bulunmamaktadır.
3. **Bütün Yazma Metotlarının Kilide Bağlantısı:**
   - `DbGatewayImpl` üzerindeki tüm yazma metotları (`insert`, `update`, `delete`, `execute`, `rawInsert`, `rawUpdate`, `rawDelete`, `transaction`), `_waitForWriteLock` ve kök `runTrackedWrite` üzerinden merkezi kilit ve drainer'a bağlanmıştır.
4. **Gateway Transaction'ları ve Nested Çağrılar:**
   - `Zone.current[#sqlite_txn]` kontrolü sayesinde, başlamış bir ana transaction içindeki alt sorguların drainer sayacını mükerrer artırması veya alt seviyede kilitlenmesi engellenmiştir. `_checkLock(isInsideTransaction: true)` ile transaction atomikliği korunmuş, drainer'ın transaction'ın commit/rollback ile tamamlanmasını beklemesi sağlanmıştır.
5. **Kalıcı Depolamanın (SharedPreferences) Uygulama Başlangıcında Yüklenmesi:**
   - *Stage 59'da sınıf tanımlanmış ancak `AppBootstrap` içine henüz bağlanmamıştı.*  
   - **Stage 60 Çözümü:** `AppBootstrap.initPreApp()` içine `CutoffMaintenanceLock(storage: SharedPreferencesMaintenanceStorage.withInstance(prefs))` entegrasyonu eklenmiş ve `initializeFromStorage()` çağrısı yerleştirilmiştir.
6. **Kilit Durumu Yüklenmeden Yazmaların Başlama Riski:**
   - `AppBootstrap.initPreApp()` akışında veritabanı gateway'i ve repository'ler ayağa kalkmadan önce kilit durumu okunmakta; okuma başarısız olursa sistem `CutoffMaintenancePhase.locked` (fail-closed) modunda başlamaktadır.
7. **Alt Seviye Yazma Koruması:**
   - Sadece controller girişleri değil, doğrudan `DatabaseManager.waitForWriteLock` ve `DbGatewayImpl` seviyesinde merkezi kontrol devrededir.
8. **Telemetri, Senkronizasyon ve Yazdırma Kuyruğunun Satış Akışına Etkisi:**
   - `TelemetryUploadService` kilit aktifken `CutoffMaintenanceActiveException` durumunu sessizce yakalar ve satışı durdurmaz. `PersistentPrintQueue` kilit altında hata kaydı oluşturur. `SyncNotifier` kilit devredeyken erken çıkış (early exit) yaparak senkronizasyonu askıya alır.

---

## 4. DEĞİŞTİRİLEN VE EKLENEN DOSYALAR

1. `lib/presentation/widgets/cutoff_maintenance_banner_widget.dart` (Yeni Eklendi):
   - Reaktif Riverpod tabanlı bakım durumu afişi. `idle` durumunda sıfır alan kaplar; `draining`, `locked`, `releasing` ve `error` durumlarında kullanıcıya anlaşılır Türkçe durum ve yönlendirme sunar.
2. `lib/presentation/widgets/app_shell.dart` (Güncellendi):
   - `CutoffMaintenanceBannerWidget`, `AppShell`'in `Stack` gövdesinin en üstüne (`SafeArea`) yerleştirilerek tüm sekmelerde (POS, Siparişler, Müşteriler, Ürünler) görünür kılındı.
3. `lib/presentation/widgets/sales/checkout_section.dart` (Güncellendi):
   - Ödeme paneli (`_buildPaymentButtons`), bakım kilidi aktifken butonları devre dışı bırakır (`disabled: true`) ve inline uyarı kutusu (`Key('checkout_maintenance_locked_warning')`) görüntüler.
4. `lib/infrastructure/bootstrap/app_bootstrap.dart` (Güncellendi):
   - `AppBootstrap.initPreApp()` aşamasında `CutoffMaintenanceLock` kalıcı depolamadan (`SharedPreferencesMaintenanceStorage.withInstance(prefs)`) yüklenir ve fail-closed korumayla `DatabaseManager.cutoffMaintenanceLock`'a atanır.
5. `lib/infrastructure/migration/cutoff_maintenance_lock.dart` & `core_next/client_core/...`:
   - `stateStream` altyapısı `async*` olarak güncellenerek yeni abonelere mevcut durum anında iletilecek biçimde yapılandırıldı.
   - `SharedPreferencesMaintenanceStorage.withInstance(prefs)` constructor'ı eklendi.
   - Acil durum ve testler için `setFailClosedError([message])` eklendi.
6. `lib/providers/database_provider.dart` (Güncellendi):
   - `cutoffMaintenanceStateProvider` ilk stream olayı gelmeden önce mevcut `lock.state`'i anında sağlayacak biçimde güncellendi.
7. `test/core_next/stage10_12_60_maintenance_ui_cutover_rehearsal_test.dart` (Yeni Eklendi):
   - Bakım UI, yazma kilitleri, hata modları ve izole cutover provasını doğrulayan 12 senaryoluk test paketi.

---

## 5. REAKTİF BAKIM EKRANI (MAINTENANCE UI) ENTEGRASYONU

### UI Davranış Matrisi:

| Bakım Fazı (`phase`) | Afiş Durumu | Renk / İkon | Kullanıcıya Gösterilen Mesaj | POS Butonları |
| :--- | :---: | :---: | :--- | :---: |
| `idle` | **Görünmez** | — | — | **Aktif** |
| `lockingRequested` / `draining` | **Görünür** | Amber / Kum Saati + Spinner | "Veritabanı Bakım Moduna Alınıyor: Devam eden işlemler tamamlanıyor..." | **Devre Dışı** |
| `locked` | **Görünür** | Slate-800 / Kilit | "Sistem Bakım Modunda (Yazma Koruması Aktif): Veritabanı kesim güvenliği için yeni satış, sipariş ve tahsilat işlemleri durduruldu." | **Devre Dışı** |
| `releasing` | **Görünür** | Teal / Açık Kilit + Spinner | "Bakım Kilidi Kaldırılıyor: Normal operasyona dönülüyor, lütfen bekleyin..." | **Devre Dışı** |
| `error` | **Görünür** | Kırmızı / Hata | "Kritik Veritabanı Bakım Koruması (Fail-Closed): Veri bütünlüğünü korumak için yazma işlemleri durduruldu." | **Devre Dışı** |

- **Yetkisiz Kilit Açma Engeli:** Kullanıcı arayüzünde kilidi yetkisiz kaldırabilecek hiçbir buton veya bypass mekanizması yer almaz.
- **Güvenlik Ayrımı:** UI afişi yalnızca bilgilendirme amaçlıdır; asıl güvenlik ve engelleme veritabanı gateway katmanında icra edilir.

---

## 6. TÜM SQLITE YAZMA YOLLARI KORUMA SINIFI

| No | Yazma Yolu / Bileşen | Kod Konumu | Koruma Sınıfı | İcra / Doğrulama Yolu |
| :---: | :--- | :--- | :---: | :--- |
| 1 | Satış Tamamlama | `sales_controller.dart:159`, `checkout_section.dart:728` | **`LOCK_PROTECTED`** | UI buton engeli + Controller fail-fast + DbGateway drainer |
| 2 | Karma Ödeme | `sales_controller.dart:301`, `checkout_section.dart:748` | **`LOCK_PROTECTED`** | UI buton engeli + Transaction atomikliği koruması |
| 3 | Sipariş İşlemleri | `orders_controller.dart:207,301,512,691,939` | **`LOCK_PROTECTED`** | Controller kilit denetimi + DbGateway serialized drainer |
| 4 | Sipariş İade / Tahsilat | `orders_controller.dart:939`, `sales_controller.dart:241` | **`LOCK_PROTECTED`** | Transaction korumalı kök drainer takibi |
| 5 | Stok Düşümü & Düzeltme | `StockRepository` -> `DbGateway.transaction` | **`LOCK_PROTECTED`** | Nested transaction bypass korumalı kök yazma takibi |
| 6 | Müşteri & Finansal Defter | `customers_repository.dart`, `financial_repository.dart` | **`LOCK_PROTECTED`** | `DbGateway.assertWritePermitted` + serialized kuyruk |
| 7 | Sync Outbox & Events | `sync_v4_service.dart` -> `sync_outbox.dart` | **`LOCK_PROTECTED`** | Kilit devredeyken outbox yazmaları anında reddedilir |
| 8 | Arka Plan Senkronizasyonu | `sync_provider.dart:191,301` | **`LOCK_PROTECTED`** | `triggerSync` ve `forceFullSync` kilit aktifken erken çıkış yapar |
| 9 | Telemetri & Log Kayıtları | `telemetry_upload_service.dart:22,51` | **`LOCK_PROTECTED`** | Kilit aktifken yerel DB yazması sessizce engellenir |
| 10 | Yazdırma Kuyruğu | `persistent_print_queue.dart:144,214,230,247` | **`LOCK_PROTECTED`** | `enqueue`, `markPrinting`, `markDone`, `markFailed` fail-fast |
| 11 | Boot & Background Görevler | `app_bootstrap.dart:123`, `database_provider.dart:71` | **`LOCK_PROTECTED`** | `DatabaseManager.waitForWriteLock` seviyesinde merkezi blokaj |

---

## 7. İZOLE CUTOVER PROVASI (ISOLATED CUTOVER REHEARSAL)

Canlı işletme verilerine dokunulmadan, geçici dosya sisteminde izole kaynak ve hedef veritabanları oluşturularak tam prova yürütülmüştür:

1. **İzole Ortam Kurulumu:**
   - Kaynak: `legacy_source.db` (500g Fındık, Fındık Ezmesi, Cari Bakiye, Canlı Satış ve Tahsilat).
   - Hedef: `core_next_target.db` (İzole şema).
2. **Kilit İsteme ve Boşaltma (Draining):**
   - `acquireLock(tenantId: 'tenant_nutopia')` tetiklendi. Devam eden işlemler sıfırlandı (`inFlightCount == 0`), faz `locked` durumuna geçti.
3. **Kilit Altında Güvenli Snapshot:**
   - Kilitli fazda kaynak veritabanından snapshot alındı; yeni yazmalar denenip anında reddedildi.
4. **Hedefe Aktarım ve Mutabakat (Reconciliation):**
   - Ürün sayısı: 2 / 2 (Tam mutabık).
   - Cari hesap sayısı: 1 / 1 (Tam mutabık).
   - Satış adedi: 1 / 1 (Tam mutabık).
   - Finansal hareket adedi: 1 / 1 (Tam mutabık).
   - Finansal ciro toplamı: 400.00 TL == 400.00 TL (Kuruşu kuruşuna mutabık).
5. **Kasıtlı Hata Senaryosu:**
   - Tutar uyuşmazlığı oluşturulduğunda (`source: 1000 TL` vs `target: 850 TL`), mutabakat kapısı geçişi anında reddetti ve `DatabaseManager.databaseRoutingHook = null` korundu.

---

## 8. TEST SONUÇLARI VE ÇALIŞTIRILAN KOMUTLAR

### 8.1. Stage 10.12.60 Özel Test Paketi
```powershell
flutter test test/core_next/stage10_12_60_maintenance_ui_cutover_rehearsal_test.dart
```
- **Sonuç:** **12/12 PASS** (Süre: 8s, Exit Code: 0)
- **Doğrulanan:** 2 Güvenlik Sınırı + 4 UI Senaryosu + 4 Kilit/Servis Senaryosu + 2 İzole Prova Senaryosu.

### 8.2. Stages 10.12.58 – 10.12.60 Birleşik Test Paketi
```powershell
flutter test test/core_next/stage10_12_58_cutoff_lock_drainer_test.dart test/core_next/stage10_12_59_central_write_lock_integration_test.dart test/core_next/stage10_12_60_maintenance_ui_cutover_rehearsal_test.dart
```
- **Sonuç:** **40/40 PASS** (Süre: 9s, Exit Code: 0)

### 8.3. Stages 10.12.50 – 10.12.60 Kapsamlı Regresyon Paketi (11 Test Dosyası)
```powershell
flutter test test/core_next/stage10_12_50_nutopia_erkul_data_safety_test.dart ... test/core_next/stage10_12_60_maintenance_ui_cutover_rehearsal_test.dart
```
- **Sonuç:** **121/121 PASS** (Süre: 31s, Exit Code: 0)

### 8.4. Statik Kod Analizi (Tüm Değişen Dosyalar)
```powershell
flutter analyze lib/infrastructure/bootstrap/app_bootstrap.dart lib/infrastructure/database/database_provider.dart lib/infrastructure/database/db_gateway.dart lib/infrastructure/database/database_executor_impl.dart lib/infrastructure/migration/cutoff_maintenance_lock.dart lib/infrastructure/services/persistent_print_queue.dart lib/infrastructure/services/telemetry_upload_service.dart lib/presentation/widgets/app_shell.dart lib/presentation/widgets/cutoff_maintenance_banner_widget.dart lib/presentation/widgets/sales/checkout_section.dart lib/providers/database_provider.dart test/core_next/stage10_12_59_central_write_lock_integration_test.dart test/core_next/stage10_12_60_maintenance_ui_cutover_rehearsal_test.dart
```
- **Sonuç:** **Analyzing 13 items... No issues found!** (Süre: 11.9s, Exit Code: 0)

---

## 9. CANLI DB ERİŞİM DENETİMİ VE GÜVENLİK SINIRLARI

- Canlı veritabanı yollarına hiçbir şekilde erişilmemiştir.
- Nutopia, Erkul ve Serenut işletmelerinin canlı DB/WAL dosyalarına dokunulmamıştır.
- Canlıda test satışı, ödemesi, tahsilatı veya stok hareketi yapılmamıştır.
- Bütün testler bellek içi (`in-memory`) veya geçici sistem dizininde (`Directory.systemTemp`) izole DB'ler ile gerçekleştirilmiştir.

---

## 10. AÇIK KALAN ENGELLER

1. **Canlıda Pilot Denemesi Yapılmamıştır:** Testler izole ortamda yeşil olsa da canlı üretim ortamında pilot geçiş henüz yürütülmemiştir.
2. **Kullanıcı Onayı ve Nihai Koordinasyon:** İşletme sahipleriyle mutabakat yapılmadan ve son geri dönüş (rollback) tatbikatı tamamlanmadan cutover başlatılamaz.

---

## 11. STAGE 10.12.61 İÇİN SIRALI SONRAKİ ADIMLAR

1. **Son Kullanıcı / Kasiyer Geri Bildirim Entegrasyonu:**
   - Kilit devredeyken POS üzerinde sepet ürün ekleme/çıkarma işlemlerinin de kullanıcıyı bilgilendirerek engellenmesini sağlamak.
2. **Canlı Dışı 3 İşletme İçin Sıralı Export/Import Provası:**
   - Nutopia, Erkul ve Serenut izole kopyaları üzerinde ayrı ayrı son delta yakalama ve şema taşıma zaman ölçümlerinin yapılması.
3. **Nihai Cutover Preflight Gate:**
   - Canlı geçiş öncesi otomatik doğrulanabilir sistem kontrol listesi betiğinin hazırlanması.

---

## 12. AŞAMA KARARI VE DEĞİŞMEZ BİLDİRİM

```text
MAINTENANCE_UI_PASS_ISOLATED_ONLY
ISOLATED_CUTOVER_REHEARSAL_PASS

CUTOVER: NOT APPROVED
LIVE DATABASE WRITES: NOT PERFORMED
CORE NEXT SALES ENGINE: DISABLED
DATABASE ROUTING HOOK: NULL
OLD DATABASE RETIREMENT: NOT APPROVED
```
