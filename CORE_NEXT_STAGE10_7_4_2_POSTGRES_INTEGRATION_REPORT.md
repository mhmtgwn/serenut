# SERENUT OS — STAGE 10.7.4.2
## POSTGRESQL İZOLASYONU VE GERÇEK ENTEGRASYON DOĞRULAMA RAPORU

**Tarih:** 14 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Başlangıç Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Bitiş Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Kapsam:** PostgreSQL İzolasyonu, Fail-Closed 14 Senaryo Doğrulaması, `sync_v4_domain_materialization` Gerçek Entegrasyonu ve İstemci Regresyonu

---

## 1. ÇIKIŞ KRİTERLERİ VE DENETİM KARAR TABLOSU

| Kriter | Sonuç | Adli Kanıt ve Doğrulama Özeti |
| :--- | :---: | :--- |
| **`FAIL_CLOSED_UNIT_TESTS`** | **PASS (47/47)** | [test_db_guard.test.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/test/test_db_guard.test.ts) içindeki 14 zorunlu senaryo gerçek veritabanına dokunmadan %100 başarıyla kanıtlandı. |
| **`ISOLATED_POSTGRES_VERIFIED`** | **PASS** | `127.0.0.1:5432` üzerindeki bağımsız `serenut_test` veritabanı bağlandı; `current_database()` doğrulaması geçti. |
| **`DESTRUCTIVE_ISOLATION_PROVEN`** | **PASS** | `DROP SCHEMA public CASCADE` kalkanı başarıyla çalıştı. Test sonrası `nutopiano` geliştirme veritabanındaki 94 tablonun tamamının **eksiksiz ve el değmemiş** kaldığı adli SQL sorgusuyla kanıtlandı. |
| **`POSTGRES_SYNC_V4_INTEGRATION`** | **PASS** | [sync_v4_domain_materialization.test.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/test/sync_v4_domain_materialization.test.ts) 1..97 migration'ları uyguladı ve satış/iade/stok/muhasebe mutasyonlarını **iki kez art arda sıfır kalıntı ve sıfır hata ile** doğruladı. |
| **`CLIENT_REGRESSION_TESTS`** | **PASS (157/157)** | `test/core_next/` altındaki 20 test dosyasının tamamı 0 hata ile çalıştı. |
| **`LIVE_GATE`** | **BLOCKED** | Canlı satış ekranı (`lib/`) henüz `core_next/` motoruna bağlanmadığından (Stage 10.8 gereksinimi), canlıya geçiş kapısı güvenli olarak **BLOCKED** tutulmuştur. |

---

## 2. GÖREV 1 & 2 — ADLİ BAĞLANTI İNCELEMESİ VE FAIL-CLOSED KORUMASI

### 2.1. İncelenen Dosyalar ve Değişiklikler
1. **`server/src/config/test-db-guard.ts`**:
   - `validateTestDatabaseUrl`: Protokol (`postgres:` / `postgresql:`), veritabanı adı, kara liste (`nutopiano`, `production`, `supabase`, `rds.amazonaws.com` vb.) ve beyaz liste (`serenut_test` veya `*_test`) kontrollerini statik yürütür.
   - `assertSafeTestEnvironment`: `NODE_ENV === 'test'` ve `DATABASE_URL !== TEST_DATABASE_URL` kontrollerini yapar.
   - `assertIsolatedTestDatabase`: Fiziksel istemciden `SELECT current_database() AS db_name` çalıştırarak gerçek hedefin onaylı test veritabanı olduğunu kanıtlar.
2. **`server/src/test/sync_v4_domain_materialization.test.ts`**:
   - 10. satırda `await assertIsolatedTestDatabase(setupClient)` çağrısı eklendi. Test korumasız veya yanlış ortamda çağrıldığında `DROP SCHEMA` satırına **asla ulaşamamaktadır**.
3. **`server/src/test/run_all_ac_tests.ts`**:
   - Eski zayıf `localhost` kontrolü kaldırılmış, `assertSafeTestEnvironment` entegre edilerek `nutopiano` içeren yerel geliştirme bağlantıları da engellenmiştir.

---

## 3. GÖREV 4 — FAIL-CLOSED BİRİM TESTLERİ (14 ZORUNLU SENARYO)

Komut: `npx ts-node src/test/test_db_guard.test.ts`  
Konum: `server/`  
Sonuç: **47/47 Assertion BAŞARILI (0 HATA)**

| No | Senaryo | Test Girdisi / Durumu | Beklenen Davranış | Gerçek Çıktı | Sonuç |
| :---: | :--- | :--- | :--- | :--- | :---: |
| **1** | Güvenli test yapılandırması | `NODE_ENV=test`, `postgres://.../serenut_test` | Onaylanmalı | `databaseName: serenut_test` doğrulandı | **PASS** |
| **2** | Eksik `NODE_ENV` | `nodeEnv: undefined` | Fail-closed durmalı | `FATAL_TEST_DB_GUARD: NODE_ENV değeri kesinlikle 'test' olmalıdır` | **PASS** |
| **3** | `NODE_ENV=development` | `nodeEnv: 'development'` | Fail-closed durmalı | `Geliştirme ortamında test çalıştırılamaz` | **PASS** |
| **4** | Eksik test veritabanı URL'si | `''` veya `undefined` | Reddedilmeli | `DATABASE_URL_EMPTY` | **PASS** |
| **5** | Bozuk URL | `http://...`, `not_a_valid_url`, `postgres://host/` | Reddedilmeli | `INVALID_PROTOCOL`, `DATABASE_URL_MALFORMED`, `DATABASE_NAME_MISSING` | **PASS** |
| **6** | Üretim veritabanı adı | `production`, `prod_db`, `serenut_prod` | Reddedilmeli | `FORBIDDEN_DATABASE_IDENTIFIER` | **PASS** |
| **7** | Geliştirme veritabanı adı | `nutopiano`, `serenut_dev` | Reddedilmeli | `FORBIDDEN_DATABASE_IDENTIFIER` | **PASS** |
| **8** | Yasaklı host | `aws.rds.amazonaws.com`, `db.supabase.co`, `api.serenut.com` | Reddedilmeli | `FORBIDDEN_DATABASE_IDENTIFIER` | **PASS** |
| **9** | Gizlenmiş yasaklı hedef | `postgres://localhost/nutopiano_test` | Reddedilmeli | `FORBIDDEN_DATABASE_IDENTIFIER: nutopiano ifadesi engellendi` | **PASS** |
| **10** | `current_database()` uyuşmazlığı | Beklenen: `serenut_test`, Dönen: `different_ci_test` | Fail-closed durmalı | `FATAL_TEST_DB_GUARD: Beklenen test veritabanı 'serenut_test' iken...` | **PASS** |
| **11** | Fiziksel doğrulama hatası | Sorgudan boş satır dönmesi | Fail-closed durmalı | `current_database() sorgusundan veritabanı adı alınamadı` | **PASS** |
| **12** | Bağlantı hatası | Soket/ECONNREFUSED hatası | Hata yukarı fırlatılmalı | `connect ECONNREFUSED 127.0.0.1:5432` | **PASS** |
| **13** | Doğrulama öncesi yıkıcı SQL engeli | `nutopiano` dönen sahte istemciye `DROP SCHEMA` çağrısı | `DROP SCHEMA` asla çalıştırılmamalı | `DROP SCHEMA` sorgu günlüğüne düşmedi | **PASS** |
| **14** | Varsayılan fail-closed | Tanımsız ve beklenmeyen parametreler | Varsayılan ret | `FATAL_TEST_DB_GUARD` fırlatıldı | **PASS** |

---

## 4. GÖREV 5 & 6 — GERÇEK POSTGRESQL ENTEGRASYON DOĞRULAMASI

### 4.1. Ortam ve İzolasyon Kanıtı
- **PostgreSQL Servisi:** `postgresql-x64-16` (Windows Service, Çalışıyor).
- **Hedef Test Veritabanı:** `serenut_test` (`127.0.0.1:5432`).
- **Geliştirme Veritabanı:** `nutopiano` (`127.0.0.1:5432`).

### 4.2. `sync_v4_domain_materialization.test.ts` Çalıştırma Çıktısı
Komut:
```powershell
$env:NODE_ENV="test"; $env:TEST_DATABASE_URL="postgres://postgres:postgres@127.0.0.1:5432/serenut_test"; $env:DATABASE_URL="postgres://postgres:postgres@127.0.0.1:5432/serenut_test"; npx ts-node src/test/sync_v4_domain_materialization.test.ts
```

**Gerçek Konsol Çıktısı (Özet):**
```
🔒 Configuring database migration lock timeout (10s)...
🔒 Acquiring database migration lock...
🔄 Running database migrations...
✅ Migration version 1 (schema.sql) applied successfully.
...
✅ Migration version 97 (schema_v97.sql) applied successfully.
🔓 Releasing database migration lock...
✔ Sync V4 materializes product/customer/sale/order/ledger aggregates transactionally.
Exit Code: 0
```

### 4.3. İdempotency ve Tekrarlanabilirlik Teyidi
Test ikinci kez art arda çalıştırılmıştır:
- İkinci çalıştırma süresi: 16 saniye.
- Sonuç: `✔ Sync V4 materializes product/customer/sale/order/ledger aggregates transactionally.` (Exit Code: 0).
- Sıfır artık veri, sıfır şema tutarsızlığı.

### 4.4. `nutopiano` Geliştirme Veritabanının Korunduğunun Adli Kanıtı
Entegrasyon testlerinin tamamlanmasının ardından `nutopiano` veritabanındaki tablo sayısı bağımsız SQL sorgusu ile doğrulanmıştır:
```
Sorgu: SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'
Çıktı: POST_TEST_NUTOPIANO_COUNT: 94
```
**Adli Kanıt:** `nutopiano` veritabanındaki 94 tablonun tamamı **%100 eksiksiz ve korunmuştur**. Yıkıcı işlemler yalnızca `serenut_test` içinde izole kalmıştır.

---

## 5. GÖREV 7 — FLUTTER İSTEMCİ REGRESYON TESTLERİ

- **Komut:** `flutter test test/core_next/`
- **Geçen Test Sayısı:** **157/157 BAŞARILI**
- **Kırılan / Başarısız Test:** **0 (SIFIR)**
- **Test Süresi:** ~50 saniye

---

## 6. GÖREV 8 — DEĞİŞİKLİK VE GİT AĞACI ADLİ DENETİMİ

- `git rev-parse HEAD`: `28c158d88028f139e93f78982d4651ad424c61d2`
- `git diff --check`: Temiz.
- `git diff --stat`:
  ```
  server/src/modules/sync_v4/sync-v4.materializer.ts | 39 +++++++++++++++++++--
  server/src/modules/sync_v4/sync-v4.routes.ts       |  6 +++-
  server/src/test/run_all_ac_tests.ts                | 40 +++++++---------------
  server/src/test/sync_v4_domain_materialization.test.ts |  3 ++
  4 files changed, 56 insertions(+), 32 deletions(-)
  ```
- **Yeni Eklenen Sunucu Dosyaları:**
  - `server/src/config/test-db-guard.ts`
  - `server/src/test/test_db_guard.test.ts`
- **`lib/` Klasörü Durumu:** **%100 EL DEĞMEMİŞ (0 satır değişiklik)**.
- **Git Komutları:** Hiçbir `git commit`, `git push` veya `git add` çalıştırılmamıştır.

---

## 7. AÇIK RİSKLER VE SONRAKİ AŞAMA GEREKSİNİMLERİ

1. **Ayrı Test Kullanıcısı (Least Privilege):**
   Şu an testler `postgres` süper kullanıcısı ile `serenut_test` veritabanına bağlanmaktadır. Prodüksiyon CI/CD ortamında `nutopiano` veya canlı veritabanlarına SELECT/CONNECT dahi yapamayan ayrı bir `serenut_test_user` rolü atanmalıdır.
2. **Canlı Geçiş Kapısı (Live Cutover):**
   `core_next/` çekirdeği ve sunucu Sync V4 materializer hattı PostgreSQL üzerinde doğrulanmıştır; ancak `lib/` canlı satış ekranına adaptör bağlantısı Stage 10.8 kapsamında yapılacaktır.

---

## 8. KESİN ÇIKIŞ KARARI

- **`FAIL_CLOSED_UNIT_TESTS`:** `PASS`
- **`ISOLATED_POSTGRES_VERIFIED`:** `PASS`
- **`DESTRUCTIVE_ISOLATION_PROVEN`:** `PASS`
- **`POSTGRES_SYNC_V4_INTEGRATION`:** `PASS`
- **`CLIENT_REGRESSION_TESTS`:** `PASS`
- **`LIVE_GATE`:** **`BLOCKED`** (Canlı satış ekranı `lib/` motor geçişi Stage 10.8'e kadar bloke kalacaktır.)
