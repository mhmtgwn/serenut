# SERENUT OS — STAGE 10.12.15
## GUARDED BOOTSTRAP INTEGRATION & PRE-PRODUCTION GATE RAPORU

**Tarih:** 2026-10-16  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Git Branch:** `main`  
**Denetim Tipi:** Guarded Bootstrap Entegrasyon Hazırlığı, 3 Tekrarlı Gerçek Veri Performans Kıyaslaması ve Pre-Production Güvenlik Kapısı  
**Karar:** ⚠️ **PRE-PRODUCTION GATE READY (CANLI GEÇİŞE HAZIR DEĞİL / TÜM GÜVENLİK KORUMALARI AKTİF)**

---

### YÖNETİCİ ÖZETİ VE KAPILAR DURUM TABLOSU

| Denetim / Kapı Maddesi | Durum | Kanıt & Notlar |
| :--- | :---: | :--- |
| **1. Legacy Açılış Davranışının Korunması** | **PASS** | `DatabaseManager.databaseRoutingHook == null` varsayılanında eski `serenut_pos.db` açılır, Core Next baypas kalır. |
| **2. Varsayılan Feature Flag'lerin Kapalı Olması** | **PASS** | `coreNextSalesEngineEnabledProvider = false` ve `coreNextMigrationRunnerProvider = null` sabit tutuldu. |
| **3. `DatabaseManager` Gerçek Çağrı Zinciri** | **PASS** | `databaseRoutingHook` geriye dönük uyumlu hook mimarisi ile bağlandı. |
| **4. Migration'ın Otomatik Başlamaması** | **PASS** | Runner null olduğunda koordinatör hiçbir veri tablosuna dokunmaz, durum `notStarted` kalır. |
| **5. Rollback Korumasının Gerçek Hata Yolunda Çalışması** | **PASS** | `DatabaseRoutingResolver.assertSafeRollback()` gerçek denetleyici zincirine entegre edildi. |
| **6. Satış ve Finans Yazımlarının Rollback'i Engellemesi** | **PASS** | Sadece `sales` değil; `ledger_entries` ve `cash_transactions` yazımları da rollback'i kesin olarak bloke eder. |
| **7. Çok Kiracılı (Tenant) İzolasyonu** | **PASS** | `tenant_id` uyuşmazlığında fail-closed ile hedef DB engellenir, legacy fallback devreye girer. |
| **8. Yarım Migration / Crash Sonrası Kurtarma** | **PASS** | `migration_in_progress` durumunda kalan DB temizlenir ve yeniden denenir (`failedRecoverable`). |
| **9. Üç Tekrarlı Gerçek Veri Performansı** | **PASS** | Nutopia v60 (37.682 ürün) geçici kopyalarında 3 kez test edildi; Ortalama toplam süre: **23.00 s**. |
| **10. Veri Mutabakatı ve Bütünlük** | **PASS** | `PRAGMA integrity_check = ok`, `PRAGMA foreign_key_check = 0 ihlal`, Bakiye: `-134.500,68 TL` (0 kuruş sapma). |
| **11. 37.665 Silinmiş Ürün Analizi** | **PASS** | Yabancı anahtar (FK) bütünlüğü için taşınır; Core Next repository'lerinde `is_deleted = 0` filtresiyle gizlenir. |
| **12. 18 Saniyelik Açılış Deneyimi Mimarisi** | **PASS** | `initPreApp`'ın `runApp()` öncesi blokajı incelendi; `BrandedSplashScreen` içi ilerleme gösterge tasarımı tamamlandı. |

---

### 1. MEVCUT DURUM VE DEĞİŞMEZLİK TESPİTİ

- **Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Branch:** `main`
- **`git diff --check`:** Temiz (0 hata, çıkış kodu: 0).
- **Kaynak Veritabanı ve Dosya İmzaları (Kriptografik SHA-256):**
  - `backups/raw_tenants_20261016/raw_nutopia_v60.db`:  
    `E70AA44A43C53F47F61C7B82A0A8C290D82E9F849AEC68486782BC2917430D24` *(DEĞİŞMEDİ / %100 DOKUNULMADI)*
  - `backups/raw_tenants_20261016/raw_serenut_v44.db`:  
    `9145443F2C94A03DEA7478605DE974A1214B548523DA0406C18501918DA7D77D` *(DEĞİŞMEDİ / %100 DOKUNULMADI)*
  - `backups/raw_tenants_20261016/raw_erkul_source.json`:  
    `B4912D916818377FA3D4A2D87C9BC33AA9B5FCD69300442DD6EEA6D8FA5EE389` *(DEĞİŞMEDİ / %100 DOKUNULMADI)*

---

### 2. TEST KANITLARININ BAĞIMSIZ DOĞRULANMASI

Stage 10.12.14 ve önceki aşamalardaki sentetik test iddiaları bağımsız olarak analiz edilmiş ve sentetik sahte nesnelerle gerçek entegrasyon arasındaki ayrım netleştirilmiştir:

1. **Sentetik Birim Testi vs Gerçek Zincir:**  
   Stage 10.12.14'te `AppBootstrap.runStartupDiagnostics` çağrılmış, ancak gerçek `DatabaseManager.getDatabase()` metodunun Core Next'i dinamik olarak açıp açamayacağı test edilmemişti.
2. **Yapılan Geliştirme:**  
   `lib/infrastructure/database/database_provider.dart` içine `databaseRoutingHook` eklenerek, `DatabaseManager.getDatabase()` doğrudan test edilebilir, geriye dönük uyumlu ve varsayılan olarak **%100 KAPALI** hale getirilmiştir.
3. **Doğrulama:**  
   Mevcut üretim açılışında `databaseRoutingHook == null` olduğu için hiçbir koşulda Core Next dosyasına geçilmez; eski `serenut_pos.db` açılır.

---

### 3. GÜVENLİK SINIRLARI VE FEATURE FLAG GÜVENCESİ

- `coreNextSalesEngineEnabledProvider`: **`false`** (Değiştirilmedi).
- `coreNextMigrationRunnerProvider`: **`null`** (Otomatik migration kesinlikle tetiklenmez).
- Canlı Kullanıcı Veritabanı Yolu: `%APPDATA%\serenut_pos.db` dosyasında yazma veya migration yapılmadı.
- PostgreSQL / VPS: Canlı sunucuya veya veritabanına bağlanılmadı.
- Git Durumu: Canlıya deploy, release yayımlama, git commit veya git reset yapılmadı.

---

### 4. DATABASEMANAGER & RESOLVER ENTEGRASYON TASARIMI (8 ŞART DOĞRULAMASI)

`test/core_next/stage10_12_15_guarded_database_manager_test.dart` test dosyasında 8 kritik güvenlik şartı uçtan uca test edilmiş ve tamamı **PASS** almıştır:

1. **Şart 1 (Core Next Kapalı):** `DatabaseManager.databaseRoutingHook` null olduğunda legacy yol döner. *(PASS)*
2. **Şart 2 (Runner Yok):** `coreNextMigrationRunnerProvider` null olduğunda koordinatör göç yapmaz, hata vermeden legacyde kalır. *(PASS)*
3. **Şart 3 (İşaret Yoksa Hedef Seçilmez):** `migrationStateCompleted = false` ise resolver legacy döner. *(PASS)*
4. **Şart 4 (Bozuk Hedef DB):** Hedef dosya SQLite bütünlük testini geçemezse veya bozuksa fail-closed ile legacy seçilir. *(PASS)*
5. **Şart 5 (Kiracı Uyuşmazlığı):** DB'deki `tenant_id` ile istenen kiracı uyuşmazsa fail-closed ile erişim engellenir. *(PASS)*
6. **Şart 6 (Yarım Kalan Migration):** Migration sırasında hata olursa hedef DB durumu başarısız kalır ve asla bağlanılmaz. *(PASS)*
7. **Şart 7 (Yeni Satış / Finans Rollback Engeli):** Göç sonrası hedefte yeni satış, cari hareket veya kasa işlemi varsa rollback kesinlikle bloke edilir (`UnsafeRollbackException`). *(PASS)*
8. **Şart 8 (Eşzamanlı Açılış Kilit Koruması):** İki eşzamanlı `coordinate()` çağrısı yapıldığında `isExecutionRunning` bayrağı ikinci çağrıyı güvenle engeller (`isAlreadyRunning = true`), mükerrer göç önlenir. *(PASS)*

---

### 5. GELİŞTİRİLMİŞ ROLLBACK KORUMASI (`assertSafeRollback`) DOĞRULAMASI

Önceki aşamada yalnızca `sales` tablosuna bakan `assertSafeRollback()`, artık **tüm finansal ve operasyonel hareketleri** denetleyecek şekilde genişletilmiştir:

```dart
// core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart
1. sales WHERE created_at > ?
2. ledger_entries WHERE created_at > ?
3. cash_transactions WHERE created_at > ?
```

#### Denetlenen Senaryolar ve Sonuçlar:
- **Temiz Hedef (0 yeni hareket):** Rollback'e izin verilir. *(PASS)*
- **Yeni Satış Yazımı:** Rollback engellendi -> `UnsafeRollbackException: ... (yeni satış: 1)`. *(PASS)*
- **Yeni Cari / Defter Yazımı:** Rollback engellendi -> `UnsafeRollbackException: ... (yeni cari/defter: 1)`. *(PASS)*
- **Yeni Kasa Hareketi:** Rollback engellendi -> `UnsafeRollbackException: ... (yeni kasa: 1)`. *(PASS)*
- **Hata Anında Veri Koruma:** Rollback hatası uygulamanın çökmesine yol açmaz; veri korunur ve fail-closed kalır. *(PASS)*

---

### 6. GERÇEK VERİYLE 3 TEKRARLI PERFORMANS VE MUTABAKAT ÖLÇÜMÜ

Kaynak Nutopia v60 yedeğinin (`raw_nutopia_v60.db`) izole geçici kopyaları üzerinde 3 ardışık bağımsız göç ve adli mutabakat gerçekleştirilmiştir:

#### A) Koşu Bazında Ölçüm Tablosu

| Metrik | Koşu #1 | Koşu #2 | Koşu #3 | **3 Koşu Ortalaması** |
| :--- | :---: | :---: | :---: | :---: |
| **Toplam Süre** | 13.686 ms | 18.730 ms | 36.589 ms | **23.001 ms (23,00 s)** |
| **Yedekleme & PRAGMA Check** | 5.841 ms | 4.981 ms | 19.948 ms | **10.256 ms (10,26 s)** |
| **Toplu Veri Göçü (Batch Migration)** | 7.845 ms | 13.749 ms | 16.641 ms | **12.745 ms (12,75 s)** |
| **Adli Mutabakat & Sağlama** | 429 ms | 390 ms | 330 ms | **383 ms (0,38 s)** |

#### B) Veri Mutabakatı Doğrulaması (Tüm Koşularda Özdeş)
- **Kaynak SHA-256 (Önce):** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24`
- **Kaynak SHA-256 (Sonra):** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` *(0 bayt sapma)*
- **Toplam Ürün:** **37.682** (Aktif: 17, Silinmiş: 37.665)
- **Müşteri / Cari Sayısı:** **584**
- **Müşteri Toplam Bakiyesi:** **-134.500,68 TL** (`-13.450.068` kuruş) *(0 kuruş sapma)*
- **Satış Sayısı:** **52** (Toplam Tutar: **31.282,25 TL** / `3.128.225` kuruş)
- **Satış Kalemleri:** **120**
- **Sipariş Sayısı:** **792** (Toplam Tutar: **12.268,06 TL**)
- **Defter Hareketleri (Ledger):** **1.403**
- **Müşterisiz Nakit Satışlar:** **21** (Toplam Tutar: **12.197,00 TL** / `1.219.700` kuruş)
- **Hedef `PRAGMA integrity_check`:** `ok`
- **Hedef `PRAGMA foreign_key_check`:** `0` (Sıfır ihlal)

#### C) 37.665 Silinmiş Ürünün İncelenmesi
- **Neden Taşınıyor?** Geçmişte yapılan 52 satışın 120 satış kaleminde (`sale_items`) ve 792 sipariş kaleminde bu ürünlerin ID'leri yabancı anahtar (FK) olarak yer almaktadır. Bu ürünler aktarılmadığı takdirde SQLite `FOREIGN KEY constraint failed` hatası verir ve veri tabanı bütünlüğü bozulur.
- **Yeniden Canlandırılma (Resurrection) Riski Var mı?**  
  Hayır. Core Next tarafındaki tüm ürün sorguları ve repository implementasyonları (`core_next_product_repository.dart`, `sqlite_product_repository.dart`) `WHERE is_deleted = 0 AND is_active = 1` şartı koşar. Silinmiş ürünler kullanıcı arayüzünde, ürün listesinde veya satış ekranında ASLA görünmez.

---

### 7. 18-23 SANİYELİK AÇILIŞ DENEYİMİ VE UI MİMARİSİ

#### Mevcut Zincir Analizi:
1. `lib/main.dart` içinde `AppBootstrap.initPreApp()` çağrısı `runApp(const ProviderScope(child: MyApp()))` satırından **ÖNCE** çalışır.
2. Bu aşamada Flutter widget ağacı henüz ayağa kalkmamıştır; işletim sistemi penceresi bağlansa dahi ekranda herhangi bir Flutter `Dialog` veya `ModalBottomSheet` gösterilemez.
3. Ancak `runStartupDiagnostics` metodu, `_MyAppState` içerisindeki `_runIntegrityDiagnostics` üzerinden tetiklenir. Bu anda ekranda **`BrandedSplashScreen`** zaten render edilmektedir!

#### Önerilen İlerleme Göstergesi Tasarımı (UI Refaktörü Yapılmadan Planlandı):
- **Adım 1 (Yedekleme):** `BrandedSplashScreen` durum mesajı: *"Mevcut verileriniz güvenle yedekleniyor (%20)..."*
- **Adım 2 (Toplu Göç):** Durum mesajı: *"Core Next veri tabanına aktarılıyor (%60)..."*
- **Adım 3 (Adli Mutabakat):** Durum mesajı: *"Kuruş bazında adli mutabakat yapılıyor (%95)..."*
- **Hata Durumu:** Hata mesajı ve *"Eski sisteme dön (Güvenli Fallback)"* butonu.
- **Kapanma / Yeniden Başlama:** `isExecutionRunning` ve `prefKeyMigrationState` sayesinde uygulama aniden kapansa dahi çift işlem yapılmaz; açılışta `failedRecoverable` tespit edilip temiz yeniden başlatma sunulur.

---

### 8. ÇALIŞTIRILAN TESTLER VE HAM ÇIKTI ÖZETİ

1. **Stage 10.12.15 Guarded DatabaseManager 8-Şart Testi:**
   - Komut: `flutter test test/core_next/stage10_12_15_guarded_database_manager_test.dart`
   - Çıktı: `00:01 +8: All tests passed!` (Çıkış Kodu: 0) — **PASS**
2. **Stage 10.12.15 Triplicate Benchmark Testi (3 Tekrar):**
   - Komut: `flutter test test/core_next/stage10_12_15_triplicate_benchmark_test.dart`
   - Çıktı: `01:27 +1: All tests passed!` (Çıkış Kodu: 0) — **PASS**
3. **Stage 10.12.12 Anonim Nakit Satış & 10.9.7 Startup/Rollback Regresyon Testleri:**
   - Komut: `flutter test test/core_next/stage10_12_12_anonymous_cash_sales_test.dart test/core_next/stage10_9_7_startup_restore_rollback_test.dart`
   - Çıktı: `01:10 +9: All tests passed!` (Çıkış Kodu: 0) — **PASS**
4. **Stage 10.12.14 İzole Bootstrap Rehearsal Testi (15 Senaryo):**
   - Komut: `flutter test test/core_next/stage10_12_14_isolated_bootstrap_rehearsal_test.dart`
   - Çıktı: `00:45 +15: All tests passed!` (Çıkış Kodu: 0) — **PASS**
5. **Git Diff Bütünlük Kontrolü:**
   - Komut: `git diff --check`
   - Çıktı: Temiz (Çıkış Kodu: 0) — **PASS**
6. **Üretim Kaynak Kodları Analizi:**
   - `lib/infrastructure/database/database_provider.dart` -> 0 issues — **PASS**
   - `core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart` -> 0 issues — **PASS**
   - `lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart` -> 0 issues — **PASS**

---

### 9. KALAN ÜRETİM ENGELLERİ (PRE-PRODUCTION BLOCKERS)

Canlı veritabanına geçiş (cutover) ve Core Next motorunun production ortamında açılması öncesinde çözülmesi gereken açık engeller:

1. **Açılış Ekranı (BrandedSplashScreen) İlerleme Entegrasyonu:**  
   Ortalama 23 saniye süren göç sırasında kullanıcının uygulamanın donduğunu sanıp zorla kapatmasını (`kill process`) önlemek için `BrandedSplashScreen` içine yüzdelik / aşamalı metin akışı eklenmelidir.
2. **Kullanıcı Onayı & Pilot Seçimi Karar Kapısı:**  
   Gerçek kullanıcı veritabanının Core Next'e göç ettirilmesi için yönetici veya kullanıcıdan açık UI onayı ("Yeni Nesil Serenut Çekirdeğine Geçiş Yap") alınmalıdır.
3. **Çok Kiracılı Bulut Eşitlemesi (Sync v4) Canlı Doğrulaması:**  
   Yerel SQLite veritabanı Core Next formatına geçtikten sonra, sunucu PostgreSQL ile ilk iki yönlü senkronizasyonun (pull/push) canlı ortamda denenmesi için kontrollü bir pilot işletme oturumu açılmalıdır.

---

### SONUÇ

Stage 10.12.15 hedefleri eksiksiz tamamlanmıştır. `DatabaseManager` ve `DatabaseRoutingResolver` entegrasyonu **varsayılan olarak KAPALI, test edilebilir ve geriye dönüşü kontrollü** şekilde hazır hale getirilmiştir. Canlı veritabanına dokunulmamış, üretim ortamı legacy akışında %100 güvence altına alınmıştır.
