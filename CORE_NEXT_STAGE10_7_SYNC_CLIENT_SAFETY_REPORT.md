# SERENUT OS — STAGE 10.7: SYNC V4 İSTEMCİ GÜVENLİĞİ, OUTBOX DEAD-LETTER VE SUNUCU TEST HAZIRLIĞI RAPORU

**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.7  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Canlıya Geçiş Durumu:** ⛔ **ENGELLENDİ (BLOCKED)**  

---

## 1. GİRİŞ VE ÇALIŞMA SINIRLARI

Stage 10.6.1 bağımsız adli doğrulama raporunda tespit edilen mimari açıklar (`localDeviceId` eksikliğinde yerel satışın yabancı sayılarak stokun mükerrer düşülmesi riski, `sale_payload_conflict` / `mutation_payload_conflict` sunucu hatalarının outbox işlemcisinde sonsuz retry döngüsüne girmesi ve sunucu PostgreSQL testlerindeki `DROP SCHEMA public CASCADE` yıkım riski) bu aşamada ele alınmıştır.

### Kesin Çalışma Sınırlarına Uyum Beyanı
- `lib/` altındaki canlı satış uygulamasına **kesinlikle dokunulmamıştır** (`%100` salt okunur bırakılmıştır).
- Canlı API, PostgreSQL veya müşteri veritabanlarına bağlantı kurulmamıştır.
- Production verisi üzerinde migration veya test çalıştırılmamıştır.
- `git add`, `git commit`, `git push` veya deploy komutları çalıştırılmamıştır.
- Yazıcı entegrasyonu ve canlı geçiş runbook'u başlatılmamıştır; canlıya geçiş kapısı **BLOCKED** olarak korunmuştur.

---

## 2. İNCELENEN VE DEĞİŞTİRİLEN DOSYALAR

| Dosya Yolu | Durum | Yapılan İşlem / Kapsam |
|---|---|---|
| `core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart` | Değiştirildi | `localDeviceId` güvenli doğrulama (`unidentified_local_device`), ikincil `sales` tablosu kontrolü (`id`, `receipt_no`, `idempotency_key`), atomik transaction koruması. |
| `core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart` | Değiştirildi | `sale_payload_conflict`, `mutation_payload_conflict`, `refund_actor_required` terminal listeye eklendi; `SyncConflictException` ile HTTP 409 çatışma ayrımı yapıldı. |
| `core_next/client_core/lib/domain/models/sync_dtos.dart` | Değiştirildi | `SyncConflictException` sınıfı eklendi (HTTP 409 ve opsiyonel `errorCode` desteği). |
| `core_next/client_core/lib/infrastructure/sync/sync_v4_http_client.dart` | Değiştirildi | HTTP 409 yanıtı durumunda JSON içerisindeki `error` alanını ayıklayarak `SyncConflictException` fırlatacak şekilde güncellendi. |
| `core_next/client_core/lib/presentation/di/core_providers.dart` | Değiştirildi | `coreDeviceIdProvider` ve `coreSyncPullIngestionServiceProvider` pre-warmed DI konteynerine eklendi. |
| `test/core_next/stage10_7_client_safety_test.dart` | Yeni Oluşturuldu | 16 adet kapsamlı regresyon ve adli güvenlik testi (P0-1, P0-2, Watermark, Migration). |
| `server/src/modules/sync_v4/sync-v4.materializer.ts` | İncelendi | Hata kodları ve savepoint rollback akışları doğrulandı. |
| `server/src/modules/sync_v4/sync-v4.routes.ts` | İncelendi | Advisory lock, `mutation_payload_conflict` ve `rejected` dizi formatı doğrulandı. |
| `server/src/test/sync_v4_domain_materialization.test.ts` | İncelendi | `DROP SCHEMA public CASCADE` komutunun riskleri ve test altyapısı incelendi. |
| `server/src/test/run_all_ac_tests.ts` | İncelendi | Ortam değişkeni fail-fast kalkanları ve veritabanı yalıtım mekanizması analiz edildi. |

---

## 3. BULGULAR VE ÖNCEKİ / SONRAKİ DAVRANIŞ KARŞILAŞTIRMASI

### Bulgu 1 (P0): Yerel Satışın ve İadenin Tekrar Uygulanmasını Engelleme

- **Önceki Davranış:**
  `SyncV4PullIngestionService` yapıcısında `localDeviceId` opsiyoneldi. Eğer `localDeviceId` null veya boş bırakılırsa `isLocalOrigin` ifadesi `false` dönüyordu. Bu durumda pull ingestion servisi yerel cihazın kendi oluşturduğu satış ve iadeleri "yabancı kasanın işlemi" varsayarak yerel SQLite `products` stoklarını ikinci kez düşüyor (satışta) veya artırıyordu (iadede).
- **Sonraki Davranış:**
  1. **Fail-Safe Giriş Denetimi:** `_applyChanges` fonksiyonu, batch içerisinde `sale` veya `refund` gibi cihaza bağımlı olaylar bulunduğunda `localDeviceId`'nin null, boş (`''`) veya yalnızca boşluktan (`'   '`) ibaret olup olmadığını denetler. Eksik veya geçersizse hiçbir veritabanı işlemine başlamadan güvenle `StateError('unidentified_local_device')` fırlatır. Cursor ilerlemez, stok değişmez.
  2. **İkincil Savunma Hattı (Secondary Local Lookup):** Cihaz kimliği gateway/proxy tarafından değiştirilmiş, bozulmuş veya eşleşmiyor olsa dahi, `_ingestSale` ve `_ingestRefund` fonksiyonları yerel SQLite `sales` tablosunda `id = change.entityId`, `receipt_no = payload['receipt_no']` veya `idempotency_key = payload['idempotency_key']` sorgusu yapar. Yerelde mevcut bir satış/iade tespit edilirse `isLocalOrigin = true` kabul edilir ve stok ikinci kez kesinlikle değiştirilmez.
  3. **Kalıcı İdempotency & ACID:** Olay `sync_applied_events` tablosuna yazılır. Bir hata durumunda SQLite transaction'ı tüm hareketleri geri alır (rollback) ve cursor kaydedilmez.

### Bulgu 2 (P0): Outbox Payload Çatışmalarını Terminal Duruma Alma (Dead-Letter)

- **Önceki Davranış:**
  Sunucunun döndürdüğü `sale_payload_conflict` ve `mutation_payload_conflict` hataları `nonRetryableServerErrors` listesinde bulunmuyordu. Bu nedenle `SyncV4OutboxProcessor` bu kayıtları `TRANSIENT_ERROR` olarak işaretliyor, her yeni worker çalıştığında bu mutasyonları tekrar tekrar sunucuya göndererek sonsuz retry döngüsüne giriyordu.
- **Sonraki Davranış:**
  1. `nonRetryableServerErrors` kümesine `'sale_payload_conflict'`, `'mutation_payload_conflict'` ve `'refund_actor_required'` kodları eklendi.
  2. Sunucu push yanıtında bu hata kodları döndüğünde `sync_state = 'REJECTED'` yapılır, `last_error` alanında sunucu hata kodu korunur ve retry döngüsünden çıkarılır.
  3. `SyncConflictException` (HTTP 409) desteği eklendi: Sunucu HTTP 409 döndürdüğünde, hata kodu doğrulanmış bir kalıcı çatışma ise (`sale_payload_conflict` / `mutation_payload_conflict`) mutasyon `REJECTED` yapılır. Bilinmeyen veya kodsuz HTTP 409 durumunda ise körlemesine reddedilmez; güvenle `TRANSIENT_ERROR` olarak retry kuyruğunda tutulur.
  4. `REJECTED` mutasyonlar `where: "sync_state IN ('PENDING', 'TRANSIENT_ERROR')"` filtresi sayesinde sonraki döngülerde veya uygulama yeniden başlatıldığında kesinlikle tekrar gönderilmez; `getRejectedMutations()` ile tanılama ve inceleme için listelenebilir.

### Bulgu 3 (P0): PostgreSQL Entegrasyon Test Güvenliği ve Altyapı Engeli

- **İnceleme ve Risk Tespiti:**
  `server/src/test/sync_v4_domain_materialization.test.ts` dosyası 8. satırında `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` komutunu doğrudan çalıştırmaktadır.
  `server/src/config/database.ts` dosyası `process.env.NODE_ENV === 'test'` olmadığı sürece `.env` dosyasını yüklemekte ve oradaki `DATABASE_URL`'i kullanmaktadır.
  Proje kökündeki `server/.env` dosyasında `DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/nutopiano` tanımlıdır (aktif geliştirme veritabanı).
- **Sonuç ve Karar:**
  Geliştirme veya olası canlı veritabanında şema silme ve veri kaybı riski nedeniyle, izole ve doğrulanmış ayrı bir test PostgreSQL kapsayıcısı/servisi olmadan bu test çalıştırılmamıştır (`TEST EDİLEMEDİ / GÜVENLİK ENGELİ`). Bu durum canlıya geçiş için açık bir blokaj sebebi olarak raporlanmıştır.

---

## 4. EKLENEN REGRESYON TESTLERİ VE DOĞRULAMA KAPSAMI

`test/core_next/stage10_7_client_safety_test.dart` dosyasında gerçek SQLite FFI (`sqflite_common_ffi`) üzerinde 16 adet yeni test icra edilmiştir:

### Grup 1: İstemci Pull Ingestion ve Yerel Satış Güvenliği
- **10.7.1.1:** Doğru cihaz kimliğiyle (`kasa-a`) kendi satışı çekildiğinde stok 20 olarak kalır; `sync_applied_events` tablosuna idempotent olarak kaydedilir.
- **10.7.1.2:** `localDeviceId == null` durumunda `StateError('unidentified_local_device')` fırlatılır; stok değişmez, cursor ilerlemez.
- **10.7.1.3:** Boşluktan oluşan (`'   '`) cihaz kimliğinde `StateError` fırlatılır; yabancı cihaz varsayımı engellenir.
- **10.7.1.4:** Başka kasanın satışı ilk seferde stoku 20 -> 17 düşürür; aynı olay ikinci kez geldiğinde `alreadyApplied` yakalanır ve stok 17 olarak korunur.
- **10.7.1.5:** Veritabanı kapatılıp diskten yeniden açıldıktan sonra aynı olay tekrar çekildiğinde, `sync_applied_events` tablosundaki kalıcı kayıt sayesinde stok mükerrer düşmez.
- **10.7.1.6:** Sunucu satış UUID'si farklı olsa dahi `receipt_no` ve `idempotency_key` yerel `sales` tablosuyla eşleştiğinde ikincil koruma devreye girer ve stok düşülmez.
- **10.7.1.7:** SQLite transaction içinde hata oluştuğunda tüm yazımlar rollback olur; cursor ilerlemez.
- **10.7.1.8:** Yerelde yapılmış iade geri çekildiğinde stok ikinci kez artmaz.

### Grup 2: Outbox Dead-Letter ve Payload Çatışma Yönetimi
- **10.7.2.1 & 10.7.2.2:** `sale_payload_conflict` ve `mutation_payload_conflict` yanıtları mutasyonları `REJECTED` yapar; `last_error` saklanır.
- **10.7.2.3:** `REJECTED` mutasyonlar sonraki `processOutbox()` çağrısında taranmaz; HTTP çağrı sayısı artmaz (sonsuz döngü engellendi).
- **10.7.2.4:** Uygulama yeniden başlatıldıktan sonra `REJECTED` durumu korunur; `getRejectedMutations()` ile listelenir.
- **10.7.2.5:** Sunucu HTTP 500 veya ağ hatası verdiğinde `TRANSIENT_ERROR` durumu korunur ve yeniden denenir.
- **10.7.2.6:** HTTP 409 çatışma ayrımı: Bilinen hata kodu (`sale_payload_conflict`) `REJECTED` olur; bilinmeyen kod (`arbitrary_temporary_409`) `TRANSIENT_ERROR` olarak retry kuyruğunda tutulur.
- **10.7.2.7:** Başarılı gönderim (`SYNCED`, revision güncellemesi, `last_error = null`) davranışının bozulmadığı doğrulanır.

### Grup 3: Watermark, Delta ve Şema Migration
- **10.7.3.1:** Satış (-4) ve İade (+1) hareketleri sonrasında eski katalog snapshot'ı (rev 8) geldiğinde `post_delta = -3` hesabı üzerinden `effectiveStock = 50 - 3 = 47` matematiksel kesinliği doğrulanır.
- **10.7.3.2:** v2 şemasından v3 şemasına migration işletildiğinde `sync_applied_events` tablosu eklenir; eski ürün ve satış kayıtları eksiksiz korunur.

---

## 5. ÇALIŞTIRILAN KOMUTLAR VE ÇIKIŞ KODLARI

| Komut | Çalışma Dizini | Çıkış Kodu | Sonuç / Test Sayısı |
|---|---|---|---|
| `flutter test test/core_next/stage10_7_client_safety_test.dart` | Repo Kökü | **0** | **16/16 Başarılı** |
| `flutter test test/core_next/` | Repo Kökü | **0** | **135/135 Başarılı** (Tüm CoreNext Testleri) |
| `npx tsc --noEmit` | `server/` | **0** | **0 Hata** (TypeScript derlemesi kusursuz) |
| `git diff --check` | Repo Kökü | **0** | Temiz (Whitespace veya format hatası yok) |
| `Test-NetConnection -ComputerName 127.0.0.1 -Port 5432` | Repo Kökü | **0** | Port açık, ancak izole test DB doğrulanmadı |

---

## 6. POSTGRESQL ENTEGRASYON TESTİ DEĞERLENDİRMESİ

- **Test Dosyası:** `server/src/test/sync_v4_domain_materialization.test.ts`
- **Çalıştırma Durumu:** `TEST EDİLEMEDİ / ATLANDI`
- **Adli Tespit:**
  1. Test dosyası doğrudan `DROP SCHEMA public CASCADE` çalıştırmaktadır.
  2. Testin koşturulabilmesi için izole bir test veritabanının (`serenut_test` veya `nutopiano_test`) bağımsız bir port veya Docker kapsayıcısında ayağa kaldırılması ve `NODE_ENV=test` ortam değişkeninin zorunlu kılınması gerekmektedir.
  3. Geliştirici veya aktif ortama zarar verme riski nedeniyle test çalıştırılmamış, simülasyon sonuçları gerçek entegrasyon testi olarak yansıtılmamıştır.

---

## 7. ÇÖZÜLEMEYEN SORUNLAR VE AÇIK RİSKLER

1. **İzole PostgreSQL Test Ortamı:** Sunucu tarafındaki PostgreSQL transaction ve advisory lock davranışlarını uçtan uca doğrulayacak yalıtılmış bir CI/Docker test veritabanı ortamı bulunmamaktadır.
2. **Donanım / Yazıcı Doğrulaması:** ESC/POS ve TSPL yazıcı worker isolate mimarisi kodlanmış olmakla birlikte fiziksel yazıcılar üzerinde donanımsal onay henüz tamamlanmamıştır.
3. **Canlı Entegrasyon:** `lib/` altındaki canlı satış ekranı halen eski mimariyi kullanmaktadır.

---

## 8. GİT VE DOSYA KAPSAMI DENETİMİ

- **Başlangıç HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Son HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Commit yapılmamıştır)
- **`lib/` Durumu:** `%100 DOKUNULMAMIŞTIR`.
- **İzlenen Dosya Değişiklikleri:** Yalnızca Stage 10.6'dan kalan `sync-v4.materializer.ts` ve `sync-v4.routes.ts` dosyaları (41 satır ekleme/değişiklik).
- **Yeni Dosyalar:** `test/core_next/stage10_7_client_safety_test.dart` ve `CORE_NEXT_STAGE10_7_SYNC_CLIENT_SAFETY_REPORT.md`.

---

## 9. CANLIYA GEÇİŞ KAPISI KARARI

> ### ⛔ CANLIYA GEÇİŞ DURUMU: ENGELLENDİ (BLOCKED)
>
> **Gerekçeler:**
> 1. İstemci tarafında `localDeviceId` güvenliği ve outbox dead-letter yönetimi başarıyla giderilmiş ve 135/135 testle kanıtlanmış olsa da;
> 2. Gerçek PostgreSQL entegrasyon testi `DROP SCHEMA public CASCADE` riski ve izole ortam eksikliği nedeniyle çalıştırılamamıştır (`TEST EDİLEMEDİ`).
> 3. Donanım yazıcı worker'larının saha/fiziksel cihaz kabul testleri icra edilmeden canlı satış ekranına (`lib/`) geçiş yapılamaz.

---
*Rapor Sonu — Serenut OS Stage 10.7 Tamamlandı.*
