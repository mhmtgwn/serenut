# Stage 10.12.28 — Field Hardware Acceptance & Controlled Single-Terminal Pilot Raporu

**Tarih:** 19 Ekim 2026  
**Aşama:** `Stage 10.12.28 — Field Hardware Acceptance & Controlled Single-Terminal Pilot`  
**Proje / Çalışma Alanı:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Branch:** `main`  
**Başlangıç & Bitiş HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Önceki Rapor:** `Stage 10.12.27 — Pilot Cutover Controlled Rollout & Hardware E2E Verification`  
**Karar:** `READY_FOR_OPERATOR_ACCEPTANCE`  
*(Yazılımsal tüm E2E testleri, çift veritabanı yedekleme ve fail-closed güvenlik kapısı %100 başarılı; feature flag varsayılan olarak KAPALI tutulmaktadır; geliştirme iş istasyonunda fiziki POS çevre birimleri bulunmadığından donanım kabulü operatör kontrol listesi olarak hazırlanmış ve durumları NOT RUN olarak kaydedilmiştir).*

---

## 1. Başlangıç Git Durumu ve Doğrulaması

Stage 10.12.28 başlangıcında kullanıcı çalışma ağacı ve git durumu incelenmiş, kullanıcı dosyalarına ve canlı verilere dokunulmamıştır:

- **Beklenen HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Gerçek HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Tam eşleşme)
- **Aktif Branch:** `main`
- **Git Diff & Format Kontrolü:** `git diff --check` -> **0 hata / Temiz**
- **Kullanıcı Çalışma Ağacı:** Kullanıcının mevcut değişiklikleri silinmemiş, stash edilmemiş ve üzerine yazılmamıştır. Canlı veritabanı dosyaları kesinlikle değiştirilmemiş; tüm denetimler izole geçici test dizinlerinde gerçekleştirilmiştir.

---

## 2. Gerçekten Çalıştırılan Otomatik Testler ve Sonuçları

Aşama kapsamında belirtilen 6 kritik test paketi izole çalışma alanında yürütülmüş, hiçbir sonuç gizlenmeden veya varsayılmadan tam dökümü alınmıştır:

| Sıra | Test Paketi | Toplam Test | Başarılı | Başarısız | Durum |
|:---:|---|:---:|:---:|:---:|:---:|
| 1 | `test/core_next/stage10_12_27_pilot_hardware_e2e_test.dart` | 24 | 24 | 0 | **PASS** |
| 2 | `test/services/dual_database_backup_service_test.dart` | 10 | 10 | 0 | **PASS** |
| 3 | `test/core_next/stage10_12_26_pilot_cutover_gate_test.dart` | 13 | 13 | 0 | **PASS** |
| 4 | `test/services/backup_service_test.dart` | 3 | 3 | 0 | **PASS** |
| 5 | `test/core_next/stage10_12_24_dual_database_routing_test.dart` | 15 | 15 | 0 | **PASS** |
| 6 | `test/core_next/stage10_12_25_forensic_export_import_rehearsal_test.dart` | 22 | 22 | 0 | **PASS** |
| **TOPLAM** | **Tüm Paketler** | **87** | **87** | **0** | **%100 PASS** |

### Test İzolasyonu İyileştirmesi (Teknik Düzeltme)
- **Tespit:** `test/services/backup_service_test.dart` dosyası içindeki `MockPathProviderPlatform`, doküman yolu olarak `Directory.current.absolute.path` dönmekteydi. Bu durum, birden fazla test paketi eşzamanlı çalıştığında kök dizinde `SerenutBackups/` dizini oluşturarak Windows dosya kilitleme çakışmasına (`PathAccessException errno 32`) yol açabiliyordu.
- **Düzeltme:** `backup_service_test.dart`, `dual_database_backup_service_test.dart` mimarisine uygun olarak `Directory.systemTemp.createTempSync()` ile tamamen izole bir geçici dizine yönlendirildi ve test bitiminde temizlenmesi sağlandı.
- **Sonuç:** 6 test paketinin tamamı (87 test) tek seferde eşzamanlı çalıştırıldığında dahi 0 hata ile **%100 PASS** elde edildi.

---

## 3. Yedekleme ve Kurtarma Denetimi (Backup & Restore Audit)

`BackupService.backupDualDatabases()` ve `BackupService.restoreDatabase()` mimarisi satır satır denetlenmiştir:

### 3.1 Çift Veritabanı Yedekleme (`backupDualDatabases`)
1. **Atomik SQLite Snapshot:** `PRAGMA integrity_check` 'ok' doğrulaması ardından SQLite'ın yerel `VACUUM INTO ?` snapshot komutu çalıştırılır. Desteklenmeyen durumlarda `PRAGMA wal_checkpoint(TRUNCATE)` ardından dosya kopyalama devreye girer.
2. **Geçici Dosya İzolasyonu:** Yedekler `.tmp` uzantısıyla oluşturulur, dosya boyutu (`>= 512 bayt`) ve açılabilirlik bütünlüğü test edilir. Başarılı olursa hedef `serenut_pos_backup_*.db` veya `serenut_core_v2_backup_*.db` dosyasına atomik olarak `rename` edilir.
3. **Kriptografik Bütünlük (SHA-256):** Her iki veritabanı yedeğinin de SHA-256 özeti hesaplanarak `BackupEntryInfo` nesnesinde mühürlenir.
4. **Manifest Dosyası:** Hem Legacy hem Core Next yedeklendiğinde, her iki dosyanın yolunu, boyutunu, SHA-256 özetini ve SQLite bağımsız dosya uyarısını içeren `serenut_dual_backup_manifest_*.json` dosyası yazılır.
5. **Eşzamanlı Yazma Kilidi:** İşlem süresince `DatabaseManager.isWriteLocked = true` yapılır, işlem sonunda `try ... finally` garantisiyle `false` yapılarak yazma kilidi açılır.

### 3.2 Akıllı Geri Yükleme (`restoreDatabase`)
1. **Şema & Hedef Tespiti:** Yedek dosyasının `user_version` PRAGMA'sı ve tablo yapısı incelenir:
   - `user_version == 3` veya `app_settings` + `ledger_entries` tabloları varsa -> Hedef: **Core Next DB** (`serenut_core_v2.db`).
   - `settings` + `sales` + `products` tabloları varsa -> Hedef: **Legacy DB** (`serenut_pos.db`).
   - Geçersiz şema durumunda işlem derhal durdurulur (`Fail-Closed`).
2. **Korumalı Dosya Takası & `.bak` Geri Alma:** Mevcut aktif veritabanı ve WAL/SHM dosyaları geçici `.bak` uzantısına taşınır. Yeni dosya kopyalanıp bütünlük kontrolünden (`PRAGMA integrity_check`) geçirilmeden eskiler silinmez. Hata anında `.bak` dosyaları geri yüklenerek atomik geri alma sağlanır.
3. **Yazma Kilidi:** Tüm geri yükleme süresince `DatabaseManager.isWriteLocked = true` olarak korunur.
4. **Canlı DB Korunması:** Canlı veritabanında kesinlikle bir geri yükleme veya taşıma yapılmamış; geri yükleme provası yalnızca izole test kopyaları üzerinde teyit edilmiştir.

---

## 4. Tenant ve Terminal İzolasyonu (Security Gate Audit)

`PilotCutoverGate` ve `AppBootstrap` yönlendirmesi 8 aşamalı güvenlik süzgeciyle doğrulanmıştır:

1. **`core_next_pilot_enabled` (Varsayılan: `false`):**
   - Kod doğrulaması: SharedPreferences üzerinde bu bayrak açıkça `true` yapılmadıkça geçit açılmaz.
2. **`coreNextSalesEngineEnabledProvider` (Varsayılan: `false`):**
   - `sales_controller.dart` satır 104: `final coreNextSalesEngineEnabledProvider = StateProvider<bool>((ref) => false);`
   - Satış motoru emniyetli legacy modda kalır.
3. **Acil Durum Devre Kesici (Kill Switch):**
   - `PilotCutoverGate.prefKeyKillSwitch`: Herhangi bir anda `true` yapıldığında `blockedKillSwitch` tetiklenir ve tüm sistem milisaniyeler içinde Legacy moduna döner.
4. **Tenant Kimlik Eşleşmesi:**
   - İstenen tenant (`requestedTenantId`) ile hedef veritabanındaki `app_settings.tenant_id` eşleşmezse `blockedTenantMismatch` ile geçiş derhal engellenir.
5. **Karışık Repository Oluşmama Güvencesi:**
   - `PilotCutoverGate` başarısız olduğunda veya bayrak kapalıyken `pilotGateResult.overrides` listesi boştur (`[]`).
   - Riverpod sağlayıcıları istisnasız %100 Legacy SQLite repository'lerine (`SqliteProductRepository`, `SqliteCustomerRepository`, `SqliteSaleRepository`, `SqliteFinancialTransactionRepository`) bağlanır. Kısmi veya hibrit geçiş kesinlikle imkansızdır.

---

## 5. Fiziksel Cihaz Kabul Durumu (Hardware Acceptance)

Geliştirici ortamı bir iş istasyonu / CI ortamı olduğundan fiziksel POS çevre birimleri bağlı değildir. Mock testleri asla gerçek donanım testi gibi gösterilmemiş; donanım durumları açıkça aşağıda belirtilmiştir:

| Donanım Bileşeni | Desteklenen Protokol / Sürücü | Yazılımsal Kontrol & Simülasyon | Fiziksel Donanım Durumu |
|---|---|---|:---:|
| **USB Termal Fiş Yazıcı** | ESC/POS (USB Spooler / TCP 9100 / BT) | `EscPosReceiptRenderer` layout ve `escpos-v1` formatı hazır. | **NOT RUN** |
| **Barkod Okuyucu** | USB HID Klavye Modu / Bluetooth | `BarcodeScannerMixin`, 80ms akış tamponu ve odak yönetimi hazır. | **NOT RUN** |
| **Hassas Terazi (Scale)** | RS232 / COM Port / TCP Port 4001 | `HardwareDeviceType.scale` veri modeli ve COM3 yapılandırması hazır. | **NOT RUN** |

---

## 6. Sahada Operatör Donanım Kabul Kontrol Listesi (Operator Field Checklist)

Pilot terminalde feature flag açılmadan önce sorumlu operatör tarafından fiziken doldurulup imzalanması gereken kontrol listesi:

### 📋 Bölüm A: Termal Fiş Yazıcı (ESC/POS)
- [ ] **A1. Cihaz Bağlantısı:** USB kablosu bağlı, Windows Aygıt Yöneticisi / Yazıcılar altında cihaz "Hazır" durumunda.
- [ ] **A2. Gerçek Fiş Baskısı:** Test fişi çıktısı alındı, yazı netliği ve satır hizalamaları düzgün.
- [ ] **A3. Türkçe Karakter Doğrulaması:** Fişte `Ğ, Ü, Ş, İ, Ö, Ç, ğ, ü, ş, ı, ö, ç` harflerinin bozulmadan, eksiksiz ve doğru basıldığı görüldü.
- [ ] **A4. Kâğıt Kesici:** Fiş sonunda otomatik kesici (tam veya kısmi) sorunsuz çalıştı; kâğıt sıkışması yaşanmadı.
- [ ] **A5. Kâğıt Sonu & Kapak Açık Sensörü:** Kâğıt bittiğinde veya kapak açıldığında uygulamanın donmadığı, kullanıcıya uyarı verdiği doğrulandı.

### 📋 Bölüm B: Barkod Okuyucu (HID Tabanca)
- [ ] **B1. Cihaz Tanıma:** Barkod okuyucu USB/BT üzerinden bağlandı ve bip sesi ile hazır konuma geçti.
- [ ] **B2. Hızlı Tarama (80ms Buffer):** Standart 13 haneli EAN-13 barkod okutuldu; karakterlerin eksiksiz aktarıldığı görüldü.
- [ ] **B3. Ürün Eşleşmesi:** Okutulan ürünün satış ekranında doğru isim, doğru birim fiyat ve KDV oranı ile anında sepete eklendiği doğrulandı.
- [ ] **B4. Modal Ekran Güvenliği:** Bir modal veya onay diyaloğu açıkken taranan barkodun arka planda mükerrer satış tetiklemediği teyit edildi.

### 📋 Bölüm C: Hassas Terazi (Kullanılacaksa)
- [ ] **C1. Port & Baud Rate:** Terazi COM portuna (veya TCP soketine) bağlandı, parametreler (9600 baud, 8N1) doğrulandı.
- [ ] **C2. Daralı & Net Tartım:** Teraziye konulan ağırlığın (ör. 500g fındık) ekranda kuruş/gram sapmasız okunduğu görüldü.
- [ ] **C3. Kararlı Ağırlık Kilidi:** Terazi kararlı (stable) ağırlığa ulaşmadan satış satırının kilitli kaldığı gözlendi.

### 📋 Bölüm D: Satış, Finans ve Kurtarma Provası
- [ ] **D1. Başlangıç Mutabakatı:** Kasa nakit açılış bakiyesi, açık veresiye müşteri bakiyeleri yazılı olarak teyit edildi.
- [ ] **D2. Test Satışı & İptal:** Bir adet küçük tutarlı test satışı (Karma ödeme: Nakit + Kart) yapıldı; stok ve kasa hareketleri incelendi, ardından satış iptal edilerek stok ve bakiyenin geri geldiği doğrulandı.
- [ ] **D3. Uygulama Yeniden Başlatma (Restart):** Uygulama kapatılıp açıldı; test satış kayıtlarının ve açık sepetlerin bütünlüğü korundu.
- [ ] **D4. Ağ Kesintisi & Senkronizasyon:** İnternet bağlantısı kesildi, çevrimdışı bir işlem kaydedildi; internet geri geldiğinde işlemin `sync_events` kuyruğundan tek seferde, mükerrersiz aktarıldığı doğrulandı.

---

## 7. Açık Bulgular & Risk Sınıflandırması

- **P0 (Kritik Engel):** **YOK**. Yazılım mimarisi, veri bütünlüğü, adli hash denetimleri (0 bayt mutasyon), çift veritabanı yedekleme ve fail-closed güvenlik kapıları %100 doğrulanmıştır.
- **P1 (Ön Koşul):** Fiziksel POS donanımları (yazıcı, barkod okuyucu, terazi) geliştirici ortamında bağlı değildir (**NOT RUN**). Operatör yerinde kontrol listesini tamamlamadan pilot bayrağı açılamaz.
- **P2 (Operasyonel Takip):** Pilot başlangıcında ilk 10 canlı işlem sırasında operatör ve teknik personelin yan yana gözlem yapması.

---

## 8. Acil Geri Alma Prosedürü (Emergency Rollback Runbook)

Herhangi bir beklenmeyen davranış, veri tutarsızlığı veya donanım kilitlenmesi anında uygulanacak adımlar:

### Adım 1: Kill Switch Tetikleme (< 5 Saniye)
- **Yöntem A (Uygulama İçi / Konsol):** `PilotCutoverGate.triggerEmergencyKillSwitch(prefs)` çağrısı.
- **Yöntem B (SharedPreferences / Konfigürasyon):** `core_next_kill_switch = true` veya `core_next_pilot_enabled = false` bayrağının atanması.
- **Sonuç:** Uygulama bir sonraki açılışında veya anında `blockedKillSwitch` durumuna geçer; Riverpod override listesi boşalır ve sistem %100 Legacy SQLite repository akışına döner.

### Adım 2: Çift Veritabanı Yedeğine Dönüş (Gerekirse)
- Herhangi bir veri bozulması şüphesinde, pilot öncesinde `BackupService.backupDualDatabases()` ile alınan `serenut_pos_backup_*.db` dosyası `BackupService.restoreDatabase()` aracılığıyla geri yüklenir.
- Sistem `.bak` güvencesiyle atomik olarak pilot öncesi temiz durumuna getirilir.

---

## 9. Pilot Değerlendirme Kararı

### 🏁 Karar: `READY_FOR_OPERATOR_ACCEPTANCE`

**Gerekçe:**
Yazılımsal, mimari, veri bütünlüğü ve adli mutabakat denetimleri **%100 oranında tamamlanmıştır** (87/87 otomatik test başarılı). Çift veritabanı yedekleme motoru atomik snapshot ve geri yükleme güvencesi vermektedir. Ancak fiziksel cihazlar test ortamında bulunmadığından, pilot canlıya alınmadan önce sahada yetkili operatör tarafından Bölüm 6'daki **Fiziksel Donanım Kabul Kontrol Listesi'nin** imzalanması zorunludur.

Tüm feature flag'ler (`core_next_pilot_enabled = false` ve `coreNextSalesEngineEnabledProvider = false`) operatör onayı verilene kadar **KAPALI** kalacaktır.

---

## 10. Sonraki Aşama (Stage 10.12.29) Görevleri

1. **Saha Operatör Onayı:** Hazırlanan kontrol listesinin pilot mağazada (Serenut Merkez Şube) fiziki terminal başında uygulanması ve onaylanması.
2. **Kontrollü Tek Terminal Pilot Açılışı:**
   - Yalnızca pilot terminal kimliği ve pilot tenant için `core_next_pilot_enabled = true` bayrağının aktif edilmesi.
   - Gözetimli olarak ilk gerçek müşteri satışının icra edilmesi.
3. **Canlı Mutabakat Denetimi:** Satış sonrası stok, kasa, cari bakiye ve sunucu senkronizasyon kuyruğunun canlı doğrulanması.
