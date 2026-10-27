# CORE NEXT — STAGE 10.8.8 FINANCIAL & ROUNDTRIP RECONCILIATION REPORT
**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.8.8 — Finansal ve İade Roundtrip Karşıt Denetim Raporu  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Referans Test Dosyası:** [stage10_8_8_adversarial_verification_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_8_adversarial_verification_test.dart) (Test 2 & Test 3)

---

## 1. 7 Temel Ödeme Kombinasyonunun Sınanması

Stage 10.8.8 kapsamında Core Next üzerinde 7 farklı ödeme mimarisi izole SQLite ortamında oluşturulmuş ve mutabakatları sınanmıştır:

| No | Senaryo | Toplam Tutar | Ödeme Kalemleri Dağılımı (`sale_payments`) | $\sum$ Kalem = Toplam | Cari Defter Etkisi |
| :---: | :--- | :---: | :--- | :---: | :---: |
| 1 | **Yalnız Nakit** | 100.00 TL | Nakit: 100.00 TL (10000 kuruş) | ✅ Eşit | 0 TL |
| 2 | **Yalnız Kart** | 200.00 TL | Kredi Kartı: 200.00 TL (20000 kuruş) | ✅ Eşit | 0 TL |
| 3 | **Yalnız Vadeli** | 300.00 TL | Veresiye (`onAccount`): 300.00 TL (30000 kuruş) | ✅ Eşit | +300.00 TL Borç |
| 4 | **Nakit + Kart** | 200.00 TL | Nakit: 100.00 TL + Kart: 100.00 TL | ✅ Eşit | 0 TL |
| 5 | **Nakit + Vadeli** | 250.00 TL | Nakit: 150.00 TL + Veresiye: 100.00 TL | ✅ Eşit | +100.00 TL Borç |
| 6 | **Kart + Vadeli** | 200.00 TL | Kart: 120.00 TL + Veresiye: 80.00 TL | ✅ Eşit | +80.00 TL Borç |
| 7 | **Üçlü Karma** | 200.00 TL | Nakit: 50.00 TL + Kart: 70.00 TL + Veresiye: 80.00 TL | ✅ Eşit | +80.00 TL Borç |

Her senaryoda $\sum \text{Ödemeler} = \text{Satış Toplamı}$ matematiksel kuralı %100 doğrulanmıştır.

---

## 2. Adversarial Bulgu 1: Reverse -> Forward Roundtrip Ödeme Ayrışması

Core Next'ten Legacy'ye geri dönüş (Reverse Rollback) yapıldığında ve ardından bu legacy veritabanından tekrar Core Next'e ileri migrasyon (Forward Migration) çalıştırıldığında ne olacağı sınanmıştır.

### Adli Kanıt ([stage10_8_8_adversarial_verification_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_8_adversarial_verification_test.dart) Test 2)
1. **Başlangıç (Core Next):** Satış `s-cash-card` (200.00 TL):
   - Ödeme 1: `cash` (100.00 TL)
   - Ödeme 2: `creditCard` (100.00 TL)
2. **Reverse Rollback:**
   - Legacy `sales` tablosuna `payment_method = 'mixed'` ve `notes = 'Parçalı Ödeme Dağılımı: cash: 100.00 TL, creditCard: 100.00 TL'` yazıldı.
3. **Tekrar İleri Migration (Forward Roundtrip):**
   - `MigrationBridgeEngine.migrateFromLegacy` legacy `sales` tablosunu okudu.
   - `payment_method` alanının `'mixed'` olduğunu gördü.
   - `sale_payments` tablosuna **yalnızca 1 adet kayıt** ekledi:
     - `payment_type`: `'mixed'`
     - `amount_cents`: `20000` (200.00 TL)
4. **Sonuç (Kusur Analizi):**
   - Orijinalde 2 ayrı ödeme yöntemi (100 TL nakit ve 100 TL kart) bulunurken, döngüsel geçiş sonrasında nakit ve kart kırılımı tamamen yok olmakta; Core Next içinde tek bir `mixed` satırına çökmektedir.
   - **`sales.notes` Serbest Metin Analizi:** `sales.notes` sütunu yapısal bir veri tablosu değil, insan tarafından okunabilir serbest metindir. Migration motoru bu metni Regex ile ayrıştırmadığından (ve ayrıştırmaması doğru bir mimari ilke olduğundan), legacy şemada ayrı bir ödeme tablosu olmadığı sürece bu kayıp kaçınılmazdır.

---

## 3. Adversarial Bulgu 2 (CRITICAL): İade Rollback Çift Çalıştırmada `refunded_amount` İki Katına Çıkma Hatası (Doubling Defect)

Stage 10.8.7'de `ReverseMigrationEngine` içine eklenen iade aktarım kodu denetlenmiştir.

### Hatalı Kod Satırı
`core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart` (Satır 1003-1007):
```dart
if (legacySalesCols.contains('refunded_amount')) {
  await txn.rawUpdate(
    'UPDATE sales SET refunded_amount = refunded_amount + ?, updated_at = ? WHERE id = ?',
    [refundAmount, DateTime.now().toIso8601String(), origSaleId],
  );
}
```

### Karşıt Test Kanıtı ([stage10_8_8_adversarial_verification_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_8_adversarial_verification_test.dart) Test 3)
1. Legacy'de 100.00 TL'lik orijinal satış (`sale-orig-100`) oluşturuldu.
2. Core Next'te bu satış için 40.00 TL kısmi iade (`ref-part-40`) yapıldı.
3. **1. Reverse Rollback:**
   - Legacy `sales.refunded_amount` sütunu `0.0 + 40.0 = 40.0 TL` oldu. (Doğru)
4. **2. Reverse Rollback (İdempotency Denetimi):**
   - Aynı rollback ikinci kez çalıştırıldığında, yukarıdaki SQL sorgusu koşulsuz olarak tekrar çalıştı:
   - `refunded_amount = 40.0 + 40.0 = 80.0 TL` oldu!
5. **Kusurun Ciddiyeti:**
   - 40 TL'lik tek bir iade için legacy satış kaydında **80 TL iade edilmiş gibi gösterilmektedir**.
   - Üçüncü kez çalıştırılsa 120 TL olacaktır (orijinal satış tutarından bile fazla).
   - **Kök Neden:** `refunds` tablosuna `replace` ile yazılırken idempotent davranılmış; ancak `sales.refunded_amount` güncellemesi için "bu iade daha önce işlendi mi?" denetimi (idempotency guard) konulmamıştır.

---

## 4. Gerekli Çözüm (İade Idempotency Guard)

`ReverseMigrationEngine` içinde `refunded_amount` artırılmadan önce legacy `refunds` tablosunda o `saleId`'nin varlığı kontrol edilmelidir:

```dart
final existingRefund = await txn.query(
  'refunds',
  where: 'id = ?',
  whereArgs: [saleId],
);
final bool isNewRefund = existingRefund.isEmpty;

if (isNewRefund && legacySalesCols.contains('refunded_amount')) {
  await txn.rawUpdate(
    'UPDATE sales SET refunded_amount = refunded_amount + ?, updated_at = ? WHERE id = ?',
    [refundAmount, DateTime.now().toIso8601String(), origSaleId],
  );
}
```
Bu sayede rollback kaç kez çalıştırılırsa çalıştırılsın `refunded_amount` asla iki katına çıkmaz.
