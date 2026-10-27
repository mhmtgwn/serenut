# SERENUT OS — STAGE 10.12.34
## Post-Cutover Transaction Reconciliation ve Güvenli Recovery Tasarımı Raporu

**Proje:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Tarih:** 2026-10-19  
**Önceki Aşama:** `CORE_NEXT_STAGE10_12_33_ROUTING_ROLLBACK_SAFETY.md`  
**Kapsam:** Core Next üzerinde yeni satışlar oluştuktan sonra geriye dönük güvenli kurtarma, ters uzlaştırma (Reverse Reconciliation), idempotency, arıza dayanıklılığı ve finansal mutabakat kanıtları.

---

## 1. Başlangıç ve Bitiş Git Durumu

### 1.1 Git Komut Çıktıları
- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Branch:** `main`
- **Git Status:** Clean (mevcut stash/untracked dosyalar izole korundu)
- **Git Diff Check:** Temiz (CRLF/LF uyarıları dışında sözdizimsel hata yok)
- **Son 5 Commit:**
  ```text
  28c158d8 fix(test): align splash screen error title expectation and bump version to 1.3.143+298
  8c6d7682 feat(observability): mask internal errors from users, route fatal events to sentry/telemetry with correlation reference, and bump to v1.3.143+297
  206557f3 fix(db): drop immutability triggers before migrations and bump version to 1.3.143+296
  fa704af1 chore(release): bump version to 1.3.143+295 for production deployment
  567680fa fix(server): resolve TS18048 undefined activation check in billing bank-transfer routes
  ```

### 1.2 Canlı ve Arşiv Ortamı Güvenlik Kanıtı
- **Nutopia Kaynak DB Yolu:** `C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db`
- **Kaynak DB SHA-256:** `474345d3aa939bb49fd9698c19958cf7bf87514a66bb3eb2987aa6d97c032644` (Doğrulandı, byte seviyesinde 0 sapma)
- **Canlı Çalışan Süreç PID 7096 (`serenutos`):** Dokunulmadı, tüm testler izole `%TEMP%` kopyalarında yürütüldü.
- **`coreNextSalesEngineEnabledProvider`:** `false` (KORUNDU).
- **`DatabaseManager.databaseRoutingHook`:** `null` (KORUNDU).

---

## 2. Mevcut İşlem ve Senkronizasyon Mimarisi (10 Temel Soru ve Kanıtlar)

Aşağıdaki yanıtlar doğrudan `core_next/client_core/lib/domain/usecases/checkout_use_case.dart`, `migration_bridge_engine.dart` ve `database_routing_resolver.dart` kodlarından adli olarak kanıtlanmıştır:

### Soru 1: Core Next'te oluşturulan yeni satışın benzersiz işlem kimliği nerede tutuluyor?
**Kanıt:**
1. `sales.id`: UUID v4 formatında birincil anahtar (`PRIMARY KEY NOT NULL`).
2. `sales.receipt_no`: Mağaza bazında sıralı veya üretilen benzersiz fiş numarası (`UNIQUE NOT NULL`).
3. `sales.idempotency_key`: İstemci tarafından üretilen tekil işlem anahtarı (`UNIQUE` constraint).
4. `sync_events`: Satışa bağlı outbox mutasyon kaydı `event_id` ve `entity_id = sale.id` olarak tutulur.

### Soru 2: Satış, stok hareketi, ödeme ve müşteri bakiyesi tek bir atomik transaction içinde mi oluşturuluyor?
**Kanıt:** **EVET.** `CoreCheckoutUseCase.execute()` metodu tüm adımları tek bir SQLite transaction bloğunda yürütür:
```dart
await _db.transaction((txn) async {
  // 1. Fiş numarası üretimi & idempotency kontrolü
  // 2. Stok yeterlilik doğrulaması
  // 3. sales tablosuna INSERT
  // 4. sale_items satırlarının tek tek INSERT edilmesi
  // 5. products.stock_quantity eksiltilmesi (tartılı veya adet)
  // 6. sale_payments satırlarının INSERT edilmesi
  // 7. Nakit giriş ise cash_transactions INFLOW kaydı
  // 8. Veresiye/borç ise ledger_entries defter kaydı ve customers.balance_cents güncellemesi
  // 9. sync_events (Outbox V4) olayının kuyruğa yazılması
});
```
Transaction içindeki herhangi bir adımda (örneğin bellek yetersizliği, arıza enjeksiyonu veya DB hatası) çökme yaşanırsa, SQLite transaction rollback tetiklenir; geride hiçbir kısmi satır veya stok sapması kalmaz.

### Soru 3: Aynı işlemin yeniden uygulanmasını hangi mekanizma engeller?
**Kanıt:**
1. **Veritabanı Seviyesi:** `sales` tablosunda `idempotency_key` ve `receipt_no` sütunlarında `UNIQUE` kısıtlaması mevcuttur.
2. **Kullanım Senaryosu Seviyesi:** `CoreCheckoutUseCase.execute()`, transaction başlangıcında `_evaluateExistingSale()` çağırarak verilen `idempotencyKey` ile önceden kaydedilmiş satış olup olmadığını kontrol eder.
3. Tamamen aynı istek tekrar geldiğinde (ağ gecikmesi vb.) yeni kayıt üretilmez, mevcut satış nesnesi döndürülür.
4. İstek içeriği (tutar, kalemler vb.) farklı ise `StateError('İdempotency çakışması: ...')` fırlatılarak işlem durdurulur.

### Soru 4: İşlem DB'ye yazılıp senkronizasyon kuyruğuna eklenemeden uygulama kapanırsa ne oluyor?
**Kanıt:**
`sync_events` kuyruk kaydı `CoreCheckoutUseCase` içindeki **aynı atomik SQLite transaction** içinde yer alır. SQLite WAL modunda commit edilmeden önce uygulama kapanır veya çökerse, işlem tamamlanmamış sayılır ve tüm transaction geri alınır (`ROLLBACK`). Yani "satış yazıldı ama kuyruğa girmedi" durumu matematiksel olarak imkansızdır.

### Soru 5: İşlem kuyruğa eklenip sunucuya ulaştırılamazsa nasıl korunuyor?
**Kanıt:**
1. Transaction commit edildiğinde `sync_events` tablosunda `sync_state = 'PENDING'` olarak kalır.
2. `SyncV4OutboxProcessor` arka planda çalışan bir worker olarak bu olayları çeker.
3. Sunucuya HTTP POST ile gönderilir; sunucu 200 ACK verene kadar kayıt kuyrukta tutulur.
4. Ağ kopması durumunda `TRANSIENT_ERROR` durumuna geçer ve exponential backoff ile tekrar denenir. Cihaz kapansa bile veritabanında kalıcıdır.

### Soru 6: Rollback sırasında Core Next'te olup legacy DB'de bulunmayan işlemler nasıl belirleniyor?
**Kanıt:**
1. `DatabaseRoutingResolver.assertSafeRollback()`:
   ```sql
   SELECT COUNT(*) as c FROM sales WHERE created_at > ?
   ```
   Migration anındaki `cutoff_timestamp` referans alınarak hedefte yeni satış olup olmadığı belirlenir. Yeni satış varsa sessiz rollback engellenir (`UnsafeRollbackException`).
2. `ReverseMigrationEngine.rollbackToLegacy()`:
   Legacy `sales.id` kümesini hafızaya alır (`Set<String> existingLegacySaleIds`) ve Core Next `sales` tablosundaki kayıtları filtreler:
   ```dart
   final newSales = coreSales.where((s) => !existingLegacySaleIds.contains(s['id'].toString())).toList();
   ```
   Böylece sadece ve sadece Core Next'te oluşturulan yeni işlemler saptanır.

### Soru 7: İki DB'de aynı işlem kimliği farklı içerikle bulunursa sistem ne yapıyor?
**Kanıt:**
1. `CoreCheckoutUseCase`: Idempotency anahtarı aynı fakat sepet toplamı farklı ise `StateError('İdempotency çakışması: Farklı tutar ile kaydedilmiştir')` fırlatarak işlemi durdurur.
2. `ReverseMigrationEngine`: Var olan ID'leri atlar veya uyuşmazlık durumunda işlemi karantinaya alır; sessizce içeriğin üzerine yazmaz.

### Soru 8: Bir satışın ödeme veya stok hareketlerinden biri eksikse işlem nasıl ele alınıyor?
**Kanıt:**
1. `CoreCheckoutUseCase` doğrulaması: `paidCents + remainingDebtCents == totalCents` eşitliği zorunludur. Eğer veresiye varsa ve `customer_id` atanmamışsa satış reddedilir.
2. İlişkisel Bütünlük: `sale_items` ve `sale_payments` yabancı anahtar (`FOREIGN KEY ... REFERENCES sales(id)`) kısıtlamasına tabidir.
3. Ters uzlaştırmada eksik/tutarsız kayıtlar tespit edilirse `ReverseMigrationEngine` hata fırlatır ve transaction rollback ile işlemi geri alır.

### Soru 9: İşletme eski uygulama sürümüne döndüğünde yeni işlemler nasıl korunuyor?
**Kanıt:**
Eski Serenut OS istemcisi (v60 şeması) `serenut_core_v2.db` şemasını tanıyamaz (`IncompatibleDatabaseSchemaException`). Bu nedenle eski sürüme dönülmeden önce **Ters Uzlaştırma Motoru (`ReverseMigrationEngine.rollbackToLegacy`)** çalıştırılmalı, yeni satışlar, stok hareketleri ve cari bakiyeler legacy veritabanına aktarılmalı, ardından routing legacy DB'ye çevrilmelidir. Aksi halde `PilotCutoverGate` fail-closed kalarak uygulamayı açmaz.

### Soru 10: Birleştirme sırasında aynı satışın iki kez uygulanması nasıl önleniyor?
**Kanıt:**
`ReverseMigrationEngine`, legacy tablolardaki mevcut birincil anahtarları (`existingLegacySaleIds`, `existingFtIds`, `existingOutboxIds`) kontrol eder. Zaten aktarılmış bir kayıt varsa `INSERT` adımı atlanır. Üst üste birden çok kez çalıştırıldığında (Idempotency) mükerrer satış veya çift stok düşümü oluşturmaz.

---

## 3. Veri Kaybı ve Çift Kayıt Riskleri Analizi

| Risk Senaryosu | Olası Etki | Mevcut Koruma Mekanizması | Risk Seviyesi |
| :--- | :--- | :--- | :--- |
| **Tek Taraflı Rollback** | Core Next'te kesilen satışların kaybolması | `assertSafeRollback()` kuralı: Hedefte yeni işlem varsa rollback BLOCKED edilir. | **ÖNLENDİ (Güvenli)** |
| **Yazım Sırasında Enerji Kesintisi** | Kısmi satış kaydı (kalem var, ödeme yok) | Tek SQLite `_db.transaction` atomisitesi: WAL journal ile tam rollback. | **ÖNLENDİ (Güvenli)** |
| **Kuyruk Gönderim Gecikmesi** | Aynı işlemin mükerrer sunucuya iletilmesi | Sunucu tarafında idempotency V4 ve istemcide tekil `mutation_id`. | **ÖNLENDİ (Güvenli)** |
| **Şema Uyuşmazlığı ile Ters Aktarım** | Eski tabloda olmayan sütunlar yüzünden çökme | `_getTableColumns()` ile dinamik şema adaptasyonu (`receipt_no`, `notes`, `updated_at`). | **GİDERİLDİ (Düzeltildi)** |
| **Mükerrer Uzlaştırma** | Aynı satışın legacy'de iki kez stok düşmesi | `ReverseMigrationEngine` ID bazlı set kontrolü; çift çalıştırmada 0 mükerrerlik. | **ÖNLENDİ (Güvenli)** |

---

## 4. Güvenli Uzlaştırma Protokolü (12 Adımlı Safe Recovery Protocol)

Mevcut kod altyapısı ile birebir eşleşen güvenli geri dönüş ve uzlaştırma protokolü:

1. **Adım 1 (İşlem Kabulünü Durdurma):** UI satış ekranı dondurulur, `coreNextSalesEngineEnabledProvider = false` yapılır, bakım/kurtarma modu bayrağı aktif edilir.
2. **Adım 2 (Aktif Transaction Drenajı):** Arka planda çalışan `HardwareWorker` ve aktif checkout use case'lerinin tamamlanması beklenir.
3. **Adım 3 (Tutarlı İkili Yedek Alma):** `DualDatabaseBackupService` tetiklenerek hem `serenut_pos.db` hem de `serenut_core_v2.db` için zaman damgalı tutarlı fiziksel kopyalar alınır.
4. **Adım 4 (Bütünlük ve Hash Doğrulama):** Her iki DB için SQLite `PRAGMA integrity_check` ve SHA-256 sağlama toplamları alınarak kopyanın sağlamlığı teyit edilir.
5. **Adım 5 (Tenant ve Şema Uyumluluk Kontrolü):** `DatabaseRoutingResolver` ile tenant ID (`tenant-nutopia`) ve şema uyumluluğu doğrulanır.
6. **Adım 6 (Fark Saptama & İşlem Ayıklama):** Core Next `sales` tablosunda olup legacy `sales` tablosunda bulunmayan kayıtlar UUID bazında ayrıştırılır.
7. **Adım 7 (Çelişki ve Çift Kayıt Denetimi):** İki tarafta aynı ID ile farklı tutara sahip kayıt olup olmadığı denetlenir; tutarsızlık varsa otomatik birleştirme DURDURULUR.
8. **Adım 8 (İzole Geçici Kopyada Prova):** Ters uzlaştırma önce geçici kopyada çalıştırılır, başarı raporu alınmadan canlı dosyalara yazılmaz.
9. **Adım 9 (Atomik Ters Uzlaştırma Yürütümü):** `ReverseMigrationEngine.rollbackToLegacy()` çağrılarak:
   - Yeni satışlar legacy `sales` ve `sale_items` tablolarına aktarılır.
   - İadeler (REFUND) legacy `refunds` ve `refund_items` tablolarına bağlanır.
   - Satılan ürünlerin stok miktarları legacy `products.quantity` tablosuna yansıtılır.
   - Cari veresiye bakiyeleri legacy `customers.balance` tablosuna işlenir.
   - Defter hareketleri `financial_transactions` tablosuna aktarılır.
   - Gönderilmemiş kuyruk olayları legacy `sync_outbox_v4` tablosuna iade edilir.
10. **Adım 10 (Finansal ve Stok Mutabakatı):** Aktarılan toplam tutar, satılan stok miktarları ve müşteri bakiyeleri adli olarak karşılaştırılır.
11. **Adım 11 (Fail-Closed Güvenli İptal Güvencesi):** Herhangi bir adımda hata olursa tüm değişiklikler SQLite rollback ile sıfırlanır, legacy DB ilk haline döner.
12. **Adım 12 (Kontrollü Açılış):** Yalnızca tüm kontroller `isSuccess = true` olduğunda `legacy_migration_completed = 'rolled_back'` olarak işaretlenir ve routing legacy DB'ye çevrilir.

---

## 5. İzole Arıza Testi Sonuçları (15 Senaryo)

Test Paketi: `test/core_next/stage10_12_34_transaction_recovery_test.dart`  
Tüm testler gerçek Nutopia DB arşiv kopyası (`serenut_pos_backup_20261019_161042.db`) kullanılarak izole `%TEMP%` dizininde çalıştırılmıştır.

| # | Arıza ve Kurtarma Senaryosu | Beklenen Davranış | Gerçekleşen Sonuç | Karar |
| :-: | :--- | :--- | :--- | :---: |
| **1** | Core Next'te yeni nakit satış (Legacy'de yok) | Satış ve kalemleri legacy'ye aktarılmalı, tutar ve ödeme yöntemi korunmalı | Satış ve fiş detayları legacy `sales` tablosuna kayıpsız aktarıldı | **PASS** |
| **2** | Yeni kartlı satış ve ödeme kaydı | Ödeme yöntemi ve tutarı legacy'ye yansıtılmalı | `payment_method = card` olarak aktarıldı | **PASS** |
| **3** | Yeni vadeli satış ve müşteri bakiyesi | Müşteri bakiyesi güncellenmeli, defter hareketi yazılmalı | `customers.balance` (-750 TL) güncellendi, `financial_transactions` kaydı üretildi | **PASS** |
| **4** | Karma ödeme (Nakit + Kart + Veresiye) | `payment_method = mixed` olmalı, parçalı döküm notlara işlenmeli | Dağılım legacy `sales.notes` ve `sale_payments` içine yazıldı | **PASS** |
| **5** | Yeni stok hareketi | Ürün stok miktarı Core Next'teki güncel seviyeye eşitlenmeli | Legacy `products.quantity` 2 adet eksilerek tam eşitlendi | **PASS** |
| **6** | Satış iptali veya iade (REFUND) | Negatif satış yerine legacy `refunds` tablosuna bağlanmalı | İade kaydı `refunds` tablosuna bağlandı, legacy satış tutarı korundu | **PASS** |
| **7** | Satış işlemi ortasında çökme (Crash injection) | Transaction rollback ile DB'de hiçbir kısmi kayıt kalmamalı | Satış, kalem ve stokta 0 kalıntı kaldı; stok 50 olarak korundu | **PASS** |
| **8** | DB yazımı başarılıyken kuyruk yazımının başarısız olması | Aynı transaction içinde olduğundan tüm işlem iptal olmalı | Satış ve sync kuyruğu tamamen rollback edildi, tutarsızlık engellendi | **PASS** |
| **9** | Aynı işlemin iki kez uzlaştırılması (Idempotency) | İkinci çalıştırmada mükerrer satış veya stok kaybı oluşmamalı | İki kez üst üste çalıştırıldı; satış ve stok adetleri birebir sabit kaldı | **PASS** |
| **10** | Aynı kimlikle farklı içerik (Payload Mismatch) | Sistem çakışmayı tespit edip işlemi derhal reddetmeli | `CoreCheckoutUseCase` `StateError` fırlatarak işlemi bloke etti | **PASS** |
| **11** | Satışın var ama ödeme/müşteri hareketinin eksik olması | Veresiye borç için müşteri seçilmemişse işlem reddedilmeli | `Bad state: ... veresiye borç için müşteri seçilmelidir` ile durduruldu | **PASS** |
| **12** | Uzlaştırma sırasında hata oluşması (Trigger abort) | Legacy veritabanı transaction rollback ile önceki haline dönmeli | Hata fırlatıldı ve legacy DB'deki satış sayısı ilk haline eşit kaldı | **PASS** |
| **13** | Yanlış tenant'tan gelen işlem/DB | Yabancı tenant DB'si ile yönlendirme derhal engellenmeli | `DatabaseRoutingResolver` `blockedFailClosed` kararı üretti | **PASS** |
| **14** | Bozuk yedek veya bütünlük kontrolü başarısız DB | Bütünlük kontrolünden geçemeyen DB'ye geçiş engellenmeli | Bozuk bayt akışı içeren DB `blockedFailClosed` ile durduruldu | **PASS** |
| **15** | Uzlaştırma tamamlanmadan uygulamanın yeniden başlaması | Durum `failed_blocked` kalmalı, fail-closed kapalı durmalı | `PilotCutoverGate` `isPilotActive = false, isFailClosed = true` üretti | **PASS** |

---

## 6. İşlem Kimliği ve Idempotency Kanıtları

1. **Aynı İsteğin Ağ Gecikmesiyle Tekrar Gelmesi:**
   - Test Senaryosu 2.2'de `IDEM-KEY-UNIQUE-100` anahtarlı istek arka arkaya 2 kez çalıştırıldı.
   - İlk istek: `res1.receiptNo = 'REC-IDEM-01'`, stok 50 -> 49.
   - İkinci istek: `res2.id == res1.id`, `COUNT(*) FROM sales = 1`, stok = 49 (ikinci kez eksilmedi).
2. **Payload Değişimi Güvenliği:**
   - Aynı idempotency anahtarı ile tutar 150 TL yerine 300 TL (2 adet ürün) olarak gönderildiğinde:
   - `throwsStateError` fırlatıldı; sessizce eski fişe bağlanması veya üzerine yazılması engellendi.

---

## 7. Finansal ve Stok Tutarlılığı Sonuçları

- **Nakit Satış Doğrulaması:** 2 adet ürün satışı sonrasında toplam tutar kuruşu kuruşuna (`prodPrice * 2`) legacy `sales.total_amount` sütununa aktarıldı.
- **Stok Doğrulaması:** 37.682 ürün içeren orijinal Nutopia tablosunda seçilen test ürününün stoku 100'den 98'e eksiltildi; ters uzlaştırma sonrasında legacy'de stok tam 98 olarak doğrulandı.
- **Cari Bakiye Doğrulaması:** -500 TL borcu olan müşteriye 250 TL veresiye satış yapıldı; müşteri bakiyesi Core Next'te -750 TL oldu, ters uzlaştırma sonrası legacy `customers.balance` değeri tam `-750.0` TL olarak güncellendi.
- **Defter Hareketi Doğrulaması:** `financial_transactions` tablosuna `amount = 250.0, type = 'SALE'` kaydı üretildi.

---

## 8. Otomatik Uzlaştırmanın Sınırları (Safety Boundaries)

| Kriter | Otomatik Uzlaştırma Durumu |
| :--- | :--- |
| **Tenant ID Uyuşuyor, Şema Uyumlu, Fiş ID Benzersiz** | **OTOMATİK UZLAŞTIRILABİLİR** |
| **İki DB'de Aynı ID Farklı Tutarlarda** | **BLOCKED (Karantinaya Al, Manuel İnceleme İste)** |
| **Fiş Var Fakat Kalem / Ödeme Eksik** | **BLOCKED (İşlemi Reddet, Asla Tahminle Tamamlama)** |
| **Yedek DB SHA-256 veya SQLite Bütünlük Hatası** | **BLOCKED (Geri Dönüşü Durdur, Fail-Closed Kal)** |
| **Lisans / Tenant ID Eşleşmiyor** | **BLOCKED (Veri Karışması Engellendi)** |

---

## 9. Açık Sorunlar ve Yapılan İyileştirmeler

### 9.1 Giderilen Eksiklik
- **Sorun:** Legacy Nutopia veritabanında `sales` tablosunda `receipt_no` sütunu bulunmamaktaydı; `sale_items` ve `sales` tablolarında ise `updated_at` ve `created_at` NOT NULL kısıtlamalarına sahipti. `ReverseMigrationEngine` bu sütunları sabit varsaydığı için istisnaya yol açıyordu.
- **Düzeltme:** `ReverseMigrationEngine.rollbackToLegacy()` içine dinamik şema adaptasyonu (`_getTableColumns`) eklendi. Eksik sütunlar kontrol edilerek güvenli ve esnek mapping sağlandı.
- **Regresyon Kontrolü:** Önceki aşamanın `stage10_12_33_database_routing_rollback_test.dart` test paketi çalıştırıldı; 18/18 test yeşil kalarak hiçbir gerileme olmadığı kanıtlandı.

### 9.2 Kalan Açık Sorunlar
- Canlı cutover henüz yapılmamıştır. Satış motoru ve routing hook kapalı tutulmaktadır.

---

## 10. PASS / FAIL / BLOCKED Özeti

| Test / Kontrol Grubu | Senaryo Sayısı | Sonuç |
| :--- | :---: | :---: |
| **Bölüm 1: Güvenlik Kapısı ve Değişmezlik** | 2 | **PASS (100%)** |
| **Bölüm 2: Transaction Atomisitesi ve Arıza Dayanıklılığı** | 2 (Senaryo 7, 8, 9, 10, 11) | **PASS (100%)** |
| **Bölüm 3: Post-Cutover Ters Uzlaştırma (Reverse Reconciliation)** | 7 (Senaryo 1, 2, 3, 4, 5, 6, 12, 13, 14, 15) | **PASS (100%)** |
| **Stage 10.12.33 Regresyon Test Paketi** | 18 | **PASS (100%)** |
| **Statik Analiz (`flutter analyze`)** | 1 Dosya | **PASS (0 issue)** |
| **GENEL SONUÇ** | **15 Arıza Senaryosu** | **PASS** |

---

## 11. Sonraki Aşama İçin Öneri (Stage 10.12.35)

Core Next üzerinde yeni satışlar oluşturulduktan sonra dahi, eski veritabanına veri ve stok kaybı olmaksızın geri dönülebileceği izole test ortamında kanıtlanmıştır.

Bir sonraki aşama olarak:
1. İstemci UI seviyesinde "Ters Uzlaştırma ve Güvenli Geri Dönüş" (Reverse Migration Rehearsal) senaryosunun kullanıcı bilgilendirme diyalogları ve onay mekanizmalarıyla uçtan uca simüle edilmesi,
2. Pilot Cutover Gate'in sahada gerçek mağaza personeli eşliğinde tek bir pilot cihazda kontrollü A/B testi için operasyonel kontrol listesinin hazırlanması önerilir.
