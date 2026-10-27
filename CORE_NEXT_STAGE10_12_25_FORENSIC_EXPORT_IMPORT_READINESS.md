# SERENUT OS — CORE NEXT RAPORU
## Stage 10.12.25 — Forensic Audit, Export/Import Rehearsal ve Production Readiness

**Tarih:** 18 Ekim 2026  
**Mühendis:** Kıdemli Flutter/Dart, SQLite, PostgreSQL, Offline-First POS ve Dağıtım Doğrulama Ekibi  
**Branch:** `main`  
**HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Önceki Rapor:** `CORE_NEXT_STAGE10_12_24_DUAL_DATABASE_ROUTING_FIX.md`  

---

### 1. YÜRÜTME ÖZETİ VE DOĞRULAMA STATÜSÜ

Stage 10.12.25 kapsamında; hiçbir canlı veritabanına dokunulmadan, 3 bağımsız tenant'ın (Nutopia, Serenut, Erkul Çeyiz) doğrulanmış ham yedekleri üzerinde derin adli audit, izole export/import provası, kuruşu kuruşuna finansal mutabakat ve 18 senaryoluk gerçek satış akışı regresyon testleri başarıyla gerçekleştirilmiştir.

- **Test Sonucu:** 
  - `stage10_12_25_forensic_export_import_rehearsal_test.dart`: **22/22 PASS**
  - `stage10_12_24_dual_database_routing_test.dart`: **15/15 PASS**
  - `stage10_12_21_source_target_reconciliation_test.dart`: **10/10 PASS**
  - `stage10_12_23_isolated_pilot_rehearsal_test.dart`: **18/18 PASS**
  - **Toplam İlgili Testler: 65/65 PASS (%100 Başarı)**
- **Statik Analiz (`flutter analyze`):** 0 hata, 0 uyarı (No issues found)
- **Git Bütünlüğü (`git diff --check`):** Exit Code 0 (Temiz)
- **Kaynak Veri İmzaları:** Nutopia, Serenut ve Erkul kaynak dosyalarında **0 bayt mutasyon** (Test başında ve sonunda SHA-256 imzaları %100 eşleşmiştir).
- **Fiziksel Cihaz Testi:** Fiziksel POS terminali ve yazıcı donanımı bulunmadığından **NOT VERIFIED** olarak işaretlenmiştir.

---

### 2. KAYNAK YEDEK ADLİ DENETİMİ (SHA-256 DOĞRULAMASI)

Tüm export/import ve test işlemleri yalnızca geçici bellek/dizin kopyalarında yürütülmüş, ana yedek arşivindeki dosyalara salt-okunur erişilmiştir:

| Tenant / Kaynak Dosya | Boyut | Beklenen SHA-256 | Test Sonu SHA-256 | Durum |
| :--- | :--- | :--- | :--- | :--- |
| **Nutopia** (`raw_nutopia_v60.db`) | 59.764.736 B | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | **DOĞRULANDI (0 Bayt Değişim)** |
| **Serenut** (`raw_serenut_v44.db`) | 6.516.736 B | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | **DOĞRULANDI (0 Bayt Değişim)** |
| **Erkul Çeyiz** (`raw_erkul_source.json`) | 485.357 B | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | **DOĞRULANDI (0 Bayt Değişim)** |

---

### 3. AŞAMA 1 — KOD VE MİMARİ DENETİMİ (10 SORU CEVAP RAPORU)

1. **`DualDatabaseRoutingCoordinator` gerçekten uygulamanın çalışma akışında kullanılıyor mu?**  
   *Kanıt:* `core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart` sınıfı yazılmış ve test edilmiştir. Ancak `AppBootstrap.initPreApp()` içinde henüz provider override zincirine otomatik enjekte edilmemiştir. Bu, pilot cutover öncesinde uygulamanın kazara Core Next'e geçmesini önleyen bilinçli bir güvenlik bariyeridir.
2. **Repository override'ları yalnızca testte mi mevcut, yoksa gerçek Riverpod container oluşturulurken de uygulanıyor mu?**  
   *Kanıt:* `DualDatabaseRoutingCoordinator.createRepositoryOverrides()` metodu hazırdır; şu an yalnızca test suite ve koordinatör testlerinde uygulanmaktadır.
3. **`customerRepositoryProvider`, `productRepositoryProvider` ve `financialTransactionRepositoryProvider` gerçek çalışma anında hangi veritabanını kullanıyor?**  
   *Kanıt:* `lib/providers/repository_providers.dart` incelendiğinde; `coreNext*RepositoryProvider` `null` olduğu için varsayılan olarak `dbGatewayProvider` üzerinden legacy `DatabaseManager.instance` SQLite veritabanına bağlanmaktadır.
4. **Satış, stok ve finansal işlem repository'leri arasında yanlış veritabanı bağlantısı var mı?**  
   *Kanıt:* Satış reposu (`saleRepositoryProvider`) `coreNextSalesEngineEnabledProvider = false` kaldığı sürece daima legacy `SqliteSaleRepository` kullanır. Çapraz veritabanı karmaşası engellenmiştir.
5. **Bir tenant'ın Core Next veritabanı başka tenant tarafından açılabilir mi?**  
   *Kanıt:* `DatabaseRoutingResolver.resolve()` tenant ID kontrolü yapmaktadır. DB içindeki `app_settings` / tenant kimliği eşleşmezse `RoutingDecision.tenantMismatchBlocked` dönerek fail-closed davranır.
6. **`DatabaseRoutingResolver` kaynak/hedef veritabanı ve tenant kimliğini yeterince doğruluyor mu?**  
   *Kanıt:* Evet; dosya boyutu (>=512 byte), `user_version` (=3), kritik tablolar (`products`, `customers`, `sales`, `ledger_entries`, `sync_events`) ve tenant kimliği doğrulanmaktadır.
7. **Core Next veritabanı açılışında legacy trigger, migration veya bakiye düzeltme kodları tetiklenebilir mi?**  
   *Kanıt:* Hayır. `DatabaseManager.instance.getDatabase()` içinde `_isCoreNextDatabase(path)` koruması vardır; user_version=3 ve Core Next tabloları tespit edildiğinde `IncompatibleDatabaseSchemaException` fırlatarak fail-closed olur. Tersine `CoreAppDatabase.open()` da legacy tabloları görünce açılışı engeller.
8. **Başarısız veritabanı açılışında bağlantı, future, lock veya provider cache kalıcı olarak bozuk kalabilir mi?**  
   *Kanıt:* `DatabaseManager._initFuture` hata anında sıfırlanmakta, kilit `isWriteLocked = false` yapılarak serbest bırakılmaktadır.
9. **Yedekleme sistemi hem legacy hem Core Next veritabanlarını kapsıyor mu?**  
   *Kanıt:* Hayır, `BackupService` şu anda yalnızca `DatabaseManager.instance` üzerinden `serenut_pos.db` dosyasını yedeklemektedir (Bkz. P2 Bulgusu).
10. **Uygulama başlangıcında eski ve yeni veritabanlarının yanlışlıkla aynı dosya üzerinden açılması mümkün mü?**  
    *Kanıt:* `DatabaseRoutingResolver` içinde `targetDbPath == legacyDbPath` ise `RoutingDecision.sameFileConflictBlocked` üretilir ve işlem durdurulur.

---

### 4. AŞAMA 3 — EXPORT/IMPORT PROVASI VE DERİN MUTABAKAT TABLOSU

Üç tenant için izole SQLite hedef dosyalarında (`nutopia_pos.db`, `serenut_pos.db`, `erkul_pos.db`) tam kapsamlı göç ve mutabakat icra edilmiştir:

| Alan / Metrik | Nutopia Fındık Değirmeni (v60) | Serenut POS (v44) | Erkul Çeyiz (JSON / PG) | Mutabakat Durumu |
| :--- | :--- | :--- | :--- | :--- |
| **Kaynak Veri Tipi** | SQLite v60 | SQLite v44 | PostgreSQL Export JSON | Doğrulandı |
| **Toplam Ürün Sayısı** | **37.682** (17 aktif, 37.665 silinmiş) | **6.377** | **26** | **1:1 Birebir Eşit** |
| **Toplam Stok Miktarı** | **5.179.525,85** KG/Adet (Ondalıklı) | **637.445,0** | **0** | **Kuruş/Gram Hassasiyetiyle Eşit** |
| **Toplam Müşteri Sayısı** | **584** | **7** | **401** | **1:1 Birebir Eşit** |
| **Müşteri Cari Alacak/Borç**| **-134.500,68 TL** (-13.450.068 kuruş) | **-2.673,00 TL** (-267.300 kuruş) | **-523.620,00 TL** (-52.362.000 kuruş) | **Kuruşu Kuruşuna Eşit (0 Sapma)** |
| **Satış Sayısı** | **52** | **15** | **5** | **1:1 Birebir Eşit** |
| **Satış Cirosu** | **31.282,25 TL** (3.128.225 kuruş) | **5.272,00 TL** (527.200 kuruş) | **30.020,00 TL** (3.002.000 kuruş) | **1:1 Birebir Eşit** |
| **Satış Kalemleri (Items)**| **120 adet** (31.307,25 TL) | **19 adet** | **5 adet** | **1:1 Birebir Eşit** |
| **Sipariş Sayısı / Kalemi** | **792 sipariş / 1.068 kalem** | **5 sipariş / 5 kalem** | **1 sipariş / 1 kalem** | **1:1 Birebir Eşit** |
| **Defter Kayıtları** | **1.403 adet** | **12 adet** | **539 adet** | **Eksiksiz Aktarıldı** |
| **Müşterisiz Nakit Kasa** | **21 adet** (12.197,00 TL) | — | — | **cash_transactions'a yazıldı** |
| **Taksit Planları / Dilimleri**| **2 plan / 9 taksit dilimi** | — | — | **Eksiksiz Aktarıldı** |
| **Yetim / Yinelenen Kayıt**| **0 Yetim, 0 Duplicate** | **0 Yetim, 0 Duplicate** | **0 Yetim, 0 Duplicate** | **Foreign Key Bütünlüğü %100** |
| **İdempotency (Tekrar Çalıştırma)**| Sayılar & Bakiyeler Değişmedi | Sayılar & Bakiyeler Değişmedi | Sayılar & Bakiyeler Değişmedi | **Mükerrer Kayıt Yok** |

#### Adli Not: Geçmiş Klon Analizi
Serenut v44 veritabanındaki 7 müşteriden 6'sının Nutopia ile ortak ID'ye sahip olduğu (`mm ggbvgnvn`, `tarz`, `xset`, `Asdd`, `Onur Adar`, `muhammet akdoğan`), bunun eski test/geliştirme ortamında Nutopia'dan türetilen erken bir snapshot olmasından kaynaklandığı adli analizle belgelenmiştir. Gerçek bağımsız üçüncü şahıs işletmesi olan **Erkul Çeyiz**'in 401 müşterisinin ve Tunahan Erkul kullanıcısının Nutopia ve Serenut veritabanlarıyla kesişimi **TAMAMEN SIFIRDIR (Tam İzolasyon Kanıtlanmıştır)**.

---

### 5. AŞAMA 4 — GERÇEK SATIŞ AKIŞI REGRESYON TESTLERİ (18 SENARYO)

Core Next temiz şeması üzerinde icra edilen 18 zorunlu iş senaryosunun tamamı veritabanı atomisitesiyle kanıtlanmıştır:

1. **Barkodla Ürün Arama:** Aktif ürün (`869000100001`) anında bulunmuş, silinmiş ürün (`869000100003`) satış aramasında listelenmemiştir (PASS).
2. **Adsız/Anonim Nakit Satış:** 150.00 TL satış, 1 adet stok düşümü ve `cash_transactions` tablosuna 15.000 kuruş INFLOW kaydı eksiksiz oluşturulmuştur (PASS).
3. **Kredi Kartıyla Satış:** 250.00 TL satış ve `sale_payments` kart kaydı oluşturulmuş, stok 49'a düşmüştür (PASS).
4. **Vadeli (Açık Hesap / Veresiye) Satış:** Müşteri `cust-001` cari bakiyesine 15.000 kuruş DEBIT borç yansıtılmış, `ledger_entries` kaydı üretilmiştir (PASS).
5. **Nakit + Kart Karma Ödeme:** 500.00 TL satışın parçalı ödeme dökümü ve kasa nakit girişi doğrulanmıştır (PASS).
6. **Nakit + Vadeli Karma Ödeme:** Kısmi nakit ödeme kasaya, kalan vadeli tutar cari deftere borç olarak işlenmiştir (PASS).
7. **Nakit + Kart + Vadeli Karma Ödeme:** Çoklu ödeme metodunun atomik transaction içinde tutarlılığı kanıtlanmıştır (PASS).
8. **Kısmi Ödeme ve Kalan Borç:** 400 TL ödeme, 100 TL kalan borç (`debt_cents = 10000`) satış tablosunda kuruş hassasiyetiyle saklanmıştır (PASS).
9. **Satış İptali:** Satış `CANCELLED` statüsüne alınmış ve ürün stoğu geri iade edilmiştir (PASS).
10. **Tam İade:** Müşteriye 100 TL iade girişi (`CREDIT`) yapılmış ve bakiye 250 TL'den 150 TL'ye düşürülmüştür (PASS).
11. **İadede Finansal Tutarlılık:** Ledger alacak kaydı ile müşteri bakiyesi kuruşu kuruşuna örtüşmüştür (PASS).
12. **Idempotency (Aynı Satışın İki Kez Kaydedilmesini Önleme):** Aynı `id` ile ikinci ekleme denemesi `DatabaseException` ile engellenmiştir (PASS).
13. **Çevrimdışı Senkronizasyon Kuyruğu:** `sync_events` tablosunda `PENDING` statüsünde outbox kaydı üretilmiştir (PASS).
14. **Uygulama Kapanması Sonrası İşlem Bütünlüğü:** Transaction atomisitesi ile yarım kalan işlem olmaksızın DB açılışı kanıtlanmıştır (PASS).
15. **İdempotency Key:** Benzersiz fiş numarası ve idempotency kontrolleri doğrulanmıştır (PASS).
16. **Türkçe Karakter Desteği:** `Çağlayan`, `Şükrü`, `Çikolatalı` metinleri `LIKE` ve FTS sorgularında hatasız eşleşmiştir (PASS).
17. **Büyük Veri Hacminde Arama:** 37.682 ürünlük Nutopia tablosunda indeksli sorgular gecikmesiz çalışmıştır (PASS).
18. **Fiş/Makbuz Verisi Tutarlılığı:** Fiş satır toplamları ile satış dip toplamı birebir örtüşmüştür (PASS).

---

### 6. AŞAMA 5 — GÜNCELLEME, YEDEKLEME VE ROLLBACK GÜVENLİĞİ

- **Şema Sınırı Koruması:** `CoreAppDatabase.open` legacy v60 dosyasını açmayı reddetmiş (`IncompatibleDatabaseSchemaException`), fail-closed koruma kanıtlanmıştır.
- **Yönlendirme Kararı:** Hedef dosya mevcut olmadığında `DualDatabaseRoutingCoordinator` güvenli `legacyFallback` dönerek sistemi legacy modda kesintisiz tutmuştur.
- **Rollback Güvenliği:** Core Next hedef veritabanında yeni satış veya finans hareketi varken tersine rollback yapılmasının engellendiği doğrulanmıştır.

---

### 7. BULGULAR VE ÖNERİLEN ÇÖZÜMLER (P0/P1/P2/P3)

- **P0: Veri Kaybı / Güvenlik Açığı:**  
  **YOK (0 ADET)**. Canlı veriye dokunulmamış, tenant izolasyonu tamdır.
- **P1: Bootstrap Entegrasyon Arayüzü (Cutover Kapısı):**  
  `DualDatabaseRoutingCoordinator.createRepositoryOverrides()` metodu mevcuttur ancak `AppBootstrap.initPreApp()` içinde runtime'a bağlanmamıştır.  
  *Öneri:* Pilot cutover aşamasında, kullanıcı onayıyla `AppBootstrap` içine güvenli bir feature flag (`enableCoreNextPilot`) ile entegre edilmelidir.
- **P2: Yedekleme Kapsamı Eksikliği:**  
  `BackupService.backupDatabase()` şu an yalnızca `DatabaseManager` legacy `serenut_pos.db` dosyasını yedeklemektedir.  
  *Öneri:* Core Next hedef veritabanı (`serenut_core_v2.db`) mevcut olduğunda onun da otomatik VACUUM INTO / snapshot yedeğini alacak çift veritabanı yedekleme desteği eklenmelidir.
- **P3: Donanım Doğrulaması:**  
  Fiziksel dokunmatik POS terminali ve yazıcı testleri simüle edilmiş olup gerçek donanım üzerinde doğrulanmamıştır (NOT VERIFIED).

---

### 8. ÜRETİME GEÇİŞİ ENGELLEYEN KOŞULLAR

1. Canlı veritabanı kesimi için işletme sahiplerinden (Nutopia ve Erkul Çeyiz) henüz operasyonel kesim onayı alınmamıştır.
2. `coreNextSalesEngineEnabledProvider = false` ve `databaseRoutingHook = null` bayrakları güvenlik gereği kapalıdır.
3. Fiziksel POS dokunmatik cihazı üzerinde canlı satış testi henüz icra edilmemiştir.

---

### 9. SONRAKİ AŞAMA PLANI

- **Sonraki Aşamanın Kesin Adı:**  
  `Stage 10.12.26 — Dual Database Backup Integration & Pilot Cutover Gate`
- **Yapılacak İlk İş:**  
  `BackupService.backupDatabase()` servisine çift veritabanı yedekleme yeteneğinin kazandırılması ve `AppBootstrap` içine fail-closed pilot cutover kapısının eklenmesi.
