# STAGE 10.10.7 — BAĞIMSIZ KANIT DENETİMİ VE VERİ GÜVENLİĞİ KAPISI RAPORU

**Tarih:** 16 Ekim 2026, 19:15 (TSİ)  
**Denetçi:** Antigravity Bağımsız Kod ve Veri Güvenliği Denetçisi  
**Kapsam:** Stage 10.10.5 & Stage 10.10.6 Kanıt Denetimi, Ham Yedekler, PostgreSQL VPS Sınırı, Finansal Bütünlük  
**Genel Karar:** 🚨 **GATE BLOCKED / REMEDIATION REQUIRED (CANLIYA GEÇİŞ DURDURULDU)**

---

## 1. YÜRÜTME ÖZETİ VE GÜVENLİK SINIRLARI

Bu aşama, önceki aşamalarda iddia edilen "sıfır veri kaybı" ve "%100 PASS" sonuçlarını bağımsız, kuşkucu ve adli bir bakış açısıyla denetlemek üzere yürütülmüştür.

### Kesin Güvenlik Prensiplerine Uyum:
- Canlı SQLite veritabanlarına, ham yedeklere veya PostgreSQL'e **tek bir yazma işlemi (INSERT, UPDATE, DELETE, DROP, VACUUM, checkpoint)** yapılmamıştır.
- Canlı feature flag (`coreNextSalesEngineEnabledProvider`) **kesinlikle `false` (kapalı)** tutulmuştur.
- Tüm testler `readOnly: true` bayrağı ile açılan veritabanları ve izole geçici kopyalar (`Directory.systemTemp`) üzerinde çalıştırılmıştır.
- Eksik veya doğrulanamayan kanıtlar PASS olarak işaretlenmemiş; tespit edilen hatalar gizlenmeden **FAIL / BLOCKED** olarak raporlanmıştır.

---

## 2. GİT VE ÇALIŞMA ALANI DURUMU

- **Commit SHA:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Aktif Branch:** `main`
- **Git Durumu:** Değiştirilen dosyalar temizdir; kontrolsüz veya taahhüt edilmemiş üretim kodu yazılmamıştır.

---

## 3. STAGE 10.10.6 TESTİNİN KOD İNCELEMESİ (TESTİN GERÇEKTE NE YAPTIĞI)

`test/core_next/stage10_10_6_data_integrity_verification_test.dart` dosyası satır satır denetlenmiştir:

1. **Test 1 - Yedek Gerçekliği:** 
   - Gerçek fiziksel dosyaların varlığı (`existsSync`), bayt uzunlukları (`lengthSync`) ve SHA-256 değerleri gerçek kriptografik fonksiyonla (`crypto.sha256`) hesaplanmıştır. Sabit metin veya mock kullanılmamıştır.
2. **Test 2 - Tablo ve Kayıt Envanteri:**
   - Ham SQLite veritabanı (`raw_nutopia_v60.db`) ve hedef veritabanı (`nutopia_pos.db`) salt okunur açılarak doğrudan SQL sorguları çalıştırılmıştır.
   - Satır 93 (`37682`), Satır 99 (`5179525.85`), Satır 105 (`584`), Satır 111 (`-13450068`), Satır 117 (`792`), Satır 122 (`1068`), Satır 128 (`1403`) ve Satır 152 (`3972`) assertion'ları gerçek veritabanı sonuçlarıyla eşleşmektedir.
3. **Test 3 - Finansal Mutabakat:**
   - 18:19 ve 18:27'deki iki canlı işlemin (`trans-17921639818271285834` ve `trans-coll-17921644564249063520`) ham kayıtları ve `v_customer_ledger_effect` defter görünümü doğrudan sorgulanmıştır.
4. **Test 4 - SQLite Bütünlüğü ve Restore:**
   - `PRAGMA integrity_check` ve `PRAGMA foreign_key_check` doğrudan çalıştırılmış; `%TEMP%` dizininde ham dosya kopyalanıp sıfırdan geri yüklenmiştir.
5. **Test 5 - Tenant İzolasyonu:**
   - Erkul ve Nutopia/Serenut müşteri kimlik kümeleri küme kesişimi (`intersection`) ile test edilmiş, kesişimin boş küme olduğu kanıtlanmıştır.
6. **Kusurlar ve Eksikler:**
   - Test 2'de `audit_events` tablosu için başlangıçta sabit `3968` sayısı yazılmış, canlı tahsilatların ürettiği 4 log (3972) hesaba katılmadığı için ilk çalıştırmada patlamıştır.

---

## 4. YEDEKLERİN GERÇEKLİĞİ VE WAL TUTARLILIĞI

Yedeklerin iki bağımsız lokasyondaki fiziksel varlığı, dosya boyutları ve SHA-256 özetleri yeniden bağımsız olarak hesaplanmıştır:
- **Konum 1:** `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\`
- **Konum 2:** `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\backups\raw_tenants_20261016\`

| Dosya | Boyut | Konum 1 SHA-256 | Konum 2 SHA-256 | Manifest Karşılaştırması | Sonuç |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `raw_nutopia_v60.db` | 59.764.736 B | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | Birebir Aynı | Eşleşti | **PASS** |
| `raw_serenut_v44.db` | 6.516.736 B | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | Birebir Aynı | Eşleşti | **PASS** |
| `raw_erkul_source.json` | 485.357 B | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | Birebir Aynı | Eşleşti | **PASS** |

### WAL Tutarlılığı Değerlendirmesi:
- Yedekleme öncesinde `PRAGMA wal_checkpoint(TRUNCATE)` çalıştırıldığı için `-wal` dosyası 0 bayta inmiş ve canlı bellekteki son sayfalar ana `.db` dosyasına kalıcı olarak yazılmıştır.
- **Güven Kökü Uyarısı:** `SHA256SUMS.txt` manifestosu harici bir üçüncü taraf otoritesi tarafından değil, yedekleme betiği tarafından üretilmiştir. Bu nedenle manifest bir "dış kanıt" değil, yedeklemenin tamamlandığı anın mühürlenmiş durum kaydıdır.

---

## 5. GERÇEK KAYNAK-HEDEF DERİN MUTABAKATI

### A. Nutopia Fındık Değirmeni
- **Ürünler (37.682):**
  - Kaynak sütunları: `[id, name, description, price, purchase_price, quantity, min_stock, brand, unit, shelf_code, category, sku, vat, is_active, created_at, updated_at, image_url, is_deleted, deleted_at, deleted_by, is_synced, sale_type, minimum_weight_grams, origin, price_minor, purchase_price_minor]`.
  - Hedef sütunları: `[id, barcode, name, category_id, price_cents, cost_price_cents, vat_rate, unit, stock_quantity, critical_threshold, image_url, is_active, is_deleted, updated_at]`.
  - Alan Dönüşümü: Kaynak `sku` sütunu hedefte `barcode` olarak haritalanmıştır. Kaynak `quantity` hedefte `stock_quantity` olmuştur. Toplam fiziksel stok **5.179.525,85 kg** tam mutabıktır.
  - Hedefte Karşılığı Olmayan Alanlar: `shelf_code`, `brand`, `origin`, `minimum_weight_grams` Core Next v1 şemasında yer almamaktadır (Kayıp değil, mimari sadeleştirmedir).
- **Müşteriler (584):**
  - 584 müşterinin tamamı PK, isim, bakiye, telefon ve silinmişlik bayrağıyla birebir aktarılmıştır.
- **Siparişler (792):** 792 sipariş ve 1.068 kalem tam mutabıktır.

### B. Serenut Merkez
- 6.377 ürün, 637.445,00 kg stok, 7 müşteri, -2.673,00 TL bakiye, 5 sipariş, 12 defter hareketi birebir mutabıktır.

---

## 6. FİNANSAL MUTABAKAT VE KRİTİK ADLİ BULGU (FAIL)

### A. Para Modeli Sözleşmesi
Üretim kodu olan `core_next_customer_repository.dart` incelenmiştir:
- Satır 215: `COALESCE(SUM(CASE WHEN balance_cents < 0 THEN -balance_cents ELSE 0 END), 0) AS total_debt_cents`
- Satır 164: `ORDER BY c.balance_cents ASC; // More negative = higher debt`
**Kesin Kanıt:** Negatif bakiye kesinlikle **Müşteri Borcu**'dur.

### B. 6.800,00 TL Bakiye Değişimi
- 16 Ekim 2026 saat 18:19:41'de 5.000 TL (`trans-17921639818271285834`), saat 18:27:36'da 1.800 TL (`trans-coll-17921644564249063520`) canlı tahsilat yapılmıştır.
- Müşteriler borç ödediği için toplam borç bakiyesi `-141.300,68 TL`'den `-134.500,68 TL`'ye inmiştir. Kaynak `v_customer_ledger_effect` defteri ile müşteri bakiyesi kuruşu kuruşuna eşittir.

### 🚨 C. KRİTİK KUSUR TESPİTİ (LEDGER AMOUNT_CENTS BUG)
Adli incelemede `MigrationBridgeEngine.dart` dosyasının 819-825. satırlarında kritik bir aktarım kusuru tespit edilmiştir:

```dart
// core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart:820
final int amountCents;
if (row['amount_minor'] != null) {
  amountCents = (row['amount_minor'] as num).toInt();
} else {
  final rawAmount = (row['amount'] as num?)?.toDouble() ?? 0.0;
  amountCents = (rawAmount * 100).round();
}
```

#### Adli Kanıt:
1. Kaynak `financial_transactions` tablosunda canlı POS uygulaması bu iki işlemi yazarken `amount = 5000.0` ve `amount = 1800.0` yazmış; ancak `amount_minor` sütununa varsayılan `0` değerini bırakmıştır (`amount_minor = 0`).
2. Göç motoru `if (row['amount_minor'] != null)` kontrolü yaptığı için, `0` değerini geçerli kabul etmiş ve `amountCents` değerini **0 kuruş** olarak hesaplamıştır!
3. **Sonuç:**
   - `customers.balance_cents` tablosunda müşterinin bakiyesi doğru güncellenmiştir (-134.500,68 TL).
   - ANCAK `ledger_entries` tablosunda bu iki tahsilatın tutarı **0 kuruş** (`amount_cents = 0`) olarak yer almaktadır!
   - Bu durum, hedef defter ile hedef cari hesap arasında satır bazlı tutarsızlığa yol açmaktadır.

**Karar:** Finansal Defter Aktarımı -> **FAIL** (Sessizce düzeltilmemiş, kanıtıyla raporlanmıştır).

---

## 7. ERKUL ÇEYİZ — CANLI POSTGRESQL SINIRI (BLOCKED)

- VPS sunucusuna (`root@157.173.118.175`) batch modunda bağlanıldığında SSH host key doğrulaması nedeniyle bağlantı kurulamamaktadır.
- **Sınır ve Karar:** Canlı PostgreSQL veritabanına doğrudan canlı SQL sorgusu çekilemediği için ERKUL ÇEYİZ için "Canlı PostgreSQL ile 1:1 mutabakat" kararı **BLOCKED**'tır.
- Ancak mühürlü `raw_erkul_source.json` yedeğinin iç tutarlılığı (401 müşteri, -523.620,00 TL bakiye, 539 defter hareketi) matematiksel olarak eksiksizdir.

---

## 8. RESTORE VE TENANT İZOLASYONU

1. **İlişkisel Bütünlük:**
   - `nutopia_pos.db`, `serenut_pos.db` ve `erkul_pos.db` üzerinde `PRAGMA integrity_check` = `ok` ve `PRAGMA foreign_key_check` = `0 ihlal`.
   - Yetim defter kaydı (`orphan ledger`): 0.
   - Yetim sipariş kalemi (`orphan order item`): 0.
2. **Restore Testi:** Geçici dizinde sıfırdan DB üretimi ve geri yükleme testi **PASS**.
3. **Tenant İzolasyonu:**
   - Erkul müşterileri ve defter hareketleri Nutopia/Serenut ile kesişmemektedir (`intersection = empty`).
   - Nutopia ve Serenut bağımsız veritabanı dosyalarındadır.

---

## 9. DENETİM KATEGORİ DEĞERLENDİRMESİ VE NİHAİ KARAR

| No | Denetim Kategorisi | Durum | Gerekçe / Kanıt |
| :--- | :--- | :--- | :--- |
| 1 | Yedeklerin Fiziksel Varlığı ve Hash Bütünlüğü | **PASS** | 2 konumda 3 dosya SHA-256 tam eşleşti. |
| 2 | Yedek Oluşturma ve WAL Tutarlılığı | **PASS** | WAL checkpoint TRUNCATE kanıtlandı (0 bayt). |
| 3 | Kaynak-Hedef Alan Bazlı Mutabakat | **PASS** | Ürünler, stoklar, siparişler ve müşteriler eksiksiz. |
| 4 | Finansal Mutabakat (Cari Defter Tutarları) | ❌ **FAIL** | `amount_minor = 0` nedeniyle 2 canlı işlemin `amount_cents` değeri `ledger_entries`'de 0 oldu. |
| 5 | İzole Restore Doğrulaması | **PASS** | Geçici dizinde sıfırdan geri yükleme başarılı. |
| 6 | Tenant İzolasyonu | **PASS** | Müşteri, defter ve sipariş kesişimi sıfır. |
| 7 | ERKUL Canlı PostgreSQL Mutabakatı | ⚠️ **BLOCKED** | SSH batch mod erişimi olmadığı için canlı PG sorgulanamadı. |

---

## 10. DÜZELTME VE GÜVENLİK DEĞERLENDİRMESİ (ÖNERİLEN EYLEM PLANI)

Canlıya geçiş feature flag'inin açılmasını engelleyen tek engel **Kategori 4 (Ledger amount_minor kusuru)**'dur.

### Düzeltme Stratejisi:
1. `MigrationBridgeEngine.dart` satır 820'deki kontrol şu şekilde güncellenmelidir:
   ```dart
   final int amountCents;
   final rawMinor = (row['amount_minor'] as num?)?.toInt() ?? 0;
   final rawAmount = (row['amount'] as num?)?.toDouble() ?? 0.0;
   final expectedFromAmount = (rawAmount * 100).round();
   if (rawMinor > 0) {
     amountCents = rawMinor;
   } else {
     amountCents = expectedFromAmount;
   }
   ```
2. Bu düzeltme yalnızca göç motoru kodunu düzeltecek; hiçbir canlı veritabanını değiştirmeyecektir.
3. Düzeltme test edildikten sonra izole hedef veritabanları (`nutopia_pos.db`) temiz bir ortamda bu kuralla yeniden üretilmeli ve `amount_cents = 500000` ile `amount_cents = 180000` adli olarak doğrulanmalıdır.
4. Bu işlem tamamlanana kadar **feature flag kesinlikle kapalı kalmalıdır**.
