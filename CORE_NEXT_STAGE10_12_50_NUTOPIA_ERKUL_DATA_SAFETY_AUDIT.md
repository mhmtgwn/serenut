# CORE NEXT — STAGE 10.12.50
## NUTOPIA + ERKUL ÇEYİZ: İŞLETME BAZLI VERİ KORUMA, DOĞRU DB EŞLEŞTİRME VE KAYIPSIZ GEÇİŞ GÜVENLİĞİ DENETİM RAPORU

**Tarih:** 2026-10-20  
**Proje Yolu:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git Dalı:** `main`  
**Git HEAD (Başlangıç ve Bitiş):** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Önceki Rapor:** `CORE_NEXT_STAGE10_12_49_CONTROLLED_SHADOW_OBSERVATION.md`  
**Öncelik Kapsamı:** YALNIZCA **Nutopia Fındık Değirmeni** ve **Erkul Çeyiz**  
**Preflight Kararı:** `PREFLIGHT_BLOCKED_DATA_RISK`  
**Cutover Durumu:** `NOT_APPROVED`  

---

## 1. Değişmez Güvenlik Kuralları ve Canlı Durum Teyidi

Canlı işletmelerimiz ticari faaliyetlerine kesintisiz devam etmektedir. Veri güvenliği değişmezleri tam koruma altındadır:

| Güvenlik Kuralı | Beklenen Durum | Gerçek Durum | Kod / Konum Teyidi |
| :--- | :--- | :--- | :--- |
| **Canlı Satış Motoru Flag'i** | `coreNextSalesEngineEnabledProvider = false` | `false` | [sales_controller.dart:L104](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L104) |
| **Veritabanı Yönlendirme Kancası** | `DatabaseManager.databaseRoutingHook = null` | `null` | [database_provider.dart:L48](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L48) |
| **Tek Yetkili Veri Kaynağı (SSoT)** | Canlı Eski Veritabanı | Eski Veritabanı | Canlı okuma ve yazma yalnızca eski veritabanı üzerinden yürütülmektedir |
| **Canlı Kaynak DB'ye Yazma/Test** | Kesinlikle Yapılmayacak | Yapılmadı | Canlı veritabanına test yazımı, migration veya bakım yazımı yapılmamıştır |
| **İşletmelerin Ayrımı (Kiracı İzolasyonu)**| Kesinlikle Karıştırılmayacak | Tam İzolasyon | Nutopia, Erkul ve Serenut dosyaları ve verileri bağımsız tutulmaktadır |
| **Serenut Canlı Geçiş Kapsamı** | Bu Aşamada Kapsam Dışı | Kapsam Dışı | Yalnızca salt-okunur referans olarak tutuldu, canlı geçişe alınmadı |
| **Otomatik Cutover Durumu** | Yapılmayacak | Yapılmadı | Canlı cutover veya routing tetiklenmemiştir |

---

## 2. Git ve Çalışma Ağacı Durumu

```bash
$ git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

$ git branch --show-current
main

$ git diff --check
# Temiz (0 whitespace/conflict hatası)
```

Çalışma ağacındaki tüm kullanıcı değişiklikleri ve önceki aşama raporları eksiksiz korunmaktadır.

---

## 3. Nutopia ve Erkul Çeyiz Kaynak Envanteri ve Adli Bulgular

Her işletme için sahadaki fiziksel dosyalar, iç kimlikler (`business_name`) ve kayıt sayıları tek tek incelenmiştir:

### A) NUTOPIA FINDIK DEĞİRMENİ (Birinci Öncelik)
- **Aktif Canlı Veritabanı:** `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db`
  - Boyut: 61,390,848 bayt
  - SHA-256: `d5d68d105b5664a138cb0be2afcc2db9618d0f32502a2d3d3843b6e08eddd879`
  - SQLite Bütünlüğü: `PRAGMA integrity_check` = `ok`
  - İç İşletme Adı: `settings.business_name = 'Nutopia Fındık Değirmeni'`
  - Kullanıcılar: `mehmet güven`, `Mehmet GUVEN` (rol: owner)
  - Satışlar: 52 adet | Toplam: **31,282.25 TL** | Tahsil Edilen: **17,610.75 TL**
  - Müşteriler (Cari): 614 adet | Bakiye Toplamı: **-116,403.18 TL**
  - Ürünler: 37,682 adet | Toplam Stok Miktarı (`quantity`): **5,178,627.150 adet/kg**
  - Finansal Hareketler: 1,498 kayıt | Toplam Tutar: **2,384,550.52 TL**
  - Çevrimdışı Senkronizasyon: `sync_outbox_v4` tablosunda 21 kayıt (tümü `DEAD_LETTER` durumunda)
  - Aktif Kullanım Durumu: **EVET (Canlı kasa operasyonları bu dosya üzerinde devam etmektedir)**
- **Nutopia RAW Yedek:** `backups\raw_tenants_20261016\raw_nutopia_v60.db` (59,764,736 bayt, SHA-256 `e70aa44a...`, `integrity_check` = `ok`)
- **Nutopia Core Next Hedef DB:** `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\core_next\nutopia_pos.db`
  - Boyut: 17,010,688 bayt
  - SHA-256: `c976b4d243800c763525078b9c8e9931375a1bf88fe6afca727461c230c61753`
  - SQLite Bütünlüğü: `PRAGMA integrity_check` = `ok`
  - Core Satışlar: 52 adet (31,282.25 TL / 17,610.75 TL) -> **Kuruşu kuruşuna 0.00 TL tam eşleşme!**
  - Core Ürünler: 37,682 adet (Stok toplamı: 5,179,525.850) -> **37,682 adet ürün tam eşleşme!**
  - Core Müşteriler: 584 adet (Bakiye toplamı: -134,500.68 TL)
  - Core Defter (`ledger_entries`): 1,403 kayıt (Toplam: 2,027,888.72 TL)

> [!WARNING]
> **Nutopia Veri Riski Tespiti:**
> Aktif canlı veritabanında **614 müşteri** ve **1,498 finansal hareket** varken, mevcut `core_next\nutopia_pos.db` hedefinde **584 müşteri** ve **1,403 defter hareketi** bulunmaktadır.  
> **31 müşteri** (ör. Temel Bozkurt: -1,000 TL, Emin Kaya: -500 TL, Sadık Bozcu: -1,220 TL) ve **95 finansal hareket** (356,661.80 TL tutarında) hedef veritabanında henüz yer almamaktadır. Bu durum delta catch-up çalıştırılmadan doğrudan cutover yapılması halinde veri kaybı yaratacaktır.

---

### B) ERKUL ÇEYİZ (İkinci Öncelik)
- **Erkul Kaynak Verisi:** `backups\raw_tenants_20261016\raw_erkul_source.json`
  - Format: Resmi JSON Snapshot (UTF-8)
  - Boyut: 485,357 bayt
  - SHA-256: `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389`
  - İç İşletme Kimliği: `companies[0].name = "Erkul Çeyiz"`
  - Satışlar: 5 adet (Tutar: 30,020.00 TL | Tahsilat: 12,000.00 TL)
  - Müşteriler: 401 adet (Toplam vadeli bakiye: **-523,620.00 TL**)
  - Ürünler: 26 adet
  - Finansal Hareketler: 539 kayıt (Toplam: 4,882,425.00 TL)
  - Müşteri Siparişleri (`customer_orders`): 1 adet
  - Stok Hareketleri (`inventory_movements`): 5 adet
- **Erkul Core Next Hedef DB:** `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\core_next\erkul_pos.db`
  - Boyut: 557,056 bayt
  - SHA-256: `ad744fcf4aa5c4af0e0628b58fc7b15db1695d21173bdf5087655da5f1067860`
  - SQLite Bütünlüğü: `PRAGMA integrity_check` = `ok`
  - Core Satışlar: 5 adet (30,020.00 TL / 12,000.00 TL) -> **Birebir %100 eşleşme!**
  - Core Müşteriler: 401 adet (Bakiye: -523,620.00 TL) -> **Birebir %100 eşleşme!**
  - Core Ürünler: 26 adet -> **Birebir %100 eşleşme!**
  - Core Defter (`ledger_entries`): 539 kayıt (4,882,425.00 TL) -> **Birebir %100 eşleşme!**
  - Aktif Kullanım Durumu: Statik doğrulanmış snapshot (Canlı SQLite bağlantısı yok).

---

### C) SERENUT (Yalnızca İzolasyon Referansı — Canlı Geçiş Kapsamı Dışında)
- **Kaynak DB:** `backups\raw_tenants_20261016\raw_serenut_v44.db` (6,516,736 bayt, SHA-256 `9145443f...`)
- **Hedef DB:** `core_next\serenut_pos.db` (2,355,200 bayt, SHA-256 `a7cc9d22...`)
- **İç Kimlik:** `settings.business_name = 'serenut'` (15 satış, 6,377 ürün, 7 müşteri)
- **Durum:** Bu aşamada canlı geçiş kapsamına kesinlikle alınmamıştır. Nutopia ve Erkul'dan bağımsız olarak izole tutulmaktadır.

---

## 4. İşletme Bazlı Kaynak → Hedef Eşleştirme Tablosu

| İşletme | Kaynak Veri / DB | Kaynak Kimliği | Hedef DB | Hedef Kimliği | Eşleşme Durumu |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Nutopia Fındık Değirmeni** | `.../databases/serenut_pos.db` | `Nutopia Fındık Değirmeni` (37,682 ürün, 52 satış) | `.../databases/core_next/nutopia_pos.db` | Nutopia (37,682 ürün, 52 satış) | **Doğrulandı (Delta Catch-up Gerekli)** |
| **Erkul Çeyiz** | `raw_erkul_source.json` | `Erkul Çeyiz` (401 müşteri, 26 ürün, 5 satış) | `.../databases/core_next/erkul_pos.db` | Erkul Çeyiz (401 müşteri, 26 ürün, 5 satış) | **Doğrulandı (%100 Parite)** |
| **Serenut** | `raw_serenut_v44.db` | `serenut` (6,377 ürün, 15 satış, 7 müşteri) | `.../databases/core_next/serenut_pos.db` | Serenut (6,377 ürün, 15 satış) | **Geçiş Kapsamı Dışında (İzole)** |

---

## 5. Kayıpsız Aktarım Veri Modeli ve Tablo Kapsamı

| Kaynak Tablo | Hedef Tablo | Birincil Anahtar & Eşleştirme | Insert/Update Stratejisi | Silme/İptal Korunumu | Mükerrer Kayıt Önleme | Eksiklik / Uyarı |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `products` | `products` | `id` (veya `barcode`) | `ON CONFLICT(id) DO UPDATE` | `is_deleted = 1` korunur | PK tekilliği (`id`) | Legacy'deki `quantity` alanı hedefte `stock_quantity` kolonuyla eşleştirilmelidir. |
| `customers` | `customers` | `id` (boşsa fallback ID) | `ON CONFLICT(id) DO UPDATE` | `is_deleted = 1` korunur | PK tekilliği (`id`) | 31 müşteri hedefte eksiktir; delta catch-up zorunludur. |
| `sales` | `sales` | `id` | `ON CONFLICT(id) DO UPDATE` | `status = CASE WHEN CANCELLED...` | `idempotency_key` | 52 satış kuruşu kuruşuna hedeftir. |
| `sale_items` | `sale_items` | `id` | `INSERT OR IGNORE` | Satış bağlılığı | PK tekilliği (`id`) | Kalem toplamı satış tutarına eşittir. |
| `sale_payments` | `sale_payments` | `id` (veya `$saleId-pay-$type`)| `ON CONFLICT(id) DO UPDATE` | İptal durumunda defter ters kaydı | PK tekilliği (`id`) | Eski DB'de yapısal `sale_payments` tablosu yoksa `sales.payment_method` güvenli fallback kullanılır. |
| `financial_transactions` | `ledger_entries` | `id` | `INSERT OR IGNORE` | Append-only defter | PK tekilliği (`id`) | 95 işlem hedefte eksiktir; delta catch-up zorunludur. |
| `refunds` | `sales` + `ledger_entries` | `id` | Hedef satış durumunu güncelle | `PARTIALLY_REFUNDED` / `REFUNDED` | PK tekilliği (`id`) | İade tutarı kuruşu kuruşuna ledger'a yazılır. |
| `sync_outbox_v4` | `sync_events` | `mutation_id` / `id` | `INSERT ON CONFLICT DO UPDATE` | Statü korunumu | `event_id` | 21 adet `DEAD_LETTER` kaydı hedef senkronizasyon kuyruğuna taşınmalıdır. |

---

## 6. Canlı İşlemler Sürerken Veri Kaybı Riski Analizi

1. **Watermark Hesaplaması:**  
   Milisaniye epoch `lastMigrationCutoffTimestamp` kullanılır. Aynı milisaniyede oluşabilecek işlemleri kaçırmamak için SQLite WHERE filtresinde `>=` kullanılmakta ve `_parseTimestampMs` ile ISO8601 stringleri epoch ms'ye çevrilmektedir.
2. **Durum Geri Alınma Engeli (Monotonic Status):**  
   İptal edilmiş (`CANCELLED`) veya iade edilmiş (`REFUNDED`) bir kayıt hedefte ise, gecikmiş bir paket tarafından `COMPLETED` olarak ezilemez.
3. **Kasa İşlemleri İzolasyonu:**  
   Aktif kasa `serenut_pos.db` üzerinde SQLite WAL modunda çalışmaktadır. Gölge koordinatör yalnızca `SELECT` yaptığından kasanın yazma kilidini bloklamaz.
4. **Kiracı Başına Bağımsız Kilit ve Watermark:**  
   Her işletme kendi bağımsız hedef dosyasına (`nutopia_pos.db` / `erkul_pos.db`) yazacağından ve kilit mekanizması izole olduğundan kiracılar arası kilitlenme riski sıfırdır.

---

## 7. Finansal, Vadeli ve Stok Mutabakat Planı

### Nutopia Mutabakat Planı:
1. **Satışlar:** 52 satış = 52 satış (31,282.25 TL / 17,610.75 TL) -> **Mutabık (Fark 0.00 TL)**.
2. **Ürünler & Stok:** 37,682 ürün = 37,682 ürün. Legacy `quantity` (5,178,627.15) ile Core Next `stock_quantity` (5,179,525.85) arasındaki 898.70 birimlik fark incelenmeli ve delta stok güncellemesi ile eşitlenmelidir.
3. **Cari Vadeli Bakiyeler:** 614 müşteri vs 584 müşteri. Eksik 31 müşterinin bakiyesi (-18,097.50 TL) hedefe aktarılarak -116,403.18 TL'ye mutabık kılınmalıdır.
4. **Defter Hareketleri:** 1,498 tx vs 1,403 defter kaydı. Eksik 95 işlem hedefe aktarılmalıdır.

### Erkul Çeyiz Mutabakat Planı:
1. **Satışlar:** 5 satış = 5 satış (30,020.00 TL) -> **Mutabık (Fark 0.00 TL)**.
2. **Cari Vadeli Bakiyeler:** 401 müşteri = 401 müşteri (**-523,620.00 TL**) -> **Kuruşu kuruşuna tam mutabakat (Fark 0.00 TL)**.
3. **Ürünler:** 26 ürün = 26 ürün -> **Mutabık**.
4. **Finansal Hareketler:** 539 hareket = 539 defter kaydı (**4,882,425.00 TL**) -> **Tam mutabakat**.

---

## 8. Test Sonuçları (Stages 43 - 50 Regresyon Paketi)

Yeni eklenen [stage10_12_50_nutopia_erkul_data_safety_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_50_nutopia_erkul_data_safety_test.dart) test paketi ile birlikte 8 aşamanın tüm regresyon testleri çalıştırılmıştır:

```bash
$ flutter test \
  test/core_next/stage10_12_43_automatic_lossless_migration_test.dart \
  test/core_next/stage10_12_44_live_safe_export_import_test.dart \
  test/core_next/stage10_12_45_automatic_cutover_integration_test.dart \
  test/core_next/stage10_12_46_critical_data_loss_remediation_test.dart \
  test/core_next/stage10_12_47_shadow_verification_test.dart \
  test/core_next/stage10_12_48_shadow_observation_readiness_test.dart \
  test/core_next/stage10_12_49_pilot_gate_preflight_test.dart \
  test/core_next/stage10_12_50_nutopia_erkul_data_safety_test.dart
```

### Gerçek Terminal Test Çıktısı:
```text
00:00 +0: loading test/core_next/stage10_12_43_automatic_lossless_migration_test.dart
...
00:40 +66: All tests passed!
Exit code: 0
```
- **Toplam Test:** 66 test
- **Başarılı:** 66
- **Başarısız:** 0
- **Atlanan:** 0

---

## 9. Tespit Edilen Eksikler ve Önem Dereceleri

1. **[YÜKSEK] Nutopia Canlı DB ile Hedef Arasındaki 31 Müşteri ve 95 Hareket Farkı:**
   - Canlı kasanın devam eden işlemleri nedeniyle hedef DB geride kalmıştır.
   - Çözüm: İzole test ortamında Nutopia delta catch-up çalıştırılarak 31 müşteri ve 95 hareket hedefe aktarılmalıdır.
2. **[ORTA] `sync_outbox_v4` Kuyruğundaki 21 Adet Dead Letter Paket:**
   - Eski sunucu senkronizasyonundan kalan bu kayıtlar Core Next `sync_events` tablosuna aktarılmalı, ancak canlı API'ye kontrolsüz basılmamalıdır.
3. **[DÜŞÜK] Nutopia `quantity` vs `stock_quantity` Kolon İsimlendirmesi:**
   - Adaptör ve koordinatör her iki kolonu da başarıyla desteklemektedir.

---

## 10. Preflight Kararı ve Sonraki Aşama İçin Kesin İşler

### Denetim Kararı: `PREFLIGHT_BLOCKED_DATA_RISK`

> [!CAUTION]
> **Güvenlik Nedeni:**
> Nutopia aktif canlı veritabanında bulunan **31 müşteri** ve **95 finansal hareket**, mevcut Core Next `nutopia_pos.db` hedefinde eksiktir. Bu delta farkı izole catch-up ile kapatılmadan canlı gözlem veya cutover başlatılması veri kaybına yol açar. Bu nedenle preflight kapısı güvenle durdurulmuştur.

### Bir Sonraki Aşama (Stage 10.12.51) İçin Gereken Kesin İşler:
1. Nutopia canlı veritabanının en güncel snapshot'ı üzerinde izole bir delta catch-up provası yapılarak 31 müşteri ve 95 defter hareketinin eksiksiz aktarıldığının kanıtlanması.
2. Erkul Çeyiz için doğrulanmış JSON verisinin Core Next `erkul_pos.db` ile %100 parite durumunun korunarak bağımsız pilot hazır hale getirilmesi.
3. Her iki işletmenin mutabakat raporlarının 0.00 TL fark ile tamamlanması.

---

## 11. Kesin Kapanış Beyanları

- **Nutopia ve Erkul Çeyiz Verileri:** Birbirinden tamamen ayrı tutulmuş; dosya, şema ve kayıt kimliği düzeyinde hiçbir çapraz kirlilik olmadığı kanıtlanmıştır.
- **Serenut İşletmesi:** Canlı geçiş kapsamına kesinlikle alınmamış, izole referans olarak korunmuştur.
- **Canlı Kaynak Veritabanları:** Değiştirilmemiş, üzerine yazılmamış ve test verisi gönderilmemiştir.
- **Canlı Gözlem:** Başlatılmamıştır.
- **Cutover:** Onaylanmamıştır (`NOT_APPROVED`).
- **Son Git Durumu:** HEAD `28c158d88028f139e93f78982d4651ad424c61d2`, branch `main`, `git diff --check` temiz.
