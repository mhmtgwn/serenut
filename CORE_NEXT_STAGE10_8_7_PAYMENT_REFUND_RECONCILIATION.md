# CORE NEXT — STAGE 10.8.7 PAYMENT & REFUND RECONCILIATION
**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.8.7 — Karma Ödeme ve İade Mutabakat Raporu  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Referans Test Dosyaları:** [stage10_8_7_remediation_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_7_remediation_test.dart), [stage10_8_6_adversarial_audit_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_6_adversarial_audit_test.dart)

---

## 1. Şema Karşılaştırması: Legacy POS vs. Core Next

| Alan / Fonksiyon | Legacy POS (`serenut_pos.db`) | Core Next (`serenut_core_v2.db`) | Ayrışma / Risk | Stage 10.8.7 Çözümü |
| :--- | :--- | :--- | :--- | :--- |
| **Ödeme Temsili** | `sales.payment_method` (Tek string: 'cash', 'card', 'onAccount', 'mixed') | `sale_payments` tablosu (1..N kayıt, her biri kuruş tamsayı ve tip) | Birden fazla ödeme yapıldığında legacy satış başlığı tek bir yönteme indirgenirse ikincil ödeme yöntemi kaybolur. | Çoklu ödeme satırı varsa `sales.payment_method = 'mixed'` yazılır; tam döküm (`cash: 150.00 TL, onAccount: 100.00 TL`) `sales.notes` sütununa kaydedilir. |
| **Veresiye / Borç Etkisi** | `financial_transactions` (`type = 'DEBT'`, `contact_id`, `amount`) | `ledger_entries` (`account_id = contact_id`, `type = 'DEBIT'`, kuruş) | Müşteri bakiyesi defter kayıtlarıyla eşleşmelidir. | Veresiye tutarı `financial_transactions` tablosuna aktarılır; müşteri `balance` değeri tam kuruş karşılığıyla artırılır. |
| **İade Temsili** | Ayrı `refunds` ve `refund_items` tabloları (`amount > 0`); `sales.refunded_amount` artırılır. | Negatif tutarlı `sales` kaydı (`status = 'REFUND'`, `total_cents < 0`); negatif `sale_items`. | Core Next negatif satışları doğrudan legacy `sales` tablosuna aktarılırsa, şema kısıtları (`CHECK(total_amount >= 0)`) ihlal edilir ve ileri migration çatlar. | `ReverseMigrationEngine`, `status == 'REFUND'` veya `totalCents < 0` satırlarını yakalar; legacy `refunds` ve `refund_items` tablolarına pozitif tutarla dönüştürür; `sales.refunded_amount` değerini günceller. |
| **Para Birimi Birimi** | TL (Gerçel sayı / Double, e.g. `250.50`) | Kuruş (Tamsayı / Integer, e.g. `25050`) | Kuruş yuvarlama kayıpları. | `centsToDouble(int cents) => cents / 100.0` ve `doubleToCents(double val) => (val * 100).round()` ile %100 deterministik kuruş-kuruş mutabakatı. |

---

## 2. Karma Ödeme (Split Payment) Mutabakatı

### Senaryo ve Test Edilen Akış
Bir müşteriye toplam **250.00 TL (25000 kuruş)** tutarında satış yapılır:
- **150.00 TL (15000 kuruş)** Peşin Nakit (`cash`)
- **100.00 TL (10000 kuruş)** Veresiye (`onAccount`)

### Core Next Durumu
- `sales`: `id = 'sale-split-01'`, `total_cents = 25000`
- `sale_payments`:
  - Satır 1: `payment_type = 'cash'`, `amount_cents = 15000`
  - Satır 2: `payment_type = 'onAccount'`, `amount_cents = 10000`
- `ledger_entries`: Müşteri için `10000 kuruş DEBIT`

### Reverse Rollback Sonrası Legacy POS Durumu
- `sales`:
  - `id = 'sale-split-01'`
  - `total_amount = 250.00`
  - `payment_method = 'mixed'`
  - `notes = 'Parçalı Ödeme Dağılımı: cash: 150.00 TL, onAccount: 100.00 TL'`
- `financial_transactions`:
  - `contact_id = 'cust-split-01'`, `type = 'DEBT'`, `amount = 100.00`
- `contacts`:
  - Müşteri cari bakiyesi tam `+100.00 TL` artırılmıştır.

### Bağımsız Mutabakat Formülü
$$\sum \text{Satış Toplamı} (250.00) = \sum \text{Nakit Ödeme} (150.00) + \sum \text{Veresiye Defter Etkisi} (100.00)$$
$$\text{Fark (Delta)} = 0.00 \text{ TL}$$

---

## 3. İade (Refund) Şeması ve Döngüsel Migration Mutabakatı

### Senaryo ve Test Edilen Akış
1. Orijinal Satış: `100.00 TL` (1 adet Ürün A)
2. Core Next'te İade: `-100.00 TL` (`status = 'REFUND'`, -1 adet Ürün A)
3. Reverse Rollback çalıştırılır:
   - Legacy `sales` tablosuna negatif satış **yazılmaz**.
   - Legacy `refunds` tablosuna `id = 'refund-...'`, `sale_id = 'sale-orig-01'`, `amount = 100.00` yazılır.
   - Legacy `refund_items` tablosuna `quantity = 1`, `unit_price = 100.00` yazılır.
   - Orijinal satışın `sales.refunded_amount` sütunu `100.00 TL` olarak güncellenir.
4. **Döngüsel İleri Doğrulama (Roundtrip):**
   - Bu legacy veritabanı üzerinde tekrar `MigrationBridgeEngine.migrateFromLegacy` çalıştırıldığında, legacy `sales` tablosunda hiçbir negatif satır bulunmadığından ve `refunds` tablosu başarıyla okunduğundan migrasyon **0 hata** ile tamamlanır.

---

## 4. İki Kez Çalıştırma (Idempotency) ve Mükerrerlik Kanıtı

| Tablo / Kayıt Türü | 1. Rollback Sonrası | 2. Rollback Sonrası | Mükerrer Kayıt (Duplicate) | Yabancı Anahtar Hatası |
| :--- | :--- | :--- | :--- | :--- |
| **Legacy `sales`** | 1 kayıt | 1 kayıt | 0 | Yok |
| **Legacy `sale_items`**| 1 kayıt | 1 kayıt | 0 | Yok |
| **Legacy `financial_transactions`** | 1 kayıt | 1 kayıt | 0 | Yok |
| **Legacy `refunds`** | 1 kayıt | 1 kayıt | 0 | Yok |
| **Legacy `refund_items`** | 1 kayıt | 1 kayıt | 0 | Yok |

`ReverseMigrationEngine`, `ConflictAlgorithm.ignore` ve idempotent SQL `WHERE NOT EXISTS` kontrolleri kullanarak hem satışları, hem kalemleri hem de iadeleri mükerrer kayıt oluşturmadan korur.
