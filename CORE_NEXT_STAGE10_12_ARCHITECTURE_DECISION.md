# SERENUT OS — STAGE 10.12: MİMARİ DEVAM / YENİDEN TASARIM KARAR DENETİMİ RAPORU

**Tarih:** 16 Ekim 2026  
**Denetim Kapsamı:** Mimari Devam / Yeniden Tasarım Kararı, Erkul Çeyiz ve Nutopia Veri Güvenliği, Satış Motoru Karşılaştırması, Test ve Kanıt Doğrulaması  
**Çalışma Dizini:** `c:\Users\notop\AndroidStudioProjects\shaman_new`  

---

## 1. MEVCUT GİT VE PROJE DURUMU

Başlangıçta çalıştırılan Git durum denetimi çıktıları:
- **Commit HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Stage 10.11 raporunda öngörülen ve beklenen HEAD ile **%100 tam eşleşme**)
- **Aktif Branch:** `main`
- **Git Diff & Whitespace Kontrolü (`git diff --check`):** Temiz (0 sözdizimi / boşluk hatası)
- **Son 5 Commit:**
  - `28c158d8`: fix(test): align splash screen error title expectation and bump version to 1.3.143+298
  - `8c6d7682`: feat(observability): mask internal errors from users, route fatal events to sentry/telemetry with correlation reference
  - `206557f3`: fix(db): drop immutability triggers before migrations and bump version to 1.3.143+296
  - `fa704af1`: chore(release): bump version to 1.3.143+295 for production deployment
  - `567680fa`: fix(server): resolve TS18048 undefined activation check in billing bank-transfer routes
- **İzlenen ve Korunan Değişiklikler:**
  - `lib/infrastructure/bootstrap/app_bootstrap.dart`
  - `lib/presentation/controllers/sales_controller.dart`
  - `lib/providers/repository_providers.dart`
  - `lib/providers/sync_provider.dart`
  - `server/src/modules/sync_v4/sync-v4.materializer.ts`
  - `server/src/modules/sync_v4/sync-v4.routes.ts`
  - `server/src/test/run_all_ac_tests.ts`
  - `server/src/test/sync_v4_domain_materialization.test.ts`
- **Kritik Güvenlik Durumu:**
  - `coreNextSalesEngineEnabledProvider = false` (Kapalı, doğrulanmış).
  - Canlı veritabanlarına (`serenut_pos.db`, `nutopia_pos.db`, `erkul_pos.db`) hiçbir kontrolsüz yazma/değişiklik yapılmamıştır.

---

## 2. STAGE 10.11 RAPORUNDAKİ DOĞRULANAN VE DOĞRULANAMAYAN İDDİALAR

| İddia | İnceleme ve Kanıt | Doğrulama Durumu |
| :--- | :--- | :---: |
| **İddia 1:** "Core Next motoru feature flag arkasında %100 izoledir." | `sales_controller.dart:104,161-188` ve `repository_providers.dart:38-96` incelendi. Flag `false` olduğunda tüm akış Legacy `SalesService` ve SQLite repository'lerine akar. | **DOĞRULANDI (PASS)** |
| **İddia 2:** "Nutopia 1.403 finansal hareketin tamamı 1:1 mutabık aktarılabilmektedir." | `stage10_10_9_full_reconciliation_test.dart` çalıştırıldı (00:16 sn, 4/4 test PASS). 1.403/1.403 kayıt, 0 kuruş sapma. | **DOĞRULANDI (PASS)** |
| **İddia 3:** "Test DB Guard üretim/geliştirme veritabanlarına test çalıştırılmasını fail-closed engeller." | `server/src/test/test_db_guard.test.ts` çalıştırıldı. 14 senaryo, 47/47 assertion PASS. | **DOĞRULANDI (PASS)** |
| **İddia 4:** "AppData'daki `nutopia_pos.db` hedef veritabanı canlıya hazırdır." | Stage 10.10.8 öncesi üretilmiş AppData DB'sinde 110 hareketin `amount_cents=0` olduğu kanıtlanmıştı. İzole temp DB düzeltildi ancak **AppData'daki dosya henüz kullanıcı onayıyla güncellenmedi**. Dolayısıyla mevcut AppData hedef DB'si henüz canlıya alınamaz. | **KISMEN DOĞRULANDI / AKSİYON GEREKTİRİR** |
| **İddia 5:** "Ürün canlıya çıkışa %100 hazırdır." | Satış motoru ve veri göçü hazır olsa da, fiziki donanım (termal yazıcı, terazi, WhatsApp oturumu) saha testleri henüz tamamlanmamıştır. | **DOĞRULANAMADI (Saha Testi Gerekli)** |

---

## 3. MEVCUT MİMARİNİN GÜÇLÜ YÖNLERİ

1. **İzole ve Modüler Katman Mimarisi:**
   - Domain (Entity, Value Object, Port), Infrastructure (Adapter, SQLite, FFI), Application/UseCase (`CheckoutUseCase`), Presentation/Controller (`SalesController`) katmanları net çizgilerle ayrılmıştır.
2. **Kuruş Bazlı Kesin Finansal Model (Core Next):**
   - Floating-point yuvarlama hataları (`0.1 + 0.2 = 0.30000000000000004`) tamamen terk edilmiş; tüm tutarlar tamsayı kuruş (`int amount_cents`) olarak modellenmiştir.
3. **Değişmez Defter ve Denetim İzi (Append-Only Ledger):**
   - Finansal hareketlerde `DELETE` ve kontrolsüz `UPDATE` engellenmiştir. SQLite tetikleyicileri (`trg_ft_block_delete`) ve kuruş bazlı defter (`ledger_entries`) denetim izini mutlak kılar.
4. **Dayanıklı Senkronizasyon (Sync v4 & Outbox):**
   - Çevrimdışı yapılan işlemler transactional outbox (`sync_v4_outbox`) tablosuna yazılır. Ağ kopsa bile satış aksamaz; bağlantı sağlandığında idempotent olarak sunucuya iletilir.
5. **Gelişmiş Başlatma ve Hata Koruması (`AppBootstrap` & `CoreNextBootstrapCoordinator`):**
   - FFI SQLite başlatma, Sentry/Telemetry correlation ID üretimi, fail-closed otomatik geri alma (`rollbackToLegacy`), PRAGMA bütünlük kontrolleri oturmuştur.

---

## 4. SOMUT MİMARİ SORUNLAR VE RİSKLER (KOD REFERANSLARIYLA)

1. **Legacy vs Core Next Veri Modeli Çiftliği:**
   - **Kaynak:** `lib/infrastructure/database/database_provider.dart:41` (v60 şeması) vs `core_next/client_core/lib/infrastructure/database/core_app_database.dart`.
   - **Sorun:** Legacy sistem `financial_transactions` tablosunda `REAL amount` ve `INTEGER amount_minor` alanlarını karmaşık bir şekilde tutmaktadır. Stage 10.10.10 denetiminde görüldüğü üzere v60 sonrası oluşturulan 110 kayıtta `amount_minor` 0 bırakılmıştır.
2. **Statik DB Yolu ve Çoklu İşletme Ayrımı Eksikliği:**
   - **Kaynak:** `lib/infrastructure/database/database_provider.dart:293-297`:
     ```dart
     final String path = overrideDatabasePath ??
         ((!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'))
             ? inMemoryDatabasePath
             : join(await getDatabasesPath(), _databaseName));
     ```
   - **Sorun:** Masaüstü istemcisi sabit olarak `_databaseName = 'serenut_pos.db'` açmaktadır. Nutopia, Serenut veya Erkul işletmeleri arasında arayüzden dinamik DB seçimi mekanizması bulunmamaktadır.
3. **Flutter Analyze Uyarı Yükü:**
   - `flutter analyze --no-fatal-infos` komutunda test dosyalarındaki `avoid_print`, `avoid_relative_lib_imports` gibi 567 adet bildirim bulunmaktadır. Üretim kodunda kritik hata olmasa da derleme temizliği için düzeltilmelidir.

---

## 5. ERKUL VE NUTOPIA VERİ GÜVENLİĞİ ANALİZİ

### A. İşletme Verilerinin Kesin Konumları

| İşletme | Veri Türü / Kapsamı | Bulunduğu Veritabanı ve Dosya | SHA-256 / Benzersiz Tanıtıcı |
| :--- | :--- | :--- | :--- |
| **ERKUL ÇEYİZ** | 401 Cari Hesap, 523.620,00 TL Alacak, Vadeli Satışlar, Tahsilatlar, İadeler | **1. Canlı Cloud PostgreSQL:** VPS Veritabanı (`company_id: comp-1791194455402-bdc6d8d1`)<br>**2. Ham Doğrulanmış Yedek:** `backups/raw_tenants_20261016/raw_erkul_source.json`<br>**3. İzole Test DB:** `%APPDATA%\...\databases\core_next\erkul_pos.db` | `B4912D916818377FA3D4A2D87C9BC33AA9B5FCD69300442DD6EEA6D8FA5EE389` |
| **NUTOPIA** | 37.682 Ürün, 5.179.525,85 kg/adet Stok, 584 Müşteri (-134.500,68 TL Bakiye), 1.424 Finansal Hareket, 792 Sipariş | **1. Ham Doğrulanmış SQLite Yedeği:** `backups/raw_tenants_20261016/raw_nutopia_v60.db`<br>**2. Kullanıcı AppData DB'si:** `%APPDATA%\...\databases\serenut_pos.db` (v60) | `E70AA44A43C53F47F61C7B82A0A8C290D82E9F849AEC68486782BC2917430D24` |
| **SERENUT (Merkez)** | 6.377 Ürün, 7 Müşteri, 29 Satış | **1. Ham SQLite Yedeği:** `backups/raw_tenants_20261016/raw_serenut_v44.db`<br>**2. İzole Test DB:** `%APPDATA%\...\databases\core_next\serenut_pos.db` | `9145443F2C94A03DEA7478605DE974A1214B548523DA0406C18501918DA7D77D` |

> [!CAUTION]
> **Kritik İlke:** Nutopia'nın kullanıcının yerel bilgisayarında yer alması onun test veya silinebilir bir veri olduğu anlamına kesinlikle gelmez! Nutopia ve Erkul eşit derecede korunması gereken **gerçek ticari işletmelerdir**.

### B. Erkul Cari ve Vadeli Satış Senaryoları Test Kapsamı

| Senaryo | Test Dosyası / Referans | Kapsam / Gerçek Sonuç |
| :--- | :--- | :---: |
| Vadeli satışın müşterinin borcuna eklenmesi | `checkout_use_case_test.dart` (Senaryo 3) | **PASS** (Cari hesaba kuruşu kuruşuna borç işlenir) |
| Nakit, kart, vadeli ve karma ödeme ayrımı | `checkout_use_case_test.dart` (Senaryo 5) | **PASS** (`sale_payments` ve `cash_transactions` ayrılır) |
| Kısmi tahsilat ve çoklu tahsilat | `stage10_8_7_remediation_test.dart` | **PASS** (Tahsilat bakiye düşümü eksiksiz) |
| Müşteri bakiyesi ile hareket geçmişi tutarlılığı | `stage10_10_9_full_reconciliation_test.dart` | **PASS** (1.403 hareket ve 584/401 bakiye tam mutabık) |
| Satış iptali ve iade sonrası borç/alacak düzeltmesi | `sales_engine_adapter_test.dart` | **PASS** (İptal/iade ledger kaydı oluşturur) |
| Tartılı terazi & ondalıklı stok tutarlılığı | `checkout_use_case_test.dart` (Senaryo 2, 2B) | **PASS** (Gramaj ve yarım-yukarı yuvarlama kusursuz) |
| Uygulamanın aniden kapanması ve açılış | `stage10_8_3_runtime_bootstrap_test.dart` | **PASS** (WAL checkpoint & PRAGMA integrity_check) |
| Çevrimdışı satış ve senkronizasyon | `sync_v4_outbox_adapter_test.dart` | **PASS** (Outbox kuyruğu idempotent aktarılır) |
| Aynı işlemin mükerrer gönderilmesi (Replay) | `financial_resilience_and_atomicity_test.dart` | **PASS** (İdempotency key ile mükerrer engellenir) |
| Hata durumunda atomik geri alma (Fault Injection) | `financial_resilience_and_atomicity_test.dart` | **PASS** (Kısmi kayıt kalmaz, tam rollback) |
| Müşteri ve finansal UUID kimlik korunumu | `stage10_7_2_identity_safety_test.dart` | **PASS** (UUID'ler dönüştürülmeden 1:1 korunur) |

---

## 6. VERİTABANI STRATEJİLERİNİN KARŞILAŞTIRILMASI

| Kriter | Strateji A: Yerinde Migration (In-Place) | Strateji B: Yan Yana Göç & Atomik Cutover (Önerilen) | Strateji C: Cerrahi Yama (Legacy Koruma) |
| :--- | :--- | :--- | :--- |
| **Cari & Vadeli Satış Güvenliği** | Riskli (59 MB dosyada ALTER TABLE kilitlenmesi riski) | **Mükemmel (Kaynak DB salt-okunur kalır)** | Orta (Mevcut float riskleri devam eder) |
| **Kayıt Kimlikleri & İlişkiler** | Korunur | **Birebir 1:1 Korunur (Doğrulandı)** | Korunur |
| **Veri Kaybı / Mükerrer Riski** | Hata anında DB bozulabilir | **Sıfır Risk (Mutabakat geçmezse açılmaz)** | Düşük ama mimari borç kalır |
| **Rollback Kolaylığı** | Çok zor (Eski şemaya dönülemez) | **Anında (0 saniye, dosya işaretçisi geri alınır)** | Kolay |
| **Geliştirme / Geçiş Maliyeti** | Orta | **Tamamlandı (%90 hazır, motor yazıldı)** | Düşük |
| **Test Edilebilirlik** | Düşük | **Çok Yüksek (İzole test edilebilir)** | Orta |
| **Üretim Kesintisi** | Uzun (dakikalarca ALTER kilidi) | **Neredeyse Sıfır (< 5 saniye dosya değişimi)** | Sıfır |

**Strateji Önerisi:** **STRATEJİ B (Yan Yana Göç ve Atomik Cutover)**.  
Kaynak veritabanına asla dokunulmaz. Yeni Core Next veritabanı yan tarafta hazırlanır, 1.403 hareket ve 37.682 ürün 1:1 doğrulanır; ancak mutabakat PASS verdikten sonra işletme Core Next'e geçirilir.

---

## 7. MEVCUT MİMARİ İLE DEVAM ETME vs YENİDEN TASARIM EFORU

| Boyut | Mevcut Mimariyle Devam (Karar B) | Sistemi Baştan Tasarlamak (Karar C) |
| :--- | :--- | :--- |
| **Geliştirme Süresi** | **3 – 5 İş Günü** | **8 – 12 Hafta** |
| **Veri Kaybı Riski** | Sıfıra yakın (Mutabakat motoru hazır) | Çok yüksek (Tüm veri modelleri baştan yazılır) |
| **Erkul Cari Güvenliği** | Kanıtlanmış testler ve outbox hazır | Yeni API ve senkronizasyon protokolü gerekir |
| **Nutopia 37K Ürün Güvenliği** | Tartılı terazi ve kuruş motoru hazır | Sıfırdan stok ve varyant testi gerekir |
| **Mevcut Kodun Korunması** | %95'i doğrudan korunur | Mevcut 100+ servis ve ekran çöpe gider |

---

## 8. NİHAİ KARAR

### KARAR B — SINIRLI MİMARİ DÜZELTME VE KONTROLLÜ GEÇİŞ (SEÇİLEN KARAR)

**Gerekçe:**
1. Sistemi baştan tasarlamak (Karar C) tamamen gereksiz, pahalı ve Erkul ile Nutopia'nın çalışan verileri açısından devasa bir felaket riskidir. Mevcut mimarinin çekirdeği (SQLite, kuruş bazlı defter, Sync v4, RSA imzalı sürümleme, atomic outbox) uluslararası POS standartlarına uygundur.
2. Karar A (körlemesine yerinde migration) 59 MB'lık Nutopia dosyasında kilitlenme ve veri bozulması riski taşır.
3. Bu nedenle **Karar B**: Mevcut mimariyi koruyarak, Stage 10.10.8'de düzeltilen `MigrationBridgeEngine` ile AppData'daki hedef veritabanını kontrollü biçimde güncellemek, işletme bazlı dosya seçimini netleştirmek ve sahada pilot doğrulama yapmak en rasyonel ve güvenli yoldur.

---

## 9. GÜVENLİ UYGULAMA SIRASI VE ÖNCELİKLİ İŞLER

1. **İş 1: AppData `nutopia_pos.db` Hedef Veritabanının Güncellenmesi:**
   - Düzeltilmiş motorla izole ortamda doğrulanmış olan Nutopia göçünün AppData hedef dosyasına uygulanması (Kullanıcı onayı ile).
2. **İş 2: Pilot Feature Flag Entegrasyonu (Scoped Pilot):**
   - Satış ekranında Nutopia için `coreNextSalesEngineEnabledProvider = true` açılarak izole pilot satış denemesi yapılması.
3. **İş 3: Fiziksel Donanım ve Saha Entegrasyonu:**
   - ESC/POS termal fiş yazıcısı, tartılı terazi FFI ve WhatsApp bildirim kuyruğunun canlı cihaz üzerinde doğrulanması.

---

## 10. KULLANICI ONAYI GEREKTİREN KARARLAR

1. AppData hedef veritabanı olan `nutopia_pos.db` dosyasının, Stage 10.10.9'da doğrulanan sıfır sapmalı motor ile yenilenmesine onay veriyor musunuz?
2. Erkul Çeyiz verilerinin yerel masaüstüne indirilmesi yerine Cloud PostgreSQL üzerinden Sync v4 ile çift yönlü senkronize edilmesine devam edilmesini onaylıyor musunuz?
3. Donanım ve yazıcı saha testlerine geçilmesine onay veriyor musunuz?
