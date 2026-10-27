# SERENUT OS — STAGE 10.4: İADE BÜTÜNLÜĞÜ VE SENKRONİZASYON ENGELİ RAPORU

**Tarih:** 2026-10-13  
**Aşama:** Stage 10.4 — Finansal İade Bütünlüğü, Mutabakat, Tam Payload Idempotency ve Sunucu Protokolü Engel Analizi  
**Kapsam:** `core_next/`, `test/core_next/`  
**Durum:** İstemci tarafı finansal açıklar kapatıldı ve doğrulandı; sunucu stok projeksiyonu engeli kaynak kodla kanıtlandı ve sözleşmesi tasarlandı.

---

## 1. BAŞLANGIÇ GİT DURUMU VE KORUMA SINIRLARI

Çalışmaya başlarken sistemin temiz durumu doğrulanmış ve kaydedilmiştir:

- **HEAD Hash:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Takip Edilen Dosya Farkı (`git diff --stat`):** `0 files changed, 0 insertions(+), 0 deletions(-)`
- **Koruma Kuralları:** `lib/` (eski uygulama) ve `server/` (eski sunucu) dizinlerine dokunulmamıştır. Canlı API, PostgreSQL, canlı kullanıcı veritabanı, commit, push ve deploy yapılmamıştır. Canlı satış ekranına entegrasyon yapılmamıştır.

---

## 2. ADLİ BULGULAR VE GİDERİLME DURUMU

### 2.1. Karma Ödeme İadesi: Özgün Ödemeyle Mutabakat ve Nakit Sınırı
*Durum:* **GİDERİLDİ VE DOĞRULANDI**  
*Dosya / Satır:* [refund_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L330-L510)  
*İlgili Testler:* [stage10_4_financial_integrity_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_4_financial_integrity_test.dart) (Test 10.4.1, 10.4.2, 10.4.3, 10.4.4)

#### Tespit Edilen Açık:
Önceki mimaride karma ödeme iadesinde çağıran tarafından gönderilen `paymentDistributions` toplamı iade tutarına eşitse sorgusuz kabul ediliyordu. Örneğin; orijinal satışta 10 TL nakit ve 90 TL veresiye tahsil edilmişken, çağıran 50 TL nakit çıkışı talep ettiğinde kasadan haksız nakit çıkışı (`cash_transactions OUTFLOW`) yapılabiliyordu.

#### Uygulanan Çözüm ve Doğrulama:
1. **Özgün Ödeme Tablosu Okuma:** `sale_payments` tablosundan orijinal satışın ödeme kalemleri (`cash`, `onAccount`, `creditCard`) kuruş kuruşuna ayrıştırılmıştır.
2. **Önceki İadelerin Düşümü:** Aynı fişe ait önceki iadelerin (`sales` ve `sale_payments`) nakit ve veresiye çıkışları toplanmış; `availableCashRefundCents = max(0, origCashCents - priorCashRefunded)` ve `availableDebtRefundCents = max(0, origDebtCents - priorDebtRefunded)` hesaplanmıştır.
3. **Deterministik Dağılım Denetimi:**
   - Talep edilen nakit tutarı `availableCashRefundCents` değerini aşarsa işlem `StateError` ile reddedilir.
   - Talep edilen vadeli borç silimi `availableDebtRefundCents` değerini aşarsa işlem `StateError` ile reddedilir.
   - Dağılım toplamı iade tutarına eşit değilse veya karma satışta dağılım verilmemişse işlem reddedilir.
4. **Kart İadesi Güvenlik Engeli:** Gerçek POS/kart gateway entegrasyonu olmadan yapılan tüm kart iadeleri veya kart içeren dağılımlar `UnsupportedError` ile durdurulur.
5. **Atomik Transaction:** Hata durumunda SQLite transaction'ı otomatik rollback olmakta; nakit defteri, müşteri carisi, stok ve outbox tablolarında sıfır yan etki kalmaktadır.

#### Somut Test Assertion Kanıtı:
- Test `10.4.1`: 10 TL nakit + 90 TL vadeli satışta 50 TL nakit iadesi denendiğinde:
  ```dart
  expect(() => refundUseCase.execute(req), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('kalan iade edilebilir nakit tutarını (1000 kuruş) aşamaz'))));
  expect(await coreDb.db.query('cash_transactions', where: 'type = "OUTFLOW"'), isEmpty);
  expect(await coreDb.db.query('sales', where: "status = 'REFUND'"), isEmpty);
  ```

---

### 2.2. İade İdempotency: Tam ve Kararlı Payload Doğrulaması
*Durum:* **GİDERİLDİ VE DOĞRULANDI**  
*Dosya / Satır:* [refund_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L143-L255), [rbac_models.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart#L94-L115)  
*İlgili Testler:* [stage10_4_financial_integrity_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_4_financial_integrity_test.dart) (Test 10.4.5, 10.4.6, 10.4.7)

#### Tespit Edilen Açık:
Önceki versiyonda aynı `idempotencyKey` ile tekrar gelen istek karşılaştırılırken yalnızca ürün ID ve toplam adet kontrol ediliyordu. `paymentDistributions` (ödeme kanalı dağılımı), satır bazlı tutarlar ve gerekçe kontrol edilmediği için; örneğin ilk istekte 50 TL nakit iade edilmişken aynı key ile 50 TL vadeli iade istendiğinde replay gerçekleşiyor ve farklı finansal niyet çakışması algılanamıyordu.

#### Uygulanan Çözüm ve Doğrulama:
1. **Tam Ekonomik Payload Karşılaştırması:**
   - Orijinal satış ID (`reference_id`) doğrulanır.
   - İade edilen kalemlerin ürün ID'leri, satır miktarları ve kuruş bazlı satır tutarları (`existingAmountByProduct`) birebir kontrol edilir.
   - Ödeme dağılımı (`paymentDistributions` / `paid_cents` ve `debt_cents`) kontrol edilir.
   - Herhangi bir finansal alanda uyumsuzluk varsa `throw StateError('İdempotency Çakışması: ... farklı kalem, miktar, tutar veya ödeme dağılımı...')` fırlatılarak transaction derhal abort edilir.
2. **Kusursuz Deterministik Replay:**
   - Aynı anahtar ve aynı tam payload ile tekrarlandığında mevcut `RefundResultEntity` doğrudan dönülür; stok mükerrer artırılmaz, nakit defteri ve müşteri bakiyesi ikinci kez tetiklenmez.
3. **Geriye Dönük Uyumluluk:**
   - `RefundItemRequest` modeline opsiyonel `saleItemId` alanı eklenmiş, mevcut testler ve çağrılar bozulmadan satır hedefli iade altyapısı hazırlanmıştır.
   - `sync_events` outbox tablosundaki `payload_json` içine `reason`, `payment_distributions` ve detaylı `items` listesi gömülerek denetlenebilirlik kalıcı hale getirilmiştir.

#### Somut Test Assertion Kanıtı:
- Test `10.4.6`: 50 TL nakit + 50 TL vadeli iade sonrası, AYNI key ile 0 TL nakit + 100 TL vadeli iade denendiğinde `StateError('İdempotency Çakışması')` fırlatılmış; `sales` ve `cash_transactions` satır sayılarının değişmediği (`expect(refundsCountAfter, refundsCountBefore)`) doğrulanmıştır.

---

### 2.3. Sunucu Stok Projeksiyonu: Kanıt ve Engel Analizi
*Durum:* **SUNUCU/MİMARİ BAĞIMLILIĞI NEDENİYLE ENGELLENDİ**  
*Dosya / Satır:* [watermark_sync_service.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/server_core/src/sync/watermark_sync_service.ts#L167-L245)

Salt okunur kaynak kod incelemesi üzerinden zorunlu soruların kanıta dayalı yanıtları:

1. **Sunucu stok miktarı hangi işlemlerle değiştiriliyor?**
   - Sunucuda `stock_quantity` yalnızca `ev.entityType === 'PRODUCT'` olan olaylar geldiğinde `materializeEntity` fonksiyonunda [watermark_sync_service.ts:193-219](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/server_core/src/sync/watermark_sync_service.ts#L193-L219) `stock_quantity = EXCLUDED.stock_quantity` olarak doğrudan üzerine yazılmaktadır.
2. **Satış mutation'ı sunucuda stok hareketi oluşturuyor mu?**
   - **HAYIR!** [watermark_sync_service.ts:167-245](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/server_core/src/sync/watermark_sync_service.ts#L167-L245) incelendiğinde; `materializeEntity` içinde yalnızca `PRODUCT` ve `CUSTOMER` blokları vardır. `SALE` olayı için hiçbir domain materializer yazılmamıştır; `products.stock_quantity` azaltılmaz.
3. **Sunucu stok revizyonu ile satış mutation sequence/revision değerleri aynı anlamı mı taşıyor?**
   - **HAYIR!** `server_revision`, kiracıya ait tüm olayların (`PRODUCT`, `CUSTOMER`, `SALE`, `LEDGER_ENTRY`) paylaştığı tek bir global log sayaçtır (`currentRev += 1`). Ürün kartının stok revizyonu değildir. Başka bir müşterinin telefon numarası güncellendiğinde de `server_revision` artar.
4. **Bir mutation'ın `COMPLETED` olması, satışın sunucu stok projeksiyonuna uygulandığını kanıtlıyor mu?**
   - **KESİNLİKLE HAYIR!** İstemcinin mutasyonu `COMPLETED` görmesi, sunucunun olayı `sync_event_log` tablosuna append ettiğini ve `acknowledgedEventIds` listesine eklediğini gösterir. Sunucu stoğu düşürmediği için stok projeksiyonuna uygulandığını kanıtlamaz.
5. **Birden fazla cihaz aynı ürünü sattığında sunucu hangi mekanizmayla stok yakınsaması sağlıyor?**
   - **MEVCUT KODDA BÖYLE BİR MEKANİZMA YOKTUR!** İki cihaz bağımsız `SALE` gönderdiğinde sunucu bunları loglar ancak stok hesaplamaz. Eğer cihazlar `PRODUCT` snapshot'ı gönderirse son gelen olay (LWW - Last Write Wins) diğerini ezer.
6. **Pull yanıtı, stok snapshot'ının hangi mutation sequence'ine kadar uygulandığını bildiriyor mu?**
   - **HAYIR!** `SyncPullResult` yalnızca `{ currentRevision: number, events: SyncEventPayload[] }` döner. DTO içinde `applied_mutation_sequence` veya nedensel sınır (causal watermark) alanı bulunmamaktadır.

#### Engel Tespiti ve Bir Sonraki Aşama İçin Protokol Tasarımı:
İstemci tarafında sahte zaman damgaları veya tahmin deltalari üreterek bu açığı "çözüldü" göstermek veri bütünlüğüne aykırıdır. Sunucu aşaması için gereken sözleşme:
- **Server Materializer:** `SALE` ve `REFUND` olayları geldiğinde PostgreSQL üzerinde `UPDATE products SET stock_quantity = stock_quantity - data.quantity WHERE id = data.product_id` çalıştırılmalı ve `inventory_movements` append-only tablosuna yazılmalıdır.
- **Causal Snapshot Metadata:** `PRODUCT` push/pull DTO'suna `stock_applied_through_seq: number` alanı eklenmelidir. Böylece istemci, gelen snapshot'ın kendi satışından önceki mi yoksa sonraki mi olduğunu kesin olarak anlayabilir.

---

### 2.4. Actor ve Yönetici Onayı Sınırı
*Durum:* **KISMEN GİDERİLDİ (MİMARİ BAĞIMLILIK TESPİT EDİLDİ)**  
*Dosya / Satır:* [rbac_models.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart#L94-L115)

#### İstemci İçi İyileştirme:
`ManagerApproval` sınıfına `actionReference` (ilgili satış ID'si), `maxApprovedAmount` (onaylanan maksimum tutar/iskonto sınırı) ve `approvedAt` zaman damgası alanları eklenerek onay nesnesinin belirli bir işleme bağlanması sağlanmıştır.

#### Güvenlik Sınırı ve Mimari Bağımlılık Bildirimi:
- İstemci ortamı (Flutter Windows/Android) güvenilmeyen ortamdır (untrusted client).
- İstemci tarafındaki `ActorContext` ve `ManagerApproval` sınıfları, operatörlerin ve UI katmanının kaza eseri yetkisiz işlem yapmasını engelleyen tip güvenliği mekanizmalarıdır (defensive programming).
- **Gerçek Güvenlik Bağımlılığı:** Kötü niyetli kullanıcıların veya tersine mühendisliğin aktör kimliğini manipüle etmesini önlemek, ancak sunucu tarafında doğrulanmış kriptografik oturum token'ları (JWT/HMAC) ve sunucu tarafı RBAC yetkilendirmesi ile mümkündür.

---

## 3. TEST ÇALIŞTIRMA VE KALİTE ÇIKTILARI

Tüm test paketleri temiz sanal ortamda çalıştırılmıştır:

### 3.1. Yeni Stage 10.4 Finansal Bütünlük Test Paketi
```powershell
flutter test test/core_next/stage10_4_financial_integrity_test.dart
```
- **Çıktı:** `00:02 +7: All tests passed!`
- **Test Sayısı:** 7 test
- **Exit Code:** `0`

### 3.2. Stage 10.3 Regresyon Test Paketi
```powershell
flutter test test/core_next/stage10_3_fixes_test.dart
```
- **Çıktı:** `00:00 +9: All tests passed!`
- **Test Sayısı:** 9 test
- **Exit Code:** `0`

### 3.3. Stage 10.2 Regresyon Test Paketi
```powershell
flutter test test/core_next/stage10_2_critical_fixes_test.dart
```
- **Çıktı:** `00:00 +10: All tests passed!`
- **Test Sayısı:** 10 test
- **Exit Code:** `0`

### 3.4. Tüm `core_next/` Test Paketi (13 Test Dosyası)
```powershell
flutter test test/core_next/
```
- **Çıktı:** `00:28 +109: All tests passed!`
- **Test Sayısı:** 109 test
- **Exit Code:** `0`

---

## 4. BULGU ÖZET TABLOSU

| No | Alan | Durum | Gerekçe ve Kanıtlar |
|---|---|---|---|
| 1 | **Karma Ödeme İadesi Mutabakatı** | **GİDERİLDİ VE DOĞRULANDI** | Orijinal `sale_payments` ve önceki iadelerin nakit/vadeli bakiyeleri kuruş bazında hesaplanır; 10 TL nakit satılmışken 50 TL nakit çıkışı talebi derhal `StateError` alır ve sıfır yan etki bırakır. |
| 2 | **İade İdempotency Tam Payload** | **GİDERİLDİ VE DOĞRULANDI** | Aynı key ile farklı `paymentDistributions`, farklı satır tutarı veya farklı ürün gönderildiğinde açık conflict fırlatılır; aynı payload ise stok/nakit defterini tekrarlamadan güvenli replay döner. |
| 3 | **Sunucu Stok Projeksiyonu** | **SUNUCU/MİMARİ BAĞIMLILIĞI NEDENİYLE ENGELLENDİ** | `core_next/server_core/src/sync/watermark_sync_service.ts` dosyasında `SALE` mutasyonunun stok düşürmediği ve pull DTO'sunda `stock_applied_through_seq` alanının bulunmadığı kaynak kodla kanıtlanmıştır. |
| 4 | **Actor & Yönetici Onayı** | **KISMEN GİDERİLDİ / MİMARİ BAĞIMLILIK** | İstemci tarafında `ManagerApproval` satış ID'si ve tutar sınırına bağlanmıştır; ancak kriptografik güvenlik için sunucu doğrulaması zorunlu mimari bağımlılıktır. |

---

## 5. NİHAİ KARAR VE ENTEGRASYON DURUMU

> **CANLI SATIŞ EKRANINA ENTEGRASYON YAPILMAMALIDIR.**

İstemci tarafındaki finansal iade açıkları (karma ödeme nakit çıkışı, idempotency çakışmaları, aşırı iade engeli) tamamen kapatılmış ve 109 test ile doğrulanmıştır. Ancak **Sunucu Stok Projeksiyonu (Madde 3)** gereksinimi sunucu protokolünde eksik olduğu için, sunucu tarafı sözleşmesi güncellenmeden canlı satış ekranına geçiş veri tutarsızlığı riski taşımaktadır.
