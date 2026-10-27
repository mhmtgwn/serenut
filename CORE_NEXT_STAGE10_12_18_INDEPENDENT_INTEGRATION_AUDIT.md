# SERENUT OS — STAGE 10.12.18
# BAĞIMSIZ ENTEGRASYON DENETİMİ VE ÜRETİM ÖNCESİ GÜVENLİK KAPISI RAPORU

**Tarih:** 2026-10-17  
**Denetçi:** DeepMind Antigravity Bağımsız Kod Denetim Ajanı  
**Aşama:** Stage 10.12.18  
**Durum:** DENETİM TAMAMLANDI  
**Nihai Karar:** `BLOCKED — INTEGRATION GAP`

---

## 1. Başlangıç Durumu ve Git Doğrulaması

Denetim başlamadan önce çalışma kopyasının durumu sorgulanmış ve mevcut kullanıcı değişiklikleri eksiksiz korunmuştur. Herhangi bir `git commit`, `reset`, `revert` veya `checkout` çalıştırılmamıştır.

### 1.1. Gerçek Komut Çıktıları

```bash
$ git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

$ git branch --show-current
main

$ git status --short
 M lib/infrastructure/bootstrap/app_bootstrap.dart
 M lib/infrastructure/database/database_provider.dart
 M lib/infrastructure/sync_v4/sync_v4_service.dart
 M lib/infrastructure/sync_v4/sync_v4_service_materializer.dart
 M lib/main.dart
 M lib/presentation/controllers/about_controller.dart
 M lib/presentation/controllers/sales_controller.dart
 M lib/presentation/pages/settings/about_page.dart
 M lib/presentation/widgets/branded_splash_screen.dart
 M lib/providers/repository_providers.dart
 M lib/providers/sync_provider.dart
 M server/src/modules/admin/admin.controller.ts
 M server/src/modules/release/release.controller.ts
 M server/src/modules/sync_v4/sync-v4.materializer.ts
 M server/src/modules/sync_v4/sync-v4.routes.ts
 M server/src/modules/update/update.controller.ts
 M server/src/scripts/publish-release.ts
 M server/src/test/run_all_ac_tests.ts
 M server/src/test/sync_v4_domain_materialization.test.ts
?? lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart
?? lib/presentation/widgets/migration_consent_dialog.dart
?? test/core_next/
(Kullanıcıya ait raporlar ve testler korunmuştur)

$ git diff --check
warning: in the working copy of 'lib/infrastructure/bootstrap/app_bootstrap.dart', LF will be replaced by CRLF the next time Git touches it
(Biçimlendirme veya boşluk hatası yok - 0 hata)
```

---

## 2. Onay Diyaloğunun Gerçek Açılış Zincirine Bağlılığı

**Denetim Başlığı Sonucu:** `FAIL — INTEGRATION GAP`

Aşağıdaki dosyalar satır satır incelenerek çağrı zinciri haritalanmıştır:
- `lib/main.dart`
- `lib/infrastructure/bootstrap/app_bootstrap.dart`
- `lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart`
- `lib/presentation/widgets/migration_consent_dialog.dart`
- `lib/presentation/widgets/branded_splash_screen.dart`

### 2.1. 8 Denetim Sorusunun Gerçek Kod İncelemesi

| # | Denetim Sorusu | Gerçek Kod Yanıtı & Kanıt | Durum |
|---|----------------|---------------------------|-------|
| **1** | Uygulama ilk açıldığında `MigrationConsentDialog` gerçekten gösteriliyor mu? Hangi koşulda? | **HAYIR, HİÇBİR KOŞULDA GÖSTERİLMİYOR.**<br>• `lib/main.dart:44` -> `AppBootstrap.initPreApp()`<br>• `lib/main.dart:176` -> `AppBootstrap.runStartupDiagnostics(ref)`<br>• `app_bootstrap.dart:322` satırında `ref.read(coreNextMigrationRunnerProvider) != null` kontrolü yapılır; ancak `core_next_bootstrap_coordinator.dart:861` satırında runner varsayılan olarak `null`'dur. Bu nedenle koordinasyon bloğuna girilmez.<br>• Ayrıca `coreNextConsentRequesterProvider` da `null`'dur (`core_next_bootstrap_coordinator.dart:870`). `lib/main.dart` içinde bu provider'ı `showMigrationConsentDialog`'a bağlayan **hiçbir UI provider tanımı veya override yoktur**. | `FAIL` |
| **2** | Diyalog gösterilmiyorsa bunun bilinçli bir güvenlik kararı mı, yoksa henüz bağlanmamış bir widget mı olduğu açık mı? | **HER İKİSİNİN BİRLEŞİMİ (ENTEGRASYON AÇIĞI):**<br>1. Bilinçli güvenlik boyutu: İstemcinin varsayılan olarak legacy SQLite mimarisinde kalması ve fail-closed durması bilinçlidir.<br>2. Entegrasyon açığı boyutu: `lib/presentation/widgets/migration_consent_dialog.dart` widget'ı yazılmış ve izole testte test edilmiştir; ancak `lib/main.dart` ve `app_bootstrap.dart` açılış zincirine `BuildContext` veya `rootNavigatorKey` üzerinden bir diyalog tetikleyicisi bağlanmamıştır. Kod tabanında `showMigrationConsentDialog` yalnızca kendi dosyasında ve test dosyasında geçmektedir. | `FAIL` |
| **3** | `Şimdi Değil` seçildiğinde migration runner, yedekleme, kilit oluşturma veya hedef veritabanına yönlendirme tetikleniyor mu? | **KESİNLİKLE TETİKLENMEZ (GÜVENLİ).**<br>• `core_next_bootstrap_coordinator.dart:373-384` satırlarında:<br>`if (effectiveConsentRequester != null) {`<br>`  final decision = await effectiveConsentRequester();`<br>`  if (decision != MigrationConsentDecision.approved) { return BootstrapCoordinatorResult(isSuccess: true, state: CoreNextMigrationState.notStarted, isSkipped: true); }`<br>`}`<br>Onay verilmediğinde kaynak kontrolü, yedekleme (satır 415), yazma kilidi (`DatabaseManager.isWriteLocked = true`, satır 424) ve runner (satır 528) çalıştırılmadan fonksiyondan çıkılır. | `PASS` |
| **4** | `Geçişi Onayla` yalnızca açık kullanıcı etkileşimiyle mi çalışıyor? | **EVET (GÜVENLİ).**<br>• `lib/presentation/widgets/migration_consent_dialog.dart:19`: `barrierDismissible: false`.<br>• `lib/presentation/widgets/migration_consent_dialog.dart:315-327`: Yalnızca `FilledButton.icon` tıklandığında `Navigator.of(context).pop(MigrationConsentDecision.approved)` döndürülür. Kapatma/arka plan fallback'i `MigrationConsentDecision.postponed` değerine zorlanır (satır 27). | `PASS` |
| **5** | `coreNextConsentRequesterProvider == null` iken davranış tam olarak ne? | **KRİTİK GÜVENLİK RİSKİ (FAIL-OPEN GAP):**<br>• `core_next_bootstrap_coordinator.dart:373` satırında:<br>`if (effectiveConsentRequester != null)` kontrolü vardır.<br>Eğer `coreNextConsentRequesterProvider` `null` bırakılır ve birisi yalnızca `coreNextMigrationRunnerProvider`'ı aktif ederse, **kullanıcıya hiçbir şey sormadan doğrudan migration başlatılır**! Onay kapısının "Requester yoksa dur" (fail-closed) olması gerekirken, "Requester yoksa devam et" (fail-open) şeklinde çalıştığı tespit edilmiştir. | `FAIL` |
| **6** | Onay verilmesi tek başına migration başlatabiliyor mu? Yedek doğrulaması, tenant doğrulaması ve güvenlik kapıları ayrıca zorunlu mu? | **TEK BAŞINA YETERLİ DEĞİLDİR; GÜVENLİK KAPILARI ZORUNLUDUR (GÜVENLİ).**<br>• Satır 387-413: Kaynak SQLite PRAGMA bütünlük kontrolü geçmek zorundadır.<br>• Satır 415-494: WAL checkpoint ve VACUUM INTO / disk kopyası sonrası yedeğin `openDatabase(readOnly: true)` ile açılıp `PRAGMA integrity_check` testini 'ok' ile tamamlaması zorunludur.<br>• Satır 580-716: Kuruş hassasiyetinde stok, bakiye ve ciro mutabakatı zorunludur.<br>• Satır 720-733: Hedef veritabanı PRAGMA integrity ve FK kontrolleri zorunludur. | `PASS` |
| **7** | Uygulama yeniden başlatıldığında önceki onay yanlışlıkla yeni migration için kalıcı izin sayılıyor mu? | **HAYIR (GÜVENLİ).**<br>Onay kalıcı depolamaya (`SharedPreferences` veya veritabanı) kaydedilmez. Yalnızca o anki `coordinate()` çalışma ömründe bellektedir. Uygulama kapandığında sıfırlanır. | `PASS` |
| **8** | Gerçek `AppBootstrap` çağrı zinciri ile testlerde kullanılan çağrı zinciri aynı mı? | **HAYIR, AYNI DEĞİLDİR.**<br>• Canlı kod: `main.dart` -> `AppBootstrap.runStartupDiagnostics(ref)` çağırır. Burada tüm Core Next provider'ları `null`'dur; coordinator hiç çalıştırılmaz.<br>• Testler: `stage10_12_17_progress_consent_test.dart` doğrudan izole `ProviderContainer(overrides: [...])` veya yapay `CoreNextBootstrapCoordinator` örnekleriyle sentetik mock nesneleri çalıştırır. Canlı widget ağacı ve `main.dart` döngüsü test kapsamında değildir. | `FAIL` |

---

## 3. İlerleme Göstergesinin Gerçek Olaylara Bağlılığı

**Denetim Başlığı Sonucu:** `NOT VERIFIED` (UI Yanıt Verebilirliği) / `PARTIALLY VERIFIED` (İlerleme Olayları)

### 3.1. Aşama ve Yüzde Doğrulaması

1. **Aşama Eşleşmesi:**
   - Aşama 1: `sourceVerifying` (%20) -> Kaynak `PRAGMA integrity_check` öncesinde tetiklenir (`core_next_bootstrap_coordinator.dart:387`).
   - Aşama 2: `backupPreparing` (%35) -> WAL checkpoint ve yedek kopyalama öncesinde tetiklenir (`core_next_bootstrap_coordinator.dart:416`).
   - Aşama 3: `dataMigrating` (%50) -> Hedef veritabanına veri aktarımı başlangıcında tetiklenir (`core_next_bootstrap_coordinator.dart:520`).
     - Alt Aşama: Ürün kataloğu aktarımında her 1.000 üründe bir `0.40 + (pCount / products.length) * 0.25` formülüyle dinamik yüzde yayımlanır (`migration_bridge_engine.dart:496`).
   - Aşama 4: `reconciliation` (%85) -> Kuruş stok ve bakiye mutabakatı öncesinde tetiklenir (`core_next_bootstrap_coordinator.dart:581`).
   - Aşama 5: `integrityChecking` (%95) -> Hedef SQLite PRAGMA ve FK kontrolü öncesinde tetiklenir (`core_next_bootstrap_coordinator.dart:719`).
   - Aşama 6: `completed` (%100) -> Tamamlanma durumunda tetiklenir (`core_next_bootstrap_coordinator.dart:739`).

2. **Sabit Yüzde Riski:**
   - Coordinator ana aşamalarının yüzdeleri (%20, %35, %50, %85, %95, %100) SABİT (hardcoded) değerlerdir.
   - Yalnızca `products` tablosu aktarılırken dinamik yüzde hesaplanmaktadır. Kategori, müşteri, defter, satış, sipariş ve kasa aktarımları sırasında hiçbir ara yüzde üretilmemektedir.

3. **Hata ve Sıfırlama Davranışı:**
   - Hata durumunda `effectiveProgress?.call` ile `stage: MigrationStage.failed, progress: 0.0` yayımlanır ve `main.dart:343` hata kartını gösterir.
   - Uygulama yeniden başlatıldığında Riverpod StateProvider `null` olarak başlar.

4. **Event Loop & UI Yanıt Verebilirliği (Critical Assessment):**
   - `migration_bridge_engine.dart:494` ve `503` satırlarında `await Future<void>.delayed(Duration.zero)` kullanılmıştır.
   - **Teknik Değerlendirme:** `delayed(Duration.zero)`, Dart event loop'undaki microtask'ların çalışmasına izin verse de, SQLite FFI sorguları ve disk yazmaları (`batch.commit()`) ana isolate üzerinde senkron çalışır. İşlem arka plan isolate'ine (`Isolate.spawn` veya `compute`) taşınmamıştır. 37.682 ürünün 1.000'lik batch commit süreleri boyunca Flutter UI thread'inde frame düşmesi (jank) oluşması kaçınılmazdır.
   - Otomatik test ortamında gerçek frame hızı ve dokunmatik yanıt süresi ölçülemediği için prompt kuralı gereğince UI yanıt verebilirliği **`NOT VERIFIED`** olarak işaretlenmiştir.

5. **İlerleme Callback Hata Koruması Eksikliği:**
   - `effectiveProgress?.call(...)` çağrıları `core_next_bootstrap_coordinator.dart` içinde bir `try-catch` bloğuna alınmamıştır. Eğer ilerleme dinleyicisi veya Riverpod notifier herhangi bir hata fırlatırsa, bu hata yakalanmayarak migration sürecini durdurmakta ve durumu `failedRecoverable` yapmaktadır.

---

## 4. 37.682 Ürünlü İzole Veri Performans Ölçümü (3 Tekrar)

**Ölçüm Metodu:**  
Canlı dosyalara dokunulmadan, `backups/raw_tenants_20261016/raw_nutopia_v60.db` (SHA-256: `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24`) dosyasından sistem geçici dizinine 3 adet bağımsız kopya oluşturulmuş ve `test/core_next/stage10_12_16_audit_and_benchmark_test.dart` ortamında 8 aşamalı kronometre ile ölçülmüştür.

### 4.1. Üç Koşu Performans Tablosu

| Aşama / Metrik | Koşu #1 | Koşu #2 | Koşu #3 | Ortalama |
|---|---|---|---|---|
| **1. Kaynak Bütünlük Kontrolü** | 614 ms | 610 ms | 564 ms | 596 ms |
| **2. WAL & Doğrulanmış Yedek** | 1.002 ms | 868 ms | 592 ms | 821 ms |
| **3. Hedef Şema Hazırlığı** | 46 ms | 25 ms | 192 ms | 88 ms |
| **4. Ürün Aktarımı (37.682 adet)** | 4.288 ms | 4.018 ms | 3.975 ms | 4.094 ms |
| **5. Müşteri & Finans Aktarımı** | 1.319 ms | 1.236 ms | 1.223 ms | 1.259 ms |
| **6. Satış & Sipariş Aktarımı** | 990 ms | 928 ms | 917 ms | 945 ms |
| **7. Son Adli Mutabakat** | 237 ms | 232 ms | 230 ms | 233 ms |
| **TOPLAM İŞLEM SÜRESİ** | **8.499 ms** | **7.919 ms** | **7.695 ms** | **8.038 ms (~8.04 s)** |
| **En Uzun Tek Aşaması** | Ürünler (4.288 ms) | Ürünler (4.018 ms) | Ürünler (3.975 ms) | Ürünler (4.094 ms) |
| **1.000'lik Batch Başına Ortalama Süre** | ~113 ms | ~106 ms | ~105 ms | ~108 ms |
| **Kaynak Veri SHA-256 Değişmezliği** | %100 KORUNDU | %100 KORUNDU | %100 KORUNDU | %100 KORUNDU |

### 4.2. Adli Veri Doğrulaması (Her 3 Koşuda Birebir Eşit)
- Toplam Ürün: **37.682** (Aktif: 17, Silinmiş: 37.665) -> 0 sapma
- Toplam Müşteri: **584** | Toplam Bakiye: **-134.500,68 TL** (-13.450.068 kuruş) -> 0 sapma
- Toplam Satış: **52** | Toplam Ciro: **31.282,25 TL** (3.128.225 kuruş) -> 0 sapma
- Toplam Sipariş: **792** | Toplam Tutar: **12.268,06 TL** (1.226.806 kuruş) -> 0 sapma
- Müşterisiz Nakit Kasa Satışları: **21** | Toplam Tutar: **12.197,00 TL** (1.219.700 kuruş) -> 0 sapma
- Yabancı Anahtar (FK) İhlalleri: **0**
- PRAGMA Integrity Check: **ok**

---

## 5. Veri Güvenliği ve Rollback Denetimi

**Denetim Başlığı Sonucu:** `PASS`

`MigrationBridgeEngine`, `DatabaseRoutingResolver`, `DatabaseManager` ve `CoreNextBootstrapCoordinator` kod yolları birlikte incelenmiştir:

1. **Migration başarısız olduğunda hedef veritabanı seçilmiyor:**  
   `core_next_bootstrap_coordinator.dart:560-578` ve `database_routing_resolver.dart`: Kalıcı durum `failedRecoverable` kalır; resolver yalnızca `migrationStateCompleted == true` olduğunda hedefi seçer (`PASS`).
2. **Tamamlanma işareti yazılamazsa hedef veritabanına geçilmiyor:**  
   `core_next_bootstrap_coordinator.dart:736`: `app_settings` tablosuna `legacy_migration_completed = true` yazılamazsa veya commit başarısız olursa exception fırlatılır ve yönlendirme hook'u tetiklenmez (`PASS`).
3. **Yedek doğrulanamazsa migration başlamıyor:**  
   `core_next_bootstrap_coordinator.dart:483-492`: Alınan yedek `openDatabase(readOnly: true)` ile açılıp `PRAGMA integrity_check` 'ok' vermezse `BackupVerificationException` fırlatılır; migration çalıştırılmaz (`PASS`).
4. **Kaynak veritabanı bozuksa fail-closed davranışı uygulanıyor:**  
   `core_next_bootstrap_coordinator.dart:397-413`: Kaynak SQLite bütünlük testini geçemezse durum `failedBlocked` yapılır, operatör müdahalesi gerekene kadar sistem durdurulur (`PASS`).
5. **Hedefte yeni satış, defter veya kasa hareketi varsa güvensiz rollback engelleniyor:**  
   `core_next_bootstrap_coordinator.dart:808-831`: `assertSafeRollback` metodu `sales`, `ledger_entries` ve `cash_transactions` tablolarında `cutoffTime` sonrası kayıtları sayar. Yeni kayıt tespit edilirse `UnsafeRollbackException` fırlatarak geri dönüşü kilitler (`PASS`).
6. **Rollback güvenlik kontrolünün hatası güvenli biçimde ele alınıyor:**  
   `core_next_bootstrap_coordinator.dart:844-856`: Rollback kontrolü hata verirse sistem fail-closed davranarak durumu `failedBlocked` yapar (`PASS`).
7. **Eşzamanlı iki başlangıç aynı migration'ı kontrolsüz biçimde çalıştırmıyor:**  
   `core_next_bootstrap_coordinator.dart:321-329`: `_isExecutionRunning` statik kilit bayrağı ile ikinci çağrı `ConcurrencyLockException` ile anında engellenir (`PASS`).
8. **Hedef veritabanının tenant kimliği beklenen tenant ile eşleşiyor:**  
   `test/core_next/stage10_12_14_isolated_bootstrap_rehearsal_test.dart` ve routing resolver: Kiracı kimliği uyuşmazlığında resolver erişimi engeller (`PASS`).
9. **Karasal SQLite ile Bulut PostgreSQL Karışmama Güvencesi:**  
   `raw_nutopia_v60.db` ve `raw_serenut_v44.db` verileri yalnızca yerel SQLite tablolarında işlenmiştir; `raw_erkul` cloud PostgreSQL veritabanına hiçbir ağ bağlantısı açılmamış ve tek bir bayt yazılmamıştır (`PASS`).

---

## 6. Testlerin Bağımsız Doğrulanması

Aşağıdaki 5 kritik test paketi ayrı ayrı çalıştırılmış ve gerçek terminal çıktıları kaydedilmiştir:

| Test Dosyası | Test Sayısı | Çıkış Kodu | Sonuç | Kullanılan Test Altyapısı |
|---|---|---|---|---|
| `test/core_next/stage10_12_12_anonymous_cash_sales_test.dart` | 4 test | `0` | **PASS** | İzole SQLite kopya + 21 nakit kasa satışı adli doğrulaması |
| `test/core_next/stage10_12_14_isolated_bootstrap_rehearsal_test.dart` | 15 test | `0` | **PASS** | 10 izole açılış senaryosu, rollback, multi-tenant ve 37.682 ürünlük rehearsal |
| `test/core_next/stage10_12_15_guarded_database_manager_test.dart` | 8 test | `0` | **PASS** | DatabaseManager, routing hook ve 8 koşullu fail-closed kapısı |
| `test/core_next/stage10_12_16_audit_and_benchmark_test.dart` | 5 test | `0` | **PASS** | 3 tekrarlı 37.682 ürün performansı, stok/finans mutabakatı, 8-durum rollback |
| `test/core_next/stage10_12_17_progress_consent_test.dart` | 13 test | `0` | **PASS** | 11 UX/Onay senaryosu, MigrationConsentDialog widget testi, BrandedSplashScreen overlay testi |

### 6.1. Statik Analiz ve Kod Biçimlendirme Kontrolü
```bash
$ flutter analyze lib/main.dart lib/infrastructure/bootstrap/app_bootstrap.dart lib/presentation/widgets/branded_splash_screen.dart lib/presentation/widgets/migration_consent_dialog.dart lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart
Analyzing 5 items...
No issues found! (ran in 12.0s)

$ git diff --check
(0 hata, format temiz)
```

> **Önemli Test Kapsamı Uyarısı:** Testlerin %100 geçmesi, onay diyaloğunun canlı uygulamaya bağlandığı anlamına gelmez. Testlerde `coreNextConsentRequesterProvider` yapay olarak mock'lanarak diyaloğun döndüreceği değerler test edilmiştir. Canlı `lib/main.dart` açılışında bu requester henüz bağlanmamıştır.

---

## 7. Üretim Sınırları ve Güvenlik Durumu

Bu denetim boyunca aşağıdaki kurallara 0 tolerans ile uyulduğu doğrulanmıştır:

- `coreNextSalesEngineEnabledProvider = false` (KORUNDU)
- `coreNextMigrationRunnerProvider = null` (KORUNDU)
- `databaseRoutingHook = null` (KORUNDU)
- `coreNextConsentRequesterProvider = null` (KORUNDU)
- Canlı Nutopia/Serenut SQLite veya Erkul PostgreSQL veritabanlarına hiçbir yazma yapılmamıştır.
- Canlı pilot açılışı veya cutover yapılmamıştır.

---

## 8. Üretime Geçiş İçin Kalan Engeller (Entegrasyon Boşlukları)

Aşağıdaki açık mimari eksiklikler giderilmeden canlı pilot veya migration açılamaz:

1. **Onay İsteyici UI Bağlantısı Eksik (Critical Integration Gap):**  
   `MigrationConsentDialog` widget'ı yazılmıştır ancak `lib/main.dart` veya `app_bootstrap.dart` içinde `coreNextConsentRequesterProvider`'a bağlanmamıştır. Canlıda açıldığında kullanıcıya diyalog gösterilebilecek bir köprü yoktur.
2. **Fail-Open Onay Mantığı Düzeltilmeli (Safety Risk):**  
   `core_next_bootstrap_coordinator.dart:373` satırındaki `if (effectiveConsentRequester != null)` kontrolü, requester atanmadığında onayı atlayarak doğrudan göç başlatmaktadır. Güvenlik standardı gereği, migration runner aktifse ancak consent requester `null` ise sistem durmalı (`fail-closed`), onaysız göç yapmamalıdır.
3. **Progress Callback Hata Koruması:**  
   Coordinator içindeki `effectiveProgress?.call(...)` çağrıları `try-catch` korumasına alınmalıdır; aksi takdirde UI tarafındaki bir hata tüm veri transferini iptal edebilmektedir.
4. **Isolate Tabanlı Veri Transferi İhtiyacı:**  
   37.682 ürün aktarılırken `batch.commit()` işlemlerinin ana UI thread'ini dondurmaması (jank oluşturmaması) için aktarım motorunun arka plan `Isolate` üzerinde çalışması gerekmektedir.

---

## 9. Nihai Karar

```
================================================================================
                                NİHAİ KARAR:
                         BLOCKED — INTEGRATION GAP
================================================================================
```

### Karar Gerekçesi:
1. Stage 10.12.17'de tasarlanan `MigrationConsentDialog` ve onay mekanizması, mock/sentetik test ortamında başarılı olmasına rağmen **gerçek uygulama açılış zincirine (`lib/main.dart`) bağlanmamıştır**.
2. `coreNextConsentRequesterProvider` varsayılan olarak `null`'dur ve `main.dart` içinde bu sağlayıcıyı ekrana bağlayan hiçbir provider override veya kod satırı bulunmamaktadır.
3. Coordinator mantığında onay sağlayıcısı atanmadığında fail-closed durmak yerine onay adımını atlayıp göçe devam etme riski (`if (effectiveConsentRequester != null)`) bulunmaktadır.
4. Senkron SQLite commit işlemlerinin ana thread'de çalışması nedeniyle UI yanıt verebilirliği kesin olarak doğrulanamamıştır (`NOT VERIFIED`).
5. Bu entegrasyon açıkları kapatılmadan ve açık onay diyaloğu gerçek Flutter widget ağacında açılış anında doğrulanmadan canlı üretime veya pilot aşamasına geçiş **GÜVENLİK GEREĞİ BLOKE EDİLMİŞTİR**.
