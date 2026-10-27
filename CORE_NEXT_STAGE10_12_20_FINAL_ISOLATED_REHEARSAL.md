# CORE NEXT — STAGE 10.12.20
## SON BAĞIMSIZ DOĞRULAMA VE İZOLE GEÇİŞ PROVASI RAPORU

**Tarih:** 2026-10-17  
**Ortam:** Serenut OS Desktop (Windows 11 x64, Flutter 3.24.5 / Dart 3.5.4)  
**Denetçi / İcra Eden:** Antigravity Bağımsız Kod & Güvenlik Denetim Ajanı  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (`main`)  
**Temel Kaynak Yedeği:** `backups/raw_tenants_20261016/raw_nutopia_v60.db`  
**Kaynak SHA-256:** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` (Değişmezlik Doğrulandı)  
**Nihai Karar:** `ISOLATED REHEARSAL PASSED — PILOT REVIEW REQUIRED`

---

## 1. YÜRÜTME ÖZETİ VE DOĞRULAMA ÇERÇEVESİ

Stage 10.12.19 raporunda beyan edilen güvenlik ve UI entegrasyonu iddiaları körlemesine doğru kabul edilmeyerek, gerçek kod ve test icraları üzerinden bağımsız olarak denetlenmiştir. Denetim ve prova süreci 5 ana eksende yürütülmüştür:
1. **Gerçek UI Açılışı ve Onay Yaşam Döngüsü**: Splash ve Navigator/Overlay akışının `effectiveConsentRequester` ile güvenli bağlantısı.
2. **Fail-Closed Bağımsız Denetimi**: Runner, Requester, Onay, Yedek, Tenant ve Callback hata matrisinde sıfır toleranslı engelleme (`callCount == 0`).
3. **İzole Veri Geçiş Provası & Adli Mutabakat**: Nutopia v60 ham SQL analizinden türetilen gerçek sayılarla 1:1 tam mutabakat ve idempotency (çift çalıştırma) testi.
4. **Hata ve Güvenli Geri Dönüş (Rollback) Tatbikatı**: Veri tabanı bozulması, yarıda kesilme ve post-migration veri koruma bariyerleri (`assertSafeRollback`).
5. **Regresyon Test Paketi ve Statik Analiz**: Stage 10.12.12'den 10.12.20'ye kadar tüm test paketlerinin icrası, `flutter analyze` ve `git diff --check`.

---

## 2. BÖLÜM A — GERÇEK UI AÇILIŞI VE ONAY MEKANİZMASI

### A.1. Üretim Durumu: Onay Diyaloğunun Açılmaması (PASS)
- `AppBootstrap.runStartupDiagnostics` ve `CoreNextBootstrapCoordinator.shouldAttemptMigration` zinciri denetlendi.
- Üretimde `runner == null` olduğu için `shouldAttemptMigration` doğrudan `false` dönmektedir.
- Uygulama normal başlatıldığında onay diyaloğunun yanlışlıkla açılmadığı izole widget testinde (`main.dart` açılış mantığıyla) doğrulanmıştır:
  - `find.byType(MigrationConsentDialog)` -> **0 eşleşme (Bulunamadı - Beklenen Davranış)**.

### A.2. Kontrollü Dependency Override Onay Akışı (PASS)
- UI test ortamında `effectiveConsentRequester` kontrollü olarak tetiklendiğinde `MigrationConsentDialog` overlay/dialog katmanında render edildi:
  - Başlık: *"Yeni Veritabanı Mimarisine Geçiş"*
  - Açıklama, risk uyarıları ve eylem butonları eksiksiz görüntülendi.

### A.3. Kullanıcı Eylemleri ve Yaşam Döngüsü (PASS)
1. **"Şimdi Değil" Senaryosu**:
   - Kullanıcı diyaloğu reddettiğinde (`onDismissed`), onay isteği güvenle `false` döner.
   - Migration çağrılmadan uygulama eski veritabanı rotasında kalır.
2. **Onay Senaryosu**:
   - Kullanıcı onayladığında (`onConfirmed`), `Future<bool>` `true` olarak çözülür ve onay jetonu koordinatöre iletilir.
3. **Çift Açılış (Double Prompt) Engeli**:
   - `_pendingConsentRequest != null` koruması sayesinde, ilk diyalog açıkken gelen ikinci bir onay isteği anında `false` dönerek kuyruğu kirletmez ve ekranda çift popup açılmasını engeller.
4. **Widget Dispose Senaryosu**:
   - Ekran kapanırken veya dispose edilirken bekleyen onay Future'ı askıda bırakılmaz; `_pendingConsentCompleter?.complete(false)` ile temizlenir ve memory leak engellenir.

### A.4. Onayın Gerçek Migration Çağrısına Ulaşma Zinciri (Kod Referansları)
1. `lib/infrastructure/bootstrap/app_bootstrap.dart`:
   - `AppBootstrap.runStartupDiagnostics(...)` -> line 38: `effectiveConsentRequester` çağrılır.
   - `coreNextCoordinator.shouldAttemptMigration(...)` kontrol edilir.
2. `lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart`:
   - `shouldAttemptMigration(...)`: Runner kontrolü + `isCompleted` kontrolü + tenant ID eşleşmesi.
   - `requestConsent(...)`: `effectiveConsentRequester` çağrılır (`MigrationConsentDecision`).
   - `executeGuardedMigration(...)`: Eğer `consentGranted == true` ve `runner != null` ise `runner.run(...)` tetiklenir.
3. `lib/main.dart`:
   - `_MyAppState.showMigrationConsentDialog`: `navigatorKey.currentContext` üzerinden overlay/dialog açarak koordinatörün istediği onayı kullanıcıya sunar.

---

## 3. BÖLÜM B — FAIL-CLOSED BAĞIMSIZ GÜVENLİK KAPILARI

Tüm hata durumları test harness altında izole edilerek migration motorunun çağrı sayısı (`callCount`) ve hedef veritabanı durumu denetlenmiştir:

| Test Senaryosu | Runner Durumu | Requester Durumu | Beklenen Davranış | Gerçekleşen Motor Çağrısı (`callCount`) | Hedef DB Seçildi mi? | Tamamlanma İşareti? | Durum |
| :--- | :--- | :--- | :--- | :---: | :---: | :---: | :---: |
| **B.1 Runner Null** | `null` | Aktif | Engellendi (Fail-Closed) | **0** | Hayır (Legacy) | Yazılmadı | **PASS** |
| **B.2 Requester Null** | Mock | `null` | Engellendi (Fail-Closed) | **0** | Hayır (Legacy) | Yazılmadı | **PASS** |
| **B.3 Onay Red / Hata** | Mock | Exception / Red | Engellendi (Fail-Closed) | **0** | Hayır (Legacy) | Yazılmadı | **PASS** |
| **B.4 Yedek Başarısız** | Mock | Onaylandı | Yedek alınamadı -> İptal | **0** | Hayır (Legacy) | Yazılmadı | **PASS** |
| **B.5 Tenant Mismatch** | Mock | Onaylandı | Farklı Tenant -> Engellendi | **0** | Hayır (Legacy) | Yazılmadı | **PASS** |
| **B.6 Callback Hatası** | Mock | Onaylandı | Hata izole edildi, sessizce yutulmadı | Motor fail verdi | Hayır (Legacy) | Yazılmadı | **PASS** |

*Sonuç: Tüm fail-closed güvenlik kapıları %100 sızdırmazlıkla doğrulanmıştır.*

---

## 4. BÖLÜM C — İZOLE VERİ GEÇİŞ PROVASI & ADLİ REKONSİLİASYON

Geçiş provasında canlı Nutopia veritabanına ve Erkul PostgreSQL veritabanına kesinlikle dokunulmamış; SHA-256 imzalı `raw_nutopia_v60.db` yedeğinin geçici izole kopyası (`nutopia_rehearsal_source.db`) üzerinde gerçek `MigrationBridgeEngine` çalıştırılmıştır.

Beklenen değerler farazi fixture'lardan değil, kaynak SQLite dosyasında doğrudan çalıştırılan ham SQL aggregate sorgularından elde edilmiştir:

### C.1. Adli Mutabakat Tablosu (Kaynak vs Hedef)

| Varlık / Alan | Kaynak SQLite (raw_nutopia_v60) | Hedef Core Next SQLite | Fark / Hata | Mutabakat Notu |
| :--- | :--- | :--- | :---: | :--- |
| **Toplam Ürün Sayısı** | 37,682 | 37,682 | **0** | Bire bir aktarıldı |
| **Aktif Ürün Sayısı** | 37,682 | 37,682 | **0** | Silinmiş ürün yok |
| **Stok Miktarı Toplamı** | 405,671.30 birim | 405,671,300 milli-units | **0** | 1,000x tamsayı hassasiyetiyle kayıpsız korundu |
| **Kritik Fiyat Alanları** | Kayıpsız (kuruş) | Kayıpsız (cents) | **0** | Bire bir kuruş bazlı denklik |
| **Toplam Müşteri Sayısı** | **584** | **584** | **0** | Tüm müşteri tabanı eksiksiz aktarıldı |
| **Müşteri Bakiye Toplamı**| -134,500.68 TL | -13,450,068 kuruş | **0** | Kuruşu kuruşuna tam mali denklik |
| **Satışlar (Sales)** | 52 | 52 | **0** | 41 sipariş bağlantılı + 11 doğrudan |
| **Satış Kalemleri** | 72 | 72 | **0** | Tüm satır kalemleri eksiksiz |
| **Siparişler (Orders)** | 792 | 792 | **0** | Bire bir aktarıldı |
| **Sipariş Kalemleri** | 1,068 | 1,068 | **0** | Bire bir aktarıldı |
| **Taksit Planları** | 2 | 2 | **0** | Aktif taksit sözleşmeleri korundu |
| **Taksit Dilimleri** | 9 | 9 | **0** | Dilim ve vade tarihleri korundu |
| **Finans Defteri (Ledger)**| 1,403 | 1,403 | **0** | Tarihçe ve outbox eksiksiz kuruldu |
| **Anonim Nakit Satışlar** | 21 | 21 | **0** | Müşterisiz nakit fişleri outbox/ledger'a bağlandı |
| **Yetim Kayıt Sayısı** | 0 | 0 | **0** | İlişkisel bütünlük tam |
| **UUID Çakışması** | 0 | 0 | **0** | Deterministik UUID mapping kusursuz |

### C.2. İkinci Çalıştırma & İdempotency (PASS)
- Aynı izole hedef veritabanı üzerinde `MigrationBridgeEngine.migrateAll()` ikinci kez çalıştırılmıştır.
- **İkinci Çalıştırma Sonucu**:
  - Ürün sayısı: 37,682 (Değişmedi, çift kayıt = 0)
  - Müşteri sayısı: 584 (Değişmedi, çift kayıt = 0)
  - Satış sayısı: 52 (Değişmedi, çift kayıt = 0)
  - Finans defteri: 1,403 (Değişmedi, çift kayıt = 0)
  - **İdempotency Başarısı: %100**

---

## 5. BÖLÜM D — HATA VE GERİ DÖNÜŞ (ROLLBACK) TATBİKATI

İzole geçiş ortamında 7 kritik olağanüstü durum tatbikatı icra edilmiştir:

1. **Yedekleme Başarısızlığı**:
   - Simülasyon: Disk/yazma hatası nedeniyle ön-yedekleme başarısız kılındı.
   - Sonuç: Migration motoru başlamadan işlem durduruldu. Kaynak veri korundu. Hedef seçilmedi. (**PASS**)
2. **Migration Ortasında Hata (Mid-run Crash)**:
   - Simülasyon: Veri aktarımının ortasında beklenmeyen exception fırlatıldı.
   - Sonuç: SQLite transaction rollback yapıldı. `app_settings` içerisine `core_next_migration_completed` bayrağı YAZILMADI. Resolver rotayı eski veritabanında tuttu. (**PASS**)
3. **Uygulamanın Beklenmedik Kapanması (Process Kill)**:
   - Simülasyon: Yarım kalan veritabanı ile uygulama yeniden başlatıldı.
   - Sonuç: Açılış kontrollerinde tamamlanma bayrağı olmadığı için hedef veritabanına geçiş yapılmadı; uygulama fail-closed olarak legacy SQLite ile güvenle açıldı. (**PASS**)
4. **Tamamlanma İşaretinin Yazılamaması**:
   - Simülasyon: Veriler aktarıldı fakat `isCompleted` bayrağı yazılamadan kesinti oldu.
   - Sonuç: `DatabaseRoutingResolver` hedef DB'yi onaylamadı, eski veritabanı aktif kaldı. (**PASS**)
5. **Hedef Veritabanının Bozuk (Corrupt) Olması**:
   - Simülasyon: Hedef `.db` dosyasına rastgele geçersiz baytlar yazılarak dosya başlığı bozuldu.
   - Sonuç: Resolver ve bağlantı havuzu hatayı yakaladı (`DatabaseException`), uygulama çökmedi, legacy DB'ye fallback yaptı. (**PASS**)
6. **Eşzamanlı İki Başlangıç Girişimi (Concurrency Lock)**:
   - Simülasyon: İki ayrı thread/işlem aynı anda migration başlatmaya çalıştı.
   - Sonuç: Koordinatör kilit mekanizması ikinci çağrıyı derhal reddetti (`MigrationAlreadyRunningException`). (**PASS**)
7. **Hedefte Yeni Satış/Finans Kaydı Varken Rollback Girişimi (Unsafe Rollback Guard)**:
   - Simülasyon: Migration tamamlandıktan sonra hedef Core Next veritabanında yeni bir satış ve kasa tahsilatı oluşturuldu. Ardından eski veritabanına geri dönülmek istendi.
   - Sonuç: `DatabaseRoutingResolver.assertSafeRollback` yeni işlem kayıtlarını tespit ederek **`UnsafeRollbackException` fırlattı ve geri dönüşü kesin olarak engelledi**. Veri kaybı riski tamamen önlendi. (**PASS**)

---

## 6. BÖLÜM E — TEST, STATİK ANALİZ VE GİT DOĞRULAMASI

### E.1. Test Paketi İcra Matrisi

| Aşama / Test Dosyası | Test Sayısı | Başarılı | Başarısız | Çıkış Kodu | Durum |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Stage 10.12.12** (`stage10_12_12_anonymous_cash_sales_test.dart`) | 4 | 4 | 0 | 0 | **PASS** |
| **Stage 10.12.14** (`stage10_12_14_isolated_bootstrap_rehearsal_test.dart`) | 15 | 15 | 0 | 0 | **PASS** |
| **Stage 10.12.15** (`stage10_12_15_guarded_database_manager_test.dart`) | 8 | 8 | 0 | 0 | **PASS** |
| **Stage 10.12.16** (`stage10_12_16_audit_and_benchmark_test.dart`) | 5 | 5 | 0 | 0 | **PASS** |
| **Stage 10.12.17** (`stage10_12_17_progress_consent_test.dart`) | 13 | 13 | 0 | 0 | **PASS** |
| **Stage 10.12.19** (`stage10_12_19_fail_closed_ui_consent_test.dart`) | 15 | 15 | 0 | 0 | **PASS** |
| **Stage 10.12.20** (`stage10_12_20_final_isolated_rehearsal_test.dart`) | 17 | 17 | 0 | 0 | **PASS** |
| **TOPLAM** | **77** | **77** | **0** | **0** | **%100 PASS** |

### E.2. Statik Kod Analizi (`flutter analyze`)
- Komut: `flutter analyze lib/main.dart lib/presentation/widgets/branded_splash_screen.dart lib/infrastructure/bootstrap/app_bootstrap.dart lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart test/core_next/stage10_12_20_final_isolated_rehearsal_test.dart`
- Çıktı: `Analyzing 5 items... No issues found! (ran in 8.1s)`
- Çıkış Kodu: **0 (Tertemiz)**

### E.3. Git Biçim ve Boşluk Doğrulaması (`git diff --check`)
- Komut: `git diff --check`
- Çıktı: Whitespace/hata yok (Yalnızca platform CRLF uyarıları).
- Çıkış Kodu: **0**

---

## 7. BÖLÜM F — KESİN GÜVENLİK SINIRLARI TEYİDİ

Aşağıdaki kritik üretim güvenlik sınırlarının korunduğu kesin olarak teyit edilmiştir:

1. **Üretim Migration Runner**: `lib/main.dart` ve `app_bootstrap.dart` içinde `runner: null` olarak kapalıdır.
2. **Veritabanı Yönlendirme (Routing Hook)**: `databaseRoutingHook == null` durumdadır; uygulama varsayılan olarak legacy SQLite motoruna yönlenir.
3. **Core Next Satış Motoru Bayrağı**: `sales_engine_core_next_enabled == false` durumdadır.
4. **Canlı Nutopia Veritabanı**: `raw_nutopia_v60.db` yedeğinin SHA-256 imzası (`e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24`) değişmemiştir; tek bir bayt dahi yazılmamıştır.
5. **Erkul PostgreSQL**: Sunucu tarafına hiçbir bağlantı kurulmamış ve veri yazılmamıştır.
6. **Git Bütünlüğü**: Hiçbir commit, reset veya revert yapılmamış; kullanıcının çalışma dizini korunmuştur.

---

## 8. BÖLÜM G — NİHAİ DEĞERLENDİRME VE KARAR

- Gerçek UI ve yaşam döngüsü onay akışı: **PASS**
- Fail-closed güvenlik kapıları: **PASS**
- İzole veri aktarımı ve adli mutabakat: **PASS** (37,682 ürün, 584 müşteri, 52 satış, 792 sipariş, 1,403 defter kaydı, 21 anonim nakit satış fişi, 0 kayıp)
- İkinci çalıştırma (idempotency): **PASS** (0 çift kayıt)
- Hata senaryoları ve güvenli rollback bariyeri: **PASS**
- Regresyon testleri (77/77): **PASS**

### NİHAİ KARAR

```text
================================================================================
           ISOLATED REHEARSAL PASSED — PILOT REVIEW REQUIRED
================================================================================
```

> **ÖNEMLİ UYARI:** İzole provanın başarıyla tamamlanmış olması canlı üretime geçiş (production cutover) izni anlamına gelmez. Canlı geçişten önce yönetici pilot incelemesi ve kontrollü aşamalı dağıtım onay prosedürü gereklidir.
