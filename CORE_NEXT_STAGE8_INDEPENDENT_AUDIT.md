# SERENUT OS — STAGE 8: BAĞIMSIZ FORENSİK ENTEGRASYON DENETİM RAPORU

**Belge Adı:** `CORE_NEXT_STAGE8_INDEPENDENT_AUDIT.md`  
**Aşama:** Stage 8 — Bağımsız Adli Kanıt Doğrulama, Dayanıklılık ve Entegrasyon Hazırlık Denetimi  
**Denetim Tarihi:** 13 Ekim 2026  
**Denetim Rolü:** Kıdemli Bağımsız Forensik Güvenlik ve Finansal Sistem Denetçisi  
**Proje Kökü:** `c:\Users\notop\AndroidStudioProjects\shaman_new`  
**Nihai Karar:** **HAZIR DEĞİL (ENTEGRASYON BLOKE)**

---

## 1. Yönetici Özeti

Stage 7 raporunda (`CORE_NEXT_STAGE7_FINANCIAL_RESILIENCE_REPORT.md`) yer alan "35 testin tamamı (%100) başarılı olmuştur", "üretim koduna dokunulmadı", "idempotency ve atomiklik kanıtlandı" iddiaları, Stage 8 kapsamında sıfırdan, bağımsız komut çıktıları, kaynak kod satır analizleri ve adli test çalıştırmalarıyla denetlenmiştir.

### Temel Denetim Bulguları:
1. **Kod İzolasyonu Korunmuştur:** `lib/` üretim dizininde `HEAD` commit'ine göre **0 diff** bulunmaktadır. Canlı satış ekranı (`sales_page.dart`) ve canlı veritabanı doğrudan değiştirilmemiştir.
2. **"35 Test %100 Başarılı" İddiası Yanlıştır (Test Çökmesi Tespit Edildi):** `flutter test test/core_next/` komutu bağımsız olarak yeniden çalıştırıldığında **Exit Code 1 (Hata)** ile sonuçlanmıştır. Toplam 35 testten **34'ü geçmiş, 1'i başarısız olmuştur** (`real_data_verification_test.dart` line 163: `Expected: <2>, Actual: <22>`). Testin canlı kullanıcı veritabanı dosyasını (`%APPDATA%`) doğrudan sandbox'a kopyalaması ve oradaki dinamik veriye katı sabit değerler koyması sonucu test kırılmıştır.
3. **Eşzamanlı Checkout (Concurrency) Korunmasızdır:** Idempotency kontrolü (`_db.query`), transaction başlatılmadan **önce** çalışmaktadır. İki eşzamanlı checkout isteği aynı anda geldiğinde yarış koşulu (race condition) oluşmakta, ikinci istek zarif bir replay yerine yakalanmamış SQLite `UNIQUE constraint failed: sales.idempotency_key` hatası fırlatmaktadır.
4. **Geçmiş Karma Ödemeler Aslında Geri Çatılamaz:** Eski veritabanı şemasında tek bir `payment_method` metin alanı bulunmakta; parçalı ödeme (split payment) tutarları geçmişte hiç kaydedilmemiştir. Migrasyon motoru eski satışları %100 nakit veya %100 kart olarak varsayıp aktarmaktadır. Bu durum geçmiş veri bütünlüğü açısından adli bir kabul sınırıdır; gerçek geçmiş karma veri gibi sunulamaz.
5. **Bulut Senkronizasyon İstemcisi Yoktur:** Sunucu tarafındaki `POST /api/v4/sync/push` ve `x-sync-protocol-version: 6` sözleşmesi doğrulanmış ancak `core_next/client_core` içinde bu sözleşmeyle konuşan hiçbir ağ servis istemcisi (sync worker/pusher) bulunmamaktadır. Yalnızca yerel `sync_events` tablosuna kayıt atılmaktadır.
6. **Donanım Katmanı Eksiktir:** ESC/POS ve TSPL bayt oluşturucuları simülasyonda çalışsa da, `HardwareWorker` içinde Windows Spooler (`winspool.drv`), USB RAW ve Terazi (RS-232 Seri Port) kodları tamamen eksiktir (yalnızca yorum satırları mevcuttur).

---

## 2. Gerçek Git Durumu ve Değişiklik Kapsamı

Komut satırından toplanan ham veriler:

* **Aktif Branch:** `main`
* **HEAD Commit SHA:** `28c158d88028f139e93f78982d4651ad424c61d2`
* **`git diff HEAD --stat`:** `0 files changed, 0 insertions, 0 deletions` (Tamamen temiz)
* **`git diff HEAD -- lib/`:** Çıktı boştur. Üretim kodunda Stage 4–7 arasında hiçbir değişiklik yapılmamıştır.
* **`git status --short` Çıktısı:**
  ```text
  ?? CORE_NEXT_INDEPENDENT_AUDIT.md
  ?? CORE_NEXT_SECOND_PASS_AUDIT.md
  ?? CORE_NEXT_STAGE3_FORENSIC_VERIFICATION.md
  ?? CORE_NEXT_STAGE4_FIX_REPORT.md
  ?? CORE_NEXT_STAGE5_FORENSIC_REPORT.md
  ?? CORE_NEXT_STAGE6_INTEGRATION_PREPARATION.md
  ?? CORE_NEXT_STAGE7_FINANCIAL_RESILIENCE_REPORT.md
  ?? core_next/
  ?? test/core_next/
  ```
* **Rapor Dosyaları Teyidi:**
  - `CORE_NEXT_STAGE6_INTEGRATION_PREPARATION.md` (Mevcut, 151 satır, 9.024 bayt)
  - `CORE_NEXT_STAGE7_FINANCIAL_RESILIENCE_REPORT.md` (Mevcut, 149 satır, 10.400 bayt)

---

## 3. Yeniden Çalıştırılmış Test Sonuçları

### 3.1. Ortam Bilgileri
* **Flutter Sürümü:** `3.29.3 • channel stable`
* **Dart Sürümü:** `3.7.2`
* **İşletim Sistemi:** Windows (x64)

### 3.2. Test Komutu Çıktısı (`flutter test test/core_next/`)
* **Çıkış Kodu (Exit Code):** `1` (**BAŞARISIZ**)
* **Test İstatistiği:** Toplam 35 test, **34 BAŞARILI, 1 BAŞARISIZ**

#### Dosya Bazında Gerçek Test Dağılımı ve Doğrulama Matrisi:

| Test Dosyası | Stage 7 Raporundaki İddia | Gerçek Test Sayısı | Gerçek Sonuç | Hata Detayı |
| :--- | :---: | :---: | :---: | :--- |
| `checkout_use_case_test.dart` | 7 | 7 | **PASS** | Hatasız tamamlandı |
| `database_integration_test.dart` | 3 | 3 | **PASS** | Hatasız tamamlandı |
| `fault_injection_migration_test.dart` | 2 | 2 | **PASS** | Hatasız tamamlandı |
| `financial_resilience_and_atomicity_test.dart` | 3 | 3 | **PASS** | Hatasız tamamlandı |
| `hardware_worker_test.dart` | *(Stage 7 tablosunda yok)* | 3 | **PASS** | Hatasız tamamlandı |
| `ledger_service_test.dart` | 10 *(Hatalı Bildirim)* | 7 | **PASS** | Gerçekte 7 test var, Stage 7 raporunda sehven 10 yazılmış |
| `migration_bridge_test.dart` | 4 | 4 | **PASS** | Hatasız tamamlandı |
| `real_data_verification_test.dart` | 3 | 3 | **FAIL (1 Hata)** | `Expected: <2>, Actual: <22>` (Satır 163) |
| `sales_engine_adapter_test.dart` | 3 | 3 | **PASS** | Hatasız tamamlandı |
| **TOPLAM** | **35 (İddia: %100 Pass)** | **35** | **34 PASS / 1 FAIL** | **GENEL SUITE EXIT CODE: 1** |

### 3.3. Başarısız Olan Testin Adli Analizi
`test/core_next/real_data_verification_test.dart` (Satır 163-164):
```dart
expect(report.customerDiscrepancies.length, 2,
    reason: 'Yalnızca Migration 60 stale trigger hatası olan 2 müşteride fark olmalıdır!');
```
* **Neden Başarısız Oldu?** Test, `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db` konumundaki canlı kullanıcı veritabanını okumaktadır. Canlı veritabanında müşteri sayısı 548'den 562'ye çıkmış ve `balance_minor != ROUND(balance * 100)` olan müşteri sayısı **22** adettir. Test ise sabit olarak `2` beklemektedir.
* **Adli Risk:** Birim/entegrasyon testinin, ana makinenin AppData dizinindeki değişen kullanıcı verisine bağımlı olması (hermetik olmaması) test kararlılığını bozmaktadır.

---

## 4. Kanıtlanan Bulgular

Aşağıdaki özelliklerin kaynak kodda bulunduğu ve testlerle doğrulandığı kanıtlanmıştır:

1. **Finansal Tamsayı Kuruş Mimarisi (`MoneyCents`):**
   * Dosya: [`money_cents.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/money_cents.dart#L1-L60)
   * `int value` olarak tutulmakta, float yuvarlama hatası (0.1 + 0.2) yaşanmamaktadır.
   * Kanıt Testi: [`ledger_service_test.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/ledger_service_test.dart#L44-L50)
2. **Ticari Yarım-Yukarı (Half-Up) Tartılı Gramaj Hesabı:**
   * Dosya: [`core_sales_flow_state.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/presentation/sales/core_sales_flow_state.dart#L28-L32)
   * `rawCents = (unitPrice.value * quantity + 500) ~/ 1000;` ile tam tamsayı yuvarlama yapılmaktadır.
   * Kanıt Testi: [`checkout_use_case_test.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/checkout_use_case_test.dart#L90-L135)
3. **Ardışık Idempotent Replay (Aynı İstek Tekrarı):**
   * Dosya: [`checkout_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L100-L108)
   * Aynı fiş numarası ve aynı sepet ile tekrar çağrıldığında stok tekrar düşülmemekte, kasa hareketi tekrar yazılmamakta, mevcut satış döndürülmektedir.
   * Kanıt Testi: [`financial_resilience_and_atomicity_test.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/financial_resilience_and_atomicity_test.dart#L158-L176)
4. **Idempotency Çakışma Reddi (Conflict Rejection):**
   * Dosya: [`checkout_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L109-L114)
   * Aynı idempotency key ile farklı tutarlı sepet geldiğinde `StateError` fırlatılmaktadır.
   * Kanıt Testi: [`financial_resilience_and_atomicity_test.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/financial_resilience_and_atomicity_test.dart#L177-L193)
5. **Tek SQLite Transaction Kapsamı ve Rollback:**
   * Dosya: [`checkout_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L160-L277)
   * `sales`, `sale_items`, `products (stok)`, `sale_payments`, `cash_transactions`, `ledger_entries`, `sync_events` tabloları tek bir `_db.transaction((txn) async { ... })` bloğu içindedir.
   * 5 aşamalı hata simülasyonunda (`after_sales_insert`, `after_items_insert`, `after_payments_insert`, `after_ledger_insert`, `after_sync_events_insert`) tüm yazımların ve bakiye/stokların sıfır artıkla geri alındığı kanıtlanmıştır.
   * Kanıt Testi: [`financial_resilience_and_atomicity_test.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/financial_resilience_and_atomicity_test.dart#L195-L262)
6. **Sıfır, Negatif ve Fazla Ödeme Korumaları:**
   * Dosya: [`checkout_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L66-L84)
   * `totalCents <= 0`, `paidCents > totalCents`, split negatif tutar ve müşterisiz veresiye işlemleri engellenmektedir.
   * Kanıt Testi: [`financial_resilience_and_atomicity_test.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/financial_resilience_and_atomicity_test.dart#L81-L129)

---

## 5. Doğrulanamayan ve Çürütülen İddialar

1. **"35 Testin Tamamı Başarılıdır" İddiası: ÇÜRÜTÜLDÜ.**
   * `flutter test test/core_next/` komutu Exit Code 1 vermektedir. `real_data_verification_test.dart` başarısızdır.
2. **"Idempotency Tüm Eşzamanlı Yarış Koşullarını Çözmüştür" İddiası: DOĞRULANAMADI.**
   * [`checkout_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L87-L93) satırlarında `_db.query` transaction dışındadır. Aynı anda gelen 2 istek bu sorguyu aynı anda geçer ve `txn.insert` anında SQLite `DatabaseException (UNIQUE constraint)` hatasıyla çöker. Eşzamanlı test paketi bulunmamaktadır.
3. **"Geçmiş Karma Ödemeler Kuruşu Kuruşuna Aktarılmıştır" İddiası: DOĞRULANAMADI (Mümkün Değil).**
   * Eski şemada geçmiş satışlarda karma ödeme dağılımı (örn. 50 TL nakit + 50 TL kart) tutulmamıştır. [`migration_bridge_engine.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart#L351-L374) satırları tüm `paidCents` tutarını tek bir ödeme tipine atamaktadır.
4. **"Sunucu Senkronizasyon İstemcisi Hazırdır" İddiası: DOĞRULANAMADI.**
   * `core_next/client_core` içinde HTTP push/pull veya WebSocket istemcisi yoktur.
5. **"Donanım Katmanı Hazırdır" İddiası: DOĞRULANAMADI.**
   * `HardwareWorker` içinde Windows Spooler ve Seri Port (Terazi) kodları fiilen mevcut değildir; sadece TCP/IP soket vardır.

---

## 6. Risk Matrisi (Kritik / Yüksek / Orta / Düşük)

```
+--------------------------------------------------------------------------+
| KRİTİK (Bloker)                                                          |
| 1. real_data_verification_test.dart kırık (Exit Code 1)                  |
| 2. Eşzamanlı (concurrent) checkout yarış koşulu ve yakalanmamış SQLite   |
|    UNIQUE constraint çökmesi                                             |
| 3. core_next içinde sunucu senkronizasyon istemcisinin bulunmaması        |
+--------------------------------------------------------------------------+
| YÜKSEK (Entegrasyon Riski)                                               |
| 1. Donanım katmanında USB RAW / Windows Spooler ve Terazi kodunun        |
|    bulunmaması                                                           |
| 2. İade (Refund), İptal (Void) ve Parçalı İade motorunun core_next       |
|    içinde henüz yazılmamış olması                                        |
| 3. Testin yerel AppData canlı veritabanı yoluna sıkı sıkıya bağlı olması |
+--------------------------------------------------------------------------+
| ORTA                                                                     |
| 1. Geçmiş satış aktarımında karma ödeme kırılımının eksikliği             |
| 2. SalesEngineAdapter'ın legacy modunda yalnızca mock dönmesi             |
+--------------------------------------------------------------------------+
| DÜŞÜK                                                                    |
| 1. Raporlama belgelerindeki test adedi yazım farkı (10 yerine 7)          |
+--------------------------------------------------------------------------+
```

---

## 7. Finansal ve Migrasyon Riskleri

1. **Yarıda Kalan veya Tekrarlanan Migrasyon Davranışı:**
   * [`migration_bridge_engine.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart#L347) üzerinde `sales` ve `sale_payments` eklenirken `ConflictAlgorithm.ignore` kullanılmıştır.
   * Migrasyon tekrar çalıştırıldığında eski satışlarda bir düzeltme yapılmışsa hedef veritabanına yansımaz.
2. **Eski Veritabanına Eşzamanlı Yazma Riski:**
   * Migrasyon 37.000 ürün için 5 ila 15 saniye sürmektedir. Bu esnada eski uygulama açık kalır ve SQLite'a yazarsa veri tutarsızlığı oluşabilir. Migrasyon esnasında eski veritabanı kilitlenmemektedir.
3. **İade (Refund) ve Defter Dengesizliği:**
   * `core_next` şu anda sadece `debitSale` (satış borçlandırma) ve `postCollection` (tahsilat) metodlarına sahiptir. İade edilen bir fişte müşteri bakiyesinin ve stokların nasıl geri alınacağına dair use case yoktur.

---

## 8. Senkronizasyon Sözleşmesi Adli Analizi

Sunucu kaynak kodları ([`server/src/modules/sync_v4/sync-v4.routes.ts`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts)) incelenerek sözleşme doğrudan kaynaktan doğrulanmıştır:

* **Gerçek Uç Nokta:** `POST /api/v4/sync/push`
* **Zorunlu Başlıklar:**
  - `x-sync-protocol-version: 6` (Eksik veya farklıysa HTTP 426 `sync_protocol_upgrade_required` döner).
  - `x-device-activation-id`: UUID
  - `x-device-id`: String (device_hash)
* **İdempotency ve Yarış Koruması:**
  - Sunucu önce `pg_advisory_xact_lock(hashtext(company_id), hashtext('operational-reset'))` kilidi alır.
  - Her mutasyon için `SELECT revision FROM sync_v4_changes WHERE tenant_id = $1 AND mutation_id = $2::uuid` kontrol edilir. Varsa yan etkisiz olarak mevcut revision döner.
* **İstemci Tarafındaki Durum:**
  - `core_next/client_core` içinde bu API'ye istek atan bir HTTP istemcisi **YOKTUR**.
  - Checkout anında yalnızca yerel SQLite `sync_events` tablosuna `PENDING` durumuyla JSON yazılmaktadır ([`checkout_use_case.dart:L266-L274`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L266-L274)).

---

## 9. Fiziksel Donanım Doğrulama Durumu

[`core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart#L137-L155):
* **ESC/POS ve TSPL Bayt Üretimi:** Birim testlerde bayt formatı (kâğıt kesme, barkod komutları) doğrulanmıştır.
* **Ağ Yazıcısı (TCP/IP):** Kod mevcuttur (`Socket.connect` port 9100).
* **USB / Windows Spooler (`winspool.drv`):** Kod **YOKTUR** (satır 153'te açıklama satırı olarak bırakılmıştır).
* **Terazi (RS-232):** Kod `core_next` içinde **YOKTUR**.
* **Karar:** Donanım entegrasyonu tamamlanmamıştır; fiziksel cihaz doğrulaması yapılmadan sahaya verilemez.

---

## 10. Eksik Testler ve Somut Kabul Kriterleri

Entegrasyon onayının verilebilmesi için aşağıdaki testlerin yazılması ve geçmesi şarttır:

1. **Eşzamanlı Checkout (Concurrency Test):**
   * Aynı idempotency anahtarıyla aynı anda iki `checkoutUseCase.execute()` çağrısı `Future.wait` ile tetiklenmeli; biri başarıyla tamamlanırken diğeri SQLite UNIQUE çökmesi yaşamadan zarifçe bekleyip idempotent replay sonucunu dönmelidir.
2. **Hermetik Canlı Veri Testi:**
   * `real_data_verification_test.dart` içindeki canlı `%APPDATA%` mutlak dosya yolu bağımlılığı kaldırılmalı; test izole bir fixture veritabanı üzerinde çalışmalı ve `customerDiscrepancies.length` beklentisi dinamik veya izole veri kümesine uygun olmalıdır.
3. **Satış İadesi ve İptal (Void/Refund Test):**
   * Tamamlanmış bir satışın iadesi yapıldığında `sale_payments`, `cash_transactions` ve `products.stock_quantity` kalemlerinin simetrik ters hareketlerinin test edilmesi.
4. **Bulut Senkronizasyon İstemci Entegrasyon Testi:**
   * `sync_events` tablosundaki kayıtları alıp `POST /api/v4/sync/push` formatına çeviren, HTTP 426/409 yanıtlarını işleyen bir istemci servis testi.

---

## 11. Nihai Karar

### **KARAR: HAZIR DEĞİL (ENTEGRASYON BLOKE)**

### Kararın Gerekçesi:
1. `flutter test test/core_next/` komutunun bağımsız çalıştırılmasında **Exit Code 1 (Hata)** alınması,
2. Eşzamanlı iki satış isteğinde SQLite UNIQUE constraint çökme açığının bulunması,
3. `core_next` paketinde sunucu senkronizasyon istemcisinin ve USB/Terazi donanım sürücülerinin henüz bulunmaması,
4. Canlı satış ekranına bağlanacak `SalesEngineAdapter`'ın henüz üretim akışına bağlanabilecek olgunlukta olmaması.

Mevcut kod dondurması (`lib/` 0 diff) korunmalı, canlı dağıtım ve entegrasyon yapılmamalıdır.
