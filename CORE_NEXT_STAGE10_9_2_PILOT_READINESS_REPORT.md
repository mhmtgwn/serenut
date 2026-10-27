# SERENUT OS — STAGE 10.9.2: STARTUP SAFETY, STAGING SYNC, OPERATIONAL ROLLBACK & PILOT READINESS REPORT

**Tarih:** 2026-10-16  
**Aşama:** Stage 10.9.2 — Startup Safety + Staging Sync + Operational Rollback + Pilot Readiness  
**Önceki Aşama:** Stage 10.9.1 — Deployment Status Audit (Karar: `READY_FOR_FURTHER_TESTING`)  
**Nihai Karar:** `READY_FOR_FURTHER_TESTING`

---

## 1. Başlangıç ve Bitiş Git Durumu

### 1.1 Başlangıç Durumu
- **Branch:** `main`
- **Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Son 5 Commit:**
  - `28c158d8` fix(test): align splash screen error title expectation and bump version to 1.3.143+298
  - `8c6d7682` feat(observability): mask internal errors from users, route fatal events to sentry/telemetry with correlation reference, and bump to v1.3.143+297
  - `206557f3` fix(db): drop immutability triggers before migrations and bump version to 1.3.143+296
  - `fa704af1` chore(release): bump version to 1.3.143+295 for production deployment
  - `567680fa` fix(server): resolve TS18048 undefined activation check in billing bank-transfer routes

### 1.2 Bitiş Durumu
- **Branch:** `main`
- **Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Commit yapılmadı, çalışma ağacı korundu)
- **`git diff --check`:** Temiz (0 sözdizimi/boşluk hatası)
- **Güvenlik Kuralları:**
  - Canlı production VPS ve PostgreSQL veritabanına bağlanılmadı / veri değiştirilmedi.
  - Feature flag (`coreNextSalesEngineEnabledProvider`) `false` olarak korundu.
  - Yıkıcı migration veya izinsiz veri silme komutu çalıştırılmadı.

---

## 2. Değiştirilen Dosyalar ve Değişiklik Gerekçeleri

| Dosya | Değişiklik Türü | Gerekçe |
|---|---|---|
| `lib/infrastructure/bootstrap/app_bootstrap.dart` | Değiştirildi | Açılış adımlarına (`runStartupDiagnostics`) katı zaman aşımı (bounded timeouts: DB bütünlüğü 10s, crash kurtarma 4s, SMS kuyruk süpürme 3s, donanım/remote config 3s, depo ön ısıtma 3s) eklendi. Ana isolate kilitlenmelerini önleyen izolasyon ve `ProviderContainer`/`WidgetRef` esnekliği sağlandı. |
| `test/core_next/stage10_9_7_startup_restore_rollback_test.dart` | Düzeltildi | Sözdizimi eksiği (kapanış parantezi) ve `DatabaseManager` içe aktarım eksiği giderildi; test süiti çalışır duruma getirildi. |
| `test/core_next/stage10_9_2_startup_safety_test.dart` | Yeni Dosya | Açılış güvenliği, kilitlenme dayanıklılığı, zaman aşımı koruması ve fail-closed davranışını doğrulayan 5 adet yeni birim testi eklendi. |
| `lib/presentation/controllers/sales_controller.dart` | Korundu | Çalışma ağacındaki mevcut Core Next satış controller adaptör değişiklikleri korundu. |
| `lib/providers/repository_providers.dart` | Korundu | Core Next ve Legacy repository sağlayıcı köprüleri korundu. |
| `lib/providers/sync_provider.dart` | Korundu | Outbox ve sync adapter sağlayıcıları korundu. |
| `server/src/modules/sync_v4/sync-v4.routes.ts` | Korundu | Sync v4 endpoint rotaları korundu. |
| `server/src/modules/sync_v4/sync-v4.materializer.ts` | Korundu | Sync v4 PostgreSQL materializer korundu. |

---

## 3. Görev A — Startup Safety Bulguları ve Testleri

### 3.1 İncelenen Bağımlılık Zinciri
Açılış anında `AppBootstrap.runStartupDiagnostics` şu sıralı adımları yürütür:
1. **Adım 1: Bütünlük Denetimi (IntegrityCheckService):** SQLite dosya sağlığı ve PRAGMA denetimi.
2. **Adım 2: Çökme Kurtarma (CrashRecoveryManager):** Önceki oturum çökmesi veya yarım kalan transaction tespiti.
3. **Adım 3: SMS Takılı İş Temizliği (SmsLogRepository.resetStuckJobs):** Gönderim sırasında kilitlenmiş SMS loglarının serbest bırakılması.
4. **Adım 4: Donanım ve Remote Config Kontrolleri:** Yazıcı/cihaz listeleme ve uzaktan yapılandırma.
5. **Adım 5: Depo Ön Isıtma (Settings, Products, Customers):** Sık erişilen modellerin belleğe alınması.
6. **Adım 6: Core Next Koordinasyonu (CoreNextBootstrapCoordinator):** Runner enjekte edilmişse yedekleme, migration ve mutabakat.

### 3.2 Tespit Edilen Riskler ve Alınan Önlemler
1. **Splash Ekranında Sonsuz Bekleme Riski:** İkincil işlerin (SMS log süpürme veya uzak config sorgusu) SQLite kilitleri veya ağ gecikmeleri nedeniyle UI splash ekranını sonsuza kadar bloke etme riski giderildi. Her adıma `timeout` sınırları konuldu.
2. **Hata İzolasyonu:** SMS temizliği veya depo ön ısıtma aşamasında bir hata meydana geldiğinde (`try-catch` blokları içinde) bu durum hata loguna yazılır ancak uygulamanın açılışını engellemez.
3. **Fail-Closed Bütünlük Koruması:** Adım 1'deki veritabanı bütünlük kontrolü (`integrityReport.isDatabaseHealthy == false`) asla sessizce geçiştirilmez. Kritik bozulma durumunda kullanıcıya hata kodu (`ERR-XXXXXX`) üretilerek açılış güvenli şekilde durdurulur (`failedBlocked: true`).
4. **Bloke Durum Koruması:** Eğer sistem daha önceki aşamada `failedBlocked` olarak işaretlenmişse, `CoreNextBootstrapCoordinator` doğrudan atlanır; böylece hasarlı veritabanı üzerinde işlem yapılması engellenir.

### 3.3 Startup Safety Test Sonuçları
- **Komut:** `flutter test test/core_next/stage10_9_2_startup_safety_test.dart`
- **Sonuç:** `5/5 PASSED` (Çıkış Kodu: 0)
  1. Sağlıklı açılışta tanı adımları tamamlanır ve PASS üretilir.
  2. Bozuk veya onarılamayan DB tespit edildiğinde fail-closed devreye girer (`failedBlocked: true`, `ERR-XXXXXX` hata referansı).
  3. SMS süpürme hatası durumunda hata izole edilir ve açılış devam eder.
  4. SMS süpürme işlemi askıda kalırsa 3 saniyelik bounded timeout tetiklenir ve açılış kilitlenmez.
  5. Daha önce bloke olmuş durumda koordinatör başlatılmaz, Legacy güvenlik modu korunur.

---

## 4. Görev B — Staging Sync Round-Trip Bulguları ve Kanıtları

### 4.1 Staging Ortam İzolasyon Durumu
- `TEST_DATABASE_URL` ortam değişkeni güvenli yerel test ayrımı gerektirmektedir.
- `server/src/config/test-db-guard.ts` güvenlik bekçisi çalıştırılmış ve 47 zorunlu güvenlik senaryosu test edilmiştir. Bu bekçi:
  - Canlı production hostlarını (`aws.rds.amazonaws.com`, `api.serenut.com`, `db.supabase.co`) kesin olarak engeller.
  - `NODE_ENV !== 'test'` durumunda fail-closed ile yürütmeyi durdurur.
  - Canlı veritabanına izinsiz bağlanmayı veya şema silmeyi (`DROP SCHEMA`) imkansız kılar.
- **VPS Staging Kanıtı:** Uzak sunucuda izole staging VPS erişimi doğrulanmamıştır. Canlı production sistemine müdahale etmeme kuralı uyarınca **canlı VPS üzerinde round-trip çalıştırılmamıştır**.

### 4.2 Yerel Sözleşme ve Entegrasyon Kanıtları
- İstemci tarafı Core Next Sync adaptörleri (`SqliteOutboxRepository`, `SyncV4Engine`, `SyncV4Client`) yerel SQLite üzerinde şu sözleşmeleri karşılamaktadır:
  - Satış ve iadelerin outbox tablosuna atomik yazılması.
  - Çift göndermede (duplicate push) idempotency korunumu (`event_id` ve `idempotency_key` tekilliği).
  - Ağ kesintisi veya sunucu 5xx durumunda outbox kayıtlarının `retry_count` ile beklemeye alınması ve veri kaybı yaşanmaması.
- Sunucu tarafında `sync-v4.materializer.ts` modülü:
  - `idempotent_consumer_log` kullanarak yinelenen satış/ödeme kayıtlarının mükerrer ledger veya cari hesap bakiyesi oluşturmasını engeller.

---

## 5. Görev C — Operational Rollback ve Güvenli Çalışma Prosedürü (Runbook)

### 5.1 Rollback Mekanizması Mimarisi
Core Next mimarisinde, feature flag'in (`coreNextSalesEngineEnabled`) kapatılması **TEK BAŞINA YETERLİ DEĞİLDİR**.
- Feature flag kapatıldığında sistem Legacy arayüzüne ve `serenut_pos.db` SQLite veritabanına geri döner.
- Ancak Core Next aktifken yapılan yeni satışlar, tahsilatlar ve iadeler `serenut_core_v2.db` içine yazılmıştır.
- Bu veriler Legacy veritabanına aktarılmadan flag kapatılırsa **VERİ GÖRÜNMEZLİĞİ VE BAKIYE UYUŞMAZLIĞI (SPLIT-BRAIN)** oluşur.
- Bu nedenle geri dönüş için `ReverseMigrationEngine.rollbackToLegacy` motorunun çalıştırılması zorunludur.

### 5.2 Operasyonel Acil Durum Runbook'u (Step-by-Step Rollback Runbook)

```text
================================================================================
🚨 ACİL DURUM GERİ DÖNÜŞ (OPERATIONAL ROLLBACK) RUNBOOK'U
================================================================================

AŞAMA 1: İŞLEM DONDURMA (WRITE FREEZE)
1. Yeni satış veya tahsilat girişini durdurun.
2. Satış controller'ı üzerindeki writeLock mekanizmasını devreye alın:
   SalesController.setMaintenanceLock(true) veya coordinator writeLock.

AŞAMA 2: VERİTABANI YEDEKLEMESİ
1. Her iki veritabanının da anlık fiziksel kopyasını alın:
   - SerenutBackups/serenut_pos_pre_rollback_<timestamp>.db
   - SerenutBackups/serenut_core_v2_pre_rollback_<timestamp>.db
2. PRAGMA integrity_check ile yedeklerin sağlamlığını doğrulayın.

AŞAMA 3: TERSİNE MİGRASYONUN ÇALIŞTIRILMASI (REVERSE-ROLLBACK)
1. ReverseMigrationEngine.rollbackToLegacy() motorunu tetikleyin:
   - Core Next'te oluşan yeni 'sales' kayıtları -> Legacy 'sales' tablosuna yazılır.
   - Core Next 'sale_items' -> Legacy 'sale_items' tablosuna yazılır.
   - Core Next 'ledger_entries' -> Legacy 'cash_transactions' & 'customer_transactions' tablolarına yansıtılır.
   - Core Next outbox kayıtları Legacy senkronizasyon kuyruğuna taşınır.

AŞAMA 4: ÇİFT YÖNLÜ MUTABAKAT VE SAYIM DOĞRULAMASI
1. Toplam satış adedi kontrolü: Legacy sales count == Core Next sales count.
2. Toplam ciro kontrolü: Legacy SUM(final_amount) == Core Next SUM(total_amount_cents) / 100.
3. Kasa ve cari bakiye mutabakatı: Kuruşu kuruşuna denk olmalıdır.
4. Mükerrer kayıt kontrolü (idempotency): Tekrarlanan rollback denemesinde aynı kayıtların çift yazılmadığı teyit edilir.

AŞAMA 5: FEATURE FLAG KAPATILMASI
1. SharedPreferences üzerindeki Core Next aktiflik bayrağını kapatın:
   prefs.setBool('core_next_sales_engine_enabled', false)
2. Uygulamayı yeniden başlatın (Cold Restart).
3. Legacy POS ekranında Core Next döneminde yapılan satışların ve güncel stokların eksiksiz listelendiğini doğrulayın.

AŞAMA 6: POST-ROLLBACK İZLEME
1. Outbox senkronizasyonunun Legacy kanalı üzerinden çalıştığını gözlemleyin.
2. Sentry/telemetry loglarında herhangi bir SQL veya foreign key ihlali olmadığını teyit edin.
================================================================================
```

### 5.3 Test Kanıtları
- **`stage10_8_5_reverse_rollback_test.dart`:** 5/5 PASSED (Çıkış Kodu: 0)
  - Tam kapsam veri taşıma (kullanıcılar, kategoriler, ürünler, satış kalemleri, defter ve outbox).
  - Rollback idempotency (ikinci kez çalıştırmada mükerrer veri üretmeme).
  - Core Next üzerinde yapılan yeni satışların Legacy sistemine kayıpsız aktarımı.
  - Parasal hassasiyet (kuruş yuvarlama ve 0.01 TL mutabakatı).
  - SQLite `integrity_check` ve `foreign_key_check` tam uyumluluğu.
- **`stage10_9_7_startup_restore_rollback_test.dart`:** 5/5 PASSED (Çıkış Kodu: 0)
  - WAL aktifken alınan yedeklerin ana veritabanı kapatılıp taşınsa bile tam kurtarılması (Full Recovery Drill).
  - Core Next işlemlerinin Legacy tablolarına canlı geri dönüşü.

---

## 6. Görev D — Pilot Readiness Denetimi

| Denetim Maddesi | Durum | Açıklama |
|---|---|---|
| **Feature Flag Varsayılanı** | ✅ GÜVENLİ | `coreNextSalesEngineEnabledProvider` varsayılan değeri `false`'dur. |
| **Migration Runner Varsayılanı** | ✅ GÜVENLİ | `coreNextMigrationRunnerProvider` varsayılan değeri `null`'dur (devre dışı). |
| **Fail-Closed Davranışı** | ✅ GÜVENLİ | Bütünlük hatası, mutabakat sapması veya yedekleme hatasında sistem Legacy modda kalır. |
| **Tek Doğruluk Kaynağı (SSOT)** | ✅ GÜVENLİ | Feature flag kapalıyken tüm okuma/yazmalar Legacy `serenut_pos.db`'ye; açıkken Core Next `serenut_core_v2.db`'ye yapılır. Çift yazma (dual-write) engellenmiştir. |
| **Hassas Veri Maskeleme** | ✅ GÜVENLİ | Kullanıcı arayüzünde iç SQL ve sistem hataları maskelenmekte; telemetriye korelasyon kodu (`ERR-XXXXXX`) iletilmektedir. |
| **Yarım Kalan İşlem Kurtarma** | ✅ GÜVENLİ | `CoreNextBootstrapCoordinator` önceki oturumda yarım kalmış işlem (`migration_in_progress`) tespit ettiğinde temiz kurtarma yapar. |
| **Donanım & Yazıcı Entegrasyonu** | ⚠️ KISITLI | Donanım işçisi (`HardwareWorker`) ve yazıcı arayüzleri simülasyon ve kontrat seviyesinde test edilmiştir; gerçek fiziki ESC/POS ve TSPL yazıcı cihazları pilot aşamasında yerinde doğrulanmalıdır. |

---

## 7. Test Sonuçları ve Gerçek Komutlar

Aşağıdaki tüm testler bu aşamada yerel olarak fiilen çalıştırılmış ve sonuçları doğrulanmıştır:

| Test Dosyası | Komut | Durum | Çıkış Kodu | Kapsam |
|---|---|---|---|---|
| **Startup Safety Test** | `flutter test test/core_next/stage10_9_2_startup_safety_test.dart` | **PASS (5/5)** | 0 | Bounded timeouts, SMS kilit izolasyonu, splash hang koruması, fail-closed. |
| **Full Recovery & Rollback Drill** | `flutter test test/core_next/stage10_9_7_startup_restore_rollback_test.dart` | **PASS (5/5)** | 0 | Gerçek açılış çağrı zinciri, WAL yedek kurtarma tatbikatı, tersine rollback provası. |
| **Bootstrap Coordinator Test** | `flutter test test/core_next/core_next_bootstrap_coordinator_test.dart` | **PASS (16/16)** | 0 | 16 zorunlu senaryo: yedekleme, idempotency, yarım kalma, mutabakat, adversarial sapma denetimi. |
| **Reverse Rollback Proof** | `flutter test test/core_next/stage10_8_5_reverse_rollback_test.dart` | **PASS (5/5)** | 0 | Core Next'ten Legacy'ye kayıpsız geri aktarım, kuruş hassasiyeti, FK denetimleri. |
| **Financial Adversarial Audit** | `flutter test test/core_next/stage10_9_6_financial_adversarial_audit_test.dart` | **PASS (7/7)** | 0 | Defter bütünlüğü, çift ödeme/iade engeli, outbox idempotency, negatif bakiye koruması. |
| **Test DB Guard (Server)** | `npx ts-node src/test/test_db_guard.test.ts` (server dizini) | **PASS (47/47)** | 0 | Production URL engelleme, fail-closed DB izolasyonu, DROP SCHEMA koruması. |

---

## 8. Kanıt Ayrımı: Production vs. Staging vs. Yerel

1. **Production Ortamı:**
   - Canlı production VPS ve PostgreSQL veritabanına **hiçbir şekilde bağlanılmamış**, veri değiştirilmemiş ve production rollback uygulanmamıştır.
2. **Staging Ortamı:**
   - İzole ve yetkilendirilmiş uzak staging VPS erişimi ortam değişkenlerinde tanımlı olmadığı için uzak round-trip testi **CANLI VPS ÜZERİNDE YAPILMAMIŞTIR**. Bu durum açıkça eksik kanıt olarak kayıt altına alınmıştır.
3. **Yerel (Local) Ortamı:**
   - İstemci ve sunucu mimarisi SQLite FFI ve yerel Node.js ortamında test edilmiştir.
   - Bounded timeout, kilit koruması, reverse-rollback ve finansal mutabakat kanıtları yerel ortamda %100 oranında kanıtlanmıştır.

---

## 9. Açık Riskler ve Engeller

1. **Uzak Staging VPS Doğrulama Eksikliği:**
   - Sync v4 protokolünün PostgreSQL `sync_v4_events` ve `idempotent_consumer_log` tabloları üzerindeki uçtan uca canlı performansı izole bir staging sunucusunda teyit edilmelidir.
2. **Fiziki Donanım Doğrulaması:**
   - Ağ ve USB üzerinden çalışan gerçek termal fiş/etiket yazıcılarının (ESC/POS, TSPL) açılış sırasındaki gecikmeleri yerinde pilot cihazda gözlemlenmelidir.
3. **Operasyonel Eğitim:**
   - Pilot aşamasında teknik ekibin feature flag'i sadece arayüzden kapatmakla yetinmeyip runbook'ta belirtilen `ReverseMigrationEngine.rollbackToLegacy` sürecini işletmesi gerektiği bilinmelidir.

---

## 10. Pilot Öncesi Kalan İşler

1. İzole staging ortamında gerçek Android ve Windows istemcileriyle birer kez `push` -> `materialize` -> `pull` senkronizasyon turunun canlı provası.
2. Pilot mağaza cihazında fiziki termal yazıcı ve barkod okuyucu ile test satışı yapılması.
3. Sahada acil geri dönüş gereksinimi için rollback çalıştırıcı betiğin (CLI veya gizli yönetici menüsü) yetkili personelle tatbikatı.

---

## 11. Nihai Karar

Seçenekler: `BLOCKED` | `READY_FOR_FURTHER_TESTING` | `READY_FOR_CUTOVER_REVIEW`

### **Karar: `READY_FOR_FURTHER_TESTING`**

**Gerekçe:**
- Açılış güvenliği (`Startup Safety`), kilitlenme zaman aşımları (`Bounded Timeouts`), `Fail-Closed` bütünlük koruması ve `Reverse-Rollback` mekanizması yerel birim ve entegrasyon testlerinde eksiksiz olarak kanıtlanmıştır.
- Ancak izole bir uzak staging VPS üzerinde canlı PostgreSQL round-trip provası ve gerçek fiziki donanım doğrulaması henüz tamamlanmadığı için doğrudan cutover review aşamasına geçilmemiş; bir sonraki kontrollü pilot ve staging testleri için sistem **READY_FOR_FURTHER_TESTING** statüsünde onaylanmıştır.
