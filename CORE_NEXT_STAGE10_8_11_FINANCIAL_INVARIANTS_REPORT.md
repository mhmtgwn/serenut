# SERENUT OS — STAGE 10.8.11 FINANCIAL INVARIANTS REPORT
## Finansal Değişmezler, Kuruş Hassasiyeti ve Çift Taraflı Defter Mutabakat Raporu

**Tarih:** 2026-10-15  
**Kapsam:** Tamsayı Kuruş Modeli, Parçalı/Karma Ödemeler, İade Idempotency, Veresiye Muhasebe Defteri ve Kayan Nokta Hassasiyeti.

---

## 1. TEMEL FİNANSAL DEĞİŞMEZLER (FINANCIAL INVARIANTS)

Core Next mimarisinde kayan noktalı sayı (`double`) yuvarlama hataları tamamen elenmiş, kuruş bazlı tamsayı modeli (`int` cents) zorunlu kılınmıştır.

### Değişmez 1: Satış Toplamı Dengesi
$$\text{total\_cents} = \text{subtotal\_cents} - \text{discount\_cents}$$
Her satış işleminde `total_cents` değeri indirim düşüldükten sonraki net tutardır. Hiçbir koşulda `total_cents <= 0` olamaz.

### Değişmez 2: Ödeme ve Borç Denkliği
$$\text{total\_cents} = \text{paid\_cents} + \text{debt\_cents}$$
- Nakit ve kredi kartı satışlarında `paid_cents = total_cents` ve `debt_cents = 0` olmalıdır.
- Veresiye satışlarda `debt_cents = total_cents` ve `paid_cents = 0` olmalıdır.
- Karma ödemelerde `paid_cents = \sum (\text{split.amount})` ve `\text{debt\_cents} = \text{total\_cents} - \text{paid\_cents}` eşitliği kuruşu kuruşuna sağlanır.

### Değişmez 3: Kayan Nokta Dönüşümünde Determinizm
Eski arayüzden veya API'den gelen `double` değerler `(amount * 100).round()` yöntemiyle kuruşa çevrilir:
- Örnek: `33.33 TL -> 3333 kuruş`
- Örnek: `33.34 TL -> 3334 kuruş`
- Toplam: `3333 + 3333 + 3334 = 10000 kuruş (100.00 TL)`
Test Senaryosu 18'de kuruş seviyesinde %100 mutabakat kanıtlanmıştır.

---

## 2. İADE DENETİMİ VE MİKTAR AŞIM ENGELİ (REFUND INVARIANTS)

1. **Miktar Aşım Engeli:**
   İade edilmek istenen ürün adedi, orijinal satıştaki ürün adedinden daha önce yapılmış iadelerin toplamı düşüldükten sonra kalan adedi aşamaz:
   $$\text{refund\_qty} \le \text{original\_qty} - \text{previously\_refunded\_qty}$$
2. **Finansal Tutar Aşım Engeli:**
   İade toplamı, orijinal satışın toplam tutarını (`total_cents`) aşamaz.
3. **İdempotency Koruması:**
   Aynı `idempotencyKey` ile gelen iade isteği tekrar çalıştırıldığında:
   - Yeni bir iade kaydı oluşturulmaz.
   - Stok adedi ikinci kez artırılmaz.
   - Müşteri alacağı ikinci kez işletilmez.
   - Önceki iade sonucu deterministik olarak geri döndürülür.
   (Test Senaryosu 7 ile kanıtlanmıştır: 8 adetten 1 adet iade edildiğinde stok 9 olur, aynı istek tekrarlandığında stok 9 kalır).

---

## 3. MÜŞTERİ CARİ HESABI VE LEDGER MUTABAKATI

1. **İşaret Kuralı (Accounting Sign Convention):**
   - Müşterinin dükkana borcu olması durumu: $\text{balance\_cents} < 0$ (Negatif bakiye = Müşteri borçlu).
   - Müşterinin alacaklı olması (veya iade/avans durumu): $\text{balance\_cents} > 0$.
   - Bakiyesiz durum: $\text{balance\_cents} = 0$.
2. **Veresiye Satışın Etkisi:**
   Veresiye satış yapıldığında müşterinin borcu artar; `balance_cents = balance_cents - sale.debt_cents`.
3. **Tahsilatın Etkisi:**
   Tahsilat yapıldığında müşterinin borcu azalır; `balance_cents = balance_cents + collection.amount_cents`.
4. **Trigger'sız Doğrudan SQL Güncellemesi:**
   SQLite trigger karmaşası ve özyinelemeli tetikleme riskleri kaldırılmış, `CoreNextFinancialTransactionRepository` ve `CoreCheckoutUseCase` doğrudan atomik transaction ile mutabakat sağlamaktadır.

---

## 4. BAĞIMSIZ TEST KANITLARI

| Test Senaryosu | Doğrulanan Kural | Beklenen Sonuç | Gerçek Çıktı |
|---|---|---|---|
| **Senaryo 7** | Kısmi İade & Idempotency | Stok 8 -> 9, tekrar çağrıda stok = 9 | PASS (Stok = 9) |
| **Senaryo 8** | İdempotent Tahsilat | 150 TL borçtan 50 TL tahsilat: 100 TL borç kalır. Tekrar çağrıda bakiye değişmez. | PASS (Bakiye = -10000 kuruş) |
| **Senaryo 9** | Çift Yönlü Defter Dengesi | 100 TL borç + 40 TL tahsilat = -60 TL bakiye | PASS (Bakiye = -6000 kuruş) |
| **Senaryo 18** | Karma Ödeme Kuruş Mutabakatı | 33.33 + 33.33 + 33.34 = 100.00 TL | PASS (10000 kuruş, 0 sapma) |
