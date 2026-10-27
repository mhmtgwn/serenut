# SERENUT OS — CORE NEXT STAGE 10.12.41
## Erkul Legacy Recovery Tasarımı + Nutopia Delta Mutabakatı Denetim Raporu

**Proje:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Tarih:** 19 Ekim 2026  
**Hedef Branch:** `main`  
**Beklenen Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Doğrulanan Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Genel Değerlendirme Kararı:** **`BLOCKED`**

---

### 1. Başlangıç Git Durumu

Denetim öncesinde Git çalışma ağacı ve HEAD bütünlüğü tam olarak doğrulanmıştır:

- **`git rev-parse HEAD`:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **`git branch --show-current`:** `main`
- **`git diff --check`:** 0 hata / 0 uyarı (temiz)
- **Kullanıcı WIP Durumu:** Kullanıcının mevcut 22 adet değiştirilmiş dosyası ve untracked geliştirme dizinleri (`core_next/`, `test/core_next/`) eksiksiz korunmuş, hiçbir reset, checkout, stash veya commit işlemi yapılmamıştır.

---

### 2. İncelenen Kaynaklar ve SHA-256 Doğrulaması

Tüm kaynak kopyaların varlığı, dosya boyutları ve kriptografik özetleri (SHA-256) denetim öncesinde ve sonrasında tam olarak karşılaştırılmış ve değişmezlikleri kanıtlanmıştır:

| Kaynak Dosya / Bileşen | Dosya Boyutu (Bayt) | SHA-256 Özeti | Durum |
| :--- | :--- | :--- | :--- |
| `backups/raw_tenants_20261016/raw_nutopia_v60.db` | 9,072,640 | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | Doğrulandı |
| `backups/raw_tenants_20261016/raw_erkul_source.json` | 485,357 | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | Doğrulandı |
| `OneDrive/Belgeler/.../serenut_pos_backup_20261019_161042.db` | 9,076,736 | `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` | Doğrulandı |
| `OneDrive/Belgeler/.../SNAPSHOT_20261019_161042/core_next/nutopia_pos.db` | 7,507,968 | `e1342674eec7f8f9024f2b19289d311394a114771e8bf02416bcae884f1bb542` | Doğrulandı |
| `OneDrive/Belgeler/.../SNAPSHOT_20261019_161042/core_next/erkul_pos.db` | 258,048 | `785a21e64627ec7fef3756ffca4a5fb8fc6d5b0351ce7c9fe101aa0a0129e1fa` | Doğrulandı |

---

### 3. Erkul JSON Şeması ve Legacy Uyumluluk Matrisi

`raw_erkul_source.json` dosyasının şematik analizi yapılmış, 11 anahtar altındaki veri yapısı çıkarılmış ve uygulamanın gerçek Legacy SQLite v60 şemasıyla (`lib/infrastructure/database/database_provider.dart`) eşleştirilmiştir:

#### 3.1. Varlık Dağılımı ve Sayımları
- **`companies`:** 1 kayıt (Firma profili)
- **`stores`:** 1 kayıt (Mağaza)
- **`users`:** 1 kayıt (Kasiyer / Kullanıcı)
- **`customers`:** 401 kayıt
- **`products`:** 26 kayıt
- **`sales`:** 5 kayıt
- **`sale_items`:** 5 kayıt
- **`financial_transactions`:** 539 kayıt
- **`customer_orders`:** 1 kayıt
- **`customer_order_items`:** 1 kayıt
- **`inventory_movements`:** 5 kayıt
- **`refunds`:** 0 kayıt

#### 3.2. Legacy Tablo ve Alan Uyumluluk Matrisi

| Legacy v60 Tablosu | JSON Kaynak Alanları | Legacy Zorunlu Alanlar | Eksik / Türetilen Alanlar | Uyumluluk Durumu |
| :--- | :--- | :--- | :--- | :--- |
| `customers` | id, name, phone, email, address, balance, is_active, created_at, updated_at | id, name | `balance_minor` (türetildi: balance * 100) | Uyumlu |
| `products` | id, name, price, purchase_price, stock, unit, barcode, category, is_active | id, name, price, quantity | JSON `stock` -> Legacy `quantity`. `price_minor`, `purchase_price_minor` (türetildi: price * 100). `vat` eksik (varsayılan %1) | Uyumlu (Dönüştürme gerekli) |
| `sales` | id, receipt_no, total_amount, payment_type, customer_id, cashier_id, date | id, receipt_no, total_amount, payment_type | `total_amount_minor` (türetildi: amount * 100). `date` -> `created_at` | Uyumlu |
| `sale_items` | id, sale_id, product_id, quantity, unit_price, total_price | id, sale_id, product_id, quantity, unit_price | `unit_price_minor`, `total_price_minor` (türetildi: price * 100) | Uyumlu |
| `financial_transactions` | id, customer_id, type, amount, description, payment_method, date | id, customer_id, type, amount | `amount_minor` (türetildi: amount * 100). JSON `date` -> Legacy `created_at` | Uyumlu |
| `orders` | id, order_number, customer_id, total_amount, status, date | id, order_number, customer_id | `total_amount_minor` (türetildi: amount * 100) | Uyumlu |
| `order_items` | id, order_id, product_id, quantity, unit_price, total_price | id, order_id, product_id | `unit_price_minor`, `total_price_minor` (türetildi: price * 100) | Uyumlu |
| `refunds` | (Kayıt yok - Boş liste) | id, sale_id, amount | JSON kaynağında iade verisi bulunmamaktadır. | Bilgi Eksikliği |

#### 3.3. Kritik Eksiklikler ve Kanıtlanamayan Alanlar
1. **`_minor` Alanları:** JSON kaynağında `price_minor`, `balance_minor`, `amount_minor` tamsayı kuruş değerleri bulunmamaktadır. Bunlar ondalıklı sayıların 100 ile çarpılmasıyla türetilmektedir; ancak yuvarlama riskleri taşır.
2. **Kullanıcı Kimlik Doğrulama:** `users` tablosunda Legacy uygulamanın gerektirdiği parola hash'leri ve yetki bayrakları bulunmamaktadır.
3. **Gerçek SQLite İkili Yedeği Yok:** Erkul için geriye dönük resmi bir Legacy SQLite `.db` dosyası bulunmamaktadır. JSON'dan üretilen dosya sentetik bir izdüşümdür.

---

### 4. Erkul Dönüştürme Prototipi Sonucu ve Bütünlük Doğrulaması

İzole geçici klasörde (`stage41_erkul_proto_...`) çalışan `scripts/stage10_12_41_erkul_legacy_reconstruction_prototype.py` ile JSON kaynağı tam Legacy v60 şemasına dönüştürülmüş ve SQLite motoru üzerinden doğrulanmıştır:

- **`PRAGMA integrity_check`:** `ok` (0 bozuk sayfa)
- **`PRAGMA foreign_key_check`:** `0` ihlal (Tüm yabancı anahtarlar eksiksiz bağlandı)
  - 5 satış kaydının tümü geçerli müşterilere bağlıdır.
  - 5 satış kaleminin tümü geçerli satışlara ve ürünlere bağlıdır.
  - 539 finansal hareketin tümü mevcut müşterilere bağlıdır.
- **Mali ve Stok Toplamları:**
  - **Toplam Stok:** `1,000,242` birim
  - **Toplam Müşteri Bakiyesi:** `-523,620.00 TL` (`-52,362,000` kuruş)
  - **Toplam Satış Tutarı:** `30,020.00 TL` (`3,002,000` kuruş)
  - **Toplam Finansal Hareket:** `4,882,425.00 TL` (`488,242,500` kuruş)
- **Prototip Dosya Boyutu:** 303,104 bayt (SHA-256: `ccc324813f1b65bde41dde06122c2f12ecfe1394e9244456c865a09a340f6315`)
- **Prototip Durumu:** Prototip temiz bir şekilde doğrulanmış ve ardından izole geçici dizin silinmiştir. **Bu prototip kesinlikle gerçek bir yedek veya yetkili geri dönüş noktası olarak nitelendirilemez.**

---

### 5. Nutopia İşlem Bazlı Delta Mutabakatı

16 Ekim 2026 dondurulmuş arşivi (`raw_nutopia_v60.db`) ile 19 Ekim 2026 OneDrive canlı yedeği (`serenut_pos_backup_20261019_161042.db`) arasındaki farklar satır satır incelenmiş ve doğrulanmıştır:

#### 5.1. Müşteriler (Customers)
- **16 Ekim Müşteri Sayısı:** 584
- **19 Ekim Müşteri Sayısı:** 601
- **Fark:** Tam olarak **+17 `NEW` müşteri**.
- **Silinen Müşteri:** 0
- **`CHANGED` Müşteri:** 16 müşterinin vadeli bakiyesi değişmiştir.
- **Örnek Yeni Müşteri ID'leri:**
  - `5dac4d70-d922-42c2-8025-a1c2211c21e6` (SARIÇİÇEK, Bakiye: 0.0)
  - `228d82db-fe5f-4228-aa92-c07a9dc197d1` (CEMİL AŞÇI, Bakiye: 0.0)
  - `335e27a7-19a9-4673-8cb9-bc17d3b36e8b` (MURAT BALCI, Bakiye: 0.0)
  - `57ce22ee-d933-4903-8d26-728448ea9e51` (MUSTAFA DİŞLİ, Bakiye: 0.0)

#### 5.2. Finansal Hareketler (Financial Transactions)
- **16 Ekim Finansal İşlem Sayısı:** 1,424
- **19 Ekim Finansal İşlem Sayısı:** 1,466
- **Fark:** Tam olarak **+42 `NEW` finansal hareket**.
- **Silinen / Değişen İşlem:** 0 (Eski 1,424 işlem birebir korunmuştur).
- **Yeni Hareketlerin Tutar Dağılımı ve Türleri:**
  - **15 adet `payment` (Nakit / Havale Ödeme):** Toplam `6,150.00 TL`
  - **24 adet `sale` (Sipariş/Veresiye Satış - `ord-...` referanslı):** Toplam `93,840.00 TL`
  - **2 adet `manual_debt` (Manuel Borçlandırma):** Toplam `1,000.00 TL`
  - **1 adet `collection` (Tahsilat):** Toplam `10,000.00 TL`
  - **Net Finansal Hareket Toplamı:** **Tam `+110,990.00 TL`**.

#### 5.3. Müşteri Siparişleri (Customer Orders)
- **16 Ekim Sipariş Sayısı:** 792
- **19 Ekim Sipariş Sayısı:** 814
- **Fark:** Tam olarak **+22 `NEW` sipariş** (`SP-000791` ile `SP-000814` arası).
- Canlı işletmede 16-19 Ekim arasında yapılan veresiye satışların doğrudan POS kasa satış ekranından (`sales`) değil, telefonla sipariş / sipariş modülü (`orders`) üzerinden açıldığı ve finansal hareket kaydı oluşturduğu ispatlanmıştır.

#### 5.4. Kasa Satışları ve Satış Kalemleri (Sales & Sale Items)
- **16 Ekim:** 52 satış (31,282.25 TL) / 120 satış kalemi (206.0 adet)
- **19 Ekim:** 52 satış (31,282.25 TL) / 120 satış kalemi (206.0 adet)
- **Fark:** 0 yeni kasa satışı (`sales` tablosu bu 3 günde statik kalmıştır).

#### 5.5. Ürün Stok Farkları (Product Stock / Quantity)
Tüm 37,682 ürün taranmış, tam olarak **6 adet `CHANGED` ürün** tespit edilmiştir:

| Ürün Adı | 16 Ekim Miktar | 19 Ekim Miktar | Net Stok Değişimi | Sınıflandırma |
| :--- | :--- | :--- | :--- | :--- |
| **Ezme Kavanoz** | 100.0 | 24.0 | **-76.00** | `CHANGED` |
| **Kır Kavur 0.5 Pk.** | 300.0 | 77.0 | **-223.00** | `CHANGED` |
| **Kavurma** | 20.0 | 14.2 | **-5.80** | `CHANGED` |
| **Kır Kavur 1Kg Pk.** | 300.0 | 87.9 | **-212.10** | `CHANGED` |
| **Ezme Kabuklu** | 20.0 | 14.5 | **-5.50** | `CHANGED` |
| **Kır 1Kg Pk.** | 100.0 | 96.0 | **-4.00** | `CHANGED` |
| **TOPLAM STOK FARKI** | — | — | **-526.40 birim** | `CHANGED` |

---

### 6. Mutabakatı Çözülemeyen Kayıtlar ve Kritik Riskler

1. **Snapshot Tazelik Uçurumu:**
   OneDrive üzerindeki `SNAPSHOT_20261019_161042/core_next/nutopia_pos.db` dosyası, 16 Ekim tarihli arşivden göçürülmüştür. Canlı dükkanın 16-19 Ekim arasındaki:
   - **17 yeni müşterisi,**
   - **42 finansal hareketi (+110.990 TL),**
   - **22 müşteri siparişi,**
   - **-526.40 birimlik stok çıkışı**
   Core Next veritabanında **YOKTUR**. Mevcut snapshot ile canlıya geçilmesi durumunda 3 günlük gerçek işletme verisi tamamen kaybedilecektir.
2. **Erkul'un Yetkili Geri Dönüş Güvencesi Yok:**
   Erkul Çeyiz için geriye dönük resmi bir SQLite yedeği bulunmamaktadır. Sentetik prototip ilişkisel bütünlüğü sağlasa da, yetkili onay ve resmi bir geri dönüş güvencesi olmadan tek başına canlı geçiş için kullanılamaz.

---

### 7. Test Komutları ve Gerçek Sonuçları

Tüm testler gerçek komutlarla yürütülmüş, hiçbir simülasyon veya tahmini değer raporda yer almamıştır:

#### Test 1: Erkul Legacy Reconstruction Prototype Testi
- **Komut:** `python scripts/stage10_12_41_erkul_legacy_reconstruction_prototype.py`
- **Sonuç:** `Exit Code: 0`
- **Çıktı Özeti:**
  - `Integrity Check: [('ok',)]`
  - `Foreign Key İhlalleri: 0`
  - `Toplam Stok: 1,000,242`
  - `Toplam Bakiye: -523,620.00 TL`
  - `Kaynak JSON SHA-256 Değişmezliği: True`

#### Test 2: Stage 10.12.41 Kapsamlı Flutter Test Paketi
- **Komut:** `flutter test test/core_next/stage10_12_41_erkul_recovery_nutopia_delta_test.dart`
- **Sonuç:** `Exit Code: 0` (13 testin 13'ü PASS)
- **Koşulan Testler:**
  - `1.1: coreNextSalesEngineEnabledProvider = false ve databaseRoutingHook = null korunur` -> **PASS**
  - `1.2: Kaynak dosya hash değerlerinin işlem öncesi ve sonrası değişmezliği kanıtlanır` -> **PASS**
  - `2.1: Erkul JSON zorunlu alan eksikliği tespiti ve reddi` -> **PASS**
  - `2.2: Yinelenen veya geçersiz kimlik tespiti` -> **PASS**
  - `2.3: Eksik müşteri / satış referansı (Foreign Key kırılması) tespiti` -> **PASS**
  - `2.4: İzole SQLite geçici veritabanında bütünlük (PRAGMA integrity & FK) doğrulaması` -> **PASS**
  - `2.5: Hata durumunda geçici dönüşüm işleminin atomik geri alınması (rollback)` -> **PASS**
  - `3.1: Nutopia 16 Ekim ve 19 Ekim yedeğinde 17 NEW müşteri doğrulanır` -> **PASS**
  - `3.2: Nutopia 16 Ekim ve 19 Ekim yedeğinde 42 NEW finansal işlem (+110.990 TL) doğrulanır` -> **PASS**
  - `3.3: Nutopia stok farkı (-526.40 birim) işlem ve ürün bazında doğrulanır` -> **PASS**
  - `3.4: Aynı ID içeriğinde çakışma (CONFLICT) tespiti` -> **PASS**
  - `3.5: Aynı işlemin tekrar işlendiğinde çift kayıt oluşturmaması (İdempotens)` -> **PASS**
  - `3.6: Açıklanamayan bakiye ve stok farklarının körü körüne ezilmesinin engellenmesi` -> **PASS**

#### Test 3: Statik Analiz (Linter)
- **Komut:** `flutter analyze test/core_next/stage10_12_41_erkul_recovery_nutopia_delta_test.dart`
- **Sonuç:** `Exit Code: 0` (`No issues found!`)

#### Test 4: Git Whitespace & Syntax Bütünlüğü
- **Komut:** `git diff --check`
- **Sonuç:** `Exit Code: 0` (Temiz)

---

### 8. Korunan Güvenlik Sınırları

Aşama boyunca mutlak güvenlik sınırlarına titizlikle riayet edilmiştir:
- [x] Canlı veritabanlarına (`assets/db/nutopia.db`, `serenut_pos.db`, `serenut_core_v2.db`) hiçbir yazma, migration, cutover veya rollback uygulanmamıştır.
- [x] `coreNextSalesEngineEnabledProvider = false` değeri korunmuştur.
- [x] `DatabaseManager.databaseRoutingHook = null` değeri korunmuştur.
- [x] Gerçek satış, tahsilat, iade, stok veya bakiye işlemi oluşturulmamıştır.
- [x] Canlı veritabanı dosyaları taşınmamış, silinmemiş ve üzerine yazılmamıştır.
- [x] `git reset`, `git clean`, checkout, stash, add veya commit yapılmamıştır.
- [x] Tüm testler yalnızca geçici izole dosyalarda icra edilmiş, kaynak hash'leri sabit kalmıştır.

---

### 9. Genel Karar: `BLOCKED`

| Kriter | Durum | Gerekçe |
| :--- | :--- | :--- |
| **Erkul Çeyiz Recovery** | **BLOCKED** | Erkul için yetkili ve orijinal bir Legacy `.db` yedeği bulunmamaktadır. JSON'dan dönüştürülen prototip ilişkisel bütünlük sağlasa da, resmi bir geri dönüş noktası olarak onaylanmamıştır. |
| **Nutopia Canlı Delta** | **BLOCKED** | 16-19 Ekim arasındaki 17 yeni müşteri, 42 finansal hareket (+110.990 TL) ve -526.40 stok çıkışı mevcut Core Next snapshot'ında bulunmamaktadır. Snapshot güncellenmeden canlı geçiş veri kaybına neden olur. |
| **GENEL SONUÇ** | **BLOCKED** | Canlı cutover, routing, pilot açılışı veya satış motoru aktivasyonu KESİNLİKLE YAPILAMAZ. |

---

### 10. Bir Sonraki Aşamaya Geçiş İçin Gereken Somut Koşullar

1. **Erkul Çeyiz Kurumsal Kararı:**
   - Erkul Çeyiz için sentetik Legacy DB üretimi mi yapılacağı yoksa doğrudan Core Next'e temiz bir import motoru ile mi aktarılacağı konusunda onay verilmelidir.
2. **Nutopia Core Next Snapshot'ının Yeniden Göçürülmesi:**
   - 19 Ekim saat 16:10 yedeği (`serenut_pos_backup_20261019_161042.db`) esas alınarak, izole bir ortamda Core Next'e taze bir göç (re-migration) icra edilmeli ve 17 müşteri + 42 finansal hareket + 22 sipariş + 526.40 stok farkının Core Next tablolarına eksiksiz aktarıldığı kanıtlanmalıdır.
3. **Delta Senkronizasyon Motoru Onayı:**
   - Cutover anına kadar dükkanda devam eden canlı işlemlerin Core Next'e kayıpsız taşınması için sipariş (`orders`) ve finansal işlem (`financial_transactions`) köprüsünün hazır olduğu onaylanmalıdır.
