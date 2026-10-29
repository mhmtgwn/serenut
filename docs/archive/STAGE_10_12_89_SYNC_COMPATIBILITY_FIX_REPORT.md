# SERENUT OS — STAGE 10.12.89: SYNC V4 UYUMSUZLUKLARININ GÜVENLİ DÜZELTİLMESİ RAPORU

**Tarih:** 2026-10-22  
**Aşama:** Stage 10.12.89  
**Kapsam:** Sync V4 / Protocol 6 İstemci Eşleme ve Tip Uyumsuzluklarının İzolasyonlu Güvenli Düzeltilmesi  
**Son Karar:** `FIXES_VERIFIED` (Senkronizasyon adaptör düzeltmeleri hedefli testlerle %100 doğrulandı; canlı senkronizasyon satış motoru cutover'ına kadar korumalı kapalı tutulmalıdır)

---

## 1. Değiştirilen Dosyalar ve Değişiklik Gerekçeleri

Stage 10.12.88 VPS uyumluluk incelemesinde tespit edilen 4 kritik uyumsuzluk, mimari bozulmadan ve dar kapsamlı olarak giderilmiştir:

| Dosya | Değişiklik Türü | Gerekçe / Yapılan Düzeltme |
|---|---|---|
| `core_next/client_core/lib/infrastructure/sync/sync_v4_payload_adapter.dart` | Güncelleme / Genişletme | • `buildProductMutation`: Sunucunun beklediği `price` (TL), `purchase_price` (TL), `quantity` alanlarını `toLira` (cents/100) dönüşümüyle üretti; yerel SQLite için `price_cents`, `cost_price_cents`, `stock_quantity` alanlarını korudu.<br>• `buildCustomerMutation`: Sunucunun `address` ve `notes` alanlarını eşledi; `credit_limit` (TL) ve `credit_limit_cents` dönüşümünü sağladı.<br>• `buildFinancialMutation`: Sunucu Protocol 6 sözleşmesine (`sale`, `payment`, `collection`, `manual_debt`, `cancellation`, `refund`) tam uyum sağladı. `debt` türünü satış referansı yoksa `manual_debt`, varsa `sale` olarak normalize etti. Negatif tutarlara fail-closed `ArgumentError` getirdi. |
| `core_next/client_core/lib/infrastructure/repositories/core_next_product_repository.dart` | Düzeltme | `create`, `update` ve `deleteProduct` metodlarında doğrudan `SyncV4PayloadAdapter.buildProductMutation` çağrısı entegre edildi. Ürün oluşturulurken veya güncellenirken outbox kuyruğuna (`sync_events`) hem sunucu Protocol 6 hem de yerel SQLite sözleşmelerini içeren zenginleştirilmiş payload yazıldı. |
| `core_next/client_core/lib/infrastructure/repositories/core_next_customer_repository.dart` | Düzeltme | `create`, `update` ve `delete` metodlarında `SyncV4PayloadAdapter.buildCustomerMutation` entegre edildi. `address` ve `notes` alanları outbox kuyruğuna eksiksiz yazıldı. |
| `core_next/client_core/lib/infrastructure/repositories/core_next_financial_transaction_repository.dart` | Düzeltme & Koruma | • `_rowToEntity`: `DEBIT` / `BORC` / `DEBT` kayıtları sunucunun beklediği `manual_debt` türüne eşlendi.<br>• `getByType`: Hem `'DEBT'` hem de `'MANUAL_DEBT'` sorgularını destekleyecek şekilde genişletildi.<br>• `create`: Negatif tutarlı taksit veya düzeltme satırlarının sunucu outbox'ına (`sync_events`) gitmesi engellendi (`amount > 0 && paidAmount >= 0 && debtAmount >= 0`). Bu tür negatif kayıtlar yerel SQLite `ledger_entries` tablosunda bozulmadan korunurken, sunucu 400 rejection riski sıfırlandı. |
| `test/core_next/stage10_12_89_sync_compatibility_fix_test.dart` | Yeni Hedefli Test Paketi | Yapılan tüm alan eşlemeleri, kuruş/TL dönüşümleri, null/0 ayrımı, debt normalizasyonu, negatif satır koruması ve repository entegrasyonu için 11 bağımsız test oluşturuldu. |

---

## 2. Önce/Sonra Payload Örnekleri ve Para Birimi Dönüşümü

### A. Ürün Kaydı (Product Mutation)

**Önce (Stage 10.12.88 Durumu):**
Sunucu `price`, `purchase_price` ve `quantity` alanlarını beklerken istemci yalnızca `price_cents`, `cost_price_cents`, `stock_quantity` gönderiyordu. Sunucu materializer'ı (`sync-v4.materializer.ts`) `Number(payload.price)` okuduğu için fiyat `0.00 TL`, stok ise `0` oluyordu:
```json
{
  "id": "p-101",
  "name": "Ezine Peyniri",
  "price_cents": 25000,
  "cost_price_cents": 17550,
  "stock_quantity": 42
}
```

**Sonra (Stage 10.12.89 Düzeltmesi):**
Kuruş/TL dönüşümü `cents / 100.0` formülüyle güvenli yapıldı. Sunucu Protocol 6 ve yerel SQLite alanları birlikte gönderilir:
```json
{
  "id": "p-101",
  "name": "Ezine Peyniri",
  "price": 250.0,
  "purchase_price": 175.5,
  "quantity": 42,
  "price_cents": 25000,
  "cost_price_cents": 17550,
  "stock_quantity": 42,
  "min_stock": 10,
  "unit": "adet",
  "is_active": 1,
  "is_deleted": 0
}
```

*Kısmi Güncelleme ve Null/Sıfır Ayrımı:*
- Fiyat `0` ise: `price: 0.0`, `price_cents: 0` (bilerek ücretsiz ürün, sıfırlanma hatası değil).
- Maliyet `null` ise: `purchase_price` ve `cost_price_cents` payload'da `null` olarak korunur, `0` yapılmaz.
- Kısmi güncellemede güncellenmeyen alanlar silinmez veya ezilmez.

---

### B. Finansal İşlem (Financial Transaction Mutation)

**Önce (Stage 10.12.88 Durumu):**
İstemci elle borç hareketini `type: "debt"` olarak gönderiyordu. Sunucu `allowedTypes = ['sale', 'payment', 'collection', 'manual_debt', 'cancellation', 'refund']` whitelist'ine sahip olduğu için HTTP 400 `invalid_financial_transaction` hatası dönüyordu:
```json
{
  "id": "ft-201",
  "type": "debt",
  "customer_id": "cust-99",
  "amount": 56.0,
  "debt_amount": 56.0
}
```

**Sonra (Stage 10.12.89 Düzeltmesi):**
Satış referansı olmayan açık borçlar `manual_debt` olarak eşlenir. Sunucu denklemi (`amount = debt_amount = 56.0`, `paid_amount = 0.0`) tam sağlanır:
```json
{
  "id": "ft-201",
  "type": "manual_debt",
  "customer_id": "cust-99",
  "amount": 56.0,
  "amount_minor": 5600,
  "paid_amount": 0.0,
  "paid_amount_minor": 0,
  "debt_amount": 56.0,
  "debt_amount_minor": 5600,
  "reference_id": null,
  "logical_clock": 0
}
```
*Not:* Eğer işlem bir satışa referans veriyorsa (`reference_id != null`), tip `sale` olarak korunur.

---

### C. Müşteri Kaydı (Customer Mutation)

**Önce:**
İstemci sadece `notes` alanını dolduruyor, sunucunun `address` sütununa yazamadığı için sunucuda müşteri adresi boş kalıyordu.

**Sonra:**
`address` alanı hem `address` hem de `notes` anahtarlarına doldurulur; `credit_limit` (TL) ve `credit_limit_cents` (kuruş) dual-field olarak üretilir:
```json
{
  "id": "c-301",
  "name": "Ahmet Yılmaz",
  "phone": "05321112233",
  "email": "ahmet@example.com",
  "address": "Atatürk Cad. No: 12",
  "notes": "Atatürk Cad. No: 12",
  "credit_limit": 5000.0,
  "credit_limit_cents": 500000,
  "is_active": 1,
  "is_deleted": 0
}
```

---

## 3. Taksit ve Senet Koruması (Negatif Taksit / Düzeltme Satırı)

Nutopia canlı veritabanında (`serenut_pos.db`) tespit edilen `-4465.32 TL` tutarlı negatif taksit satırı (`inst-ab6352d3-eeee-4f64-a2d0-923554147896`) ve benzeri muhasebe düzeltme satırları özel koruma altına alınmıştır:

1. **Sunucu Sözleşme Sınırı:** Sync V4 / Protocol 6 sunucusu `amount > 0` şartını zorunlu tutar (`server/src/modules/sync_v4/sync-v4.materializer.ts:600`). Negatif bir hareket sunucuya iletilirse tüm Sync V4 batch'i reddedilir (HTTP 400).
2. **Fail-Closed Adaptör Koruması:** `SyncV4PayloadAdapter.buildFinancialMutation` negatif veya sıfır tutarlı finansal işlem verildiğinde `ArgumentError` fırlatır; pozitif borca veya tahsilata dönüştürmez.
3. **Outbox Kuyruğu Filtresi:** `CoreNextFinancialTransactionRepository.create` metodunda:
   - Negatif/sıfır kayıt yerel SQLite `ledger_entries` tablosuna aynen yazılır ve saklanır (veri kaybı sıfır).
   - Ancak sunucu `sync_events` outbox kuyruğuna eklenmez.
4. **Yerel Koruma Kanıtı:** Yerel veritabanında bulunan taksit/senet planı silinmez, bakiyesi değiştirilmez; sadece sunucunun desteklemediği formattaki satır Sync V4 kanalından yalıtılır.

---

## 4. Çift Veritabanı ve Satış Otoritesi Değerlendirmesi

| Bileşen | Veritabanı | Durum |
|---|---|---|
| `SqliteSaleRepository` | `serenut_pos.db` (Legacy) | Canlı satışlar bu veritabanına yazılmaktadır. |
| `CoreNextProductRepository` | `serenut_core_v2.db` (Core Next) | Stok ve ürün katalog yönetimi. |
| `CoreNextFinancialTransactionRepository` | `serenut_core_v2.db` (Core Next) | Cari ve defter hareketleri. |
| Satış Motoru Bayrağı (`coreNextSalesEngineEnabledProvider`) | `false` | **KAPALI TUTULMAKTADIR.** |

### Çift Veritabanı Split-Brain Riski:
Eğer Sync V4 canlıda hemen etkinleştirilirse:
- Satışlar Legacy DB'ye yazılmaya devam ederken, Core Next outbox'ı sunucuya Sync V4 üzerinden gidecektir.
- Bu durum sunucuda satış hareketleri ile cari/stok hareketleri arasında senkron kopukluğu yaratabilir.
- **Karar:** Bu aşamada satış motoru kesinlikle devreye alınmamıştır (`coreNextSalesEngineEnabledProvider = false`). Satış mimarisinin Core Next'e devredilmesi (cutover) ayrı ve kontrollü bir aşamada yapılmalıdır.

---

## 5. Çalıştırılan Hedefli Testler ve Gerçek Sonuçlar

Yalnızca yapılan değişiklikleri doğrulayan `test/core_next/stage10_12_89_sync_compatibility_fix_test.dart` hedefli test paketi çalıştırılmıştır.

**Çalıştırma Komutu:**
```bash
flutter test test/core_next/stage10_12_89_sync_compatibility_fix_test.dart
```

**Test Sonuç Çıktısı:**
```
00:00 +0: STAGE 10.12.89 — Sync V4 Payload Adaptörü ve Alan Eşleme Testleri 1. Ürün Fiyatı, Maliyet ve Stok Alanları Protocol 6 ile Tam Uyumlu
00:00 +1: STAGE 10.12.89 — Sync V4 Payload Adaptörü ve Alan Eşleme Testleri 2. Kısmi Güncelleme, Sıfır Fiyat ve Null Maliyet Ayrımı
00:00 +2: STAGE 10.12.89 — Sync V4 Payload Adaptörü ve Alan Eşleme Testleri 3. Müşteri Adres ve Kredi Limiti Alan Eşleme Doğrulaması
00:00 +3: STAGE 10.12.89 — Sync V4 Payload Adaptörü ve Alan Eşleme Testleri 4. Finansal İşlem: debt -> manual_debt Dönüşümü ve Satış Referansı Koruması
00:00 +4: STAGE 10.12.89 — Sync V4 Payload Adaptörü ve Alan Eşleme Testleri 5. Satış, Tahsilat, İptal ve İade Türlerinin Sözleşmeye Uygunluğu
00:00 +5: STAGE 10.12.89 — Sync V4 Payload Adaptörü ve Alan Eşleme Testleri 6. Negatif Taksit ve Hareket Koruması (Fail-Closed)
00:00 +6: STAGE 10.12.89 — Repository ve Outbox Kuyruğu Entegrasyon Testleri 7. CoreNextProductRepository.create ve update sunucu alanlarını eksiksiz üretir
00:00 +7: STAGE 10.12.89 — Repository ve Outbox Kuyruğu Entegrasyon Testleri 8. CoreNextCustomerRepository.create sunucu address alanını eksiksiz üretir
00:00 +8: STAGE 10.12.89 — Repository ve Outbox Kuyruğu Entegrasyon Testleri 9. CoreNextFinancialTransactionRepository: debt -> manual_debt ve Idempotency
00:00 +9: STAGE 10.12.89 — Repository ve Outbox Kuyruğu Entegrasyon Testleri 10. Negatif Taksit / Düzeltme Satırı sync_events Kuyruğuna Eklenmez (Yerelde Korunur)
00:00 +10: STAGE 10.12.89 — Repository ve Outbox Kuyruğu Entegrasyon Testleri 11. getByType("manual_debt") ve getByType("debt") İstemci Sorgularında Uyumlu
00:00 +11: All tests passed!
```
**Sonuç: 11 test çalıştırıldı, 11 test BAŞARILI (0 hata).**

---

## 6. Canlı Veritabanı ve VPS Koruma Kanıtı

Aşama boyunca hiçbir canlı PostgreSQL, VPS API veya canlı SQLite dosyasına yazılmamıştır.

### Canlı SQLite Dosyaları Bütünlük Kontrolü (SHA-256):
- **Canlı Legacy DB (`serenut_pos.db`):**
  - Aşama Başlangıcı: `cad5c91ff970b84ebf8270af8cce58f72dcf6b4bda4b4dd48a74f675c17234f3`
  - Aşama Bitişi: `cad5c91ff970b84ebf8270af8cce58f72dcf6b4bda4b4dd48a74f675c17234f3`
  - **Durum: DEĞİŞMEDİ (Birebir Aynı)**
- **Canlı Core Next DB (`serenut_core_v2.db`):**
  - Aşama Başlangıcı: `854611f801684d20004d9880ef8ed408630069646b4d473722a84a13e3024a59`
  - Aşama Bitişi: `854611f801684d20004d9880ef8ed408630069646b4d473722a84a13e3024a59`
  - **Durum: DEĞİŞMEDİ (Birebir Aynı)**

### Kesin Yasaklara Uyum Kanıtı:
1. VPS / `serenut.com` sunucusuna tek bir HTTP/WebSocket isteği gönderilmemiştir.
2. Canlı PostgreSQL veya tenant şemasına dokunulmamıştır.
3. Nutopia ve Erkul Çeyiz verileri taşınmamış, silinmemiş veya dönüştürülmemiştir.
4. `coreNextSalesEngineEnabledProvider` bayrağı değiştirilmemiş, `false` olarak kalmıştır.
5. İlgisiz dosyalarda toplu refactor yapılmamış, `git commit` veya `push` atılmamıştır.

---

## 7. Çözülmemiş Riskler ve Canlıya Geçiş Engelleri

1. **Satış Otoritesi (Sales Cutover):** Satış işlemleri halen Legacy `SqliteSaleRepository` tarafından yürütülmektedir. Core Next satış motoru açılmadan canlı senkronizasyonun açılması durumunda satış hareketleri Sync V4 dışında kalacaktır.
2. **Negatif Muhasebe Satırları İçin Sunucu Protokolü:** Negatif taksit satırları yerelde korunmakta ancak Sync V4 Protocol 6 tarafından desteklenmemektedir (`amount > 0` kuralı). Sunucu tarafında iade/düzeltme mahiyetindeki negatif satırlar için ayrı bir işlem türü (ör. `adjustment` / `reversal`) tanımlanana kadar bu satırlar sunucuya gönderilmeyecektir.
3. **Masaüstü Canlı Çalıştırma:** İstemci tarafında yapılan adaptör düzeltmeleri kaynak kodda doğrulanmıştır; kurulu EXE henüz güncellenmemiştir.

---

## 8. Son Karar ve Sonraki Adım

### Son Karar: `FIXES_VERIFIED`
- Ürün fiyatı, maliyet ve stok alanlarının kuruş/TL dönüşümü ve Protocol 6 alan eşlemeleri düzeltildi ve doğrulandı.
- `debt` türünün `manual_debt` olarak dönüştürülmesi ve satış referanslarının korunması doğrulandı.
- Negatif taksit satırlarının sunucu reddine yol açmasını engelleyen koruma sağlandı.
- Repository'lerin `sync_events` kuyruğuna doğru formatta veri yazdığı testlerle kanıtlandı.
- Canlı DB'ler ve VPS tamamen dokunulmadan korundu.
