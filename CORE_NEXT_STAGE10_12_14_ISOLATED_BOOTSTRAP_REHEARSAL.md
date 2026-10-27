# SERENUT OS — STAGE 10.12.14
# İZOLE APP BOOTSTRAP MIGRATION PROVASI VE ADLİ DENETİM RAPORU

**Tarih:** 16 Ekim 2026  
**Aşama:** STAGE 10.12.14 — İZOLE APP BOOTSTRAP MIGRATION PROVASI  
**Ortam:** Windows Masaüstü (SQLite FFI, Flutter/Dart Riverpod, İzole Sandbox `%TEMP%`)  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Branch: `main`)  
**Uygulanan Test Paketi:** `test/core_next/stage10_12_14_isolated_bootstrap_rehearsal_test.dart`  
**Test Sonucu:** **15/15 PASS (%100 Başarı)**  

---

## 1. BAŞLANGIÇ DURUMU VE VERİTABANI DOKUNULMAZLIĞI

Görev başlangıcında ve testlerin icrasından sonra kaynak yedek dosyalarının SHA-256 kriptografik özet değerleri doğrulanmıştır. Gerçek kullanıcı veritabanlarına (`%APPDATA%\serenut_pos.db`) veya bulut veritabanlarına hiçbir şekilde temas edilmemiş, tüm testler `%TEMP%` altında oluşturulan izole sandbox alanlarında yürütülmüştür.

| Dosya Yolu | Dosya Boyutu | SHA-256 Özeti (Başlangıç & Bitiş) | Bütünlük Durumu |
| :--- | :--- | :--- | :--- |
| `backups/raw_tenants_20261016/raw_nutopia_v60.db` | 59.764.736 bayt | `E70AA44A43C53F47F61C7B82A0A8C290D82E9F849AEC68486782BC2917430D24` | **100% Değişmedi (İntact)** |
| `backups/raw_tenants_20261016/raw_serenut_v44.db` | 6.516.736 bayt | `9145443F2C94A03DEA7478605DE974A1214B548523DA0406C18501918DA7D77D` | **100% Değişmedi (İntact)** |
| `backups/raw_tenants_20261016/raw_erkul_source.json` | 485.357 bayt | `B4912D916818377FA3D4A2D87C9BC33AA9B5FCD69300442DD6EEA6D8FA5EE389` | **100% Değişmedi (İntact)** |

---

## 2. 10 İZOLE AÇILIŞ VE MIGRATION SENARYOSU DENETİMİ

Gerçek [AppBootstrap](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/app_bootstrap.dart) (`runStartupDiagnostics`) ve [CoreNextBootstrapCoordinator](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart) kodları kullanılarak aşağıdaki 10 senaryo uçtan uca provadan geçirilmiştir:

| No | Senaryo Tanımı | Gerçekleşen Akış ve Çağrı Sırası | Çözülen DB Yolu | Alınan Sonuç | Karar |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **İlk Açılış (Migration henüz başlamamış)** | `runner = null`, `getPersistentState() == notStarted` -> koordinatör tetiklenmez, `AppBootstrap` başarılı döner. | `isolated_legacy.db` (Legacy Fallback) | `RoutingDecision.legacyFallback`, hedef seçilmedi. | **PASS** |
| **2** | **Migration Başarıyla Tamamlanıyor** | Runner enjekte edildi -> WAL checkpoint -> doğrulanmış yedekleme -> `MigrationBridgeEngine` aktarımı -> adli mutabakat -> `app_settings` bayrağı -> `state = completed`. | `isolated_core_v2.db` (Target Selected) | `RoutingDecision.targetSelected`, tüm mutabakat 0 sapmayla onaylandı. | **PASS** |
| **3** | **Migration Sırasında Kontrollü Hata (Fail-Closed)** | `migrationRunner` içinde Disk I/O simülasyonu -> SQLite transaction geri alındı (rollback) -> `state = failedRecoverable` -> Legacy yazma kilidi açıldı. | `isolated_legacy.db` (Legacy Fallback) | `RoutingDecision.legacyFallback`, legacy veri eksiksiz ve korunmuş. | **PASS** |
| **4** | **İşlem Devam Ederken Çökme / Kapanma** | State `migration_in_progress` iken işlem kesildi -> Hedef DB'de tamamlanma işareti yok -> Resolver fail-closed devreye girdi. | `isolated_legacy.db` (Legacy Fallback) | `RoutingDecision.legacyFallback`, sahte/yarım hedef DB reddedildi. | **PASS** |
| **5** | **Yeniden Açılış ve Yarım İşlemden Kurtarma** | Başlangıçta state `migration_in_progress` tespit edildi -> temiz kurtarma moduna geçildi (`failedRecoverable`) -> taze yedekle baştan tamamlandı -> `state = completed`. | `isolated_core_v2.db` (Target Selected) | `RoutingDecision.targetSelected`, yarım işlem kalıntısı bırakılmadı. | **PASS** |
| **6** | **Tamamlanma İşareti Yazılamıyor** | Veriler aktarılsa dahi hedef DB'de `legacy_migration_completed` bayrağı eksik/false ise `_isCompletedOnTarget` false döndü. | `isolated_legacy.db` (Legacy Fallback) | Hedef DB asla devreye sokulmadı, legacy korundu. | **PASS** |
| **7** | **Hedef Veritabanı Açılamıyor / Bozuk (<512 bayt)** | Hedef dosya 5 bayt çöp veri içeriyor -> SQLite header kontrolü (<512 bayt) tetiklendi -> `blockedFailClosed`. | `isolated_legacy.db` (Blocked Fail-Closed) | `RoutingDecision.blockedFailClosed`, bozuk DB'ye yazım engellendi. | **PASS** |
| **8** | **Kaynak (Legacy) DB Bütünlük Hatası** | Kaynak DB'de `PRAGMA integrity_check` hatası simüle edildi -> Koordinatör anında durdu -> `state = failedBlocked`, hata referansı üretildi (`ERR-4748AB`). | `isolated_legacy.db` (Blocked Fail-Closed) | `CoreNextMigrationState.failedBlocked`, bozuk kaynak taşınmadı. | **PASS** |
| **9** | **İkinci Kez Başlatma Girişimi (İdempotency)** | State `completed` iken `coordinate()` tekrar çağrıldı -> hedefteki bayrak doğrulandı -> işlem `isSkipped = true` ile atlandı. | `isolated_core_v2.db` (Target Selected) | 0 mükerrer kayıt, 0 gereksiz I/O. | **PASS** |
| **10**| **İki Eşzamanlı Açılış Girişimi (Concurrency Lock)** | Koordinasyon yürütülürken ikinci eşzamanlı `coordinate()` çağrıldı -> `_isExecutionRunning` bayrağı yakaladı -> `isAlreadyRunning: true`. | N/A (Kilit Devrede) | Yarış durumu (race condition) ve çift aktarım engellendi. | **PASS** |

---

## 3. MIGRATION STATE VE ATOMİKLİK KANITI

Farklı depolama alanları (`SharedPreferences` vs SQLite `app_settings`) arasındaki atomik uyumsuzluk riski mimari düzeyde analiz edilmiş ve şu kurallarla emniyete alınmıştır:

1. **Transaction İçinde Hedef Bayrak:** [migration_bridge_engine.dart:1356](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart#L1356) hedef Core Next veritabanı transaction'ının en son adımı olarak `app_settings` tablosuna `legacy_migration_completed = 'true'` kaydını yazar. Aktarım sırasında en ufak bir hata olursa SQLite transaction'ı tamamen geri alınır (ROLLBACK) ve bu bayrak asla diske yazılmaz.
2. **Koordinatör Çift Doğrulaması:** `CoreNextBootstrapCoordinator._isCompletedOnTarget()` metodu hem `PRAGMA integrity_check = 'ok'` sonucunu hem de `app_settings.legacy_migration_completed == 'true'` varlığını aynı anda şart koşar.
3. **SharedPreferences Kalıcılığı:** Ancak ve ancak adli mutabakat (ürün sayısı, kuruş toplamları, defter bakiyeleri) %100 doğrulandıktan sonra `SharedPreferences` üzerindeki `core_next_bootstrap_migration_state` değeri `'completed'` yapılır.
4. **Yarım Kalmış Durumun Asla Başarılı Sayılmaması:** Uygulama `migration_in_progress` veya `verification_in_progress` durumunda kapandığında, yeni açılışta koordinatör bunu `failedRecoverable` olarak işaretler ve temiz bir yeniden aktarım başlatır.

---

## 4. ROLLBACK GÜVENLİĞİ VE `assertSafeRollback()` ENTEGRASYONU

Stage 10.12.13'te açık kalan `DatabaseRoutingResolver.assertSafeRollback()` metodu, [CoreNextBootstrapCoordinator.rollbackToLegacy()](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart#L630) hata/geri dönüş yoluna `CoreNextRollbackGuard` arayüzü ile mimari olarak bağlanmış ve iki bağımsız durumda test edilmiştir:

### Durum A: Yeni hedefte henüz yeni satış veya finansal kayıt yok
- **Test:** Göç tamamlandıktan sonra yeni bir satış yazılmadan `rollbackToLegacy()` çağrıldı.
- **Sonuç:** `assertSafeRollback()` kontrolü geçti.
- **Kayıt Güvenliği:** Hedefteki göç verileri silinmedi (adli delil güvenliği korundu). `app_settings` tablosundaki `legacy_migration_completed` bayrağı `'rolled_back'` olarak güncellendi.
- **Yönlendirme:** `DatabaseRoutingResolver.resolve()` güvenli şekilde `RoutingDecision.legacyFallback` kararı üretti.

### Durum B: Yeni hedefte en az 1 yeni satış veya finansal kayıt oluşmuş
- **Test:** Kesme anından sonra hedef Core Next DB'sine yeni bir satış (`id: sale-new-cutover-999`, 50.00 TL) kaydedildi ve ardından `rollbackToLegacy()` çağrıldı.
- **Sonuç:** `assertSafeRollback()` metodu `UnsafeRollbackException` fırlattı:
  ```
  UnsafeRollbackException: Yeni veritabanında 1 adet yeni satış kaydedilmiş! 
  Sessiz geri dönüş yeni kayıtların kaybolmasına neden olur. İşlem durduruldu.
  ```
- **Kalıcı Durum:** Koordinatör `state = CoreNextMigrationState.failedBlocked` olarak kalıcı blokaj uyguladı.
- **Sessiz Geri Dönüş Engellendi:** Hedefteki hiçbir kayıt silinmedi; `app_settings` bayrağı `'rolled_back'` yapılmadı (`'true'` korundu). Yeni satışın kaybolması engellendi.

---

## 5. İŞLETME KAPSAMI VE VERİ İZOLASYONU

Nutopia yerel SQLite veritabanı ile sentetik Gamma (Erkul Çeyiz simülasyonu) veritabanları üzerinde izolasyon testi icra edilmiştir:

1. **Güvenilir Kaynak Doğrulaması:** `DatabaseRoutingResolver.resolve()` parametresi olarak verilen `requestedTenantId`, hedef Core Next veritabanındaki `app_settings.tenant_id` değeri ile karşılaştırılır.
2. **Çapraz Erişim Engeli:**
   - Nutopia istemcisi (`tenant-nutopia-01`), Gamma veritabanı dosyasını (`gamma_core.db`) açmaya çalıştığında resolver anında `RoutingDecision.blockedFailClosed` kararı vererek şu hatayı üretmiştir:
     ```
     Tenant ID uyuşmazlığı: İstenen "tenant-nutopia-01" != DB "tenant-gamma-02".
     ```
3. **Veri Kirliliği Kontrolü:** İki bağımsız veritabanı açıldığında, Nutopia tablolarında Gamma ürünlerinin (0 kayıt), Gamma tablolarında ise Nutopia ürünlerinin (0 kayıt) bulunmadığı kanıtlanmıştır.

---

## 6. 37.682 ÜRÜNLÜ GERÇEK NUTOPIA KOPYASI İLE PERFORMANS ÖLÇÜMÜ

Orijinal `raw_nutopia_v60.db` yedeğinin `%TEMP%` altında oluşturulan izole kopyası üzerinde gerçek migration ve adli mutabakat süresi ölçülmüştür:

```
====================================================
STAGE 10.12.14 GERÇEK PERFORMANS VE SÜRE RAPORU:
  Toplam Süre          : 18.201 ms (18,20 saniye)
  WAL Checkpoint & Yedek: 6.714 ms (6,71 saniye)
  Toplu Veri Göçü      : 11.487 ms (11,49 saniye)
  Adli Mutabakat       : Dahili coordinator adımında çalıştı (0 sapma)
  Aktarılan Toplam Ürün: 37.682 adet (17 aktif, 37.665 silinmiş)
  Aktarılan Anon Satış : 21 adet (1.219.700 kuruş = 12.197,00 TL)
  Müşteri Bakiyesi     : -134.500,68 TL (-13.450.068 kuruş) (Sıfır Sapma)
====================================================
```

### UX / Kullanıcı Deneyimi Değerlendirmesi
- **Süre Analizi:** 37.682 ürün içeren devasa bir envanterin doğrulanmış yedeğinin alınması, SQLite FFI üzerinde aktarılması ve adli mutabakatının yapılması toplam **18,20 saniye** sürmektedir.
- **UI Etkisi:** 18 saniyelik bir süre, açılış sırasında uygulamanın donmuş gibi algılanmasına yol açabilir. 
- **Öneri:** Gerçek üretim açılışında, koordinatör çalışırken kullanıcıya **"Veritabanı Güncelleniyor... Lütfen bekleyiniz"** şeklinde modal bir splash/progress göstergesi sunulmalıdır.

---

## 7. KARARLAR (A - F)

### A. Gerçek bootstrap/coordinator koduyla izole açılış provası tamamlandı mı?
**EVET (PASS).** 10 senaryonun tamamı, gerçek [AppBootstrap.runStartupDiagnostics](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/app_bootstrap.dart#L316) ve [CoreNextBootstrapCoordinator](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart) çağrı zincirleri kullanılarak başarıyla tamamlanmıştır.

### B. Yarım migration sonrası yeniden başlatma güvenli mi?
**EVET (PASS).** Yarım kalan bir migration oturumunun ardından uygulama yeniden başlatıldığında, koordinatörün yarım kalmış işlemi (`migration_in_progress`) tespit edip `failedRecoverable` ile güvenli şekilde taze yedeğe dönerek sıfırdan başarıyla tamamladığı kanıtlanmıştır.

### C. Yeni satış oluştuktan sonra rollback engeli gerçek hata yolunda çalışıyor mu?
**EVET (PASS).** Hedef veritabanına kesme anından sonra yeni bir satış yazıldığında, [CoreNextBootstrapCoordinator.rollbackToLegacy](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart#L630) yolu `UnsafeRollbackException` fırlatarak sessiz geri dönüşü kesin olarak engellemiş ve durumu `failedBlocked` yaparak yeni kaydı korumuştur.

### D. Tenant izolasyonu kanıtlandı mı?
**EVET (PASS).** Nutopia ve sentetik Gamma işletmeleri arasında çapraz erişim girişimlerinin `DatabaseRoutingResolver` tarafından anında `blockedFailClosed` kararı ile durdurulduğu ve veri kirliliğinin sıfır olduğu kanıtlanmıştır.

### E. Üretim açılışına geçmeden önce kalan engeller neler?
1. **Runner Default:** [coreNextMigrationRunnerProvider](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart#L688) üretimde hâlâ varsayılan olarak `null` dönmektedir (kontrollü koruma).
2. **DatabaseManager Yönlendirmesi:** [DatabaseManager.getDatabase()](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart) henüz `DatabaseRoutingResolver`'a devredilmemiştir (hâlâ doğrudan `serenut_pos.db` açmaktadır).
3. **Açılış İlerleme Göstergesi (UX):** 37.682 ürünlük geçiş 18,2 saniye sürdüğü için kullanıcı arayüzünde bilgilendirme diyaloğu/splash bar eklenmelidir.

### F. Bir sonraki aşamada üretim koduna sınırlı entegrasyon değişikliği yapmak için yeterli kanıt var mı?
**EVET.** İzole ortamda tüm adli mutabakat, fail-closed davranışları, rollback koruması ve veri bütünlüğü %100 kanıtlanmıştır. Bir sonraki aşamada, kontrollü bir bayrak arkasında üretim açılış kablolamasına (wiring) geçilmeye hazırdır. Ancak canlı geçiş (production cutover) için yine **ayrı kullanıcı onayı** gerekmektedir.
