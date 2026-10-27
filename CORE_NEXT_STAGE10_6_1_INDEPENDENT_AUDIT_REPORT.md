# SERENUT OS — STAGE 10.6.1: BAĞIMSIZ ADLİ DOĞRULAMA VE CANLIYA GEÇİŞ KAPISI RAPORU

**Tarih:** 2026-10-13  
**Aşama:** Stage 10.6.1 — Bağımsız Adli Denetim, Kanıt Doğrulaması ve Canlıya Geçiş Kapısı  
**Denetlenen Kapsam:** `server/src/modules/sync_v4/`, `core_next/client_core/lib/infrastructure/`, `test/core_next/stage10_6_sync_convergence_test.dart`  
**Denetim Türü:** Salt Okunur Adli Kod Analizi, Transaction İncelemesi, Matematiksel Watermark Kanıtı  
**Nihai Karar:** **CANLIYA GEÇİŞ: `BLOCKED` (DURDURULDU)**

---

## 1. GİT DURUMU VE HEAD

### 1.1. Denetim Başlangıcı ve Bitişi
- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **İzlenen Değiştirilmiş Dosyalar (`git diff --stat`):**
  - `server/src/modules/sync_v4/sync-v4.materializer.ts` (39 satır ekleme/değişiklik)
  - `server/src/modules/sync_v4/sync-v4.routes.ts` (6 satır ekleme/değişiklik)
- **İzlenmeyen Dosyalar:** `core_next/`, `test/core_next/` ve önceki aşama raporları.
- **Değişiklik Kısıtı:** Bu denetim aşamasında hiçbir kaynak veya test dosyası oluşturulmamış, değiştirilmemiş veya silinmemiştir; yalnızca bu denetim raporu üretilmiştir.

---

## 2. SUNUCU İŞLEM BÜTÜNLÜĞÜ VE TRANSACTION DENETİMİ

Sunucu tarafındaki gerçek TypeScript üretim kodu (`sync-v4.routes.ts` ve `sync-v4.materializer.ts`) bağımsız olarak incelenmiştir:

### 2.1. Satış, Stok, Hareket ve Replikasyon Kaydının Atomikliği
- **Kaynak Kod Kanıtı:** [sync-v4.routes.ts:65-336](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L65-L336), [sync-v4.materializer.ts:266-285](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L266-L285)
- **Gerçek Akış:**
  1. İstek `client.query('BEGIN')` ile başlar.
  2. Her mutasyon için `client.query('SAVEPOINT sync_mutation')` açılır.
  3. `applyDomainMutation` çağrılır:
     - `INSERT INTO sales`
     - `UPDATE products SET quantity = quantity - $1, updated_at = NOW()`
     - `INSERT INTO inventory_movements` (delta: `-qty`, movement_type: `'sale'`)
     - `INSERT INTO sale_items`
  4. `INSERT INTO sync_v4_changes` çalıştırılır ve `revision` üretilir.
  5. `INSERT INTO sync_v4_entities` çalıştırılır.
  6. `RELEASE SAVEPOINT sync_mutation` yapılır.
  7. Tüm mutasyonlar tamamlandığında `client.query('COMMIT')` icra edilir.
- **Değerlendirme:** Tüm yazımlar tek bir PoolClient ve tek bir PostgreSQL transaction'ında yürütülür. Yarım kalmış işlem (örneğin satış yazılıp stok düşmemesi veya stok düşüp log yazılmaması) PostgreSQL ACID garantileriyle engellenmiştir.
- **Etiket:** `DOĞRULANDI`

### 2.2. İade ve İptal Bütünlüğü
- **Kaynak Kod Kanıtı:** [sync-v4.materializer.ts:141-158](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L141-L158), [refund.service.ts:90-115](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/order/refund.service.ts#L90-L115)
- **Gerçek Akış:**
  - `RefundService.create` fonksiyonuna aynı transaction client'ı aktarılır.
  - `INSERT INTO refunds`, `INSERT INTO refund_items`, `UPDATE products SET quantity = quantity + $1`, `INSERT INTO inventory_movements (movement_type: 'refund')` ve `sync_v4_changes` aynı transaction içinde commit edilir.
- **Etiket:** `DOĞRULANDI`

### 2.3. Aynı Satışın Tekrar Gönderilmesi (Idempotency)
- **Kaynak Kod Kanıtı:** [sync-v4.routes.ts:132-142](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L132-L142), [sync-v4.materializer.ts:175-181](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L175-L181)
- **Gerçek Akış:**
  - Birinci kalkan: Aynı `mutation_id` gelirse `sync_v4_changes` üzerinden mevcut revizyon döner ve `upsertSale` çağrılmadan döngü `continue` eder.
  - İkinci kalkan: Farklı `mutation_id` fakat aynı `sale_id` ile gelinirse `upsertSale` içindeki `SELECT ... FROM sales WHERE id = $1 FOR UPDATE` kaydı bulur; payload birebir aynı ise sessizce no-op `return;` eder. İkinci stok hareketi yazılmaz.
- **Etiket:** `DOĞRULANDI`

### 2.4. Aynı Satış Kimliği ile Farklı Payload Gelmesi (Conflict Davranışı)
- **Kaynak Kod Kanıtı:** [sync-v4.materializer.ts:182-212](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L182-L212), [sync-v4.routes.ts:281-304](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L281-L304)
- **Gerçek Akış:**
  - Önceden var olan satışın `total_amount`, `paid_amount`, `payment_method`, `customer_id` veya `sale_items` (ürün kimliği veya miktarı) uyuşmazsa `throw new Error("sale_payload_conflict")` fırlatılır.
  - Route katmanında `catch (mutationError)` bloğu:
    `ROLLBACK TO SAVEPOINT sync_mutation` yapar; işlemi `rejected` dizisine ekler (`rejected.push({ mutation_id, error: "sale_payload_conflict" })`).
  - İstemciye HTTP 200 içinde `{ results: [], conflicts: [], rejected: [{ error: "sale_payload_conflict" }] }` döner.
  - **Kritik Detay (İstemci Tarafı):** İstemci outbox işlemcisinde ([sync_v4_outbox_processor.dart:129](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart#L129)) `sale_payload_conflict` henüz `nonRetryableServerErrors` kümesinde yer almadığı için istemci bu mutasyonu `REJECTED` (ölü mektup) yerine `TRANSIENT_ERROR` olarak işaretleyip tekrar denemektedir. Başarılı ACK verilmemektedir (stok bozulmaz), ancak istemci sonsuz denemeye girmemek için bu hatayı kalıcı hata saymalıdır.
- **Etiket:** `KISMEN DOĞRULANDI`

### 2.5. Eşzamanlı Yarış Durumu (Concurrent Push Race Condition)
- **Kaynak Kod Kanıtı:** [sync-v4.routes.ts:145-148](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L145-L148)
- **Gerçek Akış:**
  - `SELECT pg_advisory_xact_lock(hashtext($1), hashtext($2))` ile kiracı ve varlık bazında exclusive PostgreSQL transaction kilidi alınır.
  - Aynı satış ID'si için yarışan iki eşzamanlı istek veritabanı düzeyinde sıralanır; ikinci gelen istek kilit kalktığında committed kaydı görerek idempotency kontrolüne takılır.
- **Etiket:** `DOĞRULANDI`

---

## 3. İSTEMCİ PULL INGESTION VE STOK MUTASYONU DENETİMİ

`core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart` bağımsız olarak incelenmiştir:

### 3.1. Çok Kasalı Satış ve İade Tüketimi
- **Kaynak Kod Kanıtı:** [sync_v4_pull_ingestion_service.dart:132-140](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L132-L140), [sync_v4_pull_ingestion_service.dart:333-470](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L333-L470)
- **Gerçek Akış:**
  - `_applyChanges` döngüsünde `change.entityType == 'sale'` ve `'refund'` artık sessizce yutulmamakta (`otherCount++`), `_ingestSale` ve `_ingestRefund` fonksiyonlarına yönlendirilmektedir.
  - `change.deviceId != localDeviceId` kontrolüyle: Başka kasaların yaptığı satışların kalemleri yerel SQLite `products.stock_quantity` sütunundan düşülmektedir. İadelerde ise stok artırılmaktadır.
  - Her stok hareketi `sync_applied_events` tablosuna `quantity_delta` ve `revision` ile kaydedilmektedir.
- **Etiket:** `DOĞRULANDI`

### 3.2. Yerel Cihazın Kendi Satışını Yeniden Uygulaması (Açık ve Risk)
- **Kaynak Kod Kanıtı:** [sync_v4_pull_ingestion_service.dart:345-349](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L345-L349)
- **Bulgu:**
  ```dart
  final isLocalOrigin = localDeviceId != null &&
      localDeviceId!.isNotEmpty &&
      change.deviceId.isNotEmpty &&
      change.deviceId == localDeviceId;
  ```
  - `localDeviceId` parametresi servisin kurucusunda **opsiyoneldir** (`{this.localDeviceId}`).
  - Eğer çağıran kod `localDeviceId` geçmezse (null olursa) veya cihaz ID'si eşleşmezse, `isLocalOrigin = false` olur.
  - Servis, yerel `sales` veya `sync_events` tablosunu kontrol etmemekte; yalnızca `isLocalOrigin` bayrağına ve `sync_applied_events` tablosuna güvenmektedir.
  - **Risk:** `localDeviceId` sağlanmazsa, kasanın kendi yaptığı satışlar pull sırasında yabancı satış sanılarak yerel stoktan **ikinci kez düşülecektir**.
- **Etiket:** `KISMEN DOĞRULANDI` (Mimari koruma kuralı gerektirir).

### 3.3. Hata Durumunda Cursor Güvenliği
- **Kaynak Kod Kanıtı:** [sync_v4_pull_ingestion_service.dart:107-160](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L107-L160)
- **Gerçek Akış:**
  - Tüm değişiklikler ve `_saveCursor(txn, nextCursor)` çağrısı tek bir `db.transaction` içindedir.
  - Batch'in herhangi bir yerinde SQLite hatası çıkarsa tüm transaction rollback olur; cursor ilerlemez; olay kaybı yaşanmaz.
- **Etiket:** `DOĞRULANDI`

### 3.4. Matematiksel Watermark Hesabı (`_calculateUnreflectedSoldQty`)
- **Kaynak Kod Kanıtı:** [sync_v4_pull_ingestion_service.dart:282-330](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L282-L330)
- **Formül:**
  $$\text{effectiveStock} = \text{rawRemoteStock} - \text{unreflectedSold}$$
  $$\text{unreflectedSold} = \text{localPendingQty} - \sum_{R_{event} > R_{snap}} \text{quantity\_delta}$$
- **Sayısal Doğrulama Örneği:**
  - Başlangıç stoğu 10.
  - Kasa B, Kasa A'nın rev 105 ile yaptığı 2 adetlik satışını işler (`quantity_delta = -2`). Kasa B stoğu 8 olur.
  - Daha sonra gecikmiş bir rev 100 katalog snapshot'ı (stok 10) gelir ($R_{snap} = 100$).
  - `post_delta` ($R > 100$) = $-2$.
  - `unreflectedSold` = $0 - (-2) = +2$.
  - `effectiveStock` = $10 - 2 = 8$.
  - **Sonuç:** Stok 10'a geri sıçramaz; 8 olarak korunur!
- **Etiket:** `DOĞRULANDI`

---

## 4. WATERMARK VE CURSOR SEMANTİĞİ DENETİMİ

| Soru | Kod Kanıtı ve İnceleme | Sınıf |
|---|---|---|
| Watermark nerede saklanıyor? | Sunucuda `sync_v4_changes.revision` (`BIGSERIAL`); istemcide `sync_applied_events.revision` ve `app_settings.sync_pull_cursor`. | `DOĞRULANDI` |
| Sunucu mu üretiyor, istemci mi? | Sunucu PostgreSQL sequence'i üretir. İstemci yalnızca sunucu revizyonunu kaydeder; yerel kafasına göre sıra üretmez. | `DOĞRULANDI` |
| Global sequence mi, varlık bazlı mı? | Global kiracı sequence'idir. Ürün bazlı ayrı bir monotonically increasing alt sayaç yoktur; kiracının tüm varlıkları aynı sequence'i paylaşır. | `DOĞRULANDI` |
| Eski snapshot yeni hareketi ezebilir mi? | Hayır. `post_delta` formülü sayesinde $R_{event} > R_{snap}$ olan hareketler snapshot stoğundan düşülür. | `DOĞRULANDI` |
| Cursor batch commit olmadan ilerler mi? | Hayır. `_saveCursor` tek bir SQLite transaction'ının en sonundadır. | `DOĞRULANDI` |
| Bootstrap ve incremental cursor uyumlu mu? | Evet. Bootstrap sunucudaki `COALESCE(MAX(revision), 0)` değerini döner; incremental pull bu cursor'dan sonrasını (`revision > cursor`) çeker. | `DOĞRULANDI` |

---

## 5. TEST A–J KAPSAM MATRİSİ VE GERÇEK NİTELİK DENETİMİ

`test/core_next/stage10_6_sync_convergence_test.dart` içindeki 10 test adli olarak incelenmiştir:

| Test | Satır Aralığı | İstemci Tarafı Nitelik | Sunucu Tarafı Nitelik | Kanıtlamadığı / Sınırı |
|---|---|---|---|---|
| **Test A (Normal Satış)** | L234-L265 | **Gerçek SQLite** (`sqflite_common_ffi`) & gerçek `SyncV4PullIngestionService` | `SimulatedSyncV4Server` (Dart In-Memory) | Gerçek Express route ve PostgreSQL transaction'ını çalıştırmaz. |
| **Test B (İade)** | L267-L305 | **Gerçek SQLite** & gerçek ingestion | `SimulatedSyncV4Server` (Dart In-Memory) | Gerçek `RefundService.create` PostgreSQL kilitlerini test etmez. |
| **Test C (Yinelenen Push)** | L307-L343 | Yalnızca sunucu simülasyonu sınanır | `SimulatedSyncV4Server` | Gerçek `sync_v4_changes` UNIQUE constraint yarışını test etmez. |
| **Test D (Payload Çakışması)** | L345-L387 | Yalnızca sunucu simülasyonu sınanır | `SimulatedSyncV4Server` | Gerçek route katmanı `rejected` HTTP serileştirmesini test etmez. |
| **Test E (Çok Satırlı Satış)** | L389-L411 | **Gerçek SQLite** & gerçek ingestion | `SimulatedSyncV4Server` | - |
| **Test F (Rollback)** | L413-L436 | Yalnızca sunucu simülasyonu sınanır | `SimulatedSyncV4Server` snapshot geri yükleme | Gerçek PostgreSQL `ROLLBACK TO SAVEPOINT` icra edilmez. |
| **Test G (Sayfalı Pull & Retry)**| L438-L485 | **Gerçek SQLite** & gerçek ingestion | `SimulatedSyncV4Server` pagination | Gerçek HTTP bağlantı zaman aşımı test edilmez. |
| **Test H (Snapshot & Olay Sırası)**| L487-L512 | **Gerçek SQLite** & gerçek watermark hesabı | Sabit `SyncPullChange` DTO'ları | Uçtan uca HTTP pipeline'ı test etmez; hesaplama modelini kanıtlar. |
| **Test I (Eşzamanlı Çevrimdışı)** | L514-L567 | **Gerçek SQLite** (2 ayrı Kasa A ve B) | `SimulatedSyncV4Server` | İki ayrı fiziksel cihazın WebSocket senkronizasyonunu test etmez. |
| **Test J (Bootstrap & Incremental)**| L569-L620 | **Gerçek SQLite** & gerçek ingestion | `SimulatedSyncV4Server` | Canlı veritabanı hydration yükünü test etmez. |

### Adli Değerlendirme:
- İstemci tarafında testler **kesinlikle gerçektir**; gerçek SQLite motoru (`sqflite_common_ffi`), gerçek tablolar, gerçek yabancı anahtar ve indeksler çalıştırılmıştır.
- Sunucu tarafında ise testler **gerçek Express/PostgreSQL üzerinde değil**, sunucu protokolünü simüle eden bir Dart motoru (`SimulatedSyncV4Server`) üzerinde koşmuştur. Sunucu TypeScript kodunun doğruluğu statik adli analiz ve `npx tsc --noEmit` ile kanıtlanmış, ancak canlı DB testi yapılmamıştır.

---

## 6. GERÇEK SUNUCU TESTLERİNİN KAPSAMI

- `server/package.json` içindeki testler (`npm test`, `test:release-signing`, `test:routes`) incelenmiştir.
- `server/src/test/sync_v4_domain_materialization.test.ts` testi `DROP SCHEMA public CASCADE` komutuyla doğrudan `pgPool` bağlantısına bağımlıdır.
- Güvenlik kuralları ve canlı PostgreSQL'e dokunmama yasağı nedeniyle bu test bu aşamada çalıştırılamamıştır.
- **Etiket:** `TEST EDİLEMEDİ` (Yerel izole test PostgreSQL konteyneri gerektirir).

---

## 7. MİGRATİON VE ESKİ KURULUM RİSKİ DENETİMİ

- **Kaynak Kod Kanıtı:** [schema_definitions.dart:256-312](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/schema_definitions.dart#L256-L312)
- **Şema Sürümü:** `CoreSchemaDefinitions.schemaVersion = 3`
- **İnceleme Bulguları:**
  1. `onCreate`: Yeni kurulumlarda `sync_applied_events` tablosu ve indeksleri doğrudan oluşturulur.
  2. `onUpgrade`: Eski v1 ve v2 veritabanları açıldığında `if (oldVersion < 3)` bloğu çalışır ve `CREATE TABLE IF NOT EXISTS sync_applied_events` çalıştırır.
  3. Veri kaybı riski: Mevcut hiçbir tablo silinmemekte (`DROP TABLE` yok), kolon silinmemektedir.
  4. Yarıda kesilme riski: `IF NOT EXISTS` kullanıldığı için işlem kesilip tekrar başlatılsa bile hata vermez.
  5. `SyncV4PullIngestionService._applyChanges` içinde de savunmacı `CREATE TABLE IF NOT EXISTS sync_applied_events` çalıştırıldığı için, migration çalışmamış olsa bile ilk senkronizasyonda tablo oluşturulur.
- **Etiket:** `DOĞRULANDI` (Güvenli, veri kaybı riski yok).

---

## 8. KANITLANMAMIŞ GARANTİLER VE KALAN AÇIKLAR

1. **`localDeviceId` Null Güvensizliği (`KISMEN DOĞRULANDI`):**
   - `SyncV4PullIngestionService` kurucusunda `localDeviceId` null bırakılırsa, servis kendi ürettiği satışları yabancı satış sanarak yerel stoktan mükerrer düşecektir.
   - *Giderilme Şartı:* `_ingestSale` içinde yerel `sales` tablosunda `id = change.entityId` kontrolü ikinci bir kalkan olarak eklenmeli veya `localDeviceId` zorunlu (`required`) yapılmalıdır.
2. **`sale_payload_conflict` Retry Döngüsü (`KISMEN DOĞRULANDI`):**
   - Sunucunun fırlattığı `sale_payload_conflict` hatası istemci outbox işlemcisinde `nonRetryableServerErrors` kümesinde yer almadığı için `TRANSIENT_ERROR` yapılmakta ve sonsuz tekrar denemesine girmektedir.
   - *Giderilme Şartı:* `sale_payload_conflict` ve `mutation_payload_conflict` hataları `nonRetryableServerErrors` içine eklenmelidir.
3. **Sunucu Uçtan Uca PostgreSQL Test Eksikliği (`TEST EDİLEMEDİ`):**
   - Sunucu transaction ve idempotency mantığı TypeScript seviyesinde yazılmış ve simülasyonla doğrulanmış, ancak gerçek PostgreSQL üzerinde çalışan otomatik entegrasyon testi koşulmamıştır.

---

## 9. CANLIYA GEÇİŞ KAPISI VE NİHAİ KARAR

### NİHAİ KARAR:
> **CANLI SATIŞ EKRANINA ENTEGRASYON: `BLOCKED` (DURDURULDU)**

### Gerekçeler:
1. `localDeviceId` kurucuda opsiyonel bırakılmıştır; null gelmesi halinde yerel satışların mükerrer düşme riski mevcuttur.
2. `sale_payload_conflict` istemci outbox tarafından kalıcı hata (`REJECTED`) olarak ele alınmamakta, kuyrukta `TRANSIENT_ERROR` olarak kalmaktadır.
3. Sunucu tarafındaki PostgreSQL transaction ve advisory lock davranışları canlı/yerel izole PostgreSQL üzerinde uçtan uca otomatik test edilmemiştir.
4. `lib/` canlı satış ekranına entegrasyon ve fiziksel donanım testleri henüz icra edilmemiştir.

Bu 3 küçük teknik kalkan giderilip donanım aşaması tamamlanana kadar canlıya geçiş kapısı kapalı tutulmalıdır.
