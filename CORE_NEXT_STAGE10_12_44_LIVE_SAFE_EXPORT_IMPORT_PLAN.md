# SERENUT OS — STAGE 10.12.44
# CANLI İŞLEMLERİ KORUMALI DIŞA AKTARMA / İÇE AKTARMA VE GEÇİŞ GÜVENLİĞİ DENETİM RAPORU

**Tarih:** 20 Ekim 2026  
**Aşama:** Stage 10.12.44 — Live Safe Export/Import & Cutover Security Audit  
**Mevcut HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Branch:** `main`  
**Karar:** **`BLOCKED`** (Canlı Geçiş / Canlı Veri Tabanı Yönlendirmesi Kesinlikle Kilitlidir)

---

## 1. Başlangıç Git Durumu ve Değişmezlik Doğrulaması

Denetim öncesinde depodaki Git ağacı kontrol edilmiş ve hiçbir kullanıcı değişikliği, WIP dosyası veya untracked dosya silinmemiş, üzerine yazılmamıştır.

```text
git rev-parse HEAD: 28c158d88028f139e93f78982d4651ad424c61d2
git branch --show-current: main
git diff --check: [TEMİZ - Boşluk/satır hatası yok]
git status --short: 22 mevcut dosya (WIP ve Stage 10.12.43 raporları) aynen korundu.
```

### Kesin Güvenlik Sabitleri Kontrolü
1. `coreNextSalesEngineEnabledProvider`: **`false`** (Değiştirilmedi, `test/core_next/stage10_12_44_live_safe_export_import_test.dart` ile doğrulandı).
2. `DatabaseManager.databaseRoutingHook`: **`null`** (Değiştirilmedi, doğrulandı).
3. `PilotCutoverGate`: **`fail-closed`** (`disabledByDefault`, tüm tenant'lar için bloklu).

---

## 2. İncelenen Gerçek Dosya Yolları, Boyutlar ve Kriptografik Özetler

Denetlenen tüm veri dosyaları salt-okunur olarak açılmış ve testler boyunca tek bir bayt dahi değiştirilmemiştir (0 Bayt Mutasyon Garantisi).

| Dosya Tanımı | Gerçek Dosya Yolu | Boyut (Bayt) | SHA-256 Özeti | Değiştirilme Zamanı (mtime) |
|---|---|---|---|---|
| **Canlı Çalışan DB** | `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db` | 61,390,848 | - (Çalışma esnasında WAL aktif) | 2026-10-20 16:04:47 |
| **Canlı Çalışan WAL** | `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db-wal` | 4,173,592 | [Aktif işlem günlüğü] | 2026-10-20 16:19:08 |
| **19 Ekim Canlı Yedek** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db` | 61,390,848 | `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` | 2026-10-19 16:10:44 |
| **16 Ekim Ham Nutopia** | `backups\raw_tenants_20261016\raw_nutopia_v60.db` | 59,764,736 | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | 2026-10-16 19:28:43 |
| **Ham Erkul Cloud JSON** | `backups\raw_tenants_20261016\raw_erkul_source.json` | 485,357 | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | 2026-10-16 19:18:22 |
| **Ham Serenut v44** | `backups\raw_tenants_20261016\raw_serenut_v44.db` | 6,516,736 | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | 2026-10-16 19:28:57 |

---

## 3. Kaynak, Snapshot ve Canlı Veri Zaman Ayrımı (Store Operating Reality)

### Kritik Bulgu: İşletmeler Canlı İşlem Yapmaya Devam Etmektedir
Yapılan adli analizde ortaya konmuştur ki:
1. **19 Ekim Yedeği Statik Bir Kesittir:** `serenut_pos_backup_20261019_161042.db` yedeğindeki son işlemler:
   - Son Satış Zamanı: `2026-09-25T16:31:05.157850`
   - Son Sipariş Zamanı: `2026-10-19T15:00:57.241212`
   - Son Kasa / Finansal Hareket: `2026-10-19T15:00:57.336936`
2. **Canlı Veritabanı Yedeğin Ardından İşlem Görmüştür:** `AppData\Roaming\...\serenut_pos.db-wal` dosyasının boyutu **4,173,592 bayt** olup son değiştirilme tarihi **20 Ekim 2026 16:19:08**'dir.
3. **Farkların Anlamı:** 19 Ekim yedeği ile canlı veritabanı veya 16 Ekim ham yedeği arasındaki kayıt sayısı, stok ve bakiye farkları **bir veri kaybı veya adaptör hatası değildir**; işletmelerin günlük ticari hayatına devam etmesi sonucu oluşan doğal işlem hacmidir.
4. **Geçiş Kuralı:** Kaynak ve hedef aynı işlem kesitine (snapshot timestamp) bağlanmadığı sürece hiçbir mutabakat kesin başarılı ilan edilemez.

---

## 4. Firma Bazında Doğrulanmış ve Doğrulanmamış Bulgular

### A. Nutopia (Aktif Perakende Satış & Masa/Sipariş)
- **Doğrulananlar:**
  - 37,682 ürün kataloğu, 601 cari müşteri.
  - 814 sipariş ve 1,099 sipariş kalemi (19 Ekim 15:00:57'ye kadar).
  - Canlı POS uygulamasında SQLite v60 şeması kullanılmaktadır.
- **Doğrulanmayan / Riskli Olanlar:**
  - 19 Ekim 16:10 ile 20 Ekim arasındaki canlı kasa ve masa siparişleri henüz statik yedekte bulunmamaktadır.

### B. Erkul Çeyiz (Senetli / Vadeli Satış & Taksit Tahsilatı)
- **Doğrulananlar:**
  - Diskte yerel bir SQLite Legacy veritabanı yoktur; kaynak verisi PostgreSQL Cloud Export (`raw_erkul_source.json`) dosyasıdır.
  - İşlem semantiği kesin olarak ayrıştırılmıştır:
    * `manual_debt`: **423 adet**, toplam **4,310,745.00 TL** (Senetli / vadeli çeyiz sözleşme borçlandırmaları).
    * `sale`: **6 adet**, toplam **30,030.00 TL** (Peşin satışlar; 12,000 TL nakit ödenmiş, 18,030 TL borç kaydedilmiş).
    * `collection`: **109 adet**, toplam **541,640.00 TL** (Müşterilerden makbuzla tahsil edilen taksit ödemeleri).
    * `payment`: **1 adet**, **10.00 TL** (İade/tedarikçi ödemesi).
    * **Gerçek Net Alacak:** `(4,310,745 + 18,030) - 541,640 = 3,787,135.00 TL`.
  - Müşteri kartındaki toplam **-523,620.00 TL** bakiye: Cloud `sync-v4.materializer.ts` mimarisinde `manual_debt` hareketlerinin müşteri kart bakiyesine borç olarak işlenmemesi ve yalnızca tahsilatların (`collection`) eksiltici olarak düşülmesinden kaynaklanmaktadır. Bu bir kasa açığı, hırsızlık veya veri kaybı değil; bulut senkronizasyon şemasının tasarım kısıtıdır.
- **Doğrulanmayan / Riskli Olanlar:**
  - Erkul Çeyiz işletme sahibinin yazılı onayı olmadan müşteri kartı bakiyesi düzeltilemez veya değiştirilemez.

### C. Serenut (Kurumsal / Toptan)
- **Doğrulananlar:**
  - Ham v44 veritabanı (1,155 ürün, 26 müşteri, 22 sipariş) mevcuttur.
- **Doğrulanmayanlar:**
  - Canlı operasyonun son güncel veritabanı ile v44 arasındaki senkronizasyon durumu.

---

## 5. 8 Adımlı Korumalı Dışa Aktarma / İçe Aktarma Tasarımı ve Provası

Ayrı bir izole alanda (`temp/stage44_test_isolated`) 8 adımlı süreç simüle edilmiş ve kaynak verinin dokunulmazlığı kanıtlanmıştır:

```text
[Adım 1] Kaynak Veritabanını Güvenli Kopyalama:
         WAL kilitlenmesini engellemek için VACUUM INTO veya güvenli snapshot yöntemi.
[Adım 2] Kriptografik Doğrulama & Bütünlük Denetimi:
         Kopyanın SHA-256 özeti hesaplanır ve 'PRAGMA integrity_check' = ok doğrulanır.
[Adım 3] Kaynak Şema ve Metadata Çıkarma:
         user_version (v60), 44 tablo, 87 indeks, 8 tetikleyici, foreign key kuralları dökülür.
[Adım 4] Açık Eşleme Planı ile Hedefe Aktarım:
         Legacy tabloları (products, customers, orders, sales) Core Next tablolarına (core_next_sales, ledger_entries)
         birebir deterministik eşleme kurallarıyla aktarılır.
[Adım 5] Kayıt ve Finansal Mutabakat Karşılaştırması:
         Kaynak ve hedef satır sayıları, finansal toplamlar ve stok adetleri karşılaştırılır.
[Adım 6] İlişkisel Bütünlük ve Anomali Raporlama:
         'PRAGMA foreign_key_check' = 0 ihlal. Eksik, fazla veya yetim (orphan) kayıtlar ayrı loglanır.
[Adım 7] İdempotens ve Tekrar Çalıştırma Testi:
         Aynı aktarım ikinci kez çalıştırıldığında 'idempotency_key' ve 'ON CONFLICT DO NOTHING'
         sayesinde tek bir mükerrer kayıt dahi üretmediği kanıtlandı.
[Adım 8] Geri Alma / İzolasyon Güvencesi:
         Hata durumunda veya test sonunda hedef aday silinir; kaynak dosya 0 bayt mutasyonla korunur.
```

---

## 6. Canlı İşlem Devam Ederken Son Aktarım Stratejisi (Cutover Analysis)

Mevcut sistemde **CDC (Change Data Capture)** veya Kafka/Debezium benzeri bir gerçek zamanlı olay akışı mekanizması **BULUNMAMAKTADIR**. Olmayan bir CDC'yi varmış gibi kabul etmek felaket riskidir.

### Seçeneklerin Değerlendirilmesi

1. **İşletme Çalışırken Çift Yazma (Dual Write / Outbox):**
   - *Risk:* Mevcut masaüstü POS mimarisi SQLite tabanlıdır. Canlı işlem esnasında arka plandan yeni Core Next motoruna çift yazma denemek `database is locked` (SQLITE_BUSY) kilitlenmelerine ve veri tutarsızlıklarına yol açar. **UYGULANAMAZ.**
2. **CDC Tabanlı Yakalama:**
   - *Gerçek:* Kod tabanında ve yerel SQLite'ta CDC mekanizması yoktur. **MEVCUT DEĞİL.**
3. **İşletme Kapalıyken Kontrollü Son Snapshot ve Final Catch-Up (ÖNERİLEN VE TEK GÜVENLİ YOL):**
   - *Yöntem:*
     1. İlgili mağaza kapandıktan sonra (ör. 22:30) POS terminalinde yeni satış girişi durdurulur.
     2. Canlı veritabanındaki WAL checkpoint (`PRAGMA wal_checkpoint(TRUNCATE)`) tamamlanır.
     3. Nihai "Final Cutover Snapshot" alınır, SHA-256'sı mühürlenir.
     4. İzole 8 adımlı adaptör çalıştırılarak Core Next veritabanı oluşturulur.
     5. Kaynak-Hedef finansal ve stok mutabakatı %100 doğrulanır.
     6. Kontrollü geçiş onaylanır.

---

## 7. Erkul Çeyiz Finansal Güvenliği ve Kök Neden Analizi

- **Neden Müşteri Kartı Bakiyesi -523,640 TL Görünüyor?**
  Erkul Çeyiz'de satılan gelinlik ve çeyiz paketleri peşin değil senetli/taksitli satılmaktadır. Muhasebe defterinde 4.31 Milyon TL `manual_debt` (senetli borç) kaydı bulunmaktadır. Bulut PostgreSQL senkronizasyonunda bu borç hareketleri cari bakiye alanına işlenmemiş, yalnızca müşterilerin yaptığı 541 Bin TL `collection` (taksit ödemeleri) karta yansıtılmıştır.
- **Güvenlik Kuralı:** İşletme sahibinin ıslak imzalı veya yazılı finansal mutabakat kararı olmadan hiçbir müşteri bakiyesi otomatik düzeltilemez veya sunucu veritabanına yapay bakiye yazılamaz.

---

## 8. Gerçek Yazıcılar ve Donanım İş Akışı

Sistemde bağlı gerçek fiziksel yazıcılar Windows Management Instrumentation (WMI) üzerinden salt-okunur incelenmiştir:

| Yazıcı Adı | Bağlantı Portu | Sürücü | Tip / Protokol | Mevcut Rota Eşleşmesi |
|---|---|---|---|---|
| **POS-80** | `USB003` | `POS-80 11.3.0.1` | Termal Fiş Yazıcısı (ESC/POS 80mm) | `receipt` -> `receiptPrinter-1788289946738843` |
| **etiket** | `USB004` | `LABEL` | Termal Barkod/Etiket Yazıcısı (TSPL 100x60mm 203 DPI) | `productLabel` & `orderLabel` -> `labelPrinter-1788289989491204` |

### Güvenli Yazıcı Test Planı (Sıfır Canlı Satış / Stok Riski)
1. Yazıcı testi için kesinlikle gerçek bir satış fişi kesilmeyecek ve stok düşülmeyecektir.
2. İzole test modunda doğrudan yazıcı portuna veya Windows yazdırma kuyruğuna:
   - Fiş için: `*** SERENUT OS GÜVENLİK TESTİ (SATIŞ DEĞİLDİR) ***` başlıklı ESC/POS metin bloğu,
   - Etiket için: `TEST BARKOD: 00000000` içerikli TSPL etiket şablonu gönderilecektir.
3. Fiziksel çıktı testi yalnızca kullanıcı/operatör onayı alındığında tetiklenecektir.
4. Yazıcı sürücü ve port konfigürasyonları değiştirilmeyecektir.

---

## 9. Çalıştırılan Testler ve Gerçek Sonuçları

### 1. Python Adli Denetim Betiği
```bash
python scripts/stage10_12_44_live_safe_export_import_audit.py
```
- **Sonuç:** `PASS` (Exit code: 0)
- **Doğrulamalar:**
  * 19 Ekim yedeği ile canlı DB WAL ayrımı kanıtlandı.
  * 8 adımlı aktarım provası icra edildi; idempotens doğrulandı (mükerrer kayıt = 0).
  * Erkul çeyiz işlem semantiği ayrıştırıldı (`manual_debt`: 423 adet / 4.31M TL, `collection`: 109 adet / 541.6K TL).
  * Windows yazıcıları (`POS-80`, `etiket`) doğrulandı.
  * Kaynak dosyalar için 0 bayt mutasyon teyit edildi.

### 2. Flutter / Dart Entegrasyon Test Paketi
```bash
flutter test test/core_next/stage10_12_44_live_safe_export_import_test.dart
```
- **Sonuç:** `All tests passed! (6 passed, 0 failed)`
- **Kapsam:**
  * Test 1.1: `coreNextSalesEngineEnabledProvider = false` ve `databaseRoutingHook = null`.
  * Test 1.2: `PilotCutoverGate` fail-closed (Nutopia, Erkul, Serenut için bloklu).
  * Test 2.1: 19 Ekim yedeği statik zaman kesiti ve canlı WAL zaman damgası ayrımı.
  * Test 3.1: İzole snapshot, idempotens ve kaynak dokunulmazlık garantisi.
  * Test 4.1: Erkul Çeyiz `manual_debt` ve `collection` semantik doğrulaması.
  * Test 5.1: Yazıcı donanım ve rota profillerinin salt-okunur teyidi.

---

## 10. Bilinen Riskler ve Geçiş Kararı

| Risk | Etki | Önleyici Tedbir |
|---|---|---|
| **Canlı İşletme Veri Sapması** | Mağaza açıkken geçiş yapılırsa 19 Ekim'den sonraki fişler kaybolabilir | Geçiş yalnızca mağaza kapalıyken nihai snapshot ile yapılabilir |
| **CDC Mekanizması Yokluğu** | Canlı anlık çift yazma denemesi SQLite kilitlenmesine yol açar | Canlı çift yazma reddedildi; Store-Closed Catch-up zorunlu |
| **Erkul Kart Bakiyesi Tutarsızlığı** | Otomatik bakiye düzeltmesi yasal ve mali ihtilaf doğurur | İşletme sahibinin yazılı onayı olmadan bakiye düzeltilemez |
| **Yazıcı Donanım Portu Çakışması** | Satış esnasında port meşguliyeti yazdırma kuyruğunu tıkayabilir | ESC/POS ve TSPL rotaları izole test fişiyle doğrulanmalıdır |

### Nihai Karar: **`BLOCKED`**
Canlı geçiş, üretim yönlendirmesi ve `coreNextSalesEngineEnabledProvider = true` yapılması **KESİNLİKLE BLOKELİDİR**.
Geçiş ancak mağaza kapalıyken alınacak onaylı bir final snapshot ve işletme mutabakatı sonrasında açılabilecektir.
