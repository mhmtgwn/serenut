# CORE NEXT — STAGE 10.8.8 MIGRATION DATA FRESHNESS REPORT
**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.8.8 — Veri Güncelliği ve İdempotency Denetim Raporu  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Referans Test Dosyası:** [stage10_8_8_adversarial_verification_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_8_adversarial_verification_test.dart) (Test 1)

---

## 1. Yönetici Özeti ve Temel Kök Neden

Stage 10.8.7'de, `MigrationBridgeEngine` motorunun üst üste iki kez çalıştırıldığında `sale_items` tablosundaki `FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT` kuralının ihlal edilmesini önlemek amacıyla, `products` ve `customers` tablolarının aktarımında `ConflictAlgorithm.replace` yerine `ConflictAlgorithm.ignore` stratejisine geçilmiştir.

Ancak yapılan bağımsız karşıt denetim (adversarial audit), bu düzeltmenin ikincil ve kritik bir kusur doğurduğunu kanıtlamıştır:
- **`ConflictAlgorithm.ignore` İkilemi:** SQLite motorunda `INSERT ... ON CONFLICT IGNORE`, hedef tabloda aynı Primary Key (`id`) değerine sahip bir satır bulunduğunda o satırın eklenmesini tamamen yok sayar (skip eder).
- **Sonuç (Veri Bayatlaması / Stale Data):** Kaynak legacy veritabanında bir ürünün fiyatı, adı veya stok miktarı değiştiğinde, migration ikinci kez çalıştırıldığında Core Next hedef veritabanındaki kayıt güncellenmemekte; hedefte **eski (bayat) veriler** kalmaktadır.

---

## 2. Karşıt Test Senaryosu ve Adli Kanıtlar

[stage10_8_8_adversarial_verification_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_8_adversarial_verification_test.dart) (Test 1):

### Adım 1: İlk Migrasyon
- Kaynak legacy veritabanında `prod-fresh-01` kodlu ürün oluşturuldu:
  - Ad: `'Orijinal Ürün Adı'`
  - Fiyat: `100.00 TL` (10000 kuruş)
  - Stok: `50 adet`
- `migrateFromLegacy` ilk kez çalıştırıldı:
  - Hedefte satır başarıyla oluştu: `price_cents = 10000`, `stock_quantity = 50`, `name = 'Orijinal Ürün Adı'`.

### Adım 2: Kaynakta Veri Güncellemesi
- Kaynak legacy veritabanında ürün güncellendi:
  - Ad: `'GÜNCELLENMİŞ Ürün Adı'`
  - Fiyat: `150.00 TL` (15000 kuruş)
  - Stok: `35 adet`

### Adım 3: İkinci Migrasyonun Çalıştırılması
- `migrateFromLegacy` ikinci kez çalıştırıldı.
- Motor `isSuccess = true` döndü ve hiçbir FK hatası fırlatmadı.

### Adım 4: Hedef Veritabanının Doğrulanması (Bulgu Kanıtı)
- Core Next `products` tablosu sorgulandığında:
  - `name`: `'Orijinal Ürün Adı'` (Eski değerde kaldı!)
  - `price_cents`: `10000` (Eski 100 TL fiyatında kaldı!)
  - `stock_quantity`: `50` (Eski 50 stok adedinde kaldı!)

| Alan | Kaynak Güncel Değer | Hedefte Beklenen | Hedefte Gerçekleşen (Mevcut Kod) | Durum |
| :--- | :--- | :--- | :--- | :--- |
| **Ürün Adı** | `GÜNCELLENMİŞ Ürün Adı` | `GÜNCELLENMİŞ Ürün Adı` | `Orijinal Ürün Adı` | ❌ **STALE (Bayat)** |
| **Fiyat (Kuruş)** | `15000` (150.00 TL) | `15000` | `10000` (100.00 TL) | ❌ **STALE (Bayat)** |
| **Stok Miktarı** | `35` | `35` | `50` | ❌ **STALE (Bayat)** |

---

## 3. Tarihsel Referansların ve Silinmiş Ürünlerin Korunması

- **Tarihsel Kayıt Koruması:** Kaynakta bir ürün silindiğinde (`is_deleted = 1` veya satır silinmiş), ancak Core Next üzerinde bu ürüne referans veren geçmiş satış kalemleri (`sale_items`) bulunduğunda, `ConflictAlgorithm.ignore` sayesinde hedefteki ürün kaydı silinmemekte ve yabancı anahtar bütünlüğü korunmaktadır.
- Ancak bu koruma, yukarıda kanıtlanan veri bayatlaması pahasına elde edilmektedir.

---

## 4. Kalıcı Mimari Çözüm Önerisi (In-Place UPSERT)

SQLite'ta hem `ON DELETE RESTRICT` kısıtını ihlal etmemek (yani mevcut satırı `DELETE` etmemek) hem de yeni gelen güncel verileri kaybetmemek için `REPLACE` veya `IGNORE` yerine yerinde güncelleme (**In-Place UPSERT**) kullanılmalıdır:

```sql
INSERT INTO products (
  id, barcode, name, category_id, price_cents, cost_price_cents,
  vat_rate, unit, stock_quantity, critical_threshold, image_url,
  is_active, is_deleted, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  name = excluded.name,
  barcode = excluded.barcode,
  category_id = excluded.category_id,
  price_cents = excluded.price_cents,
  cost_price_cents = excluded.cost_price_cents,
  vat_rate = excluded.vat_rate,
  unit = excluded.unit,
  stock_quantity = excluded.stock_quantity,
  critical_threshold = excluded.critical_threshold,
  image_url = excluded.image_url,
  is_active = excluded.is_active,
  is_deleted = excluded.is_deleted,
  updated_at = excluded.updated_at;
```

Bu mekanizma SQLite satırını silmeden (`DELETE` tetiklemeden) hücreleri güncellediği için:
1. `sale_items` tablosundaki `ON DELETE RESTRICT` kuralı tetiklenmez (0 FK hatası).
2. Ürünün güncel adı, fiyatı ve stoğu hedefe tam aktarılır (0 veri bayatlaması).
