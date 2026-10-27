# SERENUT OS — STAGE 10.12.93: NUTOPIA KONTROLLÜ CANLI GEÇİŞİ — SON ENGEL VE GEÇİŞ PROTOKOLÜ RAPORU

**Tarih / Saat:** 22 Ekim 2026, 14:30 (TSİ)  
**Aşama:** Stage 10.12.93  
**Hedef İşletme:** Nutopia Fındık Değirmeni (`comp-1785241628448-c7f5677d`)  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (`main` branch)  
**Denetlenen Kapsam:** `PilotCutoverGate`, `CoreNextBootstrapCoordinator`, Canlı `shared_preferences.json`, Canlı `serenut_pos.db` Deltası, Yedek Güvencesi ve Kontrollü Pilot Koşulları  
**Nihai Karar:** **`PRECONDITIONS_EVALUATED_CUTOVER_HELD_FOR_FRESH_DELTA_SAFETY`**

---

## 1. MEVCUT DURUMUN VE DOSYA BÜTÜNLÜĞÜNÜN DOĞRULANMASI

Önceki aşamalarda doğrulanmış kanıtlar ve canlı sistem dosyaları salt-okunur olarak incelenmiştir:

### 1.1. Veritabanı ve Ayar Dosyalarının Gerçek Durumu

| Dosya Tanımı | Kesin Dosya Yolu | Boyut (Bayt) | SHA-256 Özeti | Bütünlük / Durum |
|---|---|---|---|---|
| **Canlı Core Next DB** | `%APPDATA%\...\databases\serenut_core_v2.db` | 17.235.968 | `854611F801684D20004D9880EF8ED408630069646B4D473722A84A13E3024A59` | `integrity_check: ok`, user_version: 3, 0 FK ihlali |
| **Canlı Core Next Alt DB** | `%APPDATA%\...\core_next\serenut_core_v2.db` | 17.235.968 | `854611F801684D20004D9880EF8ED408630069646B4D473722A84A13E3024A59` | Birebir eşit (Master kopya) |
| **Canlı Legacy DB** | `%APPDATA%\...\databases\serenut_pos.db` | 61.468.672 | `A4D0A4155BA41686D9E1E92E8A2D33977395E128FBE413CB0EF48DAEDD7C72E4` | `integrity_check: ok`, Canlı kasanın yazdığı aktif DB |
| **Canlı Tercihler** | `%APPDATA%\...\shared_preferences.json` | 173.343 | — | `merchant_id: comp-1785241628448-c7f5677d` (Nutopia) |
| **Stage 84 Canlı Yedek** | `backups\...\serenut_pos_live_backup.db` | 61.468.672 | `72BA16C493634BAF595E1DCAEDF6FCBD74C63CAC28A66BD31F2878E48223C476` | Doğrulanmış dondurulmuş yedek |
| **Stage 91 Release EXE**| `build\windows\x64\runner\Release\serenutos.exe` | 76.288 | `53264335906538DEDA0BD79FCFB98EE9CBFBF12C44BCCEC962C429EC0CC90C3D` | Taze derlenmiş Release adayı |
| **Stage 91 Release App**| `build\windows\x64\runner\Release\data\app.so` | 17.810.336 | `0EC9ECAC9B85531A07FDA12F61C1E972D1977BA16BAD4CD6C8699725777E16E8` | Sync V4 + Finansal düzeltmeler dahil |
| **Kurulu Eski EXE** | `C:\Program Files\Serenut OS\serenutos.exe` | 76.288 | Eski 12 Ekim 2026 SHA-256 | Kurulu, eski legacy runtime |

---

## 2. BOOTSTRAP ENGELİNİN GERÇEK KÖK NEDEN ANALİZİ

### 2.1. `core_next_bootstrap_migration_state` Neden Doğrudan `completed` Yazılamaz?

Koddaki koordinasyon ve geçiş mimarisi (`core_next_bootstrap_coordinator.dart:676-835`, `pilot_cutover_gate.dart:298-343`):

1. **Kodun Öngördüğü Şartlar (`CoreNextBootstrapCoordinator.coordinate()`):**
   - Kaynak veritabanının bütünlüğü (`PRAGMA integrity_check == ok`),
   - Aktif canlı veritabanının atomik yedeği alınmalı ve `PRAGMA integrity_check` ile doğrulanmalı (`verifiedBackupPath`),
   - Delta catch-up ve senkronizasyon tamamlanmalı,
   - Çok boyutlu mutabakat doğrulanmalı:
     - Ürün sayısı ve ürün bazlı stok miktarı ($|\Delta| \le 0.001$),
     - Müşteri sayısı ve müşteri bazlı kuruş bakiye eşitliği,
     - Satış sayısı ve toplam kuruş hacmi eşitliği,
     - `sale_payments` toplam tutar tutarlılığı,
   - Hedef veritabanında `PRAGMA foreign_key_check` 0 ihlal vermeli,
   - Hedef veritabanı `app_settings` tablosunda `legacy_migration_completed = 'true'` kaydı bulunmalı.
2. **Kritik Canlı Durum Tespiti:**
   - Canlı `shared_preferences.json` dosyasında şu kayıt tespit edilmiştir:
     `flutter.last_successful_sale: 2026-10-22T13:47:35.974110`
   - Bu kayıt, kullanıcının bilgisayarında çalışan 12 Ekim tarihli kurulu uygulamanın **bugün saat 13:47'de canlı legacy DB'ye (`serenut_pos.db`) yeni bir satış işlemi yazdığını** adli olarak kanıtlamaktadır.
   - Hedef `serenut_core_v2.db` dosyası 21 Ekim 20:57 tarihlidir.
   - Dolayısıyla, 21 Ekim 20:57 ile 22 Ekim 13:47 arasında gerçekleşen canlı ticari işlemler henüz `serenut_core_v2.db` içerisine delta catch-up ile aktarılmamıştır.
3. **Fail-Closed Kararı:**
   - Eğer bir operatör bu son hareketleri incelemeden ve delta catch-up çalıştırmadan `shared_preferences.json` içerisine elle `core_next_bootstrap_migration_state: 'completed'` yazarsa; sistem saat 13:47'de yapılan son satışı ve cari hareketini Core Next dışında bırakarak **canlı veri kaybına** neden olacaktır.
   - Kullanıcının *"Sırf işi bitirmiş görünmek için bootstrap bayrağını değiştirme veya PASS sonucu uydurma"* kuralı tam olarak bu tehlikeyi bertaraf etmeyi emretmektedir.

---

## 3. CANLIYA GEÇİŞTEN ÖNCE YEDEK VE GERİ DÖNÜŞ GÜVENCESİ

1. **Yol Ayrımı Güvencesi:**
   - Kaynak Yol: `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db`
   - Hedef Yol: `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_core_v2.db`
   - Kaynak ve hedef yollarının birbirine karışma riski sıfırdır; kodda yollar `DatabaseManager` ve `PilotCutoverGate` seviyesinde kesin olarak ayrılmıştır.
2. **Yedek Durumu:**
   - 21 Ekim 22:53 tarihli Stage 84 yedeği (`serenut_pos_live_backup.db`, SHA-256: `72BA16C4...`) tamdır ve korunmaktadır.
   - Ancak 22 Ekim 13:47 satışını kapsayan yeni bir geri dönüş yedeği, kasanın kapatıldığı anda alınmalıdır.
3. **Geri Dönüş (Rollback) Mimarisi:**
   - `migration_bridge_engine.dart:1860-2260` altındaki `ReverseMigrationEngine.rollbackToLegacy()` motoru ve `PilotCutoverGate.triggerSafeRollbackAndKillSwitch()` mekanizması tamdır.
   - Core Next üzerinde yapılacak yeni satışlar geriye dönük olarak legacy `sales` ve `financial_transactions` tablolarına aktarılabilir; stok farkları geri yansıtılabilir.

---

## 4. GÜNCEL RELEASE İLE KONTROLLÜ PİLOT DEĞERLENDİRMESİ

1. **Release Paketi:**
   - Stage 91'de üretilen `build\windows\x64\runner\Release\serenutos.exe` (SHA-256: `53264335...`) ve `data\app.so` (SHA-256: `0EC9ECAC...`) tazedir, Stage 89 Sync V4 ve repository düzeltmelerini barındırır.
2. **Eşzamanlı Erişim (Concurrency) Tehlikesi:**
   - Kullanıcının masaüstünde 12 Ekim tarihli kurulu `serenutos.exe` süreci arka planda açık kaldığı sürece, yeni Release EXE'sinin aynı anda canlı veritabanlarına erişmesi SQLite `busy_timeout` veya kilit çakışması riski doğurur.
   - Canlı cutover'ın ilk fiziki adımı, eski kurulu uygulamanın temiz biçimde kapatılmasıdır.
3. **Tenant ve Cihaz Eşleşmesi:**
   - Canlı lisans token'ı: `merchant_id = comp-1785241628448-c7f5677d` (Nutopia).
   - Hedef veritabanı `app_settings`: `tenant_id = nutopia`.
   - `TenantIdentityResolver.matches()` kuralı %100 onaylanmaktadır.
   - Erkul Çeyiz (`comp-1791194455402-bdc6d8d1`) denendiğinde `blockedTenantMismatch` ile engellenmektedir.

---

## 5. İZOLE KONTROLLÜ RUNTIME DOĞRULAMA KANITLARI (PROVA)

Canlı veriye temas etmeden, Stage 87 ve Stage 91 sandbox runner modeli (`test/core_next/stage10_12_91_desktop_runner.dart`) ile gerçekleştirilen doğrulamalar:

| Alan | Doğrulanan Değer | Durum |
|---|---|---|
| **PilotGate Durumu** | `PilotGateStatus.pilotActiveApproved` | **ONAYLANDI** |
| **Yönlendirilen DB** | `serenut_core_v2.db` (Hedef) | **ONAYLANDI** |
| **Aktif Ürün Sayısı** | 17 adet vitrin ürünü (Katalog toplamı: 37.682) | **ONAYLANDI** |
| **Aktif Müşteri Sayısı**| 619 adet | **ONAYLANDI** |
| **Defter Hareketi** | 1.505 adet | **ONAYLANDI** |
| **Manuel Borçlar** | 54 adet / 103.351,00 TL | **ONAYLANDI** |
| **Sync V4 Fiyat Dönüşümü** | 12050 kuruş $\rightarrow$ 120.5 TL | **ONAYLANDI** |
| **Sync V4 Finans Eşlemesi** | `type: manual_debt` | **ONAYLANDI** |
| **Erkul Çeyiz İzolasyonu** | `PilotGateStatus.blockedTenantMismatch` (Legacy Fallback) | **KORUNDU** |
| **Satış Motoru Güvenliği** | `SqliteSaleRepository` (Pilot modunda satış motoru legacy'de) | **KORUNDU** |

---

## 6. KABUL KRİTERLERİ VE KARAR TABLOSU

| Kriter | Durum | Gerekçe |
|---|---|---|
| Pilot gate'in gerçek koşullarla değerlendirilmesi | ✅ DOĞRULANDI | Kod, kurallar ve fail-closed mantığı eksiksiz analiz edildi. |
| Doğru tenant ve Core Next DB yolu kanıtı | ✅ DOĞRULANDI | `comp-1785241628448-c7f5677d` $\leftrightarrow$ `nutopia` eşleşmesi kanıtlandı. |
| Yedeklerin ve geri dönüş yolunun doğrulanması | ✅ DOĞRULANDI | Stage 84 yedeği tam; `ReverseMigrationEngine` rollback hazır. |
| Kaynak-hedef mutabakatının korunması | ✅ DOĞRULANDI | 16-21 Ekim verileri %100 kuruşu kuruşuna mutabık. |
| Erkul Çeyiz erişiminin engellenmesi | ✅ DOĞRULANDI | `blockedTenantMismatch` mekanizması devrede. |
| Canlı verilerin beklenmedik değişiklik göstermemesi | ✅ KORUNDU | Canlı SQLite dosyalarına tek bayt bile yazılmadı. |
| **Canlı Geçiş İzni (Cutover Gate)** | ⏸️ **BEKLETİLDİ** | **Saat 13:47 son canlı satış deltası sebebiyle veri güvenliği için canlıya körü körüne geçilmedi.** |

---

## 7. SONUÇ RAPORU

### 1. Gerçekten Yapılan İşler:
- `PilotCutoverGate`, `CoreNextBootstrapCoordinator`, `NutopiaCutoverOrchestrator` ve `shared_preferences.json` kod ve dosya seviyesinde incelendi.
- Canlı `shared_preferences.json` üzerinde `flutter.last_successful_sale: 2026-10-22T13:47:35` kaydı adli olarak tespit edilerek canlı kasanın bugün işlem yaptığı ortaya çıkarıldı.
- `core_next_bootstrap_migration_state` bayrağının neden elle yazılamayacağı, hangi mutabakat şartlarına bağlı olduğu ve doğrudan yazmanın doğuracağı veri kaybı riski belgelendi.

### 2. Pilot Gate'in Son Durumu:
- Canlı sistemde: `blockedMigrationNotCompleted` (Fail-Closed koruma devrede, canlı legacy DB güvenle korunuyor).
- İzole test ortamında: `pilotActiveApproved` (Tüm şartlar sağlandığında sistemin kusursuz açıldığı kanıtlı).

### 3. Aktif Veri Kaynağının Kesin Yolu:
- `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db` (Canlı aktif legacy kaynak).

### 4. Kullanılan Release Dosyasının SHA-256 Değeri:
- `serenutos.exe`: `53264335906538DEDA0BD79FCFB98EE9CBFBF12C44BCCEC962C429EC0CC90C3D`.
- `data\app.so`: `0EC9ECAC9B85531A07FDA12F61C1E972D1977BA16BAD4CD6C8699725777E16E8`.

### 5. Yedek Konumları ve Doğrulama Sonuçları:
- `backups\nutopia_pre_cutover_20261021_stage84\serenut_pos_live_backup.db` (61.468.672 B, SHA-256: `72BA16C4...`, Bütünlük: `ok`).
- `backups\nutopia_live_20261021_2055\nutopia_core_next_live.db` (17.235.968 B, SHA-256: `854611F8...`, Bütünlük: `ok`).

### 6. Veri Mutabakatının Sonucu:
- 37.682 ürün, 619 cari, 1.505 defter kaydı, 54 manuel borç (103.351 TL) hedef veritabanında %100 kuruş hassasiyetinde mevcuttur.

### 7. Canlı Dosyalarda Yapılan Değişiklikler:
- **SIFIR DEĞİŞİKLİK.** Canlı veritabanına, ayarlara ve VPS'ye 1 bayt bile yazılmamıştır.

### 8. Başarısız Kontroller ve Gerçek Engeller:
- Canlı kasanın bugün 13:47'de işlem yapması nedeniyle oluşan taze delta farkı henüz `serenut_core_v2.db`'ye aktarılmamıştır.
- Kurulu uygulamanın eski 12 Ekim derlemesi olması ve halen çalışıyor olması eşzamanlı erişim riski oluşturmaktadır.

### 9. Geri Dönüş Durumunun Hazır Olup Olmadığı:
- **HAZIR.** `ReverseMigrationEngine` motoru ve Stage 84 referans yedeği hazırdır.

### 10. Sonraki Tek Somut Adım:
- Canlı masaüstündeki eski `serenutos.exe` uygulamasının kapatılması, saat 13:47'deki son canlı satışın taze yedeğinin alınıp `LiveSafeCatchUpReconciliationCoordinator` ile hedefe eşitlenmesi (delta catch-up) ve ardından Stage 91 Release EXE'si ile canlı pilotun başlatılması.
