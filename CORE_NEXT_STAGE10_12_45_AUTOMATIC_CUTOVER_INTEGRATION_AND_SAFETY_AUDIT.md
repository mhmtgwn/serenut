# SERENUT OS — STAGE 10.12.45
# OTOMATİK GEÇİŞİN ENTEGRASYONU VE CANLI VERİ GÜVENLİĞİ DENETİM RAPORU

**Tarih:** 20 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Branch:** `main`  
**HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Durum:** Temiz git ağacı, kullanıcı değişiklikleri korundu  
**Aşama Kararı:** **`BLOCKED`** (Canlı Cutover Açılması Engellendi — Fail-Closed Güvenlik ve Doğrulama Şartları Korundu)

---

## 1. GERÇEK KOD VE MİMARİ ENTEGRASYON DURUMU

Nutopia, Serenut ve Erkul Çeyiz çalışan, canlı perakende işletmeleridir. Bu aşamada, geçiş mimarisinin sadece izole test sınıfları olarak kalmadığı, gerçek açılış ve yönlendirme zincirine bağlandığı doğrulanmıştır.

### 1.1. Gerçek Çağrı Zinciri İncelemesi

```mermaid
graph TD
    A["lib/main.dart (AppBootstrap.initPreApp)"] --> B["lib/infrastructure/bootstrap/app_bootstrap.dart (runStartupDiagnostics)"]
    B --> C["CoreNextBootstrapCoordinator.coordinate(autonomousMode: true)"]
    C --> D{"Persistent State Kontrolü (SharedPreferences)"}
    D -- "failedBlocked" --> E["Legacy Akışta Kal (Fail-Closed)"]
    D -- "notStarted / failedRecoverable" --> F["WAL Checkpoint & Verified Atomic Backup"]
    F --> G["MigrationBridgeEngine.runMigration() (İlk Aktarım)"]
    G --> H["LiveSafeCatchUpReconciliationCoordinator (Canlı Catch-Up)"]
    H --> I{"Çapraz Tablo Mutabakatı & PRAGMA Integrity Check"}
    I -- "Sapma / Hata" --> J["cutover_reconciliation_status = 'blocked' -> Legacy Fallback"]
    I -- "Tam Eşleşme" --> K["cutover_reconciliation_status = 'approved'"]
    K --> L["DatabaseRoutingResolver (PilotGate & FeatureFlag Kontrolü)"]
    L --> M{"coreNextSalesEngineEnabledProvider == false?"}
    M -- "Evet (Mevcut Durum)" --> N["Güvenli Legacy Satış Motoru Korunur"]
    M -- "Gelecekteki Kontrollü Cutover" --> O["Core Next v2 Veritabanı"]
```

### 1.2. İncelenen Dosyalar ve Gerçek Çalışma Durumu

1. **`lib/infrastructure/bootstrap/app_bootstrap.dart`**:
   - `runStartupDiagnostics` metodunda `coreNextBootstrapCoordinatorProvider` okunur.
   - `coordinator.coordinate(autonomousMode: true)` çağrısıyla müşteri onayı gerektirmeksizin arka planda otonom geçiş koordine edilir.
   - `coreNextMigrationRunnerProvider` veya `coreNextCatchUpRunnerProvider` tanımlı olmadığı sürece hiçbir canlı operasyon bozulmaz, fail-closed olarak legacy çalışır.

2. **`lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart`**:
   - Dart paket sınırlarına (`lib/` dışına çıkış kısıtlamalarına) tam uyumlu olarak `CoreNextCatchUpRunner` arayüzü ile donatılmıştır.
   - Canlı işletmelerde aktarım sırasında ve sonrasında oluşan yeni hareketler, son mutabakat (Reconciliation Step 7) çalışmadan hemen önce yakalanır (`Step 6.1`).
   - Bu sayede ara dönemde yapılan satış ve stok düşümleri hedef veritabanına uygulanır ve son mutabakat matematiksel olarak tam tutarlı bir snapshot üzerinde gerçekleşir.

3. **`core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart`**:
   - Ürünler, cariler, satışlar, satış kalemleri, parçalı ödemeler ve finansal defter hareketlerini kapsayan dinamik ve şema-esnek sorgulama motoru geliştirilmiştir.
   - Tablolarda kolon eksikliği (ör. `sku`, `phone`, `paid_amount`) durumunda çökme yaşanmaz; dinamik kolon tespiti ile güvenle delta yakalanır.
   - Yabancı anahtar (Foreign Key) kısıtlarının ihlal edilmemesi için ilişkili cari kayıtları atomik işlem içinde otomatik güvenceye alınır.
   - Sonuç `app_settings` tablosundaki `cutover_reconciliation_status` anahtarına kalıcı olarak (`approved` veya `blocked`) kaydedilir.

4. **`core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart`**:
   - `DatabaseRoutingResolver.resolve()` metodu, `app_settings` içindeki `cutover_reconciliation_status` değerini doğrudan denetler.
   - Eğer mutabakat durumu `blocked` veya `diverged` ise, hedef seçimini kesinlikle reddeder ve `RoutingDecision.legacyFallback` döner.

5. **`core_next/client_core/lib/infrastructure/database/legacy_database_retirement_policy.dart`**:
   - Eski veritabanının silinmesini kesin olarak engeller.
   - 7 katı güvenlik kriteri (özellikle Core Next üzerinde asgari 14 gün kesintisiz çalışma ve sıfır outbox kuyruğu) sağlanmadan emekliliği reddeder.
   - Tüm kriterler sağlandığında dahi dosya silinmez; `.archived_<timestamp>` olarak güvenli arşive taşınır.

---

## 2. EN KRİTİK DENETİM SORULARI VE KANITLAR

| # | Soru | Gerçek Davranış ve Kanıt | Değerlendirme |
|---|---|---|---|
| **1** | Uygulama açılışında catch-up koordinatörü gerçekten çağrılıyor mu? | **EVET.** `app_bootstrap.dart:L341-364` içerisinde `coordinator.coordinate(autonomousMode: true)` üzerinden tetiklenir. `coreNextCatchUpRunnerProvider` aktif edildiğinde Step 6.1 otomatik yürütülür. | **PASS** |
| **2** | İlk migration tamamlandığında otomatik olarak tetikleniyor mu? | **EVET.** `CoreNextBootstrapCoordinator` içerisinde Step 6 (ilk aktarım) tamamlandıktan hemen sonra Step 6.1 olarak `effectiveCatchUpRunner` otomatik olarak çağrılır. | **PASS** |
| **3** | Uygulama kapanıp yeniden açıldığında kaldığı yerden devam ediyor mu? | **EVET.** `getPersistentState()` ile `backup_in_progress` veya `migration_in_progress` tespit edilirse, sistem `failedRecoverable` durumuna alıp güvenli temiz yeniden denemeyi otonom başlatır (`stage10_12_45_automatic_cutover_integration_test.dart: Grup 4`). | **PASS** |
| **4** | Bir hata oluştuğunda sonraki deneme otomatik yapılıyor mu? | **EVET.** Kurtarılabilir hatalarda (`failedRecoverable`) bir sonraki açılışta koordinasyon tekrar çalışır; ancak 3 kez ardışık blokaj yaşanırsa `failedBlocked` ile kilitlenip legacy'de güvenle kalır. | **PASS** |
| **5** | Doğrulama sonucu gerçekten `DatabaseRoutingResolver` kararını etkiliyor mu? | **EVET.** `cutover_reconciliation_status != 'approved'` ise resolver `RoutingDecision.legacyFallback` döner (`stage10_12_45_automatic_cutover_integration_test.dart: Test 5.1`). | **PASS** |
| **6** | Cutover onayı olmadan yeni veritabanına yönlendirme mümkün mü? | **HAYIR.** Cutover onayı (`approved`) ve `PilotCutoverGate` geçmeden yeni veritabanı aktif olamaz. Ayrıca `coreNextSalesEngineEnabledProvider = false` sabiti korunmaktadır. | **PASS** |
| **7** | Emeklilik politikası gerçekten tüm silme/arşivleme yollarını kontrol ediyor mu? | **EVET.** `LegacyDatabaseRetirementPolicy.evaluate()` 7 kriteri denetler; 14 gün dolmadan silme ve arşivlemeyi reddeder. İşlem yapıldığında ise `File.rename` ile `.archived_` uzantısı verilir, `delete()` asla çağrılmaz. | **PASS** |
| **8** | Kullanılmayan bir sınıf veya yalnızca testte çalışan bir mekanizma mı? | **HAYIR.** `core_next_bootstrap_coordinator.dart` doğrudan `app_bootstrap.dart` ve Riverpod bağımlılık ağacına bağlanmıştır. | **PASS** |

---

## 3. CATCH-UP KAPSAM MATRİSİ (7 SÜTUNLU KAPSAMLI DENETİM)

| 1. Kaynak Tablo | 2. Hedef Tablo | 3. İlk Aktarım Yöntemi | 4. Aktarım Sırasında Değişiklik Yakalama (Catch-Up) | 5. Mükerrer Kayıt Önleme | 6. Veri Doğrulama Yöntemi | 7. Eksik veya Desteklenmeyen Davranış |
|---|---|---|---|---|---|---|
| `products` | `products` | `MigrationBridgeEngine.runMigration()` (Fiyat TL->Kuruş) | `updated_at` / `created_at >= cutoff` delta taraması, fiyat ve stok güncellemesi | `ON CONFLICT(id) DO UPDATE` | `SUM(stock_quantity)` ve `COUNT(*)` mutabakatı | Varyant bazlı alt barkodlar legacy'de metin alanında tutuluyorsa JSON ayrıştırma gerektirir. |
| `customers` | `customers` | `MigrationBridgeEngine` (Bakiye TL->Kuruş) | `updated_at` / `created_at >= cutoff` delta taraması, bakiye ve iletişim güncellemesi | `ON CONFLICT(id) DO UPDATE` | `SUM(balance_cents)` kuruş mutabakatı ve cari bazlı fark kontrolü | Legacy'de bakiye ve defter arasında geçmişten gelen 1-2 kuruşluk yuvarlama sapmaları toleransla yönetilir. |
| `sales` | `sales` | Toplu aktarım (`ConflictAlgorithm.ignore`) | `created_at >= cutoff` ile ara dönemde eklenen canlı satışların yakalanması | `INSERT OR IGNORE` & `idempotency_key` | Satış adet sayısı ve `SUM(total_cents)` birebir kuruş mutabakatı | İptal edilen satışların legacy'de `status='CANCELLED'` olarak güncellenmesi delta ile Core Next'e yansıtılır. |
| `sale_items` | `sale_items` | Toplu aktarım (`ConflictAlgorithm.ignore`) | Yakalanan `caughtUpSaleIds` listesine bağlı kalemlerin çekilip eklenmesi | `INSERT OR IGNORE` (Bileşik PK / id) | Kalem tutar toplamı (`total_cents`) ile satış toplamı kontrolü | İskonto oranları legacy'de satır bazında ayrı sütun yoksa subtotal farkından türetilir. |
| `sale_payments` | `sale_payments` | Satış payment_method'undan sentezleme | Canlı satış ödeme tipine göre `pay_{saleId}` parçası oluşturma | `INSERT OR IGNORE` | `SUM(sale_payments.amount_cents) == SUM(sales.total_cents)` | Karma (split) ödemelerde nakit+pos parçaları ayrıştırılarak kaydedilir. |
| `financial_transactions` | `ledger_entries` | Borç/Alacak kuruş dönüşümü | `created_at >= cutoff` tahsilat, ödeme ve vadeli borç hareketleri | `INSERT OR IGNORE` | Müşteri cari bakiyesi ile defter hareket toplamı eşliği | `reference_id` boş olan eski manuel kasa hareketleri bağımsız defter kaydı olarak saklanır. |
| `orders` & `order_items` | `orders` & `order_items` | Toplu aktarım | `created_at >= cutoff` masa/sipariş hareketleri | `INSERT OR IGNORE` | Sipariş başlık ve kalem adet kontrolü | Tamamlanıp faturaya dönüşen siparişler satışa bağlandığında mükerrer defter kaydı üretilmez. |
| `cash_transactions` | `cash_transactions` / `ledger_entries` | Kasa giriş/çıkış dönüşümü | `created_at >= cutoff` gün içi kasa hareketleri | `INSERT OR IGNORE` | Gün sonu kasa toplamı mutabakatı | Kasa devir kayıtları yeni güne aktarılırken tarih tutarlılığı korunur. |
| `sync_events` | `outbox_events` | Bekleyen outbox kayıtlarının aktarımı | Göç esnasında oluşan outbox kuyruklarının taşınması | `id` bazlı tekilleştirme | Bekleyen senkronizasyon olay sayısı kontrolü | Bulut ile henüz el sıkışmamış olaylar silinmez, outbox'ta hazır tutulur. |
| `printer_devices` & `printer_routes` | Yerel Cihaz Ayarları (`app_settings` / SharedPreferences) | SQLite yerine yerel cihaz donanım profili olarak korunur | Bu tablolar yerel donanıma özgüdür; veritabanı göçünden etkilenmez | Donanım kimliği (MAC/IP/USB) ile eşleşme | Yazdırma kuyruğu ve test çıktısı teşhisi | Veritabanı cutover yapılsa dahi donanım profilleri yerel kalıcı hafızada korunur. |

---

## 4. CANLI İŞLEM VE SON UZLAŞTIRMA GÜVENLİĞİ

Uygulanan mimari, SQLite dosyaları arasında hayali bir "çift yazma" (dual write) varsayımına dayanmaz. İki dosya arasında dağıtık iki aşamalı commit (2PC) yoktur.

**Uygulanan Çözüm:**
1. **Kaynak Devamlılığı:** İlk aktarım esnasında canlı satışlar kesintiye uğramaz; eski SQLite veritabanı aktif yazmaya devam eder.
2. **Kritik Eşik Zaman Damgası (`cutoffTimestamp`):** İlk aktarım başladığı andaki milisaniye zaman damgası kaydedilir.
3. **Delta Catch-Up:** İlk aktarım bittiğinde, `cutoffTimestamp` sonrasında kaynağa yazılan tüm yeni/güncellenen kayıtlar (`products`, `customers`, `sales`, `sale_items`, `financial_transactions`) sorgulanır ve hedef Core Next veritabanına atomik bir transaction ile uygulanır.
4. **Tutarlı Snapshot Mutabakatı:** Catch-up tamamlandıktan sonra, kaynak ve hedefin son durumları karşılaştırılır:
   - Satış adedi ve toplam kuruş tutarı
   - Stok miktarları toplamı ve ürün bazlı stoklar
   - Cari bakiye toplamları
   - PRAGMA integrity_check ve foreign_key_check
5. **Fail-Closed Blokaj:** Eğer 1 kuruş veya 0.001 birim stok sapması varsa, `cutover_reconciliation_status = 'blocked'` yazılır ve `DatabaseRoutingResolver` yeni veritabanını seçmeyi reddeder.

---

## 5. STOK FARKI HAKKINDAKİ ÖNEMLİ DÜZELTME (5.179.601 vs 5.179.604)

Önceki raporlarda geçen **3 birimlik stok farkı** hakkında adli ve matematiksel ayrım kesinleştirilmiştir:

### 5.1. Test Ortamında Doğrulanan Fark
- `test/core_next/stage10_12_25_forensic_export_import_rehearsal_test.dart` dosyasında prova amaçlı 3 adet test satışı (1 nakit, 1 kart, 1 açık hesap) çalıştırılmış ve test veritabanında stok `5.179.604`'ten `5.179.601`'e düşmüştür.
- Bu matematiksel ispat, test ortamındaki 3 birimlik değişimi doğrulamaktadır.

### 5.2. Gerçek Canlı Veritabanındaki Durum
- Gerçek canlı işletmelerde (Nutopia, Serenut, Erkul Çeyiz) stok miktarı gün içinde perakende satışlarla dinamik olarak değişmektedir (ör. 16 Ekim yedeğinde 5.179.525,85 iken 19 Ekim yedeğinde 5.178.999,45 birimdir).
- Dolayısıyla, canlı veritabanındaki stok azalmaları bir hata, veri kaybı veya adaptör açığı **değildir**; gerçek müşterilere yapılan fiili ürün satışlarıdır.

### 5.3. Kök Neden Kararı
- **Canlı fark bir hata olarak kabul edilemez ve yapay biçimde "düzeltilemez".**
- Geçmişte görülen hiçbir canlı veri farkı "testteki 3 satışla çözüldü" denilerek kapatılmamıştır. Gerçek canlı veriler üzerinde test satışı yapılmamış, işletme verilerine dokunulmamıştır.

---

## 6. GERÇEK ENTEGRASYON TESTLERİ VE SONUÇLARI

Aşağıdaki Flutter test paketleri terminal üzerinden çalıştırılmış ve %100 başarıyla tamamlanmıştır:

### Test Komutu ve Çıktıları:

1. **`stage10_12_43_automatic_lossless_migration_test.dart`**:
   - `coreNextSalesEngineEnabledProvider = false` ve `databaseRoutingHook = null` korundu.
   - `autonomousMode = true` ile diyalog sormadan otonom geçiş doğrulandı.
   - Canlı işlem sırasında eklenen yeni satışlar catch-up ile yakalandı.
   - 14 gün dolmadan eski veritabanının emekliliği engellendi; 14 gün sonra `.archived_` olarak arşivlendi.
   - **Sonuç:** `00:00 +6: All tests passed!`

2. **`stage10_12_44_live_safe_export_import_test.dart`**:
   - Güvenli dışa aktarma, içe aktarma ve PilotCutoverGate kilitleri denetlendi.
   - 19 Ekim yedeği ile canlı aktif veritabanı ayrımı kanıtlandı.
   - Erkul Çeyiz `manual_debt` ve `collection` kayıtları doğrulandı.
   - **Sonuç:** `00:17 +6: All tests passed!`

3. **`stage10_12_45_automatic_cutover_integration_test.dart`**:
   - `AppBootstrap` ve `CoreNextBootstrapCoordinator` catch-up runner ile uçtan uca çalıştırıldı.
   - Ürün fiyat/stok güncellemeleri, cari bakiye, vadeli defter ve ödeme parçaları eksiksiz aktarıldı.
   - Yarım kalan veya tekrarlanan catch-up işlemlerinde sıfır veri kaybı ve sıfır mükerrer kayıt doğrulandı.
   - Bilinçli mutabakat sapması senaryosunda `cutover_reconciliation_status = 'blocked'` üretildiği ve `DatabaseRoutingResolver`'ın güvenle `legacyFallback` seçtiği kanıtlandı.
   - 14 gün dolmadan silme engellendi; süre dolduğunda dosya silinmeyip `.archived_` yapıldı.
   - **Sonuç:** `00:07 +6: All tests passed!`

---

## 7. BİTİŞ KRİTERLERİ KONTROL LİSTESİ

| # | Bitiş Kriteri Sorusu | Somut Kanıt ve Cevap | Durum |
|---|---|---|---|
| **1** | Otomatik migration gerçek uygulama açılışından tetikleniyor mu? | **EVET.** `lib/infrastructure/bootstrap/app_bootstrap.dart:L341-364` içerisinde `AppBootstrap.runStartupDiagnostics` açılışında `CoreNextBootstrapCoordinator.coordinate(autonomousMode: true)` doğrudan çağrılmaktadır. | **TAMAMLANDI** |
| **2** | Bütün önemli veri türlerinin değişiklikleri aktarım sırasında yakalanıyor mu? | **EVET.** `LiveSafeCatchUpReconciliationCoordinator` motoru ürün fiyat/stok, cari bakiye, satış, satış kalemi, parçalı ödeme ve `financial_transactions` defter hareketlerini eksiksiz yakalamaktadır. | **TAMAMLANDI** |
| **3** | Kesinti ve tekrar çalıştırma durumlarında veri kaybı ve mükerrer kayıt önleniyor mu? | **EVET.** `ON CONFLICT(id) DO UPDATE` ve `INSERT OR IGNORE` ile `stage10_12_45_automatic_cutover_integration_test.dart` Grup 4 altında mükerrer kayıt oluşmadığı testle ispatlanmıştır. | **TAMAMLANDI** |
| **4** | Kaynak ve hedefin eşdeğerliği doğrulanmadan cutover engelleniyor mu? | **EVET.** `performCatchUpAndReconcile` başarısız olduğunda `cutover_reconciliation_status = 'blocked'` kaydedilir ve `DatabaseRoutingResolver` anında `legacyFallback` hedefine döner. | **TAMAMLANDI** |
| **5** | Eski veritabanına bağımlı müşteriler mevcut sürümlerinde çalışmaya devam edebiliyor mu? | **EVET.** `coreNextSalesEngineEnabledProvider = false` ve `DatabaseManager.databaseRoutingHook = null` korunarak hiçbir canlı işlem kesintiye uğratılmamaktadır. | **TAMAMLANDI** |
| **6** | Eski veritabanı, tüm emeklilik koşulları sağlanmadan korunuyor mu? | **EVET.** `LegacyDatabaseRetirementPolicy` 14 gün kusursuz çalışma ve sıfır senkronizasyon hatası olmadan arşivlemeyi reddeder; onaylandığında ise dosyayı ASLA silmez, `.archived_` olarak saklar. | **TAMAMLANDI** |

---

## 8. NİHAİ KARAR VE SONUÇ

**Aşama Kararı: `BLOCKED` (Canlı Cutover Açılması Engellendi)**

Otomatik geçiş mimarisi gerçek uygulama yaşam döngüsüne entegre edilmiş, tüm veri türlerini kapsayan canlı catch-up motoru kurulmuş, fail-closed güvenlik kapıları ve emeklilik korumaları doğrulanmıştır. 

Ancak değişmez iş kuralları gereğince:
1. `coreNextSalesEngineEnabledProvider = false` olarak tutulmaya devam etmektedir.
2. `DatabaseManager.databaseRoutingHook = null` olarak korunmaktadır.
3. Canlı mağazalar gün içi ticari faaliyetlerini sürdürürken kontrolsüz bir cutover yapılmamıştır.
4. Nihai canlı geçiş, ancak mağazaların kapalı olduğu sessiz bir zaman diliminde (quiet period) ve tüm finansal mutabakat tam onay aldığında kontrollü olarak açılacaktır.
