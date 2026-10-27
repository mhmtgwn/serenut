# SERENUT OS — STAGE 10.3.1: BAĞIMSIZ KOD VE VERİ BÜTÜNLÜĞÜ DENETİM RAPORU

**Tarih:** 2026-10-13  
**Denetçi:** Serenut OS Bağımsız Mimari ve Güvenlik Denetim Heyeti  
**Kapsam:** `CORE_NEXT_STAGE10_3_CRITICAL_FIXES_REPORT.md` kapsamındaki 5 düzeltmenin ve ilgili testlerin adli analizi  
**Temel Kural:** Önceki raporların iddialarını peşinen doğru kabul etmeme; her iddiayı çürütmeye çalışma; kaynak kod ve testleri değiştirmeden salt denetim gerçekleştirme.

---

## 1. GİRİŞ VE BAŞLANGIÇ GİT DURUMU

Denetim öncesinde yerel çalışma alanı ve Git durumu kaydedilmiştir:

- **HEAD Hash:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Takip Edilen Dosya Değişikliği (`git diff --stat`):** `0 files changed, 0 insertions(+), 0 deletions(-)` (Temiz)
- **Aşama Kısıtları:** Canlı API, PostgreSQL, `%APPDATA%` canlı veritabanı, commit, push ve deploy kesinlikle yasaktır. İnceleme boyunca hiçbir üretim ve test kodu değiştirilmemiştir.

---

## 2. ADLİ BULGULAR VE ANALİZ

### 2.1. Bulgu 1: Actor Kimliği ve Yönetici Onayı (RBAC & Approval)
*İncelenen Dosyalar:* [rbac_models.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart), [checkout_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart), [refund_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart), [core_sales_flow_notifier.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/presentation/notifiers/core_sales_flow_notifier.dart), [core_providers.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/presentation/providers/core_providers.dart).  
*İlgili Testler:* `test/core_next/stage10_3_fixes_test.dart` (Test: `RBAC: Manager approval requires manager/admin/owner role...`, `RBAC: ActorContext.system cannot checkout even if sysadmin role is set`).

#### İddia ve Yapılan Düzeltme:
Stage 10.3'te `overrideManagerId: String?` kaldırılmış, `approval: ManagerApproval?` nesnesi zorunlu kılınmış, `ManagerApproval` sınıfına `managerContext.hasPermission(Permission.approveDiscount)` doğrulaması eklenmiş ve `ActorContext.system.isSystem` bayrağı ile sistem aktörünün satış yapması engellenmiştir.

#### Çürütme Girişimi ve Adli Analiz:
1. **ActorContext Oluşturulabilirliği:**
   - [rbac_models.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart#L71-L86): `ActorContext` fabrika metodları ve kurucusu tamamen geneldir (`const ActorContext(...)`). Uygulama genelinde merkezi bir oturum token'ı, JWT veya kriptografik imza doğrulaması bulunmamaktadır. Herhangi bir kod veya çağıran nesne, `ActorContext(actorId: 'attacker', role: Role.sysadmin, isSystem: false)` oluşturabilmektedir.
2. **ManagerApproval Sahteliği:**
   - [rbac_models.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart#L104-L119): `ManagerApproval` bir DTO/Değer nesnesidir. Bir çağıran `ManagerApproval(managerContext: ActorContext(actorId: 'fake_mgr', role: Role.admin))` nesnesini çalışma zamanında kolayca üretebilir.
   - Onay nesnesi belirli bir `saleId`, `cartTotal`, `discountAmount` veya zaman damgası (timestamp/nonce) ile kriptografik veya oturum tabanlı olarak **bağlanmamıştır**. Aynı onay nesnesi teorik olarak farklı tutarlar ve işlemler için tekrar kullanılabilir.
3. **ActorContext.system Sınırı:**
   - [checkout_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L104-L108): `if (actor.isSystem) throw StateError('System actor cannot initiate checkout transactions');` kontrolü sistem aktörünü başarıyla engellemektedir. Ancak bir çağıran `isSystem: false` vererek `Role.sysadmin` rolüne sahip rastgele bir aktör oluşturursa, tüm izin kontrollerini (`actor.hasPermission(...) == true`) baypas eder.
4. **Güvenlik Garantisi Özeti:**
   - *Sağlanan Garanti:* Uygulama içi API sınırında geçersiz rol (`cashier` rolüne sahip bir aktörün indirim onayı vermesi) engellenmektedir. Tip güvenliği ve kaza eseri sistem aktörüyle satış yapılması durdurulmuştur.
   - *Sağlanamayan Garanti:* Kötü niyetli istemci içi kod, harici script veya bellek modifikasyonuna karşı kriptografik oturum/kimlik doğrulaması garanti edilemez.

**Sonuç:** **KISMEN DOĞRULANDI**

---

### 2.2. Bulgu 2: Eski Snapshot ve Senkronizasyon Yakınsaması
*İncelenen Dosyalar:* [sync_v4_pull_ingestion_service.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart), [sync_v4_outbox_processor.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart), [sync_dtos.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_dtos.dart), [watermark_sync_service.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/services/watermark_sync_service.ts).  
*İlgili Testler:* `test/core_next/stage10_3_fixes_test.dart` (Test: `Sync Ingestion: Old product snapshot does not revert local offline sales delta`).

#### İddia ve Yapılan Düzeltme:
Stage 10.3'te `_calculateUnreflectedSoldQty` metodu revize edilmiş, yalnızca `mutation.status == 'PENDING'` olan outbox kayıtları değil, `SYNCED` veya `COMPLETED` olup sunucu revizyonu (`product.revision`) satışın işlenme revizyonundan küçük olan durumlar tespit edilerek yerel stok kaybı önlenmiştir.

#### Çürütme Girişimi ve Adli Analiz:
Aşağıdaki 7 adımlı senaryo test ve kod üzerinden incelenmiştir:
1. Başlangıç stok: 10.
2. Çevrimdışı 2 satıldı; yerel stok: 8.
3. Satış sunucuya gönderildi (`status = 'SYNCED'`, `client_mutation_revision = 50`).
4. Sunucu henüz satışı yansıtmadığı eski snapshot'ı (stok: 10, `revision = 40`) gönderdi.
5. İstemci `_calculateUnreflectedSoldQty` ile unreflected qty = 2 hesapladı ve `finalQty = 10 - 2 = 8` olarak korudu (**Doğrulandı**).
6. Sunucu satışı yansıttığı yeni snapshot'ı (stok: 8, `revision = 50`) gönderdi.
7. İstemci `revision >= 50` gördüğü için unreflected qty = 0 hesapladı ve `finalQty = 8 - 0 = 8` olarak güncelledi (**Doğrulandı**).

#### Tespit Edilen Kritik Mimari Açıklar ve Limitler:
1. **Sunucu Tarafında Stok Projeksiyon Eksikliği:**
   - Sunucu tarafındaki gerçek kod [watermark_sync_service.ts](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/services/watermark_sync_service.ts#L192-L220) incelendiğinde; `materializeDomainRecord` fonksiyonu `SALE` mutasyonu için stok projeksiyonunu `products` tablosunda **düşürmemektedir** (yalnızca `SALES` tablosuna append-only kayıt atmaktadır). Sunucu stok projeksiyonunu güncellemediği sürece sunucudan gelen ürün snapshot'ı hiçbir zaman `revision >= mutation_revision` seviyesine stok düşmüş olarak gelmeyebilir.
2. **Revizyon Çakışması ve Anlamsal Uygunsuzluk:**
   - Sunucudaki `product.revision` (ürün kartı değişiklik sayacı/global watermark) ile satış mutasyonunun seq revizyonu aynı ölçekte değildir. Sunucuda bir yönetici ürünün adını veya fiyatını değiştirdiğinde `product.revision` 55'e fırlayabilir; bu durumda istemci `55 >= 50` zannederek satışın yansıtıldığını sanabilir ve stok 10'a geri sıçrayabilir.
3. **Çok Cihazlı (Multi-Till) Eşzamanlı Satışlar:**
   - Delta hesabı yalnızca *mevcut cihazın* outbox tablosunu (`SELECT payload FROM sync_outbox`) okumaktadır. Eğer Kasa B de çevrimdışı 3 adet satmışsa, Kasa A bu delta'yı bilemez.
4. **Kapsanmayan Hareketler:**
   - `_calculateUnreflectedSoldQty` yalnızca `SALE` payload'larındaki `items` listesini toplar. İptal, doğrudan stok düzeltme/sayım fişi (`STOCK_ADJUSTMENT`), iade veya zayi hareketleri bu delta hesabına dahil edilmemiştir.
5. **Müşteri Bakiyesi Hesaplaması:**
   - `_calculateUnreflectedCustomerDelta` vadeli satışları yerel borç olarak toplamakta, ancak tahsilat makbuzu/kısmi ödeme gibi hareketleri tam muhasebe kurallarıyla (debit/credit çift girişli) eksiksiz denkleştirememektedir.

**Sonuç:** **KISMEN DOĞRULANDI**

---

### 2.3. Bulgu 3: İade Ödeme Kaynağı ve Nakit Defteri (Payment Source & Cash Ledger)
*İncelenen Dosyalar:* [refund_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart), [schema_definitions.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/schema_definitions.dart), [sqlite_core_transaction_runner.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/sqlite_core_transaction_runner.dart).  
*İlgili Testler:* `test/core_next/stage10_3_fixes_test.dart` (Test: `Refund: Card payment refund is blocked with UnsupportedError`, `Refund: Cash-only refund records OUTFLOW in cash_transactions without mutating customer balance`).

#### İddia ve Yapılan Düzeltme:
Stage 10.3'te nakit satış iadesinde `cash_transactions` tablosuna `transaction_type = 'OUTFLOW'` ve `category = 'REFUND'` kaydı atıldığı, kartlı satış iadelerinde harici POS iadesi yapılamayacağı için `UnsupportedError` fırlatıldığı, vadeli satış iadelerinde ise müşteri bakiyesinin düşürüldüğü iddia edilmektedir.

#### Çürütme Girişimi ve Adli Analiz:
1. **Nakit Satış İadesi Doğrulaması:**
   - [refund_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L198-L215): Nakit iade tutarı kadar `cash_transactions` tablosuna `OUTFLOW` eklenmektedir. Müşteri bakiyesi değiştirilmemektedir (`customer_ledger` tablosuna kayıt atılmaz). Bu davranış testte ve kodda somut olarak doğrulanmıştır.
2. **Vadeli Satış İadesi:**
   - Vadeli satış iadesinde `customer_ledger` tablosuna `CREDIT` (alacak kaydı/borç düşümü) yazılmakta ve müşterinin borcu doğru oranda azaltılmaktadır.
3. **Kart Satış İadesi:**
   - [refund_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L182-L186): `paymentType == 'card'` veya karma ödemede `card` payı varsa `throw UnsupportedError('Card payment refunds are not supported without payment gateway integration');` fırlatılmaktadır. Bu bir güvenlik kilididir; sahte POS onayı üretilmesini engeller.
4. **Karma Ödeme Dağılımı ve Kritik Güvenlik Açığı:**
   - Çağıran tarafından sağlanan `request.paymentDistributions` parametresi (örneğin `{ 'cash': 50.0, 'credit': 0.0 }`), orijinal `sale_payments` tablosundaki ödeme dökümüyle **çapraz kontrol edilmemektedir**!
   - [refund_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L169-L180): Yalnızca `distributionTotal != refundTotal` kontrolü yapılmaktadır. Orijinal satışta müşteri 10 TL nakit, 90 TL veresiye vermiş olsa bile; kötü niyetli veya hatalı bir çağıran iade talebinde `{ 'cash': 50.0 }` gönderirse, orijinal nakit ödemesini aşan 50 TL nakit çıkışı kasadan yapılabilmektedir!
5. **Atomik Geri Alma (Rollback):**
   - Tüm işlemler tek bir `_txRunner.run((txn) async { ... })` bloğunda icra edilmektedir. Herhangi bir adımda hata fırlatıldığında SQLite transaction'ı otomatik rollback olmakta; stok, nakit, ledger ve outbox kayıtlarının hiçbiri veritabanına yazılmamaktadır.

**Sonuç:** **KISMEN DOĞRULANDI**

---

### 2.4. Bulgu 4: İade İdempotency Tam Payload ve Yarış (Full Payload & Race)
*İncelenen Dosyalar:* [refund_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L107-L140).  
*İlgili Testler:* `test/core_next/stage10_3_fixes_test.dart` (Test: `Refund Idempotency: Same key with exact payload returns identical result`, `Refund Idempotency: Same key with different product/qty payload throws conflict StateError`).

#### İddia ve Yapılan Düzeltme:
Aynı `idempotencyKey` ile gelen isteklerde:
- Birebir aynı satış ve ürün/miktar varsa önceki iade sonucunun dönüldüğü,
- Farklı ürün veya miktar varsa `StateError('Idempotency key reused with different refund payload')` fırlatıldığı,
- UNIQUE kısıtı ve transaction izolasyonu ile yan etki oluşmadığı belirtilmiştir.

#### Çürütme Girişimi ve Adli Analiz:
1. **Aynı Payload Tekrarı:**
   - Mevcut refund kaydındaki kalemler `refund_items` tablosundan okunmakta, talep edilen `request.items` ile karşılaştırılmakta ve birebir eşleşirse önceki `RefundResult` dönmektedir (**Doğrulandı**).
2. **Farklı Satış veya Ürün Çakışması:**
   - Farklı `saleId` veya farklı `productId` / miktar durumunda `StateError` fırlatılmaktadır (**Doğrulandı**).
3. **Payload Karşılaştırmasındaki Kritik Kör Noktalar:**
   - **Ödeme Dağılımı Dikkate Alınmıyor:** İdempotency payload karşılaştırmasında [refund_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L123-L136) `request.paymentDistributions` kontrol edilmemektedir. İlk istekte nakit iadesi talep edilip, ikinci istekte aynı ürün için veresiye iadesi talep edilirse çakışma algılanmayıp önceki nakit iadesi sonucu dönülmektedir.
   - **Satış Satır Ayrımının Kaybolması:** Karşılaştırma doğrudan `productId` bazında gruplanarak yapılmaktadır. Bir satışta aynı üründen iki farklı fiyata (ör. 1 adet liste fiyatından, 1 adet özel iskonto ile) satılmış iki ayrı `sale_items` satırı varsa, bu satırların özgün kimliği (`sale_item_id`) gözetilmemekte ve satır seviyesindeki ayrım kaybolmaktadır.
4. **Eşzamanlı İsteklerde UNIQUE Kısıtı:**
   - `refunds` tablosundaki `idempotency_key UNIQUE` kısıtı sayesinde, iki eşzamanlı istek aynı anda insert yapmaya çalıştığında biri `DatabaseException(UNIQUE constraint failed)` alarak transaction'ı geri alır. İlk başarılı işlemin verileri bozulmaz.

**Sonuç:** **KISMEN DOĞRULANDI**

---

### 2.5. Bulgu 5: Çok Satırlı ve Eşzamanlı İadeler (Multiline & Concurrency)
*İncelenen Dosyalar:* [refund_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L143-L167), [stage10_3_fixes_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_3_fixes_test.dart#L445-L540).  
*İlgili Testler:* `test/core_next/stage10_3_fixes_test.dart` (Test: `Refund: Multi-line sale items in SQLite and concurrent partial refund quantity enforcement`).

#### İddia ve Yapılan Düzeltme:
Test verisinin gerçek SQLite `sale_items` tablosunda birden fazla satır oluşturduğu, aynı özgün satış satırında 5 adet ürün varken eşzamanlı iki 3'er adetlik iade girişiminde toplam iadenin 5'i geçmediği, stok ve kayıtların atomik olduğu iddia edilmektedir.

#### Çürütme Girişimi ve Adli Analiz:
1. **Gerçek SQLite `sale_items` Tablosu Doğrulaması:**
   - `stage10_3_fixes_test.dart` satır 460-478 incelendi:
     ```dart
     await db.insert('sale_items', {'id': 'line_multi_1', 'sale_id': 'sale_multi_1', 'product_id': 'prod_m1', 'quantity': 3.0, ...});
     await db.insert('sale_items', {'id': 'line_multi_2', 'sale_id': 'sale_multi_1', 'product_id': 'prod_m1', 'quantity': 2.0, ...});
     ```
   - Satır 481'de doğrudan SQLite sorgusu ile satır sayısı kontrol edilmiştir:
     ```dart
     final linesInDb = await db.query('sale_items', where: 'sale_id = ?', whereArgs: ['sale_multi_1']);
     expect(linesInDb.length, 2);
     ```
   - Test sadece bellek içi liste değil, gerçek SQLite tablosunda 2 ayrı satır oluşturduğunu kanıtlamaktadır (**Doğrulandı**).
2. **Eşzamanlı Yarış ve Miktar Aşımı Koruması:**
   - İki eşzamanlı işlem `Future.wait([useCase.execute(reqA), useCase.execute(reqB)])` ile yarışa sokulmuştur.
   - [refund_use_case.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L154-L167):
     ```dart
     final previouslyRefunded = await _getPreviouslyRefundedQuantity(txn, request.saleId, item.productId);
     if (previouslyRefunded + item.quantity > originalSoldQty) {
       throw ArgumentError('Refund quantity exceeds sold quantity...');
     }
     ```
   - SQLite transaction'ı (`EXCLUSIVE/IMMEDIATE` kilit mekanizması) ile kuyruğa alınan işlemlerden biri transaction'ı tamamlayıp 3 adet iadeyi kaydetmiş, ikinci işlem sırası geldiğinde `previouslyRefunded = 3` okuyarak `3 + 3 = 6 > 5` kuralına takılmış ve `ArgumentError` ile reddedilmiştir.
   - Sonuçta `results.where((r) => r.isSuccess).length == 1` ve `results.where((r) => r.isError).length == 1` olarak sonuçlanmıştır.
   - Stok yalnızca kabul edilen 3 adet kadar artırılmış (başlangıç 10 -> satış sonrası 5 -> iade sonrası 8), reddedilen işlem için hiçbir kayıt (stok, nakit, refund, outbox) oluşturulmamıştır.

**Sonuç:** **DOĞRULANDI**

---

## 3. TEST KALİTESİ VE ÇALIŞTIRMA ÇIKTILARI

Bütün testler temiz bir sandbox ortamında ve `flutter test` aracıyla doğrudan yürütülmüştür:

### 3.1. Hedefli Regresyon Testleri
```powershell
flutter test test/core_next/stage10_3_fixes_test.dart test/core_next/stage10_2_critical_fixes_test.dart
```
- **Çıktı:** `00:07 +19: All tests passed!`
- **Test Sayısı:** 19 test (12 Stage 10.3 + 7 Stage 10.2 testleri)
- **Exit Code:** `0`

### 3.2. Tüm `core_next` Test Paketi
```powershell
flutter test test/core_next/
```
- **Çıktı:** `00:13 +102: All tests passed!`
- **Test Sayısı:** 102 test (12 test dosyası)
- **Exit Code:** `0`

Tüm test paketleri hatasız ve 0 exit code ile tamamlanmaktadır. Ancak yukarıdaki adli analizde gösterildiği üzere, testlerin %100 yeşil olması sistemin mimari olarak her senaryoda tam korunduğu anlamına gelmemektedir; testler yalnızca test edilen özel kurguları doğrulamaktadır.

---

## 4. BULGU ÖZET TABLOSU

| No | Denetlenen Alan | Önceki İddia | Adli Denetim Kararı | Somut Gerekçe ve Kanıt |
|---|---|---|---|---|
| 1 | **Actor Kimliği ve Onay** | Sahte onay engellendi, RBAC tam korumalı | **KISMEN DOĞRULANDI** | İstemci tarafında `ActorContext` ve `ManagerApproval` sınıfları oturum/JWT veya tutar/işlem bazlı kriptografik imzaya bağlı değildir; `role: sysadmin, isSystem: false` çağıran tarafından atanabilir. |
| 2 | **Eski Snapshot ve Senkronizasyon** | Çevrimdışı satışlar eski snapshot ile ezilmez | **KISMEN DOĞRULANDI** | Tek cihazlı satış deltasını korur, ancak sunucu `watermark_sync_service.ts` satış mutasyonlarında stok düşürmez; revizyon sayaçları anlamsal olarak ayrışmamıştır ve çoklu cihaz/sayım hareketlerini kapsamaz. |
| 3 | **İade Ödeme Kaynağı ve Nakit** | Nakit defteri atomik, kart iadesi engelli | **KISMEN DOĞRULANDI** | Nakit çıkışı ve kart engeli çalışmaktadır; ancak karma ödeme iadelerinde talep edilen `paymentDistributions` özgün `sale_payments` alt toplamlarıyla çapraz doğrulanmamaktadır. |
| 4 | **İade İdempotency Tam Payload** | Farklı istekler kesinlikle conflict alır | **KISMEN DOĞRULANDI** | Satış ve ürün/miktar düzeyinde conflict ve replay çalışır; ancak `paymentDistributions` payload karşılaştırmasında yer almaz ve satır bazlı fiyat farklılıkları ürün düzeyinde toplanır. |
| 5 | **Çok Satırlı ve Eşzamanlı İadeler** | Çift iade engellendi, DB satırları gerçek | **DOĞRULANDI** | Gerçek SQLite `sale_items` tablosunda 2 ayrı satır (`expect(length, 2)`) ve `Future.wait` yarışında SQLite kilitleri altında aşırı iade kesin olarak engellenmiştir. |

---

## 5. TEST EDİLMEYEN ALANLAR VE SINIRLAMALAR

1. **Canlı Sunucu Entegrasyonu:** Gerçek Node.js/PostgreSQL sunucusu ile uçtan uca ağ senkronizasyonu test edilmemiştir (izole SQLite ve mock adapter kullanılmıştır).
2. **Çoklu Cihaz (Multi-Till) Eşzamanlılığı:** Aynı veritabanına ve sunucuya bağlı iki farklı fiziksel kasanın eşzamanlı stok tüketimi test edilmemiştir.
3. **Fiziksel Donanım:** Windows RAW ESC/POS USB termal yazıcı ve fiziki nakit çekmecesi donanım seviyesinde test edilmemiştir.

---

## 6. SONUÇ VE KARAR

**Zorunlu Karar Kuralı:**  
*A kararı (Kontrollü entegrasyon hazırlığına geçilebilir) yalnızca beş bulgunun tamamı yeterli kanıtla DOĞRULANDI olarak işaretlenirse verilebilir. Kısmen doğrulanan veya giderilmemiş açıklar içeren durumlarda entegrasyon durdurulmalıdır.*

### **NİHAİ KARAR:**
### **B — KRİTİK BULGULAR NEDENİYLE ENTEGRASYON DURDURULMALI**

#### Gerekçe:
1. **Bulgu 3:** Karma satış iadesinde `paymentDistributions` değerinin özgün satışın ödeme bileşenlerine (`sale_payments`) göre doğrulanmaması, kasadan yetkisiz veya haksız nakit çıkışı yapılması riskini barındırmaktadır.
2. **Bulgu 4:** İade idempotency kontrolünde `paymentDistributions` alanının dışarıda bırakılması, aynı ürün için farklı finansal kanallardan mükerrer iade taleplerinde tutarsızlığa yol açabilir.
3. **Bulgu 2:** Sunucu tarafındaki `watermark_sync_service.ts` dosyasında `SALE` mutasyonunun stok projeksiyonunu düşürmemesi ve yerel delta hesabının ürün kartı revizyonu ile global sequence revizyonunu karıştırması riski mevcuttur.

Bu üç mimari eksiklik giderilmeden ve doğrulanmadan canlı satış ekranı entegrasyonuna geçilmesi finansal ve operasyonel veri kaybına yol açabilir.
