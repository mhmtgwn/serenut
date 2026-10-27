# SERENUT OS — STAGE 10.12.17
## MIGRATION PROGRESS UX & EXPLICIT CONSENT GATE REPORT

**Tarih:** 17 Ekim 2026  
**Aşama:** Stage 10.12.17  
**Amaç:** `BrandedSplashScreen` üzerinde reaktif ve gerçek verilere dayalı ilerleme arayüzünün kurulması ile veri aktarımı öncesinde işletme sahibine şeffaf bilgi verip açık onay alan `MigrationConsentDialog` bileşeninin entegrasyonu.  
**Nihai Karar:** `UX READY FOR REVIEW` (Kullanıcı arayüzü ve onay mekanizması incelemeye hazırdır; canlıya geçiş izni değildir).

---

## 1. BAŞLANGIÇ GİT DURUMU VE DEĞİŞMEZLİK

- **HEAD Hash:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Mevcut Dal (Branch):** `main`
- **`git diff --check`:** Çıkış kodu `0` (Hatasız)
- **Kullanıcı Değişiklikleri:** Korundu; reset, commit veya silme işlemi yapılmadı.

### Kaynak Veritabanları SHA-256 Değişmezlik Doğrulaması

| Dosya Yolu | SHA-256 Sağlama Özeti | Durum |
| :--- | :--- | :---: |
| `backups/raw_tenants_20261016/raw_nutopia_v60.db` | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | **IMMUTABLE (KORUNDU)** |
| `backups/raw_tenants_20261016/raw_serenut_v44.db` | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | **IMMUTABLE (KORUNDU)** |
| `backups/raw_tenants_20261016/raw_erkul_source.json` | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | **IMMUTABLE (KORUNDU)** |

---

## 2. REAKTİF İLERLEME GÖSTERGESİ (PROGRESS UX) MİMARİSİ

Mevcut marka kimliği (`BrandedSplashScreen`) ve renk paleti korunarak, yapay zamanlayıcılar yerine veritabanı motorunun gerçek aşamalarından türetilen reaktif durum modeli entegre edilmiştir.

### 6 Gerçek İlerleme Aşaması ve Yüzde Dağılımı

| Aşama No | Durum Metni (`stageTitle`) | Aşama Kodu (`MigrationStage`) | Gerçek Yüzde | Detay Açıklaması |
| :---: | :--- | :--- | :---: | :--- |
| **1** | `Kaynak veritabanı doğrulanıyor` | `sourceVerifying` | `%20` | Kaynak SQLite dosyasının `PRAGMA integrity_check` ve DDL doğrulaması. |
| **2** | `Yedek hazırlanıyor` | `backupPreparing` | `%35` | `PRAGMA wal_checkpoint(TRUNCATE)` ve doğrulanmış fiziksel yedek kopya. |
| **3** | `Veriler aktarılıyor` | `dataMigrating` | `%40` – `%75` | 37.682 ürün, cari hesaplar, satışlar, siparişler ve anonim kasa hareketleri. |
| **4** | `Finans ve stok mutabakatı yapılıyor` | `reconciliation` | `%85` | Kaynak ve hedef bakiyeler, stok toplamları ve kuruş duyarlılığında mutabakat. |
| **5** | `Son bütünlük kontrolleri yapılıyor` | `integrityChecking` | `%95` | Hedef DB `PRAGMA integrity_check`, `foreign_key_check` ve indeks kontrolleri. |
| **6** | `İşlem tamamlandı` / `Hata oluştu` | `completed` / `failed` | `%100` / `%0` | Başarı durumunda kalıcı state onayı; hata durumunda hata referans kodu ve fail-closed. |

### UI İş Parçacığı (Event-Loop) Yanıt Verebilirlik Güvencesi:
- 37.682 ürünlük toplu aktarım sırasında `MigrationBridgeEngine`, her 1.000 kayıtta bir transaction batch commit işlemi gerçekleştirir ve `await Future<void>.delayed(Duration.zero)` ile Dart event loop'unu serbest bırakır.
- Bu sayede 10-15 saniyelik büyük veri göçü esnasında Flutter UI çizim motoru 60 FPS akıcılığını korur; arayüz donmaz veya kilitlenmez.

---

## 3. AÇIK KULLANICI ONAYI DİYALOĞU (`MigrationConsentDialog`)

Veri aktarımından önce işletme sahibine tam şeffaflık sağlayan `MigrationConsentDialog` bileşeni (`lib/presentation/widgets/migration_consent_dialog.dart`) oluşturulmuştur.

### Diyalog İçerik ve Güvenlik Parametreleri:
1. **Neden Yapılıyor?:** İşletmenin satış, stok ve cari işlemlerinin daha yüksek performansla, kuruş duyarlılığında ve sıfır veri kaybı güvencesiyle çalışabilmesi için Core Next motoruna geçiş.
2. **Aktarılacak Veriler:**
   - Katalog ve Stoklar (37.682 ürün ve stok kayıtları)
   - Cari Hesaplar ve Bakiyeler (584 müşteri hesabı, defter hareketleri ve taksitler)
   - Satışlar, Siparişler ve Kasa (Geçmiş satışlar ve 21 müşterisiz nakit kasa işlemi)
3. **Önemli Bilgilendirme ve Kesinti Uyarısı:**
   - ⏳ İşlem süresince (~10-15 saniye) uygulamanın kullanılamayabileceği.
   - 🔒 İşlem öncesinde doğrulanmış tam SQLite yedeği alınacağı.
   - ⚠️ Yeni satış yapıldıktan sonra eski sürüme geri dönüşün, yeni kayıtların korunması için güvenlik kilitlerine tabi olduğu (`assertSafeRollback`).
4. **Butonlar ve Davranış Modeli:**
   - **`Şimdi Değil`:** Kullanıcı geçişi erteler; migration başlatılmaz, yedek alınmaz, veritabanı kilitlenmez ve mevcut legacy veritabanıyla çalışmaya devam edilir.
   - **`Koşulları İncele`:** Tıklandığında teknik parametreleri (kaynak/hedef yolları, PRAGMA modu, mutabakat kuralı, rollback güvencesi) gösteren inceleme panelini açar/kapatır.
   - **`Geçişi Onayla`:** Kullanıcı açık onay verir; kontrollü geçiş akışı başlatılır.

---

## 4. 11 TEST SENARYOSU VE DOĞRULAMA KANITLARI

| Senaryo No | Test Edilen Senaryo | Beklenen Sonuç | Test Kanıtı | Durum |
| :---: | :--- | :--- | :--- | :---: |
| **1** | Migration kapalıyken normal açılış | Runner ve consent null iken açılış değişmez, progress null kalır | `test/core_next/stage10_12_17_progress_consent_test.dart` (Test 1) | **PASS** |
| **2** | Kullanıcı geçişi reddeder (`Şimdi Değil`) | Migration başlamaz, runner çağrılmaz, legacy devam eder | `stage10_12_17_progress_consent_test.dart` (Test 2) | **PASS** |
| **3** | Kullanıcı onay verir (`Geçişi Onayla`) | Yalnızca izin verilen migration akışı başlar ve tamamlanır | `stage10_12_17_progress_consent_test.dart` (Test 3) | **PASS** |
| **4** | Yedek doğrulaması başarısız olursa | Migration durdurulur, kilit kaldırılır, state `failedRecoverable` kalır | `stage10_12_17_progress_consent_test.dart` (Test 4) | **PASS** |
| **5** | Tenant kimliği uyuşmazsa | Fail-closed devreye girer, hedef DB seçimi engellenir | `stage10_12_17_progress_consent_test.dart` (Test 5) | **PASS** |
| **6** | İlerleme bilgisi güncellemesi | 6 aşama ve monoton artan yüzdeler (`%20` -> `%100`) eksiksiz yayınlanır | `stage10_12_17_progress_consent_test.dart` (Test 6) | **PASS** |
| **7** | Migration hata durumu | Hata referans kodu üretilir, `stage: failed` ve durum metni gösterilir | `stage10_12_17_progress_consent_test.dart` (Test 7) | **PASS** |
| **8** | Yarım kalmış migration sonrası açılış | Tamamlanmamış hedef seçilmez, legacy fallback yapılır | `stage10_12_17_progress_consent_test.dart` (Test 8) | **PASS** |
| **9** | Tamamlanma işareti yoksa hedef seçimi | Tamamlanma bayrağı olmadan hedef veritabanı seçilmez | `stage10_12_17_progress_consent_test.dart` (Test 9) | **PASS** |
| **10** | Yeni veri bulunan hedefte rollback | Yeni satış varsa `UnsafeRollbackException` ile geri dönüş engellenir | `stage10_12_17_progress_consent_test.dart` (Test 10) | **PASS** |
| **11** | UI yanıt verebilirlik (Event loop) | Uzun süren batch aktarımında frame/timer akışı kesilmez | `stage10_12_17_progress_consent_test.dart` (Test 11) | **PASS** |
| **UI-1** | `MigrationConsentDialog` Widget Testi | Başlık, açıklamalar, koşul inceleme toggle ve butonlar çalışır | `stage10_12_17_progress_consent_test.dart` (UI Test 1) | **PASS** |
| **UI-2** | `BrandedSplashScreen` Reaktif Çizim | Durum, detay ve `%65` linear progress bar kusursuz render edilir | `stage10_12_17_progress_consent_test.dart` (UI Test 2) | **PASS** |

---

## 5. REGRESYON TEST SONUÇLARI

Tüm test paketleri izole ortamlarda çalıştırılmış ve tamamı hatasız geçmiştir:

| Test Dosyası | Kapsam | Test Sayısı | Çıkış Kodu | Sonuç |
| :--- | :--- | :---: | :---: | :---: |
| `test/core_next/stage10_12_17_progress_consent_test.dart` | UX, Dialog ve 11 Senaryo | 13 | 0 | **PASS** |
| `test/core_next/stage10_12_16_audit_and_benchmark_test.dart` | 8-Aşama Benchmark & Mutabakat | 5 | 0 | **PASS** |
| `test/core_next/stage10_12_15_guarded_database_manager_test.dart` | DatabaseManager 8-Condition Gate | 8 | 0 | **PASS** |
| `test/core_next/stage10_12_14_isolated_bootstrap_rehearsal_test.dart` | Açılış Provası & Rollback | 15 | 0 | **PASS** |
| `test/core_next/stage10_12_12_anonymous_cash_sales_test.dart` | 21 Anonim Nakit Satış Göçü | 6 | 0 | **PASS** |
| **GENEL TOPLAM** | **Tam Regresyon Doğrulaması** | **47** | **0** | **TÜMÜ BAŞARILI** |

---

## 6. ÜRETİM GÜVENLİK SINIRLARI KONTROLÜ

Gerçek üretim kodunda varsayılan kilitler ve korumalar doğrulanmıştır:

- **`coreNextSalesEngineEnabledProvider`:** `false` ([sales_controller.dart:L104](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L104))
- **`coreNextMigrationRunnerProvider`:** `null` ([core_next_bootstrap_coordinator.dart:L853](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart#L853))
- **`databaseRoutingHook`:** `null` ([database_provider.dart:L47](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L47))
- **`coreNextConsentRequesterProvider`:** `null` ([core_next_bootstrap_coordinator.dart:L862](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart#L862))
- **Canlı DB / Bulut Postgres:** Canlı Nutopia SQLite veya Erkul bulut PostgreSQL veritabanına hiçbir veri yazılmamış ve canlı migration çalıştırılmamıştır.

---

## 7. NİHAİ KARAR

# `UX READY FOR REVIEW`

**Açıklama:**  
Stage 10.12.16 denetiminde tespit edilen iki eksiklik eksiksiz tamamlanmıştır:  
1. `BrandedSplashScreen`, migration'ın 6 gerçek aşamasını ve gerçek aktarım yüzdelerini UI kilitlenmesi olmadan reaktif olarak gösterebilmektedir.  
2. `MigrationConsentDialog`, kullanıcıya geçişin nedenini, kapsamını, kesinti süresini ve rollback risklerini şeffaf biçimde sunmakta; `Şimdi Değil` seçeneğiyle migration'ı başlatmadan legacy akışı korumaktadır.  

Sistem, kontrollü bir pilot aşamasına geçilmeden önce görsel ve işlevsel olarak incelemeye hazırdır. Bu karar canlıya geçiş veya bayrak açma izni teşkil etmez.
