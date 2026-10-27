# CORE NEXT — STAGE 10.12.23
## İZOLE PİLOT PROVASI, GERÇEK VERİTABANI YÖNLENDİRME VE AÇILIŞ DAYANIKLILIĞI RAPORU

**Tarih:** 2026-10-17  
**Ortam:** Serenut OS Desktop (Windows 11 x64, Flutter 3.24.5 / Dart 3.5.4)  
**Denetçi / İcra Eden:** Antigravity Bağımsız Kod & Güvenlik Denetim Ajanı  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (`main`)  
**Doğrulanan Kaynak Yedeği:** `backups/raw_tenants_20261016/raw_nutopia_v60.db`  
**Kaynak SHA-256 İmzası:** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24`  
**Nihai Karar:** `BLOCKED — DATABASE ROUTING OR RECOVERY SAFETY GAP`

---

## 1. YÜRÜTME ÖZETİ

Stage 10.12.23 kapsamında, Core Next geçişinin izole test ortamında etkinleştirildiği senaryoda uygulamanın gerçek veritabanı yönlendirmesi (`DatabaseManager`, `DatabaseRoutingResolver`, `DbGatewayImpl`, `SqliteCustomerRepository`), açılış dayanıklılığı (UI yaşam döngüsü, olay döngüsü / isolate performansı, eşzamanlı kilitlenme koruması) ve adli veri mutabakatı derinlemesine sınanmıştır.

Denetim sonucunda:
1. Kaynak Nutopia v60 veritabanının salt okunurluğu korunmuş, SHA-256 imzası (`e70aa44a...`) milimetrik olarak teyit edilmiştir.
2. Tüm Riverpod üretim bayraklarının (`coreNextMigrationRunnerProvider = null`, `DatabaseManager.databaseRoutingHook = null`, `coreNextSalesEngineEnabledProvider = false`) varsayılan olarak güvenle kapalı kaldığı doğrulanmıştır.
3. 9 ayrı test paketinde toplam **105 adet regresyon testi %100 PASS** ile sonuçlanmıştır. Statik kod analizinde (`flutter analyze`) 0 hata raporlanmıştır.
4. **KRİTİK MİMARİ BULGU (SAFETY GAP)**: Resolver seviyesinde hedef DB seçimi başarıyla çalışırken, `DatabaseManager.instance.getDatabase()` metodunun üretim kodunda `version: 60` şemasına, eski migrasyonlara (`_onUpgrade`) ve eski trigger'lara (`financial_transactions`) sıkı sıkıya bağlı olduğu; `databaseRoutingHook` tarafından temiz Core Next veritabanına (`version: 3`) yönlendirildiğinde legacy yükseltme adımlarını (Migration 4 -> 60) temiz şemaya uygulamaya çalışarak çöktüğü veya şemayı bozma riski taşıdığı fiilen kanıtlanmıştır.

Bu nedenle, pilot öncesi veri kaybını ve şema bozulmasını önlemek amacıyla aşama **`BLOCKED — DATABASE ROUTING OR RECOVERY SAFETY GAP`** olarak sınıflandırılmıştır.

---

## 2. BÖLÜM 1 — DEĞİŞMEZ GÜVENLİK KURALLARI VE CANLI ORTAM KORUMASI

| Kontrol Maddesi | Beklenen Güvenli Davranış | Gerçekleşen Sonuç | Durum |
| :--- | :--- | :--- | :---: |
| **Canlı SQLite ve PostgreSQL Koruması** | Canlı Nutopia DB ve Erkul PostgreSQL'e 0 bayt yazım. | Yalnızca geçici temp dizinindeki kopyalar üzerinde çalışıldı. | **PASS** |
| **Kaynak DB Hash İmzası** | `raw_nutopia_v60.db` SHA-256 değişmemeli. | Başlangıç ve bitişte `e70aa44a...` birebir aynı. | **PASS** |
| **Üretim Lisans & Tenant Verisi** | Uzak sunucu veya lisans durumu değiştirilmemeli. | Hiçbir harici HTTP/WebSocket çağrısı yapılmadı. | **PASS** |
| **Runner Varsayılanı** | `coreNextMigrationRunnerProvider` null kalmalı. | ProviderContainer varsayılanı `null`. | **PASS** |
| **Routing Hook Varsayılanı** | `DatabaseManager.databaseRoutingHook` null kalmalı. | Statik değişken varsayılanı `null`. | **PASS** |
| **Sales Engine Varsayılanı** | `coreNextSalesEngineEnabledProvider` false kalmalı. | ProviderContainer varsayılanı `false`. | **PASS** |
| **Repo Temizliği** | Git reset, revert, stash veya çalışma alanı silinmemeli. | Kullanıcı çalışma dizinindeki değişiklikler korundu. | **PASS** |

---

## 3. BÖLÜM 2 — GERÇEK VERİTABANI YÖNLENDİRMESİ VE GÜVENLİK KAPISI DENETİMİ

Gerçek çağrı zinciri izole dosya bağımlılıklarıyla 8 ayrı senaryoda test edilmiştir:

`main.dart → AppBootstrap → CoreNextBootstrapCoordinator → MigrationRunner → completion state → DatabaseRoutingResolver → DatabaseManager → dbGatewayProvider → repository providers`

### 3.1. Senaryo Matrisi ve Test Sonuçları

| No | Test Senaryosu | Beklenen Davranış | Test Kanıtı & Gözlem | Sonuç |
| :---: | :--- | :--- | :--- | :---: |
| **1** | **Runner `null`** | Migration çalışmamalı; legacy DB ve legacy repository açılmalı. | `test 2.1`: `DatabaseManager.getDatabase()` legacy yolu açtı, `SqliteCustomerRepository.findAll()` 576 aktif müşteriyi legacy DB'den getirdi. PRAGMA database_list = legacy dosya yolu. | **PASS** |
| **2** | **Routing hook `null`** | Mevcut legacy davranışı %100 korunmalı. | `test 2.2`: Hook `null` iken legacy dosya yolu seçildi, veritabanı sorunsuz açıldı. | **PASS** |
| **3** | **Hook enjekte edilmiş fakat `migrationStateCompleted = false`** | Hedef DB seçilmemeli; legacyFallback uygulanmalı. | `test 2.3`: Resolver `legacyFallback` döndü. `DatabaseManager` ve `SqliteCustomerRepository` legacy DB'de kaldı. | **PASS** |
| **4** | **Geçiş tamamlandığında hedef DB yönlendirmesi** | Hedef DB seçilmeli; legacy ve hedef şeması güvenle ayrıştırılmalı. | `test 2.4`: `resolver.resolve()` hedef yolu (`targetSelected`) başarıyla seçti. ANCAK `DatabaseManager.getDatabase()` legacy şema yükseltme mekanizması nedeniyle Core Next dosyasını açmaya çalışırken fail-closed çöktü. | **BLOCKED (SAFETY GAP)** |
| **5** | **Uygulama yeniden başlatıldığında mükerrerlik (Idempotency)** | Tamamlanmış geçiş ikinci kez veri kopyalamamalı. | `test 2.5`: Coordinator ikinci açılışta `isCompletedOnTarget == true` görerek `isSkipped: true` ve `state: completed` ile runner'ı tetiklemeden güvenle atladı. | **PASS** |
| **6** | **Bozuk veya eksik completion state** | Güvensiz hedef seçimi engellenmeli; fallback yapılmalı. | `test 2.6`: State eksik/bozukken resolver doğrudan `legacyFallback` kararı verdi. | **PASS** |
| **7** | **Yanlış Tenant ID veya mutabakat farkı** | Hedefe erişim durdurulmalı (`blockedFailClosed`). | `test 2.7`: `requestedTenantId != tenant_id` durumunda resolver `blockedFailClosed` döndü ve hedef yolu reddetti. | **PASS** |
| **8** | **Hedefte yeni satış/finans varken rollback girişimi** | Sessiz geri dönüş engellenmeli (`UnsafeRollbackException`). | `test 2.8`: Hedefe yeni satış eklendikten sonra `assertSafeRollback` çalıştırıldı; `UnsafeRollbackException` fırlatılarak yeni verilerin sessizce kaybı engellendi. | **PASS** |

### 3.2. Kritik Güvenlik Açığı İncelemesi (Safety Gap Teşhisi)

[lib/infrastructure/database/database_provider.dart:L467-L471](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L467-L471) ve [L125-L128](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L125-L128) incelendiğinde:

```dart
// DatabaseManager._initializeDatabase()
final db = await openDatabase(
  path,
  version: databaseVersion, // 60 (Legacy şema sürümü)
  onCreate: _onCreate,
  onUpgrade: _onUpgrade,   // Legacy migrasyonlar (Migration 4 -> 60)
  ...
);
...
// DatabaseManager.getDatabase()
await _verifyDatabaseSchemaInvariants(_database!); // sms_logs, print_queue, users bekler
await DatabaseTriggers.verifyAndRepairTriggers(_database!); // financial_transactions trigger bekler
await _reconcileAllCustomerBalances(_database!); // v_customer_ledger_effect view bekler
```

- **Teşhis**: `DatabaseManager`, yalnızca 60 sürüm birikmiş eski `serenut_pos.db` dosyasını yönetmek üzere tasarlanmıştır.
- **Tehlike**: `databaseRoutingHook` aktif edilip temiz Core Next veritabanı yolu (`serenut_core_v2.db`, şema sürümü 3) `DatabaseManager`'a iletildiğinde, SQLite FFI motoru `user_version` değerini 3 olarak okur. `3 < 60` olduğu için `_onUpgrade(db, 3, 60)` tetiklenir ve eski 57 adet migrasyon script'i temiz Core Next veritabanı üzerinde çalıştırılmaya kalkışılır!
- **Hata Çıktısı**: Migration 52 aşamasında `CREATE INDEX IF NOT EXISTS idx_ft_created ON financial_transactions(created_at)` çalıştırıldığında, Core Next şemasında `financial_transactions` tablosu bulunmadığından `SqliteException(1): no such table: main.financial_transactions` hatasıyla patlar.
- **Güvenlik Çıkarımı**: Bu durum pilot ortamda aktif edilirse Core Next veritabanı açılış anında kilitlenir veya otomatik recovery mekanizması dosyayı "bozuk" sanarak karantinaya alır (`core_next_app.db.corrupted_timestamp`).
- **Gereken Çözüm**: `DatabaseManager`, hook üzerinden gelen yolun bir Core Next veritabanı olduğunu algıladığında legacy `_onUpgrade`, `_verifyDatabaseSchemaInvariants` ve `DatabaseTriggers` adımlarını baypas etmeli VEYA `RepositoryProviders` seviyesinde `CoreAppDatabase` doğrudan sağlayıcıya bağlanmalıdır.

---

## 4. BÖLÜM 3 — AÇILIŞ VE UI DAYANIKLILIĞI

| Denetim Alanı | İncelenen Durum | Bulgular ve Gözlem | Durum |
| :--- | :--- | :--- | :---: |
| **İlk Açılış & Legacy Kullanım** | Normal açılışta legacy veri akışı | `SqliteCustomerRepository` üzerinden 576 aktif müşteri gecikmesiz yüklendi. | **PASS** |
| **Onay Ekranı & Erteleme** | Splash ekranı overlay diyalog ve postponed kararı | `TestAppLifecycleHarness` üzerinde `MigrationConsentDialog` çizildi; "Şimdi Değil" tıklandığında `MigrationConsentDecision.postponed` kararı Future'a iletildi ve coordinator geçişi atladı. | **PASS** |
| **Yedekleme Başarısızlığı** | Geçersiz disk sürücüsü (`Z:\...`) simülasyonu | Yedekleme başarısız olunca coordinator `failedRecoverable` durumuna geçti; motor çağrılmadı (çağrı sayısı = 0) ve legacy DB korundu. | **PASS** |
| **Geçiş Sırasında Hata & Rollback** | Motor çalışırken `SocketException` enjeksiyonu | Hata anında coordinator `failedRecoverable` durumuna geçti; `isRolledBack` korundu. | **PASS** |
| **Geçiş Sonrası Yeniden Açılış** | Başarılı göç sonrası idempotent başlangıç | `isCompletedOnTarget == true` tespit edilerek ikinci kez veri çoğaltılması engellendi. | **PASS** |
| **Eşzamanlı Geçiş Girişimi** | Paralel iki `coordinate()` çağrısı | `_isExecutionRunning` kilidi devreye girdi; 1 çağrı devam ederken diğeri `isAlreadyRunning: true` ile anında tekilleştirildi. | **PASS** |
| **Event-Loop Yielding & Profiling** | Single-threaded Dart isolate rahatlatma | 10 mikro-adım `Future.delayed(Duration.zero)` ile 0ms gecikmeyle yielded edildi; Dart main isolate kilitlenmedi (<500ms). | **PASS** |
| **Fiziksel POS Cihazı Dokunmatik Ekran** | Donanım üzerinde parmak gecikmesi ve ekran tepkisi | Fiziksel POS terminali bağlı olmadığından test ortamında doğrulanamaz. Kural gereği `NOT VERIFIED`. | **NOT VERIFIED** |

---

## 5. BÖLÜM 4 — DERİN ADLİ MUTABAKAT VE VERİ BÜTÜNLÜĞÜ

Gerçek Nutopia v60 yedek veritabanı kopyası üzerinde icra edilen tam göç mutabakatı:

- **Kaynak DB Yolu:** `backups/raw_tenants_20261016/raw_nutopia_v60.db`
- **Kaynak SHA-256:** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24`
- **Test Sonrası Kaynak SHA-256:** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` (Sıfır bayt sapma)

### 5.1. Tablo ve Bakiye Karşılaştırma Matrisi

| Varlık / Tablo | Kaynak (Nutopia v60) | Hedef (Core Next v3) | Fark / Sapma | Karar |
| :--- | :---: | :---: | :---: | :---: |
| **Toplam Ürün** | 37.682 | 37.682 | 0 | **PASS** |
| ↳ *Aktif Ürünler* | 17 | 17 | 0 | **PASS** |
| ↳ *Silinmiş / Arşiv Ürünler* | 37.665 | 37.665 | 0 | **PASS** |
| **Toplam Müşteri** | 584 | 584 | 0 | **PASS** |
| ↳ *Aktif Müşteriler (Repo Query)* | 576 | 576 | 0 | **PASS** |
| ↳ *Müşteri Bakiye Toplamı* | -134.500,68 TL | -13.450.068 kuruş | **0,00 TL (0 kuruş)** | **PASS** |
| **Satışlar (Fişler)** | 52 | 52 | 0 | **PASS** |
| **Satış Kalemleri** | 120 | 120 | 0 | **PASS** |
| ↳ *Satış Kalemleri Parasal Toplamı*| 31.307,25 TL | 3.130.725 kuruş | **0,00 TL (0 kuruş)** | **PASS** |
| **Siparişler** | 792 | 792 | 0 | **PASS** |
| **Sipariş Kalemleri** | 1.068 | 1.068 | 0 | **PASS** |
| **Müşteri Defter Kayıtları** | 1.403 (`financial_transactions`) | 1.403 (`ledger_entries`) | 0 | **PASS** |
| **Anonim Nakit Satışlar** | 21 fiş | 21 (`cash_transactions`) | 0 | **PASS** |
| ↳ *Anonim Nakit Toplamı* | 12.197,00 TL | 1.219.700 kuruş | **0,00 TL (0 kuruş)** | **PASS** |
| **Taksit Planları & Dilimleri** | 2 plan, 9 dilim | 2 plan, 9 dilim | 0 | **PASS** |
| **Yetim Kayıtlar (Orphans)** | 0 | 0 (`sale_items` / `order_items`) | 0 | **PASS** |
| **Yinelenen Kayıtlar (Duplicates)**| 0 | 0 | 0 | **PASS** |

---

## 6. BÖLÜM 5 — REGRESYON TEST MATRİSİ VE STATİK ANALİZ

### 6.1. Regresyon Test Koşum Sonuçları (9 Test Dosyası)

```bash
flutter test \
  test/core_next/stage10_12_12_anonymous_cash_sales_test.dart \
  test/core_next/stage10_12_14_isolated_bootstrap_rehearsal_test.dart \
  test/core_next/stage10_12_15_guarded_database_manager_test.dart \
  test/core_next/stage10_12_16_audit_and_benchmark_test.dart \
  test/core_next/stage10_12_17_progress_consent_test.dart \
  test/core_next/stage10_12_19_fail_closed_ui_consent_test.dart \
  test/core_next/stage10_12_20_final_isolated_rehearsal_test.dart \
  test/core_next/stage10_12_21_source_target_reconciliation_test.dart \
  test/core_next/stage10_12_23_isolated_pilot_rehearsal_test.dart
```

| Aşama / Test Dosyası | Test Sayısı | Başarılı | Başarısız | Çıkış Kodu | Durum |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Stage 10.12.12** (`anonymous_cash_sales_test.dart`) | 4 | 4 | 0 | 0 | **PASS** |
| **Stage 10.12.14** (`isolated_bootstrap_rehearsal_test.dart`) | 15 | 15 | 0 | 0 | **PASS** |
| **Stage 10.12.15** (`guarded_database_manager_test.dart`) | 8 | 8 | 0 | 0 | **PASS** |
| **Stage 10.12.16** (`audit_and_benchmark_test.dart`) | 5 | 5 | 0 | 0 | **PASS** |
| **Stage 10.12.17** (`progress_consent_test.dart`) | 13 | 13 | 0 | 0 | **PASS** |
| **Stage 10.12.19** (`fail_closed_ui_consent_test.dart`) | 15 | 15 | 0 | 0 | **PASS** |
| **Stage 10.12.20** (`final_isolated_rehearsal_test.dart`) | 17 | 17 | 0 | 0 | **PASS** |
| **Stage 10.12.21** (`source_target_reconciliation_test.dart`) | 10 | 10 | 0 | 0 | **PASS** |
| **Stage 10.12.23** (`isolated_pilot_rehearsal_test.dart`) | 18 | 18 | 0 | 0 | **PASS** |
| **GENEL TOPLAM** | **105** | **105** | **0** | **0** | **%100 PASS** |

### 6.2. Statik Kod Analizi (`flutter analyze`)

```bash
flutter analyze \
  test/core_next/stage10_12_23_isolated_pilot_rehearsal_test.dart \
  lib/infrastructure/database/database_provider.dart \
  core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart
```
- **Çıktı:** `Analyzing 3 items... No issues found! (ran in 63.5s)`
- **Çıkış Kodu:** `0 (Temiz)`

### 6.3. Git Durumu ve Repo Bütünlüğü

- `git rev-parse HEAD`: `28c158d88028f139e93f78982d4651ad424c61d2`
- `git branch --show-current`: `main`
- `git diff --check`: Exit Code 0 (Temiz)
- Çalışma ağacı korunmuş; commit, reset veya revert yapılmamıştır.

---

## 7. BÖLÜM 6 — PİLOT ÖNCESİ DÜZELTME YOL HARİTASI (REMEDIATION PATH)

Aşamanın `BLOCKED` kararı almasına neden olan veritabanı yönlendirme açığının kapatılması için pilot öncesi yapılması gereken mimari müdahale şudur:

1. **`DatabaseManager` Çift Şema Ayrımı (Dual-Schema Guard)**:
   - `DatabaseManager._initializeDatabase()` içinde `databaseRoutingHook` bir yol döndürdüğünde, bu veritabanının Core Next olup olmadığı (`PRAGMA user_version < 10` veya `table_info('ledger_entries')`) kontrol edilmelidir.
   - Core Next tespit edildiğinde `openDatabase` çağrısına `version: 60`, legacy `_onCreate` ve legacy `_onUpgrade` verilmemeli; dosya saf SQLite bağlantısı olarak açılmalıdır.
   - Açılış sonrası `_verifyDatabaseSchemaInvariants`, `DatabaseTriggers.verifyAndRepairTriggers` ve `_reconcileAllCustomerBalances` adımları yalnızca legacy veritabanları için işletilmelidir.
2. **Repository Delegasyonu**:
   - `lib/providers/repository_providers.dart` içindeki `coreNextProductRepositoryProvider` ve `coreNextCustomerRepositoryProvider` sağlayıcıları, `DatabaseRoutingResolver` hedef DB'yi seçtiğinde doğrudan `CoreAppDatabase` ile eşleştirilmeli; eski `SqliteCustomerRepository`'nin kuruş duyarlılıklı yeni şemada float sorgulaması engellenmelidir.

---

## 8. NİHAİ KARAR

```text
================================================================================
            BLOCKED — DATABASE ROUTING OR RECOVERY SAFETY GAP
================================================================================
```

### Karar Gerekçesi:
1. Kaynak veri mutabakatı (37.682 ürün, 584 müşteri, 52 satış, 792 sipariş, 1.403 defter, 21 anonim nakit) ve fail-closed güvenlik kapıları izole test ortamında **%100 kusursuz** çalışmaktadır.
2. Ancak `DatabaseManager.instance.getDatabase()` doğrudan çağrıldığında, legacy `version: 60` yükseltme döngüsü ve legacy trigger motoru temiz Core Next şemasına müdahale etmeye kalkışmaktadır.
3. Bu mimari güvenlik açığı giderilmeden ve `DatabaseManager` Core Next için çift-şema korumasına kavuşturulmadan pilot terminallerde canlı geçiş yapılması güvenli değildir.

> **ÖNEMLİ BİLGİLENDİRME:** Üretim bayrakları kesinlikle açılmamış, canlı veritabanlarına tek bir bayt dahi yazılmamış ve üretime geçiş yapılmamıştır.
