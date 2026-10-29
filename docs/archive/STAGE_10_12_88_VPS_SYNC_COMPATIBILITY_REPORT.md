# SERENUT OS — STAGE 10.12.88: VPS SYNC V4 UYUMLULUK VE İZOLE TEST RAPORU

**Tarih:** 2026-10-21  
**Aşama:** Stage 10.12.88  
**Durum:** İnceleme ve Adli Denetim Tamamlandı  
**Nihai Karar:** **BLOCKED** *(Canlı VPS ve Canlı Tenant Senkronizasyonu İçin)* / **STAGING_TEST_READY** *(Adaptör Düzeltmesi Sonrası İzole Staging Koşuluna Bağlı)*

---

## 1. YÖNETİCİ ÖZETİ VE KORUMA DOĞRULAMASI

Stage 10.12.87 sonrasında üretilen v1.3.143 Release EXE'sinin ardından, Core Next istemci mimarisi ile Serenut VPS Sync V4 / Protocol 6 sunucu altyapısı salt-okunur (read-only) adli denetimle karşılaştırılmıştır.

### 🛡️ Kesin Koruma Sınırları Doğrulaması
1. **Canlı Veritabanı Bütünlüğü:**
   - `%APPDATA%\...\serenut_pos.db`: `cad5c91ff970b84ebf8270af8cce58f72dcf6b4bda4b4dd48a74f675c17234f3` (DEĞİŞMEDİ — %100 KORUNDU)
   - `%APPDATA%\...\serenut_core_v2.db`: `854611f801684d20004d9880ef8ed408630069646b4d473722a84a13e3024a59` (DEĞİŞMEDİ — %100 KORUNDU)
2. **Canlı VPS & Tenant Koruma:**
   - Nutopia (`comp-1785241628448-c7f5677d`), Erkul Çeyiz ve canlı VPS tenant'larına hiçbir veri yazılmamıştır.
   - Canlı `https://serenut.com` API'sine hiçbir test satışı, borç veya stok mutasyonu iletilmemiştir.
   - Hiçbir git reset/clean/commit/push işlemi yapılmamıştır.

---

## 2. İŞ 1: İSTEMCİ VE SUNUCU KOD KARŞILAŞTIRMASI

### A. Uyumlu ve Uyumsuz Veri Modelleri

| Varlık (Entity) | İstemci (Core Next) Modeli | Sunucu Sync V4 / Protocol 6 Beklentisi | Durum | Risk & Detay |
| :--- | :--- | :--- | :--- | :--- |
| **Satış (sale)** | `SyncV4PayloadAdapter.buildSaleMutation` | `upsertSale` (`sales`, `sale_items`, `inventory_movements`) | **TAM UYUMLU** | Küçük harf `sale`, Lira dönüşümü (`toLira`), tolerans kontrolü (`|total - expected| <= 0.05`), parçalı ödemeler (`cash`, `card`, `veresiye`, `mixed`) tam eşleşmektedir. |
| **Ürün (product)** | `CoreNextProductRepository` (`sync_events`) | `applyDomainMutation` (`products`) | 🔴 **KRİTİK UYUMSUZLUK** | İstemci repo payload'a `price_cents`, `cost_price_cents`, `stock_quantity` yazmaktadır. Sunucu ise `price`, `purchase_price`, `quantity` beklemektedir. Push edilirse sunucu ürünü **0.00 TL** fiyat ve **0** stok ile günceller! |
| **Müşteri (customer)** | `CoreNextCustomerRepository` (`sync_events`) | `applyDomainMutation` (`customers`) | ⚠️ **KISMİ UYUMSUZLUK** | İstemci `notes: entity.address` yazarken sunucu `address` beklemektedir. İstemci `balance_cents` gönderse de sunucu balance'ı doğrudan güncellemez (trigger'a bırakır, doğru davranış). |
| **Finansal İşlem (financial_transaction)** | `CoreNextFinancialTransactionRepository` | `upsertFinancialTransaction` (`financial_transactions`) | 🔴 **KRİTİK UYUMSUZLUK** | İstemci `DEBIT` işlemlerini `type = 'debt'` olarak maplemektedir. Sunucu ise yalnızca `['sale','payment','collection','manual_debt','cancellation','refund']` kabul eder. Sunucu `invalid_financial_transaction` fırlatarak işlemi reddeder. |
| **Taksit & Senet (installments)** | `SqliteInstallmentRepository` (`customer_installments`) | `customer_installment_plans` (`schema_v97.sql`) | ℹ️ **MİMARİ AYRIŞMA** | Taksit planları Sync V4 `entityTypes` kümesinde yer almaz. İstemci taksiti `manual_debt` ve `collection` finansal işlemleri olarak sunucuya yansıtır; taksit vadeleri yerel SQLite'ta saklanır. |
| **İade (refund)** | `CoreRefundUseCase` / `RefundService` | `RefundService.create` | ⚠️ **KURAL KISITI** | İade mutasyonları sunucuda mutlaka `actorId` gerektirir (`refund_actor_required`). İstemci adapter'ı doğrudan `refund` mutasyonu göndermeyi bu nedenle engellemiştir. |

---

### B. SQLite vs PostgreSQL Dönüşümlerinde Olası Kayıp Noktaları

1. **Kuruş (Integer Cents) vs Ondalık (Decimal TL):**
   - Core Next SQLite'ta finansal ve stok verileri integer cents (`MoneyCents`, `price_cents`, `total_cents`) olarak tutulur.
   - VPS PostgreSQL tablolarında `NUMERIC(12, 2)` ve `FLOAT` kullanılır.
   - `SyncV4PayloadAdapter` satış ve finansal işlemlerde kuruşu `toStringAsFixed(2)` ile IEEE 754 kayan nokta sapmalarından arındırarak Lira'ya çevirmektedir.
   - **Kayıp Riski:** `CoreNextProductRepository` ve `CoreNextCustomerRepository` bu adaptörden geçirilmediği için doğrudan kuruş anahtarlarını göndermekte, bu da sunucuda alanların `0` düşmesine neden olmaktadır.
2. **Müşteri Bakiyeleri:**
   - PostgreSQL tarafında `customers.balance`, `trg_recalculate_customer_balance` trigger'ı aracılığıyla `SUM(debt_amount) - SUM(paid_amount)` formülüyle hesaplanır.
   - İstemci tarafında `_ingestCustomer` hem `balance` hem `balance_cents` okuyabilir ve bekleyen yerel hareketleri (`unreflectedDeltaCents`) ekler.
   - **Kayıp Riski Yok**, ancak finansal işlem tipi `manual_debt` yerine `debt` gönderilirse sunucu reddedeceği için bakiye senkronize olamaz.
3. **Karma ve Parçalı Ödemeler:**
   - Nakit + Kart veya Nakit + Veresiye durumunda `payment_method: 'mixed'` atanmaktadır.
   - Sunucu `mixed` yönteminde peşin ödenen tutarı (`paid_amount`) ve borcu kabul eder.
4. **Taksit Planları ve Negatif Kayıtlar:**
   - Sunucu `upsertFinancialTransaction` fonksiyonu negatif tutarları kesinlikle yasaklar:
     `amount < 0 || paidAmount < 0 || debtAmount < 0 => throw invalid_financial_transaction`.
   - Negatif bakiye düzeltmeleri veya negatif taksitler sunucuya push edilirse işlem anında reddedilir.
5. **Yeniden Gönderim (Idempotency) ve Nedensel Sıralama:**
   - Sunucu, `sync_v4_changes(tenant_id, mutation_id)` üzerinde idempotenttir. Aynı mutasyon tekrar gelirse önceki revizyon döndürülür.
   - Causal ordering: Satış (`causalSequence: 1`) her zaman ilişkili cari borçtan (`causalSequence: 2`) önce sunucuya ulaşacak şekilde outbox'ta gruplanmıştır.

---

### C. Çift Veritabanı (Dual-DB) Senkronizasyon Tutarlılığı

Stage 10.12.87 desktop testinde görüldüğü üzere:
- `Product`, `Customer` ve `FinancialTransaction` depoları `CoreNext` (`serenut_core_v2.db`) üzerinden çalışmaktadır.
- `Sale` deposu ise `SqliteSaleRepository` (`serenut_pos.db`) üzerinden çalışmaktadır.

🚨 **Split-Brain ve Veri Ayrışması Riski:**
- Eğer bu hibrit yapı ile senkronizasyon açılırsa:
  - Satışlar `serenut_pos.db`'ye kaydedilip oradaki `sync_outbox_v4` kuyruğuna yazılır. Stoklar sadece eski DB'de düşer.
  - UI'da gösterilen `serenut_core_v2.db` stokları satıştan etkilenmez.
  - İki farklı DB'de iki bağımsız outbox kuyruğu (`sync_outbox_v4` ve `sync_events`) oluşur.
  - Sunucuya iki farklı istemci gibi bağımsız event akışı gider ve cursor'lar ayrışır.
- **Zorunlu Çözüm:** Senkronizasyon açılmadan önce satış motoru da tamamen Core Next'e (`CoreNextSaleRepository` ve `CoreCheckoutUseCase`) bağlanmalı, tek bir veritabanı (`serenut_core_v2.db`) authoritative olmalıdır.

---

## 3. İŞ 2: İZOLE TEST ORTAMININ BELİRLENMESİ

### A. VPS Üzerindeki Ortam Durumu
1. **Staging Alan Adı Kontrolü:**
   - `staging.serenut.com` ve `api.staging.serenut.com` DNS sorguları yapılmış, **"no such host"** (DNS kaydı yok) yanıtı alınmıştır.
2. **Canlı Sunucu Durumu:**
   - `https://serenut.com/health` sorgusu başarıyla dönmüştür (`status: healthy, db: up, redis: up, uptime: ~51 saat`).
   - Canlı veritabanı `serenut_db` üzerinde Nutopia ve Erkul Çeyiz gibi canlı tenant'lar bulunmaktadır.
3. **Mevcut Staging Altyapısı (Kod Seviyesi):**
   - Sunucu kodunda `server/scripts/deploy_staging.sh`, `server/ecosystem.staging.config.js` ve `server/nginx.staging.conf` mevcuttur.
   - Staging ortamı `PORT: 3001` ve `DATABASE_URL: serenut_db_staging` olarak tasarlanmıştır.
   - Ancak canlı VPS'te bu port dış dünyaya açık değildir ve staging tenant'ı canlıda tanımlı değildir.

### B. Staging Kurulumunun Teknik Gereksinimleri
Canlı veriye yazmadan uçtan uca senkronizasyon testi yapabilmek için:
1. VPS üzerinde `deploy_staging.sh` çalıştırılarak ayrı `serenut_db_staging` veritabanı ve `serenut-backend-staging` PM2 servisi devreye alınmalıdır.
2. Staging veritabanında sentetik bir test şirketi oluşturulmalıdır:
   - Tenant ID: `comp-test-staging-sync`
   - Test Cihaz Aktivasyonu: `act-test-device-01`
   - Test Terminali: `dev-staging-terminal`
3. İstemci `SyncV4HttpClient` bu staging endpoint'ine (`http://185.255.93.94:3001/api/v4/sync` veya SSH tüneli / yerel mock) yönlendirilmelidir.
4. **KESİN KURAL:** Canlı Nutopia tenant'ı asla test veya staging amacıyla kullanılamaz.

---

## 4. İŞ 3: ÇALIŞTIRILAN DOĞRULAMALAR VE KANITLAR

Aşağıdaki izole birim ve protokol testleri çalıştırılmış, tümü başarıyla geçmiştir:

1. `test/core_next/sync_v4_outbox_adapter_test.dart` (11 Test — BAŞARILI):
   - DTO alanlarının Protocol 6 sözleşmesiyle uyumu.
   - Kuruş/Lira sınır değer dönüşümleri.
   - Nakit, kart, veresiye ve karma ödeme temsilleri.
   - Hata enjeksiyonunda atomik rollback ve determinizm.
2. `test/core_next/sync_v4_http_client_test.dart` (15 Test — BAŞARILI):
   - `x-sync-protocol-version: 6` başlık denetimi.
   - HTTP 426 (Upgrade Required), HTTP 401/403 yetkilendirme hataları.
   - Idempotent tekrar gönderimler ve kısmi ret (partial rejection) senaryoları.
3. `test/core_next/stage10_7_3_pull_worker_test.dart` (14 Test — BAŞARILI):
   - Tek ve çok sayfalı pull akışı (Pagination loop).
   - Çevrimdışı yerel mutasyonların korunması (LWW çakışma önleme).
   - Çok kasalı satış ve iadelerde stok idempotentliği.

---

## 5. BULGULAR, EKSİKLER VE RİSK MATRİSİ

| No | Tespit Edilen Eksik / Risk | Etki | Önleyici Eylem |
| :--- | :--- | :--- | :--- |
| **1** | `CoreNextProductRepository` payload'unda `price` yerine `price_cents`, `quantity` yerine `stock_quantity` bulunması. | **YÜKSEK (Veri Bozulması):** Sunucu fiyat ve stoğu 0 yapar. | `SyncV4PayloadAdapter.buildProductMutation` oluşturulmalı ve `sync_events`'e Lira/adet formatında yazılmalıdır. |
| **2** | Cari borç hareketinde `type: "debt"` gönderilmesi. | **YÜKSEK (Senkronizasyon Engeli):** Sunucu 400 ile reddeder. | Repo mapper'ında `debt` -> `manual_debt` dönüşümü yapılmalıdır. |
| **3** | Müşteri adresinin `notes` anahtarıyla enqueued edilmesi. | **ORTA:** Sunucuda adres alanı boş kalır. | `address` anahtarı eklenmelidir. |
| **4** | Hibrit Veritabanı Kullanımı (`serenut_pos.db` + `serenut_core_v2.db`). | **KRİTİK (Split-Brain):** Satış ve ürün verileri iki ayrı veritabanına bölünür. | Satış motoru da Core Next'e geçirilmeli ve tek DB otoritesi sağlanmalıdır. |
| **5** | VPS üzerinde aktif genel staging DNS/tenant bulunmaması. | **ORTA (Test Ortamı):** Canlı VPS'e güvenli izole test yapılamaz. | VPS'de izole `serenut_db_staging` açılmalı veya yerel mock harness kullanılmalıdır. |

---

## 6. NİHAİ KARAR VE SONRAKİ ADIMLAR

### 🛑 NİHAİ KARAR: **BLOCKED**
*Ürün/cari payload anahtarlarındaki uyumsuzluklar (fiyatın sıfırlanma riski) ve hibrit DB split-brain tehdidi nedeniyle canlı VPS ile istemci arasındaki gerçek veri senkronizasyonu bu aşamada **BLOKE EDİLMİŞTİR**.*

### 📋 Güvenle Atılacak Sonraki Adımlar:
1. **Adaptör Düzeltmesi (Kod Seviyesi):**
   - `SyncV4PayloadAdapter` içine `buildProductMutation` ve `buildCustomerMutation` eklenerek `price`, `quantity`, `address` gibi alanların Protocol 6 formatına dönüştürülmesi.
   - `core_next_financial_transaction_repository.dart` içindeki `type = 'debt'` ifadesinin `type = 'manual_debt'` olarak düzeltilmesi.
2. **Satış Otoritesinin Birleştirilmesi:**
   - Hibrit `SqliteSaleRepository` yerine Core Next satış akışının authoritative yapılması.
3. **İzole Sentetik Test (Staging Harness):**
   - Düzeltmeler tamamlandıktan sonra, canlı tenant'lara dokunulmadan sentetik bir test şirketinde (`comp-test-isolated`) bootstrap ve push/pull döngüsünün test edilmesi.
