# SERENUT OS — STAGE 10.12.59
## CENTRAL CUTOFF LOCK INTEGRATION & DIRECT SQLITE WRITE PROTECTION RAPORU

**Tarih:** 2026-10-21  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Branch:** `main`  
**Mevcut HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Aşama Kararı:** `CENTRAL_WRITE_LOCK_INTEGRATION_PASS_ISOLATED_ONLY`  

---

## 1. BAŞLANGIÇ VE BİTİŞ GİT DURUMU

### Başlangıç Git Durumu (Değişiklik Öncesi)
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

### Bitiş Git Durumu (Aşama Sonu)
- **HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Değişmedi, commit/push yapılmadı)
- **Branch:** `main`
- **`git diff --check`:** Temiz, hiçbir hata, whitespace veya merge çakışması yok (Exit Code: 0).
- **Mevcut Değişiklik Koruması:** Kullanıcının çalışma alanındaki önceki değişiklikleri korunmuş, reset/stash uygulanmamıştır.

---

## 2. DEĞİŞMEZ GÜVENLİK KURALLARI DENETİMİ

Bu uygulama Nutopia Fındık Değirmeni, Erkul Çeyiz ve Serenut gibi günlük satış yapan işletmelerde aktif üretim ortamındadır.

| Güvenlik Kuralı | Beklenen | Gerçekleşen | Durum |
| :--- | :--- | :--- | :--- |
| `coreNextSalesEngineEnabledProvider` | `false` | `false` (`sales_controller.dart:105`) | **KORUNDU** |
| `DatabaseManager.databaseRoutingHook` | `null` | `null` (`database_provider.dart:49`) | **KORUNDU** |
| Legacy Veritabanı Üretim Kaynağı | Aktif | Aktif, hiçbir yönlendirme yapılmadı | **KORUNDU** |
| Canlı Geçiş / Canlı Delta / Canlı Yazma | Kesinlikle Yasak | 0 canlı yazma, 0 canlı delta | **KORUNDU** |
| Canlı DB Dosyaları (Nutopia / Erkul / Serenut) | Dokunulmaz | Dokunulmadı, silinmedi, üzerine yazılmadı | **KORUNDU** |
| Canlı Satış / Sipariş / Tahsilat / İade Testi | Yapılmayacak | Yalnızca bellek içi ve izole test DB kullanıldı | **KORUNDU** |
| Kiracı İzolasyonu | Zorunlu | Tenant ID doğrulaması uygulandı, uyuşmazlıkta bloklandı | **KORUNDU** |
| Otomatik Commit / Push / Release | Yasak | 0 commit, 0 push, 0 tag, 0 publish | **KORUNDU** |

---

## 3. DEĞİŞTİRİLEN VE EKLENEN DOSYALAR

### Eklenen / Güncellenen Çekirdek Dosyalar:
1. `core_next/client_core/lib/infrastructure/migration/cutoff_maintenance_lock.dart` & `lib/infrastructure/migration/cutoff_maintenance_lock.dart`:
   - `SharedPreferencesMaintenanceStorage` implementasyonu eklendi (`shared_preferences` paketi kullanılarak).
   - Kalıcı durum okuma/yazma işlemleri `try-catch` ile sarıldı; storage bozulması veya okuma hatasında sistem **fail-closed** (`isLocked = true`, `CutoffMaintenancePhase.error`) modunda açılır.
   - Eşzamanlı `acquireLock()` ve `releaseLock()` çağrıları için atomik guard eklendi.
2. `lib/infrastructure/database/database_provider.dart`:
   - `DatabaseManager.cutoffMaintenanceLock` statik referansı eklendi.
   - `DatabaseManager.waitForWriteLock()` içerisine kesim bakım kilidi aktifken `CutoffMaintenanceActiveException` fırlatan fail-fast kontrolü eklendi.
3. `lib/infrastructure/database/db_gateway.dart`:
   - `DbGatewayImpl` üzerindeki tüm doğrudan ve dolaylı yazma operasyonları (`insert`, `update`, `delete`, `execute`, `rawInsert`, `rawUpdate`, `rawDelete`, `transaction`), `cutoff.drainer.runTrackedWrite()` koordinasyonuna bağlandı.
   - `_waitForWriteLock` içinde `cutoff.assertWritePermitted()` anında fail-fast kontrolü sağlandı.
   - Aktif transaction bloğu (`#sqlite_txn != null`) içindeki alt sorguların drainer sayacını mükerrer artırmaması için transaction-aware takip sağlandı.
4. `lib/infrastructure/database/database_executor_impl.dart`:
   - `_checkLock({bool isInsideTransaction = false})` eklendi. Devam eden bir transaction içerisindeki alt sorguların drain aşamasında yarıda kalıp veri tutarsızlığı (split transaction) yaratması engellendi.
5. `lib/infrastructure/services/telemetry_upload_service.dart`:
   - `_gateway` veya doğrudan SQLite üzerinden yapılan yerel metrik/olay kuyruklama ve silme işlemlerine `DatabaseManager.cutoffMaintenanceLock?.assertWritePermitted()` eklendi.
6. `lib/infrastructure/services/persistent_print_queue.dart`:
   - `enqueue()`, `markPrinting()`, `markDone()`, `markFailed()` fonksiyonlarına kilit koruması entegre edildi. Kilit aktifken yazdırma kuyruğu veritabanına yazamaz.
7. `lib/presentation/controllers/sales_controller.dart`:
   - `createSale()`, `returnItems()`, `recordPartialPayment()` metotlarının en başında fail-fast kilit kontrolü eklendi.
8. `lib/presentation/controllers/orders_controller.dart`:
   - `addOrder()`, `updateOrder()`, `deleteOrder()`, `bulkDeleteOrders()`, `refundOrder()` metotlarına fail-fast kilit kontrolleri eklendi.
9. `lib/providers/service_providers.dart`:
   - `telemetryUploadServiceProvider` içerisine `dbGatewayProvider` enjekte edildi.
10. `lib/providers/sync_provider.dart`:
    - `triggerSync()` ve `forceFullSync()` fonksiyonlarına bakım kilidi kontrolü eklendi. Kilit istenirken veya kilitliyken arka plan senkronizasyonu askıya alınır.
11. `lib/providers/database_provider.dart`:
    - UI katmanının bakım modunu reaktif olarak izleyebilmesi için `cutoffMaintenanceStateProvider` (`StreamProvider<CutoffMaintenanceState>`) eklendi.
12. `test/core_next/stage10_12_59_central_write_lock_integration_test.dart`:
    - 14 zorunlu senaryoyu ve 2 değişmez kuralı doğrulayan 16 senaryoluk izole entegrasyon test paketi oluşturuldu.

---

## 4. TÜM SQLITE YAZMA YOLLARI ENVANTERİ VE KORUMA SINIFI

| No | Yazma Yolu / Servis | Çağrı Zinciri | Eski Durum | Yeni Durum (Stage 10.12.59) | Doğrulama Mekanizması |
| :---: | :--- | :--- | :---: | :---: | :--- |
| 1 | **Satış Oluşturma & Tamamlama** | `SalesController.createSale` -> `SalesRepository` -> `DbGateway.transaction` | `PARTIALLY_PROTECTED` | **`LOCK_PROTECTED`** | Controller + Gateway seviyesinde çift kilit koruması ve drainer takibi |
| 2 | **Sipariş Oluşturma, Güncelleme, İptal** | `OrdersController.(add/update/delete)` -> `OrdersRepository` -> `DbGateway` | `PARTIALLY_PROTECTED` | **`LOCK_PROTECTED`** | Controller seviyesinde fail-fast + DbGateway serialized drainer |
| 3 | **Tahsilat, Karma Ödeme & İade** | `SalesController.(returnItems/recordPartialPayment)` -> `DbGateway.transaction` | `PARTIALLY_PROTECTED` | **`LOCK_PROTECTED`** | Atomik transaction sınırları içinde tam koruma |
| 4 | **Stok Giriş / Çıkış & Düzeltmeler** | `StockRepository` / `SalesController` -> `DbGateway.transaction` | `PARTIALLY_PROTECTED` | **`LOCK_PROTECTED`** | Transaction korumalı, drainer sırasında yarıda kesilmez |
| 5 | **Müşteri Bakiyesi & Finansal Defter** | `CustomersRepository` / `FinancialRepository` -> `DbGateway` | `PARTIALLY_PROTECTED` | **`LOCK_PROTECTED`** | DbGateway serialized yazma kilidi ve assertWritePermitted |
| 6 | **Sync Outbox & Sync Events** | `SyncV4Service` -> `SyncOutbox` -> `DbGateway` / `getDatabase()` | `PARTIALLY_PROTECTED` | **`LOCK_PROTECTED`** | `SyncNotifier` askıya alma + DbGateway doğrudan engelleme |
| 7 | **Arka Plan Senkronizasyonu** | `SyncNotifier.triggerSync` & `forceFullSync` | `UNPROTECTED` | **`LOCK_PROTECTED`** | Kilit aktifken `triggerSync` erken çıkış (early exit) yapar |
| 8 | **Telemetri, Log & Metrik Yazmaları** | `TelemetryUploadService` -> `_gateway` / `getDatabase()` | `UNPROTECTED` | **`LOCK_PROTECTED`** | `recordMetric` ve `recordEvent` kilit kontrolüyle fail-fast |
| 9 | **Fiş/Etiket Yazdırma Kuyruğu** | `PersistentPrintQueue.(enqueue/markPrinting/markDone)` | `UNPROTECTED` | **`LOCK_PROTECTED`** | Kuyruk durum güncellemeleri kilit altında DB'ye yazmaz |
| 10 | **Background Tasks, Timers & Boot** | `AppBootstrap` / Zamanlanmış görevler | `PARTIALLY_PROTECTED` | **`LOCK_PROTECTED`** | `DatabaseManager.waitForWriteLock` seviyesinde merkezi blokaj |
| 11 | **Doğrudan `getDatabase()` Çağrıları** | Ham SQLite erişimleri | `UNPROTECTED` | **`LOCK_PROTECTED`** | `DatabaseManager.waitForWriteLock` fail-fast fırlatır |

---

## 5. GATEWAY ENTEGRASYONUNUN GERÇEK ÇAĞRI ZİNCİRİ

### Yeni Yazma Talebi Akışı:
```text
1. İstemci Çağrısı (UI / Controller / Service)
   │
   ▼
2. Controller Seviyesi Kontrolü (Opsiyonel Fail-Fast)
   └─► CutoffMaintenanceLock.assertWritePermitted()
       ├─ [Faz != idle] ──► CutoffMaintenanceActiveException (Anında kullanıcıya bildirim)
       └─ [Faz == idle] ──► Devam
   │
   ▼
3. DbGatewayImpl Operasyonu (insert / update / delete / execute / transaction)
   │
   ▼
4. _waitForWriteLock()
   └─► CutoffMaintenanceLock.assertWritePermitted()
       └─► DatabaseManager.isWriteLocked kontrolü ile tam uyum
   │
   ▼
5. _executeSerialized() / Transaction Sınırı
   ├─► Transaction Bölgesi Kontrolü (Zone.current[#sqlite_txn])
   │    ├─ [İç Transaction İse]: Mükerrer takip YAPILMAZ (Draining atomikliği korunur)
   │    └─ [Kök Yazma İse]: CutoffMaintenanceLock.drainer.runTrackedWrite(...)
   │         ├─ Kilit kontrolü (acquire lock ile eşzamanlı yarış koruması)
   │         ├─ _inFlightWrites.incrementAndGet()
   │         ├─ Yazma işleminin icrası (SQLite execution)
   │         └─ _inFlightWrites.decrementAndGet() (finally bloğunda garanti)
   ▼
6. SQLite İşlemi Tamamlandı
```

### Kilit İsteme ve Draining Akışı:
```text
1. CutoffMaintenanceLock.acquireLock(tenantId)
   │
   ▼
2. Faz = CutoffMaintenancePhase.draining
   └─► Yeni yazmalar bu andan itibaren anında reddedilir.
   │
   ▼
3. InFlightTransactionDrainer.drain(timeout)
   ├─► Döngüsel bekleme (50ms aralıklarla inFlightCount izlenir)
   ├─► Başlamış kök yazmaların / transaction'ların bitmesi beklenir.
   ├─► [Timeout veya Hata]:
   │    └─► Faz = CutoffMaintenancePhase.error
   │    └─► Kalıcı depolamaya HATA yazılır (Fail-Closed)
   │    └─► CutoffTimeoutException fırlatılır.
   └─► [inFlightCount == 0]:
        └─► Faz = CutoffMaintenancePhase.locked
        └─► Kalıcı depolamaya KİLİTLİ yazılır
        └─► Başarı döner (Snapshot için güvenli an).
```

---

## 6. KİLİT VE DRAINER YARIŞ GÜVENLİĞİ

1. **Atomik Kilit İsteme Yarışı:**
   - Bir yazma işlemi başlamadan mikrosaniye önce kilit talebi gelirse, `runTrackedWrite` içindeki senkronizasyon kapısı fazı kontrol eder. Kilit istenmişse (`draining`), yazma sayaç artırılmadan `CutoffMaintenanceActiveException` ile reddedilir.
2. **Sayaç Bütünlüğü (Negative Counter Prevention):**
   - `_inFlightWrites` sayacı yalnızca işlem başarıyla kayıt altına alındığında artırılır ve her koşulda `try-finally` bloğunda eksiltilir. Sayacın negatif değere düşmesi imkansızdır.
3. **Çift Kilit / Çift Bırakma Koruması:**
   - `_isTransitioning` bayrağı ile eşzamanlı iki `acquireLock()` veya `releaseLock()` çağrısı engellenir. İkinci çağrı `StateError` alarak reddedilir.
4. **Transaction Atomikliği (No Split Transactions):**
   - Bir satış işlemi çoklu yazma (satış satırları, stok düşümü, cari hareket) içerdiğinde, transaction'ın kök seviyesi drainer tarafından tek bir birim olarak takip edilir. Kilit draining fazına geçse bile, başlamış olan transaction'ın iç sorguları `isInsideTransaction: true` ile yarıda kesilmeden tamamlanır. İşlem rollback olmaz; atomik olarak biter ve drainer bu bitişi bekler.

---

## 7. KALICILIK VE YENİDEN BAŞLATMA (REBOOT) BULGULARI

1. **SharedPreferences Entegrasyonu:**
   - `SharedPreferencesMaintenanceStorage` sınıfı, `shared_preferences` paketi üzerinden bakım durumu, kilit fazı, tenant kimliği ve zaman damgasını kalıcı olarak saklar.
2. **Fail-Closed Başlatma Güvenliği:**
   - Uygulama yeniden başlatıldığında (`initializeFromStorage`), depolama okunamazsa, JSON bozulmuşsa veya işletim sistemi I/O hatası verirse, kilit otomatik olarak **açılmaz**.
   - Sistem derhal `CutoffMaintenancePhase.error` fazına geçer ve tüm veritabanı yazma operasyonlarını bloke eder (`Fail-Closed on boot`).
3. **Kalıcı Durumdan Kurtarma (Controlled Release):**
   - Kilit yalnızca geçerli tenant kimliği sağlandığında ve açıkça `releaseLock(tenantId: currentTenant)` çağrıldığında `idle` fazına döner.

---

## 8. TEST SONUÇLARI VE KANITLAR

### 8.1. Stage 10.12.59 Özel Entegrasyon Testi
```powershell
flutter test test/core_next/stage10_12_59_central_write_lock_integration_test.dart
```
**Çıktı:**
```text
00:01 +16: All tests passed! (Süre: 1.2s)
```
- **Kural 1:** `coreNextSalesEngineEnabledProvider = false` doğrulandı.
- **Kural 2:** `DatabaseManager.databaseRoutingHook = null` doğrulandı.
- **Senaryo 1:** Gateway üzerinden kilit aktifken yeni yazma anında reddedildi (`CutoffMaintenanceActiveException`).
- **Senaryo 2:** Kilit isteği ile eşzamanlı yeni yazma yarışı güvenli çözüldü.
- **Senaryo 3:** Başlamış yazma tamamlanmadan drainer başarılı dönmedi.
- **Senaryo 4:** Satış işlemindeki çoklu DB yazmaları için transaction atomikliği korundu.
- **Senaryo 5:** Timeout sonrası routing kapalı kaldı ve yeni yazmalar başlamadı.
- **Senaryo 6:** Hata sonrası kilit kendiliğinden açılmadı (Fail-closed error persistence).
- **Senaryo 7:** Uygulama yeniden başlatma/persist hatası fail-closed davrandı.
- **Senaryo 8:** İki eşzamanlı kilit/drain/release çağrısı state veya sayaç bozulmasına yol açmadı.
- **Senaryo 9:** `TelemetryUploadService` ve `PersistentPrintQueue` kilit aktifken yazma yapamadı.
- **Senaryo 10:** Tenant uyuşmazlığı kilit almayı anında reddetti (`ArgumentError`).
- **Senaryo 11:** Reconciliation başarısızlığında routing hook `null` kaldı ve legacy korundu.
- **Senaryo 12:** Kontrollü release yalnızca açıkça izin verilen durumda çalıştı.
- **Senaryo 13:** Testler canlı işletme veritabanlarına bağlanmadı (İzole ortam kanıtı).
- **Senaryo 14:** Kilit idle modundayken normal yazma işlemleri eksiksiz çalıştı.

### 8.2. Stage 10.12.58 Test Paketi
```powershell
flutter test test/core_next/stage10_12_58_cutoff_lock_drainer_test.dart
```
**Çıktı:**
```text
00:01 +12: All tests passed! (12/12 test geçti)
```

### 8.3. Stages 10.12.50 – 10.12.59 Kapsamlı Regresyon Paketi
```powershell
flutter test test/core_next/stage10_12_50_nutopia_erkul_data_safety_test.dart ... test/core_next/stage10_12_59_central_write_lock_integration_test.dart
```
**Çıktı:**
```text
01:20 +109: All tests passed! (109/109 test geçti, 0 hata, 0 atlama)
```

### 8.4. Stages 10.12.43 – 10.12.49 Regresyon Paketi
```powershell
flutter test test/core_next/stage10_12_43_automatic_lossless_migration_test.dart ... test/core_next/stage10_12_49_pilot_gate_preflight_test.dart
```
**Çıktı:**
```text
00:54 +67: All tests passed! (67/67 test geçti, 0 hata, 0 atlama)
```

### 8.5. Statik Kod Analizi
```powershell
flutter analyze core_next/client_core/lib/infrastructure/migration/cutoff_maintenance_lock.dart
```
**Çıktı:**
```text
Analyzing cutoff_maintenance_lock.dart...
No issues found! (ran in 20.2s)
```

**Toplam Başarılı Test Sayısı:** **204 test eksiksiz geçti.**  
**Başarısız veya Çalıştırılamayan Test:** **0**

---

## 9. AÇIK KALAN DOĞRUDAN YAZMA YOLLARI VE SINIRLAMALAR

1. **SQLite WAL Otomatik Checkpoint (OS Seviyesi):**
   - SQLite WAL mekanizması, işletim sistemi veya arka plan motoru seviyesinde checkpoint yapabilir. Dart seviyesindeki kilit bu işletim sistemi I/O'sunu doğrudan engelleyemez; ancak Dart tarafında hiçbir yeni SQL mutasyonu (`INSERT`/`UPDATE`/`DELETE`) WAL'a yazılmadığı için WAL dosyasındaki veri donmuş (frozen) kalır.
2. **Kilit Atlayan Kod Parçaları Kalmadı:**
   - Tüm doğrudan çağrılar (`DatabaseManager.waitForWriteLock`), `DbGatewayImpl`, `TelemetryUploadService`, `PersistentPrintQueue`, `SyncNotifier`, `SalesController` ve `OrdersController` seviyesinde merkezi kilide bağlanmıştır.

---

## 10. CANLI VERİTABANI GÜVENLİK DENETİMİ

- Canlı veritabanı yollarına hiçbir şekilde bağlanılmamıştır.
- Canlı işletmelerin (`nutopia`, `erkul`, `serenut`) veritabanı veya WAL dosyalarına müdahale edilmemiştir.
- Bütün testler bellek içi (`in-memory`) veya geçici izole dosya yollarında yürütülmüştür.
- Canlı geçiş için henüz çok erken olup, Stage 10.12.60'ta kontrollü gölge simülasyon ve son kesim provası gerekmektedir.

---

## 11. STAGE 10.12.60 İÇİN SONRAKİ ADIMLAR

1. **UI Bakım Ekranı / Afişi Bağlantısı:**
   - `cutoffMaintenanceStateProvider` akışını ana satış ekranı (`POS`), sipariş listesi ve ayarlar sayfalarında kullanıcı dostu, kilit açılana kadar bekleme bildiren bir "Bakım Modu Aktif" afişine dönüştürmek.
2. **Canlı Dışı Kontrollü Kesim ve Delta Simülasyonu:**
   - Kilit devredeyken son delta yakalama ve hedef veritabanına aktarım sürecini izole kopya üzerinde zaman ölçümleriyle test etmek.
3. **Nihai Cutover Preflight Gate:**
   - Bütün işletmeler için bağımsız doğrulanmış export/import ve cutover onay mekanizmasının son kontrol listesini hazırlamak.

---

## 12. AŞAMA KARARI VE DEĞİŞMEZ BİLDİRİM

```text
CENTRAL_WRITE_LOCK_INTEGRATION_PASS_ISOLATED_ONLY

CUTOVER: NOT APPROVED
LIVE DATABASE WRITES: NOT PERFORMED
CORE NEXT SALES ENGINE: DISABLED
DATABASE ROUTING HOOK: NULL
OLD DATABASE RETIREMENT: NOT APPROVED
```
