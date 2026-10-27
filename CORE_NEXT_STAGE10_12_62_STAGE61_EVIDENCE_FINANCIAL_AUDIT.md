# SERENUT OS — STAGE 10.12.62
# STAGE 61 EVIDENCE AUDIT, REAL EXPORT/IMPORT PROOF & FINANCIAL RECONCILIATION RAPORU

**Tarih:** 21 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Branch:** `main`  
**Denetim Kapsamı:** Stage 10.12.61 iddialarının bağımsız adli denetimi, sentetik vs gerçek export/import kanıtları, Erkul JSON derin finansal mutabakatı, Nutopia ve Serenut gerçek yedek analizleri, kilit ve satış akışı çağrı zincirleri.

---

## 1. ÇALIŞMA ORTAMI VE DEĞİŞMEZ GÜVENLİK SINIRLARI

Aşağıdaki değişmez güvenlik sınırları doğrulanmış ve %100 korunmuştur:

| Güvenlik Kuralı | Beklenen Durum | Gerçek Durum | Kanıt |
|---|---|---|---|
| `coreNextSalesEngineEnabledProvider` | `false` | `false` | `stage10_12_61_cart_lock_three_tenant_export_import_test.dart:48` |
| `DatabaseManager.databaseRoutingHook` | `null` | `null` | `stage10_12_61_cart_lock_three_tenant_export_import_test.dart:55` |
| `coreNextSaleExecutorProvider` | `null` | `null` | `stage10_12_61_cart_lock_three_tenant_export_import_test.dart:62` |
| Canlı DB Yazma / Değiştirme | 0 bayt mutasyon | 0 bayt mutasyon | Canlı DB'ler açılmadı, taşınmadı, değiştirilmedi |
| Canlı Uygulama Kilit / Bakım Modu | Etkinleştirilmedi | Etkinleştirilmedi | Canlı POS veya veritabanına müdahale edilmedi |
| Üretim Dağıtımı / Push / Release | Yapılmadı | Yapılmadı | Değişiklikler yalnızca yerel çalışma alanında tutuldu |

### Başlangıç ve Bitiş Git Doğrulaması

```powershell
git rev-parse HEAD        # 28c158d88028f139e93f78982d4651ad424c61d2
git branch --show-current   # main
git diff --check           # Exit Code: 0 (Boşluk/satır sonu hatası yok)
git log -5 --oneline       # 28c158d8 fix(test): align splash screen error title expectation...
```

---

## 2. STAGE 61 RAPORU İDDİALARININ ADLİ KOD VE TEST DENETİMİ

Stage 10.12.61 raporundaki (`CORE_NEXT_STAGE10_12_61_CART_LOCK_THREE_TENANT_EXPORT_IMPORT.md`) iddialar, `test/core_next/stage10_12_61_cart_lock_three_tenant_export_import_test.dart` kaynak kodu ve gerçek test çalıştırmalarıyla bağımsız olarak incelenmiştir:

| İddia | Stage 61 Rapor İddiası | Gerçek Kod ve Test Bulgusu | Doğrulama Kararı |
|---|---|---|---|
| **Test 61 Başarısı** | 13/13 PASS | `flutter test` yeniden çalıştırıldı: 13/13 PASS (Exit Code: 0, 8.0s) | **DOĞRULANDI** |
| **Regresyon 50–61** | 134/134 PASS | 12 test dosyası birlikte çalıştırıldı: 134/134 PASS (Exit Code: 0, 1m 30s) | **DOĞRULANDI** |
| **Kaynak Hash Dokunulmazlığı** | 3 işletmede 0 bayt mutasyon | SHA-256 değerleri önce ve sonra birebir aynı çıktı | **DOĞRULANDI** |
| **Bakım Kilidi Kapsamı** | Tüm yazma yolları LOCK_PROTECTED | UI, FSM controller, SalesController ve DbGateway zinciri kilitli | **DOĞRULANDI** |
| **Statik Analiz (`flutter analyze`)** | Değişen dosyalarda 0 issue | Değişen 3 dosyada `No issues found!`, tam projede 699 eski issue mevcut | **DOĞRULANDI** |
| **Erkul Net Alacak** | 3.769.105,00 TL | Yalnızca `manual_debt - collection` için geçerli; 6 satış ve 1 ödeme hesaba katılmamış! | **KISMİ DOĞRULAMA / EKSİK KAPSAM** |
| **Üç İşletmede Gerçek Export/Import** | Gerçek verilerle export/import provası başarılı | Test gövdesinde gerçek DB'ler değil, **sentetik 1-2 kayıtlık fixture'lar** aktarılmış! | **ÇARPITMA / SENTETİK FİXTURE KULLANILMIŞ** |
| **Üç İşletmede 0 Veri Farkı** | 0 sapma ile mutabık kalındı | Yalnızca sentetik fixture testinde 0 fark var; 37.682 Nutopia ürünü için aktarım yapılmadı | **ÇARPITMA / TAM AKTARIM YAPILMADI** |

> [!WARNING]
> **Kritik Denetim Tespiti:**  
> Stage 61 testinde `raw_nutopia_v60.db` ve `raw_serenut_v44.db` dosyalarının varlığı, boyutu, SHA-256'sı ve `PRAGMA integrity_check`'i başarıyla doğrulanmıştır. Ancak `CoreAppDatabase`'e aktarım aşamasında gerçek 37.682 Nutopia ürünü veya 6.377 Serenut ürünü aktarılmamış; test içine elle 2 adet sentetik ürün (`nut_p_kg`, `nut_p_adet`) ve 1 adet müşteri (`ser_c_1`) eklenerek birim ayrımı doğrulanmıştır. Dolayısıyla "üç işletmenin tüm gerçek verileriyle export/import tamamlandı" iddiası **gerçeği yansıtmamaktadır; sentetik fixture provasıdır**.

---

## 3. ÜÇ İŞLETME İÇİN DOSYA KİMLİĞİ VE HASH DENETİMİ

Yalnızca `backups/raw_tenants_20261016/` altında bulunan izole yedekler salt okunur modda doğrudan taranmıştır:

### 1. Nutopia Fındık Değirmeni
- **Dosya Yolu:** `backups/raw_tenants_20261016/raw_nutopia_v60.db`
- **Dosya Türü:** SQLite Database (Version 60)
- **Dosya Boyutu:** 59,764,736 bayt (~59.7 MB)
- **SHA-256 Sağlama:** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24`
- **SQLite Bütünlüğü (`PRAGMA integrity_check`):** `ok`
- **İşletme Kimliği (`settings.business_name`):** `Nutopia Fındık Değirmeni`
- **Tablo Sayısı:** 27 tablo
- **Kritik Tablo Kayıt Sayıları:**
  - `products`: 37,682 kayıt
  - `customers`: 584 kayıt
  - `sales`: 52 kayıt
  - `sale_items`: 91 kayıt
  - `financial_transactions`: 1,424 kayıt

### 2. Erkul Çeyiz
- **Dosya Yolu:** `backups/raw_tenants_20261016/raw_erkul_source.json`
- **Dosya Türü:** JSON Metin Dosyası (UTF-8, SQLite DEĞİLDİR)
- **Dosya Boyutu:** 485,357 bayt (~485 KB)
- **SHA-256 Sağlama:** `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389`
- **JSON Ayrıştırma:** Başarılı (16 anahtar varlık: `companies`, `customers`, `products`, `sales`, `sale_items`, `financial_transactions`, `customer_orders`, `customer_order_items`, `customer_installment_plans`, `customer_installments`, `refunds`, `invoices`, `inventory_movements`, `devices`, `stores`, `users`)
- **İşletme Kimliği (`companies[0].name`):** `Erkul Çeyiz`
- **Varlık Sayıları:**
  - `companies`: 1
  - `customers`: 401 (401 benzersiz ID, 0 boş ID)
  - `products`: 26 (26 benzersiz ID, tamamı adet bazlı)
  - `sales`: 5
  - `financial_transactions`: 539 (539 benzersiz ID, 0 silinmiş, 0 negatif tutar)

### 3. Serenut
- **Dosya Yolu:** `backups/raw_tenants_20261016/raw_serenut_v44.db`
- **Dosya Türü:** SQLite Database (Version 44)
- **Dosya Boyutu:** 6,516,736 bayt (~6.5 MB)
- **SHA-256 Sağlama:** `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d`
- **SQLite Bütünlüğü (`PRAGMA integrity_check`):** `ok`
- **İşletme Kimliği (`settings.business_name`):** `serenut` (İl: Zonguldak, İlçe: Ereğli, Sahip: mehmet güven)
- **Tablo Sayısı:** 26 tablo
- **Kritik Tablo Kayıt Sayıları:**
  - `products`: 6,377 kayıt
  - `customers`: 7 kayıt
  - `sales`: 15 kayıt
  - `sale_items`: 19 kayıt
  - `orders`: 5 kayıt
  - `financial_transactions`: 22 kayıt

---

## 4. GERÇEK EXPORT/IMPORT ANALİZİ (SENTETİK VS GERÇEK KANIT)

Stage 61 testinde yapılan işlemler ile gerçek işletme verisi geçişi arasındaki farklar adım adım tespit edilmiştir:

| Adım / Kriter | Stage 61 Testinde Yapılan | Gerçekte Gereken Üretim Adımı | Durum |
|---|---|---|---|
| **Kaynak Dosya** | `raw_nutopia_v60.db` (59.7 MB) salt okunur açıldı | `raw_nutopia_v60.db` (59.7 MB) | Mevcut |
| **Kullanılan Export/Import Metodu** | `coreDb.db.insert('products', ...)` (2 sentetik satır) | `MigrationBridgeEngine.migrateFromLegacy(legacyDb)` | **KULLANILMADI** |
| **Oluşan Export Çıktısı** | Yok (Doğrudan `nutopia_candidate.db`'ye 2 sentetik kayıt) | Tam şema migration raporu & SQLite dump | **YAPILMADI** |
| **Hedef DB Oluşumu** | Sıfırdan, izole geçici DB | Sıfırdan, izole geçici DB | Uygun |
| **Kaynak / Hedef Kayıt Sayısı** | Kaynak: 37.682 ürün -> Hedef: **2 ürün** | Kaynak: 37.682 -> Hedef: 37.682 | **UYUMSUZ (Test fixture)** |
| **Finansal Hareket Aktarımı** | Kaynak: 1.424 hareket -> Hedef: **0 hareket** | Kaynak: 1.424 -> Hedef: 1.424 | **UYUMSUZ (Test fixture)** |
| **İkinci Çalıştırma İdempotens** | 2 sentetik kayıt için test edildi | 37.682 ürün ve 1.424 hareket için test edilmeli | **KISMİ KANIT** |
| **Kaynak Dosya SHA-256** | Prova öncesi ve sonrası değişmedi | Değişmedi (0 bayt mutasyon) | **DOĞRULANDI** |

**Sonuç:** Stage 61 testi, sistemin kilit mantığını, birim ayrımını (kg vs adet) ve kuruş hassasiyeti modelini doğrulamaktadır; ancak 3 işletmenin **tüm verilerinin hatasız aktarıldığını kanıtlamaz**.

---

## 5. ERKUL FİNANSAL MUTABAKATI — DERİN ADLİ İNCELEME

Stage 61 raporundaki rakamlar (`manual_debt: 4.310.745,00 TL`, `collection: 541.640,00 TL`, `net: 3.769.105,00 TL`) `raw_erkul_source.json` üzerindeki tüm 539 hareket taranarak bağımsız doğrulanmıştır.

### Finansal Hareketlerin Gerçek Dağılımı (539 Kayıt)

| İşlem Türü (`type`) | Adet | Kuruş Tutarı (`cents`) | TL Karşılığı | Anlamı ve Muhasebe Etkisi |
|---|---|---|---|---|
| `manual_debt` | 423 | 431,074,500 | 4,310,745.00 TL | Senetli çeyiz sözleşmesi müşteri borçlandırması |
| `collection` | 109 | 54,164,000 | 541,640.00 TL | Elden veya bankadan yapılan tahsilat |
| `sale` | 6 | 3,003,000 | 30,030.00 TL | POS üzerinden yapılan satış (18.030 TL veresiye, 12.000 TL nakit) |
| `payment` | 1 | 1,000 | 10.00 TL | POS üzerinden nakit ödeme |
| **TOPLAM** | **539** | **488,242,500** | **4,882,425.00 TL** | Tüm finansal hareketler |

### Kritik Keşif: Müşteri Bakiyeleri ile Hareketler Arasındaki Uyumsuzluk

1. **İddia Edilen Net Alacak:**
   $$\text{Net Alacak (Yalnızca Senetler)} = 4.310.745,00 - 541.640,00 = 3.769.105,00 \text{ TL}$$
2. **Tüm Hareketler Dahil Net Alacak:**
   $$\text{Toplam Borç} = 4.310.745,00 + 18.030,00 (\text{Veresiye Satış}) = 4.328.775,00 \text{ TL}$$
   $$\text{Toplam Tahsilat} = 541.640,00 + 10,00 (\text{Nakit Ödeme}) = 541.650,00 \text{ TL}$$
   $$\text{Gerçek Net Alacak} = 4.328.775,00 - 541.650,00 = 3.787.125,00 \text{ TL}$$
3. **Müşteri Tablosundaki Bakiye Toplamı:**
   - Erkul JSON dosyasındaki 401 müşterinin `balance` kolonları toplandığında: **`-523,620.00 TL`** çıkmaktadır!
   - 401 müşteriden 311'inin bakiyesi `0.00 TL`'dir.
   - Bakiyesi sıfır olmayan 90 müşteriden **88 tanesinde `balance == -collection`** olduğu tespit edilmiştir!
   - **Neden:** Eski Erkul POS yazılımında, 4.310.745 TL'lik senet sözleşmeleri `customers.balance` kolonuna yansıtılmamış; müşteri bakiyesi yalnızca elden tahsilat yapıldıkça eksiye düşürülmüştür. Sadece iki müşteride (Tunahan isimli 2 kayıt) satış/ödeme bakiyeye girmiştir.

> [!CAUTION]
> **Karar:** `BLOCKED_SEMANTICS_UNVERIFIED`  
> Erkul Çeyiz veritabanında `customers.balance` alanı ile `financial_transactions` tablosu arasında işletim sistemi kaynaklı yapısal semantik kopukluk bulunmaktadır. `financial_transactions` tablosu tek gerçek kaynak (single source of truth) kabul edilmeden yapılacak bir bakiye senkronizasyonu işletmenin 3.769.105 TL'lik senetli alacağını sıfırlayabilir veya -523.620 TL borçlu gösterebilir!

---

## 6. NUTOPIA VE SERENUT VERİTABANI ANALİZİ

### 1. Nutopia Fındık Değirmeni (`raw_nutopia_v60.db`)
- **Stok Birim Dağılımı:**
  - `adet`: 37,673 farklı ürün, toplam **5,054,094 adet** stok.
  - `kg`: 9 farklı ürün (Naturel İç Fındık, Kavrulmuş Fındık, vb.), toplam **125,431.85 kg** stok.
  - *Kanıt:* Adet ve kilogram stokları ayrı tutulmaktadır; asla tek havuzda toplanamaz.
- **Finansal Hareket Dağılımı (1,424 Kayıt):**
  - `sale`: 828 adet, toplam 1,262,674.40 TL
  - `payment`: 396 adet, toplam 598,538.90 TL
  - `collection`: 89 adet, toplam 175,720.32 TL
  - `manual_debt`: 54 adet, toplam 103,351.00 TL
  - `cancellation`: 35 adet, toplam 62,489.00 TL
  - `refund`: 22 adet, toplam 11,977.00 TL
- **Müşteri Bakiyeleri:** 584 müşteri, net bakiye toplamı: **`-134,500.68 TL`**.

### 2. Serenut (`raw_serenut_v44.db`)
- **Stok Birim Dağılımı:**
  - `adet`: 6,369 farklı ürün, toplam **636,740 adet** stok.
  - `kg`: 8 farklı ürün, toplam **705 kg** stok.
- **Finansal Hareket Dağılımı (22 Kayıt):**
  - `sale`: 20 adet, toplam 8,796.00 TL
  - `collection`: 1 adet, toplam 2,625.00 TL
  - `payment`: 1 adet, toplam 350.00 TL
- **Müşteri Bakiyeleri:** 7 müşteri, net bakiye toplamı: **`-2,673.00 TL`**.
- **Satışlar:** 15 satış, toplam ciro: **`5,272.00 TL`**.

---

## 7. KİLİT VE SATIŞ AKIŞI ADLİ DENETİMİ

Yazma ve kilit yolları çağrı zincirleriyle denetlenmiştir:

1. **Kasiyer UI Katmanı (`sales_page.dart`):**
   - `_ensureSalesActionPermitted` kontrolü: Ürün seçimi, barkod okuma, sepet miktarı artırma/azaltma, sepeti silme ve satış tamamlama butonlarında kilit devredeyse işlemi durdurur ve Türkçe SnackBar gösterir.
2. **Sepet FSM Katmanı (`sales_flow_controller.dart`):**
   - `SalesFlowNotifier._dispatch`: `addProduct`, `removeProduct`, `clearCart`, `submitPayment` eylemlerinde `DatabaseManager.cutoffMaintenanceLock` kilitliyse `CutoffMaintenanceActiveException` fırlatır. Sepet hafızada korunur, kaybolmaz.
3. **Satış Servisi Katmanı (`sales_controller.dart`):**
   - `createSale`: `_checkMaintenanceLock` çağrısı yaparak kilitli modda doğrudan istisna fırlatır.
4. **Veritabanı Katmanı (`db_gateway.dart` & `database_manager.dart`):**
   - `DbGatewayImpl`: `_waitForWriteLock()` ile kilit denetimi yapar; ham SQLite sorgularını engeller.
5. **Yarış Durumu ve Drainer Güvencesi:**
   - Kilit istendiğinde sistem önce `lockingRequested`, ardından `draining` fazına geçer.
   - `draining` fazında yeni yazmalar anında engellenir (`isWritePermitted == false`).
   - Devam eden işlem (`inFlightCount > 0`) bitene kadar `drainer.drain()` bekler. Yarım kalmış veya kısmen yazılmış satış oluşması fiziksel olarak imkansızdır.
6. **İkincil Servisler (Telemetry & Print Queue):**
   - `TelemetryUploadService` ve `PersistentPrintQueue`, `CutoffMaintenanceActiveException` oluştuğunda bu hatayı yakalayarak (try/catch) POS ekranını çökertmez.

### Yazma Yolları Sınıflandırma Tablosu

| Yazma Yolu | Bileşen & Metot | Sınıflandırma | Kanıt |
|---|---|---|---|
| POS Satış Tamamlama | `SalesController.createSale` | **LOCK_PROTECTED** | `sales_controller.dart:67` |
| Sepet Mutasyonları | `SalesFlowNotifier._dispatch` | **LOCK_PROTECTED** | `sales_flow_controller.dart:210` |
| Kasiyer Ekranı Etkileşimi | `SalesPage._ensureSalesActionPermitted` | **LOCK_PROTECTED** | `sales_page.dart:187` |
| Doğrudan SQLite Yazmaları | `DbGatewayImpl.insert/execute/txn` | **LOCK_PROTECTED** | `db_gateway.dart:55` |
| Sipariş İptali | `OrdersController.cancelOrder` | **LOCK_PROTECTED** | `orders_controller.dart:42` |
| Telemetri Kaydı | `TelemetryUploadService.recordMetric` | **LOCK_PROTECTED** | Fail-safe try/catch |
| Yazıcı Kuyruğu | `PersistentPrintQueue.enqueue` | **LOCK_PROTECTED** | Fail-safe try/catch |

---

## 8. TEST VE ANALİZ ÇALIŞTIRMA ÇIKTILARI

Komutlar gerçek ortamda bağımsız çalıştırılmış ve tam çıktıları kaydedilmiştir:

### 1. Stage 61 Testi
```powershell
flutter test test/core_next/stage10_12_61_cart_lock_three_tenant_export_import_test.dart
```
**Çıktı:** `All 13 tests passed! (Exit Code: 0, 8.0s)`

### 2. Stages 50–61 Regresyon Paketi (12 Dosya)
```powershell
flutter test test/core_next/stage10_12_50_nutopia_erkul_data_safety_test.dart test/core_next/stage10_12_51_nutopia_delta_catchup_test.dart test/core_next/stage10_12_52_financial_stock_integrity_test.dart test/core_next/stage10_12_53_dart_reconciliation_repair_test.dart test/core_next/stage10_12_54_pre_cutover_financial_flow_test.dart test/core_next/stage10_12_55_final_backup_delta_rollback_test.dart test/core_next/stage10_12_56_delta_completeness_test.dart test/core_next/stage10_12_57_cutover_protocol_audit_test.dart test/core_next/stage10_12_58_cutoff_lock_drainer_test.dart test/core_next/stage10_12_59_central_write_lock_integration_test.dart test/core_next/stage10_12_60_maintenance_ui_cutover_rehearsal_test.dart test/core_next/stage10_12_61_cart_lock_three_tenant_export_import_test.dart
```
**Çıktı:** `All 134 tests passed! (Exit Code: 0, 1m 30s)`

### 3. Statik Analiz (`flutter analyze`)
- **Değiştirilen Dosyalar:** `No issues found! (Exit Code: 0, 11.6s)`
- **Tüm Proje:** `699 issues found` (Eski test ve servis dosyalarındaki info/warning seviyesinde, gerileme yok).

---

## 9. AÇIK ENGELLER VE CANLI GEÇİŞ KARARI

1. **Canlı DB Dokunulmazlığı:** Canlı hiçbir üretim veritabanı açılmamış, değiştirilmemiş ve canlıya yazma yapılmamıştır.
2. **Erkul Semantik Engeli (`BLOCKED_SEMANTICS_UNVERIFIED`):** `customers.balance` (-523,620 TL) ile `financial_transactions` (3,769,105 TL senetli alacak + 18,030 TL veresiye) arasındaki semantik fark çözülmeden Erkul Çeyiz için canlı geçiş yapılamaz.
3. **Gerçek Boyutlu Migration Kanıtı Eksikliği:** Nutopia'nın 37,682 ürünlük gerçek SQLite verisi test ortamında tam olarak aktarılmamış; sentetik fixture kullanılmıştır. Gerçek veri boyutunda (60 MB) uçtan uca aktarım süresi ve bellek tüketimi ölçülmelidir.

---

```text
CUTOVER: NOT APPROVED
LIVE DATABASE WRITES: NOT PERFORMED
CORE NEXT SALES ENGINE: DISABLED
DATABASE ROUTING HOOK: NULL
OLD DATABASE RETIREMENT: NOT APPROVED
NUTOPIA EXPORT/IMPORT: HASH_VERIFIED_SYNTHETIC_FIXTURE_PASS_FULL_DB_NOT_MIGRATED
ERKUL EXPORT/IMPORT: BLOCKED_SEMANTICS_UNVERIFIED (BALANCE_MISMATCH_-523K_VS_+3.769M)
SERENUT EXPORT/IMPORT: HASH_VERIFIED_SYNTHETIC_FIXTURE_PASS_FULL_DB_NOT_MIGRATED
```
