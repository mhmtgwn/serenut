# SERENUT OS — STAGE 10.7.2: SATIŞ KİMLİĞİ GÜVENLİĞİ VE PULL ÇALIŞMA ZİNCİRİ DENETİM VE DÜZELTME RAPORU

**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.7.2  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Canlıya Geçiş Durumu:** ⛔ **ENGELLENDİ (BLOCKED)**  

---

## 1. KANITLANAN SATIŞ KİMLİĞİ SÖZLEŞMESİ

Projede uçtan uca satış oluşturma, kuyruğa yazma, sunucuya iletme, sunucuda kalıcılaştırma ve pull ile diğer istemcilere dağıtma adımları kaynak kod seviyesinde incelenmiş ve şu sözleşme kanıtlanmıştır:

1. **Yerel Satış Kimliği (UUID v4):**
   - İstemcide satış [`CoreCheckoutUseCase.execute`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L87) içinde `final saleId = _uuid.v4();` ile üretilir.
   - Yerel SQLite tablosuna `INSERT INTO sales (id, receipt_no, idempotency_key, ...)` şeklinde birincil anahtar (`PRIMARY KEY`) olarak yazılır.
2. **Outbox Mutasyonu ve Taşıma:**
   - [`SyncV4PayloadAdapter.buildSaleMutation`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_payload_adapter.dart#L136) içinde `entityId: saleId` olarak atanır.
   - Sunucuya `POST /api/v4/sync/push` ile `entity_type: 'sale'`, `entity_id: saleId` olarak gönderilir.
3. **Sunucu Tarafı Bütünlüğü ve Korunması:**
   - [`server/src/modules/sync_v4/sync-v4.materializer.ts:266`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L266):
     ```sql
     INSERT INTO sales (id, company_id, customer_id, total_amount, paid_amount, discount_amount, payment_method, status, fsm_state, idempotency_key, created_at, updated_at, is_deleted, created_by)
     VALUES ($1,$2,$3,$4,$5,$6,$7,'completed','completed',$8,COALESCE($9::timestamptz,NOW()),NOW(),false,$10)
     ```
     Burada `$1` parametresi doğrudan istemcinin gönderdiği `mutation.entity_id` değeridir. Sunucu yeni bir UUID üretmez, istemcinin orijinal UUID'sini korur.
   - [`server/src/modules/sync_v4/sync-v4.routes.ts:225-235`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L225-L235):
     Replikasyon günlüğüne `INSERT INTO sync_v4_changes (entity_type, entity_id, ...)` olarak yine aynı `mutation.entity_id` yazılır.
4. **Pull Değişikliği İletimi:**
   - Sunucu [`sync-v4.routes.ts:376`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L376) sorgusuyla `sync_v4_changes` tablosundaki `entity_id` değerini `SyncPullChange.entityId` olarak istemciye döner.
   - İstemciye ulaşan `change.entityId`, orijinal yerel satış UUID'sinin kendisidir.
5. **Fiş Numarası (`receipt_no`) Yokluğu:**
   - PostgreSQL `sales` tablosunda `receipt_no` kolonu bulunmamaktadır.
   - `SyncV4PayloadAdapter.buildSaleMutation` metodunda (L121-131) payload nesnesi hazırlanırken `receipt_no` parametresi JSON payload'a dahil edilmemiştir.
   - Sunucu pull veya bootstrap yanıtlarında `receipt_no` alanı dönmemektedir.
6. **İade (`refund`) Olayı Kimliği:**
   - İade işlemi sunucuda `refunds` tablosuna bağımsız bir `id` (iade UUID'si) ve `sale_id` (orijinal satış UUID'si) ile kaydedilir.
   - Replikasyon günlüğünde `entity_type: 'refund'` ve `entity_id: refund_id` olarak iletilir. Orijinal satış ID'si ise `payload['sale_id']` içinde taşınır.

---

## 2. `receipt_no` YANLIŞ EŞLEŞME RİSKİNİN GİDERİLMESİ

### 2.1. Önceki Hatanın Kök Nedeni (False Positive)
Önceki [`SyncV4PullIngestionService._ingestSale`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L372) uygulamasında:
```sql
SELECT id FROM sales 
WHERE id = ? 
   OR (receipt_no IS NOT NULL AND receipt_no = ?)
   OR (idempotency_key IS NOT NULL AND idempotency_key = ?)
LIMIT 1
```
Bu sorguda `receipt_no` eşleşmesi bulunmaktaydı. Kasa B'nin bağımsız olarak ürettiği bir fiş numarası (`REC-001`), Kasa A'nın kendi yerel satış fiş numarasıyla (`REC-001`) çakıştığında; Kasa A bu satışı "kendi yerel satışı" varsayarak (`isLocalOrigin = true`) yabancı satışın stok düşümünü tamamen atlıyordu.

### 2.2. Uygulanan Güvenli Çözüm
[`core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart) dosyasında `_ingestSale` (L370-388) ve `_ingestRefund` (L471-489) metotları güvenli hale getirilmiştir:

1. **`receipt_no` Eşleştirmesi Tamamen Kaldırıldı:**
   Fiş numarası hiçbir koşulda yerel köken kanıtı sayılmamaktadır.
2. **Değişmez UUID Önceliği:**
   Yerel veritabanında satış eşleştirmesi birincil olarak `id = change.entityId` (128-bit UUID v4) üzerinden yapılır.
3. **Ayırt Edilebilir `idempotency_key` Koruması:**
   `checkout_use_case.dart:92` gereği `idempotency_key` belirtilmediğinde fiş numarasına (`receiptNo`) varsayılan atanmaktadır. Bu nedenle `payloadIdempKey == payloadReceiptNo` olduğu durumlarda bu anahtarın küresel tekilliği bulunmadığından ikincil aramada devre dışı bırakılmıştır (`? = 1` koruması):
   ```dart
   final bool isIdempKeyDistinguishable = payloadIdempKey != null &&
       payloadIdempKey.trim().isNotEmpty &&
       payloadIdempKey != payloadReceiptNo;

   final existingLocalSales = await txn.rawQuery('''
     SELECT id FROM sales 
     WHERE id = ? 
        OR (? = 1 AND idempotency_key IS NOT NULL AND idempotency_key = ?)
     LIMIT 1
   ''', [
     change.entityId,
     isIdempKeyDistinguishable ? 1 : 0,
     payloadIdempKey ?? '',
   ]);
   ```
4. **İade Eşleştirmesi Güvenliği:**
   `_ingestRefund` içinde de aynı mantık işletilmiş; `WHERE status = 'REFUND'` şartı korunarak orijinal satış (`COMPLETED`) ile iadelerin birbirine karışması engellenmiştir.

---

## 3. EKLENEN REGRESYON TESTLERİ VE DOĞRULAMA KAPSAMI

Yeni test dosyası: [`test/core_next/stage10_7_2_identity_safety_test.dart`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_7_2_identity_safety_test.dart)  
Gerçek SQLite FFI (`sqflite_common_ffi`) üzerinde 8 adet zorunlu güvenlik senaryosu kodlanmış ve koşturulmuştur:

| No | Senaryo Adı | Assertion ve Test Akışı | Sonuç |
|---|---|---|---|
| **10.7.2.1** | Kendi satışının pull event'i stok düşmemeli | Kendi kasanın satışı (`kasa-a`) pull edildiğinde `prod['stock_quantity'] == 20` olarak korunur, `sync_applied_events` tablosuna yazılır. | **BAŞARILI** |
| **10.7.2.2** | Aynı `receipt_no` bulunsa bile yabancı stok atlanmamalı | Yerelde `REC-COMMON-100` fişi varken Kasa B aynı fiş numarasıyla satış gönderdiğinde stok 20 -> 17 düşer; yabancı satış atlanmaz. | **BAŞARILI** |
| **10.7.2.3** | Farklı UUID durumunda açık ve güvenli davranış | Yabancı kasanın farklı UUID'si stok düşer (20 -> 16). Ancak kendi kasanın satışı UUID farklı olsa dahi (`isDeviceLocal = true`) stok düşmez. | **BAŞARILI** |
| **10.7.2.4** | Yabancı satış tekrarı (Replay idempotency) | Kasa B'nin satışı (5 adet) ilk seferde stoğu 20 -> 15 yapar; aynı olay ikinci kez pull edildiğinde stok 15'te kalır. | **BAŞARILI** |
| **10.7.2.5** | İade olayı tekrarı (Replay idempotency) | Kasa B'nin iadesi (2 adet) ilk seferde stoğu 15 -> 17 yapar; ikinci kez pull edildiğinde mükerrer artış olmaz, 17 kalır. | **BAŞARILI** |
| **10.7.2.6** | İade olayı orijinal satışla karıştırılmamalı | Yerelde `status: 'COMPLETED'` orijinal satış varken gelen yabancı iade onunla eşleşmez (`status = 'REFUND'` ayrımı); stok 20 -> 21 artırılır. | **BAŞARILI** |
| **10.7.2.7** | Hata durumunda tutarlılık (ACID Rollback) | Transaction içinde hata fırlatıldığında `sync_applied_events` temiz kalır, cursor ilerlemez (`cursor == 0`). | **BAŞARILI** |
| **10.7.2.8** | Cihaz kimliği fail-safe koruması | `localDeviceId: null` ve `'   '` durumunda `StateError('unidentified_local_device')` fırlatılır, yabancı varsayımı engellenir. | **BAŞARILI** |

---

## 4. PULL ÇALIŞMA ZİNCİRİNİN GERÇEK DURUMU

`core_providers.dart` ve ilgili sınıflar uçtan uca incelenmiş; çalışma zincirinin mevcut durumu tespit edilmiştir:

1. **Mevcut ve Çalışan Parçalar:**
   - [`SyncV4HttpClient`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_http_client.dart): Sunucu ile HTTP iletişimini kuran izole istemci (`pull()`, `push()`, `bootstrap()`).
   - [`SyncV4PullIngestionService`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart): Çekilen değişiklikleri SQLite'a ACID transaction içinde idempotent uygulayan servis.
   - `coreSyncPullIngestionServiceProvider` ve `coreDeviceIdProvider`: Riverpod DI tanımları.
   - Cursor Kalıcılığı: `app_settings` tablosundaki `sync_pull_cursor` anahtarı üzerinde transaction commit'iyle atomik saklanmaktadır.
2. **Eksik Olan Parça (Zincir Kopukluğu):**
   - HTTP istemcisinden cursor okuyarak `httpClient.pull()` yapan ve dönen sayfaları `ingestionService.ingestPull()` metoduna aktaran bir **`PullWorker`** veya **`SyncPullOrchestrator`** sınıfı mevcut değildir.
   - `core_providers.dart` içinde `SyncV4HttpClient` sağlayıcısı bulunmamaktadır (çünkü `baseUrl`, `deviceActivationId` ve `deviceId` dinamik lisans parametreleridir).
   - Dolayısıyla `coreSyncPullIngestionServiceProvider` tanımlı olmasına rağmen çalışma zamanında hiçbir servis veya widget tarafından çağrılmamakta, atıl (dormant) durmaktadır.

---

## 5. EKSİK BİLEŞENLER VE GEREKEN SONRAKİ ADIM TASARIMI

Pull zincirinin üretime hazır hale gelmesi için gereken en küçük ve temiz mimari tasarım:

```
[ Lisans / Terminal Konfigürasyonu ]
               │
               ▼
   coreSyncHttpClientProvider (Yeni eklenecek)
               │
               ▼
   coreSyncPullWorkerProvider (Yeni eklenecek Worker)
   ├── 1. cursor = await ingestionService.getSavedCursor()
   ├── 2. dto = await httpClient.pull(cursor: cursor, limit: 100)
   ├── 3. result = await ingestionService.ingestPull(dto)
   └── 4. if (dto.changes.length == limit) repeatNextPage()
               │
               ▼
[ Arka Plan Zamanlayıcı / UI Manuel Yenileme Butonu ]
```

- **Gereken Bileşen 1:** Lisans/aktivasyon servisinden `baseUrl` ve `deviceActivationId` alarak `SyncV4HttpClient` örneği sağlayan bir Riverpod sağlayıcısı.
- **Gereken Bileşen 2:** Tekil sayfa çekme (`pullNextBatch()`) ve tam döngü (`syncPullAll()`) metotlarını içeren, hata durumunda retry/backoff yöneten hafif bir `SyncV4PullWorker`.
- **Gereken Bileşen 3:** Kasa satış ekranı açıldığında veya periyodik aralıklarla bu worker'ı tetikleyen yaşam döngüsü entegrasyonu.

Bu aşamada mimari sınırlar gereği aceleyle uydurma worker yazılmamış; eksiklik net olarak belgelenmiştir.

---

## 6. DEĞİŞTİRİLEN DOSYALAR VE GİT DURUMU

### 6.1. Değiştirilen ve Eklenen Dosyalar
1. [`core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart):
   - `_ingestSale` ve `_ingestRefund` içindeki ikincil eşleştirme güvenli hale getirildi; `receipt_no` aramadan çıkarıldı, `isIdempKeyDistinguishable` koruması eklendi.
2. [`test/core_next/stage10_7_2_identity_safety_test.dart`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_7_2_identity_safety_test.dart):
   - 8 adet yeni regresyon ve kimlik güvenliği testi yazıldı.

### 6.2. Git Ağaç Durumu
- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **`git diff --check`:** Temiz (Format/whitespace hatası yok).
- **`git diff --stat`:**
  ```text
  server/src/modules/sync_v4/sync-v4.materializer.ts | 39 ++++++++++++++++++++--
  server/src/modules/sync_v4/sync-v4.routes.ts       |  6 +++-
  2 files changed, 41 insertions(+), 4 deletions(-)
  ```
  *(Tracked alanda yalnızca Stage 10.6'dan kalan 2 sunucu dosyası bulunmaktadır)*.
- **`lib/` Durumu:** **`%100 DOKUNULMAMIŞTIR`**. Canlı kod tamamen salt okunur korunmuştur.
- **Untracked Dosyalar:** `core_next/` kaynakları, `test/core_next/` test dosyaları ve raporlar.

---

## 7. ÇALIŞTIRILAN KOMUTLAR VE TEST SONUÇLARI

| Komut | Çalışma Dizini | Çıkış Kodu | Sonuç |
|---|---|---|---|
| `flutter test test/core_next/stage10_7_2_identity_safety_test.dart` | Repo Kökü | **0** | **8/8 Başarılı** |
| `flutter test test/core_next/stage10_7_client_safety_test.dart` | Repo Kökü | **0** | **16/16 Başarılı** |
| `flutter test test/core_next/` | Repo Kökü | **0** | **143/143 Başarılı** (Tüm CoreNext Testleri) |
| `git diff --check` | Repo Kökü | **0** | Temiz |

---

## 8. AÇIK P0 / P1 BULGULAR LİSTESİ

1. **P0 (Kritik Blokaj): İzole PostgreSQL Test Ortamı Yokluğu**
   - `server/src/test/sync_v4_domain_materialization.test.ts` içindeki `DROP SCHEMA public CASCADE` riski devam etmektedir. İzole Docker/test veritabanı olmadan çalıştırılamaz.
2. **P1: `SyncV4PullWorker` Eksikliği (Dormant Ingestion Provider)**
   - `coreSyncPullIngestionServiceProvider` tanımlı olmasına rağmen bunu periyodik veya olay tabanlı tetikleyecek arka plan worker'ı henüz yazılmamıştır.
3. **P1: Fiziksel Donanım ve Yazıcı Doğrulaması**
   - ESC/POS ve TSPL isolate yapıları kodlanmış olup fiziksel USB/RAW yazıcı saha testleri beklenmektedir.
4. **P1: Canlı Satış Ekranı (`lib/`) Entegrasyonu**
   - `lib/` halen eski mimariyi kullanmaktadır; yeni çekirdeğe kesintisiz geçiş (cutover) runbook'u henüz başlatılmamıştır.

---

## 9. CANLIYA GEÇİŞ KAPISI KARARI

> ### ⛔ NİHAİ KARAR: CANLIYA GEÇİŞ ENGELLENDİ (BLOCKED)
>
> **Gerekçeler:**
> 1. `_ingestSale` içindeki `receipt_no` yalancı pozitif eşleşme riski başarıyla giderilmiş ve 8 yeni senaryo (toplam 143 test) ile kanıtlanmış olsa da;
> 2. `SyncV4PullWorker` henüz yazılmadığı için istemci çalışma zamanında pull döngüsü tamamlanmamıştır;
> 3. PostgreSQL entegrasyon testleri `DROP SCHEMA public CASCADE` yıkım riski nedeniyle güvenli izole ortam olmadan çalıştırılamaz;
> 4. `lib/` canlı satış uygulamasına bu aşamada kesin sınırlar gereği dokunulmamıştır.

---
*Rapor Sonu — Serenut OS Stage 10.7.2 Tamamlandı.*
