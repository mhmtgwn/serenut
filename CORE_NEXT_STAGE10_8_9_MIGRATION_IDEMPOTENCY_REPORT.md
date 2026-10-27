# SERENUT OS — STAGE 10.8.9 MIGRATION IDEMPOTENCY & FRESHNESS REPORT

**Tarih:** 2026-10-15  
**Proje:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Kapsam:** ADV-01 (Migration Veri Güncelliği & In-Place UPSERT) ve ADV-02 (İade Rollback Idempotency)

---

## 1. ADV-01: MIGRATION VERİ GÜNCELLİĞİ VE IN-PLACE UPSERT

### 1.1. Kusur Tespiti ve Kök Neden
Stage 10.8.8 bağımsız denetiminde `MigrationBridgeEngine.dart` dosyasında şu iki büyük sorun bulunmuştu:
1. `ConflictAlgorithm.ignore` kullanıldığında: Kaynakta (legacy) ürünün adı, fiyatı veya stok adedi değiştirildikten sonra ikinci bir migration çalıştırıldığında hedefteki (Core Next) ürün güncellenmiyor, eski değerlerinde donup kalıyordu.
2. `ConflictAlgorithm.replace` kullanıldığında: SQLite motoru `REPLACE` komutunu `DELETE` + `INSERT` olarak işlettiğinden, hedef veritabanında `sale_items` tablosundaki `FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT` kuralı tetikleniyor ve `DatabaseException(787)` hatası ile işlem çöküyordu.

### 1.2. Mimari Çözüm: In-Place UPSERT (`ON CONFLICT DO UPDATE`)
`core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart` dosyasında `products`, `customers` ve `categories` tablolarına veri aktarımı native SQLite UPSERT kalıbına dönüştürüldü:
```sql
INSERT INTO products (
  id, legacy_id, name, barcode, price_cents, cost_cents, vat_rate, stock_quantity, ...
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ...)
ON CONFLICT(id) DO UPDATE SET
  name = excluded.name,
  barcode = excluded.barcode,
  price_cents = excluded.price_cents,
  cost_cents = excluded.cost_cents,
  vat_rate = excluded.vat_rate,
  stock_quantity = excluded.stock_quantity,
  updated_at = excluded.updated_at
```

Bu yöntemin avantajları:
- **FK Güvenliği:** Satır fiziksel olarak silinmediği için bağlı `sale_items` kayıtlarının `RESTRICT` kısıtlaması tetiklenmez.
- **Veri Güncelliği:** Kaynakta değişen ad, barkod, fiyat ve stok verileri hedefte anında güncellenir.
- **Idempotency:** Aynı migration 10 kez de çalıştırılsa hedef tablo tutarlı ve güncel kalır.

### 1.3. Doğrulama Senaryosu ve Test Kanıtı
Test: `test/core_next/stage10_8_9_remediation_test.dart` ("ADV-01: Migration fresh updates do not fail FK RESTRICT and update target in-place")
- **Adım 1:** Legacy DB'ye `prod-1` ("Laptop", 15.000 TL, stok 10) eklendi ve 1. migration çalıştırıldı.
- **Adım 2:** Hedef Core Next DB'sinde `prod-1` kullanılarak bir satış yapıldı (`sale_items` satırı oluşturuldu).
- **Adım 3:** Legacy DB'de `prod-1` güncellendi: Ad "Laptop Pro", Fiyat 18.000 TL, Stok 8 yapıldı.
- **Adım 4:** 2. migration çalıştırıldı.
- **Sonuç:**
  - Hata: `0` (FK RESTRICT hatası fırlatılmadı).
  - Hedef Adı: `Laptop Pro` (Güncellendi).
  - Hedef Fiyat: `1800000 cents` (18.000 TL) (Güncellendi).
  - Hedef Stok: `8.0` (Güncellendi).
  - İlişkili `sale_items`: Eksiksiz korundu.

---

## 2. ADV-02: İADE ROLLBACK IDEMPOTENCY

### 2.1. Kusur Tespiti ve Kök Neden
Stage 10.8.8'de `ReverseMigrationEngine.reverseMigrateRefunds` metodunda şu sorgu çalışıyordu:
```sql
UPDATE sales SET refunded_amount = refunded_amount + ?, status = ? WHERE id = ?
```
Bu koşulsuz artım (`refunded_amount + ?`), rollback ikinci kez veya network retry / crash recovery sırasında tekrar çalıştığında aynı iadeyi tekrar ekliyor ve `refunded_amount` değerini 40 TL'den 80 TL'ye fırlatıyordu.

### 2.2. Mimari Çözüm: Deterministik Alt Sorgu Yeniden Hesaplama
`ReverseMigrationEngine` içerisinde iade rollback akışı yeniden yapılandırıldı:
1. İade kaydı `refunds` tablosuna `INSERT OR IGNORE` ile eklenir (böylece tekil `id` sayesinde aynı iade çiftlenmez).
2. Satışın `refunded_amount` değeri artımlı toplama yerine, `refunds` tablosundaki o satışa ait kayıtların toplamı olarak tek bir atomik alt sorgu ile hesaplanır:
```sql
UPDATE sales SET 
  refunded_amount = (SELECT COALESCE(SUM(amount), 0.0) FROM refunds WHERE sale_id = ?),
  status = CASE 
    WHEN (SELECT COALESCE(SUM(amount), 0.0) FROM refunds WHERE sale_id = ?) >= final_amount THEN 'refunded'
    ELSE 'partially_refunded'
  END
WHERE id = ?
```

### 2.3. Doğrulama Senaryosu ve Test Kanıtı
Test: `test/core_next/stage10_8_9_remediation_test.dart` ("ADV-02: Refund rollback idempotency prevents doubling of refunded_amount")
- **Senaryo:** 100 TL'lik satışa (`sale-1`) 40 TL'lik iade (`ref-1`) uygulandı.
- **1. Rollback:** Legacy'de `refunds` tablosuna 40 TL eklendi. `sales.refunded_amount = 40.0`, `status = 'partially_refunded'`.
- **2. Rollback (Yeniden Çalıştırma):** Tekrar çalıştırıldı.
- **Sonuç:**
  - Legacy `refunds` tablosundaki satır sayısı: `1`
  - Legacy `sales.refunded_amount`: `40.0` TL (İkiye katlanmadı!).
  - Legacy `sales.status`: `partially_refunded`.
  - Kalan net satış tutarı: `60.0` TL (`100.0 - 40.0`).

---

## 3. MUTABAKAT VE BÜTÜNLÜK ÖZETİ

| Parametre | 1. Çalıştırma | 2. Çalıştırma (Retry) | Beklenen Matematiksel Sonuç | Durum |
|---|---|---|---|---|
| Ürün Adı | Laptop Pro | Laptop Pro | Laptop Pro | **EŞLEŞTİ** |
| Ürün Fiyatı | 18.000 TL | 18.000 TL | 18.000 TL | **EŞLEŞTİ** |
| Ürün Stok | 8.0 | 8.0 | 8.0 | **EŞLEŞTİ** |
| FK Hata Sayısı | 0 | 0 | 0 | **SIFIR HATA** |
| İade Sayısı | 1 | 1 | 1 | **EŞLEŞTİ** |
| İade Edilen Tutar | 40.0 TL | 40.0 TL | 40.0 TL | **EŞLEŞTİ** |
| Kalan Tutar | 60.0 TL | 60.0 TL | 60.0 TL | **EŞLEŞTİ** |

Hem forward migration veri tazeliği (freshness) hem de reverse migration iade idempotency doğrulamaları %100 başarıyla tamamlanmıştır.
