# CORE NEXT — STAGE 10.12.24
## ÇİFT VERİTABANI MİMARİSİ VE GÜVENLİ CORE NEXT ROUTING DÜZELTMESİ RAPORU

**Tarih:** 2026-10-18  
**Ortam:** Serenut OS Desktop (Windows 11 x64, Flutter 3.24.5 / Dart 3.5.4)  
**Denetçi / İcra Eden:** Antigravity Bağımsız Kod & Güvenlik Denetim Ajanı  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (`main`)  
**Doğrulanan Kaynak Yedeği:** `backups/raw_tenants_20261016/raw_nutopia_v60.db`  
**Kaynak SHA-256 İmzası:** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24`  
**Nihai Karar:** `DUAL DATABASE ISOLATED TESTS PASSED — PRODUCTION STILL DISABLED`

---

## 1. YÜRÜTME ÖZETİ

Stage 10.12.23 raporunda tespit edilen kritik mimari güvenlik engeli (`DatabaseManager.instance.getDatabase()` metodunun eski şema sürümü 60, legacy `_onUpgrade` ve legacy trigger onarım mekanizmalarını Core Next şema sürümü 3 olan hedef veritabanına uygulamaya kalkışması) giderilmiştir.

Bu aşamada:
1. **Çift Veritabanı Mimarisi (Dual-Database Architecture)** tesis edilmiş; Legacy SQLite (`serenut_pos.db`) ile Core Next SQLite (`serenut_core_v2.db`) arasındaki yaşam döngüsü, şema ve repository sınırları tam olarak ayrıştırılmıştır.
2. **Çift Yönlü Şema Sınırı Koruması (Mutual Schema Guard)**:
   - `DatabaseManager`, kendisine Core Next şemasına ait bir dosya verildiğinde (`user_version == 3` ve Core Next tabloları `ledger_entries`/`sync_events`), legacy migrasyon ve trigger adımlarına hiç girmeden fail-closed `IncompatibleDatabaseSchemaException` fırlatarak durur.
   - `CoreAppDatabase.open()`, kendisine legacy şemasına ait bir dosya verildiğinde (`user_version > 3` veya legacy tablolar `financial_transactions`/`sms_logs`), downgrade işlemine girmeden fail-closed `IncompatibleDatabaseSchemaException` fırlatarak durur.
3. **Güvenli Yönlendirme Koordinatörü (`DualDatabaseRoutingCoordinator`)**:
   - `DatabaseRoutingResolver` üçlü denetimi (`triple-check`) ve tenant eşleşmesi başarıyla tamamlanmadan hedef veritabanı asla açılmaz.
   - Doğrulanmış `CoreAppDatabase` örneği üzerinden Riverpod repository override'ları üretilir; `customerRepositoryProvider`, `productRepositoryProvider` ve `financialTransactionRepositoryProvider` Core Next depolarına bağlanır.
   - `coreNextSalesEngineEnabledProvider = false` varsayılanı korunmuş; satış reposu (`saleRepositoryProvider`) %100 oranında legacy `SqliteSaleRepository` üzerinde tutulmuştur.
4. **10 Test Paketinde 120 Regresyon Testi %100 PASS**:
   - Stage 10.12.12'den 10.12.24'e kadar tüm testler tek bir hata dahi olmaksızın başarıyla tamamlanmıştır.
   - `flutter analyze` 0 hata/uyarı vermiştir.
   - Kaynak veritabanı hash değeri milimetrik olarak korunmuştur.

---

## 2. BÖLÜM 1 — DEĞİŞMEZ GÜVENLİK KURALLARI VE CANLI ORTAM KORUMASI

| Kontrol Maddesi | Beklenen Güvenli Davranış | Gerçekleşen Sonuç | Durum |
| :--- | :--- | :--- | :---: |
| **Canlı SQLite ve PostgreSQL Koruması** | Canlı Nutopia DB ve Erkul PostgreSQL'e 0 bayt yazım. | Yalnızca geçici temp dizinindeki kopyalar üzerinde çalışıldı. | **PASS** |
| **Kaynak DB Hash İmzası** | `raw_nutopia_v60.db` SHA-256 değişmemeli. | Başlangıç ve bitişte `e70aa44a...` birebir aynı. | **PASS** |
| **Üretim Lisans & Tenant Verisi** | Uzak sunucu veya lisans durumu değiştirilmemeli. | Hiçbir harici HTTP/WebSocket çağrısı yapılmadı. | **PASS** |
| **Runner Varsayılanı** | `coreNextMigrationRunnerProvider` null kalmalı. | ProviderContainer varsayılanı `null`. | **PASS** |
| **Routing Hook Varsayılanı** | `DatabaseManager.databaseRoutingHook` null kalmalı. | Statik değişken varsayılanı `null`. | **PASS** |
| **Sales Engine Varsayılanı** | `coreNextSalesEngineEnabledProvider = false` korunmalı. | ProviderContainer varsayılanı `false`. | **PASS** |
| **Repo Temizliği** | Git reset, revert, stash veya kullanıcı çalışma ağacı silinmemeli. | Çalışma dizini korundu. | **PASS** |

---

## 3. BÖLÜM 2 — MİMARİ DOĞRULAMA VE ŞEMA SINIRI DÜZELTMESİ

### 3.1. Yapılan Mimari Değişiklikler

#### A) `lib/infrastructure/database/database_provider.dart`
- **Şema Koruyucu Metot (`_isCoreNextDatabase`)**:
  [lib/infrastructure/database/database_provider.dart:L305-L338](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L305-L338)
  - `path` dosyasının ilk 60 baytından `user_version` okunur.
  - Sürüm 3 ise salt-okunur bağlantıyla `sqlite_master` taranır; `ledger_entries` veya `sync_events` tablolarının varlığı doğrulanır.
- **Fail-Closed Erken Kesme (`_initializeDatabase`)**:
  [lib/infrastructure/database/database_provider.dart:L420-L428](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L420-L428)
  - `isDiskDb` dosyasında Core Next şeması algılandığında `openDatabase(..., version: 60, onUpgrade: _onUpgrade)` çağrılmadan **ÖNCE** `IncompatibleDatabaseSchemaException` fırlatılır.
  - `_onUpgrade`, `_verifyDatabaseSchemaInvariants`, `DatabaseTriggers.verifyAndRepairTriggers` ve müşteri bakiyesi uzlaştırma adımlarına **asla girilmez**.
  - `currentVersion > databaseVersion` (örn. sürüm 99) durumunda da fail-closed durdurulur.
- **Güvenli Lazy Future Temizliği (`getDatabase`)**:
  [lib/infrastructure/database/database_provider.dart:L119-L125](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L119-L125)
  - Başarısız açılış denemesinde `_databaseFuture = null` yapılarak kalıcı kilitlenme engellenmiştir.

#### B) `core_next/client_core/lib/infrastructure/database/app_database.dart`
- **Ters Şema Koruması (`CoreAppDatabase.open`)**:
  [core_next/client_core/lib/infrastructure/database/app_database.dart:L39-L51](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/app_database.dart#L39-L51)
  - Eğer `CoreAppDatabase.open` metoduna legacy veritabanı dosyası (`user_version > 3`) verilirse, SQLite otomatik downgrade çalıştırmadan önce `IncompatibleDatabaseSchemaException` fırlatılır.
  - `onOpen` hook'unda `financial_transactions` veya `sms_logs` gibi legacy tablolar bulunursa fail-closed reddedilir.

#### C) `core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart`
- **Yeni Koordinatör**:
  [core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart:L39-L90](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart#L39-L90)
  - `DatabaseRoutingResolver` çıktısı `RoutingDecision.targetSelected` olmadan `CoreAppDatabase.open()` tetiklenemez.
  - `createRepositoryOverrides`: Core Next aktif olduğunda `coreNextCustomerRepositoryProvider`, `coreNextProductRepositoryProvider` ve `coreNextFinancialTransactionRepositoryProvider`'ı `CoreAppDatabase`'e bağlar.
  - `enableSalesEngine = false` olduğundan satış reposu legacy üzerinde kalır.

---

## 4. BÖLÜM 3 — İZOLE REGRESYON TESTLERİ VE KANITLAR

Yeni test paketi: [`test/core_next/stage10_12_24_dual_database_routing_test.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_24_dual_database_routing_test.dart)

| No | Senaryo Açıklaması | Test Kodu / Kanıt | Sonuç |
| :---: | :--- | :--- | :---: |
| **1** | **Varsayılan Legacy Açılışı** | `DatabaseManager.getDatabase()` sürüm 60'ı ve legacy DB yolunu açtı; `SqliteCustomerRepository` 576 aktif müşteriyi legacy DB'den okudu. | **PASS** |
| **2** | **Core Next Hedefinin Doğru Şemadan Açılışı** | `CoreAppDatabase.open()` şema sürümü 3 olarak açıldı; `products`, `customers`, `sales`, `ledger_entries`, `sync_events` doğrulandı. | **PASS** |
| **3** | **Core Next Açılışında Legacy `_onUpgrade` Çağrılmaması** | `DatabaseManager` Core Next dosyasına yönlendirildiğinde `IncompatibleDatabaseSchemaException` fırlattı; dosyanın şema sürümü 3 olarak korundu ve `financial_transactions` tablosu yazılmadı. | **PASS** |
| **4** | **Legacy Trigger Onarımının Çalışmaması** | Core Next DB üzerinde `financial_transactions` triggerlarının (`trg_ft_insert_ledger` vb.) bulunmadığı kanıtlandı. | **PASS** |
| **5** | **Legacy Açılışında Gerekli Legacy Migration ve Kontrollerin Çalışması** | v59 şemasındaki legacy veritabanı `DatabaseManager` tarafından v60 sürümüne başarıyla yükseltildi ve invariant kontrolleri geçti. | **PASS** |
| **6** | **Yanlış Şema veya Bilinmeyen DB Kimliğinin Reddedilmesi** | Bilinmeyen şema (v99) `DatabaseManager` tarafından, legacy şema (v60) `CoreAppDatabase` tarafından fail-closed reddedildi. | **PASS** |
| **7** | **Tamamlanmamış Migration Durumunda Hedefin Seçilmemesi** | `migrationStateCompleted = false` iken coordinator `RoutingDecision.legacyFallback` döndü; hedef DB açılmadı. | **PASS** |
| **8** | **Tamamlanmış Hedefin Doğru Core Next Repository'sine Bağlanması** | `createRepositoryOverrides` ile `customerRepositoryProvider` -> `CoreNextCustomerRepository`, `productRepositoryProvider` -> `CoreNextProductRepository`, `financialTransactionRepositoryProvider` -> `CoreNextFinancialTransactionRepository` bağlandı. Kuruş duyarlıklı tutarlar (350.0 TL / 150.0 TL) doğru çözümlendi. | **PASS** |
| **9** | **Yanlış Tenant Seçiminin Engellenmesi** | İstenen tenant `other-unauthorized-tenant` iken resolver `blockedFailClosed` döndü; hedef DB açılamadı. | **PASS** |
| **10** | **Açılış veya Repository Oluşturma Hatasında Fail-Closed** | Geçersiz/bozuk dosya içeriği verildiğinde sistem `blockedFailClosed` ile durdu. | **PASS** |
| **11** | **Aynı DB Bağlantısının İki Farklı Şema Yöneticisine Verilmemesi** | `PRAGMA database_list` ile `DatabaseManager` ve `CoreAppDatabase` bağlantılarının ayrı dosyalara (`legacy_serenut_pos.db` ve `serenut_core_v2.db`) baktığı teyit edildi. | **PASS** |
| **12** | **İkinci Açılışta Migration Tekrarı veya Mükerrer Veri Oluşmaması** | Coordinator 2. açılışta `isSkipped: true` döndü; `customers` tablosundaki 584 kayıt sayısı değişmedi. | **PASS** |

---

## 5. BÖLÜM 4 — TÜM REGRESYON TESTLERİ VE STATİK KOD ANALİZİ

### 5.1. Regresyon Test Paketi Özeti (10 Test Dosyası)

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
  test/core_next/stage10_12_23_isolated_pilot_rehearsal_test.dart \
  test/core_next/stage10_12_24_dual_database_routing_test.dart
```

| Aşama / Test Dosyası | Test Sayısı | Başarılı | Başarısız | Durum |
| :--- | :---: | :---: | :---: | :---: |
| **Stage 10.12.12** (`anonymous_cash_sales_test.dart`) | 4 | 4 | 0 | **PASS** |
| **Stage 10.12.14** (`isolated_bootstrap_rehearsal_test.dart`) | 15 | 15 | 0 | **PASS** |
| **Stage 10.12.15** (`guarded_database_manager_test.dart`) | 8 | 8 | 0 | **PASS** |
| **Stage 10.12.16** (`audit_and_benchmark_test.dart`) | 5 | 5 | 0 | **PASS** |
| **Stage 10.12.17** (`progress_consent_test.dart`) | 13 | 13 | 0 | **PASS** |
| **Stage 10.12.19** (`fail_closed_ui_consent_test.dart`) | 15 | 15 | 0 | **PASS** |
| **Stage 10.12.20** (`final_isolated_rehearsal_test.dart`) | 17 | 17 | 0 | **PASS** |
| **Stage 10.12.21** (`source_target_reconciliation_test.dart`) | 10 | 10 | 0 | **PASS** |
| **Stage 10.12.23** (`isolated_pilot_rehearsal_test.dart`) | 18 | 18 | 0 | **PASS** |
| **Stage 10.12.24** (`dual_database_routing_test.dart`) | 15 | 15 | 0 | **PASS** |
| **GENEL TOPLAM** | **120** | **120** | **0** | **%100 PASS** |

- **Yürütme Süresi:** 6 dakika 44 saniye
- **Çıkış Kodu:** `0 (Tüm testler geçti)`

### 5.2. Statik Kod Analizi (`flutter analyze`)

```bash
flutter analyze \
  lib/infrastructure/database/database_provider.dart \
  core_next/client_core/lib/infrastructure/database/app_database.dart \
  core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart \
  test/core_next/stage10_12_24_dual_database_routing_test.dart
```
- **Çıktı:** `Analyzing 4 items... No issues found! (ran in 32.6s)`
- **Çıkış Kodu:** `0 (Temiz)`

### 5.3. Git Durumu ve Repo Bütünlüğü

- `git rev-parse HEAD`: `28c158d88028f139e93f78982d4651ad424c61d2`
- `git branch --show-current`: `main`
- `git diff --check`: Exit Code 0 (Temiz)
- Çalışma ağacı korunmuş; hiçbir commit, reset, revert veya stash yapılmamıştır.

---

## 6. KABUL KRİTERLERİ DEĞERLENDİRMESİ

| Kabul Kriteri | Kanıt ve Satır Referansı | Durum |
| :--- | :--- | :---: |
| **1. Legacy Açılış Davranışının Korunması** | `DatabaseManager.instance.getDatabase()` varsayılan olarak sürüm 60 `serenut_pos.db` dosyasını açar. Test 2.1: `test/core_next/stage10_12_24_dual_database_routing_test.dart:L105-L141`. | **PASS** |
| **2. Core Next DB'nin Legacy Migration Zincirine Girmemesi** | `DatabaseManager._isCoreNextDatabase` kontrolü Core Next dosyasını tespit edip `_onUpgrade` öncesinde engeller. Test 2.3: `test/core_next/stage10_12_24_dual_database_routing_test.dart:L170-L199`. | **PASS** |
| **3. Gerçek Repository'nin Doğru DB'ye Bağlanması** | `DualDatabaseRoutingCoordinator.createRepositoryOverrides` ile Core Next depoları `CoreAppDatabase`'e bağlandı. Test 2.8: `test/core_next/stage10_12_24_dual_database_routing_test.dart:L260-L364`. | **PASS** |
| **4. Şema / Tenant Uyuşmazlığında Güvenli Ret** | Bilinmeyen sürüm, bozuk dosya veya tenant uyuşmazlığında fail-closed durdurma kanıtlandı. Test 2.6, 2.9, 2.10: `test/core_next/stage10_12_24_dual_database_routing_test.dart:L237-L258, L366-L399`. | **PASS** |
| **5. Önceki Veri Mutabakat Testlerinin Geçmesi** | Stage 10.12.12 ile 10.12.23 arasındaki tüm önceki testler (105 test) tekrar çalıştırıldı ve %100 PASS aldı. | **PASS** |
| **6. Kaynak Yedek Hash'inin Değişmemesi** | `raw_nutopia_v60.db` SHA-256 imzası testler sonunda `e70aa44a...` olarak birebir doğrulandı. Test 1.1 ve Test 3.1. | **PASS** |
| **7. Üretim Bayraklarının Kapalı Kalması** | `runner = null`, `routingHook = null`, `salesEngine = false` varsayılanları korundu. Test 1.2. | **PASS** |
| **8. Fiziksel Cihaz Doğrulaması** | Fiziksel POS dokunmatik donanımı bağlı olmadığından kural gereği işaretlendi. | **NOT VERIFIED** |

---

## 7. NİHAİ KARAR

```text
================================================================================
          DUAL DATABASE ISOLATED TESTS PASSED — PRODUCTION STILL DISABLED
================================================================================
```

### Karar Gerekçesi:
1. Stage 10.12.23'te tespit edilen şema sürüm çakışması (`_onUpgrade`'in Core Next şemasına müdahalesi) çift veritabanı sınır korumasıyla tamamen ve kesin olarak çözülmüştür.
2. `DatabaseManager` ve `CoreAppDatabase` birbirlerinin dosyalarını açmaya kalkışmayacak şekilde karşılıklı şema koruyucuları (`_isCoreNextDatabase` ve `_readUserVersion`) ile yalıtılmıştır.
3. `DualDatabaseRoutingCoordinator` aracılığıyla Riverpod repository yönlendirmesi başarıyla test edilmiş; ürün, müşteri ve finans depoları Core Next şemasına bağlanırken satış motoru güvenle legacy'de tutulmuştur.
4. Toplam **120 adet regresyon testi %100 başarıyla geçmiş**, statik analiz 0 hata vermiş ve kaynak veritabanı bütünlüğü korunmuştur.

> **ÖNEMLİ BİLGİLENDİRME:** Üretim bayrakları kesinlikle açılmamış, canlı veritabanlarına tek bir bayt dahi yazılmamış ve üretime geçiş yapılmamıştır.
