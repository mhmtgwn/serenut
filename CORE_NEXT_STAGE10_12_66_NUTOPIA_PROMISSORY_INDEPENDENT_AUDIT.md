# SERENUT OS — STAGE 10.12.66
# NUTOPIA SENETLİ İŞLEMLER BAĞIMSIZ KANIT DENETİMİ (INDEPENDENT AUDIT RAPORU)

**Tarih:** 21 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Branch:** `main`  
**Hedef Kapsam:** Stage 10.12.64 raporundaki `NUTOPIA_MANUAL_PROMISSORY_VERIFIED_PASS` sonucunun, hiçbir önceki sonucu peşinen doğru kabul etmeden, salt-okunur ham kaynak ve salt-okunur izole hedef veritabanları üzerinden bire bir işlem bazında, kuruş hassasiyetinde ve müşteri düzeyinde bağımsız kanıtlarla denetlenmesi.

---

## 1. BAŞLANGIÇ GİT DURUMU VE DOSYA HASHLERİ

### 1. Git Durumu Doğrulaması

```powershell
git rev-parse HEAD        # 28c158d88028f139e93f78982d4651ad424c61d2
git branch --show-current   # main
git diff --check           # Exit Code: 0 (Temiz)
git log -5 --oneline       # 28c158d8 fix(test): align splash screen error title expectation...
```
Kullanıcı değişiklikleri korunmuş, hiçbir dosya geri alınmamış veya temizlenmemiştir.

### 2. Salt-Okunur Dosya Kimlikleri ve Bütünlük Denetimi

| Dosya Tanımı | Dosya Yolu | Boyut (Bayt) | SHA-256 Özeti | SQLite `integrity_check` | `foreign_key_check` |
|---|---|---|---|---|---|
| **Ham Kaynak (v60)** | `backups/raw_tenants_20261016/raw_nutopia_v60.db` | 59,764,736 | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | `ok` | 0 İhlal |
| **Mevcut İzole Hedef** | `backups/stage64_isolated/nutopia/nutopia_core_next.db` | 17,018,880 | `8f270986277d661c021d75e85e25352bccb18b48ff8db6f088b9f5fbea95a300` | `ok` | 0 İhlal |
| **Önceki Kaynak Kopyası** | `backups/stage64_isolated/nutopia_source_stage64.db` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | 0 bayt (boş taslak) | - |

> [!NOTE]
> `nutopia_source_stage64.db` dosyası önceki bir çalıştırmada bağlantı açılması sonucu oluşan 0 baytlık boş bir dosyadır. Tüm adli denetim, değişmez ve tam ham kaynak olan `raw_nutopia_v60.db` (59,764,736 bayt) üzerinden salt-okunur yürütülmüştür.

---

## 2. KAYNAK VE HEDEF TABLO SAYIMLARI

| Tablo / Varlık | Ham Kaynak (`raw_nutopia_v60.db`) | İzole Hedef (`nutopia_core_next.db`) | Fark | Durum |
|---|---|---|---|---|
| **Müşteriler (`customers`)** | 584 | 584 (583 geçerli cari + 1 dahili) | 0 | Eşit |
| **Finansal Hareketler (Toplam)** | 1,424 | 1,424 (1,403 cari defter + 21 kasa) | 0 | Eşit |
| ↳ `manual_debt` | 54 | 54 (`ledger_entries.entry_type = MANUAL_DEBT`) | 0 | Eşit |
| ↳ `collection` | 89 | 89 (`ledger_entries.entry_type = COLLECTION`) | 0 | Eşit |
| ↳ `payment` | 396 | 396 (`ledger_entries.entry_type = PAYMENT`) | 0 | Eşit |
| ↳ `sale` | 828 (807 carili + 21 carisiz) | 807 carili defter + 21 `cash_transactions` | 0 | Eşit |
| ↳ `cancellation` | 35 | 35 (`ledger_entries.entry_type = CANCELLATION`) | 0 | Eşit |
| ↳ `refund` | 22 | 22 (`ledger_entries.entry_type = REFUND`) | 0 | Eşit |
| **Taksit Sözleşmeleri (`customer_installment_plans`)** | 2 | 2 | 0 | Eşit |
| **Taksit Kalemleri (`customer_installments`)** | 9 | 9 | 0 | Eşit |

---

## 3. MANUEL BORÇ VE SENET İŞLEMLERİNİN İŞLEM BAZINDA EŞLEŞTİRİLMESİ (1-TO-1 FORENSIC MATCH)

Kaynak `financial_transactions` tablosundaki 54 `manual_debt` kaydının tamamı çıkarılmış ve hedef `ledger_entries` ile işlem bazında karşılaştırılmıştır:

### 1. Döküm ve Yeniden Hesaplanan Değerler

- **Kaynak Kayıt Sayısı:** **54 adet** (Önceki raporun sabit değeri değil, ham veritabanından doğrudan sorgulanmıştır).
- **Kaynak Tutar Toplamı (`amount`):** **`103,351.00 TL`** (`10,335,100 kuruş`).
- **Kaynak Borç Toplamı (`debt_amount`):** **`103,351.00 TL`** (`10,335,100 kuruş`).
- **Kaynak Ödenen Toplamı (`paid_amount`):** **`0.00 TL`** (Tüm manuel borçlar oluşturulduğunda ödenmemiş durumdadır).
- **Silinmiş Kayıt Sayısı (`is_deleted != 0`):** **0 adet**.
- **Farklı Müşteri Sayısı:** **32 müşteri**.

### 2. İşlem Düzeyinde Bire Bir (1-to-1) Karşılaştırma Sonucu

- **Bire Bir Eşleşen Kayıt:** **54 / 54 (%100)**.
- **Kayıp Kayıt:** **0**.
- **Fazlalık Kayıt:** **0**.
- **Mükerrer Kayıt:** **0**.
- **Tutar / Kuruş Farkı:** **0 kuruş**.
- **Eşleşmeyen Müşteri:** **0**.

### 3. ID, Referans ve Açıklama Alanı Davranışı

1. **İşlem ID'si Eşleşmesi:**
   Tüm 54 kaydın hedef `ledger_entries.id` alanı, kaynak `financial_transactions.id` değeriyle (`trans-debt-...`) karakteri karakterine özdeştir.
2. **`reference_id` vs `reference_sale_id` Alanı:**
   - 52 bağımsız manuel borç kaydında kaynak `reference_id` değeri `NULL`'dır; hedefte de `NULL`'dır.
   - 2 adet sözleşmeli taksit borcunda kaynak `reference_id` bir taksit planı ID'sidir (`plan-19d3e9a9...` ve `plan-6effa275...`).
   - Hedef `ledger_entries.reference_sale_id` alanı foreign key olarak yalnızca `sales` tablosuna bağlanabilir. Bu sebeple göç motoru plan ID'lerini bu alana yazmayıp `NULL` bırakmıştır. Plan-müşteri ilişkisi ise `customer_installment_plans` tablosunda ve açıklama alanında tam olarak korunmuştur.
3. **Açıklama (`description`) Davranışı:**
   Kaynakta açıklaması dolu olan kayıtların açıklaması aynen korunmuş (`Taksitli Borç (3 Taksit)`, `Taksitli Borç (6 Taksit)` vb.); açıklaması `NULL` olan kayıtlara sistem standardı olarak `'Eski Finansal Hareket'` yazılmıştır.

---

## 4. TAKSİT PLANLARI, TAKSİT KALEMLERİ VE TAHSİLATLAR

### 1. Taksit Planları Mutabakatı (2 Plan)

1. **Aktif Plan (`plan-19d3e9a9-242e-4b34-acf7-c5ca2a5aa160`):**
   - Müşteri: `48c82bec-b95f-4eee-aff1-a7a2ba933295`
   - Toplam Tutar: Kaynak `10,000.00 TL` $\rightarrow$ Hedef `1,000,000 kuruş` (Fark: 0)
   - Peşinat: Kaynak `3,200.00 TL` $\rightarrow$ Hedef `320,000 kuruş` (Fark: 0)
   - Taksit Sayısı: 3 | Durum: `active` | Silinme: `is_deleted = 0`
   - Master Borç Kaydı: `trans-debt-d541780b-91ec-4d42-bdca-29f3b13f80aa` (`MANUAL_DEBT`, `1,000,000 kuruş`)
   - Peşinat Tahsilat Kaydı: `trans-col-e9a384dc-74db-4ade-b14b-22febc61f102` (`COLLECTION`, `320,000 kuruş`)
2. **İptal Edilmiş Plan (`plan-6effa275-9766-475c-8484-ab2e1e88d549`):**
   - Müşteri: `cust-1788335851742129-7685`
   - Toplam Tutar: Kaynak `12,000.00 TL` $\rightarrow$ Hedef `1,200,000 kuruş` (Fark: 0)
   - Peşinat: Kaynak `120.00 TL` $\rightarrow$ Hedef `12,000 kuruş` (Fark: 0)
   - Taksit Sayısı: 6 | Durum: `cancelled` | Silinme: `is_deleted = 1`
   - Master Borç Kaydı: `trans-debt-a32140da-c933-44f0-9edb-e03f68c71932` (`MANUAL_DEBT`, `1,200,000 kuruş`)
   - Peşinat Tahsilat Kaydı: `trans-col-819068d3-54cb-4ea3-9b0d-8ca5fdf84e5b` (`COLLECTION`, `12,000 kuruş`)

### 2. Taksit Kalemleri Mutabakatı (9 Kalem)

| Taksit ID | Bağlı Plan | Taksit No | Kaynak Tutar | Hedef (Kuruş) | Vade Tarihi | Durum | Silinmiş? | Eşleşen Tahsilat ID |
|---|---|---|---|---|---|---|---|---|
| `inst-ab6352d3...` | `plan-19d3e9a9...` | 1 | `-4,465.32 TL` | `-446,532` | 2026-11-09 | `pending` | Hayır | `NULL` |
| `inst-a3b52b73...` | `plan-19d3e9a9...` | 2 | `2,266.66 TL` | `226,666` | 2026-12-09 | `paid` | Hayır | `trans-col-a934ff71...` |
| `inst-483f14cf...` | `plan-19d3e9a9...` | 3 | `2,266.66 TL` | `226,666` | 2027-01-09 | `paid` | Hayır | `trans-col-be564adb...` |
| `inst-5b27d607...` | `plan-6effa275...` | 1 | `1,980.00 TL` | `198,000` | 2026-11-10 | `cancelled` | Evet (1) | `trans-col-dc53145f...` |
| `inst-584f2ecd...` | `plan-6effa275...` | 2 | `1,980.00 TL` | `198,000` | 2026-12-10 | `cancelled` | Evet (1) | `NULL` |
| `inst-ae065185...` | `plan-6effa275...` | 3 | `1,980.00 TL` | `198,000` | 2027-01-10 | `cancelled` | Evet (1) | `NULL` |
| `inst-f30abb97...` | `plan-6effa275...` | 4 | `1,980.00 TL` | `198,000` | 2027-02-10 | `cancelled` | Evet (1) | `NULL` |
| `inst-69e03a7d...` | `plan-6effa275...` | 5 | `1,980.00 TL` | `198,000` | 2027-03-10 | `cancelled` | Evet (1) | `NULL` |
| `inst-e514e227...` | `plan-6effa275...` | 6 | `1,980.00 TL` | `198,000` | 2027-04-10 | `cancelled` | Evet (1) | `NULL` |

### 3. Taksit ve Senet Tahsilatları (8 Tahsilat)

8 adet taksit açıklamalı tahsilat hareketinin tamamı incelenmiş, parçalı tahsilatların matematiksel toplamı doğrulanmıştır:

- **Plan 1 Tahsilatları (Toplam: 7,733.32 TL / 773,332 kuruş):**
  - `trans-col-e9a384dc...`: `3,200.00 TL` (`320,000 kuruş`) — Taksit Peşinatı
  - `trans-col-a934ff71...`: `2,266.66 TL` (`226,666 kuruş`) — 2. Taksit Tahsilatı
  - `trans-col-b0021af1...`: `200.00 TL` (`20,000 kuruş`) — 3. Taksit Parçalı Tahsilatı
  - `trans-col-a5cc83a3...`: `1,000.00 TL` (`100,000 kuruş`) — 3. Taksit Parçalı Tahsilatı
  - `trans-col-b2a37ff4...`: `100.00 TL` (`10,000 kuruş`) — 3. Taksit Parçalı Tahsilatı
  - `trans-col-be564adb...`: `966.66 TL` (`96,666 kuruş`) — 3. Taksit Kalan Tahsilatı (200 + 1000 + 100 + 966.66 = 2,266.66 TL)
- **Plan 2 Tahsilatları (Toplam: 2,020.00 TL / 202,000 kuruş):**
  - `trans-col-819068d3...`: `120.00 TL` (`12,000 kuruş`) — Taksit Peşinatı
  - `trans-col-dc53145f...`: `1,900.00 TL` (`190,000 kuruş`) — 1. Taksit Tahsilatı
- **Genel Taksit Tahsilatı Toplamı:** **`9,753.32 TL`** $\equiv$ **`975,332 kuruş`**. Fark: **0 kuruş**.

### 4. Mükerrer Borç Üretmeme İlkesi

Plan sözleşme tutarı (`total_amount`), taksit kalemleri toplamı (`sum(installments)`) ve defterdeki master borç (`manual_debt`) ayrı kavramlardır. Sistemde yalnızca `financial_transactions` içindeki `manual_debt` ve `collection` kayıtları deftere işlenmiş, taksit planı veya taksit satırları cariye mükerrer borç/alacak olarak eklenmemiştir.

---

## 5. MÜŞTERİ BAZINDA BAĞIMSIZ BAKİYE MUTABAKATI (584 MÜŞTERİ)

### 1. Kaynak Defter Etki Formülü (`v_customer_ledger_effect`)

Doğrudan SQLite `raw_nutopia_v60.db` şemasından alınan görünüm tanımı:
```sql
CREATE VIEW v_customer_ledger_effect AS
SELECT 
  id, customer_id, type, amount, paid_amount, debt_amount, reference_id, created_at, is_deleted,
  CASE 
    WHEN COALESCE(is_deleted, 0) != 0 THEN 0.0
    WHEN type IN ('sale', 'manual_debt') THEN -(CASE WHEN debt_amount > 0 THEN debt_amount ELSE (amount - paid_amount) END)
    WHEN type IN ('payment', 'collection') THEN paid_amount
    WHEN type = 'cancellation' THEN (CASE WHEN debt_amount > 0 THEN debt_amount ELSE (amount - paid_amount) END)
    WHEN type = 'refund' AND paid_amount = 0 THEN amount
    ELSE 0.0
  END AS balance_effect
FROM financial_transactions
```

### 2. 584 Müşteri Bağımsız Karşılaştırma Sonuçları

- **Kaynak `customers.balance` Genel Toplamı:** `-134,500.68 TL` (`-13,450,068 kuruş`)
- **Kaynak `v_customer_ledger_effect` Genel Toplamı:** `-134,500.68 TL` (`-13,450,068 kuruş`)
- **Hedef `customers.balance_cents` Genel Toplamı:** `-13,450,068 kuruş` (`-134,500.68 TL`)
- **Kontrol 1: Kaynak Bakiye vs Kaynak Defter Etkisi:**
  - Uyuşmazlık: **0 MÜŞTERİ (%100 MUTABAKAT)**.
- **Kontrol 2: Kaynak Bakiye vs Hedef Kuruş Bakiye:**
  - Gerçek Müşterilerde Uyuşmazlık: **0 MÜŞTERİ (%100 MUTABAKAT)**.
  - Açıklanan İstisna: Kaynakta `id = ""` (boş string) olan 1 adet "Peşin Müşteri" satırı (0 TL bakiyeli). Bu satır cari müşteri olmadığından hedef `customers` tablosuna aktarılmamış, nakit satışları ise doğrudan `cash_transactions` tablosuna aktarılmıştır. Kuruş etkisi: 0.

### 3. Satış Kayıtları ile Manuel Borçlar Arasındaki Önemli Adli Fark

- **Manuel Borçlar (`manual_debt`):** 54 kaydın tamamında `paid_amount = 0.0` ve `debt_amount = amount` olduğundan, defter etkisi brüt tutarın aynısıdır (`-103,351.00 TL`). Hedefteki `ledger_entries` satırları ile `customers.balance_cents` bire bir örtüşür.
- **Satış Kayıtları (`sale`):** Eski Pos yazılımında peşin veya kısmi tahsilat yapılan satışlarda tahsilat (`paid_amount`) ayrı bir `payment` satırı açılmadan doğrudan satış satırına yazılmıştır (807 carili satışta brüt 1,250,477.40 TL'nin 397,576.50 TL'si satış anında peşin ödenmiştir). Bu nedenle `ledger_entries` brüt satışları listelerken, müşteri bakiyesi net alacak-verecek dengesini kuruşu kuruşuna (`-134,500.68 TL`) yansıtmaktadır.

---

## 6. TESTLERİN BAĞIMSIZLIĞI VE ADLİ DENETİM TESTİ

### 1. Stage 64 Testinin İncelenmesi

- **Kaynak Veri:** `test/core_next/stage10_12_64_full_scale_export_import_test.dart`, 60 MB'lık ham SQLite veritabanını (`raw_nutopia_v60.db`) okumuştur; sentetik fixture kullanmamıştır.
- **Hedef İncelenmesi:** Test `setUpAll` bloğunda `MigrationBridgeEngine` çağırarak hedef veritabanını oluşturmuş ve göç motorunun canlı çıktısını denetlemiştir.
- **Sınırlılık:** Kayıtları genel toplamlar ve sayaçlar düzeyinde doğrulamış; satır satır 1-to-1 ID eşleştirmesi yapmamıştır.

### 2. Yeni Stage 66 Bağımsız Denetim Testi

- **Test Dosyası:** `test/core_next/stage10_12_66_nutopia_promissory_independent_audit_test.dart`
- **Salt-Okunur İzolasyon:** Her iki veritabanı `openReadOnlyDatabase` ile salt-okunur açılmış; hedefte ve kaynakta hiçbir mutasyon, tablo oluşturma, göç veya silme yapılmamıştır.
- **İçerik:**
  - 54 manuel borcun ID, müşteri, tutar, kuruş ve açıklama bazında 1-to-1 eşleşmesi
  - 2 taksit planı, master borçları ve peşinat tahsilatları doğrulaması
  - 9 taksit kaleminin vade, tutar ve durum doğrulaması
  - 8 taksit tahsilatının kuruş doğrulaması
  - 584 müşterinin tamamında bire bir bakiye doğrulaması
  - Satış tablosu ile manuel borç ID'lerinin kesişiminin 0 olduğu kanıtı

```powershell
flutter test test/core_next/stage10_12_66_nutopia_promissory_independent_audit_test.dart
```
**Sonuç:** `00:04 +9: All tests passed! (Exit Code: 0, 4.8s)`

```powershell
flutter analyze test/core_next/stage10_12_66_nutopia_promissory_independent_audit_test.dart
```
**Sonuç:** `No issues found! (ran in 4.8s, Exit Code: 0)`

---

## 7. ÇALIŞTIRILAN KOMUTLAR VE ÇIKIŞ KODLARI

| Komut | Amaç | Exit Code | Gerçek Sonuç |
|---|---|---|---|
| `git rev-parse HEAD; git branch; git diff --check` | Git durum ve diff doğrulaması | 0 | HEAD: `28c158d88...`, Branch: `main`, Diff: Clean |
| `python scratch/stage66_file_check.py` | Dosya boyutları, SHA-256 ve SQLite integrity kontrolü | 0 | Kaynak ve Hedef integrity: `ok`, FK: 0 |
| `python scratch/stage66_match_manual_debts.py` | 54 manuel borcun satır satır 1-to-1 eşleştirilmesi | 0 | 54/54 eşleşti, 0 kayıp, 0 mükerrer |
| `python scratch/stage66_plans_and_collections.py` | 2 plan, 9 taksit ve 8 tahsilatın doğrulanması | 0 | Kuruşu kuruşuna 0 farkla eşleşti |
| `python scratch/stage66_customer_reconciliation.py`| 584 müşteri bakiye ve defter etkisi mutabakatı | 0 | 584 müşteride kaynak bakiye vs defter uyuşmazlığı: 0 |
| `flutter test test/core_next/stage10_12_66_nutopia_promissory_independent_audit_test.dart` | Salt-okunur bağımsız denetim test paketi | 0 | 9 testin tamamı başarılı (Passed) |
| `flutter analyze test/core_next/stage10_12_66_nutopia_promissory_independent_audit_test.dart` | Statik linter denetimi | 0 | `No issues found!` |

---

## 8. ÖNCEKİ RAPORLA ÇELİŞEN BULGULAR VE AÇIKLAMALAR

1. **`reference_sale_id` vs `reference_id` Nüansı:**
   Önceki raporlarda taksit planına bağlı manuel borçların referansının hedefte doğrudan `reference_sale_id` kolonunda yer aldığı izlenimi doğabilirdi. Yapılan bağımsız denetimde, hedefteki kolonun `sales` tablosuna FK olduğu, bu yüzden plan ID'sinin bu kolona yazılmadığı, ancak plan ilişkisinin `customer_installment_plans` tablosunda ve açıklama alanında tam olarak korunduğu kanıtlanmıştır.
2. **Peşin Müşteri Satırı (1 Adet):**
   Kaynakta `id = ""` olan ve 0 TL bakiyesi bulunan "Peşin Müşteri" satırının cari tablosuna değil kasa hareketlerine yönlendirildiği netleştirilmiştir. 583 gerçek müşterinin tamamında bakiye mutabakatı %100 kusursuzdur.

---

## 9. NİHAİ BAĞIMSIZ DENETİM KARARI

Aşağıdaki zorunlu şartların tamamı kanıtlandığından:
1. Kaynak ve hedef dosyalarının varlığı, boyutu, SHA-256 özeti ve `integrity_check` sonuçları doğrulanmıştır.
2. 54 manuel borç kaydı işlem bazında (1-to-1) kuruşu kuruşuna (103,351.00 TL / 10,335,100 kuruş) eşleşmiştir.
3. 2 taksit planı, 9 taksit kalemi ve 8 taksit tahsilatı eksiksiz ve mükerrersiz eşleşmiştir.
4. 584 müşteri için bakiye farkları adli formülle incelenmiş ve 0 hata ile çözümlenmiştir.
5. Testlerin gerçek salt-okunur veritabanı üzerinde çalıştığı ve hedefi mutasyona uğratmadığı kanıtlanmıştır.
6. Açıklanamayan hiçbir tutar veya referans farkı kalmamıştır.

**SONUÇ KODU:**  
`NUTOPIA_MANUAL_PROMISSORY_INDEPENDENT_AUDIT_PASS_ISOLATED_ONLY`

---

## 10. SON GÜVENLİK DURUMU

CUTOVER: NOT APPROVED  
LIVE DATABASE WRITES: NOT PERFORMED  
CORE NEXT SALES ENGINE: DISABLED  
DATABASE ROUTING HOOK: NULL  
OLD DATABASE RETIREMENT: NOT APPROVED  
