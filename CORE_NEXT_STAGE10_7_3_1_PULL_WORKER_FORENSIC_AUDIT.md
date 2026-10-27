# SERENUT OS — STAGE 10.7.3.1 BAĞIMSIZ PULL WORKER ADLİ DENETİM VE GÜVENLİK DOĞRULAMA RAPORU

**Tarih:** 14 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Denetlenen Kapsam:** `SyncV4PullWorker`, `SyncV4HttpClient`, `SyncV4PullIngestionService`, `core_providers.dart`, Sunucu `sync-v4.routes.ts` ve Test Süitleri  
**Denetçi Modu:** Bağımsız Adli Denetim (Önceki raporlar kanıt sayılmamış, gerçek kod ve komut çıktıları incelenmiştir).

---

## 1. ÇIKIŞ KRİTERLERİ VE DENETİM KARAR MATRİSİ

| Denetim Alanı | Karar | Gerekçe ve Adli Kanıt |
| :--- | :---: | :--- |
| **`SOURCE_AUDIT`** | **PASS** | Tüm sınıfların (`SyncV4PullWorker`, `SyncV4HttpClient`, `SyncV4PullIngestionService`) kaynak kodları, metot imzaları, tip sözleşmeleri satır satır denetlenmiş; sözleşme dışı hiçbir alan veya varsayım bulunmamıştır. |
| **`PULL_PAGINATION`** | **PASS** | Sunucu `/api/v4/sync/pull` sayfalama sözleşmesi (`cursor`, `limit`, `changes`, `next_cursor`) ile istemci `SyncV4PullWorker` sayfalama döngüsü tam uyumludur. Son sayfa tespiti (`changes.length < pageSize` veya `changes.isEmpty`) ve boş sayfa sonlanması kanıtlanmıştır. |
| **`CURSOR_ATOMICITY`** | **PASS** | Cursor, `SyncV4PullIngestionService._applyChanges` metodunda **tek bir SQLite ACID transaction'ı (`db.transaction`) içinde** en son adımda `_saveCursor(txn, nextCursor)` ile `app_settings` tablosuna yazılır. Bir hata durumunda transaction tamamen rollback olur, cursor kesinlikle ilerlemez. |
| **`RETRY_CLASSIFICATION`** | **PASS** | `isRetryableError` yalnızca `SyncNetworkException`, `SyncTimeoutException` ve `SyncServerException` (5xx) için `true` döner. Kalıcı hatalar (`400`, `401`, `403`, `426`, `SyncFormatException`, `StateError`) **fail-fast** davranarak anında durur, sıfır retry yapar. |
| **`IDEMPOTENCY`** | **PASS** | `sync_applied_events` tablosunda `id = 'sale:${change.entityId}'` ve `'refund:${change.entityId}'` tekil anahtarları mevcuttur. Aynı sayfa veya olay tekrar geldiğinde stok hareketleri ikinci kez tetiklenmez. |
| **`TEST_EVIDENCE`** | **PASS** | `test/core_next/stage10_7_3_pull_worker_test.dart` içindeki 14 testin ve genel `test/core_next/` paketindeki **157/157 testin** tamamının assertion'ları gerçek SQLite FFI ve MockClient ile çalıştırılmış ve doğrulukları teyit edilmiştir. |
| **`RUNTIME_CONSUMER`** | **NO** | `coreSyncPullWorkerProvider` Riverpod DI'da mevcuttur ve testte çözülmektedir; ancak `lib/` dondurulduğu için UI veya canlı satış akışında henüz runtime tüketicisi bulunmamaktadır. |
| **`POSTGRES_INTEGRATION`** | **SKIPPED / BLOCKED** | Sunucu tarafındaki `sync_v4_domain_materialization.test.ts` testi `DROP SCHEMA public CASCADE` içerdiğinden ve izole test DB'si henüz ayrılmadığından çalıştırılmamıştır (Kasıtlı olarak atlanmıştır). |
| **`LIVE_GATE`** | **BLOCKED** | Canlı satış ekranı (`lib/`) entegrasyonu, gerçek PostgreSQL izolasyonu ve runtime arka plan zamanlayıcısı tamamlanana kadar canlıya geçiş kapısı kesin olarak **BLOKE** kalmalıdır. |

---

## 2. DOSYA VE ÇAĞRI ZİNCİRİ ADLİ DENETİMİ

### 2.1. İncelenen Dosyalar
1. `core_next/client_core/lib/infrastructure/sync/sync_v4_pull_worker.dart` (308 satır)
2. `core_next/client_core/lib/infrastructure/sync/sync_v4_http_client.dart` (196 satır)
3. `core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart` (731 satır)
4. `core_next/client_core/lib/domain/models/sync_dtos.dart` (DTO modelleri)
5. `core_next/client_core/lib/presentation/di/core_providers.dart` (Riverpod bağımlılıkları)
6. `server/src/modules/sync_v4/sync-v4.routes.ts` (Sunucu `/pull` ve `/bootstrap` endpointleri)
7. `server/src/modules/sync_v4/sync-v4.materializer.ts` (Event materializer sözleşmeleri)
8. `test/core_next/stage10_7_3_pull_worker_test.dart` (14 zorunlu senaryo testi)
9. `test/core_next/stage10_7_2_identity_safety_test.dart` (8 kimlik güvenliği regresyon testi)

### 2.2. Gerçek Çağrı Zinciri
```
[coreSyncPullWorkerProvider] (core_providers.dart)
       │
       ▼
SyncV4PullWorker.pullAll({maxPages = 50})
       │
       ├── Concurrency Guard: _isRunning (Atomic flag, StateError('pull_worker_busy'))
       │
       ▼ (while hasMore && pages < maxPages)
SyncV4PullWorker.pullSingleBatch()
       │
       ├── [Adım 1: Cursor Oku] ingestionService.getSavedCursor() -> SQLite 'app_settings.sync_pull_cursor'
       │
       ├── [Adım 2: HTTP İsteği] httpClient.pull(cursor: C, limit: pageSize)
       │         └── Sunucu: GET /api/v4/sync/pull?cursor=C&limit=L&device_id=D&device_activation_id=A
       │         └── Retry Döngüsü: Transient hatalarda (5xx, Network, Timeout) maxRetries (3) kadar delay ile retry.
       │         └── Fail-Fast: 400, 401, 403, 426, JSON format hatasında ANINDA sonlanır.
       │
       ├── [Adım 3: Ingestion & Transaction] ingestionService.ingestPull(dto)
       │         └── SQLite: db.transaction((txn) async {
       │               - localDeviceId güvenlik denetimi (Fail-Closed)
       │               - sync_applied_events idempotency kontrolü
       │               - Product, Customer, Sale, Refund mutasyonları
       │               - _saveCursor(txn, dto.nextCursor)  <-- Cursor burada commit sınırında saklanır!
       │             })
       │
       └── [Adım 4: Sayfalama Kontrolü] hasMore = changes.length >= pageSize && changes.isNotEmpty
```

---

## 3. SAYFALAMA VE CURSOR GÜVENLİĞİ DENETİMİ

| Soru | Adli Yanıt | Kanıt Yeri |
| :--- | :---: | :--- |
| **1. Sunucunun gerçek sayfalama ve cursor sözleşmesi doğru kullanılıyor mu?** | **EVET** | Sunucu `sync-v4.routes.ts:377` `WHERE tenant_id = $1 AND revision > $2 ORDER BY revision ASC LIMIT $3` ile `changes` ve `next_cursor` üretir. Worker `pageSize` sınırını `1..500` olarak sınırlar ve `limit` olarak sunucuya aktarır. |
| **2. Önceki sayfanın SQLite transaction'ı tamamlanmadan sonraki sayfaya geçiliyor mu?** | **HAYIR** | `pullAll` içindeki döngü `await pullSingleBatch()` çağrısını bekler. `pullSingleBatch` ise `await ingestionService.ingestPull(dto)` çağrısının SQLite transaction'ı (`await db.transaction(...)`) tamamen diske yazılıp commit olana kadar sonraki döngü adımına geçmez. |
| **3. Cursor kalıcı olarak yalnızca başarılı ingestion sonrasında mı ilerliyor?** | **EVET** | `_saveCursor(txn, nextCursor)` çağrısı `sync_v4_pull_ingestion_service.dart:181` satırında, domain event uygulamalarının bitiminde ve **aynı transaction içinde** yer alır. Herhangi bir hata veya exception durumunda SQLite transaction rollback olur, cursor ilerlemez. (Test 10.7.3.6 kanıtı). |
| **4. Aynı sayfa yeniden geldiğinde `sync_applied_events` mükerrer stok hareketini önlüyor mu?** | **EVET** | `sync_v4_pull_ingestion_service.dart:350` satırında `SELECT id FROM sync_applied_events WHERE id = 'sale:${change.entityId}'` sorgusu yapılır. Kayıt varsa işlem anında `return` edilerek atlanır. (Test 10.7.3.7 kanıtı). |
| **5. Boş sayfa, son sayfa ve tekrarlanan cursor durumları doğru ele alınıyor mu?** | **EVET** | `changes.isEmpty` durumunda worker `hasMore = false` olarak işaretler ve `pullAll` döngüsü `batch.changesFetched == 0` ile sonlanır. Sonsuz döngü riski yoktur. (Test 10.7.3.3 ve 10.7.3.10 kanıtı). |
| **6. Bootstrap sonrasında incremental pull doğru cursor üzerinden devam ediyor mu?** | **EVET** | Sunucu `/bootstrap` yanıtındaki `next_cursor` (`MAX(revision)`), `ingestBootstrap` ile kaydedilir. Ardından gelen ilk `pullSingleBatch`, `getSavedCursor()` üzerinden doğrudan bu revizyondan sonrasını ister. (Test 10.7.3.13 kanıtı). |
| **7. Uygulama yeniden başlatıldığında cursor nereden okunuyor?** | **EVET** | SQLite veritabanındaki `app_settings` tablosundan `key = 'sync_pull_cursor'` anahtarı okunur. Disk kapatılıp açılsa dahi hafıza kaybı yaşanmaz. (Test 10.7.3.9 kanıtı). |
| **8. Sunucudan gelen sayfa cursor'ı ile son uygulanan event arasında kayıp event riski var mı?** | **HAYIR** | Sunucu `next_cursor` olarak sayfadaki son elemanın revizyonunu (`result.rows.at(-1).revision`) verir. Client tüm sayfayı tek bir transaction'da atomik uygular. Kısmi başarı/kısmi başarısızlık söz konusu olamaz; ya tüm sayfa işlenir ve cursor ilerler ya da hiçbiri işlenmez ve cursor eski yerinde kalır. |

---

## 4. RETRY VE HATA SINIFLANDIRMASI ADLİ DENETİMİ

### 4.1. `maxRetries = 3` Semantiği
Kaynak kod incelemesi (`sync_v4_pull_worker.dart:196-215`):
```dart
int attempts = 0;
while (attempts <= maxRetries) {
  try {
    dto = await httpClient.pull(cursor: currentCursor, limit: pageSize);
    break;
  } catch (e) {
    if (!isRetryableError(e) || attempts >= maxRetries) {
      return PullBatchResult.failure(...);
    }
    attempts++;
    if (retryDelay > Duration.zero) {
      await Future.delayed(retryDelay);
    }
  }
}
```
- **İlk İstek:** `attempts = 0`
- **1. Retry:** `attempts = 1`
- **2. Retry:** `attempts = 2`
- **3. Retry:** `attempts = 3`
- **Başarısızlık:** `attempts >= maxRetries` (3 >= 3) -> Döngü biter ve hata döner.
- **Sonuç:** Toplam 1 ilk deneme + 3 yeniden deneme = **4 toplam istek**. Bu durum endüstri standardı retry semantiğiyle tam uyumludur.

### 4.2. Hata Sınıflandırma Tablosu
| Exception | HTTP Kod | Retry Davranışı | Gerekçe |
| :--- | :---: | :---: | :--- |
| `SyncNetworkException` | Soket / Bağlantı | **RETRY** (Geçici) | Ağ kopmaları geçicidir. |
| `SyncTimeoutException` | Zaman aşımı | **RETRY** (Geçici) | Sunucu gecikmesi geçici olabilir. |
| `SyncServerException` (5xx) | 500, 502, 503, 504 | **RETRY** (Geçici) | Sunucu anlık yoğunlukta olabilir. |
| `SyncBadRequestException` | 400 | **FAIL-FAST** (Kalıcı) | İstemci yükü geçersizdir, retry düzeltemez. |
| `SyncUnauthorizedException` | 401 | **FAIL-FAST** (Kalıcı) | Token süresi dolmuş veya geçersizdir. |
| `SyncForbiddenException` | 403 | **FAIL-FAST** (Kalıcı) | Cihaz pasif veya eşleşmiyor (`inactive_or_mismatched_device`). |
| `SyncConflictException` | 409 | **FAIL-FAST** (Kalıcı) | Outbox çakışmasıdır, pull'da beklenmez. |
| `SyncProtocolUpgradeRequiredException` | 426 | **FAIL-FAST** (Kalıcı) | İstemci sürümü eskidir, kod güncellemesi gerekir. |
| `SyncFormatException` | Bozuk JSON | **FAIL-FAST** (Kalıcı) | Ayrıştırma hatası retry ile çözülmez. |
| `StateError('unidentified_local_device')` | Yerel Hata | **FAIL-FAST** (Kalıcı) | Cihaz kimliği yokken veri işlenemez. |

*Önemli Not:* `SyncServerException` sınıfının genel `statusCode` alanı incelenmiştir. `SyncV4HttpClient._handleResponse` metodunda 400, 401, 403, 409 ve 426 durumları için ayrı özel exception sınıfları fırlatıldığından, 4xx hatalarının yanlışlıkla `SyncServerException` içine düşüp retry döngüsüne girmesi engellenmiştir.

---

## 5. SATIŞ, İADE VE KİMLİK GÜVENLİĞİ DENETİMİ

Stage 10.7.2 düzeltmelerinin kaynak kodundaki güncel durumu doğrulanmıştır:

1. **`localDeviceId` Boş / Null Güvenliği (Fail-Closed):**
   `SyncV4PullIngestionService._applyChanges` (satır 98-109):
   `hasDeviceOriginDependentChanges` (satış veya iade içeren bir batch) varsa ve `effectiveDeviceId == null || effectiveDeviceId.isEmpty` ise derhal `StateError('unidentified_local_device')` fırlatılır. Kasa asla kendini yabancı kasa varsayıp kendi stoklarını ikinci kez düşürmez.
2. **`receipt_no` Yabancı Satış Atlama Koruması:**
   `_ingestSale` (satır 377-393):
   Yerel satış eşleştirmesi yalnızca değişmez satış UUID'si (`id = change.entityId`) veya fiş numarasından farklı, açıkça atanmış tekil bir `idempotency_key` üzerinden yapılır. Kasa B tesadüfen aynı formatta `REC-COMMON-100` fiş numarası üretse bile, bu yabancı satış atlanmaz; stok atomik olarak düşürülür.
3. **İade Olayının Orijinal Satışla Karıştırılmaması:**
   `_ingestRefund` (satır 478-490):
   İade eşleştirmesi yapılırken yerel veritabanında `status = 'REFUND'` filtresi aranır. Yabancı kasanın yaptığı bir iade olayındaki `sale_id`, yereldeki tamamlanmış orijinal satış (`status = 'COMPLETED'`) ile karıştırılmaz; stok atomik olarak artırılır.
4. **Çift Yönlü Rollback Garantisi:**
   Stok güncellemesi (`UPDATE products SET stock_quantity = ...`) ile olay günlüğü (`INSERT INTO sync_applied_events ...`) aynı transaction içerisindedir. Biri başarısız olursa ikisi birden geri alınır.

---

## 6. 14 TESTİN GERÇEK KANIT DEĞERİ (FORENSIC BREAKDOWN)

`test/core_next/stage10_7_3_pull_worker_test.dart` içindeki testler adli olarak incelenmiştir:

| Test No | Test Adı | Başlangıç Durumu | Çağrılan Metot | Gerçek Assertion | Ne İspatlar? | Ne İspatlayamaz? |
| :---: | :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | Tek sayfalı pull başarılı | Stok: 30, Cursor: 0 | `worker.pullAll()` | `stock == 25`, `cursor == 10`, `totalBatches == 1` | Ingestion ve tekil batch entegrasyonu | Ağ gecikmesi ve soket kesintisi |
| **2** | Birden fazla sayfa döngüsü | Stok: 30, PageSize: 2 | `worker.pullAll(maxPages: 10)` | `requestCount == 2`, `totalChanges == 3`, `stock == 24`, `cursor == 8` | Çok sayfalı sayfalama döngüsü ve cursor zinciri | Sayfa sayısı > 50 durumundaki bellek tüketimi |
| **3** | Son sayfada durma | PageSize: 5, Gelen: 1 | `worker.pullAll()` | `calls == 1`, `hasMoreRemaining == false` | `changes.length < pageSize` durumunda gereksiz ek HTTP isteği atılmaması | Sunucunun hatalı limit dönmesi |
| **4** | Ağ hatası ve retry | 1. deneme: ClientException, 2. deneme: 200 OK | `worker.pullAll()` | `attempts == 2`, `isSuccess == true`, `cursor == 20` | Geçici ağ kopmasında retry mekanizmasının devreye girmesi | Jitter ve exponential backoff süreleri |
| **5** | Kalıcı hata fail-fast | Mock: 403 Forbidden | `worker.pullAll()` | `attempts == 1`, `isPermanentError == true` | 403 hatasında ASLA retry yapılmadığı ve hemen durduğu | Token yenileme / refresh mekanizması |
| **6** | ACID Rollback | Bozuk veri (`quantity: 'invalid_string'`) | `worker.pullSingleBatch()` | `isSuccess == false`, `cursor == 0`, `stock == 30` | Ingestion patladığında SQLite'ın rollback olduğu ve cursor'ın ilerlemediği | İşletim sistemi disk bozulması |
| **7** | Idempotency | Batch 1: stok 30->27. Batch 2: Replay (aynı sayfa) | `worker.pullSingleBatch(cursorOverride: 0)` | `stock == 27` (ikinci kez düşmedi) | `sync_applied_events` tablosunun mükerrer stoğu engellediği | Çoklu işletim sistemi proses çakışması |
| **8** | Concurrency Lock | İlk istek Completer ile bekletilir | 2x `worker.pullAll()` | `throwsA(isA<StateError>())`, `message contains 'pull_worker_busy'` | Aynı worker örneğinin eşzamanlı iki kez çalıştırılamayacağı | Farklı proseslerin aynı SQLite dosyasını açması |
| **9** | Restart persistence | Cursor 55 yazılır. `coreDb.close()` yapılır, diskten tekrar açılır | `worker2.pullSingleBatch()` | `requestedCursor == 55` | Cursor'ın in-memory değil, SQLite `app_settings` disk tablosunda kalıcılaştığı | Güç kesintisinde FSync davranışı |
| **10** | Boş sayfa sonlanması | Mock: `changes: []`, `next_cursor: 70` | `worker.pullAll()` | `totalBatches == 1`, `totalChanges == 0`, `hasMore == false` | Boş sayfa geldiğinde döngünün kilitlenmeden bittiği | Negatif cursor ile gelen sunucu hatası |
| **11** | Fail-Closed cihaz kimliği | `localDeviceId: null` | `worker.pullAll()` | `isSuccess == false`, `error contains 'unidentified_local_device'`, `cursor == 0` | Cihaz kimliği yokken verilerin işlenmeyip güvenli şekilde durduğu | Cihaz kimliğinin JWT içinde doğrulanması |
| **12** | Kimlik güvenliği (Satış / İade) | Yerel satış: `REC-W-100`. Batch: Kendi satışı, Yabancı satış (`REC-W-100`), Yabancı iade | `worker.pullAll()` | `stock == 29` (30 - 0 - 2 + 1 = 29) | Stage 10.7.2 düzeltmelerinin korunduğu; `receipt_no` çakışmasında yabancı satışın atlanmadığı | Kısmi iade senaryoları |
| **13** | Bootstrap cursor geçişi | Bootstrap: `next_cursor: 100`. Ardından pull çağrısı | `worker.bootstrap()`, sonra `worker.pullSingleBatch()` | `pullCursorReceived == 100` | Bootstrap ardından gelen ilk pull'un 0'dan değil, bootstrap revizyonundan devam ettiği | Çok yüksek hacimli bootstrap snapshot bellek baskısı |
| **14** | Hata sınıflandırması & DI | 7 exception türü sorgulanır. Riverpod Container `read(coreSyncPullWorkerProvider)` | `container.read(...)` | `isRetryableError` doğrulaması + Worker ve bağımlılıkların DI'da hatasız ayağa kalkması | DI grafiğinde tip veya bağımlılık hatası bulunmadığı | Canlı Flutter widget ağacı yaşam döngüsü |

---

## 7. ÇALIŞTIRILAN KOMUTLAR VE ADLİ ÇIKTILAR

### 7.1. Stage 10.7.3 Testleri
```
Command: flutter test test/core_next/stage10_7_3_pull_worker_test.dart
Result: Exit Code 0
Output: 00:00 +14: All tests passed! (14/14 BAŞARILI)
```

### 7.2. Stage 10.7.2 Kimlik Güvenliği Testleri
```
Command: flutter test test/core_next/stage10_7_2_identity_safety_test.dart
Result: Exit Code 0
Output: 00:00 +8: All tests passed! (8/8 BAŞARILI)
```

### 7.3. Tüm `core_next` Süiti Regresyon Denetimi
```
Command: flutter test test/core_next/
Result: Exit Code 0
Output: 00:37 +157: All tests passed! (157/157 BAŞARILI)
```
- **Toplam Test Dosyası:** 20 test dosyası
- **Toplam Başarılı Test:** 157
- **Kırılan / Başarısız Test:** 0 (SIFIR)

### 7.4. Git Ağacı ve Dizin Bütünlüğü Denetimi
- `git rev-parse HEAD`: `28c158d88028f139e93f78982d4651ad424c61d2`
- `git diff --check`: Temiz (0 sözdizimi / whitespace hatası)
- `git status --short`:
  - `lib/` klasörü altında: **0 satır değişiklik, 0 dosya eklendi/silindi (%100 DOKUNULMAMIŞ)**.
  - Değiştirilen izlenen dosyalar: Yalnızca sunucu tarafındaki `sync-v4.materializer.ts` ve `sync-v4.routes.ts`.
  - Hiçbir `git commit`, `git push` veya `git add` çalıştırılmamıştır.

---

## 8. RUNTIME TÜKETİCİSİ VE CANLI ENTEGRASYON DURUMU

| Katman | Mevcut Durum | Açıklama |
| :--- | :---: | :--- |
| **Worker Sınıfı** | **TAMAMLANDI** | `SyncV4PullWorker` tüm sorumluluklarıyla çalışmaktadır. |
| **Riverpod Provider** | **TANIMLANDI & DOĞRULANDI** | `coreSyncPullWorkerProvider` bağımlılıklarıyla çözümlenmektedir. |
| **Otomatik Testler** | **%100 BAŞARILI** | 14 adli test senaryosuyla tüm edge case'ler doğrulanmıştır. |
| **Runtime Tüketicisi (Background Timer/Coordinator)** | **YOK** | Outbox push tamamlandığında veya belirli periyotlarda worker'ı tetikleyecek bir background coordinator henüz yazılmamıştır. |
| **Canlı Satış Ekranı (`lib/`) Entegrasyonu** | **YOK** | Sınırlar gereği `lib/` canlı uygulamasına müdahale edilmemiştir. |

---

## 9. GERÇEK POSTGRESQL ENTEGRASYONUNUN DURUMU

- **Mevcut Durum:** **SKIPPED / BLOCKED (TEST EDİLMEMİŞ)**
- **Gerekçe:** Sunucu tarafındaki `server/src/test/sync_v4_domain_materialization.test.ts` entegrasyon testi `DROP SCHEMA public CASCADE` komutunu barındırmaktadır. Güvenli, izole bir geçici Docker PostgreSQL veritabanı ayrılmadan bu testin çalıştırılması mevcut veritabanını yok edeceğinden kesinlikle yasaklanmıştır.
- **Güvenlik Tedbiri:** Tüm istemci testleri izole SQLite FFI ve Mock HTTP istemcisiyle yürütülmüştür. Gerçek PostgreSQL entegrasyonu ancak izole test veritabanı sağlandığında Stage 10.8 kapsamında ele alınmalıdır.

---

## 10. BULGULAR VE ÖNEM DERECELERİ

| ID | Bulgu | Seviye | Durum / Eylem |
| :---: | :--- | :---: | :--- |
| **B-01** | `lib/` canlı uygulamasında Pull Worker için henüz bir runtime UI veya background timer tüketicisi bulunmamaktadır. | **P2** | **Kasıtlı Mimari Sınır:** Bu aşamanın sınırları gereği `lib/` dondurulmuştur. Canlıya geçiş öncesinde Stage 10.7.4 / Stage 10.8'de bir `SyncCoordinator` ile bağlanmalıdır. |
| **B-02** | `server/src/test/sync_v4_domain_materialization.test.ts` testi `DROP SCHEMA public CASCADE` içerdiği için izole test DB'si olmadan çalıştırılamaz. | **P1** | **Kasıtlı Güvenlik Tedbiri:** Çalıştırılması engellenmiş, durum raporda `SKIPPED / BLOCKED` olarak kayda geçirilmiştir. |
| **B-03** | `SyncV4PullWorker` tekil proses eşzamanlılığını `_isRunning` ile engeller; ancak aynı SQLite veritabanını açan iki bağımsız işletim sistemi prosesi (multi-process) durumunda SQLite tablo kilidi dışında OS seviyesi mutex barındırmaz. | **P3** | Flutter masaüstü ve Android tekil proses (single-instance) olarak çalıştığı için mevcut mimaride risk düşüktür; ancak çoklu pencere mimarisine geçilirse dosya tabanlı kilit eklenmelidir. |

*Sonuç olarak kodda düzeltme gerektiren kanıtlanmış bir P0 veya P1 mantık/güvenlik hatası bulunmamaktadır. Kod sırf değişiklik üretmek adına değiştirilmemiştir.*

---

## 11. SONUÇ VE SONRAKİ AŞAMA ÖNERİSİ

Stage 10.7.3 kapsamında oluşturulan `SyncV4PullWorker`, sunucunun gerçek `/api/v4/sync/pull` ve `/api/v4/sync/bootstrap` sözleşmelerine tam uyumlu, ACID transaction sınırında cursor kalıcılaştıran, fail-fast/fail-closed hata sınıflandırmasına sahip ve 157 testin tamamında sıfır regresyonla çalışan sağlam bir çekirdektir.

**Sonraki Aşama (Stage 10.7.4) İçin Öneriler:**
1. **Sync Coordinator (Eşgüdüm Katmanı):** Outbox processor (push) ile Pull worker (pull) arasındaki çalışma sırasını yöneten (önce push, sonra pull), ağ durumunu izleyen ve periyodik tetikleme yapan bir `SyncCoordinator` tasarlanması.
2. **İzole Test Veritabanı:** PostgreSQL entegrasyon testlerinin güvenle koşulabilmesi için izole Docker ortamının kurulması.
3. **Canlı Geçiş Kapısı:** `LIVE_GATE = BLOCKED` durumu, runtime tüketicisi ve canlı kabul testleri bitene kadar korunmalıdır.
