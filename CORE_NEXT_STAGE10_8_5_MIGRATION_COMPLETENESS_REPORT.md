# CORE NEXT — STAGE 10.8.5 MIGRATION COMPLETENESS REPORT
**Rapor Tarihi:** 14 Ekim 2026  
**Aşama:** Stage 10.8.5 — Migration Completeness, Reverse-Rollback Proof & Cutover Safety  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Canlı Kapı Kararı:** `LIVE_GATE: BLOCKED` (Üretim geçişi blokeli; izole pilot koşulları doğrulanmış)

---

## 1. Giriş ve Mevcut Durum Doğrulaması

Stage 10.8.4 aşamasında `MigrationBridgeEngine` çekirdek katalog, müşteri ve satış başlıklarını taşımış; ancak `sale_items`, `financial_transactions`, `users`, `categories` ve `sync_outbox_v4` tablolarını taşımadığı adli testlerle (`stage10_8_4_migration_rehearsal_test.dart`) kanıtlanmıştı.

Stage 10.8.5 kapsamında `MigrationBridgeEngine` izole test ortamında genişletilmiş ve eksik kalan tüm veri gruplarının kuruş hassasiyetinde, yabancı anahtar (FK) bütünlüğünü koruyarak ve çift yönlü geri dönüş (Reverse Rollback) kabiliyetiyle taşınması tamamlanmıştır.

### Adli Git ve Çalışma Ağacı Durumu
- **Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **`git diff --check`:** Temiz, 0 hata/uyarı.
- **Test Paketi Sayımı:**
  - `test/core_next/`: 191 test (Stage 10.8.5 testleri dahil, tamamı PASS)
  - `test/ui/`: 9 test (tamamı PASS)
  - `test/services/`: 13 test (tamamı PASS)
  - **Toplam Benzersiz Test Sayısı:** 213 test, 0 başarısızlık.

---

## 2. Veri Grupları Kapsam Denetimi Matrisi

| Veri Grubu | Kaynak Tablo (Legacy v60) | Hedef Tablo (Core Next v3) | Dönüşüm & Kuruş Kuralı | Korunan Kimlikler | Eksik / Risk Analizi | Doğrulama Testi |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Kullanıcılar & Roller** | `users` | `users` | `pin_hash` ve `password_hash` korunur; `role` (admin/cashier) aktarılır | `id`, `username` | Kullanıcı adı çakışması durumunda sentetik `user_$id` fallback'i | `test 1` |
| **Kategoriler** | `categories` veya `products.category` | `categories` | Varsa doğrudan, yoksa tekil `category` string'lerinden sentetik slug ID ile oluşturulur | `id`, `name` | Kategori tablosu olmayan v60 kurulumları için otomatik türetme | `test 1` |
| **Ürün Kataloğu** | `products` | `products` | `price * 100` -> `price_cents`, `purchase_price * 100` -> `cost_price_cents` | `id`, `barcode`, `sku` | Kategori FK ilişkisi (`category_id`) bağlandı | `test 1` |
| **Müşteriler / Cariler** | `customers` | `customers` | `balance * 100` -> `balance_cents`, `credit_limit * 100` -> `credit_limit_cents` | `id`, `phone`, `tax_number` | Bayat `balance_minor` tespit edilip defter bakiyesi esas alınır | `test 1` |
| **Satış Başlıkları** | `sales` | `sales` | `total_amount * 100` -> `total_cents`, `paid_amount * 100` -> `paid_cents` | `id`, `receipt_no`, `idempotency_key` | Negatif tutar, tahsilat > toplam kontrolleri devrede | `test 1, 4` |
| **Satış Kalemleri** | `sale_items` | `sale_items` | `unit_price * 100` -> `unit_price_cents`, `subtotal * 100` -> `total_cents` | `id`, `sale_id`, `product_id` | Yetim kalem koruması: Silinmiş ürün için placeholder açılır | `test 1` |
| **Ödeme Dağılımları** | `sales.payment_method` | `sale_payments` | Nakit, kart, veresiye ve karma (`mixed`) ayrıştırılır; kuruş olarak yazılır | `id` (`$saleId-pay-legacy-*`) | Parçalı ödemeler için sahte tahmin üretilmez, açıkça `mixed` etiketlenir | `test 1` |
| **Müşteri Defteri** | `financial_transactions` | `ledger_entries` | `amount * 100` -> `amount_cents`, kümülatif `balance_after_cents` hesaplanır | `id`, `customer_id`, `reference_sale_id` | Müşteri hareket sırasına göre deterministik bakiye takibi | `test 1` |
| **Bekleyen Senkronizasyon** | `sync_outbox_v4` (`PENDING`) | `sync_events` (`PENDING`) | `payload` -> `payload_json`, `mutation_id` -> `event_id`, sıra korunur | `event_id`, `entity_type`, `entity_id` | Çevrimdışı bekleyen satış ve mutasyonların kaybolması engellendi | `test 1` |

---

## 3. Migration Motorunun Güvenlik Özellikleri

1. **ACID Transaction Garantisi:** Tüm migrasyon `targetDb.transaction` bloğu içerisinde tek bir işlem olarak çalışır. Herhangi bir aşamada hata oluşursa hedef veritabanına hiçbir kirli/yarım kayıt yazılmaz.
2. **Fiziksel Dosya Yedeği:** `legacyFilePath` belirtilmişse, migrasyona başlamadan önce fiziksel dosya kopyası (`.backup`) oluşturulur.
3. **Yabancı Anahtar (FK) Sıralaması:** Tablolar bağımlılık sırasına göre oluşturulur:
   `Users -> Categories -> Customers -> Products -> Sales -> Sale Items -> Sale Payments -> Ledger Entries -> Sync Events`.
4. **Yetim Kayıt İzolasyonu:** Eğer eski sistemde ürün silinmiş fakat satış kalemi kalmışsa, `sale_items` tablosundaki `FOREIGN KEY (product_id) REFERENCES products (id)` kısıtının bozulmaması için `is_deleted = 1` olan sentetik placeholder ürün kaydı açılır; veri kaybı önlenir.
5. **İdempotency & Tekrar Çalıştırma:** Aynı legacy veritabanı üzerinde motorun ikinci veya üçüncü kez çalıştırılması `ConflictAlgorithm.replace` ve `ignore` kuralları sayesinde mükerrer kayıt üretmez. `stage10_8_5_reverse_rollback_test.dart` Test 2 ile kanıtlanmıştır.

---

## 4. Doğrulama ve Test Sonuçları

- **`test/core_next/stage10_8_5_reverse_rollback_test.dart`:** 5/5 PASS (Süre: ~6s)
- **`test/core_next/stage10_8_4_migration_rehearsal_test.dart`:** 5/5 PASS (Süre: ~9s)
- **Genel `core_next` Paketi:** 191/191 PASS.
