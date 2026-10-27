# SERENUT OS — STAGE 10.3: KRİTİK AÇIKLARIN KAPATILMASI RAPORU

**Tarih:** 13 Ekim 2026  
**Aşama:** Stage 10.3 — Kritik Açıkların Kapatılması ve Kanıtlı Doğrulama  
**Kapsam:** `core_next/client_core/`, `test/core_next/`  
**Canlı Entegrasyon Durumu:** Sıfır canlı entegrasyon (`lib/` ve `server/` değiştirilmedi, canlı satış ekranına bağlanmadı).

---

## 1. YÖNETİCİ ÖZETİ VE NİHAİ TABLO

`CORE_NEXT_STAGE10_2_1_INDEPENDENT_AUDIT_REPORT.md` adli denetiminde tespit edilen beş kısmen doğrulanmış açık, Stage 10.3 kapsamında kaynak kodunda, veritabanı kısıtlarında ve regresyon testlerinde ele alınmış; 9 yeni adli test eklenerek tam test paketi (102 test) ile %100 doğrulanmıştır.

### Beş Açığın Nihai Sınıflandırma Tablosu

| No | Açık / Bulgu Alanı | Stage 10.2.1 Durumu | Stage 10.3 Nihai Sınıflandırması | Çözüm ve Doğrulama Kanıtı |
|---|---|---|---|---|
| **1** | **RBAC Güvenilir Actor & Arka Kapı Kapatılması** | KISMEN DOĞRULANDI | **GİDERİLDİ VE DOĞRULANDI** | `overrideManagerId` arka kapısı kaldırıldı; [ManagerApproval](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart#L94) nesnesiyle gerçek yönetici rolü (`manager`, `admin`, `owner`) zorunlu kılındı. `ActorContext.system` satış ve iade yollarından kesin olarak engellendi ([checkout_use_case.dart:71](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L71), [refund_use_case.dart:85](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L85)). |
| **2** | **Sync V4 Eski Snapshot & Tamamlanmış Satış** | KISMEN DOĞRULANDI | **GİDERİLDİ VE DOĞRULANDI** | [SyncV4PullIngestionService](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L238) içinde revizyon ve zaman damgası tabanlı delta yakınsaması (`_calculateUnreflectedSoldQty` & `_calculateUnreflectedCustomerDelta`) uygulandı. Satış `SYNCED` olsa dahi sunucu revizyonundan küçük eski snapshot'lar stoku ezmez; sunucuya yansıyan yeni snapshot ise ikinci kez düşülmez. Uzak tahsilatlar yerel vadeli borçla birleştirilir. |
| **3** | **İade Ödeme Kaynağı & Gerçek Nakit Çıkışı** | KISMEN DOĞRULANDI | **GİDERİLDİ VE DOĞRULANDI** | Nakit iadede `cash_transactions` tablosuna atomik `OUTFLOW` ('REFUND') kaydı eklendi ([refund_use_case.dart:490](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L490)). Kartlı satışların harici POS entegrasyonu olmadan iadesi `UnsupportedError` ile engellendi. Karma ödemelerde `paymentDistributions` verilmemişse belirsiz işlem `StateError` ile reddedilir. |
| **4** | **İade İdempotency Tam Payload Doğrulaması** | KISMEN DOĞRULANDI | **GİDERİLDİ VE DOĞRULANDI** | Sadece toplam tutar kontrolü kaldırıldı; `originalSaleId`, tüm ürün kimlikleri ve miktarlar (`existingQtyByProduct == requestedQtyByProduct`) birebir karşılaştırıldı ([refund_use_case.dart:180](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L180)). Aynı tutarda farklı ürün gönderimi `StateError` ile açıkça reddedilir. |
| **5** | **Çok Satırlı Ürün & Eşzamanlı İade Doğrulaması** | KISMEN DOĞRULANDI | **GİDERİLDİ VE DOĞRULANDI** | Test yanılsaması giderildi: `sale_items` tablosuna aynı ürün için doğrudan 2 ayrı satır (2 + 3 = 5 adet) yazıldığı veritabanından `expect(lines.length, 2)` ile kanıtlandı. Eşzamanlı 3'er adetlik iki yarışan istekte toplam iadenin 5'i aşamayacağı (`totalRefundedQty == 3`) doğrulandı. |

---

## 2. ADLİ GİT VE GÜVENLİK SINIRLARI

Çalışma süresince korunan sınırlar:

```powershell
PS> git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

PS> git status --short
?? CORE_NEXT_...
?? core_next/
?? test/core_next/

PS> git diff --stat
(Boş — takip edilen dosyalarda sıfır değişiklik)
```

- `lib/` ve `server/` dosyalarında **0 bayt** değişiklik yapılmıştır.
- Canlı sunucuya veya gerçek kullanıcı veritabanına bağlanılmamıştır.
- Commit, push veya deploy yapılmamıştır.

---

## 3. UYGULANAN DÜZELTMELER VE DOĞRULAMA KANITLARI

### 3.1. RBAC: Güvenilir Actor, System Actor Engeli ve Yönetici Onayı

#### Yapılan Değişiklikler:
1. [`rbac_models.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart#L94-L146):
   - Serbest `String? overrideManagerId` alanı kaldırıldı.
   - Yerine `ManagerApproval` sınıfı getirildi:
     ```dart
     class ManagerApproval {
       final String managerId;
       final String managerUsername;
       final AppRole managerRole;

       bool get isValidManagerRole =>
           managerRole == AppRole.manager ||
           managerRole == AppRole.admin ||
           managerRole == AppRole.owner;
     }
     ```
   - `ActorContext.hasPermission` metodu güncellendi: Kullanıcının rolü yetersizse, eklenen onayın `isValidManagerRole` olması ve onay veren yöneticinin rolünün o izne sahip olması şart koşuldu.
   - `ActorContext.isSystem` bayrağı eklendi.
2. [`checkout_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L71) ve [`refund_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L85):
   - `if (actor.isSystem) throw const AuthorizationException(...)` kuralı eklendi. Sistem arka plan kimliği ile kasanın doğrudan satış veya iade yapması engellendi.

#### Tehdit Modeli ve Mimari Beyan (Raporlama Gereksinimi):
> **Mimari Sınır Bildirimi:** `core_next` yerel istemci mimarisinde henüz merkezi bir JWT / PIN imzalama Auth/Session sunucusu bulunmamaktadır. Yapılan bu değişiklikler istemci kod tabanında ve use-case domain seviyesinde yetkisiz işlemleri, sahte yönetici onaylarını ve yanlış aktör yükseltmelerini fail-secure olarak engeller. Ancak kaynak kodunu manipüle edebilen bir yerel saldırgana karşı %100 koruma, VPS tarafında gerçek oturum doğrulayıcı token zorunluluğu getirilmeden sağlanamaz.

#### Test Kanıtı:
- Test: `1. RBAC: ActorContext.system ile satış yapılması kesinlikle reddedilir` ([stage10_3_fixes_test.dart:58](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_3_fixes_test.dart#L58)) -> `throwsA(isA<AuthorizationException>())`, `sales.isEmpty == true`.
- Test: `1. RBAC: Sahte veya yetkisiz yönetici onayı (ManagerApproval) ile indirim yapılamaz` ([stage10_3_fixes_test.dart:88](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_3_fixes_test.dart#L88)) -> Personel rolüyle sahte onay reddedildi; geçerli `ManagerApproval` ile işlem başarılı oldu.

---

### 3.2. Sync V4: Eski Snapshot ve Tamamlanmış Satış Yakınsaması

#### Yapılan Değişiklikler:
1. [`sync_v4_outbox_processor.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart#L98):
   - Sunucudan `SyncPushAckResult` alındığında dönen `revision` değeri `sync_events.base_revision` kolonuna kaydedildi.
2. [`sync_v4_pull_ingestion_service.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L236-L380):
   - `_calculateUnreflectedSoldQty`: Gelen pull değişikliğinin `change.revision` değeri bu satışın `base_revision` onayından küçükse (veya revizyon 0 iken zaman damgası eskiyse), satış `SYNCED` / `COMPLETED` olsa dahi eski snapshot'tan düşülür (`effectiveStock = rawRemoteStock - unreflectedSold`).
   - `_calculateUnreflectedCustomerDelta`: Müşterinin yerelde bekleyen veya henüz yansımamış vadeli satış/tahsilat deltaları hesaplanır (`effectiveBalance = remoteBalance + unreflectedDelta`).

#### Test Kanıtı:
- Test: `2. Sync V4: Çevrimdışı satış push edildikten sonra gelen eski snapshot stoku ezmez, yeni snapshot ikinci kez düşmez` ([stage10_3_fixes_test.dart:154](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_3_fixes_test.dart#L154)):
  - Başlangıç stok: 10. Çevrimdışı 2 satış yapıldı (stok: 8).
  - Satış push edildi (`SYNCED`, base_revision: 105).
  - Eski snapshot (rev 100, stok 10) geldi -> Yerel stok 8 olarak korundu (`expect(pRow['stock_quantity'], 8)`).
  - Yeni snapshot (rev 106, stok 8) geldi -> Satış ikinci kez düşülmedi, stok 8 olarak korundu (`expect(pRow['stock_quantity'], 8)`).
- Test: `2. Sync V4: Bekleyen vadeli satış varken uzaktaki tahsilat kaybolmaz ve bakiye birleşir` ([stage10_3_fixes_test.dart:234](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_3_fixes_test.dart#L234)):
  - Yerel vadeli satış: -200 TL borç.
  - Uzak tahsilat: +50 TL bakiye.
  - Birleşen bakiye: `expect(cRow['balance_cents'], -15000)` (-150 TL).

---

### 3.3. İadeler: Ödeme Kaynağı, Kredi Kartı Sınırı ve Kasa Nakit Hareketi

#### Yapılan Değişiklikler:
1. [`refund_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L330-L380):
   - Orijinal satışın `sale_payments` kayıtları incelendi.
   - Sadece kredi kartı ile yapılmış satışlarda harici POS terminal iade entegrasyonu olmadığı için `UnsupportedError` fırlatılarak sahte iade engellendi.
   - Karma ödemeli satışlarda (Nakit + Kart veya Nakit + Vadeli) `paymentDistributions` parametresi verilmemişse belirsiz işlem `StateError` ile reddedildi.
2. [`refund_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L490):
   - Nakit iade yapıldığında (`cashRefundCents > 0`), `cash_transactions` tablosuna atomik `OUTFLOW` ('REFUND') kaydı eklendi.

#### Test Kanıtı:
- Test: `3. İade: Nakit iadede cash_transactions tablosuna atomik OUTFLOW kaydı yazılır` ([stage10_3_fixes_test.dart:284](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_3_fixes_test.dart#L284)) -> `expect(outflows.length, 1)`, `amount_cents == 20000`, `category == 'REFUND'`.
- Test: `3. İade: Kredi kartlı satışın doğrudan iadesi harici terminal olmadığı için reddedilir` ([stage10_3_fixes_test.dart:320](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_3_fixes_test.dart#L320)) -> `throwsA(isA<UnsupportedError>())`.
- Test: `3. İade: Karma ödemeli satışta iade dağılımı belirtilmezse işlem güvenle reddedilir` ([stage10_3_fixes_test.dart:354](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_3_fixes_test.dart#L354)) -> Dağılımsız istek reddedildi; geçerli dağılımla iade başarıyla tamamlandı.

---

### 3.4. İade İdempotency: Tam Payload Karşılaştırması

#### Yapılan Değişiklikler:
1. [`refund_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L150-L200):
   - Sadece `existingTotalCents == reqCents` kontrolü kaldırıldı.
   - `existingOriginalSaleId == request.originalSaleId` doğrulandı.
   - `existingQtyByProduct` ile `requestedQtyByProduct` haritaları ürün bazında birebir karşılaştırıldı (`for (final entry in requestedQtyByProduct.entries)`).
   - Farklı ürün veya farklı miktarla aynı anahtar gönderildiğinde açıkça `StateError` fırlatıldı.

#### Test Kanıtı:
- Test: `4. İdempotency: Aynı anahtar ile aynı tutar fakat FARKLI ürün gönderilirse çakışma (conflict) fırlatılır` ([stage10_3_fixes_test.dart:404](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_3_fixes_test.dart#L404)):
  - Aynı tutara (200 TL) sahip iki farklı ürün (Zeytinyağı ve Ezine Peyniri).
  - İlk iade Zeytinyağı için yapıldı.
  - İkinci istek aynı anahtar ve aynı tutarla Ezine Peyniri için gönderildi.
  - Sonuç: `throwsA(isA<StateError>())` ile çakışma başarıyla yakalandı.

---

### 3.5. Çok Satırlı Ürün ve Eşzamanlı İade Doğrulaması

#### Yapılan Değişiklikler ve Test Düzeltmesi:
1. Sepet notifier'ının ürünleri birleştirmesi engellenerek, `sale_items` tablosuna doğrudan aynı ürün için 2 ayrı satır eklendi ([stage10_3_fixes_test.dart:470](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_3_fixes_test.dart#L470) & [stage10_2_critical_fixes_test.dart:578](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_2_critical_fixes_test.dart#L578)):
   - Satır 1: `p-103`, miktar 2.
   - Satır 2: `p-103`, miktar 3 (Toplam 5).
   - Doğrulama: `expect(itemLines.length, 2)`.
2. Eşzamanlı iki istek aynı anda 3'er adet iade talep etti (Toplam 6 > 5):
   - `Future.wait([execute, execute])` ile yarıştırıldı.
   - İlk transaction kilit aldı ve 3 adedi iade etti.
   - İkinci transaction kalan miktarın 2 olduğunu görerek güvenle `StateError` aldı.
   - Veritabanındaki toplam iade miktarının 3 <= 5 kaldığı kanıtlandı (`expect(totalRefundedQty, 3)`).

---

## 4. TAM TEST PAKETİ SONUÇLARI

### Hedefli Testler
1. `flutter test test/core_next/stage10_3_fixes_test.dart` -> **9 test, 9 passed (0 failed).** Exit code: `0`.
2. `flutter test test/core_next/stage10_2_critical_fixes_test.dart` -> **10 test, 10 passed (0 failed).** Exit code: `0`.

### Tüm `test/core_next/` Paketi
```powershell
PS> flutter test test/core_next/
...
00:31 +102: All tests passed!
```
- **Toplam Test:** 102
- **Geçen Test:** 102
- **Başarısız Test:** 0
- **Çıkış Kodu (Exit Code):** `0`

---

## 5. ÇÖZÜLEMEYEN / KALAN RİSKLER VE ÇEVRESEL SINIRLAR

Aşağıdaki unsurlar yerel mimaride simüle edilmiş olup, üretim ortamı öncesinde fiziksel doğrulama gerektirir:

1. **Merkezi Kimlik / JWT Sunucusu:** İstemci tarafında `ManagerApproval` ve `ActorContext` rolleri zorunlu kılınmış olsa da; VPS tarafında JWT oturum token'ı kontrol edilmeyen çağrılar tersine mühendisliğe karşı savunmasızdır.
2. **Kredi Kartı POS Terminal Entegrasyonu:** Kart iadesi güvenli biçimde engellenmiştir (`UnsupportedError`); ancak gerçek hayatta kartlı satış iadeleri için fiziksel banka POS cihazıyla haberleşen bir IPC/USB sürücüsü henüz geliştirilmemiştir.
3. **Fiziksel USB / ESC-POS Yazıcılar:** Windows RAW Spooler API ve kesintiler fiziksel cihaz üzerinde test edilmemiştir.
4. **Çok Cihazlı Eşzamanlı Yük Testi:** Aynı mağazada 3 kasanın canlı PostgreSQL VPS veritabanına aynı anda sync olması senaryosu gerçek donanım kümesinde doğrulanmalıdır.

---

## 6. SONUÇ

Stage 10.2.1 raporundaki **beş kısmen doğrulanmış bulgunun tamamı kaynak kodunda ve SQLite seviyesinde derinlemesine giderilmiş ve 102 test ile %100 doğrulanmıştır.**

Canlı satış ekranına (`lib/presentation/sales/sales_screen.dart`) doğrudan entegrasyon yapılmamış, `lib/` ve `server/` dizinlerinin dokunulmazlığı korunmuştur.
