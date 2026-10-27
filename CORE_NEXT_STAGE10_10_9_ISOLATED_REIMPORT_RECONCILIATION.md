# STAGE 10.10.9 — İZOLE YENİDEN AKTARIM, TAM FİNANSAL MUTABAKAT VE KABUL KAPISI RAPORU

**Tarih:** 2026-10-16  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Branch:** `main`  
**Güvenlik Protokolü:** Mutlak Koruma (Canlı DB'ler, AppData üretim DB'leri ve ham yedekler salt okunur tutulmuş, tüm göç `%TEMP%` altındaki izole sandbox dizininde yürütülmüştür)  
**Feature Flag:** `coreNextSalesEngineEnabledProvider = false` (KAPALI)

---

## 1. YÜRÜTME ÖZETİ VE KABUL KAPISI MATRİSİ

| Kategori / Denetim Alanı | Kapsam | Eşleşme Oranı | Sayısal Fark | Durum |
| :--- | :--- | :--- | :--- | :--- |
| **Nutopia Finansal Defter (Ledger)** | 1.403 Müşteri Hareketi | **%100** (1.403/1.403) | 0 fark | **PASS** |
| **Nutopia Genel Kasa Hareketleri** | 21 Müşterisiz Hareket | Belgelendi (Genel Kasa) | 0 kayıp | **PASS** |
| **Nutopia Canlı 6.800 TL Tahsilatı** | 2 İşlem (5.000 TL + 1.800 TL) | 500.000 kr + 180.000 kr | 0 kuruş fark | **PASS** |
| **Nutopia Müşteri Bakiyeleri** | 584 Müşteri | -134.500,68 TL (-13.450.068 kr) | 0 kuruş fark | **PASS** |
| **Nutopia Satışlar & Kalemleri** | 52 Satış, 120 Kalem | %100 1:1 Mutabık | 0 fark | **PASS** |
| **Nutopia Siparişler & Kalemleri** | 792 Sipariş, 1.068 Kalem | %100 1:1 Mutabık | 0 fark | **PASS** |
| **Nutopia Taksitler** | 2 Plan, 9 Taksit | %100 1:1 Mutabık | 0 fark | **PASS** |
| **Nutopia Tartılı/Ondalıklı Stok** | 37.682 Ürün | 5.179.525,85 Birim | 0 fark | **PASS** |
| **Serenut v44 Tam Göçü** | 6.377 Ürün, 7 Müşteri | -2.673,00 TL (-267.300 kr) | 0 fark | **PASS** |
| **ERKUL ÇEYİZ Doğrulanmış JSON Yedeği**| 401 Cari, 26 Ürün, 539 Defter| -523.620,00 TL (-52.362.000 kr)| 0 fark | **PASS** |
| **ERKUL ÇEYİZ Canlı PostgreSQL Erişimi**| Canlı DB Salt Okunur/Erişimsiz | Güvenlik kuralı gereği test edilmedi | N/A | **BLOCKED (BY DESIGN)** |
| **İdempotency (Tekrar Çalıştırma)** | 2. Göç Çalıştırması | %100 Mükerrersizlik (1.403 = 1.403)| 0 çift kayıt | **PASS** |
| **SQLite Bütünlüğü (PRAGMA)** | integrity_check / FK check | 0 ihlal | 0 hata | **PASS** |

---

## 2. İZOLE HEDEF VERİTABANLARININ YENİDEN OLUŞTURULMASI

Stage 10.10.8'de düzeltilen `MigrationBridgeEngine.resolveAmountCents` motoru kullanılarak, `%TEMP%\stage10_10_9_reconciliation_*` altında temiz sandbox veritabanları sıfırdan oluşturulmuştur:
- `nutopia_isolated_target.db` (Kaynak: `raw_nutopia_v60.db` geçici salt-okunur kopyası)
- `serenut_isolated_target.db` (Kaynak: `raw_serenut_v44.db` geçici salt-okunur kopyası)
- `erkul_isolated_target.db` (Kaynak: `raw_erkul_source.json` doğrudan JSON yüklemesi)

Mevcut AppData üretim veritabanlarına (`%APPDATA%\...\databases\core_next\*.db`) ve ham yedeklere hiçbir yazma işlemi yapılmamış; salt-okunurlukları korunmuştur.

---

## 3. NUTOPIA TÜM FİNANSAL HAREKETLERİN (1.424 KAYIT) DERİN ADLİ MUTABAKATI

Kaynak `raw_nutopia_v60.db` içerisindeki `financial_transactions` tablosundaki 1.424 kaydın tamamı taranmış ve hedef `ledger_entries` ile 1:1 karşılaştırılmıştır:

### 3.1 Kapsam ve Eşleşme Oranı
- **Kaynak Toplam `financial_transactions`:** 1.424
- **Müşteri İlişkili Hareketler (`customer_id` mevcut):** 1.403
- **Hedef `ledger_entries` Kayıt Sayısı:** 1.403
- **Birebir Eşleşen Kayıt Sayısı:** **1.403 / 1.403 (%100.00)**
- **Eşleşmeyen / Kayıp Müşteri Hareketi:** **0 (%0.00)**

### 3.2 Zorunlu Kategori Tasnifi ve Doğrulama
| Tutar / Kolon Grubu | Kayıt Sayısı | Eşleşme Oranı | Hedef Tutar Sözleşmesi | Sonuç |
| :--- | :--- | :--- | :--- | :--- |
| **a) `amount_minor` Pozitif** | 1.291 | %100 (1.291/1.291) | `amount_minor == (amount * 100)` tam eşit kuruş aktarımı | **PASS** |
| **b) `amount_minor` Sıfır** | 112 | %100 (112/112) | Unpopulated şema varsayılanı (v60 sonrası eklenen tahsilatlar); otoritatif `amount * 100` kuruş aktarımı | **PASS** |
| **c) `amount_minor` Null** | 0 | N/A | Şema `NOT NULL DEFAULT 0` olduğundan null kayıt bulunmamaktadır | **PASS** |
| **d) Negatif Tutarlı Hareketler** | 0 | N/A | Kaynakta negatif borç/alacak satırı yoktur; ters hareketler işlem tipiyle temsil edilmiştir | **PASS** |
| **e) `amount` ve `amount_minor` Çelişkili** | 0 | N/A | Sıfır harici non-zero uyuşmazlığı tespit edilmemiştir | **PASS** |
| **f) Meşru Sıfır Tutarlı Hareketler** | 2 | %100 (2/2) | `amount = 0.0` ve `amount_minor = 0` olan 2 sistem düzeltme kaydı hedefte `amount_cents = 0` olarak korunmuştur | **PASS** |

### 3.3 Canlı Tahsilat Örneklerinin Yeni İzole Hedefteki Durumu
Stage 10.10.7'de hatalı olarak 0 kuruş aktarılan ve Stage 10.10.8'de düzeltilen iki canlı kayıt, yeni izole hedef veritabanında doğrulanmıştır:
- `trans-17921639818271285834`:
  - Kaynak: `amount = 5000.0`, `amount_minor = 0`, `customer_id = cust-1768824151241`
  - Yeni İzole Hedef: **`amount_cents = 500000` (5.000 TL)**
- `trans-coll-17921644564249063520`:
  - Kaynak: `amount = 1800.0`, `amount_minor = 0`, `customer_id = cust-1768824151241`
  - Yeni İzole Hedef: **`amount_cents = 180000` (1.800 TL)**

### 3.4 21 Müşterisiz Genel Kasa Hareketinin Durumu
Kaynak tablodaki 21 kayıt `customer_id` alanı boş veya `NULL` olan genel kasa hareketleridir (tezgah peşin satışları / kasa açılış-kapanış nakit girişleri).
- Bu hareketler bir müşteri cari hesabına bağlı olmadığı için `ledger_entries` (müşteri cari defteri) tablosuna aktarılmamış; satış motorundaki genel kasa / satış kayıtlarında (`sales`) temsil edilmiştir.
- Müşteri cari bakiyelerine çift sayım (double-counting) etkisi yapması engellenmiştir.

---

## 4. DİĞER PARA VE STOK VERİLERİNİN MUTABAKATI

1. **Satışlar ve Ödeme Kalemleri:**
   - Toplam 52 satış kaydı.
   - Her satışın toplam, ödenen ve indirim tutarları `resolveAmountCents` fonksiyonu ile kuruş hassasiyetinde aktarılmıştır.
   - Parçalı ödemeler `sale_payments` tablosunda korunmuştur.
2. **Müşteri Bakiyeleri:**
   - Nutopia 584 müşterinin bakiye toplamı: **-134.500,68 TL (-13.450.068 kuruş)**.
   - Kaynak `customers` tablosundaki `SUM(ROUND(balance * 100))` ile hedef `customers.balance_cents` toplamı birebir eşittir.
   - Defter hareketlerindeki 6.800 TL'lik tahsilat bakiyeyi eksiksiz dengelemektedir.
3. **Siparişler ve Kalemleri:**
   - 792 sipariş ve 1.068 sipariş kalemi %100 kuruş ve miktar mutabakatıyla aktarılmıştır.
4. **Taksitler:**
   - 2 taksit planı (`customer_installment_plans`) ve 9 taksit satırı (`customer_installments`) eksiksiz korunmuştur.
5. **Stok Miktarları ve Tartılı Ürünler:**
   - Toplam ürün sayısı: 37.682.
   - Toplam stok: **5.179.525,85 birim**.
   - Kesirli/tartılı (ondalıklı kg/gram) ürünlerdeki hassasiyet kayıpsız korunmuştur.

---

## 5. SERENUT VE ERKUL ÇEYİZ MUTABAKATI

1. **Serenut (Merkez) — v44 Şeması:**
   - Ürünler: 6.377 adet (Toplam stok: 637.445 birim).
   - Müşteriler: 7 adet.
   - Bakiye Toplamı: **-2.673,00 TL (-267.300 kuruş)**.
   - Satış / Defter: 0 adet.
   - Tüm alanlar %100 mutabık.
2. **ERKUL ÇEYİZ — PostgreSQL JSON Dışa Aktarımı:**
   - 401 müşteri, 26 ürün, 5 satış, 539 defter kaydı, 1 sipariş.
   - Bakiye Toplamı: **-523.620,00 TL (-52.362.000 kuruş)**.
   - Canlı PostgreSQL erişimi kısıtı: Güvenlik protokolü gereği bu aşamada canlı PostgreSQL'e bağlantı açılmamış, doğrulanmış ve kriptografik hash'i sabit JSON yedeği üzerinden mutabakat sağlanmıştır. Canlı PostgreSQL mutabakatı **BLOCKED (BY DESIGN)** statüsünde tutulmaktadır.
3. **Tenant İzolasyonu:**
   - Üç işletmenin müşteri ve hareket kimlik kümeleri arasında kesişim `boş küme` (0 sızıntı) olarak doğrulanmıştır.

---

## 6. TEKRAR ÇALIŞTIRMA (IDEMPOTENCY), INTEGRITY VE ROLLBACK

1. **İdempotency:**
   - Göç motoru aynı hedef veritabanı üzerinde 2. kez çalıştırıldığında `ConflictAlgorithm.ignore` ve ID koruması sayesinde 0 mükerrer kayıt oluşmuş; toplam defter sayısı 1.403 ve bakiye -13.450.068 kuruş olarak sabit kalmıştır.
2. **SQLite PRAGMA Bütünlüğü:**
   - `PRAGMA integrity_check = ok`
   - `PRAGMA foreign_key_check = 0 ihlal`
3. **İşlem Bütünlüğü ve Rollback:**
   - Hata anında `transaction` rollback güvencesi doğrulanmıştır.

---

## 7. ÇALIŞTIRILAN TÜM TESTLER VE GERÇEK KONSOL ÇIKTILARI

Bu aşamada 5 bağımsız test paketi uçtan uca çalıştırılmış ve tamamı 0 hata ile geçmiştir:

1. `test/core_next/stage10_10_9_full_reconciliation_test.dart`:
   - **`All tests passed! (4/4 test grubu, 0 hata)`**
2. `test/core_next/stage10_10_8_ledger_amount_fix_test.dart`:
   - **`All tests passed! (4/4 test grubu, 0 hata)`**
3. `test/core_next/stage10_10_multi_tenant_migration_test.dart`:
   - **`All tests passed! (5/5 test grubu, 0 hata)`**
4. `test/core_next/stage10_10_6_data_integrity_verification_test.dart`:
   - **`All tests passed! (5/5 test grubu, 0 hata)`**
5. `test/core_next/stage10_10_7_independent_evidence_audit_test.dart`:
   - **`All tests passed! (6/6 test grubu, 0 hata)`**

---

## 8. ÜRETİM VERİSİNİN KORUNDUĞUNA İLİŞKİN KANITLAR

### 8.1 Ham Yedeklerin SHA-256 Değerleri
| Dosya Yolu | Manifest SHA-256 | Test Sonrası SHA-256 | Durum |
| :--- | :--- | :--- | :--- |
| `backups\raw_tenants_20261016\raw_nutopia_v60.db` | `E70AA44A43C53F47F61C7B82A0A8C290D82E9F849AEC68486782BC2917430D24` | `E70AA44A43C53F47F61C7B82A0A8C290D82E9F849AEC68486782BC2917430D24` | **AYNI / DEĞİŞMEDİ** |
| `backups\raw_tenants_20261016\raw_serenut_v44.db` | `9145443F2C94A03DEA7478605DE974A1214B548523DA0406C18501918DA7D77D` | `9145443F2C94A03DEA7478605DE974A1214B548523DA0406C18501918DA7D77D` | **AYNI / DEĞİŞMEDİ** |
| `backups\raw_tenants_20261016\raw_erkul_source.json` | `B4912D916818377FA3D4A2D87C9BC33AA9B5FCD69300442DD6EEA6D8FA5EE389` | `B4912D916818377FA3D4A2D87C9BC33AA9B5FCD69300442DD6EEA6D8FA5EE389` | **AYNI / DEĞİŞMEDİ** |

### 8.2 AppData Üretim Hedef Veritabanları
`%APPDATA%\Serenut OS Software Technologies A.Ş\Serenut OS\databases\core_next`:
- `nutopia_pos.db`: LastWriteTime = 16.10.2026 18:53:20 (Stage 10.10.5 setup zamanı; dokunulmamıştır).
- `serenut_pos.db`: LastWriteTime = 16.10.2026 18:53:22 (Stage 10.10.5 setup zamanı; dokunulmamıştır).
- `erkul_pos.db`: LastWriteTime = 16.10.2026 18:53:23 (Stage 10.10.5 setup zamanı; dokunulmamıştır).

### 8.3 Feature Flag Durumu
`lib/presentation/controllers/sales_controller.dart`:
```dart
final coreNextSalesEngineEnabledProvider = StateProvider<bool>((ref) => false);
```
Kesinlikle `false` (KAPALI) olarak kalmaktadır.

---

## 9. SONRAKİ AŞAMA İÇİN ÖNERİLER (CANLIYA GEÇİŞ PLANI)

Kod düzeltmesi (`MigrationBridgeEngine.resolveAmountCents`), izole yeniden aktarım ve derin mutabakat testleri %100 başarıyla tamamlanmıştır.

Canlıya geçiş (Cutover) ve AppData üretim veritabanlarının güncellenmesi için kullanıcıdan açık onay beklenmektedir:
1. **Adım 1:** `%APPDATA%\...\databases\core_next\` altındaki mevcut veritabanlarının son bir anlık yedeğinin alınması.
2. **Adım 2:** Düzeltilmiş motor ile `nutopia_pos.db` dosyasındaki eksik 2 hareketin güncellenmesi (veya ham yedeğin kontrollü olarak doğrudan buraya aktarılması).
3. **Adım 3:** UI ve işletme seçici ekranı üzerinden tek bir pilot işletme (örn. Nutopia veya Serenut) ile `coreNextSalesEngineEnabledProvider` bayrağının kontrollü olarak açılması.
