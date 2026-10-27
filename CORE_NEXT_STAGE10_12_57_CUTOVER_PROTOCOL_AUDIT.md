# SERENUT OS — STAGE 10.12.57
# CUTOVER PROTOCOL IMPLEMENTATION AUDIT — NO LIVE CUTOVER

**Proje Yolu:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Tarih / Saat:** 2026-10-20T23:45:00+03:00  
**Git Dalı:** `main`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Önceki Rapor:** `CORE_NEXT_STAGE10_12_56_DELTA_COMPLETENESS_AUDIT.md`  
**Denetim Aşaması Kararı:** **`BLOCKED_CUTOFF_PROTOCOL`**  

```text
================================================================================
CUTOVER: NOT APPROVED
LIVE DATABASE WRITES: NOT PERFORMED
CORE NEXT SALES ENGINE: DISABLED
DATABASE ROUTING HOOK: NULL
OLD DATABASE RETIREMENT: NOT APPROVED
================================================================================
```

---

## 1. ZORUNLU GÜVENLİK SINIRLARI VE CANLI DURUM

Stage 10.12.57 kapsamında canlı kaynak ve hedef veritabanlarına hiçbir yazma, migration, repair veya test yazması yapılmamış; salt-okunur adli inceleme ve izole test protokolü sürdürülmüştür:

| Güvenlik Kuralı | Beklenen Durum | Gerçek Durum | Sonuç |
| :--- | :--- | :--- | :--- |
| `coreNextSalesEngineEnabledProvider` | `false` | `false` ([sales_controller.dart:104](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L104)) | **KORUNDU** |
| `DatabaseManager.databaseRoutingHook` | `null` | `null` ([database_provider.dart:48](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L48)) | **KORUNDU** |
| `coreNextMigrationRunnerProvider` | `null` | `null` ([app_bootstrap.dart:136](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/app_bootstrap.dart#L136)) | **KORUNDU** |
| `coreNextCatchUpRunnerProvider` | `null` | `null` ([app_bootstrap.dart:140](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/app_bootstrap.dart#L140)) | **KORUNDU** |
| Canlı Kaynak DB (`serenut_pos.db`) | Yalnızca Salt-Okunur | 61,390,848 B, SHA-256: `262f2f3c...`, Bütünlük: `ok` | **DEĞİŞMEDİ** |
| Canlı Hedef DB (`core_next/nutopia_pos.db`) | Yalnızca Salt-Okunur | 17,010,688 B, SHA-256: `c976b4d2...`, Bütünlük: `ok` | **DEĞİŞMEDİ** |
| Kiracı İzolasyonu | Tam İzolasyon | Nutopia, Erkul Çeyiz ve Serenut ayrık tutuldu | **KORUNDU** |
| Canlı Kasa Durumu | Kesintisiz | Hiçbir kasa dondurma veya canlı işlem yapılmadı | **KORUNDU** |

---

## 2. GİT VE BAŞLANGIÇ DURUMU DOĞRULAMASI

- **Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Git Dalı:** `main`
- **Son 5 Commit:**
  - `28c158d8` fix(test): align splash screen error title expectation and bump version to 1.3.143+298
  - `8c6d7682` feat(observability): mask internal errors from users, route fatal events to sentry/telemetry with correlation reference, and bump to v1.3.143+297
  - `206557f3` fix(db): drop immutability triggers before migrations and bump version to 1.3.143+296
  - `fa704af1` chore(release): bump version to 1.3.143+295 for production deployment
  - `567680fa` fix(server): resolve TS18048 undefined activation check in billing bank-transfer routes
- **`git diff --check`:** Temiz (0 hata).

---

## 3. ALTI ADIMLI KESİM PROTOKOLÜNÜN KOD DÜZEYİNDE SINIFLANDIRILMASI

Stage 10.12.56 raporunda önerilen 6 adımlı kesim protokolü gerçek üretim kodunda taranmış ve aşağıdaki gibi sınıflandırılmıştır:

| Adım | Protokol Adımı Tanımı | Kod Durumu | İlgili Dosyalar ve Gerçek Durum |
| :---: | :--- | :---: | :--- |
| **1** | **Satış ve sipariş girişlerinin kontrollü biçimde durdurulması** | **`NOT_IMPLEMENTED`** | [`SalesController`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart), [`SalesFlowController`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_flow_controller.dart) ve [`OrdersController`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/orders_controller.dart) içinde kasayı "Geçiş Modu"na alan veya yeni satış girişini engelleyen merkezi bir lock/pause mekanizması **yoktur**. Kasiyer UI'da satış yapmaya devam edebilir. |
| **2** | **Devam eden işlemlerin tamamlandığının doğrulanması (In-flight Drain)** | **`NOT_IMPLEMENTED`** | Devam eden asenkron SQLite yazma işlemlerini veya HTTP isteklerini sayan ve bitene kadar bekleyen bir `DrainController` veya `ActiveTransactionTracker` üretim kodunda **mevcut değildir**. |
| **3** | **Tutarlı son snapshot alınması ve kesim noktasının kalıcı kaydedilmesi** | **`PARTIALLY_IMPLEMENTED`** | `SQLite Online Backup API` ile anlık tutarlı yedek alma yeteneği vardır. Ancak $T_{cut}$ kesim noktasını kalıcı bir `cutover_checkpoint` tablosuna yazan ve bunu sonraki delta için autoritatif checkpoint yapan üretim akışı runtime'a **bağlanmamıştır**. |
| **4** | **Snapshot sonrasında oluşan bütün delta kayıtlarının aktarılması** | **`IMPLEMENTED_AND_TESTED`** | [`LiveSafeCatchUpReconciliationCoordinator.performCatchUpAndReconcile`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart#L250) ve [`repairHistoricalLedgerEntries`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart#L451) metotları mevcuttur; ürün, müşteri, satış, ödeme, iade, defter ve outbox kayıtlarını monoton saat güvencesiyle aktarmakta ve izole ortamda 138+ test ile doğrulanmıştır. |
| **5** | **Kaynak ve hedef arasında mutabakat kapısının çalıştırılması** | **`IMPLEMENTED_AND_TESTED`** | `LiveSafeCatchUpReconciliationCoordinator` içinde `LiveReconciliationReport`, satış sayısı, kuruş toplamı, müşteri bakiyesi ve stok toplamı mutabakat kapısı kodlanmış ve test edilmiştir. |
| **6** | **Kontrollü yönlendirme değişimi ve güvenli geri dönüş (Rollback)** | **`PARTIALLY_IMPLEMENTED`** | [`PilotCutoverGate`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/pilot_cutover_gate.dart) ve [`DualDatabaseRoutingCoordinator`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart) fail-closed fallback sunmaktadır. Ancak **yeni DB'ye yazma başladıktan sonra** eski DB'ye geri dönüşte yeni verileri eski DB'ye aktaracak **Tersine Senkronizasyon (Reverse Sync)** motoru **yoktur**. |

---

## 4. EŞZAMANLI İŞLEMLER VE BEŞ DAKİKA RİSKİ ADLİ DENETİMİ

"5 dakikalık geçiş penceresi" varsayımı gerçek kod üzerinden incelenmiş ve 8 kritik soru yanıtlanmıştır:

1. **Kasiyer yeni satış başlatırken geçiş kilidi alınabilir mi?**  
   - **HAYIR.** [`SalesController.completeSale`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart) doğrudan `_salesService.createSale` çağırır; hiçbir kilit veya geçiş modu kontrolü yapılmaz.
2. **İşlem devam ederken kilit alınırsa işlem güvenli şekilde tamamlanıyor mu?**  
   - **HAYIR.** Merkezi kilit olmadığı için eşzamanlı bir snapshot veya cutover zorlanırsa, SQLite düzeyinde WAL lock contention veya meşguliyet (busy exception) oluşabilir.
3. **Satış, sipariş, ödeme veya stok işlemi yarıda kesilebilir mi?**  
   - Tekil satışlar transaction içindedir; ancak cutover sırasında uygulama veya DB bağlantısı zorla değiştirilirse transaction `ROLLBACK` olur ve kasiyer ekranında beklenmedik hata fırlatılır.
4. **Uygulamanın birden fazla ekranı veya isolate'ı aynı DB'ye yazabilir mi?**  
   - **EVET.** `sqflite_common_ffi` arka planda izole bir C isolate worker kullanır. Ayrıca arka plan senkronizasyonu bağımsız yazma yürütür.
5. **Arka plan senkronizasyonu veya başka bir görev geçiş sırasında yeni kayıt oluşturabilir mi?**  
   - **EVET.** Canlı sistem incelemesinde tespit edildiği üzere, `SyncNotifier.triggerSync` periyodik olarak çalışmakta ve `client_telemetry_logs` tablosuna yazma yapmaktadır.
6. **Kilit veya geçiş modu uygulama yeniden başlatıldığında nasıl davranır?**  
   - Kalıcı bir geçiş modu bayrağı bulunmadığı için uygulama kapatılıp açıldığında doğrudan normal legacy modda başlar.
7. **İşlem zaman aşımına uğrarsa sistem eski DB üzerinde çalışmaya devam eder mi?**  
   - **EVET.** [`PilotCutoverGate`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/pilot_cutover_gate.dart) fail-closed çalışır; timeout durumunda `RoutingDecision.legacyFallback` seçilir.
8. **İstemci çevrimdışıyken veya bir işlem kuyruğa alınmışken kesim noktası nasıl korunur?**  
   - `sync_outbox_v4` kuyruğunda bekleyen işlemler kesim anından sonra eski DB'ye yazılabilir; bu durum kesim anından sonra eski DB'de "hayalet işlem" (stale write) üretir.

> **Kritik Denetim Tespiti:**  
> Canlı yazmaları merkezi ve doğrulanabilir biçimde durdurabilen bir **Cutoff Lock / Maintenance Gate** üretim kodunda kodlanmamıştır. Bu mekanizma olmadan canlı geçiş başlatılamaz.

---

## 5. DELTA VE MUTABAKAT KAPISI ANALİZİ

İzole testler kapsamında aşağıdaki senaryolar gerçek Dart koordinatörüyle doğrulanmıştır:

- **Eşit Zaman Damgalı Kayıtlar:** Aynı milisaniyede (`2026-10-17T14:30:00.000Z`) oluşan birden fazla finansal hareket (`tx-same-1`, `tx-same-2`) deterministik biçimde ve kayıpsız aktarılmıştır.
- **Mutabakat Uyuşmazlığında Kapı Durumu:** Hedef DB'de tenant ID uyuşmazlığı simüle edildiğinde, `DualDatabaseRoutingCoordinator` fail-closed devreye girerek `RoutingDecision.blockedFailClosed` üretmiş ve geçişi kesin olarak durdurmuştur.

---

## 6. GÜVENLİ GERİ DÖNÜŞ (ROLLBACK) VE TERSİNE SENKRONİZASYON AÇIĞI

Geri dönüş mekanizması iki farklı zaman dilimi için incelenmiştir:

1. **Yönlendirme Öncesi Rollback (Pre-Routing Rollback):**  
   - **GÜVENLİDİR.** Doğrulama, yedekleme veya delta aktarımı sırasında bir hata çıkarsa yönlendirme hiç açılmaz; sistem eski DB üzerinde sıfır kayıpla çalışmaya devam eder.
2. **Yönlendirme Sonrası Rollback (Post-Routing Reverse Rollback):**  
   - **KRİTİK RİSK (Split-Brain).** Hedef `CoreAppDatabase`'e geçildikten sonra kasiyer yeni satış yaparsa ve saatler sonra bir hatadan dolayı eski DB'ye dönülmek istenirse, yeni DB'de oluşan satışları eski DB'ye geri işleyecek bir **Reverse Adapter** kodda mevcut DEĞİLDİR. Bu durum veri kaybına veya iki parçalı bölünmüş geçmişe (split-brain) yol açar.

---

## 7. ÇALIŞTIRILAN TESTLER VE REGRESYON KANITI

1. **`flutter analyze test/core_next/stage10_12_57_cutover_protocol_audit_test.dart`**
   - Sonuç: `No issues found!` (0 hata, 0 lint uyarısı).
2. **Stage 10.12.57 Test Paketi:**
   - Komut: `flutter test test/core_next/stage10_12_57_cutover_protocol_audit_test.dart`
   - Sonuç: **`10/10 All tests passed!`** (exit code 0).
3. **Kapsamlı Regresyon Paketi (Stages 10.12.43 — 10.12.57, 16 test dosyası):**
   - Komut: `flutter test $files` (PowerShell path expansion)
   - Sonuç: **`148/148 All tests passed!`** (exit code 0, 46 saniye).
4. **`git diff --check`:**
   - Sonuç: 0 hata (Temiz).

---

## 8. NİHAİ KARAR VE ENGEL TANIMI

### Karar Kodu:
## `BLOCKED_CUTOFF_PROTOCOL`

### Gerekçe:
1. Altı adımlı kesim protokolünün 1. ve 2. adımları (canlı satış/sipariş girişlerini durduran merkezi kilit ve devam eden asenkron işlemleri bekleyen drain mekanizması) üretim kodunda **kodlanmamıştır (`NOT_IMPLEMENTED`)**.
2. Canlı mağaza çalışırken eşzamanlı satışların kesim anında eski DB'ye yazılmasını engelleyecek bir bariyer bulunmamaktadır.
3. Yönlendirme sonrasında eski DB'ye dönüş gerektiğinde veri kaybını önleyecek Tersine Senkronizasyon (Reverse Sync) mekanizması mevcut değildir.

### Zorunlu Güvenlik Bildirimi:
```text
================================================================================
CUTOVER: NOT APPROVED
LIVE DATABASE WRITES: NOT PERFORMED
CORE NEXT SALES ENGINE: DISABLED
DATABASE ROUTING HOOK: NULL
OLD DATABASE RETIREMENT: NOT APPROVED
================================================================================
```
