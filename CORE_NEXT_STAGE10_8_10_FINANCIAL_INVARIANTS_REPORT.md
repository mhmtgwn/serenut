# SERENUT OS — STAGE 10.8.10 FINANCIAL INVARIANTS REPORT

**Tarih:** 2026-10-15  
**Proje:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Kapsam:** Finansal Değişmezler, Matematiksel Tutarlılık, Kuruş/TL Dönüşümleri ve İade Mutabakatı

---

## 1. TEMEL FİNANSAL DEĞİŞMEZLER (MATHEMATICAL INVARIANTS)

Sistemdeki tüm finansal işlemler aşağıdaki 5 katı değişmeze göre doğrulanmıştır:

### Değişmez 1: Satış Toplamı Değişmezi
$$\text{total\_cents} = \text{subtotal\_cents} - \text{discount\_cents} + \text{vat\_total\_cents}$$
- Kuruş bazlı tam sayı (`MoneyCents` / `INTEGER`) aritmetiği kullanıldığı için IEEE-754 kayan noktalı sayı yuvarlama hatası imkansız kılınmıştır.

### Değişmez 2: Ödeme Kalemleri Mutabakat Değişmezi
$$\sum_{i=1}^{n} \text{sale\_payments.amount\_cents}_i = \text{total\_cents}$$
- Her bir satışa ait ödeme kalemlerinin (Nakit + Kart + Vadeli) toplamı, satışın net tutarına kuruşu kuruşuna eşit olmak zorundadır.

### Değişmez 3: İade Bütünlüğü Değişmezi
$$\sum \text{refunds.amount} \le \text{total\_amount} \quad \text{ve} \quad \text{sales.refunded\_amount} = \sum \text{refunds.amount}$$
- Bir satış için yapılan kısmi veya tam iadelerin toplamı, orijinal satış tutarını aşamaz.
- `sales.refunded_amount` değeri, doğrudan `refunds` tablosundaki kayıtların toplamından alt sorgu ile deterministik olarak hesaplanır; art arda çalıştırmalarda çiftlenmez.

### Değişmez 4: Cari Borçlanma Değişmezi
$$\text{debt\_cents} = \text{total\_cents} - \text{paid\_cents}$$
- Vadeli (onAccount) ödemelerde müşteriye yansıtılan borç miktarı, ödenmeyen tutara kesinlikle eşittir.

### Değişmez 5: Kuruş ↔ TL Çift Yönlü Dönüşüm Değişmezi
$$\text{TL} = \frac{\text{cents}}{100.0} \quad \iff \quad \text{cents} = \text{round}(\text{TL} \times 100)$$
- Core Next ile legacy arasındaki veri geçişlerinde kuruş/TL dönüşümleri deterministiktir.

---

## 2. DOĞRULANAN SENARYOLAR VE MATEMATİKSEL KANITLAR

### 2.1. İade Idempotency Senaryosu (100 TL Satış, 40 TL İade)
- **Orijinal Satış:** `total_amount = 100.0 TL`
- **1. İade:** `40.0 TL`
  - `refunded_amount = 40.0 TL`
  - `kalan_tutar = 60.0 TL`
  - `status = 'partially_refunded'`
- **Rollback 1. Çalıştırma:** Legacy'de `refunded_amount = 40.0 TL`.
- **Rollback 2. Çalıştırma (Retry):** Legacy'de `refunded_amount = 40.0 TL` (**EŞLEŞTİ, ÇİFTLENMEDİ**).

### 2.2. Çoklu Ödeme Roundtrip Senaryoları (7 Kombinasyon)

| Kombinasyon | Satış Tutarı | Ödeme Dağılımı | Reverse Migration (Legacy) | Forward Migration (Core Next) | Sapma (Fark) |
|---|---|---|---|---|---|
| **Yalnız Nakit** | 100.00 TL | 100.00 TL Nakit | 100.00 TL (cash) | 10.000 cents (cash) | **0.00 TL** |
| **Yalnız Kart** | 200.00 TL | 200.00 TL Kart | 200.00 TL (creditCard) | 20.000 cents (creditCard) | **0.00 TL** |
| **Yalnız Vadeli** | 300.00 TL | 300.00 TL Vadeli | 300.00 TL (onAccount) | 30.000 cents (onAccount) | **0.00 TL** |
| **Nakit + Kart** | 200.00 TL | 100 TL Nakit + 100 TL Kart | 100 TL cash + 100 TL card | 10.000 cash + 10.000 card | **0.00 TL** |
| **Nakit + Vadeli** | 250.00 TL | 150 TL Nakit + 100 TL Vadeli | 150 TL cash + 100 TL debt | 15.000 cash + 10.000 debt | **0.00 TL** |
| **Kart + Vadeli** | 200.00 TL | 120 TL Kart + 80 TL Vadeli | 120 TL card + 80 TL debt | 12.000 card + 8.000 debt | **0.00 TL** |
| **Nakit + Kart + Vadeli** | 200.00 TL | 50 TL Nakit + 70 TL Kart + 80 TL Vadeli | 50 cash + 70 card + 80 debt | 5.000 cash + 7.000 card + 8.000 debt | **0.00 TL** |

---

## 3. SONUÇ
Tüm finansal değişmezler kuruş ve TL düzeyinde sıfır hata ile korunmaktadır.
