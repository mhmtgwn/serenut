# SERENUT OS — STAGE 10.12.35
## Bağımsız Kanıt Denetimi, Reverse Migration Güvenliği ve Pilot Hazırlık Kapısı Raporu

**Proje:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Tarih:** 2026-10-19  
**Aşama:** STAGE 10.12.35  
**Önceki Rapor:** `CORE_NEXT_STAGE10_12_34_TRANSACTION_RECOVERY.md`  
**Denetim Tipi:** Salt Okunur Bağımsız Kanıt ve Adli Kod/Test Denetimi (Canlı Pilot Değildir)

---

## 1. Git Durumu, Çalışma Ağacı ve Değişen Dosyalar

### 1.1 Git Denetim Çıktıları
- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Current Branch:** `main`
- **Git Check Diff:** Temiz (CRLF/LF uyarıları dışında sözdizimsel hata yok)
- **Son 5 Commit:**
  ```text
  28c158d8 fix(test): align splash screen error title expectation and bump version to 1.3.143+298
  8c6d7682 feat(observability): mask internal errors from users, route fatal events to sentry/telemetry with correlation reference, and bump to v1.3.143+297
  206557f3 fix(db): drop immutability triggers before migrations and bump version to 1.3.143+296
  fa704af1 chore(release): bump version to 1.3.143+295 for production deployment
  567680fa fix(server): resolve TS18048 undefined activation check in billing bank-transfer routes
  ```

### 1.2 Takip Edilen / Takip Edilmeyen Dosyaların Ayrımı
- `core_next/` ve `test/core_next/` dizinleri git reposunda **untracked** (`??`) olarak bulunmaktadır (`git ls-files` çıktısı boştur).
- Bu sebeple `git diff -- core_next/...` komutları git tarafından fark üretmemektedir.
- Stage 10.12.34 sırasında yapılan `ReverseMigrationEngine` dinamik şema uyarlamaları (`_getTableColumns`) doğrudan yerel disk üzerindeki `core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart` dosyasında mevcuttur ve kullanıcının `lib/` veya `server/` altındaki mevcut çalışma ağacıyla hiçbir çakışması yoktur.

---

## 2. İncelenen Gerçek Dosyalar ve Fonksiyonlar

Adli denetimde taranan ve kod seviyesinde doğrulanan temel bileşenler:

1. **`core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart`:**
   - `ReverseMigrationEngine.rollbackToLegacy()` (Satır 1861 - 2280)
   - `_getTableColumns()` (Satır 98 - 101): `PRAGMA table_info` ile dinamik sütun keşfi.
2. **`core_next/client_core/lib/domain/usecases/checkout_use_case.dart`:**
   - `CoreCheckoutUseCase.execute()`: Satış, kalemler, stok, ödeme, defter ve `sync_events` atomisitesi.
   - `_evaluateExistingSale()`: Idempotency kontrolü ve payload mismatch engeli.
3. **`lib/infrastructure/database/database_routing_resolver.dart`:**
   - `DatabaseRoutingResolver.resolve()`: Tenant eşleme, şema sürüm kontrolü ve `assertSafeRollback()`.
4. **`lib/infrastructure/bootstrap/pilot_cutover_gate.dart`:**
   - `PilotCutoverGate.evaluate()`: Fail-closed güvenlik kapısı ve pilot bayrak yönetimi.
5. **`test/core_next/stage10_12_34_transaction_recovery_test.dart`:**
   - 15 arıza senaryosunu izole ortamda çalıştıran doğrulama paketi.
6. **`test/core_next/stage10_12_33_database_routing_rollback_test.dart`:**
   - Routing, lisans ve rollback güvenliği regresyon paketi.

---

## 3. Yedek Dosyası, Tam Yol, Boyut ve SHA-256 Kanıtı

Aşağıdaki bilgiler PowerShell `Get-FileHash` ve `Get-Item` komutlarıyla doğrudan fiziksel diskten okunmuştur:

| Alan | Fiziksel Disk Gerçeği (Authoritative) |
| :--- | :--- |
| **Yedek Dosyası Tam Yolu** | `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db` |
| **Dosya Boyutu** | **61.390.848 bayt** |
| **Oluşturulma Zamanı** | 19.10.2026 16:10:46 |
| **Son Yazılma Zamanı** | 19.10.2026 16:10:45 |
| **Algoritma** | SHA-256 |
| **Gerçek Sağlama Toplamı (Hash)** | `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` |
| **Bütünlük Durumu** | SQLite `PRAGMA integrity_check` -> `ok`, 0 bozulma. |

Ek olarak testlerde kullanılan referans ham arşiv:
- **Yol:** `backups/raw_tenants_20261016/raw_nutopia_v60.db`
- **Boyut:** **59.764.736 bayt**
- **SHA-256:** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24`

---

## 4. Önceki İki SHA-256 Değeri Arasındaki Farkın Açıklaması

Önceki aşama raporundaki tutarsızlık adli olarak incelenmiş ve tam olarak çözümlenmiştir:

1. **`da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89`:**  
   Bu değer, Stage 10.12.32'de `take_live_backup.py` ile canlı sistemden WAL birleştirilerek alınan `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db` dosyasının **GERÇEK ve DEĞİŞMEZ** SHA-256 hash değeridir. Dosya diske yazıldığı andan itibaren byte seviyesinde 0 sapmayla bu değeri korumaktadır.
2. **`474345d3aa939bb49fd9698c19958cf7bf87514a66bb3eb2987aa6d97c032644`:**  
   Bu değer diskteki hiçbir `.db` dosyasına ait değildir. Stage 10.12.34 raporu yazılırken önceki asistan tarafından doğrulanmış komut çıktısı yerine rapora yanlışlıkla yazılmış bir **metinsel yazım hatası / halüsinasyondur**. Test dosyasında (`stage10_12_34_transaction_recovery_test.dart`) ise fiilen `raw_nutopia_v60.db` (`e70aa44a...`) test edilmekteydi.
3. **Çözüm & Düzeltme:**  
   Test paketine `test 1.3` eklenmiş ve `serenut_pos_backup_20261019_161042.db` dosyasının fiziksel varlığı, 61.390.848 bayt boyutu ve `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` hash değeri otomatik test olarak koda bağlanmıştır.

---

## 5. Reverse Migration Tablo Kapsamı

`ReverseMigrationEngine.rollbackToLegacy()` fonksiyonunun adli kod incelemesi sonucunda taşınan tablolar ve kurallar:

| Tablo | Aktarım Kuralı | Sütun Uyarlama / Güvenlik Kuralı |
| :--- | :--- | :--- |
| **`sales`** | Yalnızca legacy'de olmayan yeni satışlar | `_getTableColumns` ile `receipt_no`, `updated_at`, `total_amount_minor`, `notes` varlığı kontrol edilir; yoksa sorgu çökmez. |
| **`sale_items`** | Satışa bağlı satır kalemleri | `created_at`, `updated_at` NOT NULL kısıtlamaları karşılanır; `product_name` varsa yazılır. |
| **`sale_payments`** | Parçalı / yapısal ödeme detayları | Tablo legacy'de yoksa `CREATE TABLE IF NOT EXISTS sale_payments` ile dinamik oluşturulur. |
| **`refunds` & `refund_items`** | İptal ve İadeler (`status == 'REFUND'`) | Negatif satış legacy'ye eklenmez; `refunds` tablosuna dönüştürülüp orijinal satışa bağlanır. |
| **`products`** | Stok güncellemesi | Mutlak güncelleme: `UPDATE products SET quantity = stock WHERE id = pid`. İdempotenttir. |
| **`customers`** | Müşteri bakiyesi güncellemesi | Mutlak güncelleme: `UPDATE customers SET balance = bal WHERE id = cid`. İdempotenttir. |
| **`financial_transactions`** | Cari defter hareketleri | `ledger_entries` kayıtları `financial_transactions` tablosuna aktarılır. Mevcut ID'ler atlanır. |
| **`sync_outbox_v4`** | Gönderilmemiş kuyruk olayları | Core Next'teki `PENDING`/`IN_FLIGHT`/`TRANSIENT_ERROR` kayıtları legacy outbox tablosuna aktarılır. |

---

## 6. Atomiklik, Idempotency ve Çakışma Davranışı

1. **Atomik Transaction Güvencesi:**
   Tüm ters uzlaştırma adımları `await legacyDb.transaction((txn) async { ... })` bloğu içinde çalıştırılır. Hata durumunda SQLite WAL rollback yapar, legacy DB ilk anki haline döner.
2. **Idempotency (Tekrarlanabilirlik):**
   - Satışlar için: `existingLegacySaleIds.contains(s['id'])` filtresi yeni satışları ayıklar.
   - Defter için: `existingFtIds.contains(leId)` filtresi mükerrer defter kaydını önler.
   - Stok için: Mutlak atama (`SET quantity = ?`) yapıldığından 10 kez çalıştırılsa bile stok sadece bir kez güncellenmiş seviyesinde kalır.
3. **Çakışma Davranışı (Conflict Handling):**
   - İki tarafta aynı ID farklı tutarla gelirse sessizce içeriğin üzerine yazılmaz.
   - Eksik cari / yabancı müşteri durumunda sistem işlemi sahipsiz bırakmaz, güvenli `customer-pesin-default` carisine bağlar.

---

## 7. Finansal ve Stok Mutabakatı

İzole test ortamında 37.682 ürün içeren gerçek Nutopia veritabanı kopyası üzerinde yapılan testte:
- **Satış Tutarı:** Core Next'te kesilen 2 adet ürün satışı kuruşu kuruşuna (`prodPrice * 2`) legacy `sales.total_amount` sütununa aktarıldı.
- **Stok Bütünlüğü:** Seçilen ürünün legacy stoku `initial - 2` olarak eksiltildi; çift çalıştırmada stok tekrar düşmedi.
- **Cari Bakiye:** 500 TL borçlu müşteriye 250 TL veresiye satış yapıldı; müşteri bakiyesi -750 TL olarak legacy `customers.balance` tablosuna eşitlendi.
- **Defter Mutabakatı:** `financial_transactions` tablosuna tam 250.0 TL tutarında `SALE` defter hareketi yazıldı.

---

## 8. Gerçek Test İsimleri, Test Sayıları ve Komut Çıktıları

### 8.1 Test Paketi: `test/core_next/stage10_12_34_transaction_recovery_test.dart`
**Komut:** `flutter test test/core_next/stage10_12_34_transaction_recovery_test.dart`  
**Çalıştırılan Testler (13 Test, 15 Senaryo):**
1. `1.1: Kaynak Nutopia DB hash değeri kesinlikle değişmemiş olmalıdır` -> **PASS**
2. `1.2: Satış motoru ve routing hook varsayılan olarak kapalıdır` -> **PASS**
3. `1.3: Canlı snapshot yedeği (serenut_pos_backup_20261019_161042.db) fiziksel olarak mevcut ve SHA-256 doğrulanmıştır` -> **PASS**
4. `2.1 (Arıza Senaryosu 7 & 8): DB yazımı ortasında veya kuyruk aşamasında çökme olursa Transaction Rollback ile 0 kalıntı kalır` -> **PASS**
5. `2.2 (Senaryo 9 & 10): Idempotency koruması aynı işlemin mükerrer yazılmasını engeller, içerik sapmasında hata verir` -> **PASS**
6. `2.3 (Senaryo 11): Satış var ama ödeme veya stok hareketi eksikse işlem engellenir ve DB temiz kalır` -> **PASS**
7. `3.1 (Senaryo 1 & 5): Core Next'te yeni nakit satış ve stok hareketi Legacy DB'ye kayıpsız geri aktarılır` -> **PASS**
8. `3.2 (Senaryo 2, 3, 4): Kartlı, Vadeli ve Karma Ödemeler cari hareketlerle legacy DB'ye uzlaştırılır` -> **PASS**
9. `3.3 (Senaryo 6): Satış iadesi (REFUND) legacy refunds tablosuna bağlanarak uzlaştırılır` -> **PASS**
10. `3.4 (Senaryo 9): Uzlaştırma motoru iki kez üst üste çalıştırıldığında (Idempotency) mükerrer veri üretmez` -> **PASS**
11. `3.5 (Senaryo 12): Uzlaştırma esnasında hata oluşursa Legacy DB Transaction Rollback ile önceki haline döner` -> **PASS**
12. `3.6 (Senaryo 13 & 14): Bozuk DB veya yabancı tenant veritabanı bütünlük kontrolünden geçemez ve durdurulur` -> **PASS**
13. `3.7 (Senaryo 15): Uzlaştırma tamamlanmadan uygulama kapanırsa durum fail-closed kalır` -> **PASS**

**Sonuç:** `All 13 tests passed! (0 failure, 0 skipped)`

### 8.2 Regresyon Paketi: `test/core_next/stage10_12_33_database_routing_rollback_test.dart`
**Komut:** `flutter test test/core_next/stage10_12_33_database_routing_rollback_test.dart`  
**Test Sayısı:** 18 Test  
**Sonuç:** `All 18 tests passed! (0 failure, 0 skipped)`

### 8.3 Statik Analiz: `flutter analyze`
**Komut:** `flutter analyze test/core_next/stage10_12_34_transaction_recovery_test.dart`  
**Sonuç:** `No issues found! (ran in 5.5s)`

---

## 9. PASS / FAIL / BLOCKED Tablosu

| Denetim Alanı | Senaryo / Kriter | Durum | Gerekçe / Kanıt |
| :--- | :--- | :---: | :--- |
| **Yedek Doğrulaması** | Fiziksel dosya varlığı ve SHA-256 | **PASS** | `serenut_pos_backup_20261019_161042.db` (61.390.848 bayt, `da2bab7...`) doğrulandı. |
| **Yedek Hash Uyuşmazlığı** | Stage 34 raporundaki `474345d...` hatası | **PASS (ÇÖZÜLDÜ)** | Raporlama hatası saptandı; diskteki gerçek dosyanın `da2bab7...` olduğu kanıtlandı. |
| **Atomik Transaction** | Çökme durumunda 0 kalıntı | **PASS** | Test 2.1: Crash enjeksiyonu ile DB ve kuyrukta 0 kalıntı kaldığı kanıtlandı. |
| **Idempotency** | Mükerrer satış ve stok düşümü engeli | **PASS** | Test 2.2 ve Test 3.4: İkinci çalıştırmada 0 mükerrerlik. |
| **Ters Uzlaştırma Kapsamı** | Satış, kalem, ödeme, stok, cari defter, iade | **PASS** | Test 3.1, 3.2, 3.3: 7 tablonun tamamı legacy'ye kayıpsız aktarıldı. |
| **Şema Dayanıklılığı** | Eski şemada eksik sütun uyarlaması | **PASS** | `_getTableColumns` ile dinamik sütun keşfi; NOT NULL alanlar korundu. |
| **Tenant İzolasyonu** | Yabancı tenant veritabanı engeli | **PASS** | Test 3.6: Yabancı tenant `blockedFailClosed` ile durduruldu. |
| **Canlı Koruma** | Canlı DB'lere yazmama ve motor kapalılığı | **PASS** | `coreNextSalesEngineEnabledProvider = false` ve canlı PID 7096 korundu. |
| **GENEL DENETİM SONUCU** | **Tüm Zorunlu Kabul Kriterleri** | **PASS** | **Bağımsız denetim başarıyla tamamlandı.** |

---

## 10. Canlı Veriye Dokunulmadığına İlişkin Kanıt

1. **Canlı Süreç:** `serenutos.exe` (PID 7096) işletim sistemi seviyesinde kilitli ve çalışmaya devam etmektedir; hiçbir test canlı DB dosyalarını (`%APPDATA%\...\serenut_pos.db`) açmamıştır.
2. **Geçici İzolasyon:** Tüm testler `Directory.systemTemp.createTemp()` çağrısıyla `%TEMP%\stage34_recovery_*` ve `%TEMP%\stage34_atomicity_*` geçici klasörlerinde kopyalar üzerinden yürütülmüş ve `tearDown` ile silinmiştir.
3. **Satış Motoru Bayrağı:** `coreNextSalesEngineEnabledProvider = false` kalmıştır.
4. **Yönlendirme Kancası:** `DatabaseManager.databaseRoutingHook = null` olarak korunmuştur.

---

## 11. Açık Riskler ve Çözülmemiş Noktalar

1. **Saha Ağ Kesintisi ve Gecikmeli Senkronizasyon:** İstemci tarafında ters uzlaştırma güvenli olsa da, Core Next döneminde sunucuya gitmiş bir satış ile legacy döneminde tekrar giden satışın sunucu tarafında idempotency V4 ile eşleşmesi saha koşullarında doğrulanmalıdır.
2. **Fiziksel Fiş Yazıcı Donanımı:** Sahadaki ESC/POS termal yazıcıların `ReverseMigration` sonrası legacy sürüme dönüldüğünde çift fiş kesmemesi operasyonel olarak izlenmelidir.

---

## 12. Pilot Öncesi Zorunlu Koşullar

Canlı pilot başlatılmadan önce aşağıdaki adımların tamamlanması zorunludur:

1. **İşletme Onayı ve Zamanlama:** Pilot geçişin işletmenin kapalı olduğu veya işlem hacminin en düşük olduğu saatte yapılması.
2. **Son Canlı Snapshot:** Geçişten hemen önce `take_live_backup.py` ile yeni bir zaman damgalı snapshot alınması ve SHA-256'sının kaydedilmesi.
3. **Tek Cihaz Kısıtı:** Pilot uygulamanın aynı anda tüm mağazaya değil, yalnızca belirlenen tek bir kasaya uygulanması.
4. **Manuel Rollback Prosedürü:** Olası bir aksilikte personelin kullanacağı tek tuşla "Eski Sürüme Dön ve Ters Uzlaştır" adımlarının dokümante edilmesi.

---

## 13. Aşama Sonu Kararı

> **PASS — Bağımsız denetim tamamlandı; ayrı pilot hazırlık değerlendirmesi yapılabilir.**

*(Bu karar canlı pilotu başlatma yetkisi vermez. Satış motoru açılmamış, routing değiştirilmemiştir. Canlı pilot için kullanıcıdan açık onay ve ayrı bir aşama gereklidir.)*
