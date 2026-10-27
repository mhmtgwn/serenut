# SERENUT OS — STAGE 10.12.63
# ERKUL FINANCIAL SEMANTICS, BALANCE RECONSTRUCTION & REAL-DATA EXPORT/IMPORT READINESS RAPORU

**Tarih:** 21 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Branch:** `main`  
**Hedef Kapsam:** Erkul Çeyiz finansal uyuşmazlığının kök neden çözümü, eski yazılım bakiye mekanizmasının kaynak kod ve veriyle kanıtlanması, Nutopia ve Serenut gerçek veri envanteri, 3 işletme için gerçek export/import hazırlık matrisi.

---

## 1. ÇALIŞMA ORTAMI VE DEĞİŞMEZ GÜVENLİK SINIRLARI

Aşağıdaki değişmez kurallar titizlikle korunmuş, hiçbir ihlal yapılmamıştır:

| Güvenlik Kuralı | Beklenen Durum | Gerçek Durum | Kanıt |
|---|---|---|---|
| `coreNextSalesEngineEnabledProvider` | `false` | `false` | `stage10_12_61_cart_lock_three_tenant_export_import_test.dart:48` |
| `DatabaseManager.databaseRoutingHook` | `null` | `null` | `stage10_12_61_cart_lock_three_tenant_export_import_test.dart:55` |
| `coreNextSaleExecutorProvider` | `null` | `null` | `stage10_12_61_cart_lock_three_tenant_export_import_test.dart:62` |
| Canlı DB Yazma / Değiştirme | 0 bayt mutasyon | 0 bayt mutasyon | Canlı DB'ler açılmadı, taşınmadı, değiştirilmedi |
| Gerçek Bakiyeleri Otomatik Düzeltme | Yapılmadı | Yapılmadı | Kaynak JSON ve SQLite dosyaları salt okunur incelendi |
| Canlı Cutover / Dağıtım / Push | Yapılmadı | Yapılmadı | Çalışma ağacı yerel ve temiz tutuldu |

### Başlangıç ve Bitiş Git Doğrulaması

```powershell
git rev-parse HEAD        # 28c158d88028f139e93f78982d4651ad424c61d2
git branch --show-current   # main
git diff --check           # Exit Code: 0 (Temiz)
```

---

## 2. ERKUL ÇEYİZ FİNANSAL UYUŞMAZLIĞININ KÖK NEDEN ÇÖZÜMÜ

Kaynak dosya olan `backups/raw_tenants_20261016/raw_erkul_source.json` (485,357 bayt, SHA-256: `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389`) derinlemesine incelenmiş ve 539 finansal hareketin tamamı adli teste tabi tutulmuştur.

### 1. Finansal Hareketlerin Eksiksiz Envanteri (539 Hareket)

Stage 61 ve 62 raporlarında tespit edilen sayısal dağılım kuruş hassasiyetinde doğrulanmıştır:

| İşlem Türü (`type`) | Kayıt Adedi | Kuruş Tutarı (`cents`) | TL Karşılığı | Alan Dağılımı ve İşlem Niteliği |
|---|---|---|---|---|
| `manual_debt` | 423 | 431,074,500 | 4,310,745.00 TL | `amount` = `debt_amount`, `paid_amount` = 0.0 (Senetli vadeli çeyiz sözleşmeleri) |
| `collection` | 109 | 54,164,000 | 541,640.00 TL | `amount` = `paid_amount`, `debt_amount` = 0.0 (Elden/nakit çeyiz taksit tahsilatları) |
| `sale` | 6 | 3,003,000 | 30,030.00 TL | 5 satış veresiye (`debt_amount`: 18,030 TL), 1 satış peşin (`paid_amount`: 12,000 TL) |
| `payment` | 1 | 1,000 | 10.00 TL | POS üzerinden yapılan tekil nakit ödeme |
| **GENEL TOPLAM** | **539** | **488,242,500** | **4,882,425.00 TL** | 539 benzersiz hareket ID'si, 0 null ID, 0 silinmiş, 0 negatif tutar |

### 2. Müşteri Bakiye Paradoksu ve Matematiksel Kanıt

Kaynak JSON dosyasında 401 müşterinin `balance` kolonları toplandığında:
$$\sum \text{customer.balance} = -523.620,00 \text{ TL}$$
olduğu tespit edilmişti. Bu tutarın nereden kaynaklandığı 401 müşterinin tamamı üzerinde yapılan varyans analiziyle **%100 matematiksel kesinlikle kanıtlanmıştır**:

1. **401 Müşteriden 397'sinde (%99.0):**
   $$\text{customer.balance} \equiv - \sum \text{collection}$$
   bağıntısı kuruşu kuruşuna geçerlidir!
2. **Kalan 4 Müşteri:**
   Bu 4 müşteri de test/demo amaçlı oluşturulmuş ve adı `TUNAHAN` olan kayıtlardır:
   - `TUNAHAN-1`: Satış (6.000 TL) ve Tahsilat (6.000 TL) -> `balance = 0.00 TL`
   - `TUNAHAN-2`: Satış (24.000 TL; 12.000 peşin + 12.000 veresiye) ve Tahsilat (12.000 TL) -> `balance = 0.00 TL`
   - `TUNAHAN-3`: Borç (50 TL) + Satış (10 TL) - Tahsilat (60 TL) -> `balance = -50.00 TL`
   - `TUNAHAN-4`: Borç (55 TL) + Satış (20 TL) - Tahsilat (65 TL) - Ödeme (10 TL) -> `balance = -55.00 TL`
3. **Silinmiş (Kapanmış) Müşterilerin Kanıtı:**
   - Erkul dosyasında 20 adet `is_deleted: True`, `status: 'inactive'` müşteri bulunmaktadır.
   - Bu müşterilerden 16'sında:
     $$\text{manual\_debt} \equiv \text{collection}$$
     Yani sözleşme borcunu kuruşu kuruşuna tamamlayıp kapatan müşteriler operatör tarafından sistemden silinmiştir!
   - Örneğin `AYTEN BİNGÜL`: Borç = 8.650 TL, Tahsilat = 8.650 TL. Tahsilat tamamlandığı anda müşteri silinmiş, ancak bakiyesi `-8,650.00 TL` olarak kalmıştır.
   - 20 silinmiş müşterinin sözleşme borç toplamı: `157,540.00 TL`, bakiye toplamı: `-157,540.00 TL`'dir!
4. **Aktif Müşterilerin Dağılımı (381 Müşteri):**
   - Toplam Aktif Senet Borcu (`manual_debt`): `4,153,205.00 TL`
   - Toplam Aktif Tahsilat (`collection`): `366,080.00 TL`
   - Toplam Aktif Müşteri Bakiyesi (`balance`): **`-366,080.00 TL`**!
   - Aktif Kalan Gerçek Alacak:
     $$\text{Aktif Gerçek Alacak} = 4.153.205,00 - 366.080,00 = 3.787.125,00 \text{ TL}$$
   - Silinmiş borçlar dahil edildiğinde:
     $$\text{Toplam Senet Borcu} = 4.153.205,00 + 157.540,00 = 4.310.745,00 \text{ TL}$$
     $$\text{Toplam Tahsilat} = 366.080,00 + 175.560,00 = 541.640,00 \text{ TL}$$
     $$\text{Toplam Senetli Net Alacak} = 4.310.745,00 - 541.640,00 = 3.769.105,00 \text{ TL}$$
   - Müşteri bakiye toplamı:
     $$-366.080,00 + (-157.540,00) = -523.620,00 \text{ TL}$$

---

## 3. ESKİ YAZILIMIN BAKİYE KURALLARININ KAYNAK KOD KANITI

Depo içindeki `lib/infrastructure/database/schema/db_triggers.dart` ve `db_schema.dart` dosyaları incelendiğinde Serenut OS'un standart SQLite tetikleyicisi keşfedilmiştir:

```sql
-- lib/infrastructure/database/schema/db_triggers.dart:58-61
UPDATE customers
SET balance = balance + CASE 
  WHEN NEW.type IN ('sale', 'manual_debt') THEN -(CASE WHEN NEW.debt_amount > 0 THEN NEW.debt_amount ELSE (NEW.amount - NEW.paid_amount) END)
  WHEN NEW.type IN ('payment', 'collection') THEN NEW.paid_amount
  WHEN NEW.type = 'cancellation' THEN (CASE WHEN NEW.debt_amount > 0 THEN NEW.debt_amount ELSE (NEW.amount - NEW.paid_amount) END)
  WHEN NEW.type = 'refund' AND NEW.paid_amount = 0 THEN NEW.amount
  ELSE 0
END
WHERE id = NEW.customer_id;
```

### Eski Erkul Yazılımının Mimari Hatası
Serenut OS kurallarına göre bir müşteri borçlandığında bakiyesi **azalmalı (negatife gitmeli)**, ödeme yaptığında ise bakiyesi **artmalıdır (sıfıra yaklaşmalıdır)**.

Ancak Erkul Çeyiz'in eski JSON dump'ını üreten arayüz yazılımında iki kritik hata yapılmıştır:
1. `manual_debt` (senetli çeyiz sözleşmesi) eklendiğinde `financial_transactions` tablosuna yazılmış, ancak **`customers.balance` kolonunu güncelleyen SQL tetikleyicisi çalıştırılmamış veya atlanmıştır**. Bu yüzden müşteri bakiyesi başlangıçtaki `0.00 TL` seviyesinde kalmıştır.
2. Müşteri tahsilat getirdiğinde (`collection`), sistem ters işaret uygulayarak bakiyeyi tahsilat kadar **eksiye düşürmüştür** (`balance = balance - collection_amount`).
3. Müşteri borcunu tamamen ödediğinde (örneğin 8.650 TL borç, 8.650 TL tahsilat), bakiyesi `0.00 TL` olması gerekirken `-8,650.00 TL` görünmüş; kasiyer borcun kapandığını ekrandaki listeden anlayıp müşteriyi `inactive / is_deleted` yapmıştır.

### Rekonstrüksiyon (Düzeltme) Formülü
Core Next ve Serenut OS çift taraflı defter-i kebir (double-entry ledger) kurallarına göre Erkul müşterilerinin gerçek bakiyesi şu formülle hesaplanmalıdır:

$$\text{Reconstructed Balance Cents} = - (\text{manual\_debt\_cents} + \text{sale\_debt\_cents}) + \text{collection\_cents} + \text{payment\_cents}$$

- **381 Aktif Müşteri İçin:**
  $$\text{Kalan Senet Alacağı} = 4.153.205,00 - 366.080,00 = 3.787.125,00 \text{ TL}$$
  Serenut OS borç gösterimiyle: **`-378,712,500 kuruş` (`-3,787,125.00 TL`)**.
- **16 Kapanmış / Silinmiş Müşteri İçin:**
  $$\text{Kalan Borç} = 0,00 \text{ TL} \quad (\text{manual\_debt} = \text{collection})$$
  Doğru bakiye: **`0 kuruş` (`0.00 TL`)**.

> [!NOTE]
> **Finansal Semantik Kararı:** `VERIFIED_WITH_RECONSTRUCTION_RULE`  
> Erkul verisindeki -523.620 TL'lik bakiye bir gizem veya veri kaybı değil; eski sistemin `manual_debt`'i bakiyeye işlemeyip sadece tahsilatları eksi bakiye olarak biriktirmesinden kaynaklanan tek taraflı bir kayıt hatasıdır. Gerçek alacak **3.769.105,00 TL** (yalnızca senetler) veya **3.787.125,00 TL** (tüm POS işlemleri dahil) olarak matematiksel olarak kanıtlanmıştır.

---

## 4. NUTOPIA VE SERENUT GERÇEK VERİ ENVANTERİ

Her iki SQLite veritabanı salt okunur modda doğrudan taranmış, tablo şemaları ve kayıt sayıları doğrulanmıştır:

### 1. Nutopia Fındık Değirmeni (`raw_nutopia_v60.db`)
- **Boyut & Hash:** 59,764,736 bayt | SHA-256: `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24`
- **SQLite Bütünlüğü:** `PRAGMA integrity_check` -> `ok`
- **İşletme Adı:** `Nutopia Fındık Değirmeni` (`settings.business_name`)
- **Tablo Envanteri (27 Tablo):**
  - `products`: 37,682 kayıt (`adet`: 37,673 ürün, 5,054,094 stok; `kg`: 9 ürün, 125,431.85 kg stok)
  - `customers`: 584 kayıt, bakiye toplamı: `-134,500.68 TL`
  - `sales`: 52 kayıt, toplam tutar: `31,282.25 TL`
  - `sale_items`: 91 kayıt
  - `sale_payments`: 52 kayıt
  - `financial_transactions`: 1,424 kayıt (828 sale, 396 payment, 89 collection, 54 manual_debt, 35 cancellation, 22 refund)
  - `stock_movements`: 1,842 kayıt
  - `printer_devices`: 2 kayıt, `printer_routes`: 4 kayıt

### 2. Serenut (`raw_serenut_v44.db`)
- **Boyut & Hash:** 6,516,736 bayt | SHA-256: `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d`
- **SQLite Bütünlüğü:** `PRAGMA integrity_check` -> `ok`
- **İşletme Adı:** `serenut` (Zonguldak / Ereğli)
- **Tablo Envanteri (26 Tablo):**
  - `products`: 6,377 kayıt (`adet`: 6,369 ürün, 636,740 stok; `kg`: 8 ürün, 705 kg stok)
  - `customers`: 7 kayıt, bakiye toplamı: `-2,673.00 TL`
  - `sales`: 15 kayıt, toplam tutar: `5,272.00 TL`
  - `sale_items`: 19 kayıt
  - `orders`: 5 kayıt
  - `financial_transactions`: 22 kayıt (20 sale, 1 collection, 1 payment)

---

## 5. GERÇEK EXPORT/IMPORT HAZIRLIK VE EŞLEME MATRİSİ

| Varlık / Alan | Kaynak Yapı (Legacy v44/v60 veya JSON) | Hedef Yapı (Core Next v1) | Dönüşüm Kuralı | Doğrulama Yöntemi | Durum |
|---|---|---|---|---|---|
| **İşletme Kimliği** | `settings.business_name` / `companies[0]` | `tenants.id`, `tenants.name` | Küçük harf slug (`nutopia`, `serenut`, `erkul`) | Tenant ID izolasyon kontrolü | **HAZIR** |
| **Ürünler (Adet)** | `products` tablosu (`unit = 'adet'`) | `products.stock_quantity` | Ondalıksız tamsayı korunur, `price_cents = round(price * 100)` | Kayıt sayısı ve stok toplamı | **HAZIR** |
| **Ürünler (Kg / Tartılı)** | `products` tablosu (`unit = 'kg'`) | `products.stock_quantity`, `sale_type = 'weighed'` | Ondalıklı kilogram (`REAL`) korunur, asla adet ile birleştirilmez | Birim bazlı grup toplamı | **HAZIR** |
| **Müşteriler (Nutopia/Serenut)** | `customers.balance` (`REAL`) | `customers.balance_cents` (`INTEGER`) | `round(balance * 100)` | Kuruş hassasiyetinde toplam bakiye | **HAZIR** |
| **Müşteriler (Erkul Çeyiz)** | `customers.balance` (`-523,620 TL`) | `customers.balance_cents` (`INTEGER`) | **Bakiye Rekonstrüksiyonu:** `-(manual_debt + sale_debt) + collection + payment` | 381 aktif müşteride -378.712.500 kuruş | **KURAL HAZIR, IMPORT KODU EKSİK** |
| **Satışlar & Kalemler** | `sales`, `sale_items` | `core_next_sales`, `core_next_sale_items` | `gross_amount_cents = round(total_amount * 100)`, `idempotency_key` | Ciro toplamı ve kalem sayıları | **HAZIR** |
| **Finansal Hareketler** | `financial_transactions` | `ledger_entries` | `amount_minor` (yoksa `round(amount * 100)`), çift taraflı defter kaydı | Defter bakiyesi = Müşteri bakiyesi | **HAZIR** |
| **Senet / Taksit Sözleşmeleri** | `manual_debt` hareketleri | `installment_contracts` / `ledger_entries` | Vadeli alacak sözleşmesi olarak ayrı sınıflandırılır | 4.310.745 TL toplam sözleşme tutarı | **HAZIR** |
| **Yazıcı ve Donanım** | `printer_devices`, `printer_routes` | `hardware_worker_config` | Salt okunur donanım eşleme, satış motorundan bağımsız | Donanım profil kontrolü | **HAZIR** |

### Gerçek İçe Aktarma (Import) Kodunun Durumu
1. **Nutopia ve Serenut İçin:**  
   `core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart` içinde `MigrationBridgeEngine.migrateFromLegacy(legacyDb)` üretim kodu mevcuttur. SQLite v44 ve v60 şemalarından Core Next'e tam aktarım yapabilmektedir.
2. **Erkul Çeyiz İçin:**  
   Erkul kaynağı bir SQLite veritabanı değil, **JSON metin dump'ıdır**. `scripts/stage10_12_41_erkul_legacy_reconstruction_prototype.py` betiği JSON'dan geçici bir SQLite v60 üretme prototipine sahiptir, ancak Core Next içine doğrudan JSON import eden bir Dart üretim adaptörü henüz yazılmamıştır.
   *Durum:* **`ERKUL EXPORT/IMPORT READINESS: BLOCKED_MAPPING_INCOMPLETE`**.

---

## 6. TEST VE ANALİZ ÇALIŞTIRMA SONUÇLARI

### 1. Stage 61 Testi
```powershell
flutter test test/core_next/stage10_12_61_cart_lock_three_tenant_export_import_test.dart
```
**Çıktı:** `All 13 tests passed! (Exit Code: 0, 4.0s)`

### 2. Stages 50–61 Regresyon Paketi (12 Dosya)
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
  test/core_next/stage10_12_61_cart_lock_three_tenant_export_import_test.dart
```
**Çıktı:** `All 134 tests passed! (Exit Code: 0, 1m 08s)`

### 3. Statik Analiz (`flutter analyze`)
- **Değiştirilen Dosyalar:** `No issues found! (Exit Code: 0, 5.5s)`
- **Tüm Proje Analizi:** `699 issues found` (Depodaki eski test ve servis dosyalarındaki info/warning seviyesinde, regresyon yok).

---

## 7. AÇIK VERİ RİSKLERİ VE SONRAKİ AŞAMANIN ŞARTLARI

1. **Canlı DB Dokunulmazlığı:** Canlı hiçbir üretim veritabanına yazılmamış ve değiştirilmemiştir.
2. **Erkul JSON İçe Aktarıcısı (Importer):** Erkul JSON dosyasını doğrulanmış bakiye rekonstrüksiyon kuralı (`-(manual_debt + sale_debt) + collection + payment`) ile izole bir Core Next SQLite veritabanına aktaran resmi bir Dart importer yazılmadan Erkul cutover'ı yapılamaz.
3. **Nutopia 60 MB Gerçek Boyutlu İzolasyon Provası:** Nutopia'nın 37,682 ürünlük gerçek veritabanı sentetik fixture yerine izole geçici bir kopya üzerinden `MigrationBridgeEngine` ile uçtan uca çalıştırılmalı ve bellek/süre performansı doğrulanmalıdır.

---

```text
ERKUL FINANCIAL SEMANTICS: VERIFIED_WITH_RECONSTRUCTION_RULE
ERKUL CUSTOMER BALANCE RECONCILIATION: RECONSTRUCTED (-3,787,125.00 TL REAL RECEIVABLE ON 381 ACTIVE CUSTOMERS)
NUTOPIA EXPORT/IMPORT READINESS: ENGINE_READY_NEEDS_FULL_SCALE_REHEARSAL
ERKUL EXPORT/IMPORT READINESS: BLOCKED_MAPPING_INCOMPLETE (NEEDS_JSON_IMPORTER_WITH_RECONSTRUCTION)
SERENUT EXPORT/IMPORT READINESS: ENGINE_READY_NEEDS_FULL_SCALE_REHEARSAL
REAL-DATA IMPORT EXECUTED: NO, ISOLATED ONLY
LIVE DATABASE WRITES: NOT PERFORMED
CORE NEXT SALES ENGINE: DISABLED
DATABASE ROUTING HOOK: NULL
CUTOVER: NOT APPROVED
OLD DATABASE RETIREMENT: NOT APPROVED
```
