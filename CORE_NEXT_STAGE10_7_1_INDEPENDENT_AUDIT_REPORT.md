# SERENUT OS — STAGE 10.7.1
## BAĞIMSIZ REGRESYON VE KANIT TUTARLILIĞI ADLİ DENETİM RAPORU

**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.7.1 — Bağımsız Adli Denetim ve Doğrulama  
**Hedef Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Canlıya Geçiş Durumu:** ⛔ **ENGELLENDİ (BLOCKED)**  

---

## 1. YÜRÜTME ÖZETİ VE ÇALIŞMA SINIRLARINA UYUM BEYANI

Bu denetim, Stage 10.7 raporunda yer alan istemci güvenliği, outbox dead-letter yönetimi, yerel satış eşleştirmesi, migration ve test sonuçlarının bağımsız adli incelemesidir.

### Kesin Çalışma Sınırları Denetimi
- **Salt Okunur İnceleme:** Kaynak kodda, test dosyalarında veya migration scriptlerinde hiçbir değişiklik yapılmamıştır.
- **Canlı Satış Uygulaması (`lib/`):** `lib/` dizinine kesinlikle dokunulmamış, tek bir satır dahi değiştirilmemiştir (`%100` salt okunur).
- **Canlı API ve Veritabanı:** Canlı API veya PostgreSQL veritabanına bağlantı kurulmamıştır.
- **Yıkıcı Test Engeli:** `DROP SCHEMA public CASCADE` komutu barındıran `server/src/test/sync_v4_domain_materialization.test.ts` dosyası kesinlikle çalıştırılmamıştır.
- **Git Bütünlüğü:** `git commit`, `git push`, `git add` veya deploy komutları çalıştırılmamıştır.
- **Kanıt Standardı:** Önceki raporlardaki ifadeler tek başına kanıt kabul edilmemiş; gerçek dosya satırları, SQLite FFI çıktıları ve terminal sonuçları esas alınmıştır.

---

## 2. TEST SAYISI VE RAPOR DOĞRULUĞU DENETİMİ

### 2.1. Stage 10.7 Test Dosyasındaki Gerçek `group()` ve `test()` Sayısı
İncelenen dosya: [`test/core_next/stage10_7_client_safety_test.dart`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_7_client_safety_test.dart)

- **`group()` Sayısı: 3 Adet**
  1. Satır 33: `group('STAGE 10.7 — P0: İstemci Pull Ingestion ve Yerel Satış Güvenliği', ...)`
  2. Satır 327: `group('STAGE 10.7 — P0: Outbox Dead-Letter ve Payload Çatışma Yönetimi', ...)`
  3. Satır 608: `group('STAGE 10.7 — Watermark, Delta ve Migration Doğrulamaları', ...)`
- **`test()` Fonksiyon Çağrısı Sayısı: 16 Adet**
  - **Grup 1 (8 test):**
    - L65: `10.7.1.1: Doğru cihaz kimliğiyle kendi satışını tekrar uygulamama (tek stok düşümü)`
    - L98: `10.7.1.2: localDeviceId == null durumunda güvenli başarısızlık (StateError ve no-op)`
    - L135: `10.7.1.3: Boş veya yalnızca boşluk içeren localDeviceId güvenli başarısızlık vermelidir`
    - L162: `10.7.1.4: Aynı satış olayının iki kez gelmesi (Tekrar uygulama koruması)`
    - L192: `10.7.1.5: Uygulama yeniden başlatıldıktan sonra aynı olayın gelmesi (Kalıcı Idempotency)`
    - L224: `10.7.1.6: Sunucu satış IDsi farklı olsa dahi receipt_no / idempotency_key eşleşmesiyle yerel satış korunmalı`
    - L265: `10.7.1.7: Hata durumunda SQLite transaction rollback garantisi ve cursor ilerlememe`
    - L285: `10.7.1.8: Kendi iadesini tekrar uygulamama (Refund local origin protection)`
  - **Grup 2 (6 test):**
    - L362: `10.7.2.1 & 10.7.2.2: sale_payload_conflict ve mutation_payload_conflict terminal REJECTED durumuna alınmalı` *(İki kural tek bir `test()` bloğunda birleştirilmiştir)*
    - L405: `10.7.2.3: REJECTED mutasyonlar sonraki worker çalışmasında tekrar gönderilmemelidir`
    - L442: `10.7.2.4: Uygulama yeniden başlatıldığında REJECTED durumu korunmalı ve listelenebilmeli`
    - L491: `10.7.2.5: Geçici ağ ve sunucu 5xx hatalarında TRANSIENT_ERROR korunmalıdır`
    - L518: `10.7.2.6: HTTP 409 Çatışma Ayrımı: Bilinmeyen kod TRANSIENT_ERROR, doğrulanmış kod REJECTED olmalıdır`
    - L569: `10.7.2.7: Başarılı gönderimin mevcut davranışı korunmalıdır (SYNCED)`
  - **Grup 3 (2 test):**
    - L631: `10.7.3.1: Satış + İade kombinasyonunda effectiveStock formülü matematiksel doğruluğu`
    - L696: `10.7.3.2: Şema migration v2 -> v3 yükseltmesi ve onUpgrade idempotency`

### 2.2. Gerçek Test Çalıştırma Çıktıları

1. **Komut:** `flutter test test/core_next/stage10_7_client_safety_test.dart`
   - **Çıkış Kodu:** 0
   - **Terminal Sonucu:** `00:01 +16: All tests passed!` (16/16 Başarılı).
2. **Komut:** `flutter test test/core_next/`
   - **Çıkış Kodu:** 0
   - **Terminal Sonucu:** `00:36 +135: All tests passed!` (135/135 Başarılı).

### 2.3. Raporlardaki Sayıların Adli Analizi (16, 17, 118, 135)

| Sayı | Durum | Adli Tespit ve Gerekçe |
|---|---|---|
| **16** | **DOĞRULANDI** | `test/core_next/stage10_7_client_safety_test.dart` içindeki gerçek `test()` fonksiyonu sayısıdır. Komut koşturulduğunda `+16` olarak raporlanır. |
| **17** | **KISMEN DOĞRULANDI** | Test dosyasında tanımlanan **kural ve senaryo etiketi** sayısı 17'dir (`10.7.1.1` - `10.7.1.8`: 8 adet; `10.7.2.1` - `10.7.2.7`: 7 adet; `10.7.3.1` - `10.7.3.2`: 2 adet = 17 etiket). Ancak L362'de `10.7.2.1 & 10.7.2.2` tek bir `test()` fonksiyonunda birleştirildiği için test yürütücüsü 16 test sayar. Metinlerde 17 geçmesi senaryo etiketleme sayısından kaynaklanmaktadır. |
| **118** | **DOĞRULANMADI** | Stage 10.6 kapanış raporundaki gerçek test sayısı 118 değil, **119**'dur (`CORE_NEXT_STAGE10_6_SYNC_CONVERGENCE_REPORT.md:111: 119/119 test başarılı`). 118 sayısı, 135 toplamından 17 etiket çıkarılarak yapılan hatalı bir matematiksel türetmedir ($135 - 17 = 118$). Gerçek baz $135 - 16 = 119$'dur. |
| **135** | **DOĞRULANDI** | `test/core_next/` dizinindeki 18 test dosyasının çalıştırılması sonucunda Flutter test motorunun raporladığı gerçek toplam test sayısıdır ($119 + 16 = 135$). |

---

## 3. CİHAZ KİMLİĞİ VE DI BAĞLANTISI DENETİMİ

İncelenen dosyalar:
- [`core_next/client_core/lib/presentation/di/core_providers.dart`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/presentation/di/core_providers.dart)
- [`core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart)
- [`core_next/client_core/lib/infrastructure/sync/sync_v4_http_client.dart`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_http_client.dart)

### 3.1. DI Zincirinin Kapanma Durumu
- **`coreDeviceIdProvider`:** `core_providers.dart:73-77` satırlarında tanımlanmıştır. Sadece `coreSyncPullIngestionServiceProvider` (L82) tarafından `ref.watch(coreDeviceIdProvider)` ile okunmaktadır.
- **`coreSyncPullIngestionServiceProvider`:** `core_providers.dart:80-84` satırlarında tanımlanmıştır.
- **Kritik Adli Bulgu (P1 — Dormant Provider):**
  Ne `core_next/` içerisinde, ne de `lib/` altında hiçbir presentation controller, notifier, repository veya worker sınıfı `coreSyncPullIngestionServiceProvider` veya `coreDeviceIdProvider` sağlayıcılarını `ref.watch()` veya `ref.read()` ile **çağırmamaktadır**.
  Projede periyodik veya olay tabanlı bir `PullWorker` / `PullController` henüz yazılmamıştır. `ingestPull()` fonksiyonu yalnızca test dosyalarında elle `SyncV4PullIngestionService(...)` örneği oluşturularak çağrılmaktadır.
  **Sonuç: DI zinciri henüz üretim çalışma zamanına (runtime flow) bağlanmamıştır, atıl (dormant) durumdadır.**

### 3.2. Cihaz Kimliğinin Kalıcılığı ve Üretim Oluşturucusu
- `core_next` modülünde bağımsız bir `DeviceId` yönetim servisi veya SharedPreferences kalıcılık katmanı henüz oluşturulmamıştır.
- `core_providers.dart:75` içinde `coreDeviceIdProvider`'ın açılışta `overrideWithValue` ile beslenmesi zorunlu kılınmıştır; aksi halde `UnimplementedError` fırlatır.
- `SyncV4PullIngestionService` kurucusunda `localDeviceId` parametresi opsiyoneldir: `const SyncV4PullIngestionService(this.db, {this.localDeviceId});`. Bir geliştirici veya servis doğrudan kurucuyu çağırdığında derleme hatası almaz, ancak `localDeviceId` null kalır.

### 3.3. Fail-Safe Denetimi ve Cursor İlerlemesi
[`sync_v4_pull_ingestion_service.dart:97-109`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L97-L109):
```dart
final effectiveDeviceId = localDeviceId?.trim();
final hasDeviceOriginDependentChanges = changes.any((c) {
  final t = c.entityType.toLowerCase();
  return t == 'sale' || t == 'refund';
});

if (hasDeviceOriginDependentChanges && (effectiveDeviceId == null || effectiveDeviceId.isEmpty)) {
  throw StateError(
    'SyncV4PullIngestionService: Cihaz kimliği (localDeviceId) eksik veya geçersiz. '
    'Satış ve iade olayları yabancı cihaz varsayımıyla güvenli olmayan biçimde işlenemez (unidentified_local_device).',
  );
}
```
- **Doğrulama:** Bu kontrol `_applyChanges` fonksiyonunun en başında, veritabanı transaction'ına (L121) dahi girmeden önce çalışır.
- `localDeviceId` null, boş (`''`) veya boşluklardan (`'   '`) oluşuyorsa ve batch içinde `sale` veya `refund` varsa, `StateError('unidentified_local_device')` fırlatılır.
- Hiçbir stok hareketi yapılmaz ve `_saveCursor` çağrılmadığı için cursor kesinlikle ilerlemez (**DOĞRULANDI**).
- **Fail-safe Atlatılabilir mi?** Alternatif oluşturucu veya doğrudan çağrılar bu denetimi atlatamaz; servis daima `_applyChanges` üzerinden geçer. Ancak atlatılamaması, DI eksikliği durumunda uygulamanın pull yapamayarak sürekli hata vermesine yol açar.

---

## 4. YEREL SATIŞ EŞLEŞTİRMESİ VE STOK BÜTÜNLÜĞÜ DENETİMİ

İncelenen kod blokları:
- `_ingestSale` ([`sync_v4_pull_ingestion_service.dart:347-385`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L347-L385))
- `_ingestRefund` ([`sync_v4_pull_ingestion_service.dart:440-479`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L440-L479))
- `buildSaleMutation` ([`sync_v4_payload_adapter.dart:26-140`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_payload_adapter.dart#L26-L140))
- `upsertSale` ([`server/src/modules/sync_v4/sync-v4.materializer.ts:163-271`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L163-L271))

### 4.1. Eşleştirme Alanlarının Adli Analizi

1. **`id` (Entity ID):**
   - İstemcide `CoreCheckoutUseCase` (L87) tarafından `_uuid.v4()` ile üretilir.
   - Sunucuya `SyncMutation.entity_id` olarak iletilir.
   - Sunucu `upsertSale` fonksiyonunda `INSERT INTO sales (id, ...) VALUES ($1, ...)` olarak aynı UUID kullanılır.
   - Normal akışta yerel ve sunucu ID'leri birebir aynıdır.
2. **`receipt_no` Kapsamı ve Varlık Durumu (Kritik Bulgu):**
   - Yerel SQLite şemasında (`schema_definitions.dart:81`): `receipt_no TEXT UNIQUE NOT NULL`.
   - **Sunucu Tarafında Fiş No Yoktur:** PostgreSQL `sales` tablosunda ve `sync_v4_changes` günlüğünde `receipt_no` kolonu bulunmamaktadır!
   - **İstemci Payload Adaptörü Fiş No Göndermemektedir:** `SyncV4PayloadAdapter.buildSaleMutation` metodunda (L121-131) payload nesnesi hazırlanırken `receipt_no` parametresi alınmasına rağmen **JSON payload'a dahil edilmemiştir**.
   - Sonuç: Gerçek sunucudan pull edilen `sale` veya `refund` olaylarında `change.payload['receipt_no']` daima `null` gelir!
3. **`idempotency_key` Kapsamı:**
   - İstemcide `CheckoutRequest.idempotencyKey ?? receiptNo` olarak atanır.
   - Yerel SQLite'ta `UNIQUE` kısıtına sahiptir.
   - Sunucuda `sales.idempotency_key` olarak saklanır ve `sync_v4_changes` payload'ına girer.
4. **Eşleşme Alanları Sırası ve Önceliği:**
   [`sync_v4_pull_ingestion_service.dart:372-383`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L372-L383):
   ```sql
   SELECT id FROM sales 
   WHERE id = ? 
      OR (receipt_no IS NOT NULL AND receipt_no = ?)
      OR (idempotency_key IS NOT NULL AND idempotency_key = ?)
   LIMIT 1
   ```
   Sorguda SQL `OR` kullanıldığı için alanlar arasında öncelik hiyerarşisi yoktur; koşullardan herhangi biri eşleştiğinde `existingLocalSales.isNotEmpty` olur ve `isLocalOrigin = true` kabul edilir.

### 4.2. Yalancı Pozitif (False Positive) ve Stok Atlama Riski (P1 Risk)
- **Soru:** Sadece fiş numarası eşleştiği için yabancı bir satışın stok hareketi atlanabilir mi?
- **Adli Yanıt: EVET.**
  Eğer iki kasa bağımsız olarak aynı formatta fiş üretiyorsa (ör. her iki kasa da gün başlangıcında `REC-001` üretirse) veya test ortamlarında olduğu gibi payload'a `receipt_no` enjekte edilirse:
  Kasa B'nin yaptığı satış Kasa A'ya ulaştığında, Kasa A'nın yerel `sales` tablosunda aynı fiş numarasına sahip kendi eski bir satışı bulunuyorsa sorgu eşleşir (`LIMIT 1`).
  Kasa A bu satışı "kendi satışı" zannederek stok düşümünü **atlar**. Kasa B'nin sattığı ürün Kasa A'da rafta var görünmeye devam eder.

### 4.3. İade Olayı ve Satış Ayrımı
- `_ingestRefund` sorgusunda `WHERE status = 'REFUND'` filtresi bulunmaktadır. Bu nedenle orijinal satışın (`status = 'COMPLETED'`) fiş numarasıyla çakışma yaşanmaz.
- İade kimliği (`change.entityId`) ile orijinal satış kimliği sunucuda ve istemcide doğru ayrıştırılmıştır.
- Ancak iki farklı kasanın yaptığı iadeler aynı fiş no (`REF-REC-01`) taşırsa, Kasa B'nin iadesi Kasa A'da yerel sayılarak stok artırımı atlanabilir.

### 4.4. 6 Senaryonun Mevcut Testlerdeki Durumu

| No | Senaryo | Test Durumu | Detay ve Kanıt |
|---|---|---|---|
| 1 | Aynı fiş numarasına sahip iki farklı işletme/şube | **TEST EDİLMEDİ** | Test süitinde şube veya çok kiracılı fiş çakışması testi yoktur. |
| 2 | Aynı fiş numarasına sahip farklı cihaz satışları | **TEST EDİLMEDİ** | Farklı cihazların aynı `receipt_no` ile satış yapıp stok düşümünün atlanması riski sınanmamıştır. |
| 3 | Yerel satışın sunucu ID'siyle farklı ID taşıması | **DOĞRULANDI** | `stage10_7_client_safety_test.dart:224` (Test 10.7.1.6) senaryoyu doğrulamıştır. |
| 4 | Yerel satışın idempotency anahtarının null olması | **TEST EDİLMEDİ** | Şemada `idempotency_key` nullable olmasına rağmen null olduğu durum için pull testi yoktur. |
| 5 | Yabancı satışın yanlışlıkla yerel satışla eşleşmesi | **TEST EDİLMEDİ** | Yalancı pozitif (false positive) koruması ve sınırları test edilmemiştir. |
| 6 | Aynı satışa ait iade olayının iki kez gelmesi | **KISMEN DOĞRULANDI** | Kendi iadesi (Test 10.7.1.8) ve Kasa B iadesinin 2 kez pull edilmesi (Test B) test edilmiştir; ancak parçalı iade mükerrerliği sınanmamıştır. |

---

## 5. OUTBOX HATA SINIFLANDIRMASI VE DEAD-LETTER DENETİMİ

İncelenen akış:
`Sunucu HTTP Yanıtı` → `SyncV4HttpClient._handleResponse` → `SyncException Türevleri` → `SyncV4OutboxProcessor.processOutbox` → `sync_events Tablosu` → `Sonraki Döngü / Restart`.

### 5.1. Hata Kodlarına Göre Davranış Matrisi

| Hata / Senaryo | HTTP Kodu | Fırlatılan İstisna Sınıfı | Kalıcı `sync_state` | `last_error` Saklanması | Sonraki Döngüde / Yeniden Başlatmada Tekrar Gönderilir mi? |
|---|---|---|---|---|---|
| `sale_payload_conflict` | 200 (JSON rejected) veya 409 | `SyncConflictException` (errorCode: `sale_payload_conflict`) | **`REJECTED`** | `sale_payload_conflict` | **HAYIR.** `where: "sync_state IN ('PENDING', 'TRANSIENT_ERROR')"` filtresine takılmaz; kuyruktan çıkar. |
| `mutation_payload_conflict` | 200 (JSON rejected) veya 409 | `SyncConflictException` (errorCode: `mutation_payload_conflict`) | **`REJECTED`** | `mutation_payload_conflict` | **HAYIR.** Terminal dead-letter'a alınır, sonsuz döngü engellenir. |
| `refund_actor_required` | 200 (JSON rejected) veya 409 | `SyncConflictException` (errorCode: `refund_actor_required`) | **`REJECTED`** | `refund_actor_required` | **HAYIR.** Terminal listeye eklenmiştir, tekrar denenmez. |
| Bilinmeyen HTTP 409 | 409 | `SyncConflictException` (errorCode: bilinmeyen veya null) | **`TRANSIENT_ERROR`** | HTTP hata mesajı | **EVET.** Körlemesine reddedilmez; güvenle yeniden deneme kuyruğunda tutulur. |
| HTTP 500 / 502 / 503 / 504 | 5xx | `SyncServerException` (HTTP status ile) | **`TRANSIENT_ERROR`** | `SyncServerException: HTTP 500` | **EVET.** Sunucu veya DB geçici kilitlenmesi kabul edilir, tekrar denenir. |
| Timeout / Ağ Kesintisi | N/A | `SyncTimeoutException` / `SyncNetworkException` | **`TRANSIENT_ERROR`** | Zaman aşımı / bağlantı hatası mesajı | **EVET.** Bağlantı geldiğinde bir sonraki döngüde tekrar gönderilir. |

### 5.2. `REJECTED` ve `getRejectedMutations()` Kullanımı
- `REJECTED` mutasyonlar `sync_events` tablosunda kalıcı olarak korunur.
- [`sync_v4_outbox_processor.dart:266-273`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart#L266-L273):
  `getRejectedMutations()` fonksiyonu `SELECT * FROM sync_events WHERE sync_state = 'REJECTED'` sorgusu yapar.
  `retryRejectedMutation(eventId)` ise mutasyonu tekrar `PENDING` durumuna alır.
- **Kritik Tespit:** Bu metodlar testlerde eksiksiz çalışmakta ve doğrulanmaktadır; ancak şu an projede bu fonksiyonları çağıran bir UI ekranı veya admin paneli bulunmamaktadır.

---

## 6. MİGRATİON DOĞRULAMASI DENETİMİ

İncelenen dosyalar:
- [`core_next/client_core/lib/infrastructure/database/schema_definitions.dart:256-312`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/schema_definitions.dart#L256-L312)
- [`core_next/client_core/lib/infrastructure/database/app_database.dart:42-55`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/app_database.dart#L42-L55)
- [`test/core_next/stage10_7_client_safety_test.dart:696-746`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_7_client_safety_test.dart#L696-L746)

### 6.1. Migration Akışı ve Veri Bütünlüğü
1. **v2 Veritabanı Kayıtlarının Korunması:**
   - `CoreSchemaDefinitions.migrate(db, oldVersion, newVersion)` fonksiyonu v2'den v3'e geçerken (`oldVersion < 3` bloğu L292-311):
     `CREATE TABLE IF NOT EXISTS sync_applied_events (...)` ve ilgili indeksleri çalıştırmaktadır.
     Mevcut tablolara (`products`, `sales`, `customers`, `sync_events`) dokunulmaz, hiçbir veri silinmez veya değiştirilmez (**DOĞRULANDI**).
2. **Gerçek Migration Testinin İncelenmesi:**
   - Test 10.7.3.2 ([`stage10_7_client_safety_test.dart:696`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_7_client_safety_test.dart#L696)):
     1. Diskte geçici bir SQLite dosyası oluşturur.
     2. `openDatabase(path, version: 2, ...)` ile v2 şemasını ayağa kaldırır ve `products` tablosuna `'p-mig-1'` id'li gerçek ürün kaydı ekler.
     3. Veritabanını kapatır.
     4. `CoreAppDatabase.open(inMemoryOrCustomPath: path)` ile `version: 3` olarak açar. Bu işlem sqflite'ın `onUpgrade` kancasını (`CoreSchemaDefinitions.migrate(db, 2, 3)`) tetikler.
     5. `sqlite_master` üzerinden `sync_applied_events` tablosunun oluştuğunu ve önceden eklenen `'p-mig-1'` ürününün bozulmadan korunduğunu assert eder.
   - **Sonuç:** Migration testi yalnızca yeni bir DB oluşturup v3 tablosunu kontrol etmekle yetinmemiş; gerçek bir v2 -> v3 yükseltme sürecini veri içeren bir veritabanı üzerinde başarıyla yürütmüştür (**DOĞRULANDI**).
3. **Migration İdempotency:**
   - Test satır 742'de `CoreSchemaDefinitions.migrate(dbV3.db, 2, 3)` fonksiyonunu ikinci kez çağırmış; `CREATE TABLE IF NOT EXISTS` ve `CREATE INDEX IF NOT EXISTS` yapıları sayesinde hiçbir hata almadan başarıyla sonuçlandığı kanıtlanmıştır (**DOĞRULANDI**).

---

## 7. GİT VE ÇALIŞMA AĞACI KAPSAMI DENETİMİ

Çalıştırılan komutlar ve doğrulanmış terminal çıktıları:

### 7.1. HEAD Commit ve Ağaç Durumu
- **`git rev-parse HEAD`:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **`git diff --check`:** Temiz (Format veya whitespace hatası yok).
- **`git diff --stat`:**
  ```text
  server/src/modules/sync_v4/sync-v4.materializer.ts | 39 ++++++++++++++++++++--
  server/src/modules/sync_v4/sync-v4.routes.ts       |  6 +++-
  2 files changed, 41 insertions(+), 4 deletions(-)
  ```
- **Tracked Değişiklikler:** Yalnızca `server/src/modules/sync_v4/` altındaki 2 dosya üzerinde Stage 10.6'dan devralınan 41 satırlık savepoint ve hata işleme düzenlemesidir.
- **`lib/` Canlı Satış Ekranı:**
  `git status --short --untracked-files=all` çıktısında `lib/` altında **hiçbir değişiklik ve hiçbir untracked dosya yoktur**. Canlı kod %100 salt okunur korunmuştur.
- **Untracked Dosyalar:**
  Rapor dosyaları, `core_next/` kaynakları ve `test/core_next/` test dosyalarıdır.

---

## 8. NİHAİ DEĞERLENDİRME, BULGULAR VE CANLIYA GEÇİŞ KARARI

### 8.1. Bulgular Özeti Tablosu

| İnceleme Alanı | İddia / Kural | Sonuç Sınıfı | Kanıt ve Gerekçe |
|---|---|---|---|
| **Test Sayısı (Stage 10.7)** | 16 test çalıştırıldı ve geçti | **DOĞRULANDI** | `flutter test ...stage10_7_client_safety_test.dart` -> `+16: All tests passed!`. |
| **Toplam Test Sayısı** | Toplam 135 test çalıştırıldı ve geçti | **DOĞRULANDI** | `flutter test test/core_next/` -> `+135: All tests passed!`. |
| **Önceki Test Sayısı (118)** | Stage 10.6 test sayısı 118 idi | **DOĞRULANMADI** | Stage 10.6 gerçek test sayısı 119'dur ($135 - 16 = 119$). 118 hatalı bir ara türetmedir. |
| **Cihaz Kimliği Fail-Safe** | `localDeviceId` eksikse pull durur | **DOĞRULANDI** | `sync_v4_pull_ingestion_service.dart:104` satırında `StateError` fırlatılır, cursor ilerlemez. |
| **DI Bağlantısı** | DI zinciri runtime'a bağlandı | **DOĞRULANMADI** | `coreSyncPullIngestionServiceProvider` tanımlıdır ancak hiçbir UI/Worker tarafından tüketilmemektedir (Dormant). |
| **Outbox Dead-Letter** | Çatışmalar REJECTED olur ve döngü biter | **DOĞRULANDI** | `sale_payload_conflict`, `mutation_payload_conflict`, `refund_actor_required` REJECTED olur ve retry filtresine girmez. |
| **Yerel Satış Eşleştirmesi** | Fiş no eşleşmesinde stok çift düşmez | **DOĞRULANDI** | Test 10.7.1.6 ile yerel `sales` eşleşmesi doğrulanmıştır. |
| **Yalancı Pozitif Riski** | Fiş no benzerliğinde yabancı stok atlanabilir | **AÇIK RİSK (P1)** | Sunucudan `receipt_no` replike edilmemektedir; aynı fiş no taşıyan yabancı satış yerel sayılarak stok düşümü atlanabilir. |
| **v2 -> v3 Migration** | Eski veriler korunur ve tablo eklenir | **DOĞRULANDI** | Test 10.7.3.2 gerçek verili v2 veritabanını v3'e başarıyla ve veri kaybı olmadan yükseltmiştir. |
| **PostgreSQL Entegrasyon** | İzole ortamda PostgreSQL testleri yapıldı | **TEST EDİLEMEDİ** | `DROP SCHEMA public CASCADE` yıkım riski nedeniyle test engellenmiştir (Açık Blokaj). |

---

### 8.2. Açık P0 / P1 Sorunlar Listesi

1. **P0 (Engelleme Sebebi): İzole PostgreSQL Test Ortamı Yokluğu**
   - `server/src/test/sync_v4_domain_materialization.test.ts` dosyası doğrudan `DROP SCHEMA public CASCADE` içermektedir.
   - Geliştirme veya canlı veritabanını imha etme riski nedeniyle bu test koşturulamamıştır. Sunucu materializer ve advisory lock mantığı gerçek PostgreSQL üzerinde otomatik doğrulanamamıştır.
2. **P1: `SyncV4PullIngestionService` DI Zincirinin Tüketiciye Bağlanmamış Olması (Dormant Provider)**
   - `coreSyncPullIngestionServiceProvider` tanımlanmış olmasına rağmen arka planda çalışan bir `PullWorker` veya `SyncOrchestrator` bulunmamaktadır. Sistemin üretim runtime'ında pull yapabilmesi için bir tüketici worker gereklidir.
3. **P1: Yerel Satış Eşleştirmesinde Fiş Numarası (receipt_no) Güvensizliği ve Yalancı Pozitif Riski**
   - Sunucu tarafında `sales` tablosunda `receipt_no` yoktur ve pull DTO'sunda fiş no dönmez.
   - Eğer gelecekte fiş no eklenirse, farklı kasaların aynı fiş numarasını üretmesi durumunda Kasa B'nin satışı Kasa A'da "kendi satışı" zannedilerek stok düşümü atlanacaktır. Eşleştirme yalnızca küresel tekil UUID (`id`) ve doğrulanmış `idempotency_key` üzerinden yapılmalı, genel fiş numarası tek başına yerel köken kanıtı sayılmamalıdır.
4. **P1: Fiziksel Donanım ve Yazıcı Doğrulaması**
   - Donanım isolate worker kodlanmış olmakla birlikte fiziksel ESC/POS ve TSPL yazıcılar üzerinde saha kabulü henüz tamamlanmamıştır.

---

### 8.3. Canlıya Geçiş Kararı

> ### ⛔ NİHAİ KARAR: CANLIYA GEÇİŞ ENGELLENDİ (BLOCKED)
>
> **Gerekçeler:**
> 1. İstemci tarafında `localDeviceId` güvenliği ve outbox dead-letter yönetimi başarıyla uygulanmış ve 135/135 testle kanıtlanmış olsa da;
> 2. `coreSyncPullIngestionServiceProvider` henüz hiçbir çalışma zamanı bileşenine bağlanmamış, arka plan pull worker'ı yazılmamıştır;
> 3. İkincil satış eşleştirmesindeki `receipt_no` yalancı pozitif riski giderilmemiştir;
> 4. `DROP SCHEMA public CASCADE` içeren sunucu PostgreSQL entegrasyon testi izole test konteyneri olmadan çalıştırılamamıştır (`TEST EDİLEMEDİ`);
> 5. `lib/` dizinine bu aşamada kesin sınırlar gereği dokunulmamıştır.

---
*Rapor Sonu — Serenut OS Stage 10.7.1 Bağımsız Denetimi Tamamlandı.*
