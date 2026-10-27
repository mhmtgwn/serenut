# SERENUT OS — STAGE 8.2A: SENKRONİZASYON SÖZLEŞMESİ FORENSİK DENETİM RAPORU

**Tarih:** 2026-10-13  
**Denetim Kapsamı:** Üretim Sunucusu Sync V4 (Protocol 6) Sözleşmesi ile `core_next` Veri Modeli ve Kuyruk Mimarisi Bağımsız Karşılaştırmalı Denetimi  
**Denetçi:** Antigravity Bağımsız Güvenlik ve Mimari Denetim Ajanı  
**Hedef Rapor:** `CORE_NEXT_STAGE8_2A_SYNC_CONTRACT_AUDIT.md`  

---

## 1. GİRİŞ VE GİT GÜVENLİK DURUMU

Bu denetim, `core_next` mimarisi üzerinde herhangi bir istemci kodu geliştirmeden veya sunucuya canlı istek göndermeden önce yapılmıştır. Yalnızca mevcut sunucu kaynak kodları ([`server/src/`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src)), eski istemci senkronizasyon kodları ([`lib/infrastructure/sync_v4/`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/sync_v4)) ve `core_next` modülü ([`core_next/client_core/`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core)) satır satır incelenmiştir.

### Gerçek Git Durumu (Doğrulandı)
- **Aktif Branch:** `main`
- **HEAD Commit SHA:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **`git diff HEAD --stat`:** `0 files changed` (Tertemiz, hiçbir izinsiz değişiklik yok)
- **`lib/` Değişiklik Durumu:** `0` dosya değiştirildi (`lib/` bütünüyle korunmaktadır).

---

## 2. ÜRETİM SUNUCUSU SÖZLEŞMESİ (SYNC V4 / PROTOCOL 6)

Üretim sunucusunun gerçek kod yolundaki senkronizasyon rotaları, yetkilendirme mekanizmaları, başlıkları ve DTO yapıları aşağıda dosya ve satır aralıklarıyla kanıtlanmıştır.

### 2.1. Route Tanımları ve Mount Noktası
- **Router Kaydı:** [`server/src/server.ts:L417`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/server.ts#L417)
  ```ts
  app.use('/api/v4/sync', syncV4Router);
  ```
- **Protokol Tanımı:** [`server/src/modules/sync_v4/sync-v4.routes.ts:L35`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L35)
  `const syncProtocolVersion = 6;`
- **Tam Endpoint'ler:**
  1. `POST /api/v4/sync/push` ([`sync-v4.routes.ts:L54`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L54))
  2. `GET /api/v4/sync/pull` ([`sync-v4.routes.ts:L344`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L344))
  3. `GET /api/v4/sync/bootstrap` ([`sync-v4.routes.ts:L390`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L390))

### 2.2. Kimlik Doğrulama ve Zorunlu Başlıklar (Headers)
Tüm `/api/v4/sync/*` rotaları aşağıdaki ara yazılımlardan (middleware) geçer:
1. **Kimlik Doğrulama:** `authenticateUser` ([`sync-v4.routes.ts:L37`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L37)). `Authorization: Bearer <JWT_TOKEN>` zorunludur.
2. **Aktif Lisans / Hak Kontrolü:** `requireActiveEntitlement` ([`sync-v4.routes.ts:L38`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L38)).
3. **Protokol Sürüm Denetimi:** ([`sync-v4.routes.ts:L39-L48`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L39-L48))
   - Header: `x-sync-protocol-version`
   - Kural: `req.header("x-sync-protocol-version") === "6"`
   - Eşleşmezse Yanıt: **HTTP 426 Upgrade Required**
     ```json
     {
       "error": "sync_protocol_upgrade_required",
       "required_version": 6,
       "message": "Senkronizasyon protokolü güncel değil. Lütfen uygulamayı güncelleyin."
     }
     ```
4. **Cihaz Doğrulama Başlıkları:**
   - `x-device-activation-id` (veya body'de `device_activation_id`)
   - `x-device-id` (veya body'de `device_id`)
   - Sunucu, `device_activations` tablosunda `id = $1 AND company_id = $2 AND device_hash = $3 AND status = 'active'` kaydını kilitler (`FOR UPDATE`, satır 71-78). Bulunamazsa `HTTP 403 (invalid_device_activation)` döner.

### 2.3. Push İstek ve Yanıt DTO'su

#### İstek (Request) Formatı:
- **Batch Boyut Sınırı:** En fazla 100 mutasyon (`mutations.length > 100` -> HTTP 400 `invalid_sync_request`, satır 59-61).
- **Mutasyon Doğrulama Kuralları ([`sync-v4.routes.ts:L111-L125`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L111-L125)):**
  - `mutation_id`: UUIDv4 formatında dize (`uuidPattern`).
  - `entity_type`: **Kesinlikle küçük harf** `product`, `customer`, `order`, `sale`, `financial_transaction`, `refund` kümesinden biri olmalı ([`sync-v4.routes.ts:L25-L32`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L25-L32)).
  - `entity_id`: Dize, en fazla 128 karakter.
  - `operation`: Yalnızca `"UPSERT"` veya `"DELETE"`.
  - `base_revision`: Güvenli tamsayı ve `>= 0` (`Number.isSafeInteger(mutation.base_revision) && mutation.base_revision >= 0`).
  - `payload`: Boş olmayan JSON nesnesi (`typeof mutation.payload === 'object' && mutation.payload !== null`), boyutu `< 256 KB`.

#### Yanıt (Response) Formatı ([`sync-v4.routes.ts:L325`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L325)):
```json
{
  "results": [
    { "mutation_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "revision": 142 }
  ],
  "conflicts": [
    {
      "mutation_id": "uuid",
      "entity_type": "product",
      "entity_id": "prod-1",
      "server_revision": 145
    }
  ],
  "rejected": [
    {
      "mutation_id": "uuid",
      "error": "invalid_sale"
    }
  ]
}
```

### 2.4. Pull İşlemi ve DTO'su ([`sync-v4.routes.ts:L344-L382`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L344-L382))
- **Route:** `GET /api/v4/sync/pull?cursor=140&limit=200&device_activation_id=...&device_id=...`
- **Sorgu Parametreleri:**
  - `cursor`: Tamsayı, varsayılan 0.
  - `limit`: Min 1, Maks 500, varsayılan 200.
- **Veritabanı Kaynağı:** `sync_v4_changes` tablosu (`WHERE tenant_id = $1 AND revision > $2 ORDER BY revision ASC LIMIT $3`).
- **Yanıt DTO'su:**
  ```json
  {
    "changes": [
      {
        "revision": 141,
        "mutation_id": "uuid",
        "device_id": "installation-id",
        "entity_type": "product",
        "entity_id": "p-1",
        "operation": "UPSERT",
        "payload": { ... },
        "created_at": "2026-10-13T12:00:00Z"
      }
    ],
    "next_cursor": 141
  }
  ```

### 2.5. Idempotency, Çakışma ve Kilitleme Mekanizması
1. **Advisory Locks (PostgreSQL Danışman Kilitleri):**
   - Sıfırlama bariyeri için: `pg_advisory_xact_lock(hashtext(company_id), hashtext('operational-reset'))` ([satır 83](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L83)).
   - Varlık başına kilitleme: `pg_advisory_xact_lock(hashtext(company_id), hashtext("${entity_type}:${entity_id}"))` ([satır 146](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L146)). Eşzamanlı iki isteğin aynı varlığı aynı anda bozması engellenir.
2. **Mutation Idempotency Kontrolü:**
   - [`sync-v4.routes.ts:L132-L141`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L132-L141):
     `SELECT revision FROM sync_v4_changes WHERE tenant_id = $1 AND mutation_id = $2::uuid`.
   - Eğer `mutation_id` daha önce işlenmişse, varlık tekrar materyalleştirilmez, kaydedilmiş olan `revision` doğrudan `results` listesine eklenir ve mutasyon atlanır.
3. **Çakışma Tespiti (Conflict Resolution):**
   - [`sync-v4.routes.ts:L154-L178`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L154-L178):
     Eğer `currentRevision > mutation.base_revision` ise ve son değişikliği yapan `device_id` istek yapan cihazdan farklıysa, bu bir gerçek eşzamanlı çakışmadır. Mutasyon `sync_v4_conflicts` tablosuna yazılır ve `conflicts` dizisinde istemciye döndürülür; veritabanı ezilmez.
4. **Tombstone ve Silme Güvenliği:**
   - [`sync-v4.routes.ts:L200-L209`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L200-L209):
     Silinmiş bir varlık (`is_deleted = true`), başka bir cihazdan gelen eski bir `UPSERT` ile diriltilemez. Sunucu işlemi otomatik olarak `"DELETE"`e çevirir (yalnızca `reactivate_deleted: true` bayrağı açıkça gönderilmişse istisnadır).

---

## 3. İSTEMCİ MODELİ İLE SUNUCU DTO'LARININ KARŞILAŞTIRMASI

Aşağıdaki tablo, `core_next` veri modeli ve [`checkout_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L253-L261) içindeki `sync_events` üretimi ile sunucu Sync V4 / Protocol 6 sözleşmesi arasındaki uyumluluğu göstermektedir.

### 3.1. Alan Alan Uyumluluk Matrisi

| Parametre / Alan | Sunucu Sync V4 Beklentisi | `core_next` (`sync_events` / `checkout_use_case`) | Durum | Risk & Hata Kodu |
| :--- | :--- | :--- | :--- | :--- |
| **Mutation ID** | `mutation_id`: UUIDv4 dizesi | `event_id`: UUIDv4 dizesi ([`schema_definitions.dart:L161`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/schema_definitions.dart#L161)) | ⚠️ İsim Farkı | JSON mapping katmanı `event_id` -> `mutation_id` çevirisi yapmalıdır. |
| **Entity / Tür Adı** | Küçük harf: `"product"`, `"customer"`, `"sale"`, `"order"`, `"financial_transaction"`, `"refund"` | Büyük harf: `'SALE'` ([`checkout_use_case.dart:L255`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L255)) | ❌ **UYUMSUZ** | Sunucu `entityTypes.has("SALE")` kontrolünde başarısız olur ve **HTTP 400 `invalid_mutation`** fırlatır! |
| **Entity ID** | `entity_id`: Dize (`<= 128` kar.) | `entity_id`: `saleId` UUIDv4 ([`checkout_use_case.dart:L256`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L256)) | ✅ UYUMLU | Değer formatı ve uzunluğu uygundur. |
| **Base Revision** | `base_revision`: Güvenli tamsayı `>= 0` zorunlu | **ALAN YOK!** `sync_events` tablosunda `base_revision` sütunu bulunmuyor! | ❌ **UYUMSUZ** | Sunucu `!Number.isSafeInteger(mutation.base_revision)` ile **HTTP 400 `invalid_mutation`** fırlatır! |
| **Oluşturulma Zamanı** | Header/Body `created_at` ISO8601 veya `client_timestamp` | `client_timestamp`: `INTEGER` (Epoch ms) ([`schema_definitions.dart:L166`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/schema_definitions.dart#L166)) | ⚠️ Dönüşüm Gerekli | Payload içinde `created_at` ISO8601 dizesine dönüştürülmelidir. |
| **Payload Kalemleri (`items`)** | `payload.items`: Dolu dizi zorunlu (`product_id`, `quantity`, `unit_price`, `subtotal`) | **YOK!** `checkout_use_case` içindeki `payload_json` kalemleri İÇERMİYOR! | ❌ **KRİTİK UYUMSUZ** | Sunucu `upsertSale` içinde `if (!items.length) throw new Error("invalid_sale")` fırlatır! |
| **Para Birimi & Tutar** | Ondalık Lira (float/decimal): `total_amount`, `paid_amount`, `discount_amount` | Kuruş (integer cents): `total_cents`, `paid_cents`, `debt_cents` | ❌ **KRİTİK UYUMSUZ** | İsimler ve birimler uyuşmuyor; sunucu `sale_total_mismatch` fırlatır. |
| **Ödeme Yöntemi** | `payment_method`: `"cash"`, `"card"`, `"credit"`, `"mixed"`, `"veresiye"`, `"debt"`, `"karma"` | **YOK!** `payload_json` içinde `payment_method` alanı bulunmuyor. | ❌ **KRİTİK UYUMSUZ** | Sunucu `upsertSale` satır 172'de `invalid_sale` fırlatır. |
| **Protokol Sürümü** | `x-sync-protocol-version: 6` | `core_next` istemcisinde ağ katmanı ve başlık henüz yazılmadı. | ⚠️ Eksik Bileşen | İstemci ağ servisi yazılırken başlık Protocol 6 olarak ayarlanmalıdır. |
| **Hata / Tekrar Deneme** | İstemcinin `attempts`, `error_message`, `REJECTED` durumlarını yönetmesi | `sync_events` yalnızca `sync_state: 'PENDING' \| 'SYNCED'` tutuyor. | ❌ **Eksik Alanlar** | Tekrar deneme ve poison-pill yönetimi için `attempts`, `last_error` alanları eksik. |

---

## 4. FİNANSAL TUTARLILIK RİSKLERİ

Forensik incelemede `core_next` satış motoru ile sunucu Sync V4 materyalizasyonu arasında tespit edilen finansal riskler:

### 4.1. Bir Satışın Kısmen Senkronize Edilip Finansal Olarak Yarım Kalması Riski
- **Sunucu Tarafı Garantisi:** Sunucuda [`sync-v4.materializer.ts:L163-L258`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L163-L258) `upsertSale` fonksiyonu, satış başlığı (`sales`), stok düşümü (`products.quantity`), stok hareketi (`inventory_movements`) ve satış kalemlerini (`sale_items`) tek bir PostgreSQL transaction'ı içinde atomik olarak yürütür. Sunucuda satışın kalemi kaydedilip başlığının kaydedilmemesi imkansızdır.
- **`core_next` Açığı (KRİTİK):** 
  [`checkout_use_case.dart:L237-L248`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L237-L248) veresiye satışta yerel SQLite'ta `customer_ledger` tablosuna borç kaydı atar. Ancak `sync_events` kuyruğuna **yalnızca tek bir `'SALE'` mutasyonu ekler**.
  Sunucudaki `upsertSale` fonksiyonu müşteri borcunu (`customers.balance` veya `financial_transactions`) **GÜNCELLEMEZ** ([satır 232-257](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L232-L257)). Müşteri cari borcu sunucuda ayrı bir `entity_type: "financial_transaction"` mutasyonu gerektirir ([satır 339-440](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L339-L440)).
  **Sonuç:** Mevcut `core_next` kodu senkronize edilirse, sunucuda satış gerçekleşir ve stok düşer, fakat **müşterinin cari borcu sunucuya ASLA yansımaz!**

### 4.2. Mükerrer İstek (Duplicate Mutation) ve Çift Finansal Etki Riski
- **Bulgu:** Sunucu iki kademeli idempotency korumasına sahiptir:
  1. `sync_v4_changes` tablosu `(tenant_id, mutation_id::uuid)` üzerinde benzersizdir. Aynı `mutation_id` tekrar gelirse materyalizasyon çalıştırılmadan önceki revizyon döndürülür ([`sync-v4.routes.ts:L132-L141`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L132-L141)).
  2. `sales` tablosu `SELECT id FROM sales WHERE id = $1 FOR UPDATE` ile kontrol edilir. Varsa `immutable_sale` kuralı gereği hiçbir şey yapmadan çıkar (`if (prior.rowCount) return;`, [`sync-v4.materializer.ts:L181`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L181)).
- **Şart:** İstemci, bir ağ kesintisinde tekrar denerken `mutation_id` değerini değiştirmemeli, yerel `sync_events.event_id` değerini korumalıdır. Yeni bir UUID üretilirse sunucuda mükerrer finansal kayıt riski doğar!

### 4.3. Yanıt Kaybında (In-Flight Drop) Güvenli Tekrar
- Eğer sunucu `COMMIT` yaptıktan sonra yanıt dönerken ağ kesilirse, istemci mutasyonun ulaşıp ulaşmadığını bilemez.
- İstemci aynı `mutation_id` ile tekrar gönderdiğinde sunucu bunu güvenle tanır ve yan etki üretmeden revizyon numarasını teslim eder.

### 4.4. Sunucu Kabul Ettikten Sonra İstemci Kuyruğu Silinemezse (Outbox Retention)
- İstemci yanıtı aldı fakat yerel SQLite'ta `sync_events` tablosunu `SYNCED` yapamadan cihaz çöktü veya kapandı.
- Cihaz açıldığında mutasyonu tekrar gönderir. Sunucu idempotent olarak yine önceki revizyonu onaylar. İstemci bu kez yerel kaydı günceller. Veri kaybı veya mükerrer stok düşüşü yaşanmaz.

### 4.5. İki Cihazdan Eşzamanlı Güncelleme (Concurrency & Conflicts)
- Bir ürün veya müşteri iki farklı POS cihazından eşzamanlı güncellenirse:
  - Sunucu `pg_advisory_xact_lock` ile aynı varlığın paralel işlemlerini kuyruğa sokar.
  - İlk gelen işlem revizyonu artırır (ör. revizyon 12 -> 13).
  - İkinci cihaz `base_revision: 12` ile geldiğinde `currentRevision (13) > mutation.base_revision (12)` şartı tetiklenir.
  - Farklı bir cihaz olduğu için mutasyon ezilmez; `sync_v4_conflicts` tablosuna yazılır ve istemciye `conflicts` dizisinde bildirilir ([`sync-v4.routes.ts:L164-L177`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L164-L177)).

### 4.6. Mutasyon Sıralaması (Causal Dependency Ordering)
- **Kritik Bağımlılık Zinciri:**
  1. `customer` oluşturulmalı.
  2. `sale` (müşteriye ait) oluşturulmalı.
  3. `financial_transaction` (borç/tahsilat) oluşturulmalı.
- **Kod Kanıtı:** [`sync-v4.materializer.ts:L183-L188`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L183-L188):
  ```ts
  if (customerId) {
    const customer = await client.query(
      "SELECT id FROM customers WHERE id = $1 AND company_id = $2 AND is_deleted = false",
      [customerId, companyId],
    );
    if (!customer.rowCount) throw new Error("invalid_customer");
  }
  ```
  Eğer çevrimdışı oluşturulan bir müşteri ve ona yapılan satış sunucuya gönderilirken mutasyon sırası karışır veya müşteri mutasyonu geride kalırsa, sunucu satışı **`invalid_customer`** hatasıyla REDDEDER. Bu nedenle mutasyonlar kesinlikle istemcideki oluşturulma sırasına göre gönderilmelidir.

### 4.7. Kalıcı Reddetme (4xx) ve Kuyruk Tıkanması (Head-of-Line Blocking)
- Eğer bir mutasyon geçersiz veri nedeniyle sunucu tarafından `rejected` dizisine atılırsa (ör. `invalid_sale`, `sale_total_mismatch`), istemci bunu tekrar tekrar göndermemelidir.
- Aksi halde istemci senkronizasyon kuyruğu kalıcı olarak tıkanır (Poison Pill). Mutasyon `FAILED` olarak işaretlenmeli ve sıradaki bağımsız mutasyonların akışına izin verilmelidir.

---

## 5. TEST PLANI VE EKSİK SENARYOLAR

Mevcut test süitinde (`test/core_next/`) senkronizasyon istemcisine ait hiçbir test bulunmamaktadır (çünkü `core_next` senkronizasyon istemcisi henüz yazılmamıştır). İstemci geliştirme aşamasına geçilmeden önce aşağıdaki 10 asgari senaryonun test spesifikasyonu zorunludur:

| # | Test Senaryosu | Beklenen Doğrulama Kriteri |
| :-: | :--- | :--- |
| **1** | Aynı mutation'ın tekrar gönderilmesi | Sunucu tarafında `prior.rowCount` ile yakalanması; istemciye önceki `revision`ın dönmesi; stok veya carinin iki kez düşmemesi. |
| **2** | Sunucu commit sonrası yanıtın kopması (Mock network drop) | İstemcinin aynı `mutation_id` ile retry yapması ve sunucunun idempotent onay dönmesi. |
| **3** | İstemci yeniden başlatıldığında kuyrukta bekleyen mutation | Uygulama açılışında `sync_events` tablosundaki `PENDING` kayıtların doğru sıralamayla (`client_timestamp ASC`) kuyruğa alınması. |
| **4** | Ağ hatası ve kontrollü backoff | 500/503/timeout durumlarında istemcinin üstel geri çekilme (exponential backoff with jitter) uygulaması, sunucuyu boğmaması. |
| **5** | Kalıcı 4xx hata ile tekrar denenebilir hata ayrımı | 400 (`invalid_mutation`) veya 426 (`sync_protocol_upgrade_required`) geldiğinde mutasyonun `FAILED` işaretlenip kuyruğun kilitlenmemesi. |
| **6** | Eksik/bozuk response yönetimi | Sunucudan gelen HTML hata sayfası veya eksik JSON durumunda istemcinin durumu `SYNCED` yapmaması, hatayı loglaması. |
| **7** | Eski ve desteklenmeyen protokol sürümü (HTTP 426) | `x-sync-protocol-version` eksik veya eski olduğunda istemcinin kullanıcıya güncelleme uyarısı verip senkronizasyonu durdurması. |
| **8** | Satış ile ona bağlı cari/ödeme sıralaması | `customer` -> `sale` -> `financial_transaction` sırasının batch içinde korunması; `invalid_customer` hatasının önlenmesi. |
| **9** | İki cihazdan eşzamanlı güncelleme (Conflict flow) | Farklı cihaz tarafından güncellenen varlık için sunucudan gelen `conflicts` yanıtının yerel olarak tespit edilip ele alınması. |
| **10** | Silme ve iptal senaryoları | Satış silme girişiminde sunucunun `immutable_sale` fırlatması; iptal ve iadelerin `refund` / `cancellation` mutasyonuyla yapılması. |

---

## 6. RİSK MATRİSİ VE SOMUT KABUL KRİTERLERİ

| Risk Tanımı | Seviye | Etki | Somut Kabul Kriteri |
| :--- | :---: | :--- | :--- |
| **Entity Type Casing Hatası** | 🔴 KRİTİK | Sunucu `'SALE'` mutasyonunu doğrudan HTTP 400 ile reddeder. | `core_next` çıkışında entity type küçük harfe (`sale`) dönüştürülmelidir. |
| **Eksik `items` Dizisi** | 🔴 KRİTİK | Sunucu `payload.items` boş olunca satışı reddeder (`invalid_sale`). | `sync_events` payload'ına satılan kalemler (`sale_items`) tam döküm olarak eklenmelidir. |
| **Kuruş / Lira Format Uyuşmazlığı** | 🔴 KRİTİK | `total_cents` ile `total_amount` uyuşmazlığı sunucuda `sale_total_mismatch` üretir. | Payload dönüştürücü kuruş değerleri (`MoneyCents`) Lira ondalık formatına (`total_amount = totalCents / 100.0`) çevirmelidir. |
| **Veresiye Cari Borç Kaybı** | 🔴 KRİTİK | Veresiye satışta müşteri borcu sunucuya aktarılmaz. | Borç içeren satışlarda `sale` mutasyonunun hemen ardından bir `financial_transaction` mutasyonu kuyruğa eklenmelidir. |
| **`base_revision` Eksikliği** | 🔴 KRİTİK | Sunucu `base_revision` olmadan mutasyonu kabul etmez. | `sync_events` tablosuna `base_revision INTEGER NOT NULL DEFAULT 0` sütunu eklenmelidir. |
| **Tekrar Deneme Sayacı Eksikliği** | 🟡 ORTA | Hatalı mutasyon sonsuz döngüde sunucuyu meşgul eder. | `sync_events` tablosuna `attempts INTEGER DEFAULT 0` ve `last_error TEXT` alanları eklenmelidir. |

---

## 7. SON KARAR VE SONUÇ

### Karar: **İSTEMCİ GELİŞTİRMESİNE DOĞRUDAN HAZIR DEĞİL (HAZIR DEĞİL)**

### Karar Gerekçesi:
1. `core_next` içindeki mevcut `sync_events` kuyruk tasarımı ve `checkout_use_case.dart` tarafından üretilen payload, üretim sunucusunun **Sync V4 / Protocol 6** sözleşmesi ile **%100 uyumsuzdur**.
2. Mevcut haliyle bir senkronizasyon istemcisi yazılıp istek atılırsa, sunucu tüm mutasyonları derhal **HTTP 400 `invalid_mutation`** veya **`invalid_sale`** hatasıyla reddedecektir.
3. Ayrıca veresiye satışlarda müşteri borcunu sunucuya aktaracak `financial_transaction` mutasyonu kuyruğa yazılmadığı için **ciddi finansal veri tutarsızlığı** riski mevcuttur.

### İstemci Geliştirmesine Başlamadan Önce Yapılması Gereken Ön Koşullar (Stage 8.2B Kapsamı):
1. **Şema Güncellemesi:** `core_next` veritabanındaki `sync_events` tablosuna `base_revision`, `attempts`, `last_error` sütunlarının eklenmesi.
2. **Payload & Outbox Mimarisi:** `checkout_use_case` ve diğer yazma işlemlerinde sunucunun beklediği şemaya (`items` dizisi, Lira ondalık değerleri, küçük harf `sale`, ödeme yöntemi `payment_method`) uygun dönüşüm yapan bir **Sync Mutation Adapter / Outbox Servisi** tasarlanması.
3. **Finansal Mutasyon Çifti:** Veresiye satışlarda `sale` mutasyonuna ek olarak `financial_transaction` mutasyonunun atomik olarak outbox'a eklenmesi.
4. Bu düzeltmeler yapıldıktan sonra Stage 8.3 aşamasında senkronizasyon istemcisi implementasyonuna geçilebilir.
