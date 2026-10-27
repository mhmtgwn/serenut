# CORE NEXT — STAGE 10.8.6 CUTOVER RECOMMENDATION
**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.8.6 — Bağımsız Karşıt Denetim Tavsiye ve Kapı Raporu  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  

---

## 1. Nihai Karar

# `BLOCKED`

> **Gerekçe:** Stage 10.8.6 bağımsız karşıt denetimi (Adversarial Audit), mevcut sistemin canlı geçişe hazır olmadığını; çözülmesi gereken **2 Kritik (CRITICAL)** ve **2 Yüksek (HIGH)** seviyeli mimari blokaj bulunduğunu kanıtlamıştır.

---

## 2. Blokaj Nedenleri ve Teknik Detayları

1. **Migration Re-run / Restart Güvenliği (F-01 - CRITICAL):**
   - `MigrationBridgeEngine` ürün kataloğunu aktarırken `ConflictAlgorithm.replace` kullanmaktadır.
   - SQLite, `products` tablosundaki birincil anahtar çakışmasında önce `DELETE`, sonra `INSERT` yürütmektedir.
   - Ancak `sale_items` tablosu `FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT` kısıtına sahip olduğundan, daha önce taşınmış ürünler silinememekte ve SQLite `FOREIGN KEY constraint failed (code 1811)` hatası vererek süreci çökertmektedir.
   - **Çözüm Şartı:** Ürünler ve müşteriler için `ConflictAlgorithm.ignore` veya açık `UPDATE` mantığı uygulanmalıdır.

2. **Arayüz ve Çift Veritabanı Ayrışması (F-05 - CRITICAL):**
   - `coreNextSalesEngineEnabledProvider = true` yapıldığında satış işlemi `CoreNextSaleExecutor` tarafından `serenut_core_v2.db` içine yazılmaktadır.
   - Ancak `SalesController` işlemi bitirdikten sonra `_saleRepository.findAll()` ile arayüzü güncellemektedir.
   - Bu repository ve bağlı controller'lar (Müşteriler, Ürünler, Kasa, Dashboard, Senkronizasyon) **HALEN ESKİ VERİTABANINA (`serenut_pos.db`) BAĞLIDIR**.
   - **Çözüm Şartı:** Yalnızca satış motoru değil; UI repository'leri ve read-store katmanı da Core Next veritabanına bağlanmalı veya Authoritative Cutover tam olarak uygulanmalıdır.

3. **Reverse Rollback Karma Ödeme Kaybı (F-02 - HIGH):**
   - Core Next'te karma (nakit + kart veya nakit + veresiye) ödemeler `sale_payments` tablosunda ayrı ayrı tutulur.
   - Legacy `sales` tablosu ise tekil bir `payment_method` metin alanına sahiptir.
   - `ReverseMigrationEngine` yalnızca ilk ödemeyi almakta; ikinci yöntemin ödeme türü legacy fişinde kaybolmaktadır.
   - **Çözüm Şartı:** Geri dönüşte karma ödeme varsa legacy `payment_method` alanına `'mixed'` yazılmalı ve parçalı tutarlar açıklama/metadata olarak saklanmalıdır.

4. **Reverse Rollback İade Şema Çatışması (F-03 - HIGH):**
   - Core Next'te iadeler `sales` tablosuna negatif tutarla kaydedilmektedir.
   - Geri dönüş motoru bu negatif kaydı legacy `sales` tablosuna yazmaktadır.
   - Legacy şemada iadeler ayrı bir `refunds` tablosunda tutulduğu için, olası bir ikinci ileri migration'da `MigrationBridgeEngine` negatif satış kontrolüne takılacaktır.
   - **Çözüm Şartı:** İadeler legacy `refunds` tablosuna dönüştürülmeli veya status kontrolüyle negatif kontrolünden muaf tutulmalıdır.

---

## 3. İzlenecek Yol Haritası (Remediation Roadmap)

Canlıya geçiş (cutover) kapısının açılabilmesi için sonraki aşamada (Stage 10.8.7) şu teknik adımların tamamlanması önerilir:

1. **Stage 10.8.7.1:** `MigrationBridgeEngine` yeniden çalıştırma hatasını gidermek (`ConflictAlgorithm.ignore` / update ayrımı).
2. **Stage 10.8.7.2:** `ReverseMigrationEngine` karma ödeme dökümünü ve iadeleri legacy `refunds` tablosuna eşleme düzeltmesini yapmak.
3. **Stage 10.8.7.3:** `SalesController` ve UI repository'lerini `CoreAppDatabase` okuyacak şekilde Authoritative Store seviyesinde birleştirmek.
4. **Stage 10.8.7.4:** Yalnızca izole bir pilot terminalde, gerçek kullanıcının günlük işleyişini bozmadan kontrollü pilot testini yürütmek.

---

## 4. Sonuç

Stage 10.8.6 karşıt denetimi, sistemin güçlü yönlerini (atomik rollback garantisi, idempotency tekilliği, silinmiş ürün placeholder koruması, kuruş hassasiyeti ve defter mutabakatı) teyit etmiş; ancak canlıya geçişi engelleyen 4 somut açığı ortaya çıkarmıştır.

Bu açıklar adli olarak kanıtlandığı için karar **`BLOCKED`** olarak tescil edilmiştir.
