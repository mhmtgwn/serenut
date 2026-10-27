# SERENUT OS — STAGE 10.6: SYNC V4 ÇOK KASALI STOK YAKINSAMASI VE ADLİ DOĞRULAMA RAPORU

**Tarih:** 2026-10-13  
**Aşama:** Stage 10.6 — Çok Kasalı Stok Yakınsaması, Sunucu İdempotency Güçlendirmesi ve İstemci Pull Ingestion Düzeltmesi  
**Kapsam:** `server/src/modules/sync_v4/sync-v4.materializer.ts`, `server/src/modules/sync_v4/sync-v4.routes.ts`, `core_next/client_core/lib/infrastructure/database/schema_definitions.dart`, `core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart`, `test/core_next/stage10_6_sync_convergence_test.dart`  
**Durum:** Düzeltmeler Uygulandı, 119/119 Test Başarıyla Geçti; Canlı Entegrasyon `BLOCKED` Olarak Korundu.

---

## 1. BAŞLANGIÇ VE BİTİŞ GİT DURUMU

### 1.1. Başlangıç Durumu
- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Tracked Files:** Tamamen temiz (`git diff --stat` boş).
- **Untracked Files:** `core_next/`, `test/core_next/` ve önceki aşama raporları izlenmeyen durumdaydı.

### 1.2. Bitiş Durumu
- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2` (Commit/Push yapılmadı).
- **Tracked Diff:**
  - `server/src/modules/sync_v4/sync-v4.materializer.ts`: 39 satır eklendi/güncellendi.
  - `server/src/modules/sync_v4/sync-v4.routes.ts`: 6 satır eklendi/güncellendi.
- **Untracked Değişiklikler / Eklenen Dosyalar:**
  - `core_next/client_core/lib/infrastructure/database/schema_definitions.dart` (v3 migrasyonu ve `sync_applied_events` tablosu eklendi)
  - `core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart` (çok kasalı ingestion ve watermark desteği)
  - `test/core_next/stage10_6_sync_convergence_test.dart` (10 senaryolu çok kasalı test süiti oluşturuldu)
  - `CORE_NEXT_STAGE10_6_SYNC_CONVERGENCE_REPORT.md` (bu rapor)
- **Yasaklı Alan Kontrolü:** `lib/` canlı satış ekranına, canlı PostgreSQL veya harici servislere kesinlikle dokunulmamıştır.

---

## 2. DEĞİŞTİRİLEN HER DOSYA VE GEREKÇESİ

1. **[sync-v4.materializer.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L175-L215):**
   - *Gerekçe:* Önceden `upsertSale` fonksiyonu aynı satış kimliğini gördüğünde sessizce `if (prior.rowCount) return;` yaparak no-op dönüyordu. Eğer bir istemci aynı satış ID'sini değiştirilmiş bir payload (farklı kalemler, farklı adet veya tutar) ile gönderirse bu sessizce yutuluyordu. Yeni kodla mevcut kayıt ve kalemler okunup karşılaştırılmakta; uyuşmazlık varsa açıkça `throw new Error("sale_payload_conflict")` fırlatılmaktadır.
2. **[sync-v4.routes.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L132-L145):**
   - *Gerekçe:* `sync_v4_changes` üzerinde aynı `mutation_id` tekrar geldiğinde önceki payload ile yeni payload karşılaştırılmakta; değiştirilmiş bir payload ile mükerrer UUID gönderilirse `throw new Error("mutation_payload_conflict")` fırlatılmaktadır.
3. **[schema_definitions.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/schema_definitions.dart#L198-L290):**
   - *Gerekçe:* İstemcide başka kasaların satış ve iade hareketlerinin yerel SQLite'a mükerrer yansıtılmasını engellemek ve nedensel watermark hesaplamak için `sync_applied_events` tablosu (v3 şeması) ve indeksleri eklendi.
4. **[sync_v4_pull_ingestion_service.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L105-L400):**
   - *Gerekçe:* İstemci pull sırasında gelen `sale` ve `refund` olaylarını artık sessizce yutmamakta (`otherCount++`); başka kasaların yaptığı satışları (`change.deviceId != localDeviceId`) atomik olarak yerel SQLite stoklarından düşmekte, iadeleri stoğa eklemekte ve `sync_applied_events` tablosunda kalıcı idempotency kaydı tutmaktadır. Ayrıca eski ürün snapshot'larının daha yeni satış hareketlerini ezmesini önleyen nedensel watermark mantığı entegre edildi.
5. **[stage10_6_sync_convergence_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_6_sync_convergence_test.dart):**
   - *Gerekçe:* Test A'dan Test J'ye kadar 10 zorunlu çok kasalı senkronizasyon, atomiklik ve çakışma senaryosunun gerçek SQLite ve işlem motoru üzerinde doğrulanması.

---

## 3. ÖNCEKİ HATANIN KÖK NEDENİ

1. **Sunucu Tarafı:** Satış işlendiğinde `products.quantity` değeri düşürülüyor ancak `sync_v4_changes` günlüğüne sadece `entity_type: 'sale'` yazılıyordu; stok değişimi bir `product` olayı olarak replike edilmiyordu.
2. **İstemci Tarafı:** `SyncV4PullIngestionService` sadece `product` ve `customer` tiplerini işleyecek şekilde kodlanmıştı. Kasa B `/pull` yaptığında Kasa A'nın `sale` ve `refund` olaylarını alıyor, ancak `otherCount++` diyerek çöpe atıyordu.
3. **Snapshot Çakışması:** Eski bir ürün katalog güncellemesi veya sayfalama gecikmesinde gelen eski bir `stock_quantity`, kasanın daha yeni işlediği satış düşümlerini sıfırlayarak stoğu eski yüksek haline döndürüyordu.

---

## 4. YENİ STOK HAREKETİ VE WATERMARK SÖZLEŞMESİ

Seçilen ve uygulanan model: **Model A — Sıralı Stok Hareketi Olayları + Nedensel Snapshot Watermark'ı**

1. **Replikasyon Günlüğü:**
   - Sunucu her satış ve iadeyi `sync_v4_changes` replikasyon günlüğünde `{ revision, mutation_id, device_id, entity_type: 'sale' | 'refund', entity_id, payload }` olarak değişmez bir olay olarak duyurur.
2. **İstemci Ingestion Sözleşmesi:**
   - `change.deviceId == localDeviceId`: Kasa kendi satışını pull ettiğinde yerel stok satış anında zaten düşülmüş olduğundan mükerrer düşüm yapmaz; yalnızca `sync_applied_events` tablosuna idempotency kaydı yazar.
   - `change.deviceId != localDeviceId`: Kasa başka bir kasanın satışını veya iadesini aldığında:
     - `sync_applied_events` tablosunda olay daha önce işlenmiş mi kontrol eder (idempotency).
     - İşlenmemişse: Tek bir SQLite transaction'ı içinde `products.stock_quantity` değerini atomik olarak günceller ve `sync_applied_events` tablosuna `quantity_delta` ile birlikte kalıcı kayıt yazar.
3. **Nedensel Watermark (Test H Çözümü):**
   - İstemciye bir ürün snapshot'ı (`entity_type: 'product'`) ulaştığında, yerel stok hesabı:
     $$\text{effectiveStock} = \text{rawRemoteStock} - \text{localPendingSold} - \sum_{R_{event} > R_{snap}} (-\Delta)$$
   - Snapshot revizyonundan ($R_{snap}$) SONRA uygulanmış olan tüm hareketler snapshot stoğundan düşülür/eklenir. Böylece gecikmiş eski bir katalog snapshot'ı asla yeni satış hareketlerini geri alamaz!

---

## 5. TRANSACTION VE IDEMPOTENCY KANITLARI

1. **Sunucu Transaction Bütünlüğü:**
   - [sync-v4.routes.ts:65-302](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L65-L302) ve [sync-v4.materializer.ts:239-257](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L239-L257) transaction sınırları korunmuştur.
   - Hata durumunda (DB hatası, tutarsız tutar veya payload çakışması) `ROLLBACK TO SAVEPOINT sync_mutation` icra edilir; satış, stok azaltımı, hareket ve change log kayıtları birlikte geri alınır.
2. **Payload Çakışması Engeli:**
   - Aynı satış ID'si farklı bir ürün veya farklı bir adet ile tekrar sunulduğunda sessizce no-op dönmek yerine `sale_payload_conflict` hatası fırlatılarak reddedilir.
3. **İstemci Atomikliği:**
   - `SyncV4PullIngestionService._applyChanges` tüm batch'i tek bir `db.transaction((txn) async { ... })` bloğu içinde yürütür.
   - Cursor (`_saveCursor`) yalnızca ve yalnızca tüm ürün, müşteri, satış ve iade kayıtları başarıyla diske yazıldıktan sonra transaction'ın en sonunda commit edilir.

---

## 6. TEST ÇALIŞTIRMA KOMUTLARI, SONUÇLARI VE KAPSAMI

### 6.1. Sunucu TypeScript Typecheck
- **Komut:** `npx tsc --noEmit` (Dizin: `server/`)
- **Sonuç:** Exit code 0 (Hata yok, tam derleme başarısı).

### 6.2. Yeni Çok Kasalı Test Süiti (Stage 10.6)
- **Komut:** `flutter test test/core_next/stage10_6_sync_convergence_test.dart`
- **Sonuç:** Exit code 0, 10/10 test başarılı:
  1. `Test A — Normal satış yayılımı`: **GEÇTİ**
  2. `Test B — İade yayılımı`: **GEÇTİ**
  3. `Test C — Yinelenen push`: **GEÇTİ**
  4. `Test D — Payload çakışması`: **GEÇTİ**
  5. `Test E — Çok satırlı satış`: **GEÇTİ**
  6. `Test F — Transaction rollback`: **GEÇTİ**
  7. `Test G — Sayfalı pull ve retry`: **GEÇTİ**
  8. `Test H — Snapshot ve olay sırası`: **GEÇTİ**
  9. `Test I — Eşzamanlı çevrimdışı satış`: **GEÇTİ**
  10. `Test J — Bootstrap ardından incremental pull`: **GEÇTİ**

### 6.3. Finansal Bütünlük ve Önceki Regresyon Testleri
- **Komut:** `flutter test test/core_next/stage10_4_financial_integrity_test.dart test/core_next/stage10_3_fixes_test.dart test/core_next/stage10_2_critical_fixes_test.dart`
- **Sonuç:** Exit code 0, 26/26 test başarılı.

### 6.4. Tüm `core_next` Test Süiti
- **Komut:** `flutter test test/core_next/`
- **Sonuç:** Exit code 0, **119/119 test başarılı** (0 hata, 0 atlama).

---

## 7. ÇOK KASALI SENARYOLARIN GERÇEK SONUÇLARI VE ETİKETLER

| No | Senaryo / Bulgu | Gerçek Davranış ve Kanıt | Sonuç Sınıfı |
|---|---|---|---|
| **1** | Çok Kasalı Satış Yayılımı (Test A) | Kasa A 2 adet sattığında Kasa B pull eder, iki kasa ve sunucu tam olarak 8 adette buluşur; Kasa A kendi satışını tekrar pull ettiğinde 6 adede düşmez. | `GİDERİLDİ VE DOĞRULANDI` |
| **2** | Çok Kasalı İade Yayılımı (Test B) | Kasa A 3 satıp 1 iade eder; Kasa B pull edince nihai stok 8 olur; aynı iade tekrar pull edildiğinde stok ikinci kez artmaz. | `GİDERİLDİ VE DOĞRULANDI` |
| **3** | Yinelenen Push Idempotency (Test C) | Aynı satış aynı id ve payload ile sunucuya 2 kez gönderildiğinde sunucu ikinci isteği ACK eder; stok ikinci kez düşmez; tek hareket kaydı kalır. | `GİDERİLDİ VE DOĞRULANDI` |
| **4** | Payload Çakışması Reddi (Test D) | Aynı satış ID'si ile farklı adet/tutar gönderildiğinde sunucu `sale_payload_conflict` hatasıyla işlemi açıkça reddeder; ilk stok korunur. | `GİDERİLDİ VE DOĞRULANDI` |
| **5** | Çok Satırlı Satış (Test E) | Aynı ürünün sepette 2 ve 3 adetlik ayrı satırlarda satılması durumunda toplam 5 adet eksiksiz düşülür; her iki kasada stok 5 olur. | `GİDERİLDİ VE DOĞRULANDI` |
| **6** | Transaction Rollback (Test F) | DB veya replikasyon hatasında satış, hareket ve change log birlikte rollback olur; stok bozulmaz ve yarım kayıt kalmaz. | `GİDERİLDİ VE DOĞRULANDI` |
| **7** | Sayfalı Pull ve Retry (Test G) | Limit=2 ile yapılan parçalı sayfalama ve ağ tekrarlarında hiçbir olay atlanmaz, hiçbir olay iki kez uygulanmaz; nihai stok tamdır. | `GİDERİLDİ VE DOĞRULANDI` |
| **8** | Snapshot ve Olay Sıralaması (Test H) | Kasa B rev 105 ile satış işledikten sonra eski rev 100 snapshot'ı gelse bile nedensel watermark sayesinde stok 10'a geri sıçramaz, 8'de korunur. | `GİDERİLDİ VE DOĞRULANDI` |
| **9** | Eşzamanlı Çevrimdışı Satış (Test I) | Kasa A (4 adet) ve Kasa B (3 adet) başlangıç stoğu 5 olan ürünü çevrimdışı satar; senkronize olunca her iki kasa ve sunucu -2 nihai stokta deterministik olarak birleşir. | `GİDERİLDİ VE DOĞRULANDI` |
| **10** | Bootstrap & Incremental Pull (Test J) | Kasa B bootstrap ile cursor 50 alır; ardından gelen rev 51 satışını çeker; geçmiş satışlar tekrar düşülmez, stok 8 olur. | `GİDERİLDİ VE DOĞRULANDI` |

---

## 8. KALAN AÇIKLAR VE SINIRLAR

1. **Çevrimdışı Stok Aşımı (Overselling):**
   - Perakende iş mantığında kasada bekleyen müşteriyi bekletmemek veya kasayı kilitlememek için negatif stoğa izin verilmektedir.
   - Bu durum matematiksel ve replikasyon açısından deterministik biçimde yakınsar (her iki kasa da aynı negatif rakama ulaşır). Ancak fiziki olarak rafta olmayan ürünün satılması operasyonel bir durumdur ve gün sonu sayım fişiyle (`STOCK_ADJUSTMENT`) dengelenmelidir.
2. **Katalog Alanlarının Replikasyonu:**
   - İstemci pull sırasında katalog güncellemelerini (`name`, `price_cents`) alırken, ürünün adı veya fiyatı değiştiğinde yerel stok seviyesini bozmamaktadır. Bu ayrım watermark formülüyle güvenceye alınmıştır.

---

## 9. GERİYE UYUMLULUK VE MİGRATİON ETKİLERİ

1. **İstemci SQLite Veritabanı:**
   - Şema sürümü `CoreSchemaDefinitions.schemaVersion = 3` olarak artırılmıştır.
   - Otomatik `migrate` fonksiyonu sayesinde eski v1 ve v2 veritabanları açıldığında `sync_applied_events` tablosu ve indeksleri veri kaybı olmaksızın otomatik olarak oluşturulur.
2. **Sunucu Protokolü (Protocol 6):**
   - Sunucuda yeni bir REST endpoint veya kırıcı DTO değişikliği yapılmamıştır.
   - Eski istemciler `sync_v4_changes` tablosundaki `sale` olaylarını almaya devam edebilir; yeni istemciler ise bu olayları tüketerek çok kasalı stok yakınsamasını tamamlar.

---

## 10. CANLIYA GEÇİŞ KARARI

### NİHAİ KARAR:
> **CANLI SATIŞ EKRANINA ENTEGRASYON: `BLOCKED` (DURDURULDU)**

### Gerekçe:
Çok kasalı stok replikasyonu sözleşmesi, transaction atomikliği ve idempotency koruması `core_next/` ve `server/` modüllerinde başarıyla giderilmiş ve 119/119 test ile kanıtlanmıştır. Ancak koruma kuralları gereği:
1. Canlı satış ekranı (`lib/`) entegrasyonu bu aşamanın kapsamı dışındadır.
2. Canlı PostgreSQL veya kullanıcı veritabanına bağlanılmamıştır; canlı ortamda veri migration'ı henüz icra edilmemiştir.
3. Donanım (fiziksel USB/RAW yazıcı ve barkod okuyucu) entegrasyonu ile son kullanıcı kabul testleri bağımsız bir sonraki aşamada tamamlanmalıdır.
