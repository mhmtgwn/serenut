# SERENUT OS — STAGE 10.1: BAĞIMSIZ KOD DOĞRULAMASI VE ENTEGRASYON ÖNCESİ GÜVENLİK KAPISI RAPORU

**Tarih:** 13 Ekim 2026  
**Aşama:** Stage 10.1 — Bağımsız Kod Doğrulaması ve Entegrasyon Öncesi Güvenlik Kapısı  
**Denetlenen Kapsam:** `core_next/client_core/`, `test/core_next/`, `server/src/modules/sync_v4/`  
**Nihai Karar:** **B — En az bir kritik veya yüksek riskli engel devam ediyor; doğrudan canlı entegrasyona geçilemez.**

---

## 1. GERÇEK GIT VE DOSYA DURUMU

Aşağıdaki çıktılar doğrudan çalışma ortamındaki terminal komutlarıyla üretilmiştir:

```powershell
$ git status --short
?? CORE_NEXT_INDEPENDENT_AUDIT.md
?? CORE_NEXT_SECOND_PASS_AUDIT.md
?? CORE_NEXT_STAGE10_CRITICAL_GAPS_REPORT.md
?? CORE_NEXT_STAGE3_FORENSIC_VERIFICATION.md
?? CORE_NEXT_STAGE4_FIX_REPORT.md
?? CORE_NEXT_STAGE5_FORENSIC_REPORT.md
?? CORE_NEXT_STAGE6_INTEGRATION_PREPARATION.md
?? CORE_NEXT_STAGE7_FINANCIAL_RESILIENCE_REPORT.md
?? CORE_NEXT_STAGE8_1_REMEDIATION_REPORT.md
?? CORE_NEXT_STAGE8_2A_SYNC_CONTRACT_AUDIT.md
?? CORE_NEXT_STAGE8_2B_OUTBOX_ADAPTER_REPORT.md
?? CORE_NEXT_STAGE8_2C_SYNC_INTEGRITY_AUDIT.md
?? CORE_NEXT_STAGE8_3_HTTP_CLIENT_REPORT.md
?? CORE_NEXT_STAGE8_4_SYNC_RECOVERY_REPORT.md
?? CORE_NEXT_STAGE8_INDEPENDENT_AUDIT.md
?? CORE_NEXT_STAGE9_ARCHITECTURE_AUDIT.md
?? core_next/
?? test/core_next/

$ git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

$ git branch --show-current
main

$ git diff --stat
(Boş — Tracked hiçbir dosyada değişiklik yoktur)

$ git diff --cached --stat
(Boş)
```

**Güvenlik Sınırı Teyidi:**
- `lib/` (canlı uygulama): Sıfır değişiklik.
- `server/` (sunucu mimarisi): Sıfır değişiklik.
- Canlı PostgreSQL / `%APPDATA%`: Sıfır bağlantı.
- Test dosyaları manipüle edilmemiş, gerçek kaynak kodları taranmıştır.

---

## 2. İADE (REFUND) USE-CASE'İNİN BAĞIMSIZ ADLİ DENETİMİ

[`CoreRefundUseCase`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart), [`LedgerService`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/services/ledger_service.dart), [`CoreCheckoutUseCase`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart) ve veritabanı şeması birlikte incelenerek sorular tek tek cevaplanmıştır:

### Soru 1: İade edilen miktar, önceki iade kayıtları dikkate alınarak atomik biçimde sınırlandırılıyor mu?
- **Gözlem:** [`refund_use_case.dart:109-122`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L109-L122) satırlarında önceki iadeler `sale_items` tablosundan okunmakta ve kalan miktar hesaplanmaktadır.
- **Kritik Kusur (Race Condition & Transaction Sınırı):** Önceki iadelerin okunması (`priorRefundItems`, satır 111-115) ve miktar doğrulaması (satır 130-156), veritabanı transaction'ı (`_db.transaction`, satır 189) **dışında** yürütülmektedir! Eşzamanlı iki iade isteği geldiğinde her iki istek de transaction öncesi aynı kalan miktarı okur ve ikisi de transaction içine girerek mükerrer iade kaydeder.
- **İkinci Kusur (Çoklu Satır Ezilmesi):** Satır 107'de `final originalItemsMap = {for (var it in originalItems) it.productId: it};` kullanılmaktadır. Eğer orijinal satış fişinde aynı ürün birden fazla satırda yer almışsa (örn. tartılı veya farklı birim fiyatlı), map oluşturulurken ilk satırlar ezilmekte, yalnızca son satırın adedi dikkate alınmaktadır.

### Soru 2: İade aynı idempotency anahtarıyla tekrarlandığında stok veya bakiye yeniden değişiyor mu?
- **Gözlem:** Satır 202'de `'idempotency_key': idempotencyKey` `sales` tablosuna yazılmaktadır. Şemada `sales.idempotency_key` `UNIQUE` kısıtına sahiptir.
- **Kritik Kusur (Unhandled SQL Exception):** [`CoreCheckoutUseCase`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L102-L115) aksine, `CoreRefundUseCase` işlem öncesinde mevcut `idempotency_key` kaydını aramaz. Aynı idempotency anahtarıyla tekrar çağrıldığında, `txn.insert('sales', ...)` satırında `DatabaseException: UNIQUE constraint failed: sales.idempotency_key` fırlatılır. Transaction rollback olduğu için stok veya bakiye ikinci kez değişmez; **ancak istemci idempotency garantisi sağlamak yerine doğrudan çöker**.

### Soru 3: İade edilen para hangi ödeme kanalına döndürülüyor?
- **Gözlem:** `CoreRefundUseCase`, `sale_payments` tablosuna **HİÇBİR kayıt atmaz**.
- **Kritik Finansal Kusur:** 
  1. Orijinal satış kredi kartı, nakit veya karma yapılmış olsa bile; geri ödemenin kasadan nakit mi çıktığı yoksa POS üzerinden iade mi yapıldığı takip edilmez.
  2. Kasa çekmecesi ve kasa defteri (cash drawer / cash register ledger) üzerinde hiçbir ters hareket oluşturulmaz.
  3. Satır 268'de sunucu mutasyon payload'ına `'payment_method': 'cash'` **sabit (hardcoded)** olarak yazılmıştır.

### Soru 4: Vadeli satış iadesi müşteri borcunu doğru yönde ve doğru tutarda etkiliyor mu?
- **Gözlem:** Satır 245-255'te `originalSale['customer_id']` doluysa `LedgerService.postRefund` çağrılmaktadır. `postRefund` müşterinin bakiyesini `customer.balance + refundAmount` olarak artırır (borcunu düşürür).
- **Yüksek Riskli Finansal Bozulma:** Eğer müşteri adıyla açılmış bir satış **NAKİT** olarak ödenmişse (`debt_cents = 0`), satış anında müşterinin cari defterine hiçbir borç işlenmemiştir. İade anında ise kod `debt_cents` değerine bakmaksızın müşterinin hesabına alacak (`+refundAmount`) işler! Sonuç olarak müşteri hem kasiyerden nakit parasını geri alır, hem de sistemde işletmeye karşı havadan alacaklı hale gelir!

### Soru 5: Kısmi iade, orijinal satışın toplamını yanlışlıkla tamamen iptal ediyor mu?
- **Gözlem:** Orijinal satış kaydı `sales` tablosunda korunur, `status = 'COMPLETED'` kalır. İade için ayrı bir `status = 'REFUND'` ve negatif tutarlı fiş kaydı açılır (`-refundTotal`). Orijinal satış silinmez.
- **Raporlama Riski:** Gün sonu veya Z raporu sorguları `WHERE status = 'COMPLETED'` filtresiyle toplam ciro alıyorsa, orijinal satış tam ciro olarak kalır, iade düşülmez.

### Soru 6: İade mutasyonu sunucunun gerçek Sync V4 sözleşmesiyle uyumlu mu?
- **Sunucu Kodu İncelemesi ([`server/src/modules/sync_v4/sync-v4.materializer.ts:429-447`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.materializer.ts#L429-L447)):**
  - Sunucu `financial_transaction` altında `type = 'refund'` kabul etmektedir.
  - Sunucu `reference_id` alanının `sales.id` ile eşleşmesini zorunlu tutmaktadır (`SELECT ... FROM sales WHERE id=$1`).
  - Sunucu kontrolü: `amount > Number(sale.rows[0].total_amount) + 0.01` ise hata verir (`refund_sale_mismatch`).
  - **Sözleşme Uyumsuzluğu / Risk:** İstemci çevrimdışı iken yapılan bir satış henüz sunucuya gitmemişse (`PENDING` outbox) ve aynı çevrimdışı sürede iade yapılırsa; sunucu satış kaydını henüz görmediği için iade mutasyonunu `refund_sale_mismatch` ile **kalıcı olarak reddeder**!

---

## 3. RBAC GÜVENLİK KAPISI VE YETKİLENDİRME ADLİ DENETİMİ

[`rbac_models.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart), [`checkout_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart) ve [`ActorContext`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart#L94-L132) incelendi:

### 1. Rol Bilgisinin Kaynağı ve Güvenilirliği
- **Kritik Güvenlik Açığı (Unauthenticated Actor Injection):** `ActorContext`, herhangi bir kriptografik imza, oturum token'ı veya `users` tablosu doğrulaması olmaksızın istemci tarafında serbestçe `const ActorContext(userId: '...', username: '...', role: AppRole.owner)` şeklinde üretilebilen basit bir Dart nesnesidir. Çağıran kod kendi rolünü istediği an `owner` veya `sysadmin` olarak belirleyebilir.

### 2. Null Actor Durumunda Güvenlik İhlali (Fail-Open Bug)
- **Dosya ve Satır:** [`checkout_use_case.dart:64`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L64):
  ```dart
  final actor = request.actor ?? ActorContext.system;
  ```
- **Kritik Kusur:** Eğer UI veya harici bir çağırıcı `actor` parametresini göndermezse (`null`), use-case işlemi reddetmek yerine `ActorContext.system`'e düşmektedir. `ActorContext.system` ise **`AppRole.sysadmin`** rolündedir! Yani kimlik belirtmeyen veya parametreyi unutan her istek, otomatik olarak sistemin en yetkili kullanıcısı (sysadmin) haklarıyla yürütülmektedir! Bu durum güvenlikte "Fail-Secure" (güvenli ret) ilkesinin tam tersi olan "Fail-Open" açığıdır.

### 3. Ayrı Yetki Kontrolleri ve Rollback Güvencesi
- Satış oluşturma, iskonto (`state.generalDiscount.value > 0`), veresiye (`state.debtTotal.value > 0`) ve iade (`AppPermission.refund`) domain seviyesinde ayrı ayrı denetlenmektedir.
- Yetkisiz bir aktör işlem yapmaya çalıştığında `AuthorizationException` fırlatılmakta; SQLite ve `sync_events` outbox tablolarında hiçbir kayıt oluşmamaktadır (Test 5 ve Test 8 ile kanıtlanmıştır).

---

## 4. PULL INGESTION VE ÇAKIŞMA ÇÖZÜMLEME DENETİMİ

[`sync_v4_pull_ingestion_service.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart) ve SQLite şeması incelendi:

### 1. Sayfa Tekrarı ve Atomik Transaction Sınırı
- `ingestBootstrap` ve `ingestPull` metodları tüm kayıtları ve cursor kaydını (`_saveCursor`) tek bir `_db.transaction` içinde işlemektedir.
- Sayfanın ortasında hata alınır veya uygulama kapanırsa işlem tamamen rollback olur, cursor ilerlemez. Bu davranış sağlamdır.

### 2. Kritik Mimari Hata: Çevrimdışı Satışların Üzerine Sessizce Yazılması (Stok ve Bakiye Kaybı)
- **Dosya ve Satır:** [`sync_v4_pull_ingestion_service.dart:89-112`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L89-L112)
- **Kod Davranışı:**
  ```dart
  final pendingLocalRows = await db.query(
    'sync_events',
    columns: ['entity_type', 'entity_id'],
    where: "sync_state IN ('PENDING', 'TRANSIENT_ERROR')",
  );
  final pendingSet = pendingLocalRows
      .map((r) => '${r['entity_type']}:${r['entity_id']}'.toLowerCase())
      .toSet();
  ```
- **Kritik Kusur:** Checkout sırasında satış yapıldığında `sync_events` tablosuna yalnızca:
  - `entity_type: 'sale'`
  - `entity_type: 'financial_transaction'`
  kayıtları eklenir. `entity_type: 'product'` veya `entity_type: 'customer'` kaydı **O-L-U-Ş-T-U-R-U-L-M-A-Z**!
- **Sonuç:**
  1. Bir kasiyer çevrimdışı 10 adet ürün sattığında (stok 50'den 40'a indiğinde); `sync_events` içinde bekleyen bir `product` kaydı olmadığı için `pendingSet.contains('product:...')` `FALSE` döner!
  2. Sunucudan eski stok miktarını (50) içeren bir pull paketi geldiğinde, `_ingestProduct` `ConflictAlgorithm.replace` ile yerel stoğu doğrudan **50** yapar! Çevrimdışı yapılan satışın stok düşümü sessizce yok edilir!
  3. Aynı şekilde veresiye satış yapıldığında `customers` tablosundaki borç bakiyesi güncellenmiş ve `customer_ledger` defterine yazılmıştır; ancak `sync_events` içinde bekleyen bir `customer` kaydı olmadığı için pull ingestion uzaktaki eski bakiyeyi müşterinin üzerine doğrudan yazar! Yerel çift taraflı defter ile `customers.balance_cents` tablosu arasında mutabakat bozulur!
- **Test İllüzyonu:** Test 2'de (`stage10_gaps_verification_test.dart:149`), yapay olarak elle `entity_type: 'product'` kaydı eklenerek LWW koruması test edilmiş; ancak gerçek hayatta checkout'un bu kaydı üretmediği gizli kalmıştır.

---

## 5. OUTBOX VE SUNUCU SÖZLEŞMESİ DENETİMİ

[`sync_v4_outbox_processor.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart) ve `server/src/modules/sync_v4/`:

### 1. Nedensel Sıralama ve Grup Zaman Damgası
- Satır 61-69'daki alt sorgu:
  ```sql
  CASE WHEN group_id IS NOT NULL 
       THEN (SELECT MIN(s2.client_timestamp) FROM sync_events s2 WHERE s2.group_id = sync_events.group_id) 
       ELSE client_timestamp 
  END ASC,
  COALESCE(group_id, event_id) ASC,
  causal_sequence ASC
  ```
  Bu sorgu sayesinde finansal hareket daha eski zaman damgasına sahip olsa bile Satış (`causal_sequence: 1`) her zaman finansal hareketten (`causal_sequence: 2`) önce payload'a girmektedir (Test 9 ile kanıtlanmıştır).

### 2. Kısmi Batch Kabulü ve Kurtarma
- Satış kabul edilip (`SYNCED`), finansal işlem reddedildiğinde (`REJECTED`); satış kilitlenmekte ve tekrar gönderilmemektedir.
- Reddedilen mutasyonlar `getRejectedMutations()` ile listelenebilmekte ve `retryRejectedMutation()` ile yeniden denemeye alınabilmektedir (Test 10 ile kanıtlanmıştır).
- Ancak reddedilen finansal işlem için kullanıcı arayüzünde (UI) şu an hiçbir bildirim veya uyarı bulunmamaktadır.

---

## 6. TEST VE DOĞRULAMA ÇIKTILARI

Komutlar gerçek PowerShell terminalinde bağımsız olarak çalıştırılmıştır:

```powershell
$ flutter test test/core_next/stage10_gaps_verification_test.dart
00:00 +10: All tests passed!
Exit code: 0

$ flutter test test/core_next/
00:32 +83: All tests passed!
Exit code: 0
```

Tüm 83 test başarıyla geçmiş olmasına rağmen; yukarıdaki adli analiz, testlerin sentetik senaryoları doğruladığını ancak **uç noktalardaki finansal yarış durumlarını, eksik ödeme kanalı takibini ve Fail-Open RBAC açığını yakalamadığını** açıkça göstermiştir.

---

## 7. TESPİT EDİLEN BULGULAR VE ENTEGRASYON ENGELİ TABLOSU

| Bulgu No | Risk Seviyesi | Dosya ve Satır | Gözlenen Kod Davranışı | İşletmeye Olası Etkisi | Önerilen Düzeltme | Entegrasyona Engel mi? |
|---|---|---|---|---|---|---|
| **Bulgu 10.1.1** | **KRİTİK** | [`checkout_use_case.dart:64`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L64) | `actor == null` olduğunda `ActorContext.system` (`sysadmin`) rolüne yükseltilmektedir (Fail-Open). | Kimliği olmayan tüm istekler en yetkili yönetici gibi çalışır; yetkisiz iskonto ve veresiye engellenemez. | `actor` parametresi zorunlu (`required`) yapılmalı, `null` durumunda `AuthenticationRequiredException` fırlatılmalıdır. | **EVET (BLOKER)** |
| **Bulgu 10.1.2** | **KRİTİK** | [`sync_v4_pull_ingestion_service.dart:89-112`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart#L89-L112) | Pull ingestion LWW koruması sadece `sync_events`'taki `product` ve `customer` tiplerine bakar. Satış mutasyonları (`sale`) bu kümede yer almaz. | Çevrimdışı yapılan satışların yerel stok düşümleri ve müşteri borçları, uzak pull verisiyle sessizce ezilir; stok ve bakiye kaybı oluşur. | Pull sırasında bekleyen `sale` mutasyonlarının içerdiği ürünler ve müşteri bakiyeleri LWW koruma kümesine dahil edilmeli veya yerel defter esas alınmalıdır. | **EVET (BLOKER)** |
| **Bulgu 10.1.3** | **YÜKSEK** | [`refund_use_case.dart:245-255`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L245-L255) | İade use-case'i orijinal satışın ödeme türüne bakmaksızın, müşteri seçilmişse müşteriye alacak (`postRefund`) işler. | Peşin/nakit ödeyen müşteriye iade yapıldığında, müşteriye havadan cari alacak bakiyesi yazılır; işletme zarara uğrar. | Orijinal satışın `debt_cents` ve `paid_cents` oranları kontrol edilmeli; yalnızca veresiye kısmı cariye ters yazılmalı, nakit kısmı kasa hareketine yönlendirilmelidir. | **EVET (BLOKER)** |
| **Bulgu 10.1.4** | **YÜKSEK** | [`refund_use_case.dart:189-204`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L189-L204) | Tekrarlanan iade isteğinde idempotency ön kontrolü yoktur. Aynı idempotency anahtarı ile tekrar çağrıldığında SQLite UNIQUE hatası ile çöker. | Ağ kopması sonrası aynı iade tekrar yollandığında kullanıcı ekranında çökme veya bilinmeyen hata oluşur. | `CoreCheckoutUseCase`'deki gibi işlem öncesi `existingSales` idempotency sorgusu yapılmalı ve mevcut iade sonucu güvenle döndürülmelidir. | **EVET (BLOKER)** |
| **Bulgu 10.1.5** | **YÜKSEK** | [`refund_use_case.dart:109-122`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L109-L122) | Önceki iade miktarlarının okunması transaction dışındadır; aynı anda gelen iki iade yarış durumuna (race condition) neden olur. | Eşzamanlı iki istekte aynı ürün iki kez iade edilerek stok ve kasa haksız artırılabilir. | Kalan miktar sorgusu ve kontrolü doğrudan transaction içine alınmalıdır. | **EVET (BLOKER)** |
| **Bulgu 10.1.6** | **ORTA** | [`refund_use_case.dart:107`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L107) | `originalItemsMap` oluşturulurken aynı ürünün farklı satırları birbiri üzerine yazılmaktadır. | Aynı fişte birden fazla satırda bulunan ürünlerin kısmi iadesinde miktar sınırı yanlış hesaplanır. | Orijinal kalemler ürün bazında gruplanarak miktarları toplanmalıdır. | **HAYIR** |
| **Bulgu 10.1.7** | **ORTA** | [`refund_use_case.dart:268`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart#L268) | İade ödeme yöntemi outbox'ta sabit `'cash'` olarak kodlanmıştır; `sale_payments` tablosuna kayıt atılmamaktadır. | Kart iadeleri veya vadeli iptaller sunucuda nakit iade gibi raporlanır; kasa mutabakatı tutmaz. | İade için ödeme tipi parametresi alınmalı ve kasa defteriyle ilişkilendirilmelidir. | **HAYIR** |

---

## 8. NİHAİ KARAR VE DEĞERLENDİRME

### **KARAR: B**
> **En az bir kritik veya yüksek riskli engel devam ediyor; doğrudan canlı satış ekranı entegrasyonuna geçilemez.**

### Kararın Gerekçesi:
1. **Güvenlik Riski (Fail-Open):** `actor` parametresinin `null` geçilebilmesi ve `sysadmin` yetkisine yükseltilmesi kabul edilemez bir güvenlik açığıdır.
2. **Finansal Bütünlük Riski (Çevrimdışı Satış Ezilmesi):** Pull ingestion'ın bekleyen yerel satışları görmezden gelerek ürün stoğunu ve müşteri bakiyesini sunucudan gelen bayat veriyle ezmesi, saha kullanımında doğrudan envanter ve bakiye kaybına yol açar.
3. **Müşteri Cari Bozulması:** Nakit ödenmiş bir satışın iadesinde müşteriye cari alacak yazılması ciddi bir ticari finansal hatadır.
4. **Çökme Riski:** İade idempotency tekrarında unhandled database exception alınması operasyonel kesintiye yol açar.

### Bir Sonraki Adım Önerisi (Stage 10.2 — Güvenlik ve Finansal Düzeltmeler):
Canlı entegrasyona (`lib/presentation/sales/sales_screen.dart`) geçilmeden önce, yalnızca `core_next/` altında yukarıdaki 5 kritik ve yüksek riskli engelin (Bulgu 10.1.1 — 10.1.5) düzeltilmesi ve bu uç durumları kanıtlayan yeni negatif/stres testlerinin yazılması zorunludur.
