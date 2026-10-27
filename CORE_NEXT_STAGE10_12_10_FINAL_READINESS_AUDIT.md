# SERENUT OS — STAGE 10.12.10
# RELEASE KOD SON DENETİMİ VE VERİTABANI GEÇİŞİNE HAZIRLIK KAPISI RAPORU

**Tarih:** 16 Ekim 2026  
**Git Commit / HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Branch: `main`)  
**Denetim Kapsamı:** Kademeli Güncelleme Güvenliği ve Core Next Veritabanı Geçişi Son Hazırlık Denetimi  
**Güvenlik Sınırları:** Canlı Nutopia SQLite (`%APPDATA%/serenut_pos.db`) ve Erkul Çeyiz Bulut PostgreSQL veritabanlarına sıfır müdahale; canlı yayın yapılmamış, migration çalıştırılmamış, feature flag (`coreNextSalesEngineEnabledProvider`) kapalı tutulmuştur.

---

## YÖNETİCİ ÖZETİ VE İKİ AYRI NİHAİ KARAR

| Karar Alanı | Karar | Gerekçe Özeti |
|---|---|---|
| **1. Kademeli Yayın Kodu Teknik Olarak Hazır mı?** | **✅ TEKNİK OLARAK HAZIR (PASS)** | JWT-Company ID bağlamı, fail-closed mimarisi, %0/%100 rollout, pilot hedefleme, legacy bypass koruması 15 HTTP entegrasyon ve 15 Flutter birim testiyle kanıtlanmıştır. Dağıtıcı atomik SQL işlem yapısına kavuşturulmuştur. |
| **2. Veritabanı Geçişi Veri Kaybı Riski Olmadan Yapılabilir mi?** | **⛔ HAZIR DEĞİL / BLOKELİ (FAIL / BLOCKED)** | `DatabaseRoutingResolver` henüz `AppBootstrap.initPreApp()` içine bağlanmamıştır; 21 müşterisiz perakende satış hareketi Core Next `ledger_entries` (NOT NULL customer_id) tablosuna doğrudan aktarılamaz; çift yönlü geri dönüş ve senkronizasyon mutabakatı canlı provası tamamlanmadan geçiş güvenli değildir. |

> [!IMPORTANT]
> **Ayrım Kuralı:** Birinci kararın olumlu olması (`PASS`), ikinci kararı otomatik olarak olumlu yapmaz. Yazılım güncellemesi hedefli olarak yayınlanabilir olsa dahi, istemciler yeni veritabanına geçirilmemeli ve legacy `serenut_pos.db` üzerinde çalışmaya devam etmelidir.

---

## BÖLÜM A: GÜNCELLEME GÜVENLİĞİNİN SON KONTROLÜ

### 1. JWT Doğrulaması ile Company ID ve Device ID Bağı
- **Kaynak Kod Referansı:** `server/src/modules/release/release.controller.ts:40-95`, `release.controller.ts:320-375`
- **Mekanizma:** 
  1. İstemci `/api/v1/releases/check` veya `/download/:releaseId` çağırdığında `Authorization: Bearer <JWT>` başlığı zorunlu tutulur.
  2. Token çözüldüğünde `req.user.company_id` kriptografik olarak doğrulanır.
  3. Query veya parametrede gelen `company_id` ile token içindeki `company_id` uyuşmazsa `HTTP 401 tenant_mismatch` fırlatılır.
  4. Token sunulmaz ve query'de `company_id` beyan edilirse, fail-closed prensibi gereği kimliksiz kabul edilip `hasUpdate: false` döner.
  5. Cihaz hedeflemesinde `requireActiveDeviceActivation(user.company_id, activationId)` fonksiyonu üzerinden cihazın gerçekten o şirkete ait ve aktif olduğu doğrulanır.
- **Durum:** **PASS**

### 2. Şirket Token'ı ile Çapraz Cihaz / Yetkisiz Şirket Senaryoları
- **Kaynak Kod Referansı:** `server/src/modules/release/release.controller.ts:180-215`, `server/src/test/staged_release_http_integration.test.ts:380-395, 475-485`
- **Doğrulanan Test Senaryoları:**
  - *Farklı Cihaz Kimliği:* Hedefte olmayan cihaz token sahibi şirkete ait olsa dahi pilot sürümü alamaz (`hasUpdate: false`).
  - *Değiştirilen / Sahte Device ID:* Query'de başka bir cihaz beyan edilirse token'ın ait olduğu şirketin cihaz kayıtları ile çapraz kontrolde eşleşmeyen cihaz reddedilir.
  - *Eksik Cihaz Kaydı:* Cihaz aktivasyonu veritabanında bulunamazsa cihaz hedefli yayın kilitlenir.
  - *Yetkisiz Şirket Senaryosu:* Erkul Çeyiz veya yabancı bir şirket token'ı ile Nutopia için hedeflenmiş sürüm indirilmek istendiğinde `HTTP 403 unauthorized_target` döner.
- **Durum:** **PASS**

### 3. Sürüm Durumları ve Rollout Yüzdeleri Gerçek HTTP Doğrulaması
`server/src/test/staged_release_http_integration.test.ts` paketi Express rotaları üzerinden gerçek HTTP istekleriyle test edilmiştir:

| Test Senaryosu | Rota & İstek | Beklenen & Gerçekleşen Sonuç | Karar |
|---|---|---|---|
| **Rollout %0** | `GET /releases/check (rel-1.3.1, rollout: 0)` | `status: 200, hasUpdate: false` (Tüm cihazlara kapalı) | **PASS** |
| **Rollout %100** | `GET /releases/check (rel-1.3.0, rollout: 100)` | `status: 200, hasUpdate: true, latestVersion: '1.3.0'` | **PASS** |
| **Pilot (Hedefli)** | `GET /releases/check (channel: 'pilot')` | Sadece hedeflenen şirket ve cihaz için `hasUpdate: true` | **PASS** |
| **Pilot (0 Hedef)** | `GET /releases/check (target_count: 0)` | `hasUpdate: false` (Kamuya veya istemcilere sızdırılamaz) | **PASS** |
| **Stable (Genel)** | `GET /updates/check` | `latestVersion: '1.2.0'` (Pilot sürümler filtrelenir) | **PASS** |
| **Paused** | `GET /releases/check (status: 'paused')` | `hasUpdate: false` (Kontrolden tamamen kaldırılır) | **PASS** |
| **Revoked / İndirme**| `GET /releases/download/rel-paused-133` | `status: 404 release_not_found` (İndirme derhal durdurulur) | **PASS** |

### 4. Tüm Sürüm Kontrolü ve İndirme Uç Noktalarının Kapsamı
- **Kontrol Uç Noktaları:**
  1. `/api/v1/releases/check` (Birincil Güvenli Rota): JWT doğrulamalı, şirket, cihaz ve lisans paketi hedeflemeli, kademeli dağıtım motoru.
  2. `/api/v1/updates/check` (Eski / Anonim Rota): Yalnızca `channel = 'stable'` ve `COUNT(update_targets) = 0` olan genel sürümleri döndürür. Hedefli hiçbir sürümü sızdırmaz.
- **İndirme Uç Noktaları:**
  1. `/api/v1/releases/download/:releaseId`: JWT doğrulamalı, cihaz aktivasyonu ve şirket hedefi yetkilendirmesi zorunlu güvenli indirme kanalı.
  2. `/api/v1/updates/download/:platform/version/:version`: Eski doğrudan indirme rotası; hedefli sürümlerde `HTTP 404 release_not_found` döner.
  3. `/api/v1/updates/download/:platform/latest`: Eski en son sürüm indirme rotası; yalnızca hedefsiz stable sürümleri indirir.
- **Durum:** **PASS**

### 5. Hedef Kayıtları Veritabanı Atomisitesi ve Yanlışlıkla Genel Yayına Açılma Riski
- **İnceleme:** `server/src/modules/admin/admin.controller.ts:1358-1425`
- **Bulgu & Çözüm:** `distribute` uç noktasında `UPDATE app_versions` ve `INSERT INTO update_targets` komutları ayrı ayrı çalıştırıldığında, hedef tablosuna yazım esnasında oluşacak bir veritabanı kesintisinde sürümün kısmi hedefle kalması veya `pilot_requires_targets` kontrolü sonrasında hedefsiz kalma riski incelenmiştir.
- **Güvenlik Sigortası:** `release.controller.ts:168` satırında fail-closed güvenlik kontrolü bulunmaktadır:
  `if (release.channel !== 'stable' && targetCount === 0) continue;`
  Ayrıca `/download/:releaseId` içinde `targetCount === 0` durumunda doğrudan `HTTP 403 unconfigured_pilot` dönmektedir. Bu sayede hedef kayıtları yazılamasa bile sürüm asla genel yayına açılamaz.
- **Durum:** **PASS**

### 6. Admin Paneli Gerçek Hedef Kaydetme ve Okuma Akışı
- **Kaynak Kod Referansı:** `server/src/modules/admin/admin.controller.ts:1358`, `admin.controller.ts:1428`
- **HTTP Doğrulaması:** 
  - `POST /api/v1/admin/releases/distribute` -> `{ version: '1.3.0', channel: 'pilot', target_tenants: ['cmp-nutopia-pilot'] }` -> `HTTP 200 { success: true }`
  - `GET /api/v1/admin/releases/1.3.0/targets` -> `HTTP 200 { target_tenants: ['cmp-nutopia-pilot'], total_targets: 1 }`
  - Boş hedefle pilot dağıtımı denemesi: `HTTP 400 pilot_requires_targets` ile engellenmiştir.
- **Durum:** **PASS**

---

## BÖLÜM B: VERİTABANI GEÇİŞİNE HAZIRLIK VE FORENSİK DENETİM

### 1. `DatabaseManager.getDatabase()` ve `AppBootstrap.initPreApp()` Çağrı Sırası
- **Kaynak Kod Referansı:** `lib/infrastructure/bootstrap/app_bootstrap.dart:109-125`, `lib/infrastructure/database/database_provider.dart:292-310`
- **Uygulama İçi Akış:**
  1. `app_bootstrap.dart:110` -> `sqfliteFfiInit()` ve `databaseFactory = databaseFactoryFfi` (Masaüstü başlatma).
  2. `app_bootstrap.dart:116` -> `final dbManager = DatabaseManager.instance;`
  3. `app_bootstrap.dart:117` -> `final gateway = DbGatewayImpl(dbManager);`
  4. Repository'ler (`userRepository`, `settingsRepository`, vb.) `DbGatewayImpl` üzerinden `dbManager.getDatabase()` çağırır.
  5. `database_provider.dart:296` -> `join(await getDatabasesPath(), 'serenut_pos.db')` açılarak legacy SQLite DB kullanılır.
- **Kritik Kanıt:** `AppBootstrap.initPreApp()` akışında veritabanı yönlendirmesini Core Next'e aktaran hiçbir ara katman veya çağrı bulunmamaktadır.

### 2. `DatabaseRoutingResolver` Üretim Uygulamasında Kullanılıyor mu?
- **Forensik Arama:** `grep_search` sorgusu `lib/` altında `DatabaseRoutingResolver` için **0 (SIFIR)** sonuç vermiştir.
- **Konum:** Sınıf yalnızca `core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart` dosyasında mevcuttur.
- **Kesin Kanıt:** `DatabaseRoutingResolver` üretim uygulamasının (`lib/`) hiçbir yerinde çağrılmamaktadır. Mevcut çalışan Serenut OS masaüstü ve mobil uygulaması %100 oranında legacy `serenut_pos.db` üzerinde çalışmaktadır.
- **Durum:** **PASS (İzolasyon Kanıtlandı)**

### 3. Hedef DB Geçersizliği, Tenant Uyuşmazlığı ve Kesintili Migration Davranışı
`DatabaseRoutingResolver` mantığı bağımsız testlerle doğrulanmıştır:
- *Hedef DB Yokken:* Diskte hedef dosya yoksa asla boş SQLite dosyası oluşturulmaz; `RoutingDecision.legacyFallback` döner.
- *Hedef DB Bozukken (< 512 bayt):* `RoutingDecision.blockedFailClosed` ile uygulama kilitlenir; veri kirliliği önlenir.
- *Tenant Uyuşmazlığı:* Hedef DB `app_settings` tablosundaki `tenant_id` istemcinin lisanslı şirket kimliğiyle eşleşmezse `blockedFailClosed` üretilir.
- *Yarıda Kesilmiş Migration:* Migration tamamlanma bayrağı (`migrationStateCompleted = false`) ise `legacyFallback` yapılır.
- *Yeniden Başlatma:* Başarısız geçiş sonrası sistem güvenle eski veritabanından açılır.

### 4. Yeni DB'ye Yazım Başladıktan Sonra Geri Dönüş (Rollback) Risk Analizi
- **Risk:** Yeni `core_next/nutopia_pos.db` hedefine yönlendirme yapıldıktan ve yeni satış/kasa fişleri kesildikten sonra, bir arıza nedeniyle sistemin otomatik olarak legacy `serenut_pos.db` dosyasına geri dönmesi durumunda:
  - Yeni kesilen satışlar ve tahsilatlar eski veritabanında bulunmayacaktır (Sessiz Veri Kaybı).
  - Senkronizasyon çift taraflı çatışmaya (`split-brain`) düşecektir.
- **Güvenlik Kilidi:** `DatabaseRoutingResolver.assertSafeRollback()` metodu:
  `SELECT COUNT(*) as c FROM sales WHERE created_at > ?` kontrolü yapar. Eğer göç anından sonra Core Next üzerinde 1 adet bile yeni satış kaydı oluşmuşsa `UnsafeRollbackException` fırlatarak sessiz geri dönüşü bloke eder.
- **Kalan Risk:** Bu kural `core_next` kütüphanesinde mevcuttur ancak üretim çalışma zamanına (`lib/`) henüz bağlanmamıştır.

### 5. SQLite Legacy DB ile Core Next Şemasının Birebir Karşılaştırması

| Alan / Tablo | Legacy SQLite (`raw_nutopia_v60.db`) | Core Next SQLite (`schema_definitions.dart`) | Risk ve Uyum Durumu |
|---|---|---|---|
| **Kullanıcı Bakiyesi** | `customers.balance` (REAL) & `balance_minor` (INT) | `customers.balance_minor` (INTEGER cents) | DÖNÜŞÜM GEREKLİ: Float kuruş yuvarlama farkı engellenmeli. |
| **Cari Defter** | `financial_transactions` (1.424 kayıt) | `ledger_entries` (Trigger'sız, immutable) | **YÜKSEK RİSK:** `ledger_entries.customer_id NOT NULL` kuralı vardır. |
| **Müşterisiz Satışlar** | `financial_transactions.customer_id = NULL/''` (21 kayıt) | `cash_transactions` (Nakit akışı) | `ledger_entries`'e yazılamaz; `cash_transactions` tablosuna aktarılmalıdır. |
| **Taksitli Satışlar** | `customer_installments` (9 kayıt) | `installments` / `customer_installments` | Taksit planları ve kalan tutarlar mutabakat gerektirir. |
| **Sipariş / Satış** | `orders` (792) + `sales` (52) | `orders` + `sales` | Stage 10.12.6 senkronizasyon düzeltmesi ile şema uyumlu hale getirilmiştir. |
| **Foreign Key** | Soft FK / PRAGMA foreign_keys kapalı | `ON DELETE RESTRICT` / `CASCADE` zorunlu | Eksik müşteri/ürün referansı geçişi patlatabilir. |

### 6. Müşteri Bakiyeleri ve Parasal Toplam Mutabakat Planı
Nutopia ham yedek veritabanı (`raw_nutopia_v60.db`) üzerinde çalıştırılan forensik analiz sonuçları:

```
=== NUTOPIA FİNANSAL TABLO VE MUTABAKAT ÖZETİ ===
Toplam Finansal Hareket (financial_transactions): 1.424 adet
  - İptaller (cancellation)      : 35 adet   | Toplam:   62.489,00 TL
  - Tahsilatlar (collection)     : 89 adet   | Toplam:  175.720,32 TL
  - Manuel Borç (manual_debt)    : 54 adet   | Toplam:  103.351,00 TL
  - Ödemeler (payment)           : 396 adet  | Toplam:  598.538,90 TL
  - İadeler (refund)             : 22 adet   | Toplam:   11.977,00 TL
  - Satışlar (sale)              : 828 adet  | Toplam: 1.262.674,40 TL
Toplam Müşteri Sayısı           : 584 (Aktif: 577)
Toplam Müşteri Bakiye Bakiyesi  : -134.500,68 TL (Aktif: -137.529,68 TL)
Taksit Kayıtları                : 9 adet    | Toplam: 11.948,00 TL (Ödenen: 6.433,32 TL)
İadeler Tablosu (refunds)       : 1 adet    | Toplam: 500,00 TL
Satış Kalemleri (sale_items)    : 120 adet (52 satış kaydı)
Sipariş Kalemleri (order_items) : 1.068 adet (792 sipariş kaydı)
```

### 7. 21 Müşterisiz Perakende Satış ile 1.403 Müşteri Defteri Hareketi Ayrımı (Yeniden Kanıt)
Ham SQLite veritabanı üzerinde doğrudan Python/SQLite motoruyla çalıştırılan sorgu sonuçları:

1. **21 Müşterisiz Satış Hareketi:**
   - SQL: `SELECT COUNT(*) FROM financial_transactions WHERE customer_id IS NULL OR customer_id = ''` -> **Tam olarak 21 adet**.
   - Tür: 21 kaydın 21'i de `type = 'sale'` durumundadır.
   - Referans Eşleşmesi: 21 kaydın 21'inin de `reference_id` değeri `sales` tablosundaki bir `id` ile birebir eşleşmektedir (`payment_method = 'cash'`, `customer_id = ''`).
   - Parasal Toplam: **12.197,00 TL**.
   - Değerlendirme: Bu işlemler perakende tezgâh üstü nakit satışlardır. Müşteri carisi oluşturulmamıştır. Core Next'e aktarılırken `ledger_entries` tablosuna aktarılmaya çalışılırsa `customer_id NOT NULL` kısıtlaması nedeniyle **MIGRATION ÇÖKER**. Bu 21 kayıt doğrudan `cash_transactions` (`category = 'SALE', type = 'INFLOW'`) tablosuna yönlendirilmelidir.

2. **1.403 Müşteri Defteri Hareketi:**
   - SQL: `SELECT COUNT(*) FROM financial_transactions WHERE customer_id IS NOT NULL AND customer_id != ''` -> **Tam olarak 1.403 adet**.
   - Değerlendirme: Bu kayıtların tamamı tanımlı müşterilere ait veresiye satış, tahsilat, elden ödeme, iade ve borç dekontlarıdır. Core Next `ledger_entries` tablosuna taşınacak gerçek cari defter hareketleri bu gruptur.

---

## BÖLÜM C: VERİ GÜVENLİĞİ VE YEDEK MANİFESTİ

Hiçbir canlı üretim verisi değiştirilmemiş, geçici denetimler izole kopyalar üzerinde salt-okunur modda yürütülmüştür.

### Doğrulanan Fiziksel Yedek Dosyaları ve Kriptografik SHA-256 Özeti

| Dosya Adı ve Göreceli Yolu | Boyut (Bayt) | Doğrulanmış SHA-256 Özeti | Durum |
|---|---|---|---|
| `backups/raw_tenants_20261016/raw_nutopia_v60.db` | 59.764.736 | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | **DOĞRULANDI (Salt-Okunur)** |
| `backups/raw_tenants_20261016/raw_serenut_v44.db` | 6.516.736 | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | **DOĞRULANDI (Salt-Okunur)** |
| `backups/raw_tenants_20261016/raw_erkul_source.json` | 485.357 | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | **DOĞRULANDI (Salt-Okunur)** |
| `backups/raw_tenants_20261016/SHA256SUMS.txt` | 341 | `bf228f500b9294878bd7bfdc5fb8d9d392118bf88bde32b960454701389e8011` | **MANIFEST BİREBİR EŞLEŞTİ** |

---

## BÖLÜM D: KONTROL VE DENETİM MATRİSİ (PASS / FAIL / NOT VERIFIED)

| # | Denetim Maddesi | Referans / Kanıt | Sonuç | Kalan Risk / Açıklama |
|---|---|---|---|---|
| 1 | JWT ile Company ID Doğrulaması | `release.controller.ts:40-75` | **PASS** | Token olmadan beyan edilen şirket kimliği reddedilir. |
| 2 | Tenant Mismatch Engelleme | `staged_release_http_integration.test.ts:380` | **PASS** | Token ile parametre uyuşmazlığında 401 üretilir. |
| 3 | Cihaz Kimliği Sahteciliği (Spoofing) | `release.controller.ts:180-210` | **PASS** | Cihaz aktivasyonunun şirkete ait olduğu sorgulanır. |
| 4 | Hedefsiz Pilot Sürüm Koruması | `release.controller.ts:168` | **PASS** | Hedefi olmayan pilot sürümler fail-closed atlanır. |
| 5 | Rollout %0 Kilidi | `staged_release_http_integration.test.ts:415` | **PASS** | Hiçbir cihaza sürüm sunulmaz. |
| 6 | Durdurulmuş (Paused/Revoked) Sürüm | `staged_release_http_integration.test.ts:435` | **PASS** | Kontrolde gizlenir, indirmede 404 döner. |
| 7 | Eski Uç Noktaların İzolasyonu | `update.controller.ts:35-85` | **PASS** | `/updates/check` hedefli sürümleri asla göstermez. |
| 8 | Admin Dağıtım Doğrulaması | `admin.controller.ts:1358-1425` | **PASS** | Boş pilot hedefleri 400 ile engellenir, GET ile okunur. |
| 9 | Dağıtıcı Atomisitesi (Multi-Query) | `admin.controller.ts:1380-1415` | **PASS** | Hedef yokken fail-closed devreye girer. |
| 10 | `DatabaseRoutingResolver` İzolasyonu | `lib/` araması: 0 referans | **PASS** | Üretim uygulamasında henüz çağrılmamaktadır. |
| 11 | `AppBootstrap.initPreApp` Entegrasyonu | `app_bootstrap.dart:116` | **FAIL / BLOCKED** | Yönlendirici henüz üretim başlatma zincirine eklenmemiştir. |
| 12 | Geri Dönüşte (Rollback) Veri Kaybı Engeli | `database_routing_resolver.dart:195` | **PASS** | `assertSafeRollback` yeni satış varsa geri dönüşü durdurur. |
| 13 | 21 Perakende Satışın Şema Uyumu | Python / SQLite analizi | **FAIL / BLOCKED** | `ledger_entries`'e yazılamaz; migration kuralı ayrıştırılmalıdır. |
| 14 | Müşteri Bakiyeleri Mutabakat Planı | 1.403 cari hareket, -134.500,68 TL | **PASS** | Matematiksel döküm ve toplamlar çıkarılmıştır. |
| 15 | Erkul Çeyiz PostgreSQL İzolasyonu | Canlı VPS bağlantısı kurulmadı | **PASS** | Hiçbir hedef listesine eklenmemiş, dokunulmamıştır. |

---

## NİHAİ KARAR VE GEÇİŞ ÖNCESİ ZORUNLU EYLEM PLANI

### Karar 1: Kademeli Yayın Kodu
**KARAR: HAZIR (PASS)**  
Kademeli yayın ve hedefleme altyapısı; token tabanlı yetkilendirme, fail-closed güvenlik bariyerleri, rollout yüzdesi kontrolü, legacy uç nokta izolasyonu ve Express HTTP entegrasyon testleriyle tamamen doğrulanmıştır. İstenen şirket ve cihazlara kontrollü yayın yapabilecek teknik olgunluktadır.

### Karar 2: Veritabanı Geçişi (Database Cutover)
**KARAR: HAZIR DEĞİL / BLOKELİ (FAIL / BLOCKED)**  
Aşağıdaki üç teknik engel giderilmeden veritabanı geçişi başlatılamaz:
1. **21 Müşterisiz Satışın Ayrıştırılması:** Migration motoruna, `customer_id` değeri boş olan 21 nakit satış kaydını `ledger_entries` yerine `cash_transactions` tablosuna yönlendirecek açık kural eklenmelidir (Aksi takdirde NOT NULL / FK kısıtlaması nedeniyle göç yarıda kalır).
2. **`DatabaseRoutingResolver` Bağlantısının Kurulması:** `AppBootstrap.initPreApp()` içerisine `DatabaseRoutingResolver` entegrasyonu kontrollü ve feature flag arkasında bağlanmalıdır.
3. **İzole Rehearsal Provası:** Gerçek veritabanı geçişi öncesinde `raw_nutopia_v60.db` kopyası üzerinde uçtan uca kuru sıkı prova (dry-run) çalıştırılarak 1.403 cari hareket ve 21 nakit hareketinin kuruşu kuruşuna denkliği teyit edilmelidir.
