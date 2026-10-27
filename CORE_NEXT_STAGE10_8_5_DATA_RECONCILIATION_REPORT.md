# CORE NEXT — STAGE 10.8.5 DATA RECONCILIATION REPORT
**Rapor Tarihi:** 14 Ekim 2026  
**Aşama:** Stage 10.8.5 — Parasal ve Veri Bütünlüğü Mutabakatı  
**Tolerans:** 0 Kuruş (Sıfır Tolerans)  
**Doğrulama Testi:** `test/core_next/stage10_8_5_reverse_rollback_test.dart` (Test 4 & 5)  
**Sonuç:** TÜM PARASAL ALANLAR VE İLİŞKİSEL KISITLAR %100 DOĞRULANDI.

---

## 1. Kuruş Dönüşümü ve Ondalık Hassasiyet Sınır Değerleri

Double kayan nokta aritmetiğinde (`IEEE 754`) bilinen yuvarlama hataları (örneğin `0.1 + 0.2 = 0.30000000000000004`) ve para birimi sınır değerleri `stage10_8_5_reverse_rollback_test.dart` Test 4 kapsamında özel olarak test edilmiştir.

### Sınır Değeri Test Sonuçları Tablosu

| Test Senaryosu | Kaynak Değer (Legacy Double) | Kuruş Formülü `(val * 100).round()` | Hedef Değer (Core Next Cents) | Hedef Gösterim (TL ve Kuruş) | Sapma | Durum |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Minimum Para Birimi** | `0.01 TL` (1 Kuruş) | `(0.01 * 100).round()` | `1` | `0,01 TL (1 kuruş)` | 0 kuruş | **PASS** |
| **Kayan Nokta Tehlikesi** | `0.1 + 0.2 TL` (`0.30000000000000004`) | `((0.1 + 0.2) * 100).round()` | `30` | `0,30 TL (30 kuruş)` | 0 kuruş | **PASS** |
| **Sıfır Değer** | `0.00 TL` | `(0.00 * 100).round()` | `0` | `0,00 TL (0 kuruş)` | 0 kuruş | **PASS** |
| **Yüksek Tutar (Büyük Şirket)**| `999.999,99 TL` | `(999999.99 * 100).round()` | `99.999.999` | `999.999,99 TL (99.999.999 kuruş)` | 0 kuruş | **PASS** |
| **Negatif Cari Bakiye** | `-1.250,75 TL` (Borç) | `(-1250.75 * 100).round()` | `-125.075` | `-1.250,75 TL (-125.075 kuruş)` | 0 kuruş | **PASS** |

> **Not:** Türkiye finansal gösterim standardına uygun olarak binlik ayraç nokta (`.`), ondalık ve kuruş ayracı ise virgül (`,`) olarak temsil edilmektedir.

---

## 2. Kaynak ve Hedef Bağımsız Toplam Mutabakatı

İzole veri setleri üzerinde kaynak ve hedef veritabanları bağımsız SQL sorgularıyla toplanmış ve mutabakat yapılmıştır:

### A. Ürün Kataloğu Mutabakatı
- Kaynak Toplam Ürün Fiyatı: `32,50 TL`
- Hedef Toplam Ürün Fiyatı: `3.250 kuruş` (`32,50 TL`)
- **Fark:** 0,00 TL (0 kuruş).

### B. Müşteri Bakiye Mutabakatı
- Kaynak Müşteri Bakiyesi: `-1.250,75 TL`
- Hedef Müşteri Bakiyesi: `-125.075 kuruş` (`-1.250,75 TL`)
- **Fark:** 0,00 TL (0 kuruş).

### C. Satış ve Tahsilat Mutabakatı
- Kaynak Satış Toplamı: `65,00 TL`
- Hedef Satış Toplamı: `6.500 kuruş` (`65,00 TL`)
- Kaynak Tahsilat Toplamı: `30,00 TL`
- Hedef Tahsilat Toplamı: `3.000 kuruş` (`30,00 TL`)
- **Fark:** 0,00 TL (0 kuruş).

---

## 3. SQLite Düzeyinde Bütünlük ve Kısıt Denetimleri

`test/core_next/stage10_8_5_reverse_rollback_test.dart` Test 5 kapsamında SQLite motoruna doğrudan PRAGMA komutları verilmiştir:

```sql
PRAGMA integrity_check;
-- Sonuç: ok

PRAGMA foreign_key_check;
-- Sonuç: 0 satır (Hiçbir yabancı anahtar ihlali bulunmamaktadır)
```

### Denetlenen İlişkisel Kısıtlar:
1. `sale_items.sale_id` -> `sales.id` (ON DELETE CASCADE) — Tüm kalemler geçerli bir satış başlığına bağlıdır.
2. `sale_items.product_id` -> `products.id` (ON DELETE RESTRICT) — Tüm kalemler katalogdaki geçerli bir ürüne bağlıdır.
3. `products.category_id` -> `categories.id` (ON DELETE SET NULL) — Kategori ilişkileri tutarlıdır.
4. `sales.customer_id` -> `customers.id` (ON DELETE SET NULL) — Müşteri ilişkileri geçerlidir.
5. `ledger_entries.customer_id` -> `customers.id` (ON DELETE RESTRICT) — Defter hareketleri geçerli cariye bağlıdır.
6. `sale_payments.sale_id` -> `sales.id` (ON DELETE CASCADE) — Ödeme kayıtları doğru satışa bağlıdır.

---

## 4. Sonuç

Veri dönüşümünde kayan nokta hatası, yuvarlama kaybı veya ilişkisel kısıt ihlali bulunmamaktadır. Sistem parasal ve yapısal açıdan tam mutabakata sahiptir.
