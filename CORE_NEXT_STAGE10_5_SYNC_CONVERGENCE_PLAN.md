# SERENUT OS — STAGE 10.5: GERÇEK SYNC V4 ADLİ İNCELEME VE YAKINSAMA PLANI

**Tarih:** 2026-10-13  
**Aşama:** Stage 10.5 — Gerçek Üretim Sync V4 Adli İncelemesi, Nedensellik Analizi ve Çok Kasalı Yakınsama Planı  
**Kapsam:** `server/src/modules/sync_v4/`, `server/src/modules/order/`, `server/db/`, `core_next/client_core/lib/infrastructure/sync/`  
**Durum:** Salt Okunur İnceleme Tamamlandı; Canlı Satış Entegrasyonu `BLOCKED` Olarak Korundu.

---

## 1. İNCELENEN DOSYALAR VE GERÇEK ÇAĞRI ZİNCİRİ

Bu inceleme, mock veya taslak servislere değil (`watermark_sync_service.ts` bir Stage 8 PoC'sidir), sunucuda aktif olarak çalışan gerçek Sync V4 üretim koduna dayanmaktadır.

### 1.1. İncelenen Dosyalar ve Gerçek Satır Aralıkları
1. **Sunucu Senkronizasyon Uç Noktaları:** [sync-v4.routes.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L54-L450)
   - `/push` endpoint'i (Satır 54–342)
   - `/pull` endpoint'i (Satır 344–382)
   - `/bootstrap` endpoint'i (Satır 390–450)
2. **Sunucu Domain Materializer:** [sync-v4.materializer.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L28-L258)
   - `applyDomainMutation` fonksiyonu (Satır 28–161)
   - `upsertSale` fonksiyonu (Satır 163–258)
3. **Sunucu İade Servisi:** [refund.service.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/order/refund.service.ts#L6-L129)
   - `RefundService.create` fonksiyonu (Satır 6–129)
4. **Sunucu Veritabanı Şeması ve Tabloları:**
   - [schema_v52.sql](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/db/schema_v52.sql#L1-L17): `sync_v4_changes` (Replication Journal)
   - [schema_v53.sql](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/db/schema_v53.sql#L1-L12): `sync_v4_entities` (Tombstone & State)
   - [schema_v54.sql](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/db/schema_v54.sql#L1-L75): `sync_v4_conflicts` & indeksler
5. **İstemci Senkronizasyon Tüketim Servisi:** [sync_v4_pull_ingestion_service.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L74-L277)
   - `_applyChanges` fonksiyonu (Satır 74–141)
   - `_ingestProduct` fonksiyonu (Satır 144–242)
   - `_calculateUnreflectedSoldQty` fonksiyonu (Satır 244–277)
6. **Mevcut Sunucu Entegrasyon Testi:** [sync_v4_domain_materialization.test.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/test/sync_v4_domain_materialization.test.ts#L27-L120)

### 1.2. Gerçek Çağrı Zinciri (Execution Trace)
```
[İstemci Kasa A]
   └─ CoreCheckoutUseCase.execute()
        └─ SQLite: INSERT sales, sale_items, sync_events ('sale', status: 'PENDING')
        └─ SyncV4HttpClient.push([SyncMutationDto('sale', ...)])
             │
             ▼ (HTTP POST /api/v4/sync/push, Protocol 6)
[Sunucu sync-v4.routes.ts]
   └─ router.post('/push')
        ├─ BEGIN Transaction (PoolClient)
        ├─ Advisory Lock: pg_advisory_xact_lock(company_id, 'sale:saleId')
        ├─ SAVEPOINT sync_mutation
        ├─ applyDomainMutation(client, companyId, mutation, userId)
        │    └─ upsertSale(client, companyId, id, payload)
        │         ├─ SELECT id FROM sales WHERE id = $1 FOR UPDATE (Idempotency)
        │         ├─ INSERT INTO sales (...)
        │         ├─ UPDATE products SET quantity = quantity - $1, updated_at = NOW()
        │         ├─ INSERT INTO inventory_movements(..., movement_type: 'sale', ...)
        │         └─ INSERT INTO sale_items (...)
        ├─ INSERT INTO sync_v4_changes (tenant_id, mutation_id, entity_type: 'sale', ...) RETURNING revision
        ├─ INSERT INTO sync_v4_entities (entity_type: 'sale', updated_revision: rev, ...)
        ├─ RELEASE SAVEPOINT sync_mutation
        └─ COMMIT Transaction
```

---

## 2. DOĞRULANMIŞ MEVCUT DAVRANIŞ (KOD KANITLARI)

Aşağıdaki 8 temel soru kaynak kod satırlarıyla ve veritabanı işlem sınırlarıyla doğrulanmıştır:

### 1. `upsertSale` stok miktarını tam olarak hangi koşullarda azaltıyor?
- **Kanıt:** [sync-v4.materializer.ts:239-244](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L239-L244)
- **Koşullar:** 
  1. Satış kimliği daha önce yazılmamışsa (`prior.rowCount === 0`).
  2. Kalemler (`items`) dizisi boş değilse ve `product_id` geçerliyse.
  3. Kalem toplamları ile istemcinin bildirdiği toplam arasındaki fark 0.05'ten küçükse (`abs(clientTotal - expectedTotal) <= 0.05`).
  4. İlgili ürünün `is_deleted = false` ise.
- **SQL:**
  ```sql
  UPDATE products SET quantity = quantity - $1, updated_at = NOW()
  WHERE id = $2 AND company_id = $3 AND is_deleted = false
  ```
- **Etiket:** `DOĞRULANDI`

### 2. Satış, `inventory_movements`, `sync_v4_changes` ve ilgili idempotency kaydı aynı PostgreSQL transaction'ında mı?
- **Kanıt:** [sync-v4.routes.ts:65-302](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L65-L302), [sync-v4.materializer.ts:245-257](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L245-L257)
- Evet. Tüm işlemler `client.query('BEGIN')` ile başlar; `applyDomainMutation` (sales, products, inventory_movements, sale_items) ve `sync_v4_changes` aynı client bağlantısında icra edilir, hata durumunda `ROLLBACK TO SAVEPOINT sync_mutation` veya genel `ROLLBACK` yapılır.
- **Etiket:** `DOĞRULANDI`

### 3. Aynı satış aynı idempotency anahtarıyla yeniden gönderilirse stok ikinci kez azalabilir mi?
- **Kanıt:** [sync-v4.routes.ts:132-142](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L132-L142), [sync-v4.materializer.ts:175-181](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L175-L181)
- Hayır, stok ikinci kez **azalmaz**.
- Birinci kalkan: `sync_v4_changes` üzerinde `SELECT revision WHERE mutation_id = $2::uuid` kontrol edilir; bulunursa mevcut revizyon dönülerek `continue` edilir.
- İkinci kalkan: Farklı `mutation_id` ile gelse dahi `upsertSale` içinde `SELECT id FROM sales WHERE id = $1 FOR UPDATE` kontrol edilir; kayıt varsa `if (prior.rowCount) return;` ile no-op yapılır.
- **Etiket:** `DOĞRULANDI`

### 4. Aynı satış kimliği farklı payload ile gönderilirse ne oluyor?
- **Kanıt:** [sync-v4.materializer.ts:175-181](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L175-L181)
- `upsertSale` fonksiyonu `prior.rowCount > 0` gördüğü anda sessizce `return;` yapmaktadır. Gelen yeni payload'daki kalem veya tutar farkı kontrol **edilmemektedir**.
- İlk yazılan satış korunur, yeni payload sessizce yutulur; bir çakışma (`conflict`) hatası veya HTTP 409 fırlatılmaz.
- **Etiket:** `KISMEN DOĞRULANDI`

### 5. Satışta birden fazla ürün veya aynı ürüne ait birden fazla satır varsa miktar doğru hesaplanıyor mu?
- **Kanıt:** [sync-v4.materializer.ts:190-211](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L190-L211), [sync-v4.materializer.ts:239-257](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L239-L257)
- `normalizedItems` döngüsü her satırı bağımsız olarak işler. Aynı üründen 2 satır (ör. 3 adet ve 2 adet) varsa, `UPDATE products SET quantity = quantity - $1` sorgusu o ürün için iki kez çalışarak toplam 5 adet düşer.
- **Etiket:** `DOĞRULANDI`

### 6. Stok yetersizliği, eşzamanlı satış, iptal, iade ve satış değişikliği nasıl ele alınıyor?
- **Stok Yetersizliği:** `upsertSale` içinde `quantity >= $1` kontrolü **yoktur**. Stok negatife düşebilir (`quantity` serbestçe eksiye iner).
- **Satış Değişikliği / İptali:** [sync-v4.materializer.ts:74-75](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L74-L75) -> `if (mutation.entity_type === "sale") throw new Error("immutable_sale");`. Satış silinemez veya güncellenemez.
- **İade:** `RefundService.create` ([refund.service.ts:100-110](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/order/refund.service.ts#L100-L110)) üzerinden `UPDATE products SET quantity = quantity + $1` çalıştırılır ve `inventory_movements` (movement_type: 'refund') yazılır.
- **Etiket:** `DOĞRULANDI`

### 7. Ürün stok snapshot'ı hangi olaylarda ve hangi sequence/revision ile değişiyor?
- Ürün stok snapshot'ı, sunucudaki `products` tablosunda `quantity` sütunu olarak anında güncellenir. Ancak `sync_v4_changes` replikasyon günlüğüne **ayrı bir `product` güncelleme olayı yazılmaz!**
- Yalnızca `entity_type: 'sale'` veya `entity_type: 'refund'` olayı yazılır.
- Bir `product` olayının `sync_v4_changes` tablosuna yazılması, yalnızca katalog üzerinden (fiyat/isim/ürün kartı düzenlemesi) bir `UPSERT product` mutasyonu yapıldığında gerçekleşir.
- **Etiket:** `DOĞRULANDI`

### 8. Pull sırasında bir satış olayı görülürken stok snapshot'ı eskiyse istemci bunu anlayabiliyor mu?
- **HAYIR!** İstemci pull yaptığında gelen `SyncPullChange` DTO'su içinde [sync_dtos.dart:10-30](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/sync_dtos.dart#L10-L30) yalnızca `{ revision, mutationId, entityType, entityId, operation, payload, createdAt }` yer alır.
- Gelen bir `product` snapshot'ının hangi satış olayına kadar olan düşümleri kapsadığına dair hiçbir alan (`stock_applied_through_seq` vb.) **bulunmamaktadır**.
- **Etiket:** `SUNUCU/MİMARİ ENGELİ`

---

## 3. KAYNAK KODLA KANITLANMIŞ MİMARİ AÇIKLAR

### Açık 1: Sunucu Satış İşlediğinde `product` Değişiklik Olayı Üretmiyor
- **Dosya:** [sync-v4.routes.ts:220-235](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L220-L235)
- **Kanıt:** Sunucu `POST /api/v4/sync/push` çağrısında `applyDomainMutation` ile `products.quantity` değerini düşürür, ancak `sync_v4_changes` tablosuna **yalnızca istemcinin gönderdiği `entity_type: 'sale'` olayını yazar**. Düşen stok miktarını gösteren yeni bir `entity_type: 'product'` olayı `sync_v4_changes` içine eklenmez.
- **Sonuç:** Başka bir kasa (`Kasa B`) `GET /api/v4/sync/pull` yaptığında yalnızca `sale` olayını alır. Güncel ürün stok miktarı Kasa B'ye bir replikasyon olayı olarak iletilmez.

### Açık 2: İstemci Pull Servisi `sale` Olayını Tüketip Stok Düşmüyor
- **Dosya:** [sync_v4_pull_ingestion_service.dart:119-128](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L119-L128)
- **Kanıt:**
  ```dart
  if (change.entityType.toLowerCase() == 'product') {
    await _ingestProduct(txn, change, isDeleted);
    prodCount++;
  } else if (change.entityType.toLowerCase() == 'customer') {
    await _ingestCustomer(txn, change, isDeleted);
    custCount++;
  } else {
    otherCount++; // 'sale', 'refund', 'order' burada sessizce yutuluyor!
  }
  ```
- **Sonuç:** Kasa B, pull sırasında Kasa A'nın yaptığı satışı (`entity_type: 'sale'`) alsa bile, bu satıştaki ürünlerin stoğunu yerel veritabanında **düşürmez**. `otherCount++` yapılarak geçilir. Dolayısıyla Kasa B'de ürün stoğu Kasa A'nın satışından sonra da **eski ve yüksek** kalır!

### Açık 3: `_calculateUnreflectedSoldQty` Yalnızca Yerel Kasanın Outbox'ını Bilir
- **Dosya:** [sync_v4_pull_ingestion_service.dart:250-255](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L250-L255)
- **Kanıt:**
  ```sql
  SELECT si.quantity, se.sync_state, se.base_revision, se.client_timestamp
  FROM sale_items si
  JOIN sync_events se ON se.entity_id = si.sale_id AND se.entity_type = 'sale'
  WHERE si.product_id = ?
  ```
- **Sonuç:** Bu sorgu yalnızca yerel kasanın kendi SQLite tablosundaki satışları okur. Kasa A çevrimdışı 2 adet sattıysa, Kasa B'nin SQLite tablosunda bu satışın kaydı yoktur. Kasa B sunucudan eski bir snapshot aldığında bu delta'yı hesaplayamaz.

### Açık 4: Global Replication Cursor ile Ürün Snapshot Revizyonu Arasındaki Anlamsal Kopukluk
- **Dosya:** [sync-v4.routes.ts:371-375](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L371-L375)
- **Kanıt:** `sync_v4_changes.revision`, kiracı bazında tek bir PostgreSQL sequence (`BIGSERIAL`) tarafından artırılır. Bir müşteri adresi değiştiğinde revizyon 100'e çıkar; bir satış yapıldığında 101 olur. Bu sayaç ürünün kendi versiyonu değildir.
- İstemcideki `changeRevision < baseRev` kontrolü ([sync_v4_pull_ingestion_service.dart:269](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L269)), ilgisiz bir müşteri veya katalog güncellemesi geldiğinde yanlış sonuç üretir ve satış deltasını sıfırlayarak eski stoğu geri getirir.

---

## 4. ÇOK KASALI SENARYOLARIN ADLİ ANALİZİ

### Senaryo A — Normal Senkronizasyon (İki Kasa, Sıralı Satış)
1. Başlangıç stok: Ürün X = 10.
2. Kasa A çevrimdışı 2 adet satar -> Kasa A yerel stok = 8.
3. Kasa A senkronize olur (`POST /push`):
   - Sunucu `products.quantity` = 8 yapar.
   - Sunucu `sync_v4_changes` tablosuna `entity_type: 'sale', revision: 50` ekler.
4. Kasa B senkronize olur (`GET /pull`):
   - Kasa B `revision: 50` olarak `sale` olayını alır.
   - **Mevcut Davranış:** Kasa B `_applyChanges` içinde `sale` olayını işlemez (`otherCount++`). Kasa B'nin yerel stoğu **10 olarak kalır**.
   - **Beklenen Davranış:** Kasa B'nin yerel stoğu 8'e inmelidir.
   - **Etiket:** `CANLIYA GEÇİŞİ ENGELLİYOR`

### Senaryo B — Eşzamanlı Çevrimdışı Satış (Stok Aşımı / Overselling)
1. Başlangıç stok: Ürün X = 5.
2. Kasa A çevrimdışı 4 adet satar -> Kasa A yerel stok = 1.
3. Kasa B çevrimdışı 3 adet satar -> Kasa B yerel stok = 2.
4. İki kasa da çevrimiçi olur ve sunucuya push yapar:
   - Kasa A push: Sunucu stoğu `5 - 4 = 1` yapar, onaylar.
   - Kasa B push: `upsertSale` stok kontrolü yapmadığı için stoğu `1 - 3 = -2` yapar, onaylar!
5. **Analiz Yanıtları:**
   - *1. Sunucu stok verisi deterministik biçimde yakınsayabilir mi?*
     - Evet, sunucudaki matematiksel stok deterministiktir (`5 - 4 - 3 = -2`).
   - *2. Sistem stok yetersizliğini engelliyor mu, yoksa negatif stoğu sonradan mı uzlaştırıyor?*
     - Sistem stok aşımını **engellemez**; negatif stoğa izin verir. Çevrimdışı kasalar birbirini bilmediği için 5 adet olan fiziki üründen toplam 7 adet satılmış olur.
   - **Etiket:** `DOĞRULANDI`

### Senaryo C — Aynı Satışın Tekrar Gönderilmesi (Zaman Aşımı / Retry)
1. Kasa A satış mutasyonunu gönderir; sunucu işler ancak HTTP yanıtı ağda kaybolur.
2. Kasa A aynı `mutation_id` ile isteği tekrarlar.
3. Sunucu `sync-v4.routes.ts:136` kontrolüyle `sync_v4_changes` içinde kaydı bulur, mevcut revizyonu döner, `upsertSale` ikinci kez çağrılmaz.
4. Stok ikinci kez eksilmez; mükerrer kayıt oluşmaz.
5. **Etiket:** `DOĞRULANDI`

### Senaryo D — Kısmi veya Sırasız Pull (Snapshot ile Olay Çakışması)
1. Kasa A satış yapar (stok 10 -> 8).
2. Kasa B `bootstrap` veya katalog güncellemesi ile ürün snapshot'ı (stok: 8) alır.
3. Ancak hemen ardından eski bir pull sayfasından gecikmiş bir `product` güncellemesi (stok: 10) gelirse:
   - Kasa B'nin `SyncV4PullIngestionService` servisi `changeRevision` kontrolünde çuvallarsa yerel stok 10'a fırlar.
4. **Etiket:** `CANLIYA GEÇİŞİ ENGELLİYOR`

### Senaryo E — Sonradan İade veya İptal
1. Senkronize edilmiş satış Kasa A'da iade edilir.
2. Kasa A iade mutasyonunu push eder (`entity_type: 'refund'`).
3. Sunucu `RefundService.create` ile `products.quantity = quantity + 1` yapar ve `inventory_movements` (refund) ekler.
4. `sync_v4_changes` tablosuna `entity_type: 'refund'` yazılır.
5. Kasa B pull yaptığında:
   - `refund` olayı `SyncV4PullIngestionService` tarafından **yine işlenmez** (`otherCount++`). Kasa B iade edilen stoğun arttığını göremez.
6. **Etiket:** `CANLIYA GEÇİŞİ ENGELLİYOR`

---

## 5. GEREKLİ MİNİMUM SUNUCU PROTOKOLÜ DEĞİŞİKLİKLERİ

Sunucu kod tabanında gereksiz büyük refactoring yapmadan ve veri bütünlüğünü bozmadan uygulanması gereken asgari mimari değişiklikler şunlardır:

### 5.1. Nedensellik Analizi ve `stock_applied_through_seq` İncelemesi
1. **Global Değişiklik Sequence'i ile Ürün Bazlı Revision Ayrımı:**
   - Mevcut durumda `sync_v4_changes.revision` kiracı bazında artan global bir sayaçtır (`BIGSERIAL`).
   - Bir müşteri güncellendiğinde revizyon 105 olur; bir satış yapıldığında 106 olur.
   - Ürün tablosunda ise sadece `updated_at` vardır; ürünün hangi replikasyon revizyonunda olduğunu belirten bağımsız bir `product_revision` yoktur.
2. **Olay Kabulü ile Stok Projeksiyonu Ayrımı:**
   - Bir satış mutasyonunun kabul edilmesi (`sync-v4.routes.ts`) ile `products.quantity` değerinin azaltılması şu anda aynı transaction içindedir (atomiktir).
   - Ancak bu düşüm, **replikasyon akışına yansıtılmamaktadır**. Dolayısıyla olay sunucuda kabul edilmiş ve yerel projeksiyona uygulanmış olsa da, replike edilebilir stok projeksiyonuna dönüşmemektedir.
3. **Pull Cursor İlerlemesi ile Ürün Snapshot Güncelliği:**
   - İstemci pull yaparken bir cursor (`since_revision`) bildirir.
   - Eğer sunucu istemciye bir ürün snapshot'ı (`entity_type: 'product'`) gönderiyorsa, bu snapshot'ın veritabanındaki o anki anlık durumu mu yoksa `since_revision` anındaki geçmiş durumu mu temsil ettiği belirsizdir.
   - Bu durum, pull cursor'ının ilerlemesi ile alınan stok değerinin uyuşmamasına yol açar.
4. **`stock_applied_through_seq` Gereklilik Değerlendirmesi:**
   - Bir ürün snapshot'ının güvenle yerel SQLite'a yazılabilmesi için, snapshot ile birlikte şu bilginin gelmesi gerekir: *"Bu stok snapshot'ı, global revizyonu N değerine kadar olan tüm satış ve iadeleri içermektedir."* (`stock_applied_through_seq: N`).
   - Eğer istemci yerel kuyruğunda revizyonu `> N` olan bekleyen satışları varsa, yalnızca o satışların miktarını düşer; `≤ N` olanları ise snapshot'ın zaten içerdiğini bilerek ikinci kez düşmez.
   - **Sonuç:** `stock_applied_through_seq` olmadan istemcinin rastgele timestamp veya yerel kuyruk farkı alarak doğru stok hesaplaması **matematiksel olarak imkansızdır**.

### 5.2. Minimum Sunucu Değişikliği (Türetilmiş Stok Değişim Olayı veya Snapshot Yayını)
Sunucuda uygulanacak asgari müdahale ([sync-v4.routes.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts)):
1. `upsertSale` ve `RefundService.create` tamamlandığında, etkilenen her ürün için aynı transaction içinde `sync_v4_changes` tablosuna bir replikasyon kaydı eklenmelidir:
   - Seçenek A (Önerilen): `entity_type: 'product'` için güncel `quantity` ve `stock_applied_through_seq: revision` içeren `UPSERT` kaydı eklenir.
   - Seçenek B (Delta Modeli): `entity_type: 'product_stock_delta'` adında türetilmiş bir olay yazılarak `quantity_delta: -$qty`, `sale_id: $sale_id` duyurulur.

---

## 6. İSTEMCİ TARAFINDA GEREKLİ DEĞİŞİKLİKLER

İstemci kod tabanında (`core_next/client_core/lib/infrastructure/sync/`):

1. **`SyncV4PullIngestionService` Güncellemesi:**
   - [sync_v4_pull_ingestion_service.dart:119-138](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L119-L138) içindeki `otherCount++` bloğundan `sale` ve `refund` olayları çıkarılmalıdır.
   - Gelen `sale` olayı Kasa B'ye ulaştığında:
     - Eğer `change.deviceId != localDeviceId` ise (yani satış bu kasanın kendi satışı değilse), satıştaki ürünlerin miktarları yerel SQLite `products.quantity` tablosundan atomik olarak düşülmelidir.
     - Eğer satış bu kasanın kendi satışı ise (`change.deviceId == localDeviceId`), yerel stok zaten satış anında düşüldüğü için tekrar düşülmemelidir (idempotency).
2. **`_calculateUnreflectedSoldQty` Mantığının Düzeltilmesi:**
   - [sync_v4_pull_ingestion_service.dart:244-277](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L244-L277) fonksiyonunda, ürün snapshot'ı geldiğinde yerel outbox'taki PENDING satışların düşümü, sunucudan gelen `stock_applied_through_seq` bilgisine göre filtrelenmelidir.

---

## 7. TEST MATRİSİ VE KABUL KRİTERLERİ

Stage 10.6 aşamasında kod değişikliği yapıldığında çalıştırılacak zorunlu 10 senaryolu test matrisi:

| No | Test Adı | Başlangıç Durumu | İşlem Sırası | Beklenen Sunucu Durumu | Beklenen İstemci Durumu (Kasa A & B) | Kabul/Ret Şartı |
|---|---|---|---|---|---|---|
| **T-1** | Aynı idempotency anahtarıyla tekrarlanan push | Ürün X stok = 10 | Kasa A aynı `mutation_id` ile satış push'unu 2 kez gönderir | `products.quantity = 9`, tek `sales` kaydı, tek `inventory_movement` | Kasa A stok = 9; Kasa B stok = 9 | Stok 2. kez düşerse RET |
| **T-2** | Aynı anahtarla değiştirilmiş payload | Ürün X stok = 10 | Kasa A satış gönderir (1 adet). Ardından aynı `sale_id` fakat 2 adetlik payload push eder | İlk satış ve stok (9) korunur; sunucu tutarsızlığı reddeder veya ilk kaydı döner | Kasa A ve B stok = 9 | İkinci payload sessizce stoğu 8 yaparsa RET |
| **T-3** | Eşzamanlı iki kasanın aynı ürünü satması | Ürün X stok = 5 | Kasa A çevrimdışı 3 adet, Kasa B çevrimdışı 3 adet satar; ikisi de push eder | `products.quantity = -1`, iki sale kaydı, iki hareket | Kasa A stok = -1, Kasa B stok = -1 | Kasalar farklı stokta kalırsa RET |
| **T-4** | Çok satırlı satış | Ürün X stok = 10, Ürün Y stok = 5 | Kasa A: Sepette 2 adet X ve 3 adet X (ayrı satırlar), 1 adet Y satar | X stok = 5 (10-5), Y stok = 4 | Kasa A ve B stokları: X=5, Y=4 | X için sadece 2 veya 3 düşülürse RET |
| **T-5** | Stok hareketi ile change log rollback | Ürün X stok = 10 | Satış sırasında `sync_v4_changes` insert aşamasında DB hatası simüle edilir | `products.quantity = 10`, hiçbir hareket veya sale yazılmaz (Rollback) | Kasa A işlemi outbox'ta bekletir | Stok düşüp log yazılmazsa RET |
| **T-6** | Sayfalı ve tekrarlanan pull | 50 adet farklı satış | Kasa B `limit=10` ile 5 sayfa pull yapar; sayfa 2'yi tekrarlar | 50 satış replikasyon kaydı değişmez | Kasa B tüm 50 satışın stok düşümünü tam ve eksiksiz uygular | Mükerrer düşüm veya atlama olursa RET |
| **T-7** | Snapshot ile cursor tutarlılığı | Ürün X stok = 10 | Satış yapılır (stok 8). Kasa B pull sırasında katalog güncellemesi (snapshot) ve satış olayını ardışık alır | Sunucu revizyonları sıralı | Kasa B nihai stok = 8; eski snapshot yeni satışı ezmez | Stok 10'a geri dönerse RET |
| **T-8** | Bootstrap ardından incremental pull | Mağazada 100 ürün ve 500 geçmiş satış | Kasa B sıfırdan `bootstrap` çeker, ardından ilk incremental pull yapar | Sunucu bootstrap cursor verir | Kasa B bootstrap stoğu üzerine mükerrer satış düşümü yapmaz | Geçmiş satışlar 2. kez düşülürse RET |
| **T-9** | İade/iptal ve yeniden senkronizasyon | Ürün X stok = 8 | Kasa A 1 adet iade alır ve push eder. Kasa B pull yapar | `products.quantity = 9`, `inventory_movements` (refund) | Kasa A stok = 9, Kasa B stok = 9 | Kasa B'de stok 8'de kalırsa RET |
| **T-10** | Eski protokol istemcisiyle uyumluluk | Ürün X stok = 10 | Eski v3/v4 istemci `sale` push eder; yeni Stage 10.6 istemcisi pull yapar | Sunucu eski istemcinin mutasyonunu kabul eder ve replike eder | Yeni istemci satışı doğru işler | Eski istemci 500 alırsa RET |

---

## 8. GERİYE UYUMLULUK VE MİGRATİON RİSKLERİ

1. **Eski İstemci Uyumluluğu:**
   - Mevcut üretimdeki mobil ve masaüstü istemciler `POST /api/v4/sync/push` yaparken `client_version: 6` kullanmaktadır.
   - Sunucuda `sync_v4_changes` tablosuna `entity_type: 'product'` olaylarının eklenmesi, eski istemciler için zararsızdır; çünkü eski istemciler `product` olaylarını zaten işlemektedir (ürün katalog güncellemesi gibi).
2. **Replikasyon Günlüğü Büyüme Riski:**
   - Her satış için ek bir `sync_v4_changes` satırı yazılması, yoğun perakende operasyonlarında `sync_v4_changes` tablosunun iki kat hızlı büyümesine yol açar.
   - Bu nedenle `sync_v4_changes` için mevcut 30 günlük arşivleme / vakum politikası gözden geçirilmelidir.
3. **Migration İhtiyacı:**
   - Veritabanında yeni bir tablo eklenmesine gerek yoktur. Mevcut `sync_v4_changes` şeması ([schema_v52.sql](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/db/schema_v52.sql)) JSONB payload desteklediği için şema migration'ı gerektirmez.

---

## 9. AÇIK KALAN SORULAR VE KANITLANAMAYAN İDDİALAR

1. **Çevrimdışı Stok Aşımı (Overselling) Politikası:**
   - *Soru:* İki kasa çevrimdışı iken aynı son ürünü satarsa sunucu ne yapmalı?
   - *Kanıt:* Kodda hiçbir engelleyici kontrol yoktur (`DOĞRULANDI`). Sunucu stoğu eksiye indirir.
   - *Karar:* Perakende sektöründe satışın kasada iptal edilmemesi esastır; bu ticari bir tercihtir. Ancak teknik olarak sistemin stok aşımını önlediği iddia edilemez.
2. **Katalog Fiyat Revizyonu ile Hareket Revizyonunun Ayrımı:**
   - Sunucudaki tek global sayaç nedeniyle, katalogdaki bir fiyat değişikliği ile stok hareketi aynı replikasyon günlüğünde yarışır. Bu durum istemcide stok hesaplarken katalog alanlarının yanlışlıkla ezilmemesini gerektirir.

---

## 10. CANLIYA GEÇİŞ ENGELLERİ VE NİHAİ KARAR

### NİHAİ KARAR:
> **CANLI SATIŞ EKRANINA ENTEGRASYON: BLOCKED (DURDURULDU)**

### Gerekçeler ve Kanıtlar:
1. **[CANLIYA GEÇİŞİ ENGELLİYOR] Sunucu Satış Sonrası Stok Yayını Yapmıyor:**
   - [sync-v4.routes.ts:220-235](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L220-L235) dosyasında görüldüğü üzere, sunucu satış işlendiğinde `sync_v4_changes` tablosuna sadece `entity_type: 'sale'` yazmaktadır; ürün stok değişimini duyurmamaktadır.
2. **[CANLIYA GEÇİŞİ ENGELLİYOR] İstemci Pull Servisi Satış Olaylarını Yutuyor:**
   - [sync_v4_pull_ingestion_service.dart:136-138](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L136-L138) kodunda `sale` ve `refund` olayları `otherCount++` ile sessizce yutulmakta, diğer kasaların stokları yerel veritabanında asla düşmemektedir.
3. **[SUNUCU/MİMARİ ENGELİ] Nedensel Cursor Sözleşmesi Eksikliği:**
   - İstemciye dönen ürün snapshot'larının hangi olay revizyonuna kadar olan hareketleri yansıttığını belirten `stock_applied_through_seq` sözleşmesi mevcut değildir.

### Stage 10.6 Uygulama İzni İçin Gerekli Dosya Yetkileri:
Bu aşamada salt okunur sınırlar korunmuştur. Stage 10.6 aşamasında engelleri kaldırmak için şu dosyalarda değişiklik yapılması gerekecektir:
1. `server/src/modules/sync_v4/sync-v4.routes.ts` (Sunucu stok değişim olayının duyurulması).
2. `core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart` (İstemcide diğer kasalardan gelen satışların yerel stoğa yansıtılması).
3. `test/core_next/` (Çok kasalı senkronizasyon testlerinin eklenmesi).
