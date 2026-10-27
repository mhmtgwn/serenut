# CORE NEXT STAGE 10.8.4 — VERİTABANI MİGRASYON VE ALAN EŞLEŞTİRME MATRİSİ (MIGRATION MAPPING)

**Tarih:** 2026-10-14  
**Kaynak Veritabanı:** `serenut_pos.db` (Legacy SQLite — Şema v60)  
**Hedef Veritabanı:** `serenut_core_v2.db` (Core Next SQLite — Şema v3)  
**Denetlenen Motor:** `MigrationBridgeEngine` (`core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart`)  

---

## 1. Tablo Düzeyinde Kapsam Özeti

| Kaynak Tablo (Legacy) | Hedef Tablo (Core Next) | Kapsam Durumu | Açıklama / Adli Tespit |
| :--- | :--- | :---: | :--- |
| `products` | `products` | **VERIFIED** | Fiyatlar kuruşa dönüştürülerek (`price_cents`, `cost_price_cents`) aktarılır. |
| `customers` | `customers` | **VERIFIED** | Bakiyeler `v_customer_ledger_effect` defteriyle mutabakat yapılarak aktarılır. |
| `sales` | `sales` | **VERIFIED** | Başlık bilgileri kuruş tamsayısına dönüştürülerek aktarılır. |
| `sales` (Ödeme Bilgisi) | `sale_payments` | **VERIFIED** | Nakit, kart, veresiye, karma (`mixed`) ödeme parçaları oluşturulur. |
| `sale_items` | `sale_items` | **MISSING** | **Taşınmıyor!** `MigrationBridgeEngine` içinde `sale_items` sorgusu veya yazımı yoktur. |
| `financial_transactions` | `ledger_entries` | **MISSING** | **Taşınmıyor!** Yalnızca cari anlık bakiye doğrulanır; geçmiş defter satırları kopyalanmaz. |
| `refunds` & `refund_items` | `refunds` & `refund_items` | **MISSING** | **Taşınmıyor!** İade ve iptal geçmişi taşınmamaktadır. |
| `sync_outbox_v4` | `sync_events` | **MISSING** | **Taşınmıyor!** Bekleyen eski mutasyonlar yeni Protocol 6 kuyruğuna dönüştürülmemektedir. |
| `users` | `users` | **MISSING** | **Taşınmıyor!** Kullanıcı ve PIN kayıtları Core Next `users` tablosuna aktarılmamaktadır. |
| (products.category) | `categories` | **MISSING** | **Taşınmıyor!** Bağımsız kategori tablosu doldurulmamaktadır. |
| `audit_logs` | — | **KAPSAM DIŞI** | Adli denetim kayıtları SQLite yerine Sentry/Telemetry üzerinde saklanmaktadır. |

---

## 2. Ayrıntılı Alan Eşleştirme ve Dönüşüm Kuralları

### A. Ürün Kataloğu (`products` -> `products`)

| Kaynak Alan (`serenut_pos.db`) | Hedef Alan (`serenut_core_v2.db`) | Tip Dönüşümü | Kural & Null Davranışı | Durum |
| :--- | :--- | :--- | :--- | :---: |
| `id` / `sku` / `barcode` | `id` | `TEXT` -> `TEXT` | `row['id'] ?? barcode` | **VERIFIED** |
| `barcode` / `sku` | `barcode` | `TEXT` -> `TEXT` | Boş veya null ise kayıt atlanır (`continue`). | **VERIFIED** |
| `name` | `name` | `TEXT` -> `TEXT` | Null ise `'İsimsiz Ürün'` varsayılır. Türkçe karakterler korunur. | **VERIFIED** |
| `price` / `price_minor` | `price_cents` | `REAL`/`INT` -> `INTEGER` | `price_minor != null ? minor : (price * 100).round()` | **VERIFIED** |
| `purchase_price` / `cost_price` | `cost_price_cents` | `REAL`/`INT` -> `INTEGER?` | `(purchase_price * 100).round()`, null ise `null`. | **VERIFIED** |
| `vat` / `vat_rate` | `vat_rate` | `INTEGER` -> `INTEGER` | Null ise 20 varsayılır. | **VERIFIED** |
| `sale_type` / `unit` | `unit` | `TEXT` -> `TEXT` | `'weighed'` veya `'kg'` ise `'kg'`, aksi halde `'piece'`. | **VERIFIED** |
| `quantity` / `stock_quantity` | `stock_quantity` | `REAL` -> `INTEGER` | `stock.toInt()` ile tamsayı adede yuvarlanır. | **VERIFIED** |
| `min_stock` | `critical_threshold` | `INTEGER` -> `INTEGER` | Null ise 5 varsayılır. | **VERIFIED** |
| `image_url` | `image_url` | `TEXT` -> `TEXT?` | Birebir kopyalanır. | **VERIFIED** |
| `is_active` | `is_active` | `INTEGER` -> `INTEGER` | Null ise 1. | **VERIFIED** |
| `is_deleted` | `is_deleted` | `INTEGER` -> `INTEGER` | Null ise 0. | **VERIFIED** |
| — | `updated_at` | `INTEGER` | `DateTime.now().millisecondsSinceEpoch` atanır. | **VERIFIED** |

---

### B. Müşteriler ve Cari Hesaplar (`customers` -> `customers`)

| Kaynak Alan (`serenut_pos.db`) | Hedef Alan (`serenut_core_v2.db`) | Tip Dönüşümü | Kural & Null Davranışı | Durum |
| :--- | :--- | :--- | :--- | :---: |
| `id` | `id` | `TEXT` -> `TEXT` | Boş ise `'customer-pesin-default'` atanır. | **VERIFIED** |
| `name` | `name` | `TEXT` -> `TEXT` | Null ise `'İsimsiz Müşteri'`. Türkçe karakterler korunur. | **VERIFIED** |
| `phone` | `phone` | `TEXT` -> `TEXT?` | Birebir kopyalanır. | **VERIFIED** |
| `email` | `email` | `TEXT` -> `TEXT?` | Birebir kopyalanır. | **VERIFIED** |
| `balance` / `balance_minor` | `balance_cents` | `REAL`/`INT` -> `INTEGER` | `v_customer_ledger_effect` toplamı ile kuruş kuruş doğrulanır; sapma varsa durdurulur (`FAIL_CLOSED`). | **VERIFIED** |
| `credit_limit` / `credit_limit_minor` | `credit_limit_cents` | `REAL`/`INT` -> `INTEGER` | `credit_limit_minor ?? (credit_limit * 100).round()`. | **VERIFIED** |
| `is_active` | `is_active` | `INTEGER` -> `INTEGER` | Null ise 1. | **VERIFIED** |
| `is_deleted` | `is_deleted` | `INTEGER` -> `INTEGER` | Null ise 0. | **VERIFIED** |
| — | `updated_at` | `INTEGER` | `DateTime.now().millisecondsSinceEpoch` atanır. | **VERIFIED** |

---

### C. Satış Başlıkları ve Ödemeler (`sales` -> `sales` & `sale_payments`)

| Kaynak Alan (`serenut_pos.db`) | Hedef Alan (`serenut_core_v2.db`) | Tip Dönüşümü | Kural & Güvenlik Kısıtı | Durum |
| :--- | :--- | :--- | :--- | :---: |
| `id` | `sales.id` | `TEXT` -> `TEXT` | Birebir kopyalanır. | **VERIFIED** |
| `receipt_no` | `sales.receipt_no` | `TEXT` -> `TEXT` | `receipt_no ?? id` atanır. | **VERIFIED** |
| `customer_id` | `sales.customer_id` | `TEXT` -> `TEXT?` | Hedef `customers` tablosunda ID doğrulanır; yoksa `null` yapılır (Kopuk FK engeli). | **VERIFIED** |
| `total_amount` / `total_amount_minor` | `sales.total_cents` | `REAL`/`INT` -> `INTEGER` | `total_amount_minor ?? (total * 100).round()`. Negatif olamaz. | **VERIFIED** |
| `paid_amount` / `paid_amount_minor` | `sales.paid_cents` | `REAL`/`INT` -> `INTEGER` | `paid > total` ise işlem durdurulur (`reconciliation failure`). | **VERIFIED** |
| `discount_amount` | `sales.discount_cents` | `REAL`/`INT` -> `INTEGER` | `discount_amount_minor ?? (discount * 100).round()`. | **VERIFIED** |
| — | `sales.debt_cents` | `INTEGER` | `total_cents - paid_cents` hesaplanır. | **VERIFIED** |
| `status` | `sales.status` | `TEXT` -> `TEXT` | Null ise `'COMPLETED'`. | **VERIFIED** |
| `idempotency_key` | `sales.idempotency_key` | `TEXT` -> `TEXT` | `idempotency_key ?? id`. | **VERIFIED** |
| `created_at` | `sales.created_at` | `TEXT`/`INT` -> `INTEGER` | ISO-8601 string milisaniyeye parse edilir. | **VERIFIED** |
| `payment_method` & `paid_amount` | `sale_payments.amount_cents` | `REAL` -> `INTEGER` | `paid_cents > 0` ise `$saleId-pay-legacy-paid` kaydı eklenir. | **VERIFIED** |
| `debt_cents` | `sale_payments.amount_cents` | `INTEGER` | `debt_cents > 0` ise `$saleId-pay-legacy-debt` kaydı (`onAccount`) eklenir. | **VERIFIED** |

---

### D. Eksik Kalan Tabloların Durumu (Gap Matrix)

| Tablo Adı | Neden Kritik? | Canlı Cutover Öncesi Gereksinim | Durum |
| :--- | :--- | :--- | :---: |
| **`sale_items`** | Geçmiş fiş dökümü, iade use-case ve ürün bazlı geçmiş satış raporları için zorunludur. | `MigrationBridgeEngine`'e `sale_items` batch insert döngüsü eklenmelidir. | **MISSING** |
| **`financial_transactions`** | Müşterinin geçmiş veresiye ve tahsilat ekstresi (hesap dökümü) için gereklidir. | `financial_transactions` satırları `ledger_entries` formatına dönüştürülmelidir. | **MISSING** |
| **`sync_outbox_v4`** | Kasanın çevrimdışıyken yaptığı ve henüz sunucuya iletilmemiş satışlarının kaybolmaması için zorunludur. | `state = 'PENDING'` olan outbox kayıtları `sync_events`'e aktarılmalıdır. | **MISSING** |
| **`users`** | Kasiyerlerin ve yöneticilerin PIN kodları ile sisteme giriş yapabilmesi için gereklidir. | Kullanıcı rolleri ve PIN hash'leri `users` tablosuna kopyalanmalıdır. | **MISSING** |
| **`refunds` & `refund_items`** | Geçmiş iade kayıtlarının ve stok geri alımlarının takibi için gereklidir. | `refunds` ve `refund_items` tabloları dönüştürülmelidir. | **MISSING** |
