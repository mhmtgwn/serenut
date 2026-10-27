# CORE NEXT — STAGE 10.8.7 DEFECT REMEDIATION REPORT
**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.8.7 — Critical Defect Remediation & Single-Source-of-Truth  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Karar:** `READY_FOR_FURTHER_ISOLATED_TESTING` (Canlı geçiş izni verilmez; Feature Flag varsayılanı `false` kalır)

---

## 1. Düzeltilen Hatalar ve Adli Kanıtlar

Stage 10.8.6 bağımsız karşıt denetiminde tespit edilen 4 kritik ve yüksek öncelikli hata (F-01, F-02, F-03, F-04) ve mimari çift başlılık (F-05) incelenmiş ve giderilmiştir.

---

### Hata 1 (F-01 - CRITICAL): Migration Idempotency ve Yabancı Anahtar Çökmesi
- **Eski Davranış:** `MigrationBridgeEngine`, `products` ve `customers` tablolarına `ConflictAlgorithm.replace` ile yazıyordu. SQLite motorunda `REPLACE`, mevcut satır için önce dahili bir `DELETE`, ardından `INSERT` tetikler. Ancak `sale_items` tablosunda `FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT` kuralı mevcuttur. İlk migrasyonda kalemler oluştuktan sonra, motor ikinci kez çalıştırıldığında ürün silinemediği için SQLite `FOREIGN KEY constraint failed (code 1811)` hatası vererek çöküyordu.
- **Yeni Davranış:** `products`, `customers`, `categories`, `users`, `sale_items` ve `ledger_entries` tablolarının aktarımında `ConflictAlgorithm.ignore` stratejisine geçildi. Mevcut satırlar silinmeden korunduğu için çocuk tablolardaki `ON DELETE RESTRICT` kısıtları asla ihlal edilmez.
- **Test Kanıtı:** [stage10_8_7_remediation_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_7_remediation_test.dart) (Test 1) ve [stage10_8_6_adversarial_audit_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_6_adversarial_audit_test.dart) (Senaryo 1). Her iki testte de migration üst üste iki kez çalıştırılmış; 0 FK hatası ve 0 mükerrer kayıt ile `isSuccess = true` alınmıştır.
- **Kalan Risk:** Yok.

---

### Hata 2 (F-02 - HIGH): Reverse Rollback Karma Ödeme Dökümü Kaybı
- **Eski Davranış:** Core Next'te bir satış için `sale_payments` tablosunda birden fazla ödeme yöntemi (ör. 150 TL Nakit + 100 TL Veresiye) varsa, `ReverseMigrationEngine` yalnızca ilk ödemeyi alarak `sales.payment_method = 'cash'` yazıyordu. İkincil ödeme yöntemi dökümü legacy satış başlığında kayboluyordu.
- **Yeni Davranış:** Birden fazla ödeme satırı tespit edildiğinde:
  1. `sales.payment_method` sütununa `'mixed'` yazılır.
  2. Legacy `sales` tablosunda `notes` sütunu varsa, ödeme dökümü açık metin olarak eklenir:
     `'Parçalı Ödeme Dağılımı: cash: 150.00 TL, onAccount: 100.00 TL'`.
  3. Veresiye/borç kısmı `financial_transactions` tablosuna aktarılarak cari bakiye etkisi tam korunur.
- **Test Kanıtı:** [stage10_8_7_remediation_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_7_remediation_test.dart) (Test 2). `payment_method == 'mixed'` ve `notes` içeriği doğrulanmıştır.
- **Kalan Risk:** Yok.

---

### Hata 3 (F-03 - HIGH): Reverse Rollback Negatif İade ve Şema Çatışması
- **Eski Davranış:** Core Next'te iadeler `sales` tablosuna negatif tutarla (`status = 'REFUND'`) kaydedilir. `ReverseMigrationEngine` bu negatif satırı legacy `sales` tablosuna aynen yazıyordu. Oysa legacy şemada iadeler ayrı bir `refunds` tablosunda tutulur. Bu durum legacy DB üzerinde daha sonra tekrar ileri migration çalıştırıldığında `totalCents < 0` denetimine takılarak sürecin çökmesine neden oluyordu.
- **Yeni Davranış:** Geri dönüş motorunda iadeler ayrıştırıldı:
  1. `status == 'REFUND'` veya `totalCents < 0` olan satırlar legacy `sales` tablosuna negatif olarak YAZILMAZ.
  2. Legacy `refunds` tablosuna pozitif tutarla (`amount > 0`) eklenir.
  3. İade edilen kalemler legacy `refund_items` tablosuna yazılır.
  4. Orijinal satışın `sales.refunded_amount` sütunu artırılır.
- **Test Kanıtı:** [stage10_8_7_remediation_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_7_remediation_test.dart) (Test 2 Adım 5). Geri dönüş yapılmış legacy veritabanı üzerinde tekrar `migrateFromLegacy` çalıştırılmış ve döngüsel geçiş 0 hata ile tamamlanmıştır.
- **Kalan Risk:** Yok.

---

### Hata 4 (F-04 - MEDIUM): Senkronizasyon Kuyruğunda Uçuşta Kalan Mutasyonların Kaybı
- **Eski Davranış:** Forward ve reverse motorlar yalnızca `state = 'PENDING'` olan kuyruk kayıtlarını taşıyordu. Cutover veya rollback anında ağ kesintisi nedeniyle `IN_FLIGHT` veya `TRANSIENT_ERROR` durumunda kalmış olan mutasyonlar terk ediliyordu.
- **Yeni Davranış:** Güvenli Cutover Politikası uygulandı:
  `state IN ('PENDING', 'IN_FLIGHT', 'TRANSIENT_ERROR')` koşuluyla onaylanmamış tüm yerel mutasyonlar hedef sisteme `PENDING` olarak aktarılır. Protocol 6 sunucusu idempotent olduğundan, daha önce sunucuya ulaşmış kayıtlar yinelenmeden onaylanır; ulaşmamış olanlar ise güvenle gönderilir.
- **Test Kanıtı:** [stage10_8_7_remediation_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_7_remediation_test.dart) (Test 3). `mut-pend`, `mut-flight` ve `mut-transient` mutasyonlarının eksiksiz taşındığı kanıtlanmıştır.
- **Kalan Risk:** Yok.

---

### Hata 5 (F-05 - CRITICAL): UI Çift Başlılık ve Veritabanı Ayrışması (Dual-DB Split)
- **Eski Durum:** `SalesController.createSale` içinde `coreNextSalesEngineEnabledProvider = true` iken yazma Core Next DB'ye yapılıyor; ancak satış sonrası ekranı tazeleyen `_saleRepository.findAll()`, `productsControllerProvider` ve `syncProvider` bileşenleri eski `serenut_pos.db` dosyasını okumaya devam ediyordu.
- **Çözüm Mimarisi:** Authoritative Store Cutover haritası çıkarılmıştır. `coreNextSalesEngineEnabledProvider` varsayılanı `false` tutulmakta; canlı geçiş yapılana kadar karma (hybrid) yazma engellenmekte; tek yetkili veri kaynağı ilkesi `CORE_NEXT_STAGE10_8_7_SINGLE_SOURCE_OF_TRUTH_MAP.md` ile belgelenmiştir.
