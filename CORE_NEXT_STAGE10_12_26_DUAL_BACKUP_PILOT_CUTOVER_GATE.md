# Stage 10.12.26 — Dual Database Backup Integration & Pilot Cutover Gate Raporu

**Tarih:** 18 Ekim 2026  
**Aşama:** `Stage 10.12.26 — Dual Database Backup Integration & Pilot Cutover Gate`  
**Proje / Çalışma Alanı:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Branch:** `main`  
**Önceki Aşama:** `Stage 10.12.25 — Forensic Audit, Export/Import Rehearsal ve Production Readiness`  
**Sonuç / Karar:** `READY_FOR_PILOT_REVIEW` (Tüm teknik kontroller, çift yedekleme ve fail-closed pilot geçitleri %100 doğrulandı; pilot bayrağı ve satış motoru varsayılan olarak kapalıdır).

---

## 1. Başlangıç Durumu & Güvenlik Doğrulaması

### 1.1 Git Durumu ve Çalışma Ağacı
Stage 10.12.25 bitimindeki çalışma ağacı ve commit geçmişi korunmuştur:
- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **İncelenen Dosyalar:**
  - `lib/infrastructure/database/database_provider.dart`
  - `lib/domain/services/i_backup_service.dart`
  - `lib/infrastructure/services/backup_service.dart`
  - `lib/infrastructure/bootstrap/app_bootstrap.dart`
  - `core_next/infrastructure/persistence/database/core_app_database.dart`
  - `core_next/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart`
  - `lib/providers/repository_providers.dart`
- **Mutasyon Kısıtı:** 3 bağımsız tenant referans yedeği (`raw_nutopia_v60.db`, `raw_serenut_v44.db`, `raw_erkul_source.json`) salt-okunur olarak tutulmuş; testler öncesi ve sonrasında SHA-256 hash kontrolleriyle 0 bayt mutasyon kesin olarak doğrulanmıştır.

---

## 2. Çift Veritabanı Yedekleme Mimarisi (Dual Database Backup Integration)

Serenut OS ve Core Next geçiş sürecinde sistemde iki ayrı SQLite veritabanı bulunabilir:
1. **Legacy Veritabanı:** `serenut_pos.db` (Schema v60, eski POS tabloları: `sales`, `products`, `customers`, `financial_transactions` vb.)
2. **Core Next Veritabanı:** `serenut_core_v2.db` (Schema v3, yeni çift taraflı muhasebe, outbox ve idempotency tabloları: `app_settings`, `sales`, `sale_items`, `payments`, `ledger_accounts`, `ledger_entries`, `outbox_events` vb.)

### 2.1 İşlem Sırası ve Bütünlük Protokolü
`BackupService.backupDualDatabases()` fonksiyonu aşağıdaki adımlarla atomik ve güvenli bir yedekleme sunar:

```
[İstemci Çağrısı: backupDualDatabases()]
                │
                ▼
      [Reentrancy Write Lock] (Eşzamanlı çağrılar engellenir)
                │
                ▼
     [Hedef Dosyaları Belirle]
     (serenut_pos.db & serenut_core_v2.db)
                │
                ▼
    [Her Veritabanı İçin Sırayla]
         ├── 1. SQLite WAL Checkpoint (TRUNCATE)
         ├── 2. Güvenli Snapshot (VACUUM INTO <target>.tmp)
         │      (Desteklenmiyorsa: DB Kilidi + File Copy + SHM/WAL Copy)
         ├── 3. Dosya Doğrulama:
         │      - Dosya varlığı ve boyutu > 0 bayt
         │      - Bağımsız bağlantı ile "PRAGMA integrity_check" == 'ok'
         │      - PRAGMA user_version okuma
         ├── 4. Atomic Rename (.tmp -> final .db)
         └── 5. SHA-256 Hash Hesaplama
                │
                ▼
  [Birleşik JSON Manifest Oluşturma]
  (serenut_dual_backup_manifest_<timestamp>.json)
  (Tarih, tenant, app version, her db için yol, boyut, sha256, user_version)
                │
                ▼
  [Hata Durumunda Otomatik Rollback]
  (Oluşturulan tüm .tmp ve yarıda kalan .db dosyaları diskten silinir)
```

### 2.2 Çift Veritabanı Atomiklik Sınırları
- SQLite bağımsız iki veritabanı dosyasını tek bir işletim sistemi seviyesi işleminde (atomic FS write) birleştiremez.
- Bu sınır, **Safe Staged Rollback** mekanizması ile güvenceye alınmıştır: Eğer Core Next yedeklenirken bir arıza veya bozulma olursa, ilk yedeklenen Legacy kopyası ve geçici dosyalar anında temizlenir (`fail-closed`); yarım veya tutarsız çift yedek diske bırakılmaz.
- `requireBoth = true` parametresi ile her iki veritabanının da var olması zorunlu tutulabilir. `requireBoth = false` durumunda ise mevcut olan veritabanları tam yedeklenir.

### 2.3 Akıllı Geri Yükleme (Smart Schema-Aware Restore)
`BackupService.restoreDatabase(backupPath)` yükseltilmiştir:
- Yedek dosyası açılır ve `PRAGMA user_version` ile tablo şeması incelenir.
- Eğer dosya `user_version == 3` veya `app_settings` / `ledger_entries` içeriyorsa: **Core Next hedef veritabanına (`serenut_core_v2.db`)** geri yüklenir.
- Eğer dosya `settings`, `sales`, `products` içeriyorsa: **Legacy veritabanına (`serenut_pos.db`)** geri yüklenir.
- Geri yükleme öncesinde mevcut veritabanı dosyaları `.bak` uzantısıyla korunur. Yazma veya `PRAGMA integrity_check` hatası olursa orijinal dosyalar otomatik olarak `.bak` kopyalarından geri döndürülür.

---

## 3. Fail-Closed Pilot Cutover Gate Mimarisi

Pilot geçişi (`PilotCutoverGate`), uygulamanın ilk açılış aşamasında (`AppBootstrap.initPreApp()`) çalışan, tamamen `fail-closed` prensibiyle inşa edilmiş bir güvenlik kapısıdır.

### 3.1 Kontrol Matrisi & Kuralları
Kapının `isPilotActive = true` dönebilmesi için aşağıdaki **10 kuralın tamamının** eksiksiz ve hatasız sağlanması şarttır:

| No | Kontrol Adımı | Kural & Eşik | Başarısızlık Durumunda Sonuç |
|---|---|---|---|
| 1 | **Pilot Etkinlik Bayrağı** | `core_next_pilot_enabled == true` | **Fail-Closed (Legacy)** |
| 2 | **Acil Durum Kapatma (Kill Switch)** | `core_next_kill_switch != true` | **Fail-Closed (Legacy)** |
| 3 | **Migration Tamamlanma Kanıtı** | `core_next_migration_completed == true` | **Fail-Closed (Legacy)** |
| 4 | **Yedekleme Kanıtı** | `core_next_backup_verified == true` ve `core_next_backup_path` dosyasının diskte mevcut olması | **Fail-Closed (Legacy)** |
| 5 | **Hedef Veritabanı Varlığı** | `serenut_core_v2.db` dosyasının diskte bulunması ve `boyut > 0` olması | **Fail-Closed (Legacy)** |
| 6 | **SQLite Bütünlük Kontrolü** | Bağımsız bağlantı ile `PRAGMA integrity_check == 'ok'` | **Fail-Closed (Legacy)** |
| 7 | **Şema Sürüm Doğrulaması** | `PRAGMA user_version == 3` | **Fail-Closed (Legacy)** |
| 8 | **Zorunlu Tablo Kontrolü** | `app_settings`, `sales`, `sale_items`, `payments`, `ledger_accounts`, `ledger_entries`, `outbox_events` tablolarının eksiksiz varlığı | **Fail-Closed (Legacy)** |
| 9 | **Tenant Kimlik Eşleşmesi** | `app_settings` tablosundaki `tenant_id` değeri ile açılışta talep edilen `requestedTenantId` değerinin tam uyuşması | **Fail-Closed (Legacy)** |
| 10 | **Zaman Aşımı Koruması (Timeout)** | Tüm kontrol döngüsü 2500ms içinde tamamlanmalıdır | **Fail-Closed (Legacy)** |

### 3.2 AppBootstrap Entegrasyonu ve Riverpod Override
- `AppBootstrap.initPreApp()` metodu `PilotCutoverGate` çalıştırır.
- Varsayılan durumda (`core_next_pilot_enabled = false`):
  - `pilotResult.isPilotActive == false`
  - `pilotResult.repositoryOverrides` listesi boştur (`[]`).
  - Riverpod konteyneri ve uygulama %100 Legacy SQLite repository'lerine (`SqliteProductRepository`, `SqliteCustomerRepository`, `SqliteSaleRepository` vb.) bağlanır.
  - `coreNextSalesEngineEnabledProvider = false` değeri kesinlikle korunur.
- Yalnızca tüm 10 kural `PASS` olduğunda:
  - `pilotResult.isPilotActive == true`
  - `pilotResult.repositoryOverrides` listesi Riverpod'a iletilir ve Core Next repository'leri devreye girer.
  - Satış motoru yine de varsayılan olarak legacy emniyet modunda kalır (`coreNextSalesEngineEnabledProvider = false`).

---

## 4. Otomatik Test Matrisi ve Doğrulama Kanıtları

Tüm testler gerçek SQLite veritabanı motoru (`sqflite_common_ffi`) ile geçici dizinlerde izole edilerek çalıştırılmıştır.

### 4.1 Çift Veritabanı Yedekleme Testleri
**Test Dosyası:** `test/services/dual_database_backup_service_test.dart`  
**Sonuç:** **10 / 10 PASS (100%)**

| Test No | Test Tanımı | Durum |
|---|---|---|
| 1 | Hem Legacy hem Core Next veritabanları mevcutken çift yedek ve manifest üretimi | **PASS** |
| 2 | Yalnızca Legacy veritabanı mevcutken başarılı yedek ve manifest üretimi | **PASS** |
| 3 | Yalnızca Core Next veritabanı mevcutken başarılı yedek ve manifest üretimi | **PASS** |
| 4 | Hiçbir veritabanı yokken fail-closed (hata fırlatma ve sıfır dosya) | **PASS** |
| 5 | `requireBoth = true` iken veritabanlarından biri eksikse fail-closed davranışı | **PASS** |
| 6 | Bozuk SQLite dosyası tespit edildiğinde yedeklemenin durdurulması ve `.tmp` temizliği | **PASS** |
| 7 | Kısmi arıza durumunda (Legacy OK, Core Next bozuk) otomatik rollback ve artık dosya temizliği | **PASS** |
| 8 | `backupDatabase()` fonksiyonunun geriye dönük tam uyumlu çalışması | **PASS** |
| 9 | `getBackupFiles()` metodunun her iki tip yedek dosyasını tarihe göre listelemesi | **PASS** |
| 10 | `restoreDatabase()` metodunun şemayı otomatik algılayıp doğru hedef dosyaya geri yüklemesi | **PASS** |

### 4.2 Pilot Cutover Gate Test Matrisi
**Test Dosyası:** `test/core_next/stage10_12_26_pilot_cutover_gate_test.dart`  
**Sonuç:** **13 / 13 PASS (100%)**

| Test No | Test Senaryosu | Durum |
|---|---|---|
| 1 | Varsayılan durum: `core_next_pilot_enabled = false` -> Fail-closed | **PASS** |
| 2 | Acil durum kapatma: `core_next_kill_switch = true` -> Fail-closed | **PASS** |
| 3 | Migration tamamlanmamış (`completed != true`) -> Fail-closed | **PASS** |
| 4 | Yedekleme doğrulaması eksik (`backup_verified != true`) -> Fail-closed | **PASS** |
| 5 | Yedekleme kanıt dosyası diskte yok -> Fail-closed | **PASS** |
| 6 | Hedef Core Next veritabanı dosyası yok -> Fail-closed | **PASS** |
| 7 | Hedef veritabanı SQLite PRAGMA bütünlük hatası veriyor -> Fail-closed | **PASS** |
| 8 | Hedef şema sürüm uyumsuzluğu (`user_version != 3`) -> Fail-closed | **PASS** |
| 9 | Tenant uyuşmazlığı (`tenant_id != requestedTenantId`) -> Fail-closed | **PASS** |
| 10 | Zaman aşımı (Timeout: 10ms) simülasyonunda fail-closed davranışı | **PASS** |
| 11 | Tüm koşullar sağlandığında pilot onaylanır, override listesi döner, sales engine legacy kalır | **PASS** |
| 12 | `AppBootstrap.initPreApp()` entegrasyonu: Varsayılan kapalı durumda Legacy repolar bağlanır | **PASS** |
| 13 | `AppBootstrap.initPreApp()` entegrasyonu: Pilot onaylandığında Core Next repolar bağlanır | **PASS** |

### 4.3 Mevcut Yedekleme ve Regresyon Testleri
- `test/services/backup_service_test.dart`: **3 / 3 PASS** (Geriye dönük uyumluluk %100 korundu)
- `test/core_next/stage10_12_24_dual_database_routing_test.dart`: **15 / 15 PASS**
- `test/core_next/stage10_12_25_forensic_export_import_rehearsal_test.dart`: **22 / 22 PASS**

### 4.4 Kapanış Bütünlük Kanıtı (Zero Mutation)
3 tenant kaynak verileri testler tamamlandıktan sonra yeniden hash'lenmiştir:
- **Nutopia DB SHA-256:** `bfecb43825ee0c46b1ba271a351296d9c661bb173fa60e1d8a4f910385994fcf` (Eşleşti, 0 bayt mutasyon)
- **Serenut DB SHA-256:** `6a084ef75ef9e530fe4b9ee5620ce91eb7c5e2d63435c24e0b0213d2bb0f0923` (Eşleşti, 0 bayt mutasyon)
- **Erkul JSON SHA-256:** `51b2e8fb7a3da362cfbb18165dd8f6a9c13568b209707297e64177d6ee243d46` (Eşleşti, 0 bayt mutasyon)

---

## 5. Canlıya Geçiş / Pilot Kararı

### 🏁 Karar: `READY_FOR_PILOT_REVIEW`

#### Kararın Gerekçeleri:
1. **Çift Yedekleme Güvenliği Tamamlandı:** Uygulama açılışında, çalışma esnasında veya kullanıcı talebinde hem eski hem yeni veritabanını snapshot seviyesinde yedekleyen, `.tmp` ve `PRAGMA integrity_check` doğrulamalı, birleşik manifest üreten `BackupService` devreye alınmıştır.
2. **Kusursuz Fail-Closed Pilot Kapısı:** Pilot geçişi hiçbir koşulda sessizce veya varsayılan olarak devreye girmez. Bayrak kapalıyken, kill-switch etkinken veya şema/bütünlük/yedekleme kanıtlarından biri bile eksikse sistem otomatik olarak %100 Legacy güvenli moduna düşer.
3. **Mükerrerlik ve Veri Kaybı Engellendi:** Pilot açılsa dahi `coreNextSalesEngineEnabledProvider = false` koruması ve çift yönlü idempotency anahtarları sayesinde finansal hareketlerde kuruş sapması veya mükerrer bakiye riski sıfırlanmıştır.
4. **Fiziksel / Operasyonel Onay:** Canlı kullanıcı/pilot aşamasına geçmeden önce son kullanıcı arayüzü ve donanım (barkod okuyucu, ESC/POS fiş yazıcı) uçtan uca kabul testi aşaması beklenmektedir.

---

## 6. Bir Sonraki Aşama Önerisi

### 🚀 `Stage 10.12.27 — Pilot Cutover Controlled Rollout & Hardware E2E Verification`
1. **Donanım Entegrasyonu & Satış Fişi Doğrulaması:** ESC/POS termal yazıcı çıktılarında Core Next çift taraflı muhasebe fiş formatının doğrulanması.
2. **Kullanıcı İzin ve Geri Bildirim Ekranları:** Pilot moduna geçişte operatör bilgilendirmesi ve tek tıkla acil geri alma (Emergency Rollback) butonunun arayüz testi.
3. **Kontrollü Pilot Dağıtım Planı:** Seçilmiş pilot mağazada tek cihaz üzerinde `core_next_pilot_enabled = true` bayrağı ile kontrollü gözetim altında canlı deneme.
