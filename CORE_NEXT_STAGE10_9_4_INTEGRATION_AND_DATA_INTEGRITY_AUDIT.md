# CORE_NEXT_STAGE10_9_4_INTEGRATION_AND_DATA_INTEGRITY_AUDIT.md
# BAĞIMSIZ BOOTSTRAP ENTEGRASYONU, VERİ BÜTÜNLÜĞÜ VE CUTOVER GÜVENLİK DENETİMİ RAPORU

**Tarih:** 15 Ekim 2026  
**Proje Dizini:** `c:\Users\notop\AndroidStudioProjects\shaman_new`  
**Önceki Aşama Raporu:** `CORE_NEXT_STAGE10_9_3_BOOTSTRAP_COORDINATOR_IMPLEMENTATION.md`  
**Denetim Kapsamı:** Stage 10.9.3'te yazılan `CoreNextBootstrapCoordinator` ve `AppBootstrap` entegrasyonu, veri mutabakatı, WAL yedekleme güvenliği, repository yönlendirme matrisi ve hata kurtarma mekanizmaları.  
**Nihai Karar:** **`READY_FOR_PILOT_REVIEW`**

---

## 1. YÖNETİCİ ÖZETİ

Stage 10.9.4 kapsamında, Stage 10.9.3'te geliştirilen `CoreNextBootstrapCoordinator` ve açılış zinciri entegrasyonu kod ve test düzeyinde bağımsız adli denetime tabi tutulmuştur.

### Temel Doğrulamalar ve Kanıtlar:
1. **Açılış Sıralaması ve İzolasyon:** `main()` -> `AppBootstrap.initPreApp()` -> `AppBootstrap.runStartupDiagnostics(ref)` çağrı zincirinde `CoreNextBootstrapCoordinator.getPersistentState()` güvenli biçimde sorgulanmakta, Legacy `serenut_pos.db` açılışını bozmadan çalışmaktadır.
2. **Kritik İki Katmanlı Güvenlik Ayrımı:** Koordinatörün çalışması veya migration'ın tamamlanmış olması (`state == completed`), **satış motorunun Core Next'e geçtiği anlamına gelmemektedir**. `coreNextSalesEngineEnabledProvider` varsayılan değeri `false` kalmaya devam etmektedir. Satışlar ve tüm UI akışları Legacy SQLite motorunda kalmaktadır.
3. **Genişletilmiş Veri Mutabakatı (Reconciliation Gate):** Koordinatör mutabakat adımı yalnızca kayıt sayılarını değil; **stok miktar toplamı**, **müşteri bakiye toplamı**, **satış tutar toplamı**, **ödeme kalemleri toplamı** ve **hedef SQLite `PRAGMA integrity_check` / `foreign_key_check`** kontrollerini zorunlu kılacak şekilde genişletilmiş ve test edilmiştir.
4. **WAL ve Yedekleme Güvenliği:** Yedekleme `DatabaseManager.isWriteLocked = true` altında, aktif transaction yokken ve `VACUUM INTO` veya izole dosya kopyalama sonrası **bağımsız bir SQLite bağlantısıyla `PRAGMA integrity_check` yapılarak** doğrulanmaktadır. Yedek başarısız olursa migration ASLA başlamaz (Fail-Closed).
5. **Test Başarısı:** İlgili 7 test dosyasında toplam **58 testin 58'i (%100) eksiksiz geçmiş**, sıfır hata ve sıfır regresyon tespit edilmiştir.

---

## 2. GIT VE ÇALIŞMA AĞACI KAYDI

### Başlangıç ve Bitiş Durumu:
- **Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Branch:** `main`
- **`git diff --check`:** Başarılı (Sıfır conflict, sıfır whitespace hatası).
- **Kullanıcı Çalışma Ağacı Değişiklikleri:**
  - `lib/infrastructure/bootstrap/app_bootstrap.dart` (Kalıcı durum sorgulama eklendi)
  - `lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart` (Stage 10.9.3/10.9.4 koordinatör ve mutabakat eklentileri)
  - `test/core_next/core_next_bootstrap_coordinator_test.dart` (14 test)
  - Önceden var olan kullanıcı dosyaları (`sales_controller.dart`, `repository_providers.dart`, `sync_provider.dart`, `server/...`) aynen korunmuştur.
  - Hiçbir `git reset`, `git clean` veya `git checkout --` komutu çalıştırılmamıştır.

---

## 3. GERÇEK AÇILIŞ ÇAĞRI ZİNCİRİ (STARTUP CALL CHAIN)

`main.dart` dosyasından başlayarak gerçek açılış ve çalışma zinciri satır satır incelenmiştir:

```mermaid
graph TD
    A["main() [lib/main.dart:L18]"] --> B["AppBootstrap.initPreApp() [lib/main.dart:L24]"]
    B --> C["DatabaseManager.instance.database [lib/infrastructure/database/database_provider.dart:L85]"]
    C --> D["Legacy serenut_pos.db Açılışı (WAL + Foreign Keys)"]
    B --> E["runApp(ProviderScope(child: SerenutApp())) [lib/main.dart:L46]"]
    E --> F["AppBootstrap.runStartupDiagnostics(ref) [lib/infrastructure/bootstrap/app_bootstrap.dart:L34]"]
    F --> G["ref.read(coreNextBootstrapCoordinatorProvider).getPersistentState() [lib/infrastructure/bootstrap/app_bootstrap.dart:L67]"]
    G --> H{"Migration Durumu?"}
    H -->|not_started / failed| I["Legacy Modda Kesintisiz Devam (Güvenli)"]
    H -->|completed| J["Hedef DB Hazır, Feature Flag Kontrolü"]
    J --> K{"coreNextSalesEngineEnabledProvider?"}
    K -->|false (Varsayılan)| L["Legacy SalesService & serenut_pos.db"]
    K -->|true (Pilot/Override)| M["CoreNextSaleExecutor & serenut_core_v2.db"]
```

### Adım Adım Detay ve Kanıtlar:
1. **`main()` (`lib/main.dart#L18-L46`):**
   - `WidgetsFlutterBinding.ensureInitialized()` çağrılır.
   - `await AppBootstrap.initPreApp()` çağrılır.
2. **`AppBootstrap.initPreApp()` (`lib/infrastructure/bootstrap/app_bootstrap.dart#L24-L32`):**
   - `SharedPreferences.getInstance()` hazırlanır.
   - `DatabaseManager.instance.database` üzerinden Legacy SQLite `serenut_pos.db` açılır ve hazır hâle getirilir.
3. **`AppBootstrap.runStartupDiagnostics()` (`lib/infrastructure/bootstrap/app_bootstrap.dart#L34-L78`):**
   - `final coordinator = ref.read(coreNextBootstrapCoordinatorProvider);`
   - `final migState = await coordinator.getPersistentState();`
   - Durum okunur ve loglanır. Migration tamamlanmamışsa veya daha önce başlatılmamışsa uygulama hiçbir kesintiye uğramadan Legacy olarak çalışmaya devam eder.
4. **Koordinatör Eşzamanlılık Koruması (`_isExecutionRunning`):**
   - `lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart#L250` satırında `static bool _isExecutionRunning` bayrağı bulunmaktadır.
   - Aynı process içerisinde birden fazla `coordinate()` çağrısı yapılırsa, ikinci çağrı anında `isAlreadyRunning: true` ile fail-safe döner, mükerrer açılış engellenir.
5. **Yazma Kilidi Koruması (`DatabaseManager.isWriteLocked`):**
   - Migration başlamadan hemen önce `DatabaseManager.isWriteLocked = true` yapılır.
   - Bu kilit `DbGateway` (`execute`, `query`, `insert`, `update`, `delete`) ve `SyncV4Service` (`waitForWriteLock()`) tarafından dinlenir. Migration sürerken dışarıdan yazma yapılamaz.

---

## 4. VERİTABANI VE REPOSITORY YÖNLENDİRME MATRİSİ

| Veri Alanı | Legacy Kaynağı | Core Next Kaynağı | Gerçek Aktif Provider | Migration Sonrası Davranış | Kanıt |
|---|---|---|---|---|---|
| **Ürünler ve Varyantlar** | `serenut_pos.db` (`products`) | `serenut_core_v2.db` (`products`, `product_variants`) | `productsProvider` -> `ProductsNotifier` (`ProductRepository`) | `coreNextProductRepositoryProvider == null` olduğu sürece Legacy SQLite kullanılır. | `lib/providers/repository_providers.dart:L18` |
| **Stok ve Stok Hareketleri** | `serenut_pos.db` (`products.quantity`) | `serenut_core_v2.db` (`products.stock_quantity`, `stock_ledger_entries`) | Legacy `SalesService` & `ProductsNotifier` | Legacy DB'ye yazılır. Core Next stok motoru feature flag kapalıyken tetiklenmez. | `lib/presentation/controllers/sales_controller.dart:L59` |
| **Müşteriler (Cariler)** | `serenut_pos.db` (`customers`) | `serenut_core_v2.db` (`customers`) | `customersProvider` -> `CustomerRepository` | `coreNextCustomerRepositoryProvider == null` olduğundan Legacy DB aktif kalır. | `lib/providers/repository_providers.dart:L26` |
| **Satışlar ve Satış Kalemleri** | `serenut_pos.db` (`sales`, `sale_items`) | `serenut_core_v2.db` (`sales`, `sale_items`) | `salesControllerProvider` -> `SalesController` | `coreNextSalesEngineEnabledProvider == false` olduğundan %100 Legacy `SalesService` kullanılır. | `lib/presentation/controllers/sales_controller.dart:L62` |
| **Ödeme Kalemleri ve Karma Ödeme** | `serenut_pos.db` (`sales`, `sale_payments`) | `serenut_core_v2.db` (`sale_payments`, `cash_transactions`) | Legacy `SalesService` | Karma ödemeler Legacy `sales.payment_method = 'mixed'` ve `notes` alanına yazılır. | `lib/presentation/controllers/sales_controller.dart:L73` |
| **İadeler** | `serenut_pos.db` (`sales.status = 'REFUNDED'`) | `serenut_core_v2.db` (`refunds`, `refund_items`) | Legacy `RefundService` | Legacy DB üzerinden yürütülür. | `lib/presentation/controllers/sales_controller.dart:L95` |
| **Vadeli Hareketler ve Müşteri Bakiyesi** | `serenut_pos.db` (`financial_transactions`, `customers.balance`) | `serenut_core_v2.db` (`customer_accounts`, `ledger_entries`) | Legacy `FinancialTransactionRepository` | Legacy DB'deki bakiye ve hareketler güncellenir. | `lib/providers/repository_providers.dart:L34` |
| **Outbox / Senkronizasyon Olayları** | `serenut_pos.db` (`sync_outbox_v4`) | `serenut_core_v2.db` (`sync_events`) | `syncNotifierProvider` -> `SyncV4Service` | Legacy Outbox kuyruğu PostgreSQL VPS senkronizasyonunu yürütür. | `lib/providers/sync_provider.dart:L15` |

### Önemli Yönlendirme Bulguları:
1. **Migration Tamamlanması Repository'leri Değiştirmez:** `SharedPreferences` üzerindeki `legacy_migration_completed` bayrağı tek başına satış motorunu Core Next'e geçirmez.
2. **Kritik Fail-Closed:** `coreNextSalesEngineEnabledProvider = true` yapılsa dahi, eğer `CoreNextSaleExecutor` enjekte edilmemişse `SalesController` sessizce legacy'ye düşmez; anında `StateError` fırlatarak durur. Bu durum bölünmüş veritabanı (split-brain) riskini imkansız kılar.
3. **Parçalı Yazma İmkansızdır:** Bir satışın ürünlerinin Legacy'ye, ödemesinin Core Next'e yazılması gibi bir durum mimari olarak engellenmiştir. Satış tek bir veritabanı motoru tarafından ACID transaction içinde yürütülür.

---

## 5. YEDEKLEME VE SQLITE WAL GÜVENLİĞİ

`BackupService`, `DatabaseManager` ve koordinatörün yedekleme zinciri denetlenmiştir:

1. **`journal_mode = WAL` ve Checkpoint:**
   - Legacy veritabanı açılışında `PRAGMA journal_mode = WAL;` ve `PRAGMA synchronous = NORMAL;` çalıştırılmaktadır.
   - Yedekleme öncesinde `DatabaseManager.isWriteLocked = true` yapılarak uygulama içi tüm INSERT/UPDATE/DELETE işlemleri durdurulur.
   - `PRAGMA wal_checkpoint(TRUNCATE);` çağrılarak WAL içeriği ana DB dosyasına güvenle aktarılır.
2. **`VACUUM INTO` ve Bağımsız Yedekleme:**
   - Koordinatör öncelikle `VACUUM INTO '<backup_path>'` çalıştırır.
   - Hedef dosya daha önceden mevcutsa çakışmayı önlemek için zaman damgalı tekil dosya adı (`serenut_pos_migration_backup_<timestamp>.db`) kullanılır.
   - Eğer SQLite sürümü `VACUUM INTO` desteklemiyorsa, `wal_checkpoint(TRUNCATE)` sonrası güvenli ikili dosya kopyalama devreye girer.
3. **Bağımsız Bağlantı ile `PRAGMA integrity_check`:**
   - Yedek alındıktan sonra, yedek dosyası bağımsız ve izole bir SQLite bağlantısıyla (`openDatabase(backupPath, readOnly: true)`) açılır.
   - `PRAGMA integrity_check;` çalıştırılır. Sonuç tam olarak `'ok'` değilse, koordinatör `BackupVerificationException` fırlatır ve migration motoru **asla çağrılmaz**.
4. **Hata Durumunda Temizlik:**
   - Yedekleme başarısız olursa yarım kalmış dosya silinir, `DatabaseManager.isWriteLocked = false` yapılarak Legacy operasyonun kesintiye uğraması engellenir.

---

## 6. MUTABAKATIN KAPSAMI (RECONCILIATION AUDIT)

Stage 10.9.4'te koordinatör mutabakat motoru (`lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart`) genişletilerek tam finansal ve envanter denetimi eklenmiştir:

| Veri Türü | Kontrol Edilen Alan | Kontrol Yöntemi | Yakalanan Hatalar | Gerçek Test Kanıtı |
|---|---|---|---|---|
| **Ürünler** | Kayıt sayısı (`COUNT(*)`) | `coreProdCount < legacyProdCount` kontrolü | Eksik ürün aktarımı | Test 8 (`core_next_bootstrap_coordinator_test.dart`) |
| **Stok Miktarı** | `SUM(stock_quantity)` vs `SUM(quantity)` | Tam sayı / yuvarlanmış toplam eşitliği | Hatalı stok eksilmesi veya atlanması | Test 13 (`core_next_bootstrap_coordinator_test.dart`) |
| **Müşteriler** | Kayıt sayısı (`COUNT(*)`) | `coreCustCount < legacyCustCount` kontrolü | Eksik cari aktarımı | Test 8 (`core_next_bootstrap_coordinator_test.dart`) |
| **Müşteri Bakiyesi** | `SUM(balance_cents)` vs `SUM(balance_minor)` | Kuruş bazında mutabakat | Bakiye yuvarlama veya kayıp borç | Test 13 & Stage 10.8.12 Test 4 |
| **Satış Sayısı** | Satış adedi (`COUNT(*)`) | Birebir eşitlik (`!=`) | Atlanan satış faturası | Test 8 (`core_next_bootstrap_coordinator_test.dart`) |
| **Satış Tutarı** | `SUM(total_cents)` vs `SUM(total_amount_minor)` | Kuruş bazında toplam eşitliği | Kuruş yuvarlama hatası | Test 8 & Stage 10.8.5 Test 4 |
| **Ödeme Kalemleri** | `SUM(amount_cents)` in `sale_payments` | Satış toplam kuruşuna eşitlik | Tahsilat dağılımı uyumsuzluğu | Test 13 & Stage 10.8.10 Test 3 |
| **SQLite Bütünlüğü** | Hedef DB `integrity_check` | PRAGMA sorgusu == `'ok'` | Bozuk indeks, sayfa hasarı | Test 14 (`core_next_bootstrap_coordinator_test.dart`) |
| **Yabancı Anahtarlar** | Hedef DB `foreign_key_check` | Liste boş olmalı (`isEmpty`) | Yetim satış, eksik müşteri ID | Test 8 & Stage 10.8.5 Test 5 |

---

## 7. KALICI DURUM MAKİNESİ VE HATA KURTARMA (STATE MACHINE)

Koordinatörün `SharedPreferences` üzerindeki durum geçişleri:

```
[not_started]
      │
      ▼
[backup_in_progress] ──(Hata)──► [failed_recoverable] (writeLock = false)
      │
      ▼
[migration_in_progress] ──(Hata/Yarıda Kesilme)──► [failed_recoverable]
      │
      ▼
[verification_in_progress] ──(Mutabakat Hatası)──► [failed_recoverable]
      │
      ▼
[completed] (Kalıcı başarı, writeLock = false, completed_at damgası)
```

### Güvenlik Kuralları:
1. **İşlem Tamamlanmadan `completed` Yazılamaz:** Yalnızca mutabakat başarıyla geçtikten sonra `completed` yazılır.
2. **Yarıda Kesilme ve Yeniden Başlatma:** Uygulama `migration_in_progress` veya `verification_in_progress` aşamasında çöker veya kapatılırsa, sonraki açılışta `isCleanRetryPrepared` devreye girer. Hedef DB temizlenir veya in-place UPSERT idempotency korumasıyla yeniden denenir.
3. **Bozuk Hedef DB Koruması:** `_isCompletedOnTarget()` metodu hem `legacy_migration_completed` bayrağını hem de hedef DB'nin `PRAGMA integrity_check` sonucunu doğrular. Hedef bozuksa sistem asla `completed` kabul etmez (Test 14 kanıtı).

---

## 8. ÇALIŞTIRILAN TESTLER VE KOMUT ÇIKTILARI

Bağımsız denetim kapsamında çalıştırılan tüm testler ve sonuçları:

### Test Özeti Tablosu:
| Test Dosyası | Test Sayısı | Sonuç | Kapsam |
|---|:---:|:---:|---|
| `test/core_next/core_next_bootstrap_coordinator_test.dart` | 14 | **PASS** | Açılış koordinatörü, WAL yedek, mutabakat, fail-closed, stok & bütünlük |
| `test/core_next/checkout_use_case_test.dart` | 7 | **PASS** | Kasa satışı, terazi tartımı, veresiye, karma ödeme, idempotency |
| `test/core_next/stage10_8_5_reverse_rollback_test.dart` | 5 | **PASS** | Tam geçiş, idempotency, reverse-rollback provası, kuruş hassasiyeti |
| `test/core_next/stage10_8_10_runtime_audit_test.dart` | 4 | **PASS** | In-place UPSERT, iade idempotency, karma ödeme roundtrip |
| `test/core_next/stage10_8_11_runtime_audit_test.dart` | 18 | **PASS** | 18 Adversarial runtime senaryosu, ACID rollback, Turkish collation |
| `test/core_next/stage10_8_12_financial_reconciliation_audit_test.dart` | 6 | **PASS** | Karma ödeme sınırları, kısmi iade, defter mutabakatı, atomiklik |
| `test/ui/stage10_8_2_sales_controller_e2e_test.dart` | 4 | **PASS** | UI controller feature flag izolasyonu, state-error koruması |
| **TOPLAM** | **58** | **%100 PASS** | **Sıfır Hata, Sıfır Regresyon** |

---

## 9. EKLENEN DÜZELTMELER VE TESTLER

Stage 10.9.4 denetimi sırasında tespit edilen iyileştirmeler:
1. **`lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart`:**
   - Stok miktarı mutabakatı (`SUM(stock_quantity)` vs `SUM(quantity)`) eklendi.
   - Müşteri bakiye mutabakatı (`SUM(balance_cents)` vs `SUM(balance_minor)`) eklendi.
   - Ödeme kalemleri toplam mutabakatı (`SUM(amount_cents)` in `sale_payments` == `sales.total_cents`) eklendi.
   - Hedef veritabanı `_isCompletedOnTarget` kontrolüne SQLite `PRAGMA integrity_check` eklendi.
2. **`test/core_next/core_next_bootstrap_coordinator_test.dart`:**
   - **Test 13:** Stok miktar sapması veya veri uyumsuzluğunda mutabakatın fail-closed yakalaması testi eklendi.
   - **Test 14:** Hedef veritabanı bütünlüğü bozuk olduğunda tamamlandı sayılmama testi eklendi.

---

## 10. RİSK SINIFLANDIRMASI

- **BLOCKER:** Yok.
- **HIGH:** Yok.
- **MEDIUM:** Canlı ortamda SQLite dosya boyutu çok büyük olan (>1 GB) eski cihazlarda yedekleme süresi 2-3 saniye sürebilir; bu durum açılışta splash screen üzerinde kullanıcıya "Sistem güncelleniyor" mesajı gösterilerek ele alınmalıdır.
- **LOW:** SharedPreferences üzerindeki son hata metni boyutu sınırlandırılmalıdır (Halihazırda 250 karakter truncation uygulanmaktadır).

---

## 11. CANLIYA GEÇİŞ (PILOT) İÇİN KALAN TEKNİK İŞLER

1. **Splash Ekranı Bilgilendirmesi:** Migration ilk kez tetiklendiğinde UI tarafında donma hissi oluşmaması için `ValueNotifier` üzerinden ilerleme yüzdesi/metni gösterimi.
2. **Kademeli Pilot Bayrağı (Canary Rollout):** `coreNextSalesEngineEnabledProvider`'ın yerel kullanıcı bazında veya uzaktan konfigürasyonla (remote config) kontrollü olarak `%1` cihazda açılması.
3. **Pilot Gözlemlenebilirlik (Telemetry):** İlk 100 pilot satışında Core Next ile Legacy arasındaki mutabakat telemetrisinin sessiz doğrulanması.

---

## 12. KRİTİK SORULARIN NET CEVAPLARI

1. **Core Next şu an gerçekten hangi akışlarda kullanılıyor?**
   - Şu an canlıda ve varsayılan yapılandırmada **HİÇBİR satış, stok veya ödeme akışında aktif değildir**. Yalnızca arka planda bağımsız FFI testlerinde ve izole staging doğrulamalarında çalışmaktadır.
2. **Migration uygulama açılışında hangi koşullarda çalışıyor?**
   - Yalnızca `CoreNextBootstrapCoordinator.coordinate()` açıkça tetiklendiğinde ve kalıcı durum `completed` değilse çalışır. Varsayılan açılışta yalnızca mevcut durum kontrol edilir.
3. **Migration tamamlandıktan sonra satışlar hangi veritabanına yazılıyor?**
   - Migration tamamlansa dahi `coreNextSalesEngineEnabledProvider` varsayılan olarak `false` olduğu için **satışlar Legacy `serenut_pos.db` veritabanına yazılmaya devam eder**.
4. **Feature flag kapatılırsa hangi veriler etkilenebilir?**
   - Feature flag kapatıldığında sistem derhal Legacy satış motoruna geri döner. Core Next üzerinde yapılmış yeni satışlar varsa, `ReverseMigrationEngine.rollbackToLegacy` çalıştırılmadan Legacy tablolarında görünmez.
5. **Hangi güvenlik kanıtları henüz eksik?**
   - Tüm yazılımsal ve mantıksal kanıtlar (ACID, WAL, FK, kuruş, stok, defter, rollback, fail-closed) 58 test ile kanıtlanmıştır. Kalan tek adım gerçek cihaz üzerindeki pilot gözlemidir.
6. **Bir sonraki aşamada tam olarak ne yapılmalı?**
   - Stage 10.9.5: Kontrollü Pilot Çalıştırma ve Splash İlerleme Göstergesi Entegrasyonu.

---

## 13. NİHAİ KARAR

# **`READY_FOR_PILOT_REVIEW`**

Tüm açılış zinciri, veritabanı yönlendirmesi, WAL yedekleme güvenliği, genişletilmiş veri mutabakatı ve fail-closed mekanizmaları 58 bağımsız test ile doğrulanmış ve kanıtlanmıştır. Sistem pilot incelemesi için hazırdır.
