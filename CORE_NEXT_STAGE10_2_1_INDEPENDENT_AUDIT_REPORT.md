# SERENUT OS — STAGE 10.2.1: BAĞIMSIZ ADLİ DOĞRULAMA RAPORU

**Tarih:** 13 Ekim 2026  
**Aşama:** Stage 10.2.1 — Bağımsız Adli Doğrulama ve Çürütme Denetimi  
**Denetlenen Rapor:** `CORE_NEXT_STAGE10_2_CRITICAL_FIXES_REPORT.md`  
**Kapsam:** `core_next/client_core/`, `test/core_next/`  
**Canlı Entegrasyon Durumu:** Sıfır kod değişikliği (Audit-only, `lib/` ve `server/` dokunulmadı).

---

## 1. YÖNETİCİ ÖZETİ VE NİHAİ KARAR

Bu denetim, Stage 10.2 kapsamında yapılan düzeltmelerin ve 10 adet regresyon testinin iddialarını **bağımsız olarak çürütmeye odaklanan** adli bir incelemedir.

### Bulguların Bağımsız Değerlendirme Tablosu

| No | Bulgu Başlığı | Stage 10.2 İddiası | Stage 10.2.1 Bağımsız Sınıflandırması | Temel Adli Gerekçe / Açık |
|---|---|---|---|---|
| **10.1.1** | **RBAC Fail-Open** | Giderildi ve testle doğrulandı | **KISMEN DOĞRULANDI** | `null` actor engeli getirildi; ancak güvenilir Session/Auth katmanı yok. `ActorContext` çağıran kodca keyfi üretilebiliyor ve `overrideManagerId` ile tüm yetkiler delinebiliyor. |
| **10.1.2** | **Pull Ingestion Çevrimdışı Satış Ezilmesi** | Giderildi ve testle doğrulandı | **KISMEN DOĞRULANDI** | FK ihlali ve tek sayfa offline stok/borç koruması çözüldü; ancak senkronizasyon tamamlandıktan (`COMPLETED`) sonra sunucu gecikmeli eski snapshot gönderirse ezilme riski sürüyor. Çift taraflı bakiye birleştirme yok. |
| **10.1.3** | **Nakit İadede Müşteri Alacağı** | Giderildi ve testle doğrulandı | **KISMEN DOĞRULANDI** | Nakit satışta cari alacak engellendi; ancak kartlı satışlar otomatik NAKİT iade varsayılıyor, karma ödeme dağılımı keyfi paylaştırılıyor ve `cash_transactions` tablosuna `OUTFLOW` atılmıyor. |
| **10.1.4** | **İade İdempotency UNIQUE Çökmesi** | Giderildi ve testle doğrulandı | **KISMEN DOĞRULANDI** | Aynı istekte çökme engellendi; ancak karşılaştırma sadece toplam tutara (`existingTotalCents == reqCents`) bakıyor! Farklı ürünlerin aynı tutarla gönderildiği payload çakışmaları yakalanamıyor. |
| **10.1.5** | **Eşzamanlı İade Yarışı** | Giderildi ve testle doğrulandı | **KISMEN DOĞRULANDI** | Yarışan iki iadede fazla iade engellendi; ancak Test 10 (`Aynı ürünün birden fazla satırda bulunduğu...`), sepet notifier'ının ürünleri tek satırda birleştirmesi nedeniyle gerçekte tek satırı test etti (Test yanılsaması). |

---

### NİHAİ KARAR

**B — KRİTİK BULGULAR NEDENİYLE ENTEGRASYON DURDURULMALI**

> **Gerekçe:** Proje kuralları gereği, beş bulgunun tamamı eksiksiz ve tartışmasız biçimde doğrulanmadan Karar A verilemez. Her beş alanda da önemli güvenlik iyileştirmeleri yapılmış ve 93 birim testi geçmiş olsa da; yetkilendirme güvenilirliği, ödeme kanalı dağılımı, payload seviyesinde idempotency doğrulaması ve çoklu satır test yanılsaması gibi adli açıklar mevcuttur.

---

## 2. ADLİ GİT VE DEĞİŞMEZLİK DENETİMİ

Denetim öncesinde ve sonrasında yürütülen kontroller:

```powershell
PS> git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

PS> git status --short
?? CORE_NEXT_...
?? core_next/
?? test/core_next/

PS> git diff --stat
(Boş — takip edilen dosyalarda sıfır değişiklik)

PS> git diff --cached --stat
(Boş)
```

- Denetim süresince **hiçbir kaynak kodu değiştirilmemiştir**.
- `lib/` ve `server/` dizinlerine dokunulmamıştır.
- Canlı sunucuya veya gerçek kullanıcı veritabanına bağlanılmamıştır.

---

## 3. BEŞ KRİTİK ALANIN AYRINTILI ADLİ DENETİMİ

### 3.1. Bulgu 10.1.1 — RBAC Fail-Open ve Güvenilirlik Denetimi

#### Kod İncelemesi:
- [`checkout_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L67-L77):
  ```dart
  67: final actor = request.actor ?? _defaultActor;
  68: if (actor == null) {
  69:   throw const AuthenticationRequiredException('İşlem yapan kullanıcı/aktör kimliği zorunludur.');
  70: }
  71: actor.requirePermission(AppPermission.createSale, 'Satış oluşturma');
  72: if (state.generalDiscount.value > 0) {
  73:   actor.requirePermission(AppPermission.applyDiscount, 'İskonto uygulama');
  74: }
  75: if (state.debtTotal.value > 0) {
  76:   actor.requirePermission(AppPermission.creditSale, 'Veresiye satış yapma');
  77: }
  ```
- [`rbac_models.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart#L128-L134):
  ```dart
  128: bool hasPermission(AppPermission permission) {
  129:   if (overrideManagerId != null && overrideManagerId!.trim().isNotEmpty) {
  130:     return true;
  131:   }
  132:   return RbacPolicy.hasPermission(role, permission);
  133: }
  ```

#### Kanıtlananlar (Doğrulandı):
1. **Actor `null` İken Ret:** `request.actor == null` ve `_defaultActor == null` olduğunda istek istisnasız `AuthenticationRequiredException` ile reddedilir.
2. **Tabloların Değişmezliği:** Bu kontrol transaction öncesinde (satır 68) yapıldığı için `sales`, `sale_items`, `products`, `ledger_entries`, `sync_events` tablolarında hiçbir kalıcı değişiklik oluşmaz (`stage10_2_critical_fixes_test.dart:112-115`).
3. **Rol Ayrımı:** `AppRole.staff` iskonto veya vadeli satış yapmaya kalktığında `AuthorizationException` ile engellenir (`stage10_2_critical_fixes_test.dart:150`).

#### Çürütülen / Eksik İddialar (Açıklar):
1. **Güvenilir Oturum / Kimlik Katmanı Yokluğu:** `core_next` içinde oturum açmış kullanıcıyı doğrulayan bir Authentication servisi veya JWT/PIN doğrulama katmanı yoktur. `ActorContext` düz bir veri sınıfıdır. Çağıran kod (veya istemci katmanı) keyfi olarak `ActorContext(userId: 'x', username: 'x', role: AppRole.sysadmin)` üretebilir.
2. **`overrideManagerId` Arka Kapısı:** Satır 129'da `overrideManagerId` dolu olduğu takdirde hiçbir rol kontrolü yapılmadan `true` dönülmektedir. Bu alanın geçerli ve doğrulanmış bir yöneticiye ait olup olmadığını doğrulayan bir mekanizma yoktur.

**Sınıflandırma:** **KISMEN DOĞRULANDI**

---

### 3.2. Bulgu 10.1.2 — Pull Ingestion ve Çevrimdışı Veri Bütünlüğü

#### Kod İncelemesi:
- [`sync_v4_pull_ingestion_service.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L107-L139):
  ```dart
  107: final pendingSaleItems = await txn.rawQuery('''
  108:   SELECT si.product_id, SUM(si.quantity) as pending_qty
  109:   FROM sale_items si
  110:   JOIN sync_events se ON se.entity_id = si.sale_id AND se.entity_type = 'sale'
  111:   WHERE se.sync_state IN ('PENDING', 'TRANSIENT_ERROR')
  112:   GROUP BY si.product_id
  113: ''');
  ```
- Ürün güncellemesi (satır 236-239):
  ```dart
  236: final pendingSold = pendingProductSoldQty[change.entityId] ?? 0;
  237: final effectiveStock = rawRemoteStock - pendingSold;
  ```
- Müşteri güncellemesi (satır 331-337):
  ```dart
  331: final hasPendingLocal = pendingCustomerIds.contains(change.entityId);
  332: final int effectiveBalanceCents;
  333: if (hasPendingLocal && existing.isNotEmpty) {
  334:   effectiveBalanceCents = existing.first['balance_cents'] as int;
  335: } else {
  336:   effectiveBalanceCents = remoteBalanceCents;
  337: }
  ```

#### Kanıtlananlar (Doğrulandı):
1. **FK Bütünlüğü:** `ConflictAlgorithm.replace` kaldırılmış, `UPDATE if exists, INSERT if not` kullanılarak `ON DELETE RESTRICT` FK ihlalleri engellenmiştir.
2. **Tek Sayfa Çevrimdışı Koruma:** Çevrimdışı satış yapıldığında, sunucudan gelen eski ürün snapshot'ındaki stoktan `pendingSold` düşülerek yerel stok (48) başarıyla korunur (`stage10_2_critical_fixes_test.dart:217`).
3. **Atomik Transaction:** Cursor (`_saveCursor`) ve kayıt güncellemeleri aynı transaction içindedir (satır 100-176).

#### Çürütülen / Eksik İddialar (Açıklar):
1. **Sync Sonrası Eski Snapshot Çakışması (Senaryo 5):**
   - Kullanıcı çevrimdışı satış yaptı (`pendingSold = 2`).
   - Satış sunucuya push edildi ve `sync_events.sync_state = 'COMPLETED'` oldu.
   - Artık `pendingSold = 0`'dır.
   - Eğer sunucu stoku henüz materyalize etmeden önce istemci eski stok değerine (50) sahip bir sayfa çekerse (veya bootstrap alırsa), `effectiveStock = 50 - 0 = 50` olur ve **yerel satışın stok düşümü ezilir!**
2. **Müşteri Bakiye Yutulması (Bilateral Conflict):**
   - Müşterinin yerelde bekleyen vadeli satışı varsa (`hasPendingLocal == true`), sunucudan gelen `remoteBalanceCents` değeri **tamamen göz ardı edilmektedir** (satır 334).
   - Eğer başka bir kasadan aynı müşteriye 1.000 TL tahsilat veya borç yazılmışsa, bu uzak hareket yerel snapshot tarafından sessizce ezilmektedir.
3. **Outbox Anahtar Bağı:** `sync_events.entity_id = si.sale_id` bağı yalnızca `entity_type = 'sale'` durumunda geçerlidir.

**Sınıflandırma:** **KISMEN DOĞRULANDI**

---

### 3.3. Bulgu 10.1.3 — Nakit Satış İadesinde Finansal Doğruluk

#### Kod İncelemesi:
- [`refund_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L259-L275):
  ```dart
  261: final originalDebtCents = (originalSale['debt_cents'] as num?)?.toInt() ?? 0;
  ...
  271: final remainingDebtCents = max(0, originalDebtCents - priorDebtRefunded);
  274: final debtRefundCents = min(refundTotal.value, remainingDebtCents);
  275: final cashRefundCents = refundTotal.value - debtRefundCents;
  ```
- Cari defter kaydı kontrolü (satır 337-338):
  ```dart
  337: final customerId = originalSale['customer_id'] as String?;
  338: if (customerId != null && customerId.isNotEmpty && debtRefundCents > 0) {
  ```

#### Kanıtlananlar (Doğrulandı):
1. **Nakit Satış İadesinde Alacak Engeli:** Orijinal satış nakit ise `originalDebtCents = 0` olduğundan `debtRefundCents = 0` olur. `postRefund` çağrılmaz, cari deftere alacak yazılmaz, müşteri bakiyesi 0 kalır (`stage10_2_critical_fixes_test.dart:327-330`).
2. **Vadeli İadede Borç Silinmesi:** Vadeli satış iade edildiğinde müşteri borcu kuruşu kuruşuna düşülür (`stage10_2_critical_fixes_test.dart:376`).

#### Çürütülen / Eksik İddialar (Açıklar):
1. **Kredi Kartı İadesi Yanılsaması:**
   - Orijinal satış kredi kartı ile yapılmış olsa dahi, `debtRefundCents = 0` olacağı için satır 275'te `cashRefundCents = refundTotal` hesaplanır ve satır 358'de `payment_type: 'cash'` olarak kaydedilir!
   - Sistemde POS / kart iadesi desteği olmadığı halde kartlı satışlar gizlice **nakit iade** olarak muhasebeleştirilmektedir.
2. **Karma Ödemede Keyfi Dağılım:**
   - Orijinal satış karma ise (ör. 50 TL nakit, 50 TL kart, 50 TL veresiye), sistem iade tutarının hangi ödeme kanalına ait olduğunu sorgulamamakta ve reddetmemektedir. Keyfi biçimde "önce vadeli borcu düş, kalanı nakit say" mantığı yürütmektedir.
3. **Kasa Nakit Defteri (`cash_transactions`) Eksikliği:**
   - Normal satışta `cash_transactions` tablosuna `INFLOW` kaydı atılırken (`checkout_use_case.dart:243`), nakit iadede `cash_transactions` tablosuna **hiçbir `OUTFLOW` kaydı atılmamaktadır!** Kasa nakit mutabakatı (Z raporu) bu nedenle açık verecektir.

**Sınıflandırma:** **KISMEN DOĞRULANDI**

---

### 3.4. Bulgu 10.1.4 — İade İdempotency Denetimi

#### Kod İncelemesi:
- [`refund_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L122-L168):
  ```dart
  123: final existingRefundRows = await txn.query(
  124:   'sales',
  125:   where: 'idempotency_key = ?',
  126:   whereArgs: [request.idempotencyKey],
  127:   limit: 1,
  128: );
  ...
  152: if (existingTotalCents == reqCents) {
  153:   // Birebir aynı iade tekrarlandı (IDEMPOTENT REPLAY)
  154:   return RefundResultEntity(...);
  155: } else {
  156:   throw StateError('İdempotency Çakışması...');
  157: }
  ```

#### Kanıtlananlar (Doğrulandı):
1. **Güvenli Dönüş (No Crash):** Aynı anahtar ve aynı iade isteği tekrarlandığında unhandled SQLite UNIQUE constraint hatasıyla çökmez; önceki sonuç döner.
2. **Yan Etkisizlik:** İkinci çağrıda stok ve defter hareketleri ikinci kez tetiklenmez (`stage10_2_critical_fixes_test.dart:439`).

#### Çürütülen / Eksik İddialar (Açıklar):
1. **Zayıf Payload Karşılaştırması (Kritik Açık):**
   - Satır 152'de yalnızca `existingTotalCents == reqCents` kontrol edilmektedir.
   - **Örnek Çürütme Senaryosu:** 100 TL'lik Ürün A iade edilip `key-1` ile kaydedilsin. Daha sonra aynı `key-1` anahtarıyla 100 TL'lik Ürün B iade edilmek istendiğinde; sistem `existingTotalCents == reqCents` eşitliğini doğru bulur ve Ürün B'yi iade etmek yerine Ürün A'nın eski sonucunu döner! Kalem düzeyinde (item ID ve quantity) payload karşılaştırması yapılmamaktadır.
2. **`originalSaleId` Kontrol Eksikliği:** İdempotency anahtarı ile bulunan kaydın gerçekten `request.originalSaleId` ile ilişkili olup olmadığı sorgulanmamaktadır.

**Sınıflandırma:** **KISMEN DOĞRULANDI**

---

### 3.5. Bulgu 10.1.5 — Eşzamanlı İade Yarış Koşulu

#### Kod İncelemesi:
- [`refund_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L173-L234):
  ```dart
  173: final priorRefundItems = await txn.query(
  174:   'sale_items',
  175:   where: "sale_id IN (SELECT id FROM sales WHERE status = 'REFUND' AND receipt_no LIKE ?)",
  176:   whereArgs: ['REF-$origReceipt%'],
  177: );
  ...
  229: final remainingQty = totalSold - alreadyRefunded;
  230: if (reqItem.quantity > remainingQty) {
  231:   throw StateError('İade miktarı (...), kalan iade edilebilir miktarı (...) aşamaz.');
  232: }
  ```

#### Kanıtlananlar (Doğrulandı):
1. **Transaction İçi Okuma ve Kilitleme:** Önceki iadelerin okunması (`priorRefundItems`) ve kalan miktar doğrulaması transaction sınırları içine alınmıştır.
2. **Yarışta Fazla İade Engeli:** Eşzamanlı iki istek geldiğinde (Test 9), ilk işlem tamamlandıktan sonra ikinci işlem transaction kilidini devralır ve kalan miktarın aşıldığını görerek güvenle `StateError` fırlatır (`stage10_2_critical_fixes_test.dart:558-563`).

#### Çürütülen / Eksik İddialar (Açıklar):
1. **Test 10 Yanılsaması (Adli Bulgu):**
   - Test 10 (`Aynı ürünün birden fazla satırda bulunduğu satışta tüm miktarlar doğru toplanmalıdır`) satır 580-581'de:
     ```dart
     notifier.addProduct(pEntity, quantity: 2);
     notifier.addProduct(pEntity, quantity: 3);
     ```
   - Ancak [`core_sales_flow_notifier.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart#L21-L30) satır 21'de sepette aynı ürün varsa mevcut satırın adedini `2 + 3 = 5` olarak güncellemektedir.
   - Bu nedenle `sale_items` tablosuna **aslında hiçbir zaman iki ayrı satır yazılmamıştır!** Tek bir 5 adetlik satır yazılmıştır. Test çoklu satır senaryosunu test ettiğini iddia etmiş ancak tek satırlı durumu test etmiştir.
2. **SQL LIKE Joker Karakter Kaçışı:** Satır 176'da `receipt_no LIKE 'REF-$origReceipt%'` kullanılmıştır. Fiş numarasında `%` veya `_` gibi SQL joker karakterleri bulunması halinde beklenmeyen fiş eşleşmeleri oluşabilir.

**Sınıflandırma:** **KISMEN DOĞRULANDI**

---

## 4. TEST KALİTESİ DENETİMİ (10 REGRESYON TESTİ)

`test/core_next/stage10_2_critical_fixes_test.dart` içindeki 10 testin adli dökümü:

| Test No & Satır | Sınanan Risk | Çağrılan Metot | Assertion & Doğrulama | Yan Etki Kontrolü | Kalan Adli Açık / Değerlendirme |
|---|---|---|---|---|---|
| **T1 (L82)** | Actor null iken fail-open | `checkoutUseCase.execute(actor: null)` | `throwsA(isA<AuthenticationRequiredException>)` | Var (`sales.isEmpty`, `sync_events.isEmpty`) | Yalnızca `null` actor'ü sınar; sahte/unverified actor üretimini sınamaz. |
| **T2 (L118)** | Staff iskonto delmesi | `checkoutUseCase.execute(actor: staff)` | `throwsA(isA<AuthorizationException>)` | Var (`sales.isEmpty`) | Başlıkta "ve veresiye" yazsa da test gövdesinde vadeli satış denenmemiştir. |
| **T3 (L160)** | Pull offline stok ezilmesi | `ingestPull(pullDto)` | `stock_quantity == 48`, `price_cents == 55000` | Var (stok ve fiyat ayrı assert edildi) | Sync sonrası (`COMPLETED`) gecikmeli pull senaryosu test edilmemiştir. |
| **T4 (L221)** | Pull offline borç ezilmesi | `ingestPull(pullDto)` | `balance_cents == -50000`, `name güncellendi` | Var (bakiye ve isim kontrol edildi) | Uzak sunucudan gelen eşzamanlı geçerli tahsilatın ezilmesi sınanmamıştır. |
| **T5 (L284)** | Nakit iadede müşteri alacağı | `refundUseCase.execute(...)` | `balance_cents == 0`, `ledgerEntries.isEmpty` | Var (bakiye ve defter boşluğu) | `cash_transactions` tablosuna nakit çıkışı yazılıp yazılmadığı kontrol edilmemiştir. |
| **T6 (L333)** | Vadeli iadede borç silinmesi | `refundUseCase.execute(...)` | `balance_cents == 0` | Kısmi (yalnızca müşteri bakiyesi) | Kısmi vadeli iade (ör. 500 TL'nin 200 TL'si) test edilmemiştir. |
| **T7 (L382)** | İdempotency güvenli replay | `refundUseCase.execute(...)` (x2) | `ref2.receiptNo == ref1`, `stock == 50` | Var (stokun 2. kez artmadığı teyit edildi) | Outbox'ta (`sync_events`) çift kayıt oluşup oluşmadığı assert edilmemiştir. |
| **T8 (L442)** | İdempotency çakışma tespiti | `refundUseCase.execute(...)` (farklı adet) | `throwsA(isA<StateError>)` | Zayıf (yalnızca exception) | Veritabanında kısmi değişiklik kalıp kalmadığı assert edilmemiştir. |
| **T9 (L497)** | Eşzamanlı iade yarış koşulu | `Future.wait([execute, execute])` | `successCount == 1`, `errorCount == 1`, `stock == 50` | Var (stok 52'ye çıkmadı) | Tek veritabanı bağlantısı üzerinden test edildi. |
| **T10 (L566)** | Çoklu satır iade toplamı | `addProduct` x2 -> `refundUseCase` | `refundTotal == 200000`, `qty == 4` | Zayıf (Test yanılsaması) | **Kritik Yanılsama:** Notifier ürünleri tek sepette birleştirdiği için SQLite'a 2 satır değil tek satır yazılmıştır. |

---

## 5. TEST VE ÇALIŞTIRMA KANITLARI

Denetim esnasında çalıştırılan resmi test komutları:

```powershell
PS> flutter test test/core_next/stage10_2_critical_fixes_test.dart
00:00 +0: (setUpAll)
00:00 +0: 10.1.1: Actor null olduğunda istek sysadmin yetkisi almamalı...
...
00:01 +9: 10.1.5: Aynı ürünün birden fazla satırda bulunduğu satışta tüm miktarlar doğru toplanmalıdır
00:02 +10: All tests passed!
Çıkış Kodu: 0
```

```powershell
PS> flutter test test/core_next/
...
00:24 +93: All tests passed!
Çıkış Kodu: 0
```

- **Toplam Test:** 93
- **Geçen Test:** 93
- **Başarısız Test:** 0
- **Çıkış Kodu:** `0`

---

## 6. AÇIK RİSKLER VE ÖNERİLEN EYLEMLER

Bir sonraki aşamaya geçmeden önce giderilmesi gereken teknik borçlar:

1. **Authentication Katmanı:** `ActorContext`'in keyfi üretilmesini engelleyen, kullanıcı oturumunu ve PIN doğrulamasını zorunlu kılan bir `SessionService` tanımlanmalıdır.
2. **Kapsamlı İdempotency Karşılaştırıcısı:** İade idempotency kontrolü sadece toplam tutara değil; `originalSaleId`, kalem kimlikleri ve miktarların tam hash'ine bakmalıdır.
3. **Kasa Nakit Çıkışı (`cash_transactions`):** Nakit iadelerde `cash_transactions` tablosuna `OUTFLOW` ('REFUND') kaydı eklenmelidir.
4. **Çoklu Satır Entegrasyon Testi Düzeltmesi:** Notifier atlatılarak doğrudan `sale_items` tablosuna aynı ürün için iki ayrı satır eklenip `refundUseCase` testi yinelenmelidir.
5. **Fiziksel ve Çevresel Sınırlar:** Fiziksel USB termal yazıcı ve canlı çoklu-cihaz dağıtık senkronizasyonunun henüz gerçek donanım üzerinde doğrulanmadığı unutulmamalıdır.
