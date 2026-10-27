# SERENUT OS — STAGE 10.12.64
# FULL-SCALE ISOLATED EXPORT/IMPORT, ERKUL JSON ADAPTER & CUSTOMER-LEVEL FINANCIAL RECONCILIATION AUDIT RAPORU

**Tarih:** 21 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Branch:** `main`  
**Hedef Kapsam:** Üç işletmenin (Nutopia Fındık Değirmeni, Serenut, Erkul Çeyiz) gerçek kaynak verilerinin izole hedef veritabanlarına tam ölçekli aktarımı, resmi Erkul JSON Dart adaptörünün geliştirilmesi, müşteri düzeyinde kuruş mutabakatı, mükerrerlik ve bütünlük denetimleri.

---

## 1. ÇALIŞMA ORTAMI VE DEĞİŞMEZ GÜVENLİK SINIRLARI

Aşağıdaki değişmez kurallar titizlikle korunmuş, hiçbir ihlal yapılmamıştır:

| Güvenlik Kuralı | Beklenen Durum | Gerçek Durum | Doğrulama & Kanıt |
|---|---|---|---|
| `coreNextSalesEngineEnabledProvider` | `false` | `false` | `stage10_12_64_full_scale_export_import_test.dart:35` |
| `DatabaseManager.databaseRoutingHook` | `null` | `null` | `stage10_12_64_full_scale_export_import_test.dart:39` |
| `coreNextSaleExecutorProvider` | `null` | `null` | `stage10_12_64_full_scale_export_import_test.dart:45` |
| Canlı DB Yazma / Mutasyon | 0 bayt mutasyon | 0 bayt mutasyon | Canlı DB'ler açılmadı, taşınmadı, değiştirilmedi |
| Bakım Kilidi (Canlı Mağaza) | Etkinleştirilmedi | Etkinleştirilmedi | Canlı sistemde bakım modu açılmadı |
| Kiracı İzolasyonu | 3 Ayrı İzole Klasör | 3 Ayrı Klasör / 3 Hedef DB | `backups/stage64_isolated/{nutopia,serenut,erkul}` |
| Canlı Cutover / Dağıtım / Commit | Yapılmadı | Yapılmadı | `git status` ve `git diff` yerel ve kontrollü |

### Git Doğrulaması

```powershell
git rev-parse HEAD        # 28c158d88028f139e93f78982d4651ad424c61d2
git branch --show-current   # main
git diff --check           # Exit Code: 0 (Temiz, whitespace/CRLF hatası yok)
```

---

## 2. KAYNAK VE HEDEF DOSYALARININ KESİN FORENSİK BİLGİLERİ

Kaynak dosyalar salt-okunur olarak incelenmiş, çalışma anında izole hedef klasörlere kopyalanarak işlenmiştir. Hiçbir kaynak dosyanın üzerine yazılmamıştır.

### 1. Kaynak Arşivler (Salt-Okunur)

| İşletme | Dosya Yolu | Dosya Boyutu (Bayt) | SHA-256 Özeti |
|---|---|---|---|
| **Nutopia** | `backups/raw_tenants_20261016/raw_nutopia_v60.db` | 59,764,736 | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` |
| **Serenut** | `backups/raw_tenants_20261016/raw_serenut_v44.db` | 6,516,736 | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` |
| **Erkul Çeyiz** | `backups/raw_tenants_20261016/raw_erkul_source.json` | 485,357 | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` |

### 2. Oluşturulan İzole Hedef Çıktıları (`backups/stage64_isolated/`)

| İşletme | Hedef SQLite Dosyası | Dosya Boyutu | SHA-256 Özeti | Bütünlük (`integrity_check`) | FK İhlali (`foreign_key_check`) |
|---|---|---|---|---|---|
| **Nutopia** | `backups/stage64_isolated/nutopia/nutopia_core_next.db` | 17,018,880 | `543b6761f261e028f1e9e3b1f7bb19e17bb9e555ef75c15039667aea97e384ff` | `ok` | 0 Hata |
| **Serenut** | `backups/stage64_isolated/serenut/serenut_core_next.db` | 2,359,296 | `ba97be8bd0e938d7f8c18b7430989b30cb545e2c750375390229e4e5658395da` | `ok` | 0 Hata |
| **Erkul** | `backups/stage64_isolated/erkul/erkul_core_next.db` | 565,248 | `c85ebb69d12c90fa15d6064113db9ad5188e5af0e657d01dd521878c4e2550ff` | `ok` | 0 Hata |

---

## 3. ERKUL ÇEYİZ — RESMİ DART JSON ADAPTÖRÜ VE FİNANSAL REKONSTRÜKSİYON

Erkul Çeyiz'in verisi SQLite değil JSON metin dump'ı olduğundan, doğrudan `MigrationBridgeEngine` SQLite yolundan geçirilemezdi. Bu aşamada mimariye tam uyumlu, deterministik, `ConflictAlgorithm.ignore` ile tekrar çalıştırılabilir (idempotent) ve çift taraflı defter kurallarına sahip resmi bir Dart adaptörü geliştirilmiştir:

- **Dosya:** `core_next/client_core/lib/infrastructure/migration/erkul_json_importer.dart`
- **Sınıf:** `ErkulJsonImporter(targetDb)`
- **Köprü Entegrasyonu:** `MigrationBridgeEngine.migrateFromErkulJson` adaptöre bağlanmıştır.

### 1. Erkul Finansal Semantiği ve Adli Kanıt

Erkul verisindeki 539 finansal hareketin kuruş dökümü bağımsız olarak doğrulanmıştır:

| İşlem Türü (`type`) | Kayıt Adedi | Kuruş Tutarı | TL Tutarı | Açıklama |
|---|---|---|---|---|
| `manual_debt` | 423 | 431,074,500 | 4,310,745.00 TL | Senetli çeyiz sözleşmesi borçları (`amount = debt_amount`) |
| `collection` | 109 | 54,164,000 | 541,640.00 TL | Elden/nakit çeyiz taksit tahsilatları (`amount = paid_amount`) |
| `sale` | 6 | 3,003,000 | 30,030.00 TL | 5 vadeli satış (18,030 TL borç), 1 peşin satış (12,000 TL peşin) |
| `payment` | 1 | 1,000 | 10.00 TL | POS nakit ödeme |
| **TOPLAM** | **539** | **488,242,500** | **4,882,425.00 TL** | 0 null ID, 0 negatif tutar |

### 2. Müşteri Bakiye Rekonstrüksiyon Formülü ve İspatı

Serenut OS ve Core Next çift taraflı defter kurallarına göre müşteri bakiyesi:
$$\text{Reconstructed Balance Cents} = - (\text{manual\_debt\_cents} + \text{sale\_debt\_cents}) + \text{collection\_cents} + \text{payment\_cents}$$

- **381 Aktif Müşteri İçin:**
  - Toplam Sözleşme Borcu (`manual_debt`): `415,320,500 kuruş` (`4,153,205.00 TL`)
  - Toplam Tahsilat (`collection`): `36,608,000 kuruş` (`366,080.00 TL`)
  - Kaynak JSON Bakiyesi (`balance`): `-36,608,000 kuruş` (Eski sistem sadece tahsilatları eksi biriktirmişti!)
  - Reconstructed Balance: **`-378,712,500 kuruş` (`-3,787,125.00 TL`)**
  - Gerçek Müşteri Alacağı (Receivable): **`3,787,125.00 TL`**
- **20 Kapanmış / Silinmiş Müşteri İçin:**
  - 16 müşteride `manual_debt == collection` (borç tamamen ödenmiş ve müşteri arşivlenmiş).
  - 4 müşteride `TUNAHAN` isimli demo kayıtları yer almaktadır; satış borçları ile tahsilatları birbirini kapatmıştır.
  - 20 silinmiş müşterinin tamamında:
    $$\text{Reconstructed Balance} \equiv 0 \text{ kuruş} \quad (0.00 \text{ TL})$$
  - Kaynak JSON'da ise `-157,540.00 TL` hatalı negatif bakiye görünüyordu. Rekonstrüksiyon ile kapanmış müşterilerin bakiyesi sıfırlanmıştır.

### 3. Bilinmeyen İşlem Türü Güvenliği (Fail-Closed)

Adaptör, `financial_transactions` içinde `manual_debt`, `collection`, `sale` veya `payment` dışında bilinmeyen bir işlem türü gördüğünde aktarımı derhal durdurup `UnrecognizedFinancialTransactionTypeException` fırlatır ve işlemi transaction seviyesinde rollback yapar (hedefte 0 kayıt bırakır).

---

## 4. ÜÇ İŞLETMENİN GERÇEK ENVENTERİ VE HEDEF MUTABAKATI

### 1. Kaynak ve Hedef Kayıt Sayıları Karşılaştırma Matrisi

| Tablo / Varlık | Nutopia Kaynak (v60) | Nutopia Hedef | Serenut Kaynak (v44) | Serenut Hedef | Erkul Kaynak (JSON) | Erkul Hedef |
|---|---|---|---|---|---|---|
| **Kullanıcılar** | 2 | 2 | 1 | 1 | 1 | 1 |
| **Kategoriler** | 49 (ürünlerden) | 49 | 27 (ürünlerden) | 27 | 0 (türetilen) | 5 |
| **Ürünler (Toplam)** | 37,682 | 37,682 | 6,377 | 6,377 | 26 | 26 |
| ↳ *Adet Ürünleri* | 37,673 | 37,673 | 6,368 | 6,368 | 26 | 26 |
| ↳ *Kg / Tartılı* | 9 | 9 | 9 | 9 | 0 | 0 |
| **Müşteriler** | 584 | 584 | 7 | 7 | 401 | 401 |
| ↳ *Aktif Müşteri* | 584 | 584 | 7 | 7 | 381 | 381 |
| ↳ *Silinmiş / Pasif* | 0 | 0 | 0 | 0 | 20 | 20 |
| **Satışlar** | 52 | 52 | 15 | 15 | 5 | 5 |
| **Satış Kalemleri** | 120 | 120 | 19 | 19 | 5 | 5 |
| **Satış Ödemeleri** | 54 | 54 | 15 | 15 | 0 | 0 |
| **Finansal Hareketler (Toplam)** | 1,424 | 1,424 | 22 | 22 | 539 | 539 |
| ↳ *Cari Defter (`ledger_entries`)* | 1,403 | 1,403 | 12 | 12 | 539 | 539 |
| ↳ *Kasa Girişi (`cash_transactions`)* | 21 | 21 | 10 | 10 | 0 | 0 |
| **Siparişler (`orders`)** | 792 | 792 | 5 | 5 | 1 | 1 |
| **Sipariş Kalemleri (`order_items`)** | 1,068 | 1,068 | 5 | 5 | 1 | 1 |
| **Taksit Sözleşmeleri / Planları** | 2 plan, 9 taksit | 2 plan, 9 taksit | 0 | 0 | 0 | 0 |
| **Denetim Olayları (`audit_events`)** | 3,972 | 3,972 | 57 | 57 | 0 | 0 |

### 2. Finansal Bakiye ve Kuruş Mutabakatı

| İşletme | Kaynak Bakiye Toplamı | Hedef Bakiye Toplamı (Kuruş) | TL Karşılığı | Mutabakat Durumu |
|---|---|---|---|---|
| **Nutopia** | `-134,500.68 TL` | `-13,450,068 kuruş` | `-134,500.68 TL` | **%100 KURUŞU KURUŞUNA EŞİT (0 fark)** |
| **Serenut** | `-2,673.00 TL` | `-267,300 kuruş` | `-2,673.00 TL` | **%100 KURUŞU KURUŞUNA EŞİT (0 fark)** |
| **Erkul Çeyiz** | `-523,620.00 TL` (Tek Taraflı Hatalı) | `-378,712,500 kuruş` (381 Aktif Cari) + `0 kuruş` (20 Silinmiş Cari) | `-3,787,125.00 TL` (Net Gerçek Alacak) | **ÇİFT TARAFLI REKONSTRÜKTE EDİLDİ (3.787.125 TL Alacak)** |

### 3. Stok Mutabakatı (Adet vs Kg Kesin Ayrımı)

- **Nutopia:**
  - Adet Grubu: 37,673 ürün | Toplam Stok: `5,054,094.0 adet`
  - Kilogram Grubu: 9 ürün | Toplam Stok: `125,431.85 kg`
  - *Fark:* 0 adet, 0.0 kg. Asla birbirine karıştırılmamıştır.
- **Serenut:**
  - Adet Grubu: 6,368 ürün | Toplam Stok: `636,640.0 adet`
  - Kilogram Grubu: 9 ürün | Toplam Stok: `805.0 kg`
  - *Fark:* 0 adet, 0.0 kg.
- **Erkul Çeyiz:**
  - Adet Grubu: 26 ürün | Toplam Stok: `1,000,242.0 adet`
  - Kilogram Grubu: 0 ürün | Toplam Stok: `0.0 kg`

---

## 5. ÜÇ İŞLETMENİN KESİN AYRILIĞI VE ID ÇAKIŞMA AUDİTİ

Her hedef veritabanında `app_settings` tablosuna benzersiz `tenant_id` damgası vurulmuştur:
- Nutopia Hedefi: `tenant_id = 'nutopia'`, `business_name = 'Nutopia Fındık Değirmeni'`
- Serenut Hedefi: `tenant_id = 'serenut'`, `business_name = 'serenut'`
- Erkul Hedefi: `tenant_id = 'erkul'`, `business_name = 'ERKUL ÇEYİZ'`

### Çapraz ID Çakışma Analizi (Kritik Bulgu)

Üç veritabanı çapraz karşılaştırıldığında:
1. **Erkul Çeyiz vs Nutopia/Serenut:**
   - Müşteri, ürün, satış ve finansal hareket ID'lerinde **0 çakışma** tespit edilmiştir. Erkul tamamen bağımsız bir veri kümesidir.
2. **Nutopia vs Serenut:**
   - 7 müşterinin tamamı (`%100`) Nutopia ile aynı ID'ye sahiptir.
   - 6,354 ürün (`%99.6`) Nutopia ürün ID'leri ile çakışmaktadır.
   - 15 satışın tamamı (`%100`) ve 22 finansal hareketin tamamı (`%100`) Nutopia ID'leri ile çakışmaktadır.
   - **Kök Neden:** `raw_serenut_v44.db`, Nutopia'nın daha önceki bir SQLite v44 sürüm snapshot'ıdır. Aynı veritabanı soyundan gelmektedir.
   - **Mimari Karar:** Nutopia ve Serenut veritabanları **ASLA TEK BİR VERİTABANINDA BİRLEŞTİRİLEMEZ (MERGE YASAKTIR)**. Her iki mağaza kendi bağımsız SQLite veritabanı dosyasında (`nutopia_core_next.db` ve `serenut_core_next.db`) ayrı ayrı barındırılmalıdır.

---

## 6. NUTOPIA_MANUAL_PROMISSORY_TRANSACTIONS
### (Nutopia Fındık Değirmeni Elle Eklenen Senetli ve Vadeli İşlemler Adli Denetimi)

Nutopia Fındık Değirmeni verilerindeki elle girilen senet, senetli borç, vadeli taksit sözleşmeleri ve ilgili tahsilat hareketleri normal satışlardan ve peşin kasa işlemlerinden ayrı bir veri kaynağı ve finansal hareket türü olarak adli düzeyde incelenmiş ve izole aktarım kapsamına dahil edilmiştir.

### 1. Kaynak Tablolar, Alanlar ve İlişkili Kayıtlar

Nutopia SQLite (`raw_nutopia_v60.db`) kaynak kodunda ve veritabanında senetli/vadeli işlemler şu 3 ilişkili tabloda tutulmaktadır:

1. **`financial_transactions` (Finansal Defter):**
   - **`type = 'manual_debt'`:** Kasiyer veya yönetici tarafından müşteriye elle eklenen senetli veya açık hesap borç kayıtları.
   - **Kayıt Sayısı:** **54 adet**.
   - **Toplam Kaynak Tutar:** **`103,351.00 TL`** (`10,335,100 kuruş`).
   - **Alanlar:** `id` (`trans-debt-...`), `customer_id`, `amount` (`debt_amount = amount`, `paid_amount = 0`), `reference_id` (taksit sözleşmesine işaret ediyorsa plan ID'si, bağımsız ise `NULL`), `description`, `created_at`, `is_deleted = 0`.
   - **Müşteri Dağılımı:** **32 farklı müşteri** üzerinde dağılmıştır.
2. **`customer_installment_plans` (Senetli/Vadeli Taksit Planları):**
   - **Kayıt Sayısı:** **2 adet plan**.
   - **Plan 1 (`plan-19d3e9a9-242e-4b34-acf7-c5ca2a5aa160`):** Müşteri `48c82bec-b95f-4eee-aff1-a7a2ba933295`, Toplam Tutar: `10,000.00 TL`, Peşinat: `3,200.00 TL`, 3 Taksit, Durum: `active`, `is_deleted = 0`. Master borç kaydı: `trans-debt-d541780b-91ec-4d42-bdca-29f3b13f80aa`.
   - **Plan 2 (`plan-6effa275-9766-475c-8484-ab2e1e88d549`):** Müşteri `cust-1788335851742129-7685`, Toplam Tutar: `12,000.00 TL`, Peşinat: `120.00 TL`, 6 Taksit, Durum: `cancelled`, `is_deleted = 1`. Master borç kaydı: `trans-debt-a32140da-c933-44f0-9edb-e03f68c71932`.
3. **`customer_installments` (Senet/Taksit Detayları ve Vadeleri):**
   - **Kayıt Sayısı:** **9 adet taksit kaydı**.
   - **Plan 1 Taksitleri (3 adet):** 1 pending (vade: 2026-11-09), 2 paid (vade: 2026-12-09, 2027-01-09).
   - **Plan 2 Taksitleri (6 adet):** Tümü iptal edilmiş (`cancelled`, `is_deleted = 1`, vadeler: 2026-11-10 ila 2027-04-10).
4. **Taksit ve Senet Tahsilatları (`collection`):**
   - **Kayıt Sayısı:** **8 adet taksit açıklamalı tahsilat kaydı**.
   - **Toplam Tahsilat Tutarı:** **`9,753.32 TL`** (`975,332 kuruş`).
   - *Döküm:* Plan 1 için Peşinat (3,200.00 TL) + 2. Taksit (2,266.66 TL) + 3. Taksit parçalı (200 + 1000 + 100 + 966.66 = 2,266.66 TL); Plan 2 için Peşinat (120.00 TL) + 1. Taksit (1,900.00 TL).

### 2. Normal Satışlarla Karışmama ve Mükerrerlik Denetimi

- **ID Ayrımı:** Satış kayıtları `sale-...` önekiyle başlar ve `sale_items` satırlarına sahiptir. Senetli/manuel borçlar ise `trans-debt-...` önekine sahiptir ve satış satırı içermez.
- **Kesişim Denetimi:** `debt_ids ∩ sale_ids == ∅` (Kesişim sıfırdır, 0 çakışma).
- **Mükerrerlik Denetimi:** Hiçbir satış kaydı otomatik `manual_debt` üretmemiş, hiçbir `manual_debt` satış tablosuna tekrar yazılmamıştır.
- **Hedef Bütünlüğü:** `ledger_entries` (1,403) + `cash_transactions` (21) = 1,424 kaynak işlem (Kayıp = 0, Fazlalık = 0, Mükerrerlik = 0).

### 3. Kuruş Hassasiyetinde Kaynak vs Hedef Karşılaştırması

| Finansal Varlık | Kaynak Kayıt | Hedef Kayıt | Kaynak Tutar (TL) | Hedef Tutar (Kuruş) | Fark (Kuruş) | Durum |
|---|---|---|---|---|---|---|
| **Manuel Borçlar (`manual_debt`)** | 54 | 54 (`MANUAL_DEBT`) | `103,351.00 TL` | `10,335,100 kuruş` | **0 kuruş** | **EKSİKSİZ PASS** |
| ↳ *Sözleşmeli Taksit Borçları* | 2 | 2 | `22,000.00 TL` | `2,200,000 kuruş` | **0 kuruş** | **EKSİKSİZ PASS** |
| ↳ *Bağımsız Manuel Borçlar* | 52 | 52 | `81,351.00 TL` | `8,135,100 kuruş` | **0 kuruş** | **EKSİKSİZ PASS** |
| **Taksit Planları (`plans`)** | 2 | 2 | `22,000.00 TL` | `2,200,000 kuruş` | **0 kuruş** | **EKSİKSİZ PASS** |
| ↳ *Aktif Plan* | 1 | 1 | `10,000.00 TL` | `1,000,000 kuruş` | **0 kuruş** | **EKSİKSİZ PASS** |
| ↳ *İptal Edilen Plan* | 1 | 1 | `12,000.00 TL` | `1,200,000 kuruş` | **0 kuruş** | **EKSİKSİZ PASS** |
| **Taksit Kalemleri (`installments`)**| 9 | 9 | `11,948.00 TL` | `1,194,800 kuruş` | **0 kuruş** | **EKSİKSİZ PASS** |
| **Senet/Taksit Tahsilatları** | 8 | 8 (`COLLECTION`) | `9,753.32 TL` | `975,332 kuruş` | **0 kuruş** | **EKSİKSİZ PASS** |
| **Standart Cari Tahsilatlar** | 81 | 81 (`COLLECTION`) | `165,967.00 TL` | `16,596,700 kuruş` | **0 kuruş** | **EKSİKSİZ PASS** |

### 4. Müşteri Bakiye Mutabakatı (Tek Başına `balance` Kopyalamama Kuralı)

Nutopia kaynak veritabanında `customers.balance` alanı doğrudan kopyalanarak doğrulanmış kabul edilmemiştir. Gerçek defter etkisi adli olarak incelenmiştir:

- **Eski Sistem Defter Etkisi (`v_customer_ledger_effect` Görünümü):**
  ```sql
  CASE 
    WHEN COALESCE(is_deleted, 0) != 0 THEN 0.0
    WHEN type IN ('sale', 'manual_debt') THEN -(CASE WHEN debt_amount > 0 THEN debt_amount ELSE (amount - paid_amount) END)
    WHEN type IN ('payment', 'collection') THEN paid_amount
    WHEN type = 'cancellation' THEN (CASE WHEN debt_amount > 0 THEN debt_amount ELSE (amount - paid_amount) END)
    WHEN type = 'refund' AND paid_amount = 0 THEN amount
    ELSE 0.0
  END AS balance_effect
  ```
- **Müşteri Bazında Mutabakat Sonucu:**
  - Tüm 584 müşteride `customers.balance` ile `v_customer_ledger_effect` toplamı karşılaştırılmıştır.
  - **Müşteri Bazlı Uyuşmazlık Sayısı:** **KESİNLİKLE 0 (SIFIR)**.
  - Nutopia'nın 54 adet senetli/manuel borç kaydı ve 8 adet taksit tahsilatı, müşteri bakiyelerine tam olarak yansımıştır.
  - Hedef veritabanında kuruş bakiye toplamı: **`-13,450,068 kuruş` (`-134,500.68 TL`)**.
  - **Kaynak ile Hedef Arasındaki Fark:** **0.00 TL (0 kuruş)**.

### 5. Çözülemeyen Eşlemeler ve Fail-Closed Güvencesi

- **Tahmin Edilerek Dönüştürülen Kayıt Sayısı:** **0**.
- **Çözülemeyen / Belirsiz Finansal Hareket:** **0**.
- Tüm hareketler net kanıtlanmış finansal türlerine dönüştürülmüştür (`sale` → `SALE`, `manual_debt` → `MANUAL_DEBT`, `collection` → `COLLECTION`, `payment` → `PAYMENT`, `cancellation` → `CANCELLATION`, `refund` → `REFUND`).
- Bilinmeyen veya tanımsız bir hareket tespit edilmesi durumunda sistem fail-closed kuralı uyarınca aktarımı bloke edecek şekilde doğrulanmıştır.

---

## 7. OTOMATİK TESTLER, ANALİZ VE BAĞIMSIZ KANIT

### 1. Yeni Stage 64 Test Paketi

- **Test Dosyası:** `test/core_next/stage10_12_64_full_scale_export_import_test.dart`
- **Kapsam:** Güvenlik kuralları, Erkul JSON adaptörü, bakiye rekonstrüksiyonu, fail-closed rollback, Serenut v44 tam migrasyonu, Nutopia v60 (60 MB / 37,682 ürün) tam migrasyonu, **Nutopia senetli ve manuel borç/taksit mutabakatı (54 manual_debt, 2 plan, 9 taksit, 8 taksit tahsilatı)**, idempotens ve kiracı izolasyonu.

```powershell
flutter test test/core_next/stage10_12_64_full_scale_export_import_test.dart
```
**Sonuç:** `00:21 +13: All tests passed! (Exit Code: 0, 21.8s)`

### 2. Regresyon Test Paketi (Stages 50–64, 13 Test Dosyası)

```powershell
flutter test `
  test/core_next/stage10_12_50_nutopia_erkul_data_safety_test.dart `
  test/core_next/stage10_12_51_nutopia_delta_catchup_test.dart `
  test/core_next/stage10_12_52_financial_stock_integrity_test.dart `
  test/core_next/stage10_12_53_dart_reconciliation_repair_test.dart `
  test/core_next/stage10_12_54_pre_cutover_financial_flow_test.dart `
  test/core_next/stage10_12_55_final_backup_delta_rollback_test.dart `
  test/core_next/stage10_12_56_delta_completeness_test.dart `
  test/core_next/stage10_12_57_cutover_protocol_audit_test.dart `
  test/core_next/stage10_12_58_cutoff_lock_drainer_test.dart `
  test/core_next/stage10_12_59_central_write_lock_integration_test.dart `
  test/core_next/stage10_12_60_maintenance_ui_cutover_rehearsal_test.dart `
  test/core_next/stage10_12_61_cart_lock_three_tenant_export_import_test.dart `
  test/core_next/stage10_12_64_full_scale_export_import_test.dart
```
**Sonuç:** `01:54 +146: All tests passed! (Exit Code: 0, 1m 54s)`

### 3. Statik Kod Analizi (`flutter analyze`)

```powershell
flutter analyze core_next/client_core/lib/infrastructure/migration/erkul_json_importer.dart `
  core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart `
  test/core_next/stage10_12_64_full_scale_export_import_test.dart
```
**Sonuç:** `No issues found! (ran in 11.9s, Exit Code: 0)`

---

## 8. SONUÇLARIN SINIFLANDIRILMASI

| Kategori | Sonuç Kodu | Açıklama |
|---|---|---|
| **Nutopia Fındık Değirmeni** | `FULL_SCALE_IMPORT_PASS_ISOLATED_ONLY` | 37,682 ürün, 584 cari, 52 satış, 1,424 hareket (54'ü senetli/manuel borç, 2'si taksit planı, 9'u taksit detayı, 8'i taksit tahsilatı) tam mutabakatla izole hedefe aktarıldı. |
| **Nutopia Senetli İşlemler** | `NUTOPIA_MANUAL_PROMISSORY_VERIFIED_PASS` | 54 manual_debt (103.351 TL), 2 plan, 9 taksit ve 8 taksit tahsilatı kuruş bazında 0 farkla deftere aktarıldı, satışlarla çakışmadığı kanıtlandı. |
| **Serenut** | `FULL_SCALE_IMPORT_PASS_ISOLATED_ONLY` | 6,377 ürün, 7 cari, 15 satış, 22 hareket tam mutabakatla izole hedefe aktarıldı. |
| **Erkul Çeyiz** | `FULL_SCALE_IMPORT_PASS_ISOLATED_ONLY` | Resmi Dart JSON adaptörü ile 401 cari, 26 ürün, 5 satış, 539 hareket rekonstrükte edilerek izole hedefe aktarıldı. |
| **Finansal Semantik** | `VERIFIED_WITH_RECONSTRUCTION_RULE` | 381 aktif caride 3.787.125 TL alacak ve 20 silinmiş caride 0 TL bakiye matematiksel kesinlikle doğrulandı. |
| **Çoklu Kiracı İzolasyonu** | `ISOLATED_SEPARATE_DBS_MANDATORY` | Nutopia ve Serenut arasındaki ID çakışmaları nedeniyle veritabanlarının birleştirilmesi kesinlikle yasaktır; her işletme kendi dosyasında çalışmalıdır. |

---

## 9. KALAN ENGELLER VE GELECEK AŞAMA İÇİN GEREKLİ ADIMLAR

1. **Canlı Veri Tazeliği (Delta Catch-up):** Arşivler 16 Ekim 2026 tarihlidir. Canlı sisteme geçmeden önce mağazalardan 21 Ekim güncel canlı yedekleri alınmalı ve aradaki delta farkları doğrulanmalıdır.
2. **Kasiyer Ön-İzleme Ekranı:** Kasiyerlerin geçiş öncesinde eski bakiyeleri ile yeni kuruş bakiyelerini görebileceği salt-okunur doğrulama arayüzü sağlanmalıdır.
3. **Canlı Cutover Protokolü:** `docs/release-update-runbook.md` uyarınca üretim deploy adımları işletilmeden canlı sisteme müdahale edilmemelidir.

---

## 10. SON GÜVENLİK DURUMU

CUTOVER: NOT APPROVED  
LIVE DATABASE WRITES: NOT PERFORMED  
CORE NEXT SALES ENGINE: DISABLED  
DATABASE ROUTING HOOK: NULL  
OLD DATABASE RETIREMENT: NOT APPROVED  
