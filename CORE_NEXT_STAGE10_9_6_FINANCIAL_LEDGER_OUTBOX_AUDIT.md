# CORE_NEXT_STAGE10_9_6_FINANCIAL_LEDGER_OUTBOX_AUDIT.md
# ADVERSARIAL FINANCIAL INTEGRITY, REFUND, LEDGER & OUTBOX AUDIT RAPORU

**Tarih:** 15 Ekim 2026  
**Proje:** `c:\Users\notop\AndroidStudioProjects\shaman_new`  
**Aşama:** Stage 10.9.6 — Adversarial Financial, Refund, Ledger & Outbox Audit  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Branch: `main`)  
**Nihai Karar:** **`READY_FOR_PILOT_REVIEW`**

---

## 1. YÖNETİCİ ÖZETİ

Stage 10.9.6 kapsamında Core Next mimarisinin en hassas bileşenleri olan **Karma Ödemeler (Split Payments)**, **Kısmi ve Tam İadeler (Refunds)**, **Çift Taraflı Defter (Double-Entry Ledger)**, **Stok Hareketi (Stock Reinstatement)**, **Outbox Kuyruğu (Sync Events)** ve **Rollback Görünürlük Garantileri** bağımsız, izole FFI SQLite testleriyle adversarial (hasmane / sınır zorlayıcı) yöntemlerle denetlenmiştir.

### Temel Doğrulamalar:
1. **Karma Ödeme Kuruş Bütünlüğü (B1):** 100,00 TL'lik bir satışın 33,33 TL nakit, 33,33 TL kredi kartı ve 33,34 TL ikinci kart şeklinde bölünmesinde toplamın tam 10.000 kuruş olduğu, sıfır kuruş kaybı ve sıfır yuvarlama sapmasıyla `sales`, `sale_payments` ve `cash_transactions` tablolarına atomik olarak yazıldığı kanıtlanmıştır.
2. **Kısmi ve Tam İade Stok Korunumu (C):** İade edilen ürün adedinin satılan adedi aşması veya kalan iade edilebilir adedi aşması `StateError` ile engellenmekte; kısmi iadelerde yalnızca iade edilen kadar stok geri alınmakta (`stock_quantity + ?`); tam iadede ise stok orijinal değerine eksiksiz dönmektedir.
3. **Defter ve Bakiye Mutabakatı (D):** `LedgerService` işaret konvansiyonu doğrulanmıştır: Borçlanma bakiyeyi eksiye (`-`), tahsilat artıya (`+`), iade ise alacak yönünde artıya (`+`) işletir. `customers.balance_cents` ile `ledger_entries` hareketlerinin son durumu kuruşu kuruşuna örtüşmektedir.
4. **Outbox ve İşlem Atomikliği (E):** Satış, stok düşümü, ödeme kayıtları, defter kaydı ve outbox mutasyonu (`sync_events`) tek bir SQLite ACID transaction'ı içindedir. Outbox yazımı veya işlem ortasında hata (simüle edilmiş çökme) oluştuğunda **sıfır sızıntı ile tüm tablolar rollback** olmaktadır.
5. **Rollback Görünürlük Tespiti (F):** Feature flag tek başına kapatılırsa Core Next üzerinde yapılmış satışlar Legacy ekranında görünmez; bu nedenle pilot operasyonunda geri dönüş yapılacaksa **`ReverseMigrationEngine.rollbackToLegacy` çalıştırılması zorunlu bir operasyonel kuraldır**.
6. **ERROR Log Açıklaması (G):** Test çıktılarında görülen `❌ [ERROR] error:core_next_bootstrap_coordinator_failure (corr:ERR-...)` loglarının, adversarial testlerde kasıtlı oluşturulan `ReconciliationException` sapmalarının TelemetryService tarafından yakalanıp korelasyon koduyla güvenle kaydedilmesinden kaynaklandığı, sistem çökmesi veya sızıntı olmadığı kanıtlanmıştır.

---

## 2. BAŞLANGIÇ VE BİTİŞ GİT DURUMU

- **Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Branch:** `main`
- **`git diff --check`:** Başarılı (Sıfır hata, sıfır conflict).
- **Mevcut Değişiklikler:**
  - `lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart` (Geliştirilmiş mutabakat kontrolleri)
  - `lib/infrastructure/bootstrap/app_bootstrap.dart` (Teşhis kontrolü)
  - `test/core_next/core_next_bootstrap_coordinator_test.dart` (16 test)
  - `test/core_next/stage10_9_6_financial_adversarial_audit_test.dart` (7 yeni adversarial test)
  - Kullanıcıya ait tüm önceden var olan çalışma ağacı değişiklikleri korunmuştur.

---

## 3. İNCELENEN GERÇEK KOD YOLLARI

1. **Satış ve Checkout:**  
   `core_next/client_core/lib/domain/usecases/checkout_use_case.dart` (`CoreCheckoutUseCase.execute`)  
   - Satır 94-106: Tutar ve ödeme sınır doğrulamaları.  
   - Satır 174-325: Tek atomik SQLite transaction bloğu (Sales + Items + Stock + Payments + Cash + Ledger + Outbox).
2. **İade ve İptal:**  
   `core_next/client_core/lib/domain/usecases/refund_use_case.dart` (`CoreRefundUseCase.execute`)  
   - Satır 146-279: İdempotency ve çakışma ön kontrolü.  
   - Satır 282-364: Önceki iadelerin kümülatif kontrolü ve kalan miktar sınırları.  
   - Satır 555-620: Ters satış kaydı (`status = 'REFUND'`), stok geri alımı (`+ quantity`) ve outbox yazımı.
3. **Çift Taraflı Defter (Ledger):**  
   `core_next/client_core/lib/domain/services/ledger_service.dart` (`LedgerService`)  
   - `postDebitSale`: `newBalance = customer.balance - debtAmount;`  
   - `postCollection`: `newBalance = customer.balance + collectionAmount;`  
   - `postRefund`: `newBalance = customer.balance + refundAmount;`
4. **Koordinatör ve Hata Kaydı:**  
   `lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart`  
   - Satır 584-614: `catch (e, st)` bloğu, `TelemetryService.logError` ve writeLock serbest bırakma.

---

## 4. SATIŞ VE KARMA ÖDEME TEST SONUÇLARI (B1 & B2)

- **Test 1 — Karma Ödeme Kuruş Dağılımı:**  
  100,00 TL tutarındaki ürün için `3333 kuruş Nakit + 3333 kuruş Kart + 3334 kuruş İkinci Kart` parçaları gönderildi.  
  - Sonuç: `paid_cents = 10000`, `total_cents = 10000`, `debt_cents = 0`.  
  - `sale_payments` tablosundaki 3 parçanın toplamı tam 10.000 kuruş olarak doğrulandı.  
  - Kasa nakit hareketine (`cash_transactions`) tam 3.333 kuruş girdi.  
  - Stok tam 1 adet düştü (10 -> 9).  
  - Outbox kuyruğuna (`sync_events`) tek bir mutasyon yazıldı.
- **Test 2 — Sınır Değer İhlalleri (Negatif, Eksik, Fazla):**  
  - Negatif parça tutarı (`-500 kuruş`): `StateError('Ödeme parçası tutarı pozitif olmalıdır')` ile reddedildi.  
  - Eksik ödeme parçası toplamı (`9999 kuruş != 10000 kuruş`): `StateError` fırlatılarak reddedildi.  
  - Fazla ödeme parçası toplamı (`10001 kuruş > 10000 kuruş`): `StateError` fırlatılarak reddedildi.
- **Test 3 — Stok Yetersizliğinde Atomik İptal:**  
  - Stokta 2 adet varken 5 adet satılmak istendi.  
  - Sonuç: `StateError('Yetersiz stok')` fırlatıldı.  
  - `sales`, `sale_payments`, `sync_events` tablolarında 0 kayıt kaldı (Tam rollback). Stok 2 olarak korundu.
- **Test 4 — Satış İdempotency Koruması:**  
  - Aynı istek aynı `idempotencyKey` ile tekrarlandığında mükerrer satış veya mükerrer stok düşüşü yapılmadı; mevcut satış nesnesi döndü.  
  - Aynı `idempotencyKey` ile farklı sepette istek gönderildiğinde `StateError('İdempotency çakışması')` fırlatıldı.

---

## 5. İADE VE STOK GÜVENLİĞİ TEST SONUÇLARI (C)

- **Test 5 — Kısmi ve Tam İade Yaşam Döngüsü:**  
  - 10 adet stoktan 5 adet satıldı (Stok: 5).  
  - 2 adet kısmi iade yapıldı -> Stok 5 + 2 = 7 oldu. İade tutarı 200,00 TL yazıldı.  
  - Kalan 3 adetten fazlası (4 adet) iade edilmek istendiğinde `StateError('iade miktarı, kalan iade edilebilir miktarı (3) aşamaz')` fırlatılarak reddedildi. Stok 7'de sabit kaldı.  
  - Kalan 3 adet iade edildi -> Stok tam 10'a (orijinal seviyesine) döndü. İade tamamlandı.

---

## 6. LEDGER VE MÜŞTERİ BAKİYESİ TEST SONUÇLARI (D)

- **Test 6 — Vadeli Satış, Tahsilat ve İade Zinciri:**  
  - Başlangıç bakiyesi: `0 TL`.  
  - 100,00 TL veresiye satış yapıldı -> Müşteri bakiyesi `-10000 kuruş` (100 TL borç) oldu.  
  - Defterde `debitSale` kaydı oluştu (`balance_after = -10000`).  
  - 40,00 TL nakit tahsilat yapıldı (`postCollection`) -> Bakiye `-10000 + 4000 = -6000 kuruş` (60 TL borç) oldu.  
  - Orijinal 100,00 TL'lik satış için veresiye iadesi yapıldı (`postRefund`) -> Müşterinin 100 TL'lik borcu silindi, ödemiş olduğu 40 TL müşteriye alacak geçti (`balance_cents = +4000 kuruş`).  
  - Defterdeki kronolojik hareketlerin son bakiyesi ile `customers.balance_cents` kuruşu kuruşuna (+4000) eşitlendi.

---

## 7. OUTBOX VE TRANSACTION ATOMİKLİĞİ SONUÇLARI (E)

- **Test 7 — İşlem Ortasında Çökme Simülasyonu:**  
  - `CheckoutFaultHook` ile satış başlığı eklendikten hemen sonra (`after_sales_insert`) kasıtlı `SocketException` fırlatıldı.  
  - Sonuç: SQLite transaction'ı anında geri alındı.  
  - `sales` tablosunda 0 kayıt, `sale_items` tablosunda 0 kayıt, `sync_events` (outbox) tablosunda 0 yetim kayıt kaldı.  
  - Stok düşümü tamamen geri alındı (Stok 10 olarak kaldı).

---

## 8. MIGRATION VE ROLLBACK SONRASI FİNANSAL EŞİTLİK (F)

### Kritik Soru:
**Core Next veritabanına yazılmış bir satış, feature flag kapatıldığında Legacy ekranında görünmez kalabilir mi?**

### Cevap ve Kanıt:
**EVET, EĞER YALNIZCA FEATURE FLAG KAPATILIRSA GÖRÜNMEZ KALIR.**  
- **Nedeni:** `salesControllerProvider` feature flag kapalıyken `serenut_pos.db` üzerindeki Legacy `SalesService`'e bakar. Core Next açıkken yapılan satışlar ise `serenut_core_v2.db` üzerindeki `sales` tablosuna yazılır.  
- **Çözüm ve Garanti:** Bir pilot kullanıcısı Legacy'ye geri döndürülecekse, yalnızca feature flag kapatılmamalı; önce **`ReverseMigrationEngine.rollbackToLegacy(legacyDb: legacyDb, coreDb: coreDb)`** işletilmelidir.  
- `ReverseMigrationEngine`, Core Next'te oluşturulan yeni satışları, parçalı ödemeleri (`sale_payments`) ve cari bakiyeleri Legacy `serenut_pos.db` tablolarına kayıpsız aktarır (Bu davranış `stage10_8_5_reverse_rollback_test.dart` Test 3 ile kanıtlanmıştır).

---

## 9. TEST LOGLARINDAKİ ERROR KAYITLARININ ANALİZİ (G)

Stage 10.9.5'te görülen loglar:
```
❌ [ERROR] error:core_next_bootstrap_coordinator_failure (corr:ERR-3D9E4F)
❌ [ERROR] error:core_next_bootstrap_coordinator_failure (corr:ERR-83C31F)
```
### İnceleme Sonucu:
1. Bu loglar `lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart#L590` satırındaki `TelemetryService().logError(...)` çağrısından üretilmektedir.
2. Test 15 ve Test 16, kasıtlı olarak stok ve bakiye sapması içeren **adversarial karşı örnek** testleridir. Koordinatör bu sapmaları yakalayıp `ReconciliationException` fırlattığında `catch` bloğu çalışmakta ve telemetri servisine korelasyon referansıyla bildirim düşmektedir.
3. Bu bir sistem hatası veya çökme değildir; sistemin fail-closed korumasının başarıyla devreye girdiğini ve telemetrinin çalıştığını gösteren beklenen bir davranıştır.
4. `finally` bloğu ve `catch` içinde `DatabaseManager.isWriteLocked = false;` ve `_isExecutionRunning = false;` çalışarak hiçbir kilit veya bağlantı sızıntısı bırakmamaktadır.

---

## 10. ÇALIŞTIRILAN TEST KOMUTLARI VE GERÇEK SONUÇLAR

| Test Paketi | Test Sayısı | Sonuç | Doğrulanan Alan |
|---|:---:|:---:|---|
| `test/core_next/stage10_9_6_financial_adversarial_audit_test.dart` | 7 | **PASS** | Karma ödeme, eksik/fazla ödeme engeli, stok rollback, kısmi iade, ledger, outbox atomikliği |
| `test/core_next/core_next_bootstrap_coordinator_test.dart` | 16 | **PASS** | Açılış koordinatörü, WAL checkpoint, münferit ürün/stok/bakiye mutabakatı |
| `test/core_next/checkout_use_case_test.dart` | 7 | **PASS** | Tartılı terazi, yarım-yukarı kuruş yuvarlama, veresiye borç |
| `test/core_next/stage10_8_5_reverse_rollback_test.dart` | 5 | **PASS** | Reverse-rollback provası, kuruş sınır değerleri, SQLite PRAGMA bütünlüğü |
| `test/core_next/stage10_8_10_runtime_audit_test.dart` | 4 | **PASS** | In-place UPSERT, iade idempotency, karma ödeme roundtrip |
| `test/core_next/stage10_8_11_runtime_audit_test.dart` | 18 | **PASS** | 18 Adversarial senaryo, ACID rollback, Türkçe harf desteği |
| `test/core_next/stage10_8_12_financial_reconciliation_audit_test.dart` | 6 | **PASS** | Bağımsız defter mutabakatı, atomik transaction izolasyonu |
| `test/ui/stage10_8_2_sales_controller_e2e_test.dart` | 4 | **PASS** | UI controller feature flag izolasyonu, fail-closed StateError |
| **TOPLAM** | **67** | **%100 PASS** | **Sıfır Hata, Sıfır Regresyon** |

---

## 11. BULGULARIN SINIFLANDIRILMASI

- **BLOCKER:** Yok.
- **HIGH:** Geri dönüş (Rollback) senaryosunda feature flag kapatılmadan önce `ReverseMigrationEngine.rollbackToLegacy` çalıştırılması zorunludur. Aksi takdirde Core Next'te kesilen satışlar Legacy ekranda görünmez. (Operasyonel runbook'a kural olarak işlenmelidir).
- **MEDIUM:** Yok.
- **LOW:** Telemetri loglarında beklenen test hataları ile gerçek çalışma zamanı hatalarının log öneki ayrıştırılabilir (Gözlemlenebilirlik iyileştirmesi).

---

## 12. DÜZELTİLEN DOSYALAR VE EKLENEN REGRESYON TESTLERİ

- **`test/core_next/stage10_9_6_financial_adversarial_audit_test.dart`:** 7 yeni adversarial finansal, stok, iade ve outbox testi eklendi.
- **`lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart`:** Münferit ürün ve cari eşleştirme döngüleri korundu.

---

## 13. AÇIK KALAN RİSKLER

- Canlı pilot sırasında bir cihazda Core Next devredeyken elektrik kesintisi veya ani kapanma yaşanması durumunda, cihaz yeniden açıldığında SQLite WAL recovery otomatik çalışacaktır. Bu davranış Stage 10.8.11 Test 15 (Disk Persistence) ile doğrulanmıştır.

---

## 14. BİR SONRAKİ AŞAMA İÇİN GÖREV LİSTESİ (STAGE 10.9.7)

1. **Rollback Orchestrator Entegrasyonu:** Feature flag kapatıldığında otomatik olarak `ReverseMigrationEngine.rollbackToLegacy` tetikleyen güvenlik kilidinin UI ayarlarına bağlanması.
2. **Kademeli Pilot Çalıştırma:** İlk pilot mağazasında kontrollü başlatma.

---

## 15. NİHAİ KARAR

# **`READY_FOR_PILOT_REVIEW`**

Tüm finansal kuruş hesaplamaları, karma ödeme dağılımları, kısmi/tam iade stok geri alımları, defter mutabakatı ve outbox atomikliği 67 bağımsız test ile doğrulanmış ve kanıtlanmıştır.
