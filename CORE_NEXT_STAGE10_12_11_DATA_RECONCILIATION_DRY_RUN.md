# SERENUT OS — STAGE 10.12.11
# VERİ GEÇİŞİ FORENSİK MUTABAKAT VE İZOLE DRY-RUN RAPORU

**Tarih:** 16 Ekim 2026  
**Git Commit / HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Branch: `main`)  
**Kapsam:** Core Next Veri Modeli Forensik Mutabakatı, İzole Kuru Çalıştırma (Dry-Run), İdempotency ve 21 Müşterisiz Satışın Mimari Eşleme Denetimi  
**Güvenlik Prensibi:** Canlı Nutopia SQLite (`%APPDATA%/serenut_pos.db`) ve Erkul Çeyiz Bulut PostgreSQL veritabanlarına sıfır müdahale. Tüm testler izole `%TEMP%` kopyaları üzerinde salt-okunur kaynaklarla icra edilmiştir.

---

## 1. YÖNETİCİ ÖZETİ VE İKİ AYRI NİHAİ KARAR

| Karar Alanı | Karar | Gerekçe Özeti |
|---|---|---|
| **1. Gerçek işletme verisi Core Next modeline kayıpsız ve mutabık aktarılabiliyor mu?** | **✅ EVET / TEKNİK OLARAK MÜMKÜN (PASS)** | 37.682 ürün, 584 müşteri (-134.500,68 TL bakiye), 52 satış (31.282,25 TL), 120 satış kalemi, 792 sipariş (1.226.806,30 TL), 9 taksit ve 1.403 cari defter hareketi 1:1 kuruş hassasiyetinde mutabıktır. 21 müşterisiz perakende satışın mimari hedefi Core Next `cash_transactions` (`category = 'SALE'`) olarak kanıtlanmıştır. |
| **2. Migration'ın uygulamanın gerçek açılış akışına bağlanmasına geçmek için yeterli kanıt var mı?** | **⛔ HAYIR / HENÜZ BAĞLANAMAZ (BLOKELİ)** | `migration_bridge_engine.dart:800` satırındaki mevcut kod `customer_id` boş olan 21 satışı `continue` ile atlamaktadır. Bu 21 kaydı doğrudan `cash_transactions` tablosuna aktaran kural motora eklenip kuru sıkı provada 21/21 teyit edilmeden ve `AppBootstrap.initPreApp()` bayrak koruması onaylanmadan canlı açılış zincirine bağlanamaz. |

---

## 2. DEĞİŞİKLİK ÖNCESİ VE SONRASI DURUM KAYDI

### Git Tabanı
- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Aktif Branch:** `main`
- **Git Diff Kontrolü (`git diff --check`):** 0 hata / 0 çakışma (Temiz).
- **Mevcut Değişiklik Durumu:** Önceki aşamaların (Stage 10.12.6, 10.12.7, 10.12.8, 10.12.9, 10.12.10) hiçbir değişikliği silinmemiş, geri alınmamış veya commit edilmemiştir.

### Dosya Değişiklikleri Özeti
- `lib/infrastructure/bootstrap/app_bootstrap.dart`: Güvenli başlatma ve hata yakalama kontrolleri.
- `lib/infrastructure/sync_v4/sync_v4_service_materializer.dart`: Sipariş / satış `unit_price_minor` senkronizasyon düzeltmesi.
- `lib/main.dart` & `about_controller.dart`: Lisans ve güncelleme kontrolü parametre entegrasyonu.
- `server/src/modules/release/release.controller.ts`: Kademeli yayın, JWT doğrulama ve fail-closed hedefleme motoru.
- `server/src/modules/admin/admin.controller.ts`: Pilot dağıtım hedef zorunluluğu ve atomik hedef yönetimi.
- `server/src/test/staged_release_http_integration.test.ts`: 15 senaryolu Express HTTP entegrasyon güvenlik testi.

---

## 3. KAYNAK VERİTABANLARININ FİZİKSEL BÜTÜNLÜĞÜ VE HASH DOĞRULAMASI

Üç işletme veri kaynağı birbirinden kesin olarak izole tutulmuş ve testler öncesinde ve sonrasında SHA-256 kriptografik özetleri doğrulanmıştır:

| Kaynak / İşletme | Dosya Yolu | Boyut (Bayt) | Başlangıç SHA-256 | Test Sonrası SHA-256 | Durum |
|---|---|---|---|---|---|
| **Nutopia** | `backups/raw_tenants_20261016/raw_nutopia_v60.db` | 59.764.736 | `E70AA44A43C53F47F61C7B82A0A8C290D82E9F849AEC68486782BC2917430D24` | `E70AA44A43C53F47F61C7B82A0A8C290D82E9F849AEC68486782BC2917430D24` | **DEĞİŞMEDİ (%100 Korundu)** |
| **Serenut** | `backups/raw_tenants_20261016/raw_serenut_v44.db` | 6.516.736 | `9145443F2C94A03DEA7478605DE974A1214B548523DA0406C18501918DA7D77D` | `9145443F2C94A03DEA7478605DE974A1214B548523DA0406C18501918DA7D77D` | **DEĞİŞMEDİ (%100 Korundu)** |
| **Erkul Çeyiz** | `backups/raw_tenants_20261016/raw_erkul_source.json` | 485.357 | `B4912D916818377FA3D4A2D87C9BC33AA9B5FCD69300442DD6EEA6D8FA5EE389` | `B4912D916818377FA3D4A2D87C9BC33AA9B5FCD69300442DD6EEA6D8FA5EE389` | **DEĞİŞMEDİ (%100 Korundu)** |

---

## 4. GERÇEK ŞEMA VE TABLO EŞLEŞTİRME (MAPPING) MATRİSİ

Kaynak SQLite (v60) ile Hedef Core Next SQLite (v3) arasındaki gerçek kolon ve dönüşüm kuralları:

| Kaynak Tablo | Hedef Tablo | Birincil Anahtar (PK) | Dönüşüm Kuralı & Kuruş Hassasiyeti | Atlanma / Ret Koşulu |
|---|---|---|---|---|
| `users` | `users` | `id` (veya `usr-{username}`) | Parola hash, rol ve aktiflik bayrağı aynen korunur. | Boş username ise sentetik `user_{id}` üretilir. |
| `products` | `products` | `id` | `price * 100 -> price_cents`, `quantity -> stock_quantity`, `min_stock -> critical_threshold`. | Silinmiş ürünler `is_deleted = 1` olarak korunur. |
| `customers` | `customers` | `id` | `balance * 100 -> balance_cents`, `credit_limit -> credit_limit_cents`. Kuruş farkı varsa `CustomerDiscrepancy` kaydı düşülür. | `id` boş ise `customer-pesin-default` atanır. |
| `sales` | `sales` | `id` | `total_amount -> total_cents`, `paid_amount -> paid_cents`, `debt_cents = total - paid`. | `total_cents < 0` (REFUND hariç) `StateError` ile durdurur. |
| `sales` (Ödemeler) | `sale_payments` | `id` (`{saleId}-pay-...`) | Parçalı / tekil ödeme ayrıştırılır: `cash`, `creditCard`, `onAccount`, `bankTransfer`, `mixed`. | Tutar 0 olan ödeme kayıtları eklenmez. |
| `financial_transactions` (Müşterili) | `ledger_entries` | `id` | `amount_minor` veya `amount * 100 -> amount_cents`. `balance_after_cents` kümülatif yürütülür. | `customer_id IS NULL OR customer_id = ''` olanlar bu tabloya ALINMAZ. |
| `financial_transactions` (Müşterisiz) | `cash_transactions` | `id` | `amount_minor -> amount_cents`, `type = 'INFLOW'`, `category = 'SALE'`. Tezgâh nakit akışı. | Satış referansı olmayan sahte kayıtlar reddedilir. |
| `orders` | `orders` | `id` | `total_amount * 100 -> total_amount_cents`, `order_date -> order_date (epoch ms)`. | Müşteri geçersizse `customer_id = NULL` (İlişkisel bütünlük). |
| `order_items` | `order_items` | `id` | `quantity * unit_price * 100 -> total_cents`, `unit_price * 100 -> unit_price_cents`. | Sipariş başlığı hedefte yoksa atlanır. |
| `customer_installment_plans`| `customer_installment_plans` | `id` | `total_amount * 100 -> total_amount_cents`, `down_payment * 100 -> down_payment_cents`. | Müşteri hedefte yoksa atlanır. |
| `customer_installments` | `customer_installments` | `id` | `amount * 100 -> amount_cents`, `paid_amount * 100 -> paid_amount_cents`. | Plan hedefte yoksa atlanır. |
| `refunds` | `refunds` | `id` | `amount * 100 -> amount_cents`. | Satış hedefte yoksa atlanır. |
| `cash_expenses` | `cash_expenses` | `id` | `amount * 100 -> amount_cents`. | - |
| `cash_counts` | `cash_counts` | `id` | `expected/actual/diff * 100 -> ..._cents`. | - |
| `audit_events` | `audit_events` | `id` | Kriptografik zincir hash'leri aynen aktarılır. | - |

---

## 5. 21 MÜŞTERİSİZ NAKİT SATIŞININ FORENSİK ÇÖZÜMLEMESİ

Stage 10.12.10 denetimindeki bulgu, bağımsız Python/SQLite sorgularıyla derinlemesine incelenmiştir:

### Adli Sorgu Bulguları
- **Kayıt Sayısı:** Tam olarak **21 adet**.
- **Toplam Tutar:** **12.197,00 TL** (1.219.700 kuruş).
- **Kayıt Türü Dağılımı:** 21 kaydın 21'i de `type = 'sale'` ve `customer_id IS NULL OR customer_id = ''` durumundadır.
- **Satış Tablosu Bağlantısı:** 21 kaydın 21'inin de `reference_id` değeri `sales` tablosundaki bir `id` ile birebir eşleşmektedir (Eşleşme: %100).
- **Ödeme Yöntemi ve Durum:** `sales` tablosundaki ilgili 21 kaydın tamamında `payment_method = 'cash'`, `status = 'completed'` ve `paid_amount = total_amount` olarak kayıtlıdır.
- **Satış vs Ödeme Tutar Farkı:** **0,00 TL** (Kuruşu kuruşuna denk).
- **İade / İptal İlişkisi:** Bu 21 satışa ait `refunds` tablosunda **0 adet** kayıt vardır (Hiçbiri iade edilmemiştir).
- **İkinci Temsil (Mükerrerlik):** Legacy DB'de `sale_payments` tablosu bulunmamaktadır; `orders` tablosunda bu ID'ler yer almamaktadır.

### Mimari Hedef Kanıtı: `cash_transactions`
1. Core Next şemasında `ledger_entries` tablosu:
   ```sql
   CREATE TABLE IF NOT EXISTS ledger_entries (
     id TEXT PRIMARY KEY NOT NULL,
     customer_id TEXT NOT NULL, -- KESİNLİKLE NULL OLAMAZ
     ...
     FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE RESTRICT
   );
   ```
2. Core Next satış akışında ([checkout_use_case.dart:263-272](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L263-L272)):
   ```dart
   if (split.type == PaymentType.cash && split.amount.value > 0) {
     await txn.insert('cash_transactions', {
       'id': _uuid.v4(),
       'type': 'INFLOW',
       'amount_cents': split.amount.value,
       'category': 'SALE',
       'description': 'Fiş No: ${request.receiptNo}',
       'created_at': now.millisecondsSinceEpoch,
     });
   }
   ```
3. **Sonuç:** Müşterisi olmayan peşin nakit satışlar ticari ve muhasebesel olarak cari borç hareketi değil, **kasa nakit girişidir**. Dolayısıyla bu 21 kayıt için doğru hedef `cash_transactions` tablosudur (`category = 'SALE'`, `type = 'INFLOW'`). Sentetik müşteri oluşturulmasına gerek yoktur.

---

## 6. TAM FİNANSAL MUTABAKAT TABLOSU (RAW NUTOPIA V60)

Kaynak `raw_nutopia_v60.db` üzerinden sıfır varsayımla hesaplanan kesin finansal envanter:

```
========================================================================================
METRİK / VARLIK ALANI           KAYNAK KAYIT SAYISI     KAYNAK PARASAL TOPLAM (TL / ADET)
========================================================================================
1. Ürün Kataloğu (Toplam)       37.682 adet             1.641.915.480,60 TL (Stok Değeri)
   - Aktif Ürünler              17 adet                 168,00 TL
   - Silinmiş / Arşiv Ürünler   37.665 adet             1.641.915.312,60 TL
   - Toplam Stok Miktarı        -                       5.179.525,85 birim
----------------------------------------------------------------------------------------
2. Müşteri Carileri (Toplam)    584 müşteri             -134.500,68 TL (Net Bakiye)
   - Aktif Müşteriler           577 müşteri             -137.529,68 TL
   - Silinmiş Müşteriler        7 müşteri               +3.029,00 TL
----------------------------------------------------------------------------------------
3. Finansal Hareketler (FT)     1.424 hareket           Toplam: 2.214.750,62 TL
   - Satışlar (sale)            828 adet                1.262.674,40 TL
   - Ödemeler (payment)         396 adet                598.538,90 TL
   - Tahsilatlar (collection)   89 adet                 175.720,32 TL
   - Manuel Borç (manual_debt)  54 adet                 103.351,00 TL
   - İptaller (cancellation)    35 adet                 62.489,00 TL
   - İadeler (refund)           22 adet                 11.977,00 TL
   * Müşteri Bağlantılı (Cari)  1.403 adet              1.403 kayıt (Hedef: ledger_entries)
   * Tezgâh Peşin Satış (Kasa)  21 adet                 12.197,00 TL (Hedef: cash_transactions)
----------------------------------------------------------------------------------------
4. Satış Başlıkları (sales)     52 satış                Toplam Ciro: 31.282,25 TL
   - Nakit (cash)               31 adet                 17.560,75 TL (Tahsil: 17.560,75 TL)
   - Vadeli / Veresiye (debt)   19 adet                 13.616,50 TL (Tahsil: 0,00 TL)
   - Karma Ödeme (karma)        2 adet                  105,00 TL (Tahsil: 50,00 TL)
   - Satış Kalemleri (items)    120 adet                31.307,25 TL (İskonto: 25,00 TL)
----------------------------------------------------------------------------------------
5. Siparişler (orders)          792 sipariş             Toplam: 1.226.806,30 TL
   - Teslim Edilmiş (delivered) 659 adet                1.051.242,30 TL
   - Hazır / Hazırlanıyor       68 adet                 123.559,50 TL
   - İptal Edilmiş (cancelled)  37 adet                 33.730,50 TL
   - Yeni Açılmış (created)     28 adet                 18.274,00 TL
   - Sipariş Kalemleri (items)  1.068 adet              1.268.966,95 TL (Adet: 16.640,35)
----------------------------------------------------------------------------------------
6. Taksitli Satışlar            2 plan / 9 taksit       Plan Tutarı: 22.000,00 TL
   - İptal Edilen Taksitler     6 adet                  11.880,00 TL (Ödenen: 1.900,00 TL)
   - Ödenmiş Taksitler          2 adet                  4.533,32 TL (Ödenen: 4.533,32 TL)
   - Bekleyen Taksit            1 adet                  -4.465,32 TL (Bakiye düzeltme)
----------------------------------------------------------------------------------------
7. İadeler Tablosu (refunds)    1 adet                  500,00 TL
========================================================================================
```

---

## 7. İZOLE DRY-RUN VE TEKRARLANABİLİRLİK KANITLARI

`test/core_next/stage10_10_9_full_reconciliation_test.dart` ve `fault_injection_migration_test.dart` paketleri çalıştırılarak aşağıdaki sonuçlar kanıtlanmıştır:

### A. İlk Çalıştırma (Isolated Initial Migration)
- İzole geçici hedef veritabanına aktarım: **BAŞARILI**.
- `PRAGMA integrity_check` -> `ok`.
- `PRAGMA foreign_key_check` -> 0 hata.
- 1.403 müşteri defter hareketinin tamamı 1:1 kuruş hassasiyetinde aktarılmıştır.

### B. İkinci Çalıştırma (Idempotency Test)
- Aynı `MigrationBridgeEngine.migrateFromLegacy(fullScope: true)` çağrısı aynı veritabanı üzerinde ikinci kez çalıştırılmıştır.
- Sonuç: `ledger_entries` sayısı 1.403 olarak sabit kalmış, `products` sayısı 37.682 olarak korunmuş, hiçbir tabloda mükerrer satır oluşmamıştır.
- Müşteri bakiyelerinde 1 kuruşluk bile sapma meydana gelmemiştir.

### C. Hata Enjeksiyonu ve Atomik Rollback (Fault Injection Drill)
- Göç esnasında cari aşamasında kasıtlı bir `StateError` fırlatılmıştır.
- SQLite transaction mekanizması sayesinde o ana kadar eklenmiş olan kullanıcılar, kategoriler ve ürünler tamamen **ROLLBACK** edilmiştir.
- Hedef veritabanı temiz ve bozulmamış durumda kalmıştır.

### D. Yeniden Başlatma (Resumption Simulation)
- Hata giderildikten sonra migration baştan başlatılmış ve sistem sıfır hata ile `completed` durumuna ulaşmıştır.

---

## 8. UYGULAMA AÇILIŞI VE GERİ DÖNÜŞ (ROLLBACK) DENETİMİ

### Açılış Zinciri İncelemesi
1. [app_bootstrap.dart:116](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/app_bootstrap.dart#L116) `DatabaseManager.instance.getDatabase()` çağrısı yapar.
2. [database_provider.dart:296](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L296) doğrudan `serenut_pos.db` dosyasını açar.
3. [core_next_bootstrap_coordinator.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart) koordinatörü mevcuttur ancak canlı kodda yalnızca izole runner enjekte edildiğinde devreye girmektedir.

### Sessiz Geri Dönüş ve Çift Yönlü Risk
- **Risk:** Yeni DB'ye geçildikten sonra sistemin otomatik olarak eski DB'ye dönmesi durumunda, yeni DB'de kesilmiş olan satışlar eski DB'de bulunmayacağı için ciro kaybı oluşur.
- **Kanıtlanmış Koruma:** `DatabaseRoutingResolver.assertSafeRollback()` metodu:
  ```dart
  final newSales = await targetDb.rawQuery(
    'SELECT COUNT(*) as c FROM sales WHERE created_at > ?',
    [initialMigrationCutoffTimestamp],
  );
  if (count > 0) throw UnsafeRollbackException('Yeni satışlar var, sessiz dönüş engellendi!');
  ```
- **Çift Yönlü Motor:** [stage10_9_7_startup_restore_rollback_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_9_7_startup_restore_rollback_test.dart#L560) içinde `ReverseMigrationEngine` test edilmiş; yeni DB'deki satışların eski DB'ye geri aktarılabildiği doğrulanmıştır.

---

## 9. DENETİM VE KONTROL MATRİSİ (PASS / FAIL / NOT VERIFIED)

| # | Kontrol Maddesi | Doğrulama Yöntemi | Sonuç | Açıklama |
|---|---|---|---|---|
| 1 | Kaynak Dosyaların Değişmezliği | SHA-256 Before/After Karşılaştırması | **PASS** | Nutopia, Serenut, Erkul hash'leri %100 aynı kaldı. |
| 2 | Multi-Tenant Veri İzolasyonu | Ayrı izole kopyalar ve tenant ID kontrolleri | **PASS** | Şirketler arası veri sızıntısı 0. |
| 3 | 1.403 Cari Hareket Mutabakatı | `stage10_10_9_full_reconciliation_test` | **PASS** | 1.403 hareket 1:1 kuruş kuruşuna denk aktarıldı. |
| 4 | 21 Müşterisiz Satışın Tespiti | Python adli analizi | **PASS** | 21 adet, 12.197,00 TL, %100 nakit satış. |
| 5 | 21 Satışın Mimari Hedefi | Core Next `checkout_use_case.dart` incelemesi | **PASS** | Hedefin `cash_transactions` (`category = 'SALE'`) olduğu kanıtlandı. |
| 6 | Motorun 21 Satışı Aktarma Davranışı | `migration_bridge_engine.dart:800` incelemesi | **FAIL / BLOCKED** | Mevcut motor `customer_id` boş olduğu için bu 21 satırı atlamaktadır. |
| 7 | İdempotency (İkinci Çalıştırma) | İki kez ardışık `migrateFromLegacy` | **PASS** | Mükerrer kayıt yok, bakiye kayması 0. |
| 8 | Atomik Rollback ve Transaction | Kasıtlı hata enjeksiyonu testi | **PASS** | Hata anında tüm tablolar temizlendi. |
| 9 | PRAGMA Bütünlüğü | `integrity_check` & `foreign_key_check` | **PASS** | Hedef şema ve ilişkisel bütünlük hatasız. |
| 10 | Üretim Açılış Yolu İzolasyonu | `app_bootstrap.dart` ve `lib/` kod taraması | **PASS** | Üretim kodu hâlâ %100 legacy DB üzerinde izole çalışıyor. |

---

## 10. NİHAİ KARAR VE GEÇİŞ ÖNCESİ ZORUNLU ADIMLAR

### Karar 1: Gerçek İşletme Verisinin Core Next Modeline Aktarımı
**SONUÇ: EVET / TEKNİK OLARAK MÜMKÜN (PASS)**  
Veri modeli, kuruş hassasiyeti ve finansal defter mantığı işletmenin 1.403 cari kaydını, 584 müşterisini, 52 satışını ve 792 siparişini kayıpsız temsil edebilmektedir. 21 müşterisiz satış ise Core Next `cash_transactions` tablosuna tam oturmaktadır.

### Karar 2: Uygulamanın Gerçek Açılış Akışına Bağlanma Hazırlığı
**SONUÇ: HENÜZ BAĞLANAMAZ (BLOKELİ)**  
Canlı uygulamanın açılış yolunu Core Next'e yönlendirmeden önce şu iki teknik eylem zorunludur:
1. `migration_bridge_engine.dart` içinde `financial_transactions` döngüsüne:
   `customer_id` boş veya null olan 21 nakit satış kaydının `cash_transactions` tablosuna (`category = 'SALE'`, `type = 'INFLOW'`, `amount_cents = resolveAmountCents(...)`) eklenmesini sağlayan kural yazılmalıdır.
2. Bu kural eklendikten sonra izole hedef üzerinde `cash_transactions` tablosunda tam 21 kayıt ve 1.219.700 kuruş (12.197,00 TL) oluştuğu doğrulanmalıdır.
