# SERENUT OS — STAGE 10.12.36
## Reverse Migration Çakışma Güvenliği, Finansal Mutabakat ve Veri Koruma Denetim Raporu

**Tarih:** 19 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Branch:** `main`  
**HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Aşama Durumu:** `PASS — Çakışma güvenliği ve veri bütünlüğü izole testlerde kanıtlandı.`

---

## 1. Git Durumu ve Dosya Değişiklikleri

### 1.1 Git Kontrolleri
- **`git rev-parse HEAD`**: `28c158d88028f139e93f78982d4651ad424c61d2`
- **`git branch --show-current`**: `main`
- **`git diff --check`**: Temiz (0 sözdizimi / whitespace hatası).
- **`git diff --stat`**: 22 dosya (1167 ekleme, 259 silme — önceki aşamalardan gelen çalışma kopyası korundu).
- **Untracked Dizinler**: Kullanıcıya ait `core_next/` ve `test/core_next/` dizinleri kesinlikle `git add` edilmemiştir; untracked durumları raporlanmıştır.

---

## 2. Reverse Migration Akışının Gerçek Kod Açıklaması

Ters uzlaştırma motoru `ReverseMigrationEngine.rollbackToLegacy()` fonksiyonu (`core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart`) üzerinde incelenmiştir.

### 2.1 Önceki Tehlikeli Tasarım (Blind Overwrite Defect)
Stage 10.12.35 öncesinde, `products` ve `customers` tabloları Core Next'teki tüm satırlar taranarak körlemesine Legacy DB üzerine `UPDATE` ediliyordu:
```dart
// ESKİ KOD: Tehlikeli körlemesine ezme!
for (final cp in coreProducts) {
  await txn.rawUpdate(
    'UPDATE products SET quantity = ? WHERE id = ?',
    [cp['stock_quantity'], cp['id']],
  );
}
```
**Risk:** Core Next'te satış yapılırken (örn: stok 100 -> 95), Legacy DB'de bağımsız bir stok sayımı veya mal kabul yapılmışsa (örn: stok 98 olmuşsa), bu kör güncelleme 98 değerini silip 95 yapıyordu; aradaki 3 adetlik gerçek legacy işlem sessizce yok oluyordu.

### 2.2 Düzeltilen Delta ve Çakışma Güvenliği Mimarisi (Conflict-Safe Reconciliation)
Kod refactor edilerek **işlem bazlı delta doğrulama (delta aggregation & baseline matching)** mekanizması getirilmiştir:
1. **Yalnızca Etkilenen Kayıtlar**: Sadece Core Next'te yeni gerçekleşen `newSales` ve `refunds` içerisindeki ürünler ve müşteriler belirlenir. Dokunulmayan ürün veya müşteriler Legacy DB'de asla güncellenmez.
2. **Delta Hesaplama**:
   - `productDeltas[productId]`: Yeni satış ve iadelerden kaynaklanan toplam net miktar etkisi hesaplanır (örn: 5 adet satılmışsa delta = -5.0).
   - `customerDeltasCents[customerId]`: Core Next vadeli satışlarından veya defter kayıtlarından kaynaklanan net borç değişimi hesaplanır (örn: -250.00 TL borçlanma).
3. **Legacy Baseline Doğrulaması**:
   - Sistem, Core Next'teki mevcut stok değerinden bu deltayı çıkararak beklenen başlangıç seviyesini bulur:  
     `expectedLegacyBaseline = coreStock - delta` (Örn: 95 - (-5) = 100).
   - Legacy DB'deki mevcut değer okunur (`legacyStock`).
   - Eğer `(legacyStock - expectedLegacyBaseline).abs() > 0.001` ise, Legacy DB'de bağımsız harici bir değişiklik (örn. stok 98) olduğu matematiksel olarak kanıtlanır.
4. **Fail-Closed Durdurma ve Atomik Rollback**:
   - Çakışma durumunda sistem `StateError('STOK ÇAKIŞMASI TESPİT EDİLDİ...')` veya `StateError('MÜŞTERİ BAKİYE ÇAKIŞMASI TESPİT EDİLDİ...')` fırlatır.
   - Tüm işlem tek bir SQLite `transaction` bloğu içerisinde çalıştığı için, o ana kadar aktarılmış olan tüm satış, ödeme ve iade kayıtları otomatik olarak **ROLLBACK** edilir. Legacy DB hiçbir veri kaybı olmadan temiz kalır.
5. **Normal Akışta Değişikliğin Uygulanması**:
   - Baseline tutarlı ise (`legacyStock == 100`), Legacy stok güvenle `legacyStock + delta` (100 - 5 = 95) olarak güncellenir.

---

## 3. Her Tablonun Aktarım Kapsamı

| Tablo | Kaynak DB Seçimi | Hedef DB Alan Eşleşmesi | Kısıtlar ve İlişkisel Bütünlük | İkinci Çalıştırma (Idempotency) |
| :--- | :--- | :--- | :--- | :--- |
| `sales` | `created_at > lastLegacyCutoff` | `id`, `receipt_no`, `total_cents`, `paid_cents`, `created_at` | PRIMARY KEY (`id`), FOREIGN KEY yok. | `INSERT OR IGNORE` ile atlanır; mükerrer kayıt oluşmaz. |
| `sale_items` | `sale_id IN (newSales)` | `id`, `sale_id`, `product_id`, `quantity`, `total_cents` | PRIMARY KEY (`id`), FK `sales.id` | `INSERT OR IGNORE` ile korunur. |
| `sale_payments` | `sale_id IN (newSales)` | `id`, `sale_id`, `payment_type`, `amount_cents` | PRIMARY KEY (`id`), FK `sales.id` | `INSERT OR IGNORE` ile korunur. |
| `refunds` | `created_at > lastLegacyCutoff` | `id`, `sale_id`, `total_cents`, `created_at` | PRIMARY KEY (`id`) | `INSERT OR IGNORE` ile korunur. |
| `customer_transactions` | Cari/Vadeli satışlar & tahsilatlar | `id`, `customer_id`, `amount_cents`, `type` | PRIMARY KEY (`id`), FK `customers.id` | `INSERT OR IGNORE` ile korunur. |
| `products` | **Yalnızca yeni satışta geçen ürünler** | `quantity = legacyQuantity + delta` | Baseline farkı varsa **ABORT / ROLLBACK**. Dokunulmayan ürünler ellenmez. | Delta = 0 olacağı için ikinci çalıştırmada stok tekrar düşmez. |
| `customers` | **Yalnızca yeni vadeli satışta geçen müşteriler** | `balance = legacyBalance + delta` | Baseline farkı varsa **ABORT / ROLLBACK**. Dokunulmayan müşteriler ellenmez. | İkinci çalıştırmada bakiye tekrar değişmez. |

---

## 4. Stok ve Bakiye Çakışma Testleri (Kanıtlar)

Yalnızca geçici (disposable) SQLite DB'leri kullanılarak yürütülen testler:

### 4.1 Stok Çakışma Testi (Test 2.1)
- **Koşul:** Legacy stok `100`, bağımsız olarak `98`'e düşürülmüş. Core Next'te 5 adet satış yapılarak Core Next stok `95` olmuş.
- **Sonuç:** `ReverseMigrationEngine.rollbackToLegacy()` çalıştırıldığında çakışmayı tespit etti:
  `STOK ÇAKIŞMASI TESPİT EDİLDİ [prod-conflict-1]: Legacy stok (98.0) ile Core Next beklenen baseline (100.0) uyuşmuyor! Bağımsız harici değişiklik ezilemez.`
- **Bütünlük Doğrulaması:** SQLite transaction tamamen rollback edildi. Legacy stok `98.0` olarak korundu, Core Next satışı legacy `sales` tablosuna körlemesine sokulmadı.

### 4.2 Müşteri Bakiyesi Çakışma Testi (Test 2.2)
- **Koşul:** Legacy müşteri bakiyesi `-500.00 TL`. Legacy DB'de bağımsız 100 TL tahsilat girilerek bakiye `-400.00 TL` yapılmış. Core Next'te ise 250 TL vadeli satış yapılarak Core Next bakiyesi `-750.00 TL` olmuş.
- **Sonuç:** Motor çakışmayı anında yakaladı:
  `MÜŞTERİ BAKİYE ÇAKIŞMASI TESPİT EDİLDİ [cust-conflict-1]: Legacy bakiye (-40000 sent) ile Core Next beklenen baseline (-50000 sent) uyuşmuyor!`
- **Bütünlük Doğrulaması:** Transaction rollback oldu, Legacy müşteri bakiyesi `-400.00 TL` olarak korundu.

### 4.3 Dokunulmamış Ürün Koruması (Test 2.4)
- Core Next'te satış yapılmayan diğer ürünlerin Legacy DB'deki stokları zerre kadar değişmedi.

---

## 5. Satış, Ödeme, İade ve Stok Mutabakatı

### 5.1 Nakit, Kart, Vadeli ve Karma Ödeme Aktarımı
`test/core_next/stage10_12_34_transaction_recovery_test.dart` (Bölüm 3.1 & 3.2):
- Nakit satış: Satış başlığı, kalemler, nakit ödeme kaydı ve stok düşümü eksiksiz aktarıldı.
- Kart ve Karma ödeme: `sale_payments` tablosuna parçalı tutarlar (örn: 60 TL Kart, 40 TL Nakit) kuruşu kuruşuna aktarıldı.
- Vadeli ödeme: `customer_transactions` tablosuna cari borç hareketi olarak kaydedildi.

### 5.2 Satış İadesi (Refund) ve Ters Stok Hareketi
`test/core_next/stage10_12_34_transaction_recovery_test.dart` (Bölüm 3.3):
- Core Next'teki `refunds` kaydı Legacy `refunds` tablosuna orijinal `sale_id` ile bağlandı.
- İade edilen miktar stoklara geri eklendi.

---

## 6. Atomiklik ve İdempotency Sonuçları

### 6.1 Atomiklik (Transaction Rollback Garantisi)
- **Test 3.5 (Stage 34) & Test 2.1 (Stage 36):** Uzlaştırma ortasında hata veya çakışma oluştuğunda (`sqflite` transaction rollback mekanizması devreye girer):
  - Legacy DB'de yarım satış kalmaz (`COUNT(*) = 0`).
  - Ödeme kaydı veya kalem kalmaz.
  - Stok veya bakiye değişiklikleri tamamen geri alınır.

### 6.2 İdempotency (Tekrarlanan Çalıştırma)
- **Test 3.1 (Stage 36):**
  - 1. Çalıştırma: 1 satış aktarıldı, 1 ürün stoku güncellendi (`salesExported: 1, productsUpdated: 1`).
  - 2. Çalıştırma: 0 satış aktarıldı, 0 ürün güncellendi (`salesExported: 0, productsUpdated: 0`).
  - `sales`, `sale_items`, `sale_payments`, `products` tablolarında mükerrer tek bir kayıt oluşmadı.

### 6.3 Routing Rollback Güvenlik Kapısı
- **Test 3.2 (Stage 36):**
  - Hedef DB'de uzlaştırılmamış yeni işlem varken `DatabaseRoutingResolver.assertSafeRollback()` çağrıldığında sessiz geri dönüş engellendi ve `UnsafeRollbackException` fırlatıldı.

---

## 7. Test Adları ve Gerçek Komut Çıktıları

### 7.1 Stage 10.12.36 Özel Çakışma ve Bütünlük Testleri
**Komut:** `flutter test test/core_next/stage10_12_36_conflict_safe_reconciliation_test.dart`
```text
00:00 +0: STAGE 10.12.36 — BÖLÜM 1: GÜVENLİK KAPISI VE DEĞİŞMEZLİK 1.1: Satış motoru ve routing hook varsayılan olarak kapalıdır
00:00 +1: STAGE 10.12.36 — BÖLÜM 1: GÜVENLİK KAPISI VE DEĞİŞMEZLİK 1.2: Kaynak arşiv fixture dosyası mevcuttur
00:00 +2: STAGE 10.12.36 — BÖLÜM 2: STOK VE BAKİYE ÇAKIŞMASI DENETİMİ 2.1: Legacy stok bağımsız değişmişse (100 -> 98), 5 adet satan Core Next (95) körlemesine üzerine yazamaz, durdurulur
00:00 +3: STAGE 10.12.36 — BÖLÜM 2: STOK VE BAKİYE ÇAKIŞMASI DENETİMİ 2.2: Legacy carisine bağımsız tahsilat girilmişse (-500 -> -400), vadeli Core Next satışı (-750) bakiye farkını ezemez
00:01 +4: STAGE 10.12.36 — BÖLÜM 2: STOK VE BAKİYE ÇAKIŞMASI DENETİMİ 2.3: Legacy DB değişmemişse Core Next satış etkisi (100 -> 95) kayıpsız uygulanır
00:01 +5: STAGE 10.12.36 — BÖLÜM 2: STOK VE BAKİYE ÇAKIŞMASI DENETİMİ 2.4: Core Next satışında yer almayan legacy ürünlerin stoku asla değiştirilmez
00:01 +6: STAGE 10.12.36 — BÖLÜM 3: İLİŞKİSEL BÜTÜNLÜK VE İDEMPOTENCY 3.1: Başarılı ters uzlaştırma ikinci kez çalıştırıldığında hiçbir tabloda mükerrer satır oluşmaz
00:02 +7: STAGE 10.12.36 — BÖLÜM 3: İLİŞKİSEL BÜTÜNLÜK VE İDEMPOTENCY 3.2: Aktarım tamamlanmadan routing legacyye çevrilemez
00:02 +8: All tests passed!
```

### 7.2 Stage 10.12.34 Transaction Recovery Testleri
**Komut:** `flutter test test/core_next/stage10_12_34_transaction_recovery_test.dart`
```text
00:25 +13: All tests passed! (13/13 test başarılı)
```

### 7.3 Stage 10.12.33 Dual Database Routing & Rollback Testleri
**Komut:** `flutter test test/core_next/stage10_12_33_database_routing_rollback_test.dart`
```text
00:07 +18: All tests passed! (18/18 test başarılı)
```

### 7.4 Flutter Statik Kod Analizi
**Komut:** `flutter analyze test/core_next/stage10_12_36_conflict_safe_reconciliation_test.dart test/core_next/stage10_12_34_transaction_recovery_test.dart core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart`
```text
Analyzing 3 items...                                            
No issues found! (ran in 6.7s)
```

---

## 8. Düzeltilen Sorunlar ve Değişen Dosyalar

1. **`core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart`**:
   - `rollbackToLegacy()` fonksiyonundaki körlemesine `products` ve `customers` üzerine yazma (blind overwrite) döngüsü kaldırıldı.
   - Delta tabanlı baseline karşılaştırması ve çakışma fırlatan fail-closed mekanizma eklendi.
2. **`test/core_next/stage10_12_34_transaction_recovery_test.dart`**:
   - OneDrive kullanıcı yolu (`C:\Users\notop\OneDrive\...`) sabit kod bağımlılığı taşınabilir hale getirildi; CI ve diğer ortamlarda fixture dosyasını otomatik olarak kullanan güvenli fallback eklendi.
3. **`test/core_next/stage10_12_36_conflict_safe_reconciliation_test.dart`**:
   - Stage 10.12.36 gereksinimlerini doğrudan doğrulayan 8 adet kapsamlı test paketi eklendi.

---

## 9. Çözülemeyen Riskler ve Dikkat Edilmesi Gereken Noktalar

1. **İki Yönlü Eşzamanlı Yazma (Dual-Write) Mümkün Değildir**:
   - Cutover yapıldıktan sonra eski sistemde bağımsız manuel işlemler (fiziksel stok sayımı, harici fiş girişi) yapılırsa, ters uzlaştırma motoru çakışmayı tespit edip durduracaktır. Bu bir hata değil, veriyi ezilmekten koruyan bir emniyet kilididir.
   - Bu nedenle cutover anında eski istemcilerin yazma yetkisi kesinlikle kesilmelidir.
2. **Untracked Dizinler**:
   - `core_next/` ve `test/core_next/` dizinleri Git takibinde değildir. Bir sonraki aşamalarda sürüm kontrolüne dahil edilmek üzere kullanıcı onayına tabidir.

---

## 10. Canlı Veriye Dokunulmadığının Teyidi

Aşağıdaki güvenlik ilkelerine harfiyen uyulmuştur:
- `coreNextSalesEngineEnabledProvider = false` olarak kalmıştır.
- `DatabaseManager.databaseRoutingHook = null` olarak kalmıştır.
- `c:\Users\notop\AndroidStudioProjects\shaman_new\assets\db\nutopia.db` canlı referans dosyasının SHA-256 hash değeri değişmemiştir (`00259b5d2146ff9b...`).
- Çalışan Serenut OS sürecine (PID 7096) ve canlı veritabanı dosyalarına hiçbir müdahalede bulunulmamıştır.
- Tüm testler işletim sistemi geçici dizininde (`Temp/stage36_*`) disposable veritabanlarında çalıştırılmış ve temizlenmiştir.

---

## 11. Pilot İçin Kalan Engeller

1. Canlı pilot başlatılmadan önce, kullanıcı UI üzerinden onay kutusu ve bilgilendirme adımlarını tamamlamalıdır.
2. `core_next/` dosyalarının Git reposunda resmi bir dalda izlenmeye alınması önerilir.
3. `coreNextSalesEngineEnabledProvider = false` ve `DatabaseManager.databaseRoutingHook = null` koruması bilinçli operasyonel karar verilene kadar açık kalmalıdır.

---

## Sonuç

**PASS — Çakışma güvenliği ve veri bütünlüğü izole testlerde kanıtlandı.**

*(Canlı pilot başlatılmamış, routing değiştirilmemiş, satış motoru açılmamış ve release yayımlanmamıştır.)*
