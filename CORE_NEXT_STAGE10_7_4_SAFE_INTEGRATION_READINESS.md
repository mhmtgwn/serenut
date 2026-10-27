# SERENUT OS — STAGE 10.7.4
## GÜVENLİ POSTGRESQL ENTEGRASYONU VE RUNTIME HAZIRLIK RAPORU

**Tarih:** 14 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Kapsam:** PostgreSQL Test Veritabanı İzolasyonu, Yıkıcı Test Güvenliği, Entegrasyon Test Planı ve İstemci Runtime Hazırlığı

---

## 1. YÖNETİCİ ÖZETİ VE ÇIKIŞ KAPISI (GATE) DURUMU

| Kriter | Durum | Gerekçe / Adli Tespit |
| :--- | :---: | :--- |
| **`POSTGRES_TEST_ISOLATION`** | **UNVERIFIED / GAP IDENTIFIED** | Mevcut `database.ts` ve bağımsız test komutlarında `nutopiano` veya geliştirme veritabanına bağlanıp şema silinmesini engelleyen katı fail-closed korumanın bulunmadığı adli olarak kanıtlanmıştır. |
| **`REAL_POSTGRES_TESTS`** | **SKIPPED / BLOCKED** | `sync_v4_domain_materialization.test.ts` testi `DROP SCHEMA public CASCADE` içerdiğinden ve izole test veritabanı ayrılmadığından veri kaybını önlemek adına **çalıştırılmamıştır**. |
| **`CORE_NEXT_CLIENT_TESTS`** | **PASS (157/157)** | `test/core_next/` altındaki tüm istemci testleri izole SQLite FFI ve kontrollü MockClient ile eksiksiz çalışmış ve 0 hata ile geçmiştir. |
| **`RUNTIME_READINESS`** | **DESIGNED / READY FOR COUPLING** | `SyncV4PullWorker`, `SyncV4HttpClient` ve `core_providers.dart` mimarisi incelenmiş; `SyncCoordinator` yaşam döngüsü tasarlanmış, `lib/` henüz değiştirilmemiştir. |
| **`LIVE_GATE`** | **BLOCKED** | Güvenli test veritabanı altyapısı kurulup gerçek PostgreSQL testleri doğrulanana ve `lib/` entegrasyonu tamamlanana kadar canlı geçiş kesinlikle bloke edilmiştir. |

---

## 2. GÖREV A — TEST VERİTABANI GÜVENLİK İNCELEMESİ VE MEVCUT AÇIKLAR

### 2.1. Mevcut Yapılandırma ve Çağrı İncelemesi
1. **`server/src/config/database.ts`**:
   ```ts
   const nodeEnv = process.env.NODE_ENV || 'development';
   const envFile = nodeEnv === 'test' ? '.env.test' : '.env';
   dotenv.config({ path: path.resolve(process.cwd(), envFile) });
   ```
   *Tehlike 1:* Bir test doğrudan `ts-node src/test/<test_adi>.ts` şeklinde çalıştırıldığında `process.env.NODE_ENV` tanımsızdır. `nodeEnv` doğrudan `'development'` değerine düşer ve `.env` dosyasını yükler!
2. **`server/src/test/sync_v4_domain_materialization.test.ts`**:
   ```ts
   const setupClient = await pgPool.connect();
   try {
     await setupClient.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO public;');
   } finally {
     setupClient.release();
   }
   ```
   *Tehlike 2:* Bu dosya doğrudan çağrıldığında, hiçbir ortam veya veritabanı adı kontrolü yapmadan `pgPool` üzerinden `.env` içindeki geliştirme veritabanına bağlanır ve `public` şemasındaki **tüm tabloları, verileri ve enum'ları anında yok eder**.
3. **`server/src/test/run_all_ac_tests.ts` Açığı**:
   ```ts
   if (!testDbUrl.includes('test') && !testDbUrl.includes('localhost') && !testDbUrl.includes('127.0.0.1')) { ... }
   ```
   *Tehlike 3:* `testDbUrl.includes('localhost')` kuralı, yerel makinedeki `postgres://localhost:5432/nutopiano` veya `postgres://localhost:5432/serenut_dev` bağlantılarını "güvenli test veritabanı" sanarak kabul eder! Bu durum yerel geliştirme ortamının silinmesine yol açabilir.

### 2.2. Tasarlanan Katı Fail-Closed Test DB Koruma Protokolü
Herhangi bir yıkıcı SQL (`DROP SCHEMA`, `TRUNCATE`, `DROP TABLE`) çalıştırılmadan önce aşağıdaki 5 aşamalı güvenlik bariyeri zorunlu kılınmalıdır:

1. **Katı İsim Deseni (Name Regex):**
   Hedef veritabanı adı (`new URL(dbUrl).pathname.replace('/', '')`) kesinlikle `/^serenut_.*_test$/` desenine uymalı veya açıkça `serenut_test` olmalıdır.
2. **Yasaklı İsimler Kara Listesi (Blacklist):**
   Veritabanı URL'si veya adı şunları içeriyorsa bağlantı anında reddedilmelidir:
   `nutopiano`, `production`, `prod`, `live`, `customer`, `primary`, `serenut_db`, `shaman`.
3. **Canlı Bağlantı Teyidi (SQL Guard):**
   `pgPool.connect()` sonrasında ilk sorgu olarak şu çalıştırılmalı ve teyit edilmelidir:
   ```sql
   SELECT current_database() AS db_name;
   ```
   Dönen `db_name` katı test regex'ini karşılamıyorsa `throw new Error('FATAL_UNSAFE_DATABASE: ' + db_name)` fırlatılmalı ve proses `process.exit(1)` ile durdurulmalıdır.
4. **Dosya İçi Standalone Guard:**
   `sync_v4_domain_materialization.test.ts` ve benzeri tüm test dosyalarının en başına `assertIsolatedTestDatabase(pgPool)` çağrısı zorunlu kılınmalıdır.

---

## 3. GÖREV B — GERÇEK POSTGRESQL ENTEGRASYON TEST PLANI

Mevcut Express / PostgreSQL altyapısında sunucu tarafındaki sözleşmeler incelenmiş ve gerçek PostgreSQL test ortamı hazır olduğunda koşulacak senaryolar haritalandırılmıştır:

### 3.1. Senaryo Matrisi ve Sunucu Karşılıkları
| Senaryo | Test Edilecek Sunucu Davranışı | İlgili Kod / SQL Karşılığı |
| :--- | :--- | :--- |
| **1. Satış & Stok Tek Transaction** | Bir satış mutasyonu geldiğinde `sales`, `sale_items`, `products` (stok düşümü) ve `inventory_movements` aynı transaction'da tamamlanmalı. | `sync-v4.materializer.ts:265-290` (`applyDomainMutation`) |
| **2. İdempotency (Tekrarlanan Mutasyon)** | Aynı `mutation_id` aynı payload ile tekrar gönderildiğinde ikinci stok düşümü olmamalı, mevcut `revision` dönmeli. | `sync-v4.routes.ts:133-146` (`SELECT revision FROM sync_v4_changes`) |
| **3. Payload Conflict** | Aynı `mutation_id` farklı bir payload ile tekrar gelirse işlem reddedilmeli. | `sync-v4.routes.ts:139` (`mutation_payload_conflict`) |
| **4. İade & İptal Doğrulaması** | İade mutasyonu geldiğinde `RefundService.create` çağrılmalı, stok artmalı (`quantity_delta > 0`) ve `refunds` tablosuna yazılmalı. | `sync-v4.materializer.ts:141-159` |
| **5. Değişiklik Günlüğü ve Pull Tutarlılığı** | Başarılı mutasyon `sync_v4_changes` ve `sync_v4_entities` tablolarına artan `revision` ile yazılmalı. | `sync-v4.routes.ts:224-257` |
| **6. Sayfalama ve Cursor Sürekliliği** | `/pull?cursor=X&limit=Y` sorgusu `revision > X` filtrelemeli ve son kaydın revizyonunu `next_cursor` olarak dönmeli. | `sync-v4.routes.ts:377-385` |
| **7. Çok Kasalı Stok Yakınsaması** | Kasa A'nın push ettiği satış, Kasa B'nin pull çağrısında listelenmeli ve Kasa B yerel SQLite stoğunu düşürmelidir. | `sync-v4.routes.ts` ↔ `SyncV4PullWorker` |
| **8. Rollback ve Hata İzolasyonu** | Batch içindeki bozuk bir mutasyon (`invalid_mutation`) `ROLLBACK TO SAVEPOINT sync_mutation` yapmalı, diğer mutasyonları bozmamalıdır. | `sync-v4.routes.ts:282` |

> [!IMPORTANT]
> **Adli Ayrım Notu:** İstemci tarafında `test/core_next/stage10_7_3_pull_worker_test.dart` içinde koşan 14 test, **MockClient ve yerel SQLite FFI** kullanmaktadır. Bu testler istemcinin iş mantığını ve dayanıklılığını mükemmel şekilde kanıtlamakta, ancak yukarıdaki gerçek PostgreSQL / Express uçtan uca ağ testlerinin yerine geçmemektedir.

---

## 4. GÖREV C — RUNTIME HAZIRLIĞI VE YAŞAM DÖNGÜSÜ TASARIMI

### 4.1. Mevcut Mimari ile Karşılaştırma
- **Lisans & Yetki:** Mevcut sistemde cihaz lisansı ve aktivasyonu `license_entitlements` ve JWT oturumu üzerinden yönetilir. `SyncV4HttpClient` başlıklarında `x-device-activation-id`, `x-device-id` ve `Authorization: Bearer <token>` gönderir.
- **Provider Zinciri:** `core_providers.dart` içinde `coreSyncHttpClientProvider`, `coreSyncPullIngestionServiceProvider` ve `coreSyncPullWorkerProvider` mevcuttur.
- **Eksik Halka:** Worker'ı periyodik olarak veya olay tabanlı çalıştıran bir **Sync Coordinator (Eşgüdüm Yöneticisi)** henüz tanımlanmamıştır.

### 4.2. Canlı Uygulama Yaşam Döngüsü ve Tetikleme Tasarımı
Canlı uygulamaya (`lib/`) geçildiğinde worker'ı yönetecek katman `CoreSyncCoordinator` olmalıdır:

```
[Kasa Uygulaması Yaşam Döngüsü]
        │
        ├── 1. Başlangıç (Cold Start):
        │      - SQLite açılır ve coreDatabaseProvider pre-warm edilir.
        │      - Lisans / Cihaz kimliği okunup coreSyncHttpClientProvider beslenir.
        │      - Worker getSavedCursor() sorgular:
        │          - Cursor == 0 ve tablolar boşsa -> worker.bootstrap()
        │          - Cursor > 0 ise -> coordinator.triggerSyncCycle()
        │
        ├── 2. Düzenli Senkronizasyon (Periodic Loop):
        │      - Kural: "Önce Push, Sonra Pull"
        │      - 1. Adım: outboxProcessor.pushPendingMutations() (Yerel satışları sunucuya ilet)
        │      - 2. Adım: pullWorker.pullAll() (Diğer kasaların hareketlerini çek)
        │      - Periyot: Çevrimiçi iken her 30-60 saniyede bir.
        │
        ├── 3. İnternet Kesintisi (Network Drop / Offline):
        │      - Worker transient retry (3 kez) sonrası durur.
        │      - Kasa tamamen yerel SQLite ile offline satışa devam eder.
        │      - connectivity_plus 'online' sinyali verdiğinde anında sync döngüsü tetiklenir.
        │
        ├── 4. Oturum Sona Ermesi (Session Expiry / 401 Unauthorized):
        │      - HTTP 401 kalıcı hata olarak işaretlenir (isPermanentError = true).
        │      - Coordinator zamanlayıcıyı geçici olarak durdurur (pause).
        │      - Kullanıcı yeniden giriş yapana kadar gereksiz ağ trafiği engellenir.
        │
        └── 5. Cihaz Değişimi (Device Change / Re-activation):
               - Kasa aktivasyon kimliği değiştiğinde eski kasanın cursor'ı geçersiz kalır.
               - Yerel sync_state ve sync_applied_events temizlenerek güvenli re-bootstrap tetiklenir.
```

---

## 5. ÇALIŞTIRILAN GÜVENLİ TESTLERİN GERÇEK SONUÇLARI

- **Komut:** `flutter test test/core_next/`
- **Sonuç:** **157/157 test BAŞARILI** (0 hata, 0 regresyon)
- **Kapsam:**
  - `stage10_7_3_pull_worker_test.dart`: 14 test
  - `stage10_7_2_identity_safety_test.dart`: 8 test
  - Diğer çekirdek modüller (Outbox, HTTP client, Ledger, Checkout, Migration): 135 test
- **Git Durumu:**
  - `git diff --check`: Temiz.
  - `lib/` dizini: **%100 DOKUNULMAMIŞ (0 satır değişiklik)**.
  - Hiçbir `git commit`, `git push` veya `git add` yapılmamıştır.

---

## 6. CANLIYA GEÇİŞ (CUTOVER) İÇİN KALAN ZORUNLU ADIMLAR

1. **Ayrı Test PostgreSQL Veritabanı Kurulumu:**
   Yıkıcı testlerin koşabilmesi için `serenut_test_isolated` adında bağımsız bir veritabanı veya izole Docker container ortamı yapılandırılmalıdır.
2. **PostgreSQL Test Koruma Guard'ının Eklenmesi:**
   `database.ts` ve test dosyalarına `assertIsolatedTestDatabase()` kontrolü eklenerek `nutopiano` veya canlı veritabanına yanlışlıkla dokunulması imkansız hale getirilmelidir.
3. **CoreSyncCoordinator Geliştirilmesi:**
   Outbox Push ve Pull Worker'ı senkronize eden koordinatör sınıfı `core_next/` içine yazılmalıdır.
4. **Kontrollü `lib/` Entegrasyonu (Feature Flag):**
   `SalesEngineAdapter` üzerinden `useCoreNext = false` varsayılanı korunarak, ayarlar ekranından kontrollü geçiş sağlanmalıdır.

---

## 7. ÇIKIŞ KARARI

- **`POSTGRES_TEST_ISOLATION`:** `UNVERIFIED / GAP IDENTIFIED`
- **`REAL_POSTGRES_TESTS`:** `SKIPPED / BLOCKED`
- **`CORE_NEXT_CLIENT_TESTS`:** `PASS (157/157)`
- **`RUNTIME_READINESS`:** `DESIGNED`
- **`LIVE_GATE`:** **`BLOCKED`**
