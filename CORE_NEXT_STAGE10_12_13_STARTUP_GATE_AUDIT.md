# SERENUT OS — STAGE 10.12.13
# MIGRATION PATCH BAĞIMSIZ DENETİMİ VE STARTUP ENTEGRASYONU ÖNCESİ KAPI RAPORU

**Tarih:** 16 Ekim 2026  
**Git Commit / HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Branch: `main`)  
**Denetim Kapsamı:** `MigrationBridgeEngine` 21 Müşterisiz Nakit Satış Yaması Bağımsız İncelemesi, Test Kapsamının Gerçekliği ve Üretim Başlatma Zinciri (`AppBootstrap`) Entegrasyon Öncesi Güvenlik Kapısı  
**Güvenlik Prensibi:** Canlı Nutopia SQLite (`%APPDATA%/serenut_pos.db`) ve Erkul Çeyiz Bulut PostgreSQL veritabanlarına sıfır müdahale. `DatabaseRoutingResolver` üretim açılışına bağlanmamış, feature flag (`coreNextSalesEngineEnabledProvider`) kapalı tutulmuştur.

---

## 1. YÖNETİCİ ÖZETİ VE BEŞ AYRI NİHAİ KARAR

| # | Karar Alanı | Karar | Gerekçe Özeti |
|---|---|---|---|
| **A** | **21 Müşterisiz Nakit Satış Mapping'i Doğru mu?** | **✅ PASS** | Kaynak 21 hareketin tamamı `type = 'sale'` ve `sales` tablosunda `status = 'completed'`, `payment_method = 'cash'` durumundadır. Core Next mimarisinde peşin tezgâh satışları `cash_transactions` (`type = 'INFLOW'`, `category = 'SALE'`) tablosuna yazıldığından eşleme kuruşu kuruşuna (12.197,00 TL / 1.219.700 kuruş) ve kavramsal olarak %100 doğrudur. |
| **B** | **Gerçek İşletme Verisinin Tamamı Bağımsız Biçimde Doğrulanmış mı?** | **✅ PASS** | Testler sentetik fixture değil, doğrudan 59.764.736 baytlık `raw_nutopia_v60.db` yedeğinin izole kopyası üzerinde çalıştırılmıştır. 37.682 ürün, 584 müşteri (-134.500,68 TL bakiye), 52 satış (31.282,25 TL), 120 satış kalemi, 792 sipariş (1.226.806,30 TL), 9 taksit ve 1.403 cari defter hareketi bağımsız SQL sorgularıyla teyit edilmiştir. |
| **C** | **İdempotency ve Hata Sonrası Kurtarma Kanıtlandı mı?** | **✅ PASS** | İkinci çalıştırmada (replay) `cash_transactions` 21 kayıt ve 1.219.700 kuruşta sabit kalmış, mükerrerlik 0 olmuştur. Hata enjeksiyonunda SQLite transaction mekanizmasının tüm tabloları atomik olarak `ROLLBACK` ettiği ve 0 artık kayıt bıraktığı kanıtlanmıştır. |
| **D** | **Migration'ın Üretim Açılışına Bağlanması İçin Hangi Engeller Kaldı?** | **⚠️ 4 ENGEL TESPİT EDİLDİ (BLOKELİ)** | 1) `assertSafeRollback()` fonksiyonu uygulanmış ancak çalışma zamanı geri dönüş zincirine henüz bağlanmamıştır. 2) `coreNextMigrationRunnerProvider` üretimde `null` dönmektedir. 3) 37.682 ürünlük göç (~7-10 sn) için UI bildirim/ilerleme göstergesi eklenmelidir. 4) Çok kiracılı pilot filtresi başlatma zincirine eklenmelidir. |
| **E** | **Sonraki Aşamada Yalnızca İzole Test Açılış Akışına Geçmek Güvenli mi?** | **✅ GÜVENLİ (PASS)** | Canlı `%APPDATA%/serenut_pos.db` dosyasına dokunmadan, geçici bir kum havuzunda (`%TEMP%`) `AppBootstrap` açılış akışının simüle edilmesi teknik olarak güvenlidir ve tavsiye edilir. |

---

## 2. GIT VE PATCH DENETİMİ

### Başlangıç Komut Çıktıları
- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Aktif Branch:** `main`
- **Diff Kontrolü (`git diff --check`):** 0 hata / 0 çakışma (Temiz).
- **Mevcut Değişiklik Durumu:** Önceki aşamaların hiçbir değişikliği silinmemiş veya geri alınmamıştır.

### İncelenen Dosyalar ve Gerçek Durum
1. [core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart):
   - Satır 43: `MigrationReport` sınıfına `cashTransactionsMigrated` alanı eklendi (Geriye uyumlu).
   - Satır 801-840: `customer_id` boş veya tanımsız olan hareketler için `rawType == 'sale'` ve `validSalesSet.contains(rawRefId)` doğrulaması eklendi. Uygun olanlar `cash_transactions` (`type = 'INFLOW'`, `category = 'SALE'`) tablosuna `ConflictAlgorithm.ignore` ile aktarılıyor.
   - Tanımsız veya geçersiz referanslı müşterisiz kayıtlar için `StateError` fırlatılarak atomik rollback güvenceye alındı.
2. [test/core_next/stage10_12_12_anonymous_cash_sales_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_12_anonymous_cash_sales_test.dart):
   - Gerçek `raw_nutopia_v60.db` kopyası üzerinde 4 test paketi: 1:1 aktarım, idempotency, hata enjeksiyonu ve ödeme tipleri regresyonu.
3. [test/core_next/stage10_10_9_full_reconciliation_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_10_9_full_reconciliation_test.dart):
   - 1.403 müşteri defter hareketi, stok, sipariş ve çok kiracılı izolasyon testleri %100 başarılı.
4. [lib/infrastructure/bootstrap/app_bootstrap.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/app_bootstrap.dart):
   - Satır 116-117: `DatabaseManager.instance` doğrudan çağrılıyor. Resolver'a yönlendirme **YOKTUR**.
   - Satır 316-332: `coreNextMigrationRunnerProvider` kontrol ediliyor; üretimde `null` olduğu için koordinatör pasiftir.
5. [lib/infrastructure/database/database_provider.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart):
   - Satır 293-296: Doğrudan `serenut_pos.db` (legacy SQLite, v60) açılmaktadır.
6. [core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart):
   - Triple-check, fail-closed fallback ve `assertSafeRollback` mantığı hazırdır ancak `lib/` üretim koduna henüz bağlanmamıştır.

---

## 3. 21 SATIŞ İÇİN SAVUNMACI DOĞRULAMA (DEFENSIVE VERIFICATION)

Kaynak `financial_transactions` kayıtlarının her biri bağımsız SQL sorgularıyla savunmacı kurallara göre denetlenmiştir:

```
========================================================================================
SAVUNMACI KONTROL KRİTERİ           BEKLENEN KOŞUL                  GERÇEKLEŞEN (21/21)
========================================================================================
1. Hareket Türü (type)              type == 'sale'                  %100 'sale' (21 adet)
2. Satış Referansı (reference_id)   sales.id ile 1:1 eşleşmeli      %100 Eşleşti (21 / 21)
3. Satış Durumu (status)            'completed' olmalı              %100 'completed' (21 / 21)
4. Ödeme Yöntemi (payment_method)   'cash' olmalı                   %100 'cash' (21 / 21)
5. Tutar Tutarlılığı                ft.amount == sales.total_amount Fark: 0,00 TL (%100 Denk)
6. İptal / İade Durumu              refunds tablosunda 0 kayıt      0 İade / 0 İptal
7. Önceden Aktarım (Idempotency)    Hedefte aynı ID varsa atla      ConflictAlgorithm.ignore
8. Tenant Kapsamı                   Nutopia veri tabanı izole       %100 Nutopia Dosyasında
========================================================================================
```

### Savunmacı Hata Yönetimi Kanıtı
Eğer kaynak veritabanında `type` değeri `sale` olmayan veya `reference_id` değeri `sales` tablosunda bulunmayan müşterisiz bir kayıt yer alırsa:
- Kod sessizce atlamamakta (`continue` yapmamakta),
- Açıkça `StateError('GEÇERSİZ MÜŞTERİSİZ SATIŞ REFERANSI...')` fırlatmakta,
- Tüm SQLite işlemi derhal atomik olarak `ROLLBACK` edilmektedir.

---

## 4. İDEMPOTENCY VE KİMLİK ÇAKIŞMASI DENETİMİ

Kaynak kimliğinin hedef kayda bağlanması ve mükerrerlik koruması:

1. **Birincil Anahtar Eşleştirmesi:**
   - Kaynak `financial_transactions.id` (Örn: `trans-17852550015567359331`), hedef `cash_transactions.id` alanına birebir birincil anahtar (PRIMARY KEY) olarak atanmaktadır.
   - Sentetik veya rastgele UUID üretilmemektedir. Bu sayede kaynak ile hedef arasında deterministik 1:1 izlenebilirlik sağlanmıştır.
2. **İkinci Çalıştırma (Replay) Kanıtı:**
   - [stage10_12_12_anonymous_cash_sales_test.dart:140-188](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_12_anonymous_cash_sales_test.dart#L140-L188) içinde test edilmiştir.
   - İlk çalıştırma: `cash_transactions` -> 21 kayıt, 1.219.700 kuruş.
   - İkinci çalıştırma (Aynı hedef üzerinde): `cash_transactions` -> 21 kayıt, 1.219.700 kuruş (Fark: 0 kayıt, 0 kuruş).
   - `ledger_entries` -> 1.403 kayıt (Sabit).
3. **Yarım Kalmış Migration Sonrası Yeniden Başlatma:**
   - Migration bir hata veya kesinti nedeniyle durduğunda hedef SQLite transaction'ı otomatik rollback edildiği için hedef DB temiz kalır. Yeniden başlatıldığında sıfırdan ve eksiksiz tamamlanır.

---

## 5. TEST KAPSAMININ GERÇEKLİĞİ VE ADLİ KANITLAR

| Soru | Yanıt | Kanıt / Dosya Referansı |
|---|---|---|
| **Gerçek kaynak yedeği testte kullanılıyor mu?** | **EVET.** Sentetik sahte veri değil, 59.764.736 baytlık `raw_nutopia_v60.db` yedeği `%TEMP%` kopyalanarak test edilmektedir. | [stage10_12_12_anonymous_cash_sales_test.dart:17, 45](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_12_anonymous_cash_sales_test.dart#L17) |
| **Migration'ın gerçek üretim fonksiyonu mu çalıştırılıyor?** | **EVET.** `MigrationBridgeEngine.migrateFromLegacy(fullScope: true)` üretim sınıfı ve metodu doğrudan çağrılmaktadır. | [stage10_12_12_anonymous_cash_sales_test.dart:52](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_12_anonymous_cash_sales_test.dart#L52) |
| **Varlık toplamları bağımsız olarak mı hesaplanıyor?** | **EVET.** Kaynak SQLite dosyasından `COUNT(*)`, `SUM(amount)` ve `SUM(balance)` sorguları test kodu içinde bağımsız olarak hesaplanıp doğrulanmaktadır. | [stage10_12_12_anonymous_cash_sales_test.dart:58-95](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_12_anonymous_cash_sales_test.dart#L58-L95) |
| **21 nakit satışın her biri ID bazında doğrulandı mı?** | **EVET.** Test döngüsünde 21 kaydın tamamının `trans-...` ID'si hedef `cash_transactions` tablosundaki PK ile tek tek eşleştirilmiştir. | [stage10_12_12_anonymous_cash_sales_test.dart:103-118](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_12_anonymous_cash_sales_test.dart#L103-L118) |

---

## 6. UYGULAMA AÇILIŞI VE ROLLBACK KAPISI ANALİZİ

Üretim kodu kaynakları üzerinden 7 kritik sorunun kesin analizi:

### 1. İlk veritabanını açan ilk çağrı hangisi?
- **Dosya:** [lib/infrastructure/bootstrap/app_bootstrap.dart:116-118](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/app_bootstrap.dart#L116-L118)
- `final dbManager = DatabaseManager.instance;`
- `final gateway = DbGatewayImpl(dbManager);`
- `final userRepository = SqliteUserRepository(gateway);`
- `userRepository` veya `settingsRepository` ilk sorgusunu çalıştırdığında `dbManager.getDatabase()` tetiklenir ve [database_provider.dart:296](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L296) üzerinden diskteki `serenut_pos.db` dosyasını açar.

### 2. Migration hangi noktada çalıştırılabilir?
- **Dosya:** [lib/infrastructure/bootstrap/app_bootstrap.dart:316-332](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/app_bootstrap.dart#L316-L332)
- `AppBootstrap.runStartupDiagnostics(WidgetRef ref)` metodu içinde, donanım ve bütünlük kontrollerinin hemen ardından `ref.read(coreNextBootstrapCoordinatorProvider)` üzerinden koordinatör çalıştırılabilir.

### 3. Migration tamamlanmadan yeni veritabanı kullanılabilir mi?
- **HAYIR.** [database_routing_resolver.dart:90-97](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart#L90-L97):
  ```dart
  if (!migrationStateCompleted) {
    return DatabaseRoutingResult(
      decision: RoutingDecision.legacyFallback,
      resolvedPath: legacyDbPath,
      reason: 'Migration durumu tamamlanmadı (inProgress veya notStarted).',
      isTargetSelected: false,
    );
  }
  ```
  Hedef DB'nin seçilebilmesi için migration durumunun kesin olarak `completed` olması şarttır; aksi takdirde fail-closed olarak legacy DB'ye düşer.

### 4. Tamamlanma işareti hangi noktada ve hangi veritabanına yazılıyor?
- **Hedef Veritabanında:** [migration_bridge_engine.dart:1310-1323](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart#L1310-L1323) içinde, hedef Core Next veritabanındaki `app_settings` tablosuna `key = 'legacy_migration_completed', value = 'true'` kaydı atomik transaction içinde yazılır.
- **Yerel Kalıcı Durumda:** `CoreNextBootstrapCoordinator` tarafından `SharedPreferences` içine `CoreNextMigrationState.completed` değeri ve yedek SHA-256 özeti kaydedilir.

### 5. Uygulama migration sırasında kapanırsa bir sonraki açılışta ne olur?
- Migration tek bir SQLite transaction'ı içinde (`targetDb.transaction`) çalıştığı için işletim sistemi çökmesi veya elektrik kesintisinde hedef SQLite dosyası otomatik olarak `ROLLBACK` olur.
- Bir sonraki açılışta `SharedPreferences` durumu `inProgress` veya `notStarted` olarak okunur.
- `DatabaseRoutingResolver`, tamamlanma bayrağı olmadığı için `RoutingDecision.legacyFallback` döner.
- Uygulama güvenle eski `serenut_pos.db` veritabanından açılır; kasiyer satış yapmaya devam eder, veri kaybı veya kilitlenme yaşanmaz.

### 6. Yeni veritabanında yeni satış oluşmuşsa eski veritabanına dönüş nasıl engelleniyor?
- [database_routing_resolver.dart:195-210](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart#L195-L210):
  `assertSafeRollback()` metodu hedef veritabanında göç sonrası yeni satış olup olmadığını sorgular:
  `SELECT COUNT(*) as c FROM sales WHERE created_at > ?`
  Eğer 1 adet bile yeni satış varsa `UnsafeRollbackException` fırlatarak sessiz geri dönüşü bloke eder.

### 7. `assertSafeRollback()` gerçek geri dönüş yolunda çağrılıyor mu?
- **DURUM: HENÜZ BAĞLI DEĞİL (NOT WIRED).**
- `assertSafeRollback()` metodu [database_routing_resolver.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart#L195) içinde eksiksiz kodlanmış ve [database_routing_test.dart:255](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/database_routing_test.dart#L255) ile test edilmiştir; ancak üretimdeki satış/hata yakalama veya acil geri dönüş controller'larına henüz doğrudan entegre edilmemiştir.

---

## 7. MIGRATION'IN ÜRETİM AÇILIŞINA BAĞLANMASI İÇİN KALAN ENGELLER

Teknik olarak veri bütünlüğü çözülmüş olsa da, canlı açılış zincirini Core Next'e geçirmeden önce aşılması gereken 4 somut mühendislik engeli:

1. **`assertSafeRollback` Çalışma Zamanı Entegrasyonu:**  
   Uygulamanın herhangi bir hata durumunda legacy veritabanına dönmeyi deneyeceği acil durum mekanizmalarına `assertSafeRollback()` çağrısı eklenmelidir.
2. **`coreNextMigrationRunnerProvider` Tanımı:**  
   [core_next_bootstrap_coordinator.dart:619](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart#L619) satırındaki provider varsayılan olarak `null` dönmektedir. Üretim başlatma koordinatörünün çalışması için bu provider'ın kontrollü biçimde bağlanması gerekmektedir.
3. **UI Açılış İlerleme Göstergesi (Splash / Diagnostics):**  
   37.682 ürünün göçü ~7-10 saniye sürmektedir. Bu esnada kullanıcının uygulamanın donduğunu sanıp zorla kapatmasını (kill process) önlemek için splash ekranında "Veritabanı optimize ediliyor..." şeklinde açık bir UI geri bildirimi sağlanmalıdır.
4. **Çok Kiracılı Pilot Filtresi:**  
   Yalnızca Nutopia pilot şirketi için göç tetiklenmeli; Erkul Çeyiz veya diğer lisanslar legacy modda kalmaya devam etmelidir.

---

## 8. NİHAİ KARAR TABLOSU VE SONUÇ

| Karar Maddesi | Durum | Gerekçe |
|---|---|---|
| **A. 21 Satış Mapping'i** | **PASS** | 21 adet, 12.197,00 TL, `cash_transactions` (`category = 'SALE'`). |
| **B. İşletme Verisi Doğrulaması** | **PASS** | Gerçek yedek üzerinde 1.424 finansal hareket ve tüm tablolar tam mutabık. |
| **C. İdempotency ve Rollback** | **PASS** | İkinci çalıştırmada 0 mükerrerlik, hata enjeksiyonunda atomik rollback. |
| **D. Üretim Açılışına Bağlanma** | **BLOCKED** | 4 adet entegrasyon engeli (rollback kilidi, provider, UI splash, pilot filtresi). |
| **E. İzole Test Açılış Akışına Geçiş** | **PASS (GÜVENLİ)** | Kum havuzunda (`%TEMP%`) uçtan uca başlatma provası yapmaya hazır. |

> [!NOTE]
> **Önerilen Sonraki Aşama:** Canlı veriye dokunmadan, geçici bir kum havuzunda (`%TEMP%`) `AppBootstrap` başlatma zincirini izole bir testle simüle etmek (Stage 10.12.14: İzole Başlatma Zinciri Entegrasyon Provası).
