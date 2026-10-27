# SERENUT OS — STAGE 10.8.11 MIGRATION SAFETY REPORT
## Veri Göçü Güvenliği, FK Bütünlüğü ve Başlangıç Sıralaması Denetimi

**Tarih:** 2026-10-15  
**Kapsam:** `MigrationBridgeEngine`, `app_bootstrap.dart`, In-Place UPSERT, Foreign Key Restrict Koruması ve Transaction Rollback Garantileri.

---

## 1. MIGRATION MİMARİSİ VE ÇALIŞMA PRENSİBİ

`MigrationBridgeEngine`, legacy SQLite veritabanındaki (`serenut_pos.db`) tabloları okuyarak Core Next kuruş ve defter şemasına (`serenut_core_v2.db`) aktaran tek seferlik deterministik bir geçiş motorudur.

### Temel Güvenlik İlkeleri:
1. **Kaynak Veritabanı Asla Silinmez:**
   Migration esnasında veya sonrasında `serenut_pos.db` silinmez, üzerine yazılmaz veya tabloları drop edilmez. Kaynak veritabanı kontrollü doğrulama tamamlanana kadar güvenli salt-okunur yedek olarak korunur.
2. **In-Place UPSERT (`ON CONFLICT DO UPDATE`):**
   `products` ve `customers` tablolarına veri yazılırken `ConflictAlgorithm.replace` kullanılmaz. SQLite `REPLACE`, dahili bir `DELETE` ardından `INSERT` yaptığı için hedefteki `sale_items` ve `ledger_entries` tablolarındaki `ON DELETE RESTRICT` foreign key kısıtını ihlal edip çökmeye yol açıyordu. Stage 10.8.9'da hayata geçirilen ve Stage 10.8.11 Test 2 ve Test 4 ile bağımsız olarak kanıtlanan `ON CONFLICT DO UPDATE` tekniği, ilişkili alt kayıtları koruyarak ürün adı, fiyatı ve stoğunu in-place günceller.
3. **Tek Atomik Transaction ve Rollback Güvencesi:**
   Tüm migration tek bir SQLite transaction bloğu içinde çalıştırılır. Herhangi bir tabloda şema ihlali, geçersiz negatif tutar veya beklenmeyen istisna oluştuğunda, transaction tamamen rollback edilir; Core Next veritabanında yarım kalmış veya tutarsız hiçbir veri bırakılmaz (Test Senaryosu 3 ile kanıtlanmıştır).

---

## 2. BAŞLANGIÇ SIRALAMASI (BOOTSTRAP INITIALIZATION ORDER)

`app_bootstrap.dart` ve `AppBootstrap.runStartupDiagnostics` içerisindeki açılış akışı şu sıralamayı takip eder:

```
1. Güvenilen CA Sertifikası ve Yerel Saat Yükleme (HttpOverrides & DateFormatting)
2. Desktop SQLite FFI Başlatma (sqfliteFfiInit & databaseFactoryFfi)
3. Kalıcı Ayarlar ve Servisler (SharedPreferences, DatabaseManager, DbGateway)
4. Veritabanı Bütünlük Kontrolü (runDiagnostics & attemptDatabaseRepair)
5. Çökme Kurtarma Taraması (crashRecoveryManager.checkForCrashOnStartup)
6. Donanım ve Yazıcı Kuyruğu Başlatma (printingRuntimeProvider)
7. Yerel Depoları Ön Isıtma (Pre-warm: settingsRepo, productRepo, customerRepo)
8. Riverpod Container Hazırlığı ve Arayüzün Açılışı
```

`productRepositoryProvider` ve `customerRepositoryProvider` pre-warm adımı esnasında `coreNextProductRepositoryProvider` ve `coreNextCustomerRepositoryProvider` durumunu denetler; böylece Core Next aktif ise doğrudan Core Next tabloları ön ısıtılır.

---

## 3. BAĞIMSIZ TEST DOĞRULAMA KANITLARI

| Test | Senaryo | Test Adımları | Sonuç |
|---|---|---|---|
| **Senaryo 1** | İlk Migration (Tam Kapsam) | 1 kategori, 1 ürün, 1 müşteri, 1 satış, 1 satış kalemi içeren legacy DB Core Next'e aktarılır. | **BAŞARILI:** 1 ürün, 1 müşteri, 1 satış, 1 kalem aktarıldı. Bakiye ve fiyat kuruşa dönüştü. |
| **Senaryo 2** | Migration'ın İki Kez Çalıştırılması | İlk migration sonrası kaynakta ürün fiyatı güncellenir ve migration tekrar çağrılır. | **BAŞARILI:** FK RESTRICT hatası oluşmadı; ürün fiyatı Core Next'te 5500 kuruş olarak güncellendi. |
| **Senaryo 3** | Rollback Güvencesi | Legacy DB'ye geçersiz negatif toplamlı satış eklenir ve migration başlatılır. | **BAŞARILI:** Hata yakalandı (`GEÇMİŞ SATIŞ MUTABAKAT HATASI`). Core Next DB tertemiz kaldı (0 satış). |
| **Senaryo 4** | FK RESTRICT Koruması | Satış kalemi bulunan ürün `ProductRepository.update` ile güncellenir. | **BAŞARILI:** Satış kalemi korundu, yabancı anahtar bütünlüğü bozulmadı. |
| **Senaryo 15** | Disk Persistence | Veritabanı kapatılıp tekrar açılır. | **BAŞARILI:** Kalıcı ürün bilgileri diskten eksiksiz okundu. |
| **Senaryo 17** | ACID Rollback | Transaction ortasında bağlantı kopması/hata fırlatılır. | **BAŞARILI:** Yarım kayıt bırakılmadı, rollback tam olarak işletildi. |

---

## 4. GÜVENLİ GERİ DÖNÜŞ (SAFE ROLLBACK PROCEDURE)

Eğer pilot kullanım veya cutover sonrasında beklenmedik bir kritik durum yaşanırsa:
1. `coreNextSalesEngineEnabledProvider` bayrağı `false` yapılır.
2. UI anında `serenut_pos.db` ve legacy satış/ürün depolarına döner.
3. Legacy DB'deki veriler migration sırasında asla silinmediği için tüm geçmiş veri sağlam ve eksiksiz olarak hazır beklemektedir.
4. Core Next devrede iken yapılan yeni satışlar için `ReverseMigrationEngine` çalıştırılarak yeni satışlar legacy `sales` ve `sale_payments` tablolarına aktarılabilir.
