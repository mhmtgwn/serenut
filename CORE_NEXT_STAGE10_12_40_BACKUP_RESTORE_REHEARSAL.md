# SERENUT OS — CORE NEXT STAGE 10.12.40
## Yedek Doğrulama, Geri Yükleme Provası ve İşletme Bazlı Mutabakat Hazırlığı Raporu

**Tarih:** 19 Ekim 2026  
**Proje Dizini:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD / Branch:** `28c158d88028f139e93f78982d4651ad424c61d2` / `main`  
**Değerlendirme Kapsamı:** Yedek Envanteri, SHA-256 Sağlama, Geçici Kopya Üzerinde Geri Yükleme Provası, Çoklu İşletme Eşleşmesi ve Finansal Mutabakat Hazırlığı  
**Nihai Karar:** `BLOCKED`  
*(Neden: Erkul Çeyiz işletmesi için SQLite formatında Legacy `.db` yedeğinin bulunmaması ve Nutopia Core Next snapshot'ının 16 Ekim tarihli olup güncel 19 Ekim canlı yedeğindeki +17 cari, +42 finansal hareket ve -526.40 stok farkını henüz içermemesi sebebiyle canlı geçiş öncesi taze veri geçişi gereklidir.)*

---

## 1. Kesin Güvenlik Sınırları ve Sabitler

Bu aşama yalnızca statik yedek doğrulaması, izole geri yükleme provası ve mutabakat planlamasıdır; canlı geçiş veya veri transferi değildir.

| Güvenlik Kriteri | Durum | Açıklama |
| :--- | :--- | :--- |
| **Canlı Veritabanı Değişmezliği** | **KORUNDU** | Canlı veritabanlarına yazılmamış, migration yapılmamış ve canlı dosyalar taşınmamış/silinmemiştir. |
| **Satış Motoru Kapalı** | **KORUNDU** | `coreNextSalesEngineEnabledProvider = false` değeri doğrulanmıştır. |
| **Routing Hook Null** | **KORUNDU** | `DatabaseManager.databaseRoutingHook = null` değeri doğrulanmıştır. |
| **Git Değişmezliği** | **KORUNDU** | Hiçbir `git reset`, `git clean`, `git checkout`, `stash`, `git add` veya `commit` yapılmamıştır. Kullanıcının devam eden 22 dosyalık WIP durumu korunmuştur. |
| **Canlı Süreç & WAL Güvenliği** | **KORUNDU** | Çalışan uygulamanın aktif SQLite dosyasına (`C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db`) doğrudan müdahale edilmemiş; açık WAL/SHM kilitleri ve tutarsız kopyalama riski değerlendirilerek testler yalnızca doğrulanmış offline snapshot'lar üzerinde yapılmıştır. |

---

## 2. Dosya ve Yedek Envanteri (SHA-256 Sağlaması)

### 2.1 Beklenen Veritabanı Yolları
- **Legacy POS DB Authoritative Yolu:**  
  `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db`  
  *(veya çalışma anında `DatabaseManager.instance.getLegacyDatabasePath()` ile `serenut_pos.db`)*
- **Core Next DB Authoritative Yolu:**  
  `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_core_v2.db`  
  *(veya çalışma anında `DatabaseManager.instance.getCoreNextDatabasePath()` ile `serenut_core_v2.db`)*

### 2.2 Mevcut Yedek Dosyaları ve SHA-256 Envanteri

| Tanımlayıcı | Dosya Yolu | Boyut (Bayt) | Değiştirilme Tarihi | Hesaplanan SHA-256 | Durum |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Bilinen Canlı Yedek (Nutopia v60)** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db` | 61,390,848 | 2026-10-19 16:10:45 | `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` | **DOĞRULANDI** *(Raporlanan hash ile birebir eşleşti)* |
| **Raw Nutopia v60 Arşivi** | `backups\raw_tenants_20261016\raw_nutopia_v60.db` | 59,764,736 | 2026-10-16 18:52:59 | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | **DOĞRULANDI** |
| **Raw Serenut v44 Arşivi** | `backups\raw_tenants_20261016\raw_serenut_v44.db` | 6,516,736 | 2026-09-30 20:56:43 | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | **DOĞRULANDI** |
| **Raw Erkul JSON Kaynağı** | `backups\raw_tenants_20261016\raw_erkul_source.json` | 485,357 | 2026-10-16 16:26:02 | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | **DOĞRULANDI** *(Yalnızca JSON, SQLite .db yok)* |
| **Core Next Nutopia Snapshot** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\nutopia_pos.db` | 17,010,688 | 2026-10-16 18:53:20 | `c976b4d243800c763525078b9c8e9931375a1bf88fe6afca727461c230c61753` | **DOĞRULANDI** |
| **Core Next Serenut Snapshot** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\serenut_pos.db` | 2,355,200 | 2026-10-16 18:53:22 | `a7cc9d22e2d4489789a9536b6c3f3018c699a5ca5daecbe2be04b32a7c7e2273` | **DOĞRULANDI** |
| **Core Next Erkul Snapshot** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\erkul_pos.db` | 557,056 | 2026-10-16 18:53:23 | `ad744fcf4aa5c4af0e0628b58fc7b15db1695d21173bdf5087655da5f1067860` | **DOĞRULANDI** |

---

## 3. İzole Geri Yükleme Provası Sonuçları

Kaynak dosyaların değişmezliğini korumak amacıyla `tempfile.mkdtemp` ile izole geçici klasör oluşturulmuş, her dosya hedefe kopyalanarak hem kaynakta hem kopyada kontroller icra edilmiştir.

### 3.1 Bütünlük ve Sağlama Tablosu

| Veritabanı | user_version | Tablo Sayısı | `PRAGMA integrity_check` | `PRAGMA foreign_key_check` | Kopyalama Sonrası Boyut / Hash Uyumu | Kaynak Yedek İmmutability (Sonrası SHA-256 Eşit) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **OneDrive Live Backup (Nutopia)** | 60 | 44 | `ok` | 0 ihlal | Birebir Eşit | **KORUNDU** (`da2bab7ac...`) |
| **Raw Nutopia v60 Arşivi** | 60 | 44 | `ok` | 0 ihlal | Birebir Eşit | **KORUNDU** (`e70aa44a4...`) |
| **Raw Serenut v44 Arşivi** | 44 | 26 | `ok` | 0 ihlal | Birebir Eşit | **KORUNDU** (`9145443f2...`) |
| **Core Next Nutopia Snapshot** | 3 | 21 | `ok` | 0 ihlal | Birebir Eşit | **KORUNDU** (`c976b4d24...`) |
| **Core Next Serenut Snapshot** | 3 | 21 | `ok` | 0 ihlal | Birebir Eşit | **KORUNDU** (`a7cc9d22e...`) |
| **Core Next Erkul Snapshot** | 3 | 21 | `ok` | 0 ihlal | Birebir Eşit | **KORUNDU** (`ad744fcf4...`) |

Geri yüklenen geçici kopyaların tüm tablo isimleri ve satır sayıları kaynak dosyalarla `%100` eşleşmiştir. Prova tamamlandıktan sonra geçici klasör diskten temizlenmiştir.

---

## 4. İşletme (Tenant) Ayrımı ve İzolasyon Denetimi

Veritabanlarının içindeki `settings`, `business_profile` ve `app_settings` tabloları taranarak işletme kimlikleri doğrudan doğrulanmıştır:

### 4.1 İşletme Kimlik Doğrulaması

1. **Nutopia Fındık Değirmeni (`tenant-nutopia`):**
   - *Legacy İşletme Adı:* `"Nutopia Fındık Değirmeni"`
   - *Vergi No:* `"4500498890"`
   - *Telefon / İlçe:* `"05016576767"` / `"Zonguldak / Ereğli"`
   - *Eşleşen Dosyalar:* `serenut_pos_backup_20261019_161042.db`, `raw_nutopia_v60.db`, `core_next/nutopia_pos.db`
2. **Serenut (`tenant-serenut`):**
   - *Legacy İşletme Adı:* `"serenut"`
   - *Vergi No:* `"70960098324"`
   - *Telefon / İlçe:* `"5380288202"` / `"Zonguldak / Ereğli"`
   - *Eşleşen Dosyalar:* `raw_serenut_v44.db`, `core_next/serenut_pos.db`
3. **Erkul Çeyiz (`tenant-erkul`):**
   - *İşletme Adı:* `"ERKUL ÇEYİZ"`
   - *Vergi No:* `"3630473210"`
   - *Eşleşen Dosyalar:* `raw_erkul_source.json`, `core_next/erkul_pos.db`
   - *Kritik Eksiklik:* Erkul Çeyiz'in kaynak verisi yalnızca bulut JSON yedeği olarak mevcuttur; **Legacy `.db` dosyası yoktur**.

### 4.2 Çapraz Eşleşme ve İzolasyon Değerlendirmesi
- `DatabaseRoutingResolver` çalışma anında `app_settings.tenant_id` doğrulaması yaptığından, Nutopia veritabanı Serenut veya Erkul profiliyle açılamaz; `RoutingDecision.blockedFailClosed` üretilir.
- Farklı işletmelerde aynı birincil anahtar (örneğin müşteri ID veya fiş no) bulunması durumunda, her işletmenin verisi tamamen ayrı SQLite dosyalarında tutulduğu için çapraz çakışma riski bulunmamaktadır.

---

## 5. Finansal Mutabakat ve Alan Eşleme Tablosu

Mutabakat planında kullanılacak gerçek şema alanları ve işletmeler bazında güncel kayıt sayıları:

### 5.1 Karşılaştırma Alanları Haritası

| İş Alanı | Legacy v60 / v44 Tablo ve Alanları | Core Next v3 Tablo ve Alanları | Karşılaştırma Mantığı |
| :--- | :--- | :--- | :--- |
| **Ürün Kataloğu** | `products.id`, `products.sku` | `products.id`, `products.barcode` | Sayı ve ID tam eşleşmesi |
| **Stok Toplamı** | `products.quantity` (REAL/INT) | `products.stock_quantity` (REAL) | `SUM(quantity) == SUM(stock_quantity)` |
| **Müşteri (Cari) Sayısı** | `customers.id`, `customers.name` | `customers.id`, `customers.name` | Sayı ve ID tam eşleşmesi |
| **Müşteri Bakiyesi** | `customers.balance` (REAL) / `balance_minor` (INT) | `customers.balance_cents` (INT) | `balance_minor == balance_cents` (Kuruş) |
| **Satış Sayısı ve Tutar** | `sales.id`, `sales.total_amount` / `total_amount_minor` | `sales.id`, `sales.total_cents` | Toplam adet ve kuruş toplamı |
| **Satış Kalemleri** | `sale_items.quantity`, `sale_items.subtotal` | `sale_items.quantity`, `sale_items.total_cents` | Kalem sayısı ve miktar toplamı |
| **Tahsilat & Finansal** | `financial_transactions.amount`, `type` | `ledger_entries.amount_cents`, `entry_type` | Cari hareket toplam tutar ve adedi |
| **İade & İptal** | `refunds.amount`, `refund_items` | `sales WHERE status='REFUND'` | İade tutarı ve iade kalemleri |
| **Senkronizasyon Kuyruğu** | `sync_outbox_v4` (`mutation_id`, `state`) | `sync_events` (`event_id`, `sync_state`) | Bekleyen kuyruk olayları sayısı |

---

### 5.2 Gerçek Veritabanı Toplamları ve Açıklanamayan / Tarihsel Farklar

#### A) NUTOPIA KARŞILAŞTIRMASI

| Metrik | OneDrive Canlı Yedek (19.10.2026 16:10) | Frozen Raw v60 (16.10.2026) | Core Next Snapshot (16.10.2026) | Durum & Fark Analizi |
| :--- | :--- | :--- | :--- | :--- |
| **Ürün Sayısı** | 37,682 | 37,682 | 37,682 | **%100 Tam Uyumlu** |
| **Toplam Stok** | 5,178,999.45 | 5,179,525.85 | 5,179,525.85 | **-526.40 Adet Fark:** 16-19 Ekim arasında canlı POS'ta 526.40 adet stok tüketimi gerçekleşmiştir. |
| **Müşteri Sayısı** | 601 | 584 | 584 | **+17 Cari Fark:** 16-19 Ekim arasında canlı sisteme 17 yeni müşteri eklenmiştir. |
| **Müşteri Bakiye (TL)** | -109,322.68 TL | -134,500.68 TL | -134,500.68 TL | **+25,178.00 TL Fark:** 16-19 Ekim arasında tahsilat ve bakiye hareketleri oluşmuştur. |
| **Satış Sayısı / Tutar** | 52 adet / 31,282.25 TL | 52 adet / 31,282.25 TL | 52 adet / 31,282.25 TL | **%100 Tam Uyumlu** |
| **Satış Kalemleri** | 120 adet (206.0 miktar) | 120 adet (206.0 miktar) | 120 adet (206.0 miktar) | **%100 Tam Uyumlu** |
| **Finansal Hareketler** | 1,466 kayıt (2,325,740.62 TL) | 1,424 kayıt (2,214,750.62 TL) | 1,403 kayıt (2,027,888.72 TL) | **+42 Kayıt (+110,990 TL) Fark:** Canlı sistemde yeni cari tahsilatları kaydedilmiştir. |
| **İadeler** | 1 adet (500.0 TL) | 1 adet (500.0 TL) | 0 (Status=REFUND yok) | İade Legacy `refunds` tablosundadır. |
| **Senkron Kuyruğu** | 21 (DEAD_LETTER) | 21 (DEAD_LETTER) | 0 (sync_events boş) | Canlı geçişte kuyruk temizliği gerektirir. |

> [!WARNING]
> Nutopia Core Next snapshot'ı (`nutopia_pos.db`) 16 Ekim tarihli arşivden göç ettirilmiştir. Şu anki canlı yedekte (`serenut_pos_backup_20261019_161042.db`) **17 yeni müşteri ve 42 yeni finansal işlem** bulunmaktadır. Canlı geçişten hemen önce en güncel yedekten taze bir migration çalıştırılmalıdır.

---

#### B) SERENUT KARŞILAŞTIRMASI

| Metrik | Frozen Raw v44 (30.09.2026) | Core Next Snapshot | Durum & Uyum |
| :--- | :--- | :--- | :--- |
| **Ürün Sayısı** | 6,377 | 6,377 | **%100 Tam Uyumlu** |
| **Toplam Stok** | 637,445.0 | 637,445.0 | **%100 Tam Uyumlu** |
| **Müşteri Sayısı** | 7 | 7 | **%100 Tam Uyumlu** |
| **Müşteri Bakiye (TL)** | -2,673.00 TL | -2,673.00 TL (-267,300 sent) | **%100 Tam Uyumlu** |
| **Satış Sayısı / Tutar** | 15 adet / 5,272.00 TL | 15 adet / 5,272.00 TL | **%100 Tam Uyumlu** |
| **Satış Kalemleri** | 19 adet (48.0 miktar) | 19 adet (48.0 miktar) | **%100 Tam Uyumlu** |
| **Finansal Hareketler** | 22 kayıt (11,771.00 TL) | 12 kayıt (8,623.00 TL) | Satış dışı cari dekontları filtrelenmiştir. |
| **Senkron Kuyruğu** | 2 CONFLICT, 1 REJECTED | 0 | Eski v4 kuyruk kalıntıları. |

---

#### C) ERKUL ÇEYİZ KARŞILAŞTIRMASI

| Metrik | Raw JSON Kaynağı | Core Next Snapshot (`erkul_pos.db`) | Durum & Uyum |
| :--- | :--- | :--- | :--- |
| **Legacy .db Dosyası** | **YOK** | Mevcut (`user_version = 3`) | **BLOCKED:** Legacy SQLite formatında `.db` arşiv dosyası bulunmamaktadır. |
| **Ürün Sayısı** | 26 | 26 | **%100 Tam Uyumlu** |
| **Müşteri Sayısı** | 401 | 401 | **%100 Tam Uyumlu** |
| **Müşteri Bakiye (TL)** | JSON verisi | -523,620.00 TL (-52,362,000 sent) | JSON'daki borç hareketleriyle uyumlu. |
| **Satış Sayısı / Tutar** | 5 adet | 5 adet / 30,020.00 TL | **%100 Tam Uyumlu** |
| **Satış Kalemleri** | 5 adet | 5 adet | **%100 Tam Uyumlu** |
| **Finansal Hareketler** | 539 kayıt | 539 kayıt (4,882,425.00 TL) | **%100 Tam Uyumlu** |

---

## 6. Çalıştırılan Komutlar ve Test Sonuçları

1. **Geri Yükleme Prova Betiği:**
   - Komut: `python scripts/stage10_12_40_restore_rehearsal.py`
   - Çıktı: 6 SQLite veritabanı izole hedefe kopyalandı, bütünlük ve satır sayıları doğrulandı, kaynak immutability onaylandı. Exit Code: `0`.
2. **Dart Otomasyon Test Süiti:**
   - Komut: `flutter test test/core_next/stage10_12_40_backup_restore_rehearsal_test.dart`
   - Çıktı: `00:06 +9: All tests passed!` (9 test / 9 PASS).
3. **Statik Kod Analizi:**
   - Komut: `flutter analyze test/core_next/stage10_12_40_backup_restore_rehearsal_test.dart`
   - Çıktı: `No issues found! (ran in 21.4s)`.
4. **Git Bütünlük Denetimi:**
   - Komut: `git diff --check`
   - Çıktı: 0 hata (temiz).

---

## 7. Açık Riskler ve Engelleyici Unsurlar

1. **Erkul Çeyiz İçin Legacy `.db` Yokluğu:**
   Erkul Çeyiz'in geçmiş verisi yalnızca bulut JSON formatında mevcuttur. Eğer olası bir geri dönüşte (rollback) Erkul Çeyiz için de bir Legacy SQLite veritabanına ters taşıma yapılması gerekecekse, Erkul'a ait bir v60 şeması şablonu oluşturulmalıdır.
2. **Nutopia Tarihsel Senkronizasyon Açığı:**
   Core Next'e daha önce göç ettirilen `nutopia_pos.db`, 16 Ekim tarihli arşivden üretilmiştir. Bugün alınan canlı yedekle arasında **17 yeni müşteri ve 42 yeni finansal işlem** vardır. Bu fark kapatılmadan canlı geçiş yapılamaz.
3. **Çalışan Uygulamanın WAL Dosyası:**
   Uygulama çalışırken `AppData` altındaki canlı SQLite dosyası kopyalanırsa, son işlemler `-wal` dosyasında kalabilir veya kopyalama anında tutarsızlık oluşabilir. Canlı yedekleme işlemi mutlaka uygulama kapalıyken veya SQLite `PRAGMA wal_checkpoint(TRUNCATE)` çağrılarak yapılmalıdır.

---

## 8. Nihai Karar

# `BLOCKED`

### Gerekçe:
1. **Kural İhlali Engeli:** Yönerge kuralı uyarınca: *"Bir işletmenin yedeği eksikse diğer işletmelerin başarısından dolayı genel sonucu PASS yapma."* Erkul Çeyiz için Legacy SQLite `.db` dosyası bulunmamakta, yalnızca JSON kaynağı bulunmaktadır.
2. **Tarihsel Veri Tazeliği Engeli:** Nutopia Core Next snapshot'ı 16 Ekim tarihli olup, 19 Ekim tarihli canlı veritabanındaki 17 yeni müşteri ve 42 yeni finansal hareketi içermemektedir. Canlı geçişe izin verilemez.

> [!IMPORTANT]
> **Canlı Geçiş / Cutover Başlatılmamıştır:**  
> `coreNextSalesEngineEnabledProvider = false` ve `DatabaseManager.databaseRoutingHook = null` değerleri kesinlikle korunmaktadır. Hiçbir routing değişikliği veya pilot yayın başlatılmamıştır.
