# Stage 10.12.27 — Pilot Cutover Controlled Rollout & Hardware E2E Verification Raporu

**Tarih:** 18 Ekim 2026  
**Aşama:** `Stage 10.12.27 — Pilot Cutover Controlled Rollout & Hardware E2E Verification`  
**Proje / Çalışma Alanı:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Branch:** `main`  
**Önceki Aşama:** `Stage 10.12.26 — Dual Database Backup Integration & Pilot Cutover Gate`  
**Sonuç / Karar:** `READY_FOR_PILOT_REVIEW`  
*(Teknik ve yazılımsal E2E hazırlıkları %100 tamamlandı; feature flag varsayılan olarak kapalıdır; fiziksel POS donanımı test ortamında bulunmadığından cihaz bazlı saha testleri NOT RUN olarak işaretlenmiştir).*

---

## 1. Başlangıç Durumu & Git Doğrulaması

- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Branch:** `main`
- **Git Diff & Whitespace Kontrolü:** `git diff --check` -> **0 hata / Temiz**
- **Sıfır Mutasyon İlkesi:** 3 bağımsız tenant referans yedeğinin (`raw_nutopia_v60.db`, `raw_serenut_v44.db`, `raw_erkul_source.json`) başlangıç ve bitiş SHA-256 imzaları kuruşu kuruşuna ve baytı baytına eşleşti; **0 bayt mutasyon** kesinleşti.

---

## 2. Stage 10.12.26 Bağımsız Güvenlik Denetimi ve Sertleştirmeler (P0)

Önceki aşamada devreye alınan çift veritabanı yedekleme ve pilot cutover gate kodları derinlemesine incelenmiş ve tespit edilen noktalar anında sertleştirilmiştir:

### 2.1 Geri Yükleme Sırasında Eşzamanlı Yazma Koruması
- **Bulgu:** `BackupService.restoreDatabase()` metodu dosya takasını `.bak` korumasıyla güvenli yaparken, `DatabaseManager.isWriteLocked` bayrağını set etmiyordu.
- **Düzeltme & Sertleştirme:** `restoreDatabase()` metodu başına `DatabaseManager.isWriteLocked = true;` eklendi ve tüm işlem bir `try ... finally` bloğuna alınarak işlem bittiğinde veya hata aldığında kilidin mutlaka `false` yapılması sağlandı. Bu sayede geri yükleme sırasında açık bağlantıların veritabanına yazması engellendi.

### 2.2 PilotCutoverGate Yedekleme Kanıtı (Backup Proof) Sertleştirmesi
- **Bulgu:** `PilotCutoverGate` Rule 4 kontrolünde, eğer `migrationBackupPath` belirtilmişse ancak dosya diskte bulunamadıysa veya < 512B bozuksa, `lastBackupDate` stringinin varlığından ötürü geçit yanlışlıkla geçebiliyordu.
- **Düzeltme & Sertleştirme:** Kural katılaştırıldı: `migrationBackupPath` parametresi kayıtlıysa, belirtilen dosyanın fiziksel olarak diskte var olduğu ve `>= 512 bayt` geçerli bir dosya olduğu kesin olarak doğrulanır; dosya eksik veya bozuksa `lastBackupDate` olsa dahi fail-closed (`backupProofFound = false`) tetiklenir.

### 2.3 Acil Durum Devre Kesici (Kill Switch) Statik Yardımcıları
- **Bulgu:** Kill-switch yalnızca açılışta SharedPreferences üzerinden okunuyordu; runtime esnasında acil tetikleme için standart bir yardımcı metod yoktu.
- **Düzeltme & Sertleştirme:** `PilotCutoverGate.isKillSwitchActive(prefs)` ve `PilotCutoverGate.triggerEmergencyKillSwitch(prefs)` statik yardımcıları eklendi. Herhangi bir anomali anında operatör veya bekçi (watchdog) sistemi tek bir çağrıyla tüm Core Next geçişini anında kapatabilir.

### 2.4 Guard Başarısızlığında Karışık Repo Oluşmama Teminatı
- `AppBootstrap.initPreApp()` test edilerek doğrulandı: Pilot bayrağı kapalıyken (`core_next_pilot_enabled = false`), `pilotGateResult.overrides` listesi boştur (`[]`). Riverpod sağlayıcıları istisnasız %100 Legacy SQLite repository'lerine (`SqliteProductRepository`, `SqliteCustomerRepository`, `SqliteSaleRepository`, `SqliteFinancialTransactionRepository`) bağlanır. Karışık veya kısmi geçiş durumu imkansızdır.

---

## 3. Gerçek Satış Akışı Uçtan Uca (E2E) 14 İş Senaryosu Doğrulaması (P0)

İzole test veritabanı üzerinde 14 iş senaryosu kuruşu kuruşuna, stok ve bakiye hareketleri izlenerek çalıştırılmış ve **14/14 PASS** elde edilmiştir:

| No | Senaryo Tanımı | Test Edilen Bileşenler & Doğrulama Eşiği | Durum |
|---|---|---|---|
| **1** | **Barkodla Ürün Arama** | Aktif ürün (`869000100001`) anında döner; silinmiş ürünler (`is_deleted = 1`) satış sorgusunda filtrelenir. | **PASS** |
| **2** | **Sepet & Stok Yönetimi** | 100 adet stoktan 2 adet satış yapıldığında stok tam 98 adede düşer. | **PASS** |
| **3** | **Anonim Nakit Satış** | `customer-pesin-default` müşterisi, 150.00 TL toplam, 150.00 TL tahsilat, 0 TL borç; kasa hareketi (`cash_transactions`) 150.00 TL giriş. | **PASS** |
| **4** | **Kredi Kartıyla Satış** | 300.00 TL kartlı satış; `sale_payments` tablosuna `credit_card` ödeme tipiyle kaydedilir. | **PASS** |
| **5** | **Vadeli Satış (Erkul Çeyiz)** | Mehmet Erkul cari hesabına 850.00 TL vadeli satış; `ledger_entries` (DEBIT) 850.00 TL; müşteri bakiyesi tam 850.00 TL artar. | **PASS** |
| **6** | **Karma Ödeme (Split Payment)** | 850.00 TL toplam: 200 TL Nakit + 300 TL Kart + 350 TL Vadeli; ödeme parçaları toplamı 850.00 TL kuruş sapmasız kaydedilir. | **PASS** |
| **7** | **Satış İptali ve İade** | İptal edilen satışta ürün stoku (+1) iade edilir, müşteri cari borcu (-150 TL) düşürülür, satış `CANCELLED` olur. | **PASS** |
| **8** | **Idempotency Koruması** | Aynı satış ID'si veya idempotency anahtarıyla ikinci kez gelen istek PRIMARY KEY / Unique kısıtıyla reddedilir, mükerrer satış engellenir. | **PASS** |
| **9** | **İnternet Kesintisi & Offline Kuyruk** | Çevrimdışı yapılan satış anında yerel `sync_events` tablosuna `PENDING` durumuyla yazılır; ağ gelene kadar kuyrukta kalır. | **PASS** |
| **10** | **Kapanıp Yeniden Açılma (Restart)** | Veritabanı bağlantısı tamamen kapatılıp yeniden açıldığında kaydedilen tüm ürün, satış ve kuyruk verileri %100 korunur. | **PASS** |
| **11** | **Mükerrer Senkronizasyon Engeli** | İşlenmiş (`SYNCED`) bir senkronizasyon olayının tekrar işlenmesi engellenir. | **PASS** |
| **12** | **Türkçe Karakter & Yuvarlama** | `Çift Kavrulmuş Giresun Fındığı & Şekerli Çörek` gibi Türkçe karakterler bozulmaz; 199.99 TL x 3 = 599.97 TL kuruşu kuruşuna hesaplanır (0 kuruş sapma). | **PASS** |
| **13** | **Satış Motoru Güvenlik Sınırı** | `coreNextSalesEngineEnabledProvider` varsayılan olarak kesinlikle `false` kalır; legacy satış motoru emniyeti korunur. | **PASS** |
| **14** | **Başarısız İşlemde Atomik Rollback** | Çok adımlı satış işlemi esnasında hata fırlatıldığında veritabanı transaction rollback uygular; stok veya bakiye yarım kalmaz. | **PASS** |

---

## 4. Fiziksel Donanım Doğrulaması (ESC/POS, Barkod, Terazi) (P0)

Test ortamı yazılım geliştirme konteyneri / Windows iş istasyonudur. Gerçek fiziki donanımın bağlı olduğunu varsaymak kesinlikle yasaklanmış; mock sonuçlar yerine açık cihaz durumu raporlanmıştır:

| Donanım Türü | Protokol / Sürücü Desteği | Simülasyon / Kod Analizi | Fiziksel Test Durumu |
|---|---|---|---|
| **ESC/POS Termal Fiş Yazıcı** | USB (Windows Spooler), TCP/Ethernet (9100), Bluetooth ESC/POS | `EscPosReceiptRenderer` kod yapısı `escpos-v1` formatını, Türkçe karakterleri (CP857 / UTF-8) ve kesiciyi destekler. | **NOT RUN** *(Fiziksel termal yazıcı bağlı değil)* |
| **Barkod Okuyucu** | USB/Bluetooth HID Klavye Modu (`BarcodeScannerMixin`) | 80ms karakter akış tamponu, `KeyDownEvent` yakalama, `canHandleBarcodeScan()` modal ekran kontrolü kod düzeyinde doğrulandı. | **NOT RUN** *(Fiziksel barkod tabancası bağlı değil)* |
| **Hassas Terazi (Scale)** | RS232 / COM Port / TCP Port 4001 | `HardwareDeviceType.scale` ve COM3 konfigürasyonu veri modeli düzeyinde hazır. | **NOT RUN** *(Fiziksel terazi bağlı değil)* |

> [!IMPORTANT]
> **Donanım Kuralı Hatırlatması:** Gerçek sahaya çıkmadan önce fiziksel bir USB termal yazıcı ve barkod tabancası ile fiziki test yapılmalı, operatör kontrol listesi imzalanmalıdır.

---

## 5. Pilot Öncesi ve Sonrası Kontrol Planı (Controlled Rollout Plan)

Pilot uygulama **tek bir mağaza, tek bir terminal ve tek bir tenant (Serenut Merkez Şube)** ile sınırlandırılmıştır.

### 5.1 Pilot Öncesi Kontrol Listesi (Pre-Pilot Checklist)
1. **Tenant Doğrulaması:** Terminalde tanımlı `tenant_id` değerinin pilot hedefine ait olduğunun doğrulanması.
2. **Yedekleme Kanıtı:** `BackupService.backupDualDatabases()` çalıştırılarak hem `serenut_pos_backup_*.db` hem de `serenut_core_v2_backup_*.db` dosyalarının ve JSON manifestinin oluşturulduğunun tespiti.
3. **Geri Yükleme Provası:** Geçici bir test kopyası üzerinde restore provasının başarılı geçmesi.
4. **Finansal Mutabakat:** Açılış kasa bakiyesi ve açık müşteri bakiyelerinin yazılı olarak teyit edilmesi.
5. **Bekleyen Senkronizasyon:** `sync_events` kuyruğunda `PENDING` veya `IN_FLIGHT` işlem bulunmaması (`kuyruk = 0`).
6. **Donanım Test Çıktısı:** Test fişinin basılması, Türkçe karakterlerin ve kağıt kesiminin gözle kontrol edilmesi.

### 5.2 Pilot Sırasında İzlenecekler (Runtime Monitoring)
- **Satış ve Ödeme Hataları:** Terminal loglarında `DatabaseException` veya `SqfliteFfiException` takibi.
- **Stok Farkları:** Satılan ürünlerin fiziksel stok ile ekran stoğu arasındaki farkın 0 olması.
- **Cari Bakiye Tutarlılığı:** Veresiye satışlarda müşterinin borç hareketinin çift taraflı muhasebe (`ledger_entries`) ile tam örtüşmesi.
- **Kuyruk Gecikmesi:** Çevrimdışı kuyruğun internet geldiğinde sırayla ve mükerrersiz akması.

### 5.3 Acil Geri Alma (Emergency Rollback) Tetikleyicileri
Aşağıdaki durumlardan herhangi biri gerçekleşirse pilot derhal durdurulur:
- Kuruş farkı veya mükerrer satış kaydı oluşması.
- Uygulamanın satış esnasında kilitlenmesi veya çökmesi.
- `PilotCutoverGate.triggerEmergencyKillSwitch()` çağrısı ile saniyeler içinde fail-closed Legacy moduna dönülmesi.
- Oluşan Core Next hareketlerinin geri taşınabilmesi için çift yönlü sync audit kayıtlarının saklanması.

---

## 6. Otomatik Test Sonuçları Özeti

| Test Paketi | Test Sayısı | Başarılı | Başarısız | Açıklama |
|---|---|---|---|---|
| `test/core_next/stage10_12_27_pilot_hardware_e2e_test.dart` | 24 | **24** | 0 | Yeni E2E, güvenlik sertleştirme ve adli kontrol testleri |
| `test/services/dual_database_backup_service_test.dart` | 10 | **10** | 0 | Çift veritabanı yedekleme ve akıllı geri yükleme |
| `test/core_next/stage10_12_26_pilot_cutover_gate_test.dart` | 13 | **13** | 0 | 10 kademeli fail-closed cutover kapısı matrisi |
| `test/services/backup_service_test.dart` | 3 | **3** | 0 | Geriye dönük uyumlu legacy yedekleme servis testleri |
| `test/core_next/stage10_12_24_dual_database_routing_test.dart` | 15 | **15** | 0 | Çift veritabanı şema ve yönlendirme izolasyonu |
| `test/core_next/stage10_12_25_forensic_export_import_rehearsal_test.dart` | 22 | **22** | 0 | 3 tenant bağımsız adli denetim ve derin mutabakat |
| **TOPLAM** | **87** | **87** | **0** | **%100 Başarı Oranı** |

---

## 7. Açık Bulgular & Kalan Riskler

- **P0 Bulgusu:** Yok. Tüm yazılım, şema, kilit ve finansal güvenlik engelleri aşılmıştır.
- **P1 Bulgusu:** Fiziksel donanım testlerinin fiziki ortamda yapılmamış olması (Cihazlar `NOT RUN` durumundadır).
- **P2 Bulgusu:** Operatör eğitim dokümanı ve fiziksel acil durum butonu saha kılavuzunun yazdırılması.

---

## 8. Son Karar ve Sonraki Adımlar

### 🏁 Karar: `READY_FOR_PILOT_REVIEW`

**Açıklama:**
Yazılımsal, mimari ve finansal tüm güvenlik geçitleri, çift veritabanı yedekleme ve atomik kurtarma mekanizmaları, 14 kritik satış senaryosu ve 3 tenant veri dokunulmazlığı **%100 doğrulanmıştır**. Sistem, kontrollü pilot denemesi için teknik olarak tamamen hazırdır. Ancak fiziksel ESC/POS yazıcı ve barkod tabancası testleri geliştirici ortamında fiziksel donanım bulunmadığından **NOT RUN** durumundadır. Canlı terminalde fiziksel cihaz testi ve insan operatör onayı tamamlanana kadar feature flag'ler (`core_next_pilot_enabled = false` ve `coreNextSalesEngineEnabledProvider = false`) varsayılan kapalı emniyet durumunda tutulmaktadır.

### 📋 Sonraki Aşama
**Stage 10.12.28 — Field Hardware On-Site Acceptance & Controlled Single-Terminal Pilot Deployment**
1. Pilot mağazada (Serenut) terminal başında fiziksel ESC/POS termal yazıcı ve barkod tabancası ile canlı test fişi basımı.
2. Yetkili operatör tarafından kontrol listesinin onaylanması.
3. Kontrollü olarak feature flag'in yalnızca bu terminalde açılması ve ilk canlı satışın gözetim altında gerçekleştirilmesi.
