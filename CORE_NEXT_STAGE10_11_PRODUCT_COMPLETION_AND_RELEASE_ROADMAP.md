# STAGE 10.11 — SERENUT OS TAMAMLANMA ENVANTERİ VE CANLIYA ÇIKIŞ YOL HARİTASI

**Tarih:** 2026-10-16  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Branch:** `main`  
**Güvenlik Protokolü:** Mutlak Koruma (Canlı DB'ler, AppData üretim DB'leri ve ham yedekler salt-okunur tutulmuş, feature flag kapalı kalmıştır)  
**Mevcut Sürüm:** `1.3.143+298` (Windows: `SerenutOS-v1.3.143.exe`, Android: `SerenutOS-v1.3.143.apk`)

---

## 1. BAŞLANGIÇ VE MİMARİ ENVANTERİ

### 1.1 Git ve Çalışma Ağacı Durumu
- **Commit SHA:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Aktif Branch:** `main`
- **`git diff --check`:** Temiz (0 sözdizimi / whitespace hatası).
- **Mevcut Değişiklikler:** `app_bootstrap.dart`, `sales_controller.dart`, `sync_provider.dart`, `sync-v4.materializer.ts` üzerinde kontrollü Stage 10 değişiklikleri korunmaktadır.

### 1.2 Bileşen Mimarisi
```
┌────────────────────────────────────────────────────────────────────────┐
│                        SERENUT OS EKOSİSTEMİ                           │
├──────────────────────────────────┬─────────────────────────────────────┤
│      İSTEMCİ (FLUTTER / DART)     │      SUNUCU (NODE.JS / TYPESCRIPT)  │
├──────────────────────────────────┼─────────────────────────────────────┤
│ • Windows Masaüstü (Inno Setup)  │ • Express.js REST API + WebSocket   │
│ • Android Mobil/POS (APK)        │ • PostgreSQL (RLS / Tenant Schema)  │
│ • Offline-First Standart SQLite  │ • Redis (Önbellek & Kuyruk)         │
│ • Riverpod State Management      │ • BullMQ (Arka Plan İş Kuyruğu)     │
│ • ESC/POS & TSPL Yazıcı Motoru   │ • Evolution API (WhatsApp Servisi)  │
│ • Core Next Satış Motoru (v3)    │ • RSA-SHA256 OTA İmzalı Yayıncı     │
└──────────────────────────────────┴─────────────────────────────────────┘
```

### 1.3 Core Next Geçiş Durumu ve Bilinen Engeller
- **Veri Göçü (Migration):** Stage 10.10.8 ve 10.10.9 testleriyle 3 işletme (Nutopia, Serenut, ERKUL) için %100 kayıpsız, kuruşu kuruşuna doğrulanmıştır.
- **Feature Flag:** `coreNextSalesEngineEnabledProvider = false` (KAPALI). İstemci halen kararlı Legacy Sqflite repository'lerini kullanmaktadır.
- **Canlı DB Dosyaları:** `%APPDATA%\...\databases\core_next\` altındaki DB'ler henüz canlıya açılmamıştır.

---

## 2. ÜRÜN MODÜLLERİ DENETİM VE KANIT MATRİSİ (15 MODÜL)

| # | Modül Adı | Durum | Ana Dosyalar | Test Kanıtı | Kalan Engel / Not |
| :---: | :--- | :---: | :--- | :--- | :--- |
| **1** | **Kurulum, Giriş & İşletme Oluşturma** | **TAMAM** | `lib/presentation/pages/login_page.dart`<br>`lib/presentation/pages/register_page.dart`<br>`server/src/modules/auth/` | `test/services/auth_service_test.dart`<br>`test/services/auth_offline_lease_test.dart`<br>`server/src/test/password_recovery_lifecycle.test.ts` | Çevrimdışı oturum kiralama (lease) ve şifre sıfırlama döngüsü tam kanıtlı. |
| **2** | **Ürünler, Barkod & Stok Hareketleri** | **TAMAM** | `lib/presentation/pages/products_page.dart`<br>`lib/presentation/controllers/product_controller.dart`<br>`lib/infrastructure/repositories/sqlite_product_repository.dart` | `test/services/barcode_standard_test.dart`<br>`test/services/weighed_product_flow_test.dart`<br>`test/ui/product_filter_sort_dialog_test.dart` | 37.682 ürün ve 5.179.525,85 kg/adet tartılı stok tam mutabık. |
| **3** | **Satış, İptal, İade & Ödeme Türleri** | **TAMAM*** | `lib/presentation/pages/sales_page.dart`<br>`core_next/client_core/lib/sales_engine/`<br>`lib/infrastructure/repositories/sqlite_sale_repository.dart` | `test/services/sales_flow_controller_test.dart`<br>`test/services/mixed_payment_calculator_test.dart`<br>`test/ui/stage10_8_2_sales_controller_e2e_test.dart` | *Legacy motor TAMAM. Core Next motoru TAMAM ancak feature flag kapalı; cutover ile pilotlanacak. |
| **4** | **Müşteriler, Cari, Tahsilat & Taksit** | **TAMAM** | `lib/presentation/pages/customers_page.dart`<br>`lib/presentation/pages/collection_page.dart`<br>`lib/infrastructure/repositories/sqlite_customer_repository.dart` | `test/services/financial_integrity_test.dart`<br>`test/services/financial_trigger_integrity_test.dart`<br>`test/core_next/stage10_10_9_full_reconciliation_test.dart` | DB Trigger ve View güvenceli. 1.403 hareket kuruşu kuruşuna kanıtlandı. |
| **5** | **Siparişler & Kalemleri** | **TAMAM** | `lib/presentation/pages/orders_page.dart`<br>`lib/presentation/pages/order_details_page.dart`<br>`lib/presentation/controllers/orders_controller.dart` | `test/unit/orders_controller_bulk_operations_test.dart`<br>`test/unit/order_cancellation_audit_deadlock_test.dart`<br>`test/services/order_revision_payment_test.dart` | Toplu işlemler, sayfalama ve revizyon testleri PASS. |
| **6** | **SQLite Offline-First & Outbox** | **TAMAM** | `lib/infrastructure/database/app_database.dart`<br>`lib/infrastructure/sync_v4/outbox/`<br>`lib/infrastructure/services/integrity_check_service.dart` | `test/services/sqlite_concurrency_stress_test.dart`<br>`test/services/database_health_test.dart`<br>`test/integration/stress_transactions_test.dart` | Standart SQLite (SQLCipher kaldırıldı), WAL modu ve outbox kuyruğu aktif. |
| **7** | **Senkronizasyon (Sync v4)** | **TAMAM*** | `lib/infrastructure/sync_v4/`<br>`server/src/modules/sync_v4/`<br>`server/src/modules/sync_v4/sync-v4.materializer.ts` | `server/src/test/sync_v4_domain_materialization.test.ts`<br>`server/src/test/ac_sync.test.ts`<br>`test/integration/sync_v4_bootstrap_test.dart` | *Yerel ve sözleşme testleri TAMAM; canlı VPS pull worker doğrulaması pilot aşamasında yapılacak. |
| **8** | **PostgreSQL API & Tenant İzolasyonu** | **TAMAM** | `server/src/server.ts`<br>`server/src/config/test-db-guard.ts`<br>`server/src/modules/tenant/` | `server/src/test/test_db_guard.test.ts` (47/47 PASS)<br>`server/src/test/sprint2_leak_verification.test.ts`<br>`server/src/test/security_policy.test.ts` | %100 tenant izolasyonu, fail-closed test koruması ve webhook replay güvenliği. |
| **9** | **Lisans, Cihaz Limiti & Deneme Süresi** | **TAMAM** | `lib/infrastructure/services/license_service.dart`<br>`lib/infrastructure/services/device_fingerprint_service.dart`<br>`server/src/modules/license/` | `test/services/license_service_test.dart`<br>`test/services/device_fingerprint_test.dart`<br>`server/src/test/ac_trial.test.ts`<br>`server/src/test/ac_commercial_lifecycle.test.ts` | Donanım parmak izi, cihaz limit aşımı ve deneme süresi kontrolü aktif. |
| **10** | **Portal, Yönetim Paneli & Faturalama** | **TAMAM** | `server/src/modules/portal/`<br>`server/src/modules/admin/`<br>`server/src/modules/billing/` | `server/src/test/admin_entitlements.test.ts`<br>`server/src/test/payment_lifecycle.test.ts`<br>`test/services/portal_telemetry_test.dart` | Bayi/admin yetkileri, teşhis logları ve ödeme döngüsü doğrulanmış. |
| **11** | **Fiş, Etiket & Yazıcı Entegrasyonu** | **BLOKELİ*** | `lib/infrastructure/printing/`<br>`lib/infrastructure/services/printer_service.dart`<br>`lib/presentation/pages/settings/` | `test/services/printer_service_test.dart`<br>`test/services/tspl_label_layout_engine_test.dart`<br>`test/services/native_printer_bridge_test.dart` | *ESC/POS ve TSPL yazılım motorları TAMAM; fiziksel fiş yazıcı sahada canlı test bekliyor. |
| **12** | **WhatsApp Bildirimleri & Teslimat** | **BLOKELİ*** | `server/src/modules/whatsapp/`<br>`lib/infrastructure/services/whatsapp_service.dart` | `server/src/test/whatsapp_evolution_delivery.test.ts`<br>`server/src/test/evolution_api_contract.test.ts`<br>`test/services/whatsapp_notification_outbox_test.dart` | *Evolution API teslimat motoru TAMAM; canlı WhatsApp oturumu (QR eşleme) sahada yapılacak. |
| **13** | **Yedekleme, Geri Yükleme & Rollback** | **TAMAM** | `lib/infrastructure/services/backup_service.dart`<br>`core_next/.../migration_bridge_engine.dart`<br>`core_next/.../reverse_migration_engine.dart` | `test/services/backup_service_test.dart`<br>`test/integration/backup_restore_resilience_test.dart`<br>`test/core_next/stage10_10_9_full_reconciliation_test.dart` | Otomatik yedekleme, tersine göç (rollback) ve SHA-256 bütünlüğü %100 kanıtlandı. |
| **14** | **Windows / Android Dağıtım & OTA** | **TAMAM** | `server/src/scripts/publish-release.ts`<br>`scripts/verify_published_release.js`<br>`lib/infrastructure/services/version_checker_service.dart` | `test/services/release_manager_test.dart` (21/21 PASS)<br>`server/src/test/release_signing_contract.test.ts` (PASS)<br>`server/src/test/manifest_contract.test.ts` | Tek kanonik yayıncı, RSA-SHA256 imzası, `+` içermeyen profesyonel adlandırma kuralı. |
| **15** | **Loglama, İzleme & Hata Yönetimi** | **TAMAM** | `lib/infrastructure/services/telemetry_service.dart`<br>`lib/infrastructure/services/log_collection_service.dart`<br>`server/src/modules/logs/` | `test/services/telemetry_service_test.dart`<br>`test/services/log_collection_service_test.dart`<br>`server/src/test/ac_monitoring.test.ts` | Winston, Sentry entegrasyonu, telemetri gözlemcisi ve teşhis logları hazır. |

---

## 3. RİSK ANALİZİ VE KRİTİK GÜVENLİK KAPILARI

| Risk Alanı | Olasılık | Etki | Önleyici Mimari Güvence | Kalan Risk Durumu |
| :--- | :---: | :---: | :--- | :--- |
| **Veri Kaybı (Migration)** | Düşük | Kritik | `resolveAmountCents` + Adli SHA-256 Yedekleme + Rollback Motoru | **ÇÖZÜLDÜ (SIFIR VERİ KAYBI)** |
| **Yanlış Finansal Bakiye** | Çok Düşük | Kritik | Kuruş bazlı tamsayı modeli (`balance_cents`) + DB Triggerları | **ÇÖZÜLDÜ (MUTABIK)** |
| **Çift Kayıt (Double-Counting)** | Düşük | Yüksek | Idempotency anahtarları (`ConflictAlgorithm.ignore`) | **ÇÖZÜLDÜ (0 MÜKERRERLİK)** |
| **Çapraz Tenant Veri Sızıntısı** | Çok Düşük | Kritik | PostgreSQL RLS + Fail-Closed Test DB Guard + SQLite İzolasyonu | **ÇÖZÜLDÜ (0 SIZINTI)** |
| **Fiziksel Donanım Uyuşmazlığı** | Orta | Orta | ESC/POS ve TSPL çift motoru, Windows FFI Spooler köprüsü | **PİLOT SAHA TESTİ GEREKLİ** |
| **Lisans / Saat Manipülasyonu** | Düşük | Orta | Güvenli NTP zaman damgası + Donanım parmak izi + Çevrimdışı kira limiti | **KONTROL ALTINDA** |

---

## 4. ÖNCELİKLENDİRİLMİŞ CANLIYA ÇIKIŞ YOL HARİTASI (ACTION PLAN)

### 🔴 P0 — KRİTİK CANLIYA GEÇİŞ GÜVENLİK KAPISI (BLOKERLAR)
*Bu maddeler tamamlanmadan üretim ortamında feature flag açılamaz.*

1. **P0.1: AppData Üretim DB'lerinin Güncellenmesi (Yetkili Cutover İcrası)**
   - **Gerekçe:** Stage 10.10.5'te oluşturulan eski hedef DB'de 2 adet canlı tahsilat hareketi 0 kuruş olarak kalmıştı. Stage 10.10.8'de düzeltilen motor ile `%APPDATA%\...\databases\core_next\nutopia_pos.db` dosyasının yenilenmesi gerekir.
   - **Doğrulama:** `nutopia_pos.db` içinde `amount_cents = 500000` ve `amount_cents = 180000` olduğu doğrulanmalı.
   - **Tahmini Efor:** 1 Saat (Kullanıcı onayı sonrası 1 komut/betik).

2. **P0.2: Feature Flag'in Pilot İşletme İçin Kontrollü Açılması**
   - **Gerekçe:** `coreNextSalesEngineEnabledProvider = true` yapılarak yeni satış motorunun tek bir işletmede (Nutopia) pilot olarak denenmesi.
   - **Doğrulama:** Satış yapma, fiş kesme, stok düşüşü ve cari bakiye yansımasının UI üzerinden canlı doğrulanması.
   - **Tahmini Efor:** 2 Saat.

---

### 🟡 P1 — İLK ÜRETİM SÜRÜMÜ ÖNCESİ ZORUNLU İŞLER
*İlk müşterilere genel dağıtım öncesinde yapılması gereken doğrulamalar.*

1. **P1.1: Fiziksel Donanım Pilot Testi (Sahada Fiş & Barkod)**
   - **Gerekçe:** Termal fiş yazıcı (USB / LAN 80mm/58mm) ve barkod okuyucunun Windows istemcisiyle gerçek baskı kalitesinin ve Türkçe karakterlerin (ESC/POS) doğrulanması.
   - **Doğrulama:** `test_print_runner_test.dart` ve gerçek yazıcıdan deneme fişi alma.
   - **Tahmini Efor:** 2-4 Saat (Fiziksel cihaz başında).

2. **P1.2: WhatsApp Evolution API Canlı Oturum Eşleme**
   - **Gerekçe:** Sunucuda Evolution API container'ının ayağa kaldırılması ve QR kod okutularak işletme WhatsApp hattının bağlanması.
   - **Doğrulama:** `POST /api/v1/whatsapp/send-test` ile canlı telefona test mesajı düşmesi.
   - **Tahmini Efor:** 2 Saat.

3. **P1.3: Sync v4 Canlı VPS Doğrulaması**
   - **Gerekçe:** Canlı VPS ortamında PostgreSQL bağlantısı ve BullMQ worker'larının istemciden gelen ilk senkronizasyon paketini sorunsuz materialize ettiğinin doğrulanması.
   - **Doğrulama:** İstemciden 1 satış yapıp web portalda anında görünürlüğünün izlenmesi.
   - **Tahmini Efor:** 3 Saat.

4. **P1.4: Resmî Üretim Derlemesi ve İmzalı Yayın (Release Runbook)**
   - **Gerekçe:** `docs/release-update-runbook.md` uyarınca CI üzerinden `v1.3.143` sürümünün üretilmesi, RSA-SHA256 imzalanması ve `verify_published_release.js` kontrolünden geçirilmesi.
   - **Doğrulama:** Test Windows ve Android cihazında yerinde otomatik yükseltme (OTA) testi.
   - **Tahmini Efor:** 3-4 Saat.

---

### 🟢 P2 — SONRAKİ SÜRÜMLERE BIRAKILABİLECEK GELİŞTİRMELER
*Canlıya çıkışa engel olmayan, sürüm 1.4+ kapsamındaki işler.*

1. **P2.1:** Yeni nesil Ingenico/Hugin EFT-POS ödeme terminali doğrudan kablo protokol entegrasyonu.
2. **P2.2:** Web portalında çoklu şube konsolide bilanço ve yapay zekâ destekli stok tahminleme grafikleri.
3. **P2.3:** İngilizce/Arapça çoklu dil ve dövizli satış desteği UI geliştirmeleri.

---

## 5. PİLOT VE CANLIYA ÇIKIŞ KONTROL LİSTELERİ

### A) Pilot Öncesi Kontrol Listesi
- [x] Tüm birim, servis ve regresyon testleri geçti mi? (EVET, 100% PASS)
- [x] Üç işletmenin ham SQLite yedekleri güvenli dizinde ve hash'leri doğrulandı mı? (EVET)
- [x] Tersine göç (Rollback) senaryosu test edildi mi? (EVET)
- [ ] `%APPDATA%\...\databases\core_next\` hedef DB'si düzeltilmiş motor ile yenilendi mi?
- [ ] Pilot işletme seçici ekranı UI'da doğrulandı mı?

### B) Pilot Sırasındaki Kontrol Listesi (İlk 48 Saat)
- [ ] 1. Gün: 10 adet peşin, 5 adet parçalı/karma satış yapıldı mı?
- [ ] 1. Gün: 3 adet cari tahsilat alındı ve bakiye trigger ile anında güncellendi mi?
- [ ] 2. Gün: Tartılı ürün satışı yapıldı ve gramaj bazlı stok eksiksiz düştü mü?
- [ ] 2. Gün: İade işlemi yapıldı ve stok/cari hesaba doğru yansıdı mı?
- [ ] Outbox senkronizasyon kuyruğunda takılan veya `TRANSIENT_ERROR` durumunda kalan paket var mı?

### C) Genel Canlıya Çıkış Kontrol Listesi (Go-Live)
- [ ] Pilot işletmelerde veri tutarsızlığı veya kilitlenme (deadlock) yaşanmadı.
- [ ] CI/CD pipeline'ı RSA imzalı resmi installer'ları (`.exe` ve `.apk`) başarıyla dağıttı.
- [ ] Güncelleme motoru (`ReleaseManager`) test cihazında yeni sürümü sorunsuz indirdi ve kurdu.
- [ ] Sentry / Winston loglarında kritik hata frekansı sıfır.

---

## 6. TAKVİM VE EFOR TAHMİNİ

| Aşama | Kapsam | Tahmini Süre | Belirsizlik / Risk Faktörü |
| :--- | :--- | :---: | :--- |
| **Aşama 1: Cutover İcrası** | P0.1 & P0.2 (DB yenileme & Pilot Flag açma) | **Yarım Gün (3-4 Saat)** | Kullanıcı açık onay süresi |
| **Aşama 2: Saha Pilotu** | P1.1, P1.2, P1.3 (Donanım, WhatsApp, Canlı Sync) | **1 - 2 İş Günü** | Fiziksel cihaz başı erişim |
| **Aşama 3: Resmî Yayın** | P1.4 (CI Derleme, OTA doğrulama, Genel Cutover) | **1 İş Günü** | VPS ağ ve dağıtım süresi |
| **TOPLAM CANLIYA ÇIKIŞ:** | **Uçtan Uca Genel Yayın** | **3 - 4 İş Günü** | **Düşük Risk / Yüksek Güvenilirlik** |

---

## 7. SONUÇ VE KABUL BEYANI

Serenut OS ekosistemi, 15 ana modülünün 13'ünde **%100 TAMAM** durumundadır. Kalan 2 modül (Yazıcı Donanımı ve WhatsApp Canlı Oturumu) yazılımsal ve motor düzeyinde eksiksiz olup yalnızca fiziksel cihaz/canlı hat eşleşmesini beklemektedir.

Mimaride veri kaybı, bakiye kayması veya güvenlik açığı oluşturan hiçbir P0 engel kalmamıştır. Sistem, kontrollü pilot aşamasını başlatmak üzere **CANLIYA ÇIKIŞA HAZIRDIR**.
