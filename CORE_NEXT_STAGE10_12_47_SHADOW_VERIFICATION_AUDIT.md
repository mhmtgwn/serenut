# CORE NEXT — STAGE 10.12.47
## Shadow Verification, Bağımsız Veri Mutabakatı ve Cutover Öncesi Güvenlik Denetim Raporu

**Tarih:** 2026-10-20  
**Proje Yolu:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git Dalı:** `main`  
**Git HEAD (Başlangıç ve Bitiş):** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Önceki Aşama:** Stage 10.12.46 — Critical Data Loss Remediation  
**Denetim Kararı:** `READY_FOR_SHADOW_OBSERVATION`  
*(Not: Değişmez kurallar uyarınca `CUTOVER_APPROVED` kararı verilmesi kesinlikle yasaktır ve verilmemiştir.)*

---

## 1. Değişmez Güvenlik Kuralları ve Durum Teyidi

Canlı işletmelerimiz (**Nutopia**, **Serenut** ve **Erkul Çeyiz**) günlük operasyonlarına ve ticari işlemlerine kesintisiz devam etmektedir. Bu işletmelerin gerçek ticari verilerinin korunması amacıyla aşağıdaki değişmez kuralların durumu doğrulanmıştır:

| Güvenlik Kuralı | Beklenen Durum | Gerçek Durum | Doğrulama Yöntemi |
| :--- | :--- | :--- | :--- |
| **Satış Motoru Flag'i** | `coreNextSalesEngineEnabledProvider = false` | `false` | [sales_controller.dart:L104](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L104) |
| **Veritabanı Yönlendirme Kancası** | `DatabaseManager.databaseRoutingHook = null` | `null` | [database_provider.dart:L48](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L48) |
| **Canlı SSoT Otoritesi** | Eski Veritabanı (`serenut_pos.db`) | Eski Veritabanı | Canlı yazma kancası takılmadı, okuma/yazma eski mimaride |
| **Canlı DB Üzerinde Deneme / Test** | Kesinlikle Yapılmayacak | Yapılmadı | Tüm test ve provalar izole SQLite `:memory:` / temp DB kopyalarında yapıldı |
| **Kullanıcı / Çalışma Ağacı Koruması** | Değişiklikler Korunacak | Korundu | Hiçbir reset/clean yapılmadı, kullanıcı değişiklikleri korundu |
| **Tenant DB Bütünlüğü** | Silinmeyecek / Üzerine Yazılmayacak | Korundu | Canlı tenant dosyalarına dokunulmadı |
| **Canlı Cutover Durumu** | Yapılmayacak | Yapılmadı | Canlı cutover tetiklenmedi |

---

## 2. Git ve Çalışma Ağacı Durumu

```bash
$ git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

$ git branch --show-current
main

$ git diff --check
# Temiz (0 whitespace/conflict hatası)

$ flutter analyze core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart test/core_next/stage10_12_47_shadow_verification_test.dart
Analyzing 2 items...
No issues found! (ran in 5.0s)
```

---

## 3. Kiracı (Tenant) Yedek ve Kaynak Doğrulama Sicili

Her kiracının kaynak ve hedef veritabanları birbirinden bağımsız olarak izole edilmiş, SHA-256 ve SQLite bütünlük kontrolleri ile doğrulanmıştır:

| Kiracı (Tenant) | Dosya / Kaynak Yolu | Format / Tip | SHA-256 Checksum | `PRAGMA integrity_check` | İzole Test Geri Yüklenebilirlik |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Nutopia** | `backups/raw_nutopia_v60.db` | SQLite (v60) | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | `ok` | Doğrulandı (İzole snapshot) |
| **Serenut** | `backups/raw_serenut_v44.db` | SQLite (v44) | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | `ok` | Doğrulandı (İzole snapshot) |
| **Erkul Çeyiz** | `backups/raw_erkul_source.json` | JSON Snapshot | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | N/A (JSON) | Doğrulandı (Reconstruction) |
| **Serenut Canlı Yedek** | `backups/serenut_pos_backup_20261019_161042.db` | SQLite (v60) | `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` | `ok` | Doğrulandı (İzole kopya) |
| **Serenut Aktif AppData** | `C:\Users\notop\AppData\Roaming\com.example\serenut_pos\databases\serenut_pos.db` | SQLite (Canlı) | `bffa84321e1a669a17c4b1058acc16259887d6e1e1684a7827917fee32b258eb` | `ok` | Salt-okunur doğrulandı, canlıya dokunulmadı |

> [!IMPORTANT]
> Kaynak ve hedef veritabanlarının fiziksel olarak **asla aynı dosya olmadığı**, izole geçiş testlerinin ise sadece bellek içi (`:memory:`) ve geçici izole kopyalar üzerinde koşturulduğu kesin olarak kanıtlanmıştır.

---

## 4. Yapılan Mimari ve Kod İyileştirmeleri

Stage 10.12.47 kapsamında [live_safe_catch_up_reconciliation_coordinator.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart) üzerinde şu kritik dayanıklılık geliştirmeleri yapılmıştır:

1. **`SQLITE_BUSY` (5) ve `SQLITE_LOCKED` (6) Yeniden Deneme Mekanizması (`_executeWithRetry`):**
   - Canlı kasa satış yaparken adaptörün veritabanını kilitlemesini veya kilitlenmeden dolayı çökmesini engellemek üzere üstel geri çekilme (exponential backoff: 50ms, 100ms, 200ms) ile 3 denemeli koruma katmanı eklendi.
2. **SQLite Tip Yakınlığı (Affinity) ve Zaman Damgası Hibrit Sorgulama (`_buildTimestampWhereClause` & `_buildTimestampParams`):**
   - SQLite `TEXT` alanına yazılmış sayısal milisaniye stringleri (`'179...'`), ISO-8601 stringleri (`'2026-10-20T...'`) ve saf tamsayıları aynı anda destekleyen hibrit SQL WHERE cümlesi entegre edildi:
     `((typeof(col) == 'text' AND CAST(col AS INTEGER) >= ?) OR (typeof(col) == 'text' AND col >= ?) OR (typeof(col) != 'text' AND col >= ?) OR (strftime('%s', col) IS NOT NULL AND CAST(strftime('%s', col) AS INTEGER) * 1000 >= ?))`
3. **Akıllı Zaman Damgası Dönüştürücü (`_parseTimestampMs`):**
   - Unix epoch saniye vs milisaniye ayrımı `numeric >= 1000000000 && numeric < 10000000000` kuralıyla 10 basamaklı Unix epoch saniyelerini doğru tespit edip ms'ye çevirir; `2000` gibi küçük sayıları yanlışlıkla 1000 ile çarpmaz.
4. **Satış Durumu Monotonluğu (Monotonic Status Preservation):**
   - İptal edilmiş (`CANCELLED`) veya iade edilmiş (`REFUNDED`) bir satışın, gecikmiş/sırası bozulmuş bir `COMPLETED` paketiyle ezilmesini önleyen SQL CASE koşulu eklendi.
5. **Foreign Key (FK) 787 Bütünlük Koruması:**
   - Eski tahsilatlarda (`financial_transactions`) fiş kodlarının `reference_id` olarak girilmesi durumunda Core Next'te `FOREIGN KEY (reference_sale_id) REFERENCES sales(id)` hatasını önlemek için `sales` tablosunda ID kontrolü yapıldı; eşleşmeyenler güvenle `description` alanına aktarılarak SQLite 787 hatası engellendi.
6. **Sessiz Başarısızlıkların Ortadan Kaldırılması:**
   - Tablo aktarım `catch` bloklarında oluşan tüm hatalar `discrepanciesDetected` listesine anında yazılarak `cutoverBlockedIntegrityError: true` bayrağının set edilmesi sağlandı.

---

## 5. Shadow Verification — 15 Senaryonun Bağımsız Doğrulaması

[stage10_12_47_shadow_verification_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_47_shadow_verification_test.dart) test paketi ile 15 operasyonel senaryo ve güvenlik değişmezleri bağımsız olarak test edilmiştir:

| No | Senaryo Açıklaması | Test Edilen Koşul | Sonuç |
| :---: | :--- | :--- | :---: |
| **0** | Değişmez Güvenlik Kuralları | `coreNextSalesEngineEnabledProvider == false` ve `databaseRoutingHook == null` | **BAŞARILI** |
| **1** | Yeni Satışın Aktarılması | Canlı satışın gecikmesiz olarak Core Next `sales`, `sale_items`, `sale_payments` tablolarına aktarımı | **BAŞARILI** |
| **2** | Satışın Sonradan İptal Edilmesi | İptal edilen satışın Core Next'te `CANCELLED` olarak güncellenmesi ve monotonluk | **BAŞARILI** |
| **3** | Kısmi ve Tam İadeler | Satışın `status = PARTIALLY_REFUNDED`, `refunds` ve `refund_items` tablolarına aktarımı | **BAŞARILI** |
| **4** | `sale_items` ve Satış Kalemleri | Çoklu kalemler, barkodlar, birim fiyatlar ve tutar bütünlüğü | **BAŞARILI** |
| **5** | Gerçek Ödeme Parçaları | Nakit, POS/Kredi Kartı, Havale ve Vadeli (onAccount) ödeme yöntemlerinin ayrıştırılması | **BAŞARILI** |
| **6** | Karma Ödeme ve Kuruş Hassasiyeti | Kuruşlu (0.33 + 0.67 = 1.00) karma ödemelerin kuruş sapması olmadan aktarımı | **BAŞARILI** |
| **7** | Tahsilatlar ve Ledger Tutarlılığı | Cari tahsilatların `financial_transactions` ve `ledger_entries` ile kuruşu kuruşuna mutabakatı | **BAŞARILI** |
| **8** | Müşteri Bakiyeleri ve Vadeli Hesap | Veresiye satış ve tahsilat sonrası cari borç bakiyesinin tam doğrulanması | **BAŞARILI** |
| **9** | Ürün Fiyatı, Stok ve Hareketler | Fiyat güncellemesi ve stok hareketlerinin (`stock_movements`) birebir yansıması | **BAŞARILI** |
| **10** | `sync_outbox_v4` -> `sync_events` | Eski outbox kuyruğundaki bekleyen paketlerin Core Next senkronizasyon tablosuna transferi | **BAŞARILI** |
| **11** | Kesinti ve Yeniden Başlatma | İşlem yarım kaldığında tekrar başlatılan catch-up'ın veri tekrarı veya kaybı oluşturmaması | **BAŞARILI** |
| **12** | Idempotency (Aynı Catch-up Tekrarı)| Aynı aralıkta 3 kez ardışık catch-up çalıştırıldığında kayıt sayılarının sabit kalması | **BAŞARILI** |
| **13** | Eşzamanlı Yazma & SQLITE_BUSY | Kilitlenme durumunda `_executeWithRetry` ile 3 kez denenip güvenle tamamlanması | **BAŞARILI** |
| **14** | Hibrit Zaman Damgası Türleri | Epoch ms, ISO8601 string, SQLite format ve sayısal stringlerin hatasız ayrıştırılması | **BAŞARILI** |
| **15** | Sırası Değişmiş Çoklu Terminal | Gecikmeli gelen eski terminal kaydının güncel `CANCELLED` durumunu ezememesi | **BAŞARILI** |

---

## 6. Tüm Regresyon Test Paketi Sonuçları

Projedeki 5 aşamanın test paketleri ardışık olarak koşturulmuştur:

```bash
$ flutter test \
  test/core_next/stage10_12_43_automatic_lossless_migration_test.dart \
  test/core_next/stage10_12_44_live_safe_export_import_test.dart \
  test/core_next/stage10_12_45_automatic_cutover_integration_test.dart \
  test/core_next/stage10_12_46_critical_data_loss_remediation_test.dart \
  test/core_next/stage10_12_47_shadow_verification_test.dart
```

### Gerçek Terminal Test Çıktısı:

```text
00:00 +0: loading test/core_next/stage10_12_43_automatic_lossless_migration_test.dart
...
00:19 +47: All tests passed!
```

**Toplam Koşturulan Test:** 47 test  
**Başarılı:** 47  
**Başarısız:** 0  
**Atlanan:** 0  
**Çıkış Kodu:** 0

---

## 7. Finansal ve Operasyonel Mutabakat Matrisi

| Mutabakat Alanı | Eski Sistem (Legacy DB) | Core Next Hedef | Fark / Sapma | Değerlendirme |
| :--- | :--- | :--- | :--- | :--- |
| **Satış Toplamları (Gross)** | Kuruş bazlı tam eşleşme | `sales.total_amount` | **0.00 TL** | Tam Mutabakat |
| **Satış Kalemleri Sayısı** | `sale_items` satır sayısı | `sale_items` satır sayısı | **0 adet** | Tam Bütünlük |
| **Ödeme Parçaları** | Nakit, POS, Havale, Vadeli | `sale_payments` parçaları | **0.00 TL** | Tam Mutabakat |
| **İade Tutarları & Kalemleri** | `refunds` & `refund_items` | Core Next iade kayıtları | **0.00 TL** | Tam Mutabakat |
| **Cari / Vadeli Bakiyeler** | `customers.balance` | `ledger_entries` net bakiye | **0.00 TL** | Kuruş Hassasiyeti |
| **Stok Miktarları** | `products.stock_quantity` | `products` & `stock_movements`| **0.000 kg/adet**| Tam Bütünlük |
| **Senkronizasyon Kuyruğu** | `sync_outbox_v4` | `sync_events` | **0 kayıt kaybı** | Birebir eşleşme |
| **Foreign Key Bütünlüğü** | Foreign key disabled/loose | `PRAGMA foreign_keys = ON` | **0 FK Hatası** | Kusursuz ilişki |

---

## 8. Kilitler, Hata Yönetimi ve Donanım Kuyruğu Ayrımı

1. **Donanım Yazıcı Kuyruğu Ayrımı:**
   - Termal fiş yazıcıları (ESC/POS spooler) ve donanım kuyrukları, işletim sistemi ve donanım tamponlarında asenkron çalışır.
   - Yazıcıda kağıt bitmesi, bağlantı kopması veya USB/COM gecikmesi gibi donanım olayları veritabanı ACID işlem sınırının dışındadır. Bu arızalar veritabanı catch-up mekanizmasını kirletmeyecek veya başarısız saymayacaktır.
2. **Kilit Yönetimi:**
   - Kasa satış işlemi esnasında SQLite kilitlendiğinde (`SQLITE_BUSY`), adaptör işlemi düşürmez; üstel geri çekilme ile 3 kez dener.
   - Denemeler tükenirse işlem sessizce yutulmaz; `cutoverBlockedIntegrityError: true` ve `discrepanciesDetected` açılarak eski veritabanının Single Source of Truth (SSoT) kalması garanti edilir.

---

## 9. Canlı Gölge Gözlem Planı (Shadow Observation Plan)

Sistem `READY_FOR_SHADOW_OBSERVATION` aşamasına gelmiştir. Canlı gözlemin başarıyla yürütülmesi için aşağıdaki operasyonel plan hazırlanmıştır:

1. **Gözlem Süresi:** Minimum 1 tam iş günü (Kasa açılışından kasa kapanışına kadar).
2. **Ölçülebilir Doğrulama Kriterleri:**
   - Gün sonu Z-Raporu toplamı ile Core Next `sales` toplamı kuruşu kuruşuna karşılaştırılacak.
   - Gün sonu POS gün sonu slip toplamı ile Core Next `sale_payments (type = creditCard)` toplamı karşılaştırılacak.
   - Kasa nakit teslimatı ile `sale_payments (type = cash)` toplamı karşılaştırılacak.
   - Gün içinde açılan veresiye tutarları ile müşteri ekstre hareketleri mutabık olacak.
3. **Mevcut Durum:**
   - Canlı gözlem henüz **başlatılmamıştır**. İzole hazırlıklar tamamlanmış olup gözlem başlatıldığında `SHADOW_OBSERVATION_IN_PROGRESS` durumuna geçilecektir.

---

## 10. Geri Dönüş Güvencesi (Rollback Protection)

Olası herhangi bir beklenmeyen durumda geri dönüş mekanizması tam koruma altındadır:
- `coreNextSalesEngineEnabledProvider = false` değeri korunmaktadır.
- `DatabaseManager.databaseRoutingHook = null` değeri korunmaktadır.
- Eski veritabanı aktif yazma otoritesi olmaya devam etmektedir.
- Adaptör veya gölge süreç tamamen kapatılsa dahi işletmelerin hiçbir ticari işlemi etkilenmez.

---

## 11. Kesin Karar ve Sonraki Aşama Koşulları

### Denetim Kararı: `READY_FOR_SHADOW_OBSERVATION`

> [!CAUTION]
> **Değişmez Kural Hatırlatması:** `CUTOVER_APPROVED` kararı bu aşamada kesinlikle verilmemiştir ve verilemez.

### Bir Sonraki Aşama (Canlı Gölge Gözlemi) İçin Gerekli Somut Koşullar:
1. Mağaza açılışında doğrulanmış temiz bir veritabanı anlık yedeği alınması.
2. Gölge gözlem loglayıcısının kaynak veritabanına asla yazmadan, salt-okunur arka plan dinleyicisi olarak başlatılması.
3. 1 tam iş günü sonunda Z-Raporu ve kasa kapanış mutabakatının 0.00 TL fark ile tamamlanması.
4. Bu doğrulamalar tamamlanmadan canlı yönlendirme kancalarının açılmaması.
