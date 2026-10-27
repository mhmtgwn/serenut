# SERENUT OS — CORE NEXT STAGE 10.12.42
## Yedek Kimliği Tutarlılık Denetimi + İzole Core Next Import Provası Raporu

**Proje:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Tarih:** 19 Ekim 2026  
**Hedef Branch:** `main`  
**Beklenen Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Doğrulanan Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Genel Değerlendirme Kararı:** **`BLOCKED`**

---

### 1. Git Başlangıç ve Bitiş Durumu

Denetim boyunca çalışma ağacı ve Git durumu tamamen değişmez tutulmuştur:

- **`git rev-parse HEAD`:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **`git branch --show-current`:** `main`
- **`git diff --check`:** 0 hata / 0 uyarı (temiz)
- **Kullanıcı WIP Durumu:** Kullanıcının 22 adet değiştirilmiş dosyası ve `core_next/`, `test/core_next/` altındaki untracked geliştirme dosyaları eksiksiz korunmuş; hiçbir `git reset`, `git clean`, `checkout`, `stash`, `add` veya `commit` komutu çalıştırılmamıştır.
- **Güvenlik Sabitleri:**
  - `coreNextSalesEngineEnabledProvider = false` (korundu)
  - `DatabaseManager.databaseRoutingHook = null` (korundu)

---

### 2. Yedek Dosyalarının Envanteri, Mutlak Yolları ve Kriptografik Özetleri

OneDrive ve yerel repo altındaki tüm kritik yedek dosyaları tekil tanıtıcılar üzerinden incelenmiş ve doğrulanmıştır:

| Dosya Tanımı | Mutlak Dosya Yolu | Dosya Boyutu (Bayt) | Değiştirilme Zamanı | SHA-256 Özeti |
| :--- | :--- | :--- | :--- | :--- |
| **OneDrive Canlı Yedeği** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db` | **61,390,848** | 2026-10-19 16:10:45 | `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` |
| **OneDrive Snapshot Asıl DB** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\serenut_pos.db` | **61,390,848** | 2026-10-19 16:10:45 | `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` |
| **OneDrive Snapshot Core Next (Nutopia)** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\nutopia_pos.db` | **17,010,688** | 2026-10-16 18:53:20 | `c976b4d243800c763525078b9c8e9931375a1bf88fe6afca727461c230c61753` |
| **OneDrive Snapshot Core Next (Serenut)** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\serenut_pos.db` | **2,355,200** | 2026-10-16 18:53:22 | `a7cc9d22e2d4489789a9536b6c3f3018c699a5ca5daecbe2be04b32a7c7e2273` |
| **OneDrive Snapshot Core Next (Erkul)** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\erkul_pos.db` | **557,056** | 2026-10-16 18:53:23 | `ad744fcf4aa5c4af0e0628b58fc7b15db1695d21173bdf5087655da5f1067860` |
| **Workspace Ham Nutopia v60** | `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_nutopia_v60.db` | **59,764,736** | 2026-10-16 18:52:59 | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` |
| **Workspace Ham Serenut v44** | `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_serenut_v44.db` | **6,516,736** | 2026-09-30 20:56:43 | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` |
| **Workspace Ham Erkul JSON** | `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_erkul_source.json` | **485,357** | 2026-10-16 16:26:02 | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` |

---

### 3. Stage 40–41 Boyut Çelişkisinin Çözümü ve Kanıtı

Stage 10.12.40 raporunda `serenut_pos_backup_20261019_161042.db` için **61,390,848 bayt** ve SHA-256 `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` bildirilmişken, Stage 10.12.41 raporunun özet tablosunda aynı dosya ve aynı hash için sehven **9,076,736 bayt** yazılmıştır.

Bu tutarsızlığın kök nedeni adli inceleme ile kanıtlanmıştır:
1. **Fiziksel Dosya Değişmezliği:** Diskteki gerçek dosya boyutu her iki aşamada da ve şu anda tam **61,390,848 bayttır**.
2. **Yedek Doğum Belgesi Kanıtı:** Dosyanın oluşturulduğu an kaydedilen `SNAPSHOT_20261019_161042\BACKUP_REPORT.json` dosyasında `standalone_backup.size_bytes: 61390848` ve `sha256: da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` olarak mühürlenmiştir.
3. **Stage 40 Test Çıktısı:** `stage10_12_40_rehearsal_results.json` dosyasında boyut `61390848` olarak doğrulanmıştır.
4. **Çelişkinin Nedeni:** Diskte 9,076,736 bayt boyutunda hiçbir dosya bulunmamaktadır. Stage 41 raporunu üreten önceki model oturumunda, Markdown tablosuna bayt sayıları girilirken transkripsiyon hatası yapılmış, ancak SHA-256 hash'i ve çalıştırılan testler gerçek dosya (`61,390,848` bayt) üzerinden yapılmıştır.
5. **Sonuç:** Dosya kimliği ve bütünlüğü şüphesiz biçimde kanıtlanmış olup dosyanın gerçek boyutu **61,390,848 bayttır**.

---

### 4. Nutopia İzole Migration Eşlemeleri ve Kayıt Bazlı Mutabakat

Doğrulanmış canlı yedeğin (`serenut_pos_backup_20261019_161042.db`) izole bir kopyası üzerinde `MigrationBridgeEngine.migrateFromLegacy` tam kapsamlı (`fullScope: true`) çalıştırılmıştır.

#### 4.1. Tablo ve Kayıt Mutabakatı

| Varlık / Tablo | Kaynak v60 (19 Ekim Yedeği) | Hedef Core Next v3 | Eşleme Kuralları ve Durum |
| :--- | :--- | :--- | :--- |
| **Ürünler (`products`)** | 37,682 | **37,682** | Kuruş dönüşümü `price * 100`, stok `quantity` alanı doğrudan `stock_quantity`ye aktarıldı. |
| **Müşteriler (`customers`)** | 601 | **601** | 584 eski + 17 yeni müşteri. `balance_cents = balance * 100`. Discrepancy: 0. |
| **Satışlar (`sales`)** | 52 | **52** | Fişler `subtotal_cents`, `total_cents`, `paid_cents` ve `debt_cents` ile aktarıldı. |
| **Satış Kalemleri (`sale_items`)** | 120 | **120** | Ürün ve satış bağlantıları eksiksiz korundu. |
| **Siparişler (`orders`)** | 814 | **814** | 792 eski + 22 yeni sipariş. **Satışlara karıştırılmadı, ayrı `orders` tablosuna aktarıldı.** |
| **Sipariş Kalemleri (`order_items`)** | 1,099 | **1,099** | 1068 eski + 31 yeni kalem. `order_items` tablosuna tam eşleşti. |
| **Müşteri Defteri (`ledger_entries`)** | 1,445 | **1,445** | Müşterili tüm finansal hareketler (1403 eski + 42 yeni) immutable deftere aktarıldı. |
| **Nakit Kasa (`cash_transactions`)** | 21 | **21** | Müşterisiz 21 adet anonim satış işlemi genel kasa hareketine yönlendirildi. |
| **Toplam Finansal Hareket** | 1,466 | **1,466** | 1445 cari defter + 21 kasa nakit = 1466 (%100 tam mutabakat). |

#### 4.2. Net -526.40 Birim Stok Çıkışının Kayıt Düzeyinde İspatı
Stage 41'de raporlanan -526.40 birimlik net stok farkının, 16-19 Ekim arasında açılan 22 siparişin içerisindeki **31 yeni sipariş kaleminden (`order_items`)** kaynaklandığı matematiksel olarak %100 kanıtlanmıştır:
1. `Kır Kavur 0.5 Pk.` (b956674a-...): Sipariş edilen miktar = **223.0** -> Stok değişimi = **-223.0**
2. `Kır Kavur 1Kg Pk.` (74296569-...): Sipariş edilen miktar = **212.1** -> Stok değişimi = **-212.1**
3. `Ezme Kavanoz` (a4e94c39-...): Sipariş edilen miktar = **76.0** -> Stok değişimi = **-76.0**
4. `Kavurma` (f9a0a0c0-...): Sipariş edilen miktar = **5.8** -> Stok değişimi = **-5.8**
5. `Ezme Kabuklu` (e6db3adf-...): Sipariş edilen miktar = **5.5** -> Stok değişimi = **-5.5**
6. `Kır 1Kg Pk.` (0d32a523-...): Sipariş edilen miktar = **4.0** -> Stok değişimi = **-4.0**
- **Toplam Sipariş Çıkışı:** **526.40 birim**
- **Toplam Net Stok Değişimi:** **-526.40 birim**
- **Açıklanamayan Stok Farkı:** **0.00 birim (SIFIR)**

#### 4.3. Bütünlük ve İdempotens
- **`PRAGMA integrity_check`:** `ok`
- **`PRAGMA foreign_key_check`:** `0` ihlal
- **İdempotens:** Aynı veritabanı üzerine ikinci kez migration çalıştırıldığında satır sayıları değişmemiş, çift kayıt oluşmamıştır.
- **FK Güvenliği:** Sipariş bağlantılı finansal hareketlerin `reference_id` değerleri `sales` tablosunda aranmış; satış olmadığı için `ledger_entries.reference_sale_id = NULL` atanarak foreign key kısıtlamasının ihlal edilmesi engellenmiştir.

---

### 5. Erkul JSON → Core Next Eşlemeleri ve Kritik Veri Uyuşmazlığı

`raw_erkul_source.json` kaynağının Core Next şemasına doğrudan aktarımı analiz edilmiş ve kritik bir defter uyuşmazlığı saptanmıştır:

#### 5.1. Varlık Eşlemesi
- 401 müşteri, 26 ürün, 5 satış, 5 satış kalemi, 1 sipariş, 1 sipariş kalemi ve 539 finansal hareket başarıyla izole geçici Core Next v3 tablolarına yerleştirilebilmektedir.
- `PRAGMA integrity_check`: `ok`
- `PRAGMA foreign_key_check`: `0` ihlal

#### 5.2. Kritik Finansal Uyuşmazlık (Defter Açığı)
- **Müşteri Kayıtlarındaki Bakiye Toplamı (`customers.balance`):** `-523,620.00 TL`
- **Finansal Hareketler Giriş (`collection` + `payment`):** `541,650.00 TL`
- **Finansal Hareketler Çıkış (`sale` + `manual_debt`):** `4,340,775.00 TL`
- **Finansal Hareketlerin Net Etkisi:** **`-3,799,125.00 TL`**
- **Açıklanamayan Defter Farkı:** **`3,275,505.00 TL`**
- **Bakiye-Defter Tutarsızlığı Olan Cari Sayısı:** 401 müşteriden **395 tanesi (%98.5)**!
- **Sonuç:** Erkul JSON kaynağında yer alan finansal hareketler, müşterilerin güncel bakiyelerini açıklamamaktadır. Üretim kodundaki `MigrationBridgeEngine` bu tür bir uyumsuzlukta `MÜŞTERİ BAKİYE SAPMASI TESPİT EDİLDİ` hatası fırlatarak göçü durduracak (FAIL-CLOSED) şekilde tasarlanmıştır.

---

### 6. Test Komutları ve Gerçek Sonuçları

Tüm testler gerçek terminal ortamında çalıştırılmış ve tam başarı elde edilmiştir:

#### 6.1. Python İzole Prova Betiği
- **Komut:** `python scripts/stage10_12_42_isolated_import_rehearsal.py`
- **Sonuç:** `Exit Code: 0`
- **Doğrulamalar:**
  - Nutopia 19 Ekim yedeğinden Core Next v3 tablolarına aktarım: Tam başarı.
  - Hedef satır sayıları: Ürün=37,682, Müşteri=601, Satış=52, Sipariş=814, SiparişKalem=1,099, Defter=1,445, Kasa=21.
  - Foreign key ihlali: 0. İdempotens: Korundu.
  - Erkul 3.275M TL bakiye-defter tutarsızlığı tespit edildi ve raporlandı.

#### 6.2. Flutter Test Paketi ([stage10_12_42_isolated_import_and_backup_identity_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_42_isolated_import_and_backup_identity_test.dart))
- **Komut:** `flutter test test/core_next/stage10_12_42_isolated_import_and_backup_identity_test.dart`
- **Sonuç:** `Exit Code: 0` (**10 testin 10'u PASS**, süre: 30s)
  - `1.1: coreNextSalesEngineEnabledProvider = false ve databaseRoutingHook = null korunur` -> **PASS**
  - `1.2: Stage 40–41 yedek boyutu çelişkisinin çözümü ve kimlik tespiti` -> **PASS**
  - `1.3: Kaynak dosyaların işlem öncesi ve sonrası değişmezliği` -> **PASS**
  - `2.1: En güncel doğrulanmış kaynaktan izole Core Next migration ve mutabakat` -> **PASS**
  - `2.2: Net -526.40 birim stok çıkışının 31 yeni sipariş kalemiyle 1:1 mutabakatı` -> **PASS**
  - `2.3: İkinci kez çalıştırmada çift kayıt oluşmaması (İdempotens)` -> **PASS**
  - `2.4: Aynı ID içeriğinde çakışma (CONFLICT) tespiti` -> **PASS**
  - `2.5: Hata anında işlemin atomik geri alınması (Rollback)` -> **PASS**
  - `3.1: Erkul JSON 395 cari bakiye sapması ve 3.275M TL defter açığı tespiti` -> **PASS**
  - `3.2: Erkul için resmî Legacy .db yedeği bulunmadığının doğrulanması` -> **PASS**

#### 6.3. Linter Statik Analiz
- **Komut:** `flutter analyze test/core_next/stage10_12_42_isolated_import_and_backup_identity_test.dart`
- **Sonuç:** `No issues found! (ran in 8.8s)` (`Exit Code: 0`)

#### 6.4. Git Diff Kontrolü
- **Komut:** `git diff --check`
- **Sonuç:** `Exit Code: 0` (Temiz)

---

### 7. Kaynak Dosyaların Değişmezlik Kontrolü

İşlem öncesi ve sonrası tüm kaynak dosyaların kriptografik özetleri (SHA-256) karşılaştırılmış, 1 bayt dahi değişmediği kanıtlanmıştır:
- `serenut_pos_backup_20261019_161042.db`: `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` (**Değişmedi**)
- `raw_nutopia_v60.db`: `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` (**Değişmedi**)
- `raw_erkul_source.json`: `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` (**Değişmedi**)

---

### 8. Çözülemeyen Çatışmalar ve Riskler

1. **Erkul'un 3.275 Milyon TL Defter Uyuşmazlığı:**
   Erkul JSON kaynağında müşterilerin statik borç bakiyeleri ile hareket kayıtları arasında 3,275,505.00 TL tutarsızlık vardır. Hangi tarafın yasal/doğru bakiye olduğu bilinmeden Core Next'e aktarılması durumunda carilerin geçmiş hareketleri ile güncel bakiyeleri çelişecektir.
2. **Erkul İçin Resmî Rollback Noktası Yok:**
   Erkul Çeyiz'e ait hiçbir SQLite v60/v44 binary yedeği bulunmamaktadır. Cutover sonrası herhangi bir arıza halinde geriye dönülebilecek yetkili bir Legacy veritabanı mevcut değildir.
3. **Mevcut Core Next Snapshot'ının Eskiliği:**
   OneDrive snapshot dizinindeki `SNAPSHOT_20261019_161042\core_next\nutopia_pos.db` dosyası 16 Ekim tarihlidir ve canlı dükkanın son 3 günlük sipariş ve tahsilatlarını barındırmamaktadır. Canlıya geçiş öncesinde bu dosyanın taze göçürülmüş olanla değiştirilmesi zorunludur.

---

### 9. Genel Karar: `BLOCKED`

| Alan | Durum | Gerekçe |
| :--- | :--- | :--- |
| **Yedek Kimliği / Boyut Tutarlılığı** | **PASS** | 61,390,848 bayt doğrulanmış, Stage 41'deki 9,076,736 sayısının transkripsiyon hatası olduğu kanıtlanmıştır. |
| **Nutopia İşlem Mutabakatı** | **PASS** | 17 müşteri, 42 finansal hareket, 22 sipariş, 31 sipariş kalemi ve -526.40 stok çıkışı 1:1 çözülmüş ve doğrulanmıştır. |
| **Erkul Çeyiz Veri Güvenliği** | **BLOCKED** | Resmî SQLite yedeği bulunmamakta, JSON kaynağında ise 395 müşteride 3.275M TL bakiye-defter uyuşmazlığı bulunmaktadır. |
| **GENEL SONUÇ** | **`BLOCKED`** | Erkul'un finansal uyuşmazlığı resmi kararla çözülmeden ve canlı snapshot yenilenmeden cutover veya pilot başlatılamaz. |

---

### 10. Bir Sonraki Aşama İçin Somut Koşullar

1. **Erkul İçin Resmi Mutabakat Kararı:**
   - Erkul Çeyiz için müşterilerin güncel bakiyeleri mi (`customers.balance`), yoksa işlem hareketleri mi (`financial_transactions`) esas alınacak belirlenmeli; aradaki 3.275M TL'lik fark için bir "Açılış/Devir Bakiyesi Düzeltme Hareketi" (Opening Balance Adjustment) uygulanıp uygulanmayacağı işletme sahibince yazılı onaylanmalıdır.
2. **Nutopia Core Next Snapshot'ının Güncellenmesi:**
   - İzole provada tam başarıyla doğrulanmış olan 19 Ekim Core Next SQLite dosyası, OneDrive snapshot dizinindeki eski 16 Ekim tarihli `SNAPSHOT_20261019_161042\core_next\nutopia_pos.db` dosyasının yerine konulmalıdır.
3. **Canlı Güvenlik Sınırlarının Devamı:**
   - Bu koşullar sağlanana kadar `coreNextSalesEngineEnabledProvider = false` ve `DatabaseManager.databaseRoutingHook = null` sabitleri asla değiştirilmemelidir.
