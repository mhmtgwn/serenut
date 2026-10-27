# SERENUT OS — STAGE 10.7.4.1
## POSTGRESQL TEST GÜVENLİĞİ: FAIL-CLOSED KORUMASININ UYGULANMASI VE KANITLANMASI RAPORU

**Tarih:** 14 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Kapsam:** PostgreSQL Test Veritabanı Fail-Closed Koruma Modülü, Yıkıcı Test Kalkanı, Birim Testleri ve İzolasyon Doğrulaması

---

## 1. ÇIKIŞ KRİTERLERİ VE DENETİM KARAR TABLOSU

| Kriter | Değer | Gerekçe / Adli Kanıt |
| :--- | :---: | :--- |
| **`FAIL_CLOSED_CONFIG`** | **PASS** | `test-db-guard.ts` modülü oluşturuldu. `NODE_ENV !== 'test'`, eksik URL, bozuk format veya eksik parametre durumunda anında fırlatarak işlemi durdurduğu 43 assertion ile kanıtlandı. |
| **`DEV_DB_REJECTION`** | **PASS** | `nutopiano`, `production`, `supabase`, `rds.amazonaws.com` vb. kara liste hedefleri ile `localhost` veya `127.0.0.1` üzerindeki geliştirme veritabanları **kesinlikle reddedildi** (`run_all_ac_tests.ts` ve doğrudan çağrı test edildi). |
| **`DESTRUCTIVE_TEST_GUARD`** | **PASS** | `sync_v4_domain_materialization.test.ts:10` satırına `assertIsolatedTestDatabase()` bariyeri eklendi; doğrudan çağrıldığında `DROP SCHEMA` satırına **asla ulaşamadan** testi fail-closed ile durdurduğu terminal çıktısıyla kanıtlandı. |
| **`SAFE_UNIT_TESTS`** | **43/43 BAŞARILI** | `server/src/test/test_db_guard.test.ts` (8 ayrı arıza ve onay senaryosu) gerçek veritabanına bağlanmadan, sıfır yıkıcı etkiyle %100 başarıyla çalıştırıldı. |
| **`ISOLATED_POSTGRES_AVAILABLE`** | **NO / UNVERIFIED** | Sistemde `serenut_test` veya onaylı izole bir test PostgreSQL veritabanı henüz doğrulanmamış ve ayrılmamıştır. |
| **`REAL_POSTGRES_INTEGRATION`** | **SKIPPED** | İzole test PostgreSQL veritabanı ayrılmadığı için `DROP SCHEMA` içeren gerçek entegrasyon testleri güvenli şekilde atlanmıştır. |
| **`LIVE_GATE`** | **BLOCKED** | İzole test ortamı kurulup gerçek entegrasyon testleri geçmeden canlı geçiş kapısı kesinlikle bloke kalmaya devam edecektir. |

---

## 2. GÖREV 1 — BAĞLANTI YOLU VE RİSK ANALİZİ

Aşağıdaki bileşenler kaynak kodları üzerinden incelenmiş ve risk noktaları tespit edilmiştir:

1. **`server/src/config/database.ts`**:
   - `nodeEnv = process.env.NODE_ENV || 'development'` satırı nedeniyle, bağımsız çalıştırılan testlerde `NODE_ENV` belirtilmediğinde varsayılan olarak `.env` (geliştirme ortamı) yüklenmekteydi.
2. **`server/src/test/sync_v4_domain_materialization.test.ts`**:
   - `setupClient.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO public;')` satırından önce hiçbir veritabanı adı veya ortam denetimi bulunmamaktaydı.
3. **`server/src/test/run_all_ac_tests.ts`**:
   - `testDbUrl.includes('localhost')` kontrolü, yerel makinedeki geliştirme veritabanı olan `nutopiano` bağlantısını güvenli test veritabanı sanarak kabul etmekteydi.

---

## 3. GÖREV 2 — UYGULANAN FAIL-CLOSED KORUMA MİMARİSİ

Mevcut mimariyi bozmadan, en küçük ve en etkili güvenlik değişikliği uygulanmıştır:

### 3.1. Yeni Modül: `server/src/config/test-db-guard.ts`
- **Kara Liste (Blacklist):** `nutopiano`, `production`, `prod_db`, `prod`, `live`, `customer`, `primary`, `serenut_db`, `serenut_dev`, `shaman`, `supabase`, `rds.amazonaws.com`, `serenut.com`.
- **Beyaz Liste Deseni (Regex):** `^(serenut_test|serenut_[a-z0-9_-]+_test|[a-z0-9_-]+_test|test_[a-z0-9_-]+)$` (Büyük/küçük harf duyarsız).
- **Fonksiyonlar:**
  1. `validateTestDatabaseUrl(url)`: URL formatı, protokolü (`postgres:` / `postgresql:`), veritabanı adı, kara liste ve test regex kontrollerini statik (bağlantısız) olarak yapar.
  2. `assertSafeTestEnvironment(options)`: `NODE_ENV === 'test'` zorunluluğunu ve `DATABASE_URL !== TEST_DATABASE_URL` (geliştirme DB çakışması) kontrolünü yürütür.
  3. `assertIsolatedTestDatabase(client, expectedDbName)`: İstemciden `SELECT current_database() AS db_name` çalıştırır; dönen fiziksel veritabanı adının kara listede olmadığını ve test deseniyle eşleştiğini doğrular.

### 3.2. Yıkıcı Test Kalkanı: `sync_v4_domain_materialization.test.ts`
Testin başlangıcına aşağıdaki kalkan eklenmiştir:
```typescript
const setupClient = await pgPool.connect();
try {
  // FAIL-CLOSED GÜVENLİK BARİYERİ: Hedef veritabanının onaylı bir test DB olduğu kanıtlanmadan şema silinemez!
  await assertIsolatedTestDatabase(setupClient);
  await setupClient.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO public;');
} finally {
  setupClient.release();
}
```

### 3.3. Test Runner Kalkanı: `run_all_ac_tests.ts`
Eski `testDbUrl.includes('localhost')` açığı kaldırılarak `assertSafeTestEnvironment` entegre edilmiştir.

---

## 4. GÖREV 3 — GÜVENLİK BİRİM TESTLERİ VE ADLİ KANITLAR

Yeni yazılan `server/src/test/test_db_guard.test.ts` süiti sıfır ağ bağlantısıyla ve sahte istemcilerle çalıştırılmıştır.

### 4.1. Senaryo Sonuçları
- **Senaryo 1 (NODE_ENV Eksik/Dev):** `NODE_ENV=development` ile çağrıldığında anında `FATAL_TEST_DB_GUARD: NODE_ENV değeri kesinlikle 'test' olmalıdır` fırlattı. (BAŞARILI)
- **Senaryo 2 (DATABASE_URL Boş/Tanımsız):** `DATABASE_URL_EMPTY` hatası ile reddedildi. (BAŞARILI)
- **Senaryo 3 (Kara Liste Denetimi):** `nutopiano`, `production`, `prod_db`, `supabase`, `rds.amazonaws.com` içeren URL'ler `FORBIDDEN_DATABASE_IDENTIFIER` hatasıyla engellendi. (BAŞARILI)
- **Senaryo 4 (Test Deseni Olmayan Adlar):** `my_pos`, `serenut`, `orders`, `sales_db`, `billing_app` adları `DATABASE_NAME_NOT_TEST` ile reddedildi. (BAŞARILI)
- **Senaryo 5 (Localhost Açığı Kapatıldı):** `postgres://localhost:5432/nutopiano` bağlantısı localhost üzerinde dahi olsa derhal reddedildi. (BAŞARILI)
- **Senaryo 6 (Geçerli Test Adları):** `serenut_test`, `serenut_ci_test`, `order_module_test`, `test_integration` onaylandı. (BAŞARILI)
- **Senaryo 7 (Fiziksel SQL current_database Kontrolü):**
  - İstemci `nutopiano` döndüğünde fail-closed devreye girdi. (BAŞARILI)
  - İstemci beklenen isim yerine başka bir test adı döndüğünde isim uyuşmazlığı tespit edilerek durduruldu. (BAŞARILI)
  - Doğru test adı onaylandı. (BAŞARILI)
- **Senaryo 8 (Ortam Çelişkisi):** Çakışan geliştirme URL'leri fail-closed ile durduruldu. (BAŞARILI)

**Birim Testi Çıktısı:**
```
====================================================
🛡️  TEST-DB-GUARD FAIL-CLOSED BİRİM TESTLERİ BAŞLIYOR
====================================================
...
====================================================
🎉 TÜM TESTLER TAMAMLANDI: 43/43 BAŞARILI
====================================================
```

### 4.2. Canlı Yıkıcı Test Kalkanı Kanıtı
`npx ts-node src/test/sync_v4_domain_materialization.test.ts` komutu doğrudan çalıştırıldığında alınan gerçek çıktı:
```
❌ Sync V4 domain materialization test failed Error: FATAL_TEST_DB_GUARD: NODE_ENV değeri kesinlikle 'test' olmalıdır (Mevcut: 'development'). Geliştirme ortamında test çalıştırılamaz.
    at assertSafeTestEnvironment (test-db-guard.ts:98:11)
    at assertIsolatedTestDatabase (test-db-guard.ts:135:20)
    at run (sync_v4_domain_materialization.test.ts:10:37)
```
**Kanıt:** Test 10. satırda güvenli şekilde durdurulmuş, `DROP SCHEMA` komutuna **kesinlikle ulaşamamıştır**.

---

## 5. DOSYA VE DİZİN DEĞİŞİKLİKLERİ

- **Eklenen Dosyalar:**
  - `server/src/config/test-db-guard.ts` (Fail-closed koruma çekirdeği)
  - `server/src/test/test_db_guard.test.ts` (43 assertion içeren güvenlik birim testi)
  - `CORE_NEXT_STAGE10_7_4_1_POSTGRES_FAIL_CLOSED_REPORT.md` (Bu rapor)
- **Güncellenen Dosyalar:**
  - `server/src/test/sync_v4_domain_materialization.test.ts` (`assertIsolatedTestDatabase` guard eklendi)
  - `server/src/test/run_all_ac_tests.ts` (`assertSafeTestEnvironment` guard eklendi)
- **`lib/` Klasörü:** **%100 EL DEĞMEMİŞ (0 satır değişiklik)**.
- **Git Durumu:** Hiçbir `git commit`, `git push` veya `git add` çalıştırılmamıştır.

---

## 6. MEVCUT DURUM VE SONRAKİ AŞAMA GEREKSİNİMLERİ

1. **İzole Test Veritabanı:**
   Sistemde henüz bağımsız bir `serenut_test` PostgreSQL veritabanı kurulmamıştır. Gerçek entegrasyon testlerinin koşabilmesi için:
   - Ayrı bir PostgreSQL kullanıcısı/rolü (`serenut_test_user`).
   - Ayrı bir izole test veritabanı (`serenut_test`).
   - Yalnızca bu test veritabanına yetkili bağlantı yapılandırılmalıdır.
2. **Canlıya Geçiş Durumu:**
   Canlı geçiş kapısı `LIVE_GATE: BLOCKED` olarak korunmaktadır.
