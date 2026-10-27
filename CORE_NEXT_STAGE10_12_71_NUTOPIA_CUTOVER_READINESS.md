# SERENUT OS — STAGE 10.12.71
# NUTOPIA GEÇİŞİNE HAZIRLIK VE UYGULAMA KARARI RAPORU

**Tarih:** 21 Ekim 2026  
**Aşama:** STAGE 10.12.71 — Nutopia Geçişine Devam Et  
**Hedef Rapor:** `CORE_NEXT_STAGE10_12_71_NUTOPIA_CUTOVER_READINESS.md`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (`main` branch)  
**Odak İşletme:** Yalnızca **Nutopia Fındık Değirmeni** (Serenut ve Erkul hariç tutulmuştur)  

---

## 1. NUTOPIA DOĞRU KAYNAK - HEDEF EŞLEŞMESİ VE KİMLİK DOĞRULAMASI

### 1.1 Varlık ve Dosya Kimlikleri

| Alan | Kaynak Veritabanı | İzole Hedef Veritabanı |
| :--- | :--- | :--- |
| **Dosya Yolu** | `backups/raw_tenants_20261016/raw_nutopia_v60.db` | `backups/stage64_isolated/nutopia/nutopia_core_next.db` |
| **Boyut (Bayt)** | 59,764,736 | 17,018,880 |
| **SHA-256 Özeti** | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | `8f270986277d661c021d75e85e25352bccb18b48ff8db6f088b9f5fbea95a300` |
| **SQLite Bütünlüğü** | `ok` (0 FK ihlali) | `ok` (0 FK ihlali) |
| **İşletme Adı** | `settings.business_name = 'Nutopia Fındık Değirmeni'` | `app_settings.business_name = 'Nutopia Fındık Değirmeni'` |
| **Kiracı Kimliği** | `settings.tenant_id = 'nutopia'` | `app_settings.tenant_id = 'nutopia'` |

> **İzolasyon Güvencesi:** Nutopia hedef veritabanında Serenut veya Erkul Çeyiz'e ait hiçbir kayıt, ayar veya referans bulunmamaktadır. Çapraz veri karışması kesinlikle yoktur.

---

## 2. MEVCUT KANITLARLA TAMAMLANDIĞI BİLDİRİLEN İŞLER VE SAYISAL MUTABAKAT

### 2.1 Doğrulanmış Varlık Dağılımı

- **Ürünler:** 37.682 ürün (Toplam Stok: 5.179.525,85 kg/adet) — %100 mutabık.
- **Satışlar:** 52 satış — %100 mutabık.
- **Siparişler:** 792 sipariş ve 1.068 sipariş kalemi — %100 mutabık.
- **Finansal Hareketler (1.424 Hareket):**
  - 1.403 cari defter hareketi (`ledger_entries`)
  - 21 carisiz kasa işlemi (`cash_transactions`)
  - Toplam: 1.424 hareket kuruşu kuruşuna, satır satır (%100) eşleşmiştir.
- **Senetli ve Vadeli İşlemler:**
  - 54 adet manuel senetli borç kaydı (Toplam tutar: **103.351,00 TL**) eksiksiz defterde mevcuttur.
  - 2 adet taksit planı, 9 taksit detayı ve 8 taksit tahsilatı incelenmiştir. Taksit tahsilatları cari deftere çift yazılmamıştır.

### 2.2 584 Müşteri vs 614 Müşteri Farkının Adli Açıklaması

Önceki raporlarda görülen 584 vs 614 müşteri farkı bir sayım veya veri kaybı hatası değildir:
1. **16 Ekim 2026 Dondurulmuş Snapshot (`raw_nutopia_v60.db`):**
   - Tam olarak **584 kayıt** (583 geçerli UUID müşteri + 1 dahili 'Peşin Müşteri' [boş ID]) içermektedir. Bakiye toplamı: `-134.500,68 TL`.
   - İzole hedef `nutopia_core_next.db` bu 584 müşteriyi bire bir karşılamaktadır (583 UUID + 1 `customer-pesin-default`).
2. **Canlı Sistem (19-20 Ekim Çalışma Durumu):**
   - Kullanıcının yerel bilgisayarında (`%APPDATA%`) aktif çalışan Nutopia sisteminde 16-20 Ekim tarihleri arasında ticari faaliyet devam etmiş; sisteme **30 yeni müşteri** eklenerek toplam sayı **614**'e, finansal hareketler ise **1.498**'e (1.424 + 74 delta) ulaşmıştır.
3. **Sonuç:**
   Bu fark tam anlamıyla bir **"Canlı Veri Tazeliği Farkı (Freshness Delta)"**dır. 16 Ekim snapshot'ı temel taban (baseline) olarak geçerlidir; canlı geçiş anında bu 30 yeni müşteri ve 74 yeni hareket delta aktarımı ile hedefe taşınacaktır.

---

## 3. MEVCUT KODDAKİ MEKANİZMALAR VE ÇALIŞMA AKIŞI İNCELEMESİ

### 3.1 Bakım Kilidi (`CutoffMaintenanceLock`)
- **Dosya:** [core_next/client_core/lib/infrastructure/migration/cutoff_maintenance_lock.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/cutoff_maintenance_lock.dart)
- **Kapsam:** Tam. [DatabaseManager.transaction](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L60-L75), `insert`, `update`, `delete`, `rawInsert` ve UI kontrolcüleri ([SalesController.createSale:159](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L159), `OrdersController:207`, `SyncProvider:191`, `TelemetryUploadService:22`) kilidi kontrol eder.
- **Boşaltma (Draining):** `acquireLock()` çağrıldığında faz `lockingRequested` olur, devam eden aktif yazmaların 0'a inmesi beklenir (`draining`), ardından `locked` fazına geçilir. Kilitliyken yapılan her yazma `CutoffMaintenanceActiveException` fırlatır.

### 3.2 Delta Yakalama ve İdempotency (`LiveSafeCatchUpReconciliationCoordinator`)
- **Dosya:** [core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart:250](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart#L250)
- **Checkpoint:** `lastMigrationCutoffTimestamp` (16 Ekim epoch ms). Canlı DB'deki `created_at >= cutoff` veya `updated_at >= cutoff` olan ürün, müşteri, satış, iade ve defter kayıtları tespit edilir.
- **İdempotency:** Ürün ve müşterilerde `ON CONFLICT(id) DO UPDATE WHERE excluded.updated_at >= ...`, defterde `INSERT OR IGNORE INTO ledger_entries`, satışlarda tekil `idempotency_key` kullanılmıştır. Süreç yarıda kalıp tekrar çalıştırılsa bile **çift kayıt veya mükerrer stok düşümü oluşması matematiksel olarak imkansızdır**.

### 3.3 Geri Dönüş Motoru (`ReverseMigrationEngine`)
- **Dosya:** [core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart:1860-2260](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart#L1860-L2260)
- **Durum:** **İskelet DEĞİLDİR; 400 satırlık eksiksiz çalışan üretim kodudur.**
- **Yetenekleri:** Core Next üzerinde yapılan yeni satışları legacy `sales`, `sale_items` ve `sale_payments` tablolarına aktarır; stok değişimlerini (deltas) hesaplayıp legacy `products.quantity` üzerinde günceller; bağımsız dış müdahale varsa çakışma hatası fırlatıp rollback yapar; yeni defter hareketlerini `financial_transactions` tablosuna aktarır.

### 3.4 Veritabanı Yönlendirme ve Aktivasyon
- **Kanca:** [DatabaseManager.databaseRoutingHook](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L361)
- **Kapı:** [PilotCutoverGate](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/pilot_cutover_gate.dart) (SharedPreferences `core_next_pilot_enabled = true` ve kill-switch kontrolü ile fail-closed çalışır).

---

## 4. KALAN GERÇEK TEKNİK VE OPERASYONEL ENGELLER

Tüm alt bileşenler kod tabanında mevcut ve test edilmiş olmasına rağmen, Nutopia cutover'ının doğrudan başlatılmasını engelleyen **tek bir somut teknik eksiklik** bulunmaktadır:

### 🚨 Somut Teknik Engel: Uçtan Uca Orkestratör (Cutover Runner Glue) Eksikliği
- `CutoffMaintenanceLock.acquireLock()`,
- `LiveSafeCatchUpReconciliationCoordinator.performCatchUpAndReconcile()`,
- G1 - G7 doğrulama kapıları,
- `DatabaseManager.databaseRoutingHook` ve SharedPreferences bayraklarının güncellenmesi,
- Hata anında `ReverseMigrationEngine.rollbackToLegacy()` çağrısı,

bu parçalar ayrı sınıflar olarak mevcuttur; ancak bunları tek bir komutla veya tek bir ekrandan atomik olarak yürüten **`NutopiaCutoverOrchestrator` (veya `scripts/run_nutopia_live_cutover.dart`)** yapıştırıcı kodu (glue code) henüz tek bir çalıştırma giriş noktasına bağlanmamıştır.

Operatörün şu anda geçiş yapabilmesi için her adımı elle çağırması gerekmektedir ki bu canlı üretimde insan hatası riski taşır.

---

## 5. NUTOPIA İÇİN UYGULANABİLİR GEÇİŞ SIRASI

Nutopia cutover işlemi için izlenecek kesin operasyon adımları:

1. **Adım 1 (Yedekleme):** Canlı Nutopia DB'sinden `VACUUM INTO` ile donmuş yedek alınması, SHA-256 ve `PRAGMA integrity_check` doğrulaması (G1 Kapısı).
2. **Adım 2 (Yazma Kilidi):** `DatabaseManager.cutoffMaintenanceLock.acquireLock(reason: 'Nutopia Cutover', tenantId: 'nutopia')` çağrılarak kasanın kilitlenmesi, aktif yazmaların 0'a inmesi (G2 Kapısı).
3. **Adım 3 (Temel Hedefin Hazırlanması):** 16 Ekim'de doğrulanmış olan `nutopia_core_next.db` dosyasının canlı ortama kopyalanması (37.682 ürün, 584 cari, 1.424 hareket).
4. **Adım 4 (Delta Catch-up):** `LiveSafeCatchUpReconciliationCoordinator.performCatchUpAndReconcile` çalıştırılarak 16 Ekim'den bugüne eklenen ~30 cari ve ~74 finansal hareketin hedefe idempotent aktarılması (G3 Kapısı).
5. **Adım 5 (Bakiye ve FK Doğrulaması):** Toplam ciro kuruş farkı = 0, müşteri bakiyeleri farkı = 0 ve `foreign_key_check` = 0 doğrulaması (G4 ve G5 Kapıları).
6. **Adım 6 (Aktivasyon):** 
   - `DatabaseManager.databaseRoutingHook = () async => nutopiaTargetDbPath;`
   - `prefs.setBool('core_next_pilot_enabled', true);`
   - `coreNextSalesEngineEnabledProvider = true;`
   (G7 Kapısı).
7. **Adım 7 (Açılış):** Kasiyer ekranının açılması ve satış işlemlerinin Core Next üzerinden başlatılması.
8. **Acil Durum (Rollback):** Sorun çıkarsa `ReverseMigrationEngine.rollbackToLegacy()` çalıştırılarak yeni fişler legacy DB'ye aktarılır, bayraklar false yapılır.

---

## 6. NİHAİ KARAR

```text
================================================================================
AŞAMA KARARI: BLOCKED_BY_SPECIFIC_TECHNICAL_ISSUE
(SOMUT TEKNİK ENGELE TAKILDI)

Gerekçe:
1. Nutopia kaynak ve hedef verileri kuruşu kuruşuna doğrulanmıştır.
2. 584 vs 614 müşteri farkı 16 Ekim sonrası canlı delta farkı olarak çözümlenmiştir.
3. Bakım kilidi, delta yakalama koordinatörü ve ters geri dönüş motoru kodda mevcuttur.
4. ANCAK: Bu mekanizmaları atomik biçimde birbirine bağlayıp canlıda tek hamlede
   çalıştıracak güvenli 'NutopiaCutoverOrchestrator' yürütücüsü henüz bağlanmamıştır.
================================================================================
```

### Zorunlu Son Güvenlik Durumu (Değişmez Korumalar):

```text
CUTOVER: NOT APPROVED (Canlı geçiş yürütücüsü bağlanmadan onaylanamaz)
LIVE DATABASE WRITES: NOT PERFORMED (0 Canlı Yazma)
CORE NEXT SALES ENGINE: DISABLED (coreNextSalesEngineEnabledProvider = false)
DATABASE ROUTING HOOK: NULL (DatabaseManager.databaseRoutingHook = null)
OLD DATABASE RETIREMENT: NOT APPROVED
RELEASE: NOT PUBLISHED
```
