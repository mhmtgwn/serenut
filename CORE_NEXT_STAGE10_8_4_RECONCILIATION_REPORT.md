# CORE NEXT STAGE 10.8.4 — VERİ VE FİNANSAL MUTABAKAT RAPORU (DATA RECONCILIATION REPORT)

**Tarih:** 2026-10-14  
**Kapsam:** Stage 10.8.4 İzole Veritabanı Geçiş Provası ve Adli Mutabakat  
**Test Paketi:** `test/core_next/stage10_8_4_migration_rehearsal_test.dart`  
**Sonuç:** `VERIFIED (Kuruşu Kuruşuna Denklik Kanıtlandı)`  

---

## 1. Mutabakat Metodolojisi ve Matematiksel Kurallar

### Parasal Dönüşüm ve Kuruş Hassasiyeti Kuralı:
Legacy SQLite veritabanındaki `REAL` (floating-point double) alanlar şu formülle dönüştürülür:
$$\text{cents} = \text{round}(\text{amount} \times 100)$$

- **Tolerans Politikası:** Sıfır tolerans (0.00 TL / 0 kuruş). Kuruş seviyesinde sapmaya izin verilmez.
- **Sınır Değer Davranışları:**
  - $0.009 \text{ TL} \rightarrow 1 \text{ kuruş}$
  - $249.99 \text{ TL} \rightarrow 24999 \text{ kuruş}$
  - $-175.50 \text{ TL} \rightarrow -17550 \text{ kuruş}$

---

## 2. İzole Geçiş Provası Mutabakat Tablosu (Test Verileri)

Aşağıdaki veriler `test/core_next/stage10_8_4_migration_rehearsal_test.dart` provasında kaynak ve hedef tablolardan doğrudan çekilmiştir:

| Metrik / Alan | Kaynak (`serenut_pos.db`) | Hedef (`serenut_core_v2.db`) | Fark (Delta) | Adli Durum |
| :--- | :---: | :---: | :---: | :---: |
| **Toplam Ürün Sayısı** | 2 adet | 2 adet | 0 | **EŞİT (PASS)** |
| **Toplam Ürün Stok Adedi** | 150 adet | 150 adet | 0 | **EŞİT (PASS)** |
| **Toplam Ürün Stok Değeri** | 206.25 TL | 20.625 kuruş (= 206.25 TL) | 0.00 TL | **DENK (PASS)** |
| **Toplam Müşteri Sayısı** | 2 adet | 2 adet | 0 | **EŞİT (PASS)** |
| **Toplam Müşteri Bakiyesi** | -350.75 TL | -35.075 kuruş (= -350.75 TL) | 0.00 TL | **DENK (PASS)** |
| **Toplam Satış Sayısı** | 3 adet | 3 adet | 0 | **EŞİT (PASS)** |
| **Toplam Satış Cirosu** | 655.69 TL | 65.569 kuruş (= 655.69 TL) | 0.00 TL | **DENK (PASS)** |
| **Toplam Tahsilat (Paid)** | 254.94 TL | 25.494 kuruş (= 254.94 TL) | 0.00 TL | **DENK (PASS)** |
| **Toplam Vadeli Borç (Debt)** | 400.75 TL | 40.075 kuruş (= 400.75 TL) | 0.00 TL | **DENK (PASS)** |
| **Ödeme Parçası Kayıt Sayısı** | 0 (Eski şemada yoktu) | 4 adet (`sale_payments`) | +4 (Yeni yapı) | **DOĞRULANDI** |

---

## 3. Adli Bütünlük ve Foreign Key Denetimi

Hedef veritabanında SQLite motor seviyesinde yapılan adli kontroller:

1. **`PRAGMA integrity_check;`**
   - Sonuç: `ok` (B-Tree, sayfa dizilimi ve indeks bütünlüğü tamdır).
2. **`PRAGMA foreign_key_check;`**
   - Sonuç: `[]` (Boş — Hiçbir kopuk veya yetim yabancı anahtar bulunmamaktadır).
3. **Müşteri İlişkisi Güvencesi:**
   - Legacy satışlarda `customer_id` değeri `customers` tablosunda bulunmayan kayıtlar için hedefte `customer_id = NULL` atanarak foreign key hatası önlenmiştir.
4. **Bayat `balance_minor` Denetimi:**
   - Migration 60 döneminde hatalı trigger nedeniyle oluşan bayat `balance_minor` kayıtları tespit edildiğinde, `v_customer_ledger_effect` defter toplamı YETKİLİ bakiye kabul edilerek aktarılmış; aradaki sapma `CustomerDiscrepancy` listesine raporlanmıştır.

---

## 4. İdempotency (Tekrar Çalıştırılabilirlik) Mutabakatı

Aynı kaynak veritabanı üzerinde `MigrationBridgeEngine.migrateFromLegacy()` iki kez arka arkaya çalıştırılmıştır:

- **1. Çalıştırma Sonucu:**
  - Ürün: 1, Cari: 1, Satış: 1, Ödeme Parçası: 1.
- **2. Çalıştırma Sonucu:**
  - Ürün: 1, Cari: 1, Satış: 1, Ödeme Parçası: 1.
- **Çift Kayıt / Veri Çoğalması:** 0 adet.
- **Sonuç:** `ConflictAlgorithm.ignore` ve `ConflictAlgorithm.replace` stratejileri sayesinde sistem %100 idempotenttir.

---

## 5. Rollback ve Hata Enjeksiyonu Mutabakatı

`test/core_next/fault_injection_migration_test.dart` kapsamında:
- Cari aktarımı sırasında yapay bir hata enjekte edilmiş (defter bakiye uyuşmazlığı tetiklenmiştir).
- Hedef veritabanındaki tüm tablolar tek bir transaction içinde olduğu için **otomatik ROLLBACK** olmuş; hedef veritabanında sıfır kirlenme kalmıştır (`products = 0`, `customers = 0`, `sales = 0`).
- Hata giderildikten sonra yeniden başlatılan migrasyon 5 ürün, 3 cari ve 2 satışı eksiksiz aktarmıştır.
