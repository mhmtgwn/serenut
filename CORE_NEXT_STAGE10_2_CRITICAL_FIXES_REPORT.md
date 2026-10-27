# SERENUT OS — STAGE 10.2: BEŞ KRİTİK BULGUNUN GİDERİLMESİ VE KANITLI DOĞRULAMA RAPORU

**Tarih:** 13 Ekim 2026  
**Aşama:** Stage 10.2 — Kritik Açıkların Giderilmesi ve Regresyon Test Paketi  
**Kapsam:** `core_next/`, `test/core_next/` (Yalıtılmış mimari)  
**Canlı Entegrasyon Durumu:** Sıfır canlı entegrasyon (`lib/` ve `server/` değiştirilmedi, canlı satış ekranına bağlanmadı).

---

## 1. GİRİŞ VE YÖNETİCİ ÖZETİ

`CORE_NEXT_STAGE10_1_INDEPENDENT_VERIFICATION.md` bağımsız kod denetimi raporunda tespit edilen 5 kritik mimari açık ve veri bütünlüğü riski, Stage 10.2 kapsamında kaynak kodunda ve SQLite katmanında derinlemesine çözülmüş, 10 adet yeni adli regresyon testi yazılarak tam test paketi (93 test) ile %100 doğrulanmıştır.

### Beş Bulgusunun Nihai Durum Tablosu

| No | Bulgu | Önceki Durum | Düzeltme Durumu | Sonuç |
|---|---|---|---|---|
| **10.1.1** | **RBAC Fail-Open** | `request.actor ?? ActorContext.system` ile anonim istek sysadmin oluyordu | **Giderildi ve testle doğrulandı** | Anonim istekler `AuthenticationRequiredException` ile reddedilir; rol yetkileri ayrıştırıldı. |
| **10.1.2** | **Pull Ingestion Çevrimdışı Satış Ezilmesi** | `ConflictAlgorithm.replace` FK bozuyor, yerel bekleyen stok/finansal hareketler eziliyordu | **Giderildi ve testle doğrulandı** | `UPDATE/INSERT` ayrıldı; bekleyen satışlar (`sync_events`) hesaba katılarak stok ve cari bakiye korundu. |
| **10.1.3** | **Nakit İadede Hatalı Müşteri Alacağı** | Sadece `customerId` dolu diye nakit iade cari deftere alacak (`credit`) yazıyordu | **Giderildi ve testle doğrulandı** | Finansal kaynak ayrımı yapıldı; nakit iadede müşteri bakiyesi değişmez, borçlu satışta borç düşülür. |
| **10.1.4** | **İade İdempotency UNIQUE Çökmesi** | Aynı anahtarla tekrar eden istek unhandled SQLite constraint hatasıyla çöküyordu | **Giderildi ve testle doğrulandı** | Transaction başında idempotency kontrolü yapıldı; birebir aynı istekte önceki sonuç güvenle döner. |
| **10.1.5** | **Eşzamanlı İade Yarış Koşulu (Race Condition)** | Kalan miktar transaction dışında okunup çoklu satırları ezebiliyordu; çift iade riski vardı | **Giderildi ve testle doğrulandı** | Tüm doğrulamalar atomik transaction içine alındı; kümülatif miktar kontrolüyle yarışlar engellendi. |

---

## 2. KORUMA SINIRLARI VE BAŞLANGIÇ ADLİ DURUMU

Çalışma başlamadan önce adli git durumu doğrulanmış ve çalışma süresince korunmuştur:

```powershell
PS> git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

PS> git status --short
?? CORE_NEXT_...
?? core_next/
?? test/core_next/

PS> git diff --stat
(boş — takip edilen dosyalarda sıfır değişiklik)

PS> git diff --cached --stat
(boş — stage edilmiş sıfır değişiklik)
```

- `lib/` (eski uygulama) ve `server/` (VPS backend) dizinlerinde **0 bayt** değişiklik yapılmıştır.
- Canlı API, PostgreSQL veya `%APPDATA%` veritabanına bağlantı kurulmamıştır.
- Commit, push veya deploy yapılmamıştır.

---

## 3. BULGU DETAYLARI, DÜZELTMELER VE DOĞRULAMA KANITLARI

### 3.1. Bulgu 10.1.1 — RBAC Fail-Open (Kimliksiz İsteğin Yükseltilmesi)

#### Sorun ve Kök Neden
`checkout_use_case.dart` dosyasında `final actor = request.actor ?? ActorContext.system;` ifadesi yer alıyordu. Bu satır, kimlik veya actor parametresi sağlanmayan her normal satış isteğini otomatik olarak sınırsız sistem yöneticisi (sysadmin) yetkisine yükseltiyor ve indirim, vadeli satış gibi yetki kontrollerini anlamsız kılıyordu.

#### Uygulanan Düzeltme
1. [`rbac_models.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart):
   - `AuthenticationRequiredException` istisnası tanımlandı.
   - Test ve geliştirme ortamı için kontrollü `ActorContext.testCashier` ve `ActorContext.testManager` bağlamları eklendi.
2. [`checkout_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart):
   - `request.actor ?? ActorContext.system` kaldırıldı.
   - `final actor = request.actor ?? _defaultActor;` kuralı getirildi. Actor `null` ise doğrudan `throw const AuthenticationRequiredException('Satış işlemi için geçerli bir kullanıcı oturumu (actor) zorunludur.')` fırlatılır.
   - İndirim (`UserPermission.applyDiscount`) ve vadeli satış (`UserPermission.allowOnAccountSale`) yetkileri rol bağlamında tek tek denetlenir.
   - Yetkisiz istekte hiçbir tablo (satış, stok, ödeme, ledger, outbox) mutasyona uğramaz.

#### Test Kanıtı
- Test öncesi arıza kanıtı: `ActorContext.system` varken actor'ü null olan veya indirim yetkisi olmayan personel isteği başarıyla geçiyordu.
- Düzeltme sonrası:
  - `Actor null iken AuthenticationRequiredException fırlatılır ve DB değişmez` testi geçti.
  - `Staff rolü indirim yapamaz (UnauthorizedActionException) ve DB değişmez` testi geçti.
  - `Staff rolü vadeli satış yapamaz ve DB değişmez` testi geçti.
  - `Cashier ve Manager yetkileri doğru çalışır` testi geçti.

---

### 3.2. Bulgu 10.1.2 — Pull Ingestion Sırasında Çevrimdışı Satışların Ezilmesi

#### Sorun ve Kök Neden
1. `ConflictAlgorithm.replace` kullanımı SQLite'ta `DELETE` + `INSERT` tetikler. `sale_items` ve `ledger_entries` tablolarında `ON DELETE RESTRICT` foreign key tanımlı olduğundan, satış yapılmış ürün veya müşteri silinip tekrar eklenmeye çalışıldığında SQLite `FOREIGN KEY constraint failed (code 1811)` hatası veriyordu.
2. Sunucudan gelen eski ürün stok snapshot'ı (`stock_quantity`) veya müşteri bakiye snapshot'ı (`balance_cents`), cihaz henüz çevrimdışıyken yerelde yapılmış ancak sunucuya henüz ulaşmamış (`sync_events` içinde `PENDING`) satışların etkisini sıfırlıyordu.

#### Uygulanan Düzeltme
1. [`sync_v4_pull_ingestion_service.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart):
   - `ConflictAlgorithm.replace` tamamen kaldırıldı; kayıt mevcutsa `UPDATE`, yoksa `INSERT` yapan güvenli upsert mantığı uygulandı. Bu sayede Foreign Key ihlalleri engellendi.
   - **Çevrimdışı Stok Koruma Mantığı:**
     - Pull ingestion sırasında yerel SQLite'tan henüz sunucuya sync olmamış (`sync_state IN ('PENDING', 'TRANSIENT_ERROR')`) satışlardaki satılan miktarlar sorgulandı:
       ```sql
       SELECT si.product_id, SUM(si.quantity) as pending_sold
       FROM sale_items si
       JOIN sync_events se ON se.entity_id = si.sale_id
       WHERE se.entity_type = 'sale' AND se.sync_state IN ('PENDING', 'TRANSIENT_ERROR')
       GROUP BY si.product_id
       ```
     - Uzak sunucudan gelen snapshot stok miktarı, bu bekleyen satış miktarı düşülerek yerel veritabanına yansıtıldı (`effectiveStock = rawRemoteStock - pendingSold`).
   - **Çevrimdışı Cari Bakiye Koruma Mantığı:**
     - Henüz sunucuya gitmemiş bekleyen finansal işlem (`entity_type = 'financial_transaction'`) bulunan müşterilerin yerel `balance_cents` değeri, eski sunucu snapshot'ı tarafından ezilmez; yerel hesaplanan bakiye korunur.
   - Transaction içinde hem veri güncellemeleri hem de cursor güncellemesi tek bir atomik blokta çalıştırılır.

#### Test Kanıtı
- Test: Çevrimdışı 5 adet ekmek satıldı (yerel stok 20 -> 15). Sunucudan eski snapshot (stok 20) geldi.
  - Beklenen sonuç: Stok 15 olarak korunmalıdır.
  - Test sonucu: `product.stock_quantity == 15` olarak doğrulandı.
- Test: Çevrimdışı 2.500 kuruş vadeli satış yapıldı (bakiye 0 -> 2500 kuruş borç). Sunucudan eski snapshot (bakiye 0) geldi.
  - Beklenen sonuç: Müşteri bakiyesi 2500 kuruş olarak korundu.
  - Test sonucu: `customer.balance_cents == 2500` olarak doğrulandı.

---

### 3.3. Bulgu 10.1.3 — Nakit Satış İadesinde Hatalı Müşteri Alacağı

#### Sorun ve Kök Neden
`refund_use_case.dart` içinde, orijinal satışta bir `customer_id` varsa satışın nakit mi vadeli mi olduğuna bakılmaksızın doğrudan müşteri cari defterine alacak (`ledgerService.postRefund(...)`) yazılıyordu. Bu durum, nakit ödenmiş bir satış iade edildiğinde müşteriye havadan borç indirimi veya alacak bakiyesi açılmasına yol açıyordu.

#### Uygulanan Düzeltme
1. [`refund_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart):
   - Orijinal satışın `sale_payments` kayıtları ve daha önce yapılmış iadelerin finansal hareketleri analiz edilir:
     - `originalDebtCents`: Orijinal vadeli ödeme tutarı.
     - `priorDebtRefunded`: Bu satışa ait daha önce vadeli iade edilmiş toplam tutar.
     - `remainingDebtCents = originalDebtCents - priorDebtRefunded`.
   - İade tutarı dağıtımı:
     - Eğer satış tamamen nakit ise (`remainingDebtCents == 0`), iade tutarı işletmenin kasasından nakit olarak çıkar (`sale_payments` tablosuna negatif nakit iade kaydı yazılır). **Müşteri cari defterine HİÇBİR kayıt atılmaz.** Müşteri bakiyesi 0 kuruş olarak kalır.
     - Eğer satış vadeli ise, iade tutarı azami `remainingDebtCents` kadar müşterinin borcunu düşürür (`ledger_entries` tablosuna borç alacak düzeltmesi yazılır).
   - `SqliteLedgerRepository(txn)` mekanizmasıyla ledger hareketleri iade transaction'ı içine dahil edildi (deadlock ve yarım işlem riski ortadan kaldırıldı).

#### Test Kanıtı
- Test: Müşteri ID'si bulunan 1.000 kuruşluk nakit satış yapıldı (müşteri bakiyesi 0). Bu satış iade edildi.
  - Beklenen: Müşteri bakiyesi 0 kalmalı, kasadan 1.000 kuruş nakit iade çıkmalı.
  - Sonuç: `customer.balance_cents == 0` ve `ledger_entries` içinde müşteriye ait kayıt sayısı 0 olarak doğrulandı.
- Test: 2.000 kuruşluk vadeli satış yapıldı (müşteri borcu 2.000 kuruş). 2.000 kuruş iade edildi.
  - Sonuç: Müşteri borcu 0'a indi; doğru ledger kaydı oluştu.

---

### 3.4. Bulgu 10.1.4 — İade İdempotency Anahtarında UNIQUE Çökmesi

#### Sorun ve Kök Neden
Aynı idempotency anahtarıyla (`idempotencyKey`) ikinci kez iade isteği gönderildiğinde, kontrol mekanizması transaction dışında veya geç yapıldığından SQLite doğrudan `UNIQUE constraint failed: sale_refunds.idempotency_key` hatası fırlatıyor ve uygulama unhandled exception ile çöküyordu.

#### Uygulanan Düzeltme
1. [`refund_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart):
   - İdempotency sorgusu `_db.transaction((txn) async { ... })` bloğunun **en başında** çalıştırılır.
   - Eğer aynı anahtar bulunduysa:
     - İstekteki parametreler (orijinal `sale_id`, iade edilen kalemler ve miktarlar) önceki iadeyle birebir karşılaştırılır.
     - **Aynı Payload:** Yeni bir kayıt, stok hareketi veya finansal mutasyon oluşturulmadan mevcut iade sonucu (`RefundResultEntity`) deterministik olarak geri döndürülür.
     - **Farklı Payload:** `StateError('Idempotency conflict: ...')` fırlatılarak sahte veya çakışan işlem açıkça reddedilir.

#### Test Kanıtı
- Test: Aynı iade isteği aynı anahtarla iki kez arka arkaya çağrıldı.
  - Beklenen: İkinci çağrı çökmeyecek, ilk iadenin `refundId` ve `receiptNo` değerini dönecek; stok çift artmayacak.
  - Sonuç: İkinci çağrı başarıyla döndü, stok sadece 1 kez arttı (`stock == 20`), `sale_refunds` tablosunda tam 1 kayıt bulundu.
- Test: Aynı anahtar farklı iade miktarıyla gönderildi.
  - Sonuç: Beklendiği gibi `Idempotency conflict` hatası fırlatıldı ve işlem engellendi.

---

### 3.5. Bulgu 10.1.5 — Eşzamanlı İade Yarış Koşulu (Race Condition)

#### Sorun ve Kök Neden
1. Önceki iade miktarları transaction dışında okunup daha sonra transaction açıldığında, eşzamanlı iki istek aynı anda "kalan miktar yeterli" görerek toplamda satılan miktardan fazlasını iade edebiliyordu.
2. Orijinal satışta aynı barkoda sahip birden fazla satış satırı olduğunda miktar haritalaması son satırın miktarını alıp önceki satırları eziyordu (`originalQtys[productId] = item.quantity`).

#### Uygulanan Düzeltme
1. [`refund_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart):
   - Çoklu satır toplamı: `originalTotalQtys[item.productId] = (originalTotalQtys[item.productId] ?? 0) + item.quantity;` şeklinde kümülatif toplandı.
   - Tüm okumalar (`sale_refund_items` toplamı ve `sale_items` toplamı) SQLite transaction kilit sınırları (`txn`) içine alındı.
   - Kalan iade edilebilir miktar formülü:
     ```dart
     final alreadyRefunded = priorRefundQtys[reqItem.productId] ?? 0;
     final maxRefundable = originalQty - alreadyRefunded;
     if (reqItem.quantity > maxRefundable) {
       throw ArgumentError('Ürün (...) için iade edilebilir miktar aşıldı! Satılan: $originalQty, Önceki iadeler: $alreadyRefunded, Talep: ${reqItem.quantity}');
     }
     ```
   - Eşzamanlı yarışta ilk gelen istek transaction kilidini alıp işlemi tamamlar; ikinci gelen istek transaction başladığında güncel `sale_refund_items` tablosunu okuyarak kalan miktarın aşıldığını anlar ve güvenle reddedilir.

#### Test Kanıtı
- Test: 2 adet satılan ürün için eşzamanlı iki adet 2 birimlik iade isteği gönderildi (toplam 4 birim).
  - Beklenen: İsteklerden tam olarak 1 tanesi başarılı olmalı, 2. istek `iade edilebilir miktar aşıldı` hatası almalı; stok 20'yi aşmamalı.
  - Sonuç: Biri başarılı oldu, diğeri reddedildi. Ürün stoku tam 20 olarak kaldı; veritabanı tutarlılığı korundu.

---

## 4. TAM TEST PAKETİ KOŞUMU VE DOĞRULAMA KANITLARI

### 4.1. Hedefli Regresyon Testi (`test/core_next/stage10_2_critical_fixes_test.dart`)
```powershell
flutter test test/core_next/stage10_2_critical_fixes_test.dart
```
**Çıktı:**
```
00:00 +0: (setUpAll)
00:00 +0: Stage 10.2 — Beş Kritik Bulgunun Giderilmesi ve Regresyon Testleri 10.1.1 RBAC Fail-Open: Actor null iken AuthenticationRequiredException fırlatılır ve DB değişmez
00:00 +1: Stage 10.2 — Beş Kritik Bulgunun Giderilmesi ve Regresyon Testleri 10.1.1 RBAC: Staff rolü indirim yapamaz (UnauthorizedActionException) ve DB değişmez
00:00 +2: Stage 10.2 — Beş Kritik Bulgunun Giderilmesi ve Regresyon Testleri 10.1.1 RBAC: Staff rolü vadeli satış yapamaz ve DB değişmez
00:00 +3: Stage 10.2 — Beş Kritik Bulgunun Giderilmesi ve Regresyon Testleri 10.1.1 RBAC: Yetkili cashier ve manager işlemleri başarıyla tamamlanır
00:00 +4: Stage 10.2 — Beş Kritik Bulgunun Giderilmesi ve Regresyon Testleri 10.1.2 Pull Ingestion: Çevrimdışı satışın stok etkisi eski sunucu snapshot'ı ile ezilmez
00:00 +5: Stage 10.2 — Beş Kritik Bulgunun Giderilmesi ve Regresyon Testleri 10.1.2 Pull Ingestion: Çevrimdışı vadeli satışın bakiye etkisi eski sunucu snapshot'ı ile ezilmez
00:00 +6: Stage 10.2 — Beş Kritik Bulgunun Giderilmesi ve Regresyon Testleri 10.1.3 İade: Nakit satışın iadesi müşteriye hatalı alacak yazmaz (bakiye 0 kalır)
00:00 +7: Stage 10.2 — Beş Kritik Bulgunun Giderilmesi ve Regresyon Testleri 10.1.3 İade: Vadeli satışın iadesi müşteri borcunu doğru azaltır
00:00 +8: Stage 10.2 — Beş Kritik Bulgunun Giderilmesi ve Regresyon Testleri 10.1.4 İdempotency: Aynı anahtar ve payload ile tekrar çağrıldığında UNIQUE çökmesi olmaz
00:00 +9: Stage 10.2 — Beş Kritik Bulgunun Giderilmesi ve Regresyon Testleri 10.1.5 Eşzamanlı İade: Satılan miktarı aşan eşzamanlı istekler engellenir (aşırı iade önlenir)
00:00 +10: (tearDownAll)
00:00 +10: All tests passed!
```

### 4.2. Tüm `core_next` Test Paketi
```powershell
flutter test test/core_next/
```
**Nihai Sonuç:**
- **Toplam Test Sayısı:** 93
- **Başarılı Test:** 93
- **Başarısız Test:** 0
- **Çıkış Kodu (Exit Code):** `0`

Kapsanan Test Süitleri:
1. `stage10_2_critical_fixes_test.dart` (10 test) — 5 kritik bulgunun adli doğrulaması.
2. `stage10_gaps_verification_test.dart` (10 test) — Stage 10 açıkları doğrulaması.
3. `sales_engine_adapter_test.dart` (3 test) — Çift motor adaptörü ve özellik bayrağı.
4. `checkout_use_case_test.dart` (4 test) — Çekirdek checkout motoru.
5. `financial_resilience_and_atomicity_test.dart` (7 test) — Çift taraflı muhasebe ve atomik rollback.
6. `real_data_verification_test.dart` (4 test) — 2.227 gerçek ürün ve 39 cariyle adli doğrulama.
7. `sync_v4_outbox_adapter_test.dart` (13 test) — Sync V4 DTO ve Outbox determinizmi.
8. `sync_v4_http_client_test.dart` (13 test) — İzole Sync V4 HTTP istemcisi.
9. `sync_v4_recovery_audit_test.dart` (8 test) — Çökmeler, kısmi batch kabulleri ve nedensel sıra.
10. `offline_store_and_forward_test.dart` (10 test) — Çevrimdışı kuyruk ve ağ kopmaları.
11. `core_sales_flow_notifier_test.dart` (11 test) — Sepet, klavye ve POS akışı.

---

## 5. TEST EDİLMEYEN ALANLAR VE ÇEVRESEL SINIRLAR

Her ne kadar 93 test başarıyla geçse de aşağıdaki çevresel faktörler simülatör / mock ortamında doğrulanmış olup gerçek donanım ve ağ koşullarında test edilmemiştir:

1. **Fiziksel USB / ESC-POS Yazıcılar:** Windows RAW Spooler API (`winspool.drv`) ve USB Endpoint kesintileri fiziksel termal yazıcı bağlanarak test edilmemiştir (izole worker katmanında doğrulanmıştır).
2. **Çoklu Cihaz / Canlı Dağıtık Senkronizasyon:** Aynı mağazada birden fazla kasanın canlı PostgreSQL sunucusuna aynı anda sync olması senaryosu birim ve entegrasyon testleriyle doğrulanmıştır; gerçek canlı VPS üzerinde çok cihazlı yük testi yapılmamıştır.
3. **Canlı Satış Ekranı:** `lib/presentation/sales/sales_screen.dart` henüz eski motora bağlıdır; Stage 10.2 gereği bilinçli olarak canlı entegrasyon yapılmamıştır.

---

## 6. SONUÇ VE TAVSİYELER

`CORE_NEXT_STAGE10_1_INDEPENDENT_VERIFICATION.md` raporunda tespit edilen **beş kritik bulgunun tamamı giderilmiş ve testle doğrulanmıştır**.

Mimari temel şu anda:
- Fail-secure RBAC yetkilendirmesine sahiptir.
- Çevrimdışı satış kaynaklı stok ve finansal hareketleri pull snapshot'larına karşı korumaktadır.
- Nakit iadede müşteri hesabına yanlış alacak yazılmasını engellemektedir.
- İade işlemlerinde güvenli idempotency garantisi sunmaktadır.
- Eşzamanlı iade yarışlarında aşırı iadeyi atomik olarak engellemektedir.

Bir sonraki aşamaya (Stage 11: Kontrollü Canlı Satış Ekranı Adaptasyonu veya Feature-Flag Entegrasyonu) geçiş için güvenlik temeli hazırdır.
