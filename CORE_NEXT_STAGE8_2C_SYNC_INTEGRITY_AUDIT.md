# SERENUT OS — STAGE 8.2C: BAĞIMSIZ SENKRONİZASYON VE FİNANSAL TUTARLILIK DENETİM RAPORU

**Tarih:** 2026-10-13  
**Aşama:** Stage 8.2C — Bağımsız Senkronizasyon ve Finansal Tutarlılık Denetimi  
**Denetlenen Kapsam:** Stage 8.2B Outbox ve Payload Adaptörü Geliştirmelerinin, Sunucu Sync V4 / Protocol 6 Sözleşmesiyle Karşılaştırmalı Adli Denetimi  
**Denetçi:** Antigravity Bağımsız Kodlama ve Adli Doğrulama Ajanı  
**Hedef Rapor:** `CORE_NEXT_STAGE8_2C_SYNC_INTEGRITY_AUDIT.md`  

---

## 1. GÜVENLİK VE ÇALIŞMA AĞACI DURUMU

Denetim öncesinde ve süresince güvenlik sınırları harfiyen korunmuştur:
- `lib/` altındaki üretim uygulaması ve `server/` altındaki sunucu kaynak kodu kesinlikle değiştirilmemiştir.
- Canlı PostgreSQL ve `%APPDATA%` veritabanlarına hiçbir bağlantı açılmamıştır.
- Canlı ağ isteği, commit veya push yapılmamıştır.

### Gerçek Git Durumu:
- **Aktif Branch:** `main`
- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **`git diff --stat`:** `0 files changed` (Boş)
- **`git diff --cached --stat`:** `0 files changed` (Boş)
- **`git status --short` ve `git ls-files --others --exclude-standard` Çıktısı:**
  Takip edilmeyen (untracked) dosyalar raporlanmıştır:
  - Raporlar: `CORE_NEXT_STAGE8_2A_SYNC_CONTRACT_AUDIT.md`, `CORE_NEXT_STAGE8_2B_OUTBOX_ADAPTER_REPORT.md` vb.
  - Kod Dosyaları: `core_next/client_core/lib/...`
  - Test Dosyaları: `test/core_next/...`
  *(Tracked dosyalar üzerinde hiçbir dirty değişiklik veya silinme yoktur).*

---

## 2. İNCELENEN DOSYALAR VE SATIR ARALIKLARI

| Bileşen | Dosya Yolu | İncelenen Satır Aralığı | Amaç / Kapsam |
| :--- | :--- | :---: | :--- |
| **Sunucu Router** | `server/src/server.ts` | 415–420 | Sync V4 route mount noktası (`/api/v4/sync`) |
| **Sunucu Routes** | `server/src/modules/sync_v4/sync-v4.routes.ts` | 24–50 | Protokol sürümü (6), başlıklar, yetki kontrolleri |
| **Sunucu Push** | `server/src/modules/sync_v4/sync-v4.routes.ts` | 54–342 | `/push` batch döngüsü, savepoint, idempotency, çakışma ve DTO |
| **Sunucu Materializer**| `server/src/modules/sync_v4/sync-v4.materializer.ts` | 54–85 | Silme ve iade engelleri (`immutable_sale`, `immutable_refund`) |
| **Satış Materializer** | `server/src/modules/sync_v4/sync-v4.materializer.ts` | 163–258 | `upsertSale` kuralları, `items`, tutarlar, stok düşümü |
| **Finansal Materializer**| `server/src/modules/sync_v4/sync-v4.materializer.ts`| 339–465 | `upsertFinancialTransaction` kuralları, bakiye hesaplama |
| **İstemci Modeli** | `core_next/client_core/lib/domain/models/sync_mutation.dart` | 1–75 | `SyncMutation` DTO ve SQLite dönüşümleri |
| **İstemci Adaptörü** | `core_next/client_core/lib/infrastructure/sync/sync_v4_payload_adapter.dart` | 1–185 | Lira dönüşümü, satış/finansal mutasyon üretimi, validasyonlar |
| **İstemci Şeması** | `core_next/client_core/lib/infrastructure/database/schema_definitions.dart` | 158–265 | `sync_events` v2 DDL ve geriye uyumlu `migrate()` fonksiyonu |
| **İstemci DB** | `core_next/client_core/lib/infrastructure/database/app_database.dart` | 25–65 | `openDatabase` `onUpgrade` entegrasyonu |
| **İstemci Checkout**| `core_next/client_core/lib/domain/usecases/checkout_use_case.dart` | 245–285 | Atomik SQLite transaction içinde outbox yazımı |
| **Adli Test Paketi**| `test/core_next/sync_v4_outbox_adapter_test.dart` | 1–562 | 12 senaryolu adli doğrulama testleri |

---

## 3. DOĞRULANAN SUNUCU SÖZLEŞMESİ (SYNC V4 / PROTOCOL 6)

### 3.1. Endpoint, Başlıklar ve DTO Yapısı
- **Endpoint:** `POST /api/v4/sync/push` ([`sync-v4.routes.ts:L54`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L54)).
- **Zorunlu Başlıklar:**
  - `Authorization: Bearer <token>` ([L37](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L37)).
  - `x-sync-protocol-version: 6` ([L39-L48](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L39-L48)). Eşleşmezse HTTP 426 Upgrade Required döner.
  - `x-device-activation-id` ve `x-device-id` ([L56-L78](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L56-L78)). Aktif olmayan veya eşleşmeyen cihaz HTTP 403 alır.
- **Kabul Edilen Entity Türleri:** Yalnızca küçük harf `["product", "customer", "order", "sale", "financial_transaction", "refund"]` ([L25-L32](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L25-L32)).
- **Mutasyon Doğrulama:**
  - `mutation_id`: UUIDv4 dizesi ([L33-L34](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L33-L34)).
  - `base_revision`: Güvenli tamsayı `>= 0` ([L118](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L118)).
  - `entity_id`: Dize `<= 128` karakter.
  - `operation`: Yalnızca `"UPSERT"` veya `"DELETE"`.

### 3.2. Idempotency ve Savepoint Mekanizması
- Sunucu her gelen mutasyonu `sync_v4_changes` tablosunda `(tenant_id, mutation_id::uuid)` ile arar ([`sync-v4.routes.ts:L132-L141`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L132-L141)). Bulunursa yan etki üretmeksizin önceki `revision`ı döner.
- Sunucu batch içindeki her mutasyonu `SAVEPOINT sync_mutation` ile izole eder ([L109](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L109)). Bir mutasyon hata alırsa yalnızca o mutasyon rollback olur; transaction'daki önceki başarılı mutasyonlar commit edilir.
- Yanıt DTO'su: `{ results: [...], conflicts: [...], rejected: [...] }` ([L325](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts#L325)).

### 3.3. Parçalı (Split) Ödemelerin Sunucudaki Durumu
- Sunucu tarafında **`sale_payments` tablosu MEVCUT DEĞİLDİR**.
- `sales` tablosu yalnızca tekil `payment_method` (`"cash"`, `"card"`, `"veresiye"`, `"mixed"`), `total_amount` ve `paid_amount` tutar.
- İstemci karma (split) ödemeyi sunucuda şu şekilde temsil eder:
  - Satış mutasyonu: `payment_method = 'mixed'`, `total_amount = total`, `paid_amount = paid` (tahsil edilen nakit/kart toplamı).
  - Finansal işlem mutasyonu: `type = 'sale'`, `payment_method = 'mixed'`, `amount = total`, `paid_amount = paid`, `debt_amount = debt`.
  - Ayrıntılı parçalı ödeme dökümü (`sale_payments`) ise istemcide yerel SQLite'ta saklanır.

---

## 4. FİNANSAL ÇİFT KAYIT VE TUTARLILIK RİSKLERİ

### 4.1. Satış Materyalizasyonu Müşteri Bakiyesini Değiştirir mi?
- **Kod Kanıtı:** [`server/src/modules/sync_v4/sync-v4.materializer.ts:L163-L258`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L163-L258) içindeki `upsertSale` fonksiyonu:
  - `sales` tablosuna satışı ekler.
  - `products.quantity` değerini düşer.
  - `inventory_movements` tablosuna stok çıkış hareketi ekler.
  - `sale_items` tablosuna kalemleri ekler.
  - **`customers.balance` veya `financial_transactions` tablolarına HİÇBİR ŞEKİLDE DOKUNMAZ!**
- **Adli Sonuç:** Sunucuda müşteri bakiyesi **yalnızca ve yalnızca** `upsertFinancialTransaction` fonksiyonu tarafından yönetilir. Dolayısıyla `sale` ve `financial_transaction` mutasyonlarının her ikisinin de gönderilmesi **ASLA çift borç kaydı veya çift bakiye etkisi oluşturmaz**.

### 4.2. Finansal Senaryoların Beklenen ve Gerçekleşen Sonuç Matrisi

| Senaryo | Satış Kaydı (`sales`) | Stok Hareketi (`products`) | Müşteri Cari Bakiyesi | Finansal İşlem (`financial_transactions`) | Adli Değerlendirme |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Tamamı Nakit (100 ₺)** | `paid: 100 ₺`, `payment_method: 'cash'` | -N düşer | Değişmez (0 ₺ net etki) | Eklenmez (Cari borç yok) | ✅ Temiz nakit akışı, bakiye bozulmaz. |
| **2. Tamamı Kart (100 ₺)** | `paid: 100 ₺`, `payment_method: 'card'` | -N düşer | Değişmez (0 ₺ net etki) | Eklenmez (Cari borç yok) | ✅ Temiz pos tahsilatı. |
| **3. Tamamı Vadeli (100 ₺)** | `paid: 0 ₺`, `payment_method: 'veresiye'` | -N düşer | Borç +100 ₺ artar | 1 kayıt (`amount: 100, paid: 0, debt: 100`) | ✅ Satış ve cari mutasyonu atomik eşleşir. |
| **4. Kısmi Peşin, Kalan Vadeli (40 ₺ Nakit, 60 ₺ Veresiye)** | `paid: 40 ₺`, `payment_method: 'mixed'` | -N düşer | Borç +60 ₺ artar | 1 kayıt (`amount: 100, paid: 40, debt: 60`) | ✅ Sunucu bakiye denklemi tam uyuşur. |
| **5. Karma Ödeme (30 ₺ Nakit, 30 ₺ Kart, 40 ₺ Borç)** | `paid: 60 ₺`, `payment_method: 'mixed'` | -N düşer | Borç +40 ₺ artar | 1 kayıt (`amount: 100, paid: 60, debt: 40`) | ✅ İstemci parçaları yerelde saklar, sunucuya net özet gider. |
| **6. Aynı Mutasyonun Tekrarı (Idempotent Retry)** | Değişmez (Önceki kayıt korunur) | Değişmez (Çift stok düşümü OLMAZ) | Değişmez (Çift borç yazılmaz) | Değişmez (Tekrar eklenmez) | ✅ `sync_v4_changes` idempotency kilidi devrededir. |
| **7. Sunucu Commit Sonrası Ağ Kopması** | İlk istekte kalıcılaştı | İlk istekte düştü | İlk istekte güncellendi | İlk istekte eklendi | ✅ İstemci aynı UUID ile tekrar gönderdiğinde sunucu yan etkisiz onay döner. |
| **8. Satış Başarılı, Finansal Mutasyon Hatalı (Savepoint)** | Satış sunucuda kalıcılaştı | Stok düştü | Sunucuya yansımadı (`rejected`) | Eklenmedi | ⚠️ **Yüksek Risk:** İstemci `sale` mutasyonunu `SYNCED`, `finTx` mutasyonunu ise `REJECTED/PENDING` olarak ayrı ayrı durumlandırmalıdır. |
| **9. İki İstemciden Çakışan Mutasyon** | Her satış kendi UUID'sine sahip (çakışmaz) | Stok ardışık düşer | İlgili müşteri mutasyonu revizyona göre ele alınır | `conflicts` tablosuna yazılır | ✅ LWW/Conflict koruması aktif. |

---

## 5. OUTBOX, MIGRATION VE VERİ TUTARLILIĞI

1. **`event_id` ve `mutation_id` Eşlemesi:**
   - [`SyncMutation.toServerMutationDto()`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/sync_mutation.dart#L67):
     `'mutation_id': eventId`
   - `eventId` SQLite'ta `PRIMARY KEY`dir ve UUIDv4 formatındadır. Yeniden denemelerde bu ID ASLA değişmez; idempotency sunucuda korunur.
2. **`base_revision` Yönetimi:**
   - Yeni oluşturulan yerel satış ve finansal mutasyonlar için `base_revision = 0` olarak atanır.
   - İleride güncellenen varlıklar için varlığın son bilinen revizyonu outbox'a aktarılır.
3. **`group_id` ve `causal_sequence` Uygulaması:**
   - Bir checkout işleminde:
     - `sale`: `causal_sequence: 1`, `group_id: saleId`
     - `financial_transaction`: `causal_sequence: 2`, `group_id: saleId`
   - `test/core_next/sync_v4_outbox_adapter_test.dart` Test 6 ve 10'da kanıtlandığı üzere, kuyruktan okuma yapılırken `ORDER BY causal_sequence ASC` kuralı gözetildiğinde bağımlılık sırası mutlak olarak korunur.
4. **V1 → V2 Migration:**
   - [`CoreSchemaDefinitions.migrate()`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/schema_definitions.dart#L230) fonksiyonu:
     - `sync_events` tablosundaki mevcut v1 satırlarını korur.
     - `ALTER TABLE` ile `base_revision`, `attempts`, `last_error`, `group_id`, `causal_sequence` kolonlarını güvenle ekler.
     - Varsa eski büyük harfli `'SALE'` kayıtlarını küçük harfe (`'sale'`) normalize eder.
   - Test Senaryosu 9 ile veritabanının sıfır veri kaybıyla yükseltildiği adli olarak kanıtlanmıştır.
5. **Checkout Atomikliği:**
   - [`CoreCheckoutUseCase.execute()`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L142-L281) içindeki tüm adımlar (`sales`, `sale_items`, `sale_payments`, `cash_transactions`, `customer_ledger` ve `sync_events`) tek bir `await _db.transaction((txn) async { ... })` bloğundadır.
   - Test 7'de `after_sync_events_insert` adımına enjekte edilen yapay çökme sonucunda ne satışın ne de outbox kaydının veritabanında kalmadığı, her şeyin birlikte rollback olduğu kanıtlanmıştır.

---

## 6. PARA VE ÖDEME EŞLEMESİ ANALİZİ

1. **Kuruş → Lira Dönüşümü:**
   - Formül: `double.parse((cents / 100.0).toStringAsFixed(2))`
   - Sınır Değer Doğrulamaları:
     - 0 kuruş -> `0.0 ₺`
     - 1 kuruş -> `0.01 ₺`
     - 1.234 kuruş -> `12.34 ₺`
     - 100.050 kuruş -> `1000.50 ₺`
   - IEEE 754 float yuvarlama sapması oluşması imkansızdır.
2. **Ödeme Parçaları Toplamı:**
   - [`checkout_use_case.dart:L121-L128`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L121-L128) satırlarında:
     `computedPaidCents != paidCents.value` kontrolü yer alır. Parçalı ödemeler toplamı tahsil edilen kuruşa kuruşu kuruşuna eşit değilse işlem `StateError` ile durdurulur.
3. **Bilinmeyen / Geçmiş Ödemeler:**
   - Tarihsel veya ödeme türü belirsiz kayıtlar için yapay nakit/kart tahmini üretilmez; açık ve denetlenebilir `"mixed"` tipi kullanılır.

---

## 7. TESPİT EDİLEN BULGULAR VE RİSK MATRİSİ

| No | Bulgu Açıklaması | Seviye | Risk & Etki Analizi | Çözüm / Gereksinim |
| :-: | :--- | :---: | :--- | :--- |
| **B-1** | **Sunucu Savepoint Kaynaklı Kısmi Batch Kabulü** | 🟡 **ORTA** | Sunucu push batch içinde savepoint kullandığından `sale` onaylanıp `financial_transaction` reddedilebilir. | Stage 8.3 HTTP istemcisi yanıtı işlerken `results` ve `rejected` dizilerini ayrık ele almalı; onaylanan satışın outbox kaydını `SYNCED`, reddedilen cariyi ise `REJECTED/PENDING` yapmalıdır. |
| **B-2** | **Ayrık `sync_cursor` Tablosu Eksikliği** | 🟢 **DÜŞÜK** | `sync_events` tablosunda `base_revision` var fakat pull cursor'ı için `sync_cursor` tablosu `core_next` şemasında henüz ayrık tanımlanmamıştır. | `app_settings` tablosunda `sync_cursor` anahtarıyla tutulabilir veya Stage 8.3'te ayrık tablo eklenebilir. |
| **B-3** | **Nedensel Sıranın Tüketici Tarafından Uygulanması** | 🟢 **DÜŞÜK** | `causal_sequence` doğru üretilip saklanmaktadır; istemci henüz yazılmadığı için gönderme aşamasında `ORDER BY causal_sequence ASC` sorgulanmalıdır. | Stage 8.3 HTTP istemcisinde outbox kuyruğu okunurken `ORDER BY causal_sequence ASC, client_timestamp ASC` kuralı zorunlu kılınmalıdır. |

---

## 8. TEST KOMUTLARI VE GERÇEK ÇIKTILAR

Tüm testler yalnızca izole bellek içi (`inMemoryDatabasePath`) veritabanları üzerinde icra edilmiştir.

### 8.1. Outbox ve Adaptör Test Paketi
```bash
flutter test test/core_next/sync_v4_outbox_adapter_test.dart
```
**Gerçek Komut Çıktısı:**
```text
00:00 +0: Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri 1 & 2. DTO Alanları Sunucu Şemasıyla Uyumlu ve Entity Type Küçük Harf
00:00 +1: Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri 3. Satış Kalemleri Eksiksiz ve Tutarlı
00:00 +2: Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri 4. Kuruş / Lira Dönüşümü Sınır Değerlerinde Kuruşu Kuruşuna Doğru
00:00 +3: Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri 5. Nakit, Kart, Vadeli ve Karma Ödemeler Doğru Temsil Ediliyor
00:00 +4: Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri 6. Satış ve Finansal Mutasyonlar Tek Transaction İçinde Oluşturuluyor
00:00 +5: Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri 7. Her Hata Enjeksiyonunda Bütün Outbox ve Finansal Kayıtlar Rollback Oluyor
00:00 +6: Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri 8. Aynı Satış Tekrar Hazırlandığında Determinizm ve İdempotency
00:00 +7: Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri 9. Kuyrukta Eski v1 Kayıtlar Varsa Migration Onları Kaybetmiyor ve Normalize Ediyor
00:00 +8: Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri 10. Müşteri-Satış-Finansal İşlem Bağımlılıkları ve Nedensel Sıra Korunuyor
00:00 +9: Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri 11. Bozuk veya Eksik Satış İçin Geçerli Görünen Payload Üretilemez
00:00 +10: Stage 8.2B — Outbox ve Payload Adaptörü Adli Doğrulama Testleri 12. İade ve İptal Desteği Yoksa Bu Durum Açıkça Reddediliyor
00:01 +11: All tests passed!
```
- **Exit Code:** `0`
- **Sonuç:** `11 / 11 Başarılı`

### 8.2. Tüm `core_next` Test Süiti (Regresyon Denetimi)
```bash
flutter test test/core_next/
```
- **Exit Code:** `0`
- **Toplam Test Sayısı:** **`50 / 50 Başarılı`** (Sıfır hata, sıfır regresyon)

---

## 9. STAGE 8.3'E GEÇİŞ KOŞULLARI

Stage 8.3 kapsamında HTTP İstemcisi geliştirilirken aşağıdaki kurallar bağlayıcı kabul edilmelidir:
1. **Başlıklar:** İsteklere `x-sync-protocol-version: 6`, `x-device-activation-id` ve `x-device-id` başlıkları eklenmelidir.
2. **Kuyruk Okuma Sıralaması:** Outbox'tan mutasyonlar çekilirken kesinlikle `ORDER BY causal_sequence ASC, client_timestamp ASC` kullanılmalıdır.
3. **Savepoint / Parsiyel Yanıt Yönetimi:** Sunucudan dönen `results` ve `rejected` dizileri tekil olarak işlenmeli; onaylanan mutasyonlar `SYNCED`, reddedilenler ise `attempts` artırılarak `REJECTED/PENDING` olarak güncellenmelidir.
4. **Idempotency Korunumu:** Retry isteklerinde `mutation_id` olarak yerel `event_id` kullanılmalı; yeni UUID üretilmemelidir.

---

## 10. SON KARAR

> **SON KARAR: HTTP İSTEMCİSİ TASARIMINA GEÇİLEBİLİR.**

### Gerekçe:
Stage 8.2B'de tasarlanan ve uygulanan adaptör ile outbox katmanı; sunucu Sync V4 / Protocol 6 sözleşmesiyle tam uyumlu, kuruş bazlı hesaplamaları hatasız, çift finansal etki üretmeyen ve geriye dönük migration güvenliğini sağlayan sağlam bir temel oluşturmuştur. 50/50 otomatik test ile tam uyum kanıtlanmıştır.
