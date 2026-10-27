# CORE NEXT — STAGE 10.8.6 ADVERSARIAL AUDIT REPORT
**Tarih:** 14 Ekim 2026  
**Denetim Türü:** Bağımsız Karşıt Adli Denetim (Independent Adversarial Audit) — Yeni Özellik Eklenmedi  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Nihai Karar:** `BLOCKED` (Canlıya Geçiş Blokelidir)

---

## 1. Giriş ve Karşıt Denetim Amacı

Stage 10.8.5 raporlarındaki iddiaları doğrulamak amacıyla, sisteme "dostane" değil "karşıt" (adversarial) bir yaklaşımla yaklaşılmıştır. Amaç, testlerin mutlu yolunu (happy path) değil; uç durumları, hata enjeksiyonlarını, çift çalıştırma senaryolarını, ilişkisel kısıt çatışmalarını ve çift veritabanı ayrışmasını sorgulamaktır.

Bu denetim kapsamında üretim koduna (`lib/` ve `core_next/`) hiçbir yeni özellik veya yama eklenmemiş; durum mevcut kod tabanı ve izole test senaryoları (`test/core_next/stage10_8_6_adversarial_audit_test.dart`) üzerinden kanıtlanmıştır.

---

## 2. On Karşıt Senaryo ve Ayrıntılı Bulgular

### Senaryo 1: Migration İki Kez Çalıştırıldığında Mükerrer Kayıt ve FK Çatışması
- **İddia:** Migration motoru idempotenttir, iki kez çalıştırıldığında sorunsuz tamamlanır.
- **Karşıt Bulgu:** **BAŞARISIZ / KRİTİK HATA TESPİT EDİLDİ.**
- **Adli Kanıt:** SQLite motorunda `ConflictAlgorithm.replace` (`INSERT OR REPLACE`), mevcut bir satır varsa onu önce **DELETE** eder, ardından **INSERT** eder. `sale_items` tablosunda `FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT` kuralı mevcuttur. İlk geçişte ürünler ve satış kalemleri yazıldıktan sonra, migration motoru ikinci kez çalıştırıldığında `products` tablosundaki mevcut ürünü `DELETE+INSERT` yapmaya çalışır. Ancak bağlı `sale_items` satırları silmeyi engeller (`ON DELETE RESTRICT`) ve SQLite doğrudan şu hatayı fırlatır:
  ```
  SqfliteFfiException(1811): FOREIGN KEY constraint failed (code 1811)
  Causing statement: INSERT OR REPLACE INTO products (...)
  ```
- **Sonuç:** Migration yarıda kesilip yeniden başlatıldığında veya ikinci kez çalıştırıldığında çöker. `ConflictAlgorithm.ignore` veya `UPDATE` stratejisi kullanılmalıdır.

---

### Senaryo 2: Tablo Aktarımının Ortasında Hata Oluşursa Transaction İzolasyonu
- **İddia:** Herhangi bir adımda hata olursa veritabanına yarım/kirli veri yazılmaz.
- **Karşıt Bulgu:** **DOĞRULANDI (BAŞARILI).**
- **Adli Kanıt:** Müşteri bakiyesi ile `v_customer_ledger_effect` arasına 50 kuruşluk kasıtlı tutarsızlık enjekte edildiğinde (`c-corrupt`), motor işlemi durdurmuş ve `targetDb` içerisinde daha önce yazılan `products` ve `users` tabloları da dahil olmak üzere 0 satır bırakarak tam rollback yapmıştır (`pCount = 0`, `cCount = 0`).

---

### Senaryo 3: Reverse Rollback Kapsamı (Çoklu Ödeme, İptal, İade)
- **İddia:** Core Next üzerinde yapılan tüm yeni işlemler legacy sisteme kayıpsız aktarılır.
- **Karşıt Bulgu:** **KISMEN BAŞARISIZ / VERİ KAYBI TESPİT EDİLDİ.**
  1. **Karma / Çoklu Ödeme Kaybı:** Core Next `sale_payments` tablosunda parçalı ödeme (örneğin 140 TL Nakit + 100 TL Veresiye) tutar. Ancak legacy `sales` tablosunda yalnızca tekil `payment_method TEXT` sütunu vardır. `ReverseMigrationEngine` yalnızca ilk ödemeyi (`payments.first['payment_type']`) alarak `payment_method = 'cash'` yazar. İkinci ödeme yöntemi kırılımı legacy `sales` tablosunda kaybolur.
  2. **İade Ayrışması:** Core Next'te iadeler `sales` tablosuna negatif `total_cents` ile yazılır. Oysa legacy şemada negatif satış yasaktır ve iadeler için ayrı bir `refunds` (`CHECK(amount > 0)`) tablosu mevcuttur. Negatif bir iade satışı legacy `sales` tablosuna yazıldığında, daha sonra tekrar migration çalıştırılırsa `MigrationBridgeEngine` ("Satış toplamı negatif olamaz") hatası vererek çöker.
  3. **İptal Edilen Satışlar:** `status = 'CANCELLED'` legacy `sales` tablosuna başarıyla yansımaktadır.

---

### Senaryo 4: Reverse Rollback İki Kez Çalıştırıldığında İdempotency
- **İddia:** Reverse rollback motoru mükerrer aktarım yapmaz.
- **Karşıt Bulgu:** **DOĞRULANDI (BAŞARILI).**
- **Adli Kanıt:** İkinci çalıştırmada `newSales` listesi boş kalmış (`salesExported: 0`), ürün stokları mükerrer düşülmemiş (`48.0` olarak sabit kalmış) ve defter kayıtları atlanmıştır.

---

### Senaryo 5: Outbox Durum İzolasyonu (PENDING vs IN_FLIGHT vs SYNCED)
- **İddia:** Bekleyen çevrimdışı mutasyonlar korunur.
- **Karşıt Bulgu:** **RİSK TESPİT EDİLDİ (Veri Düşmesi).**
- **Adli Kanıt:** `MigrationBridgeEngine` yalnızca `state = 'PENDING'` olan legacy outbox kayıtlarını okur. Eğer cutover anında ağ kopmuş ve kayıt `IN_FLIGHT` veya `TRANSIENT_ERROR` durumunda kalmışsa, bu kayıt Core Next'e **AKTARILMAMAKTA VE TERK EDİLMEKTEDİR**. Benzer şekilde reverse rollback sırasında Core Next'te `CONFLICT` veya `TRANSIENT_ERROR` durumunda olan olaylar legacy'e geri döndürülmemektedir.

---

### Senaryo 6: Idempotency Anahtarı Tekilliği
- **İddia:** Aynı anahtarla mükerrer satış veya tahsilat yapılamaz.
- **Karşıt Bulgu:** **DOĞRULANDI (BAŞARILI).**
- **Adli Kanıt:** Aynı `idempotency_key` ile ikinci bir satış kaydı eklenmek istendiğinde SQLite `UNIQUE constraint failed: sales.idempotency_key` hatası vererek işlemi durdurmaktadır. `CoreCheckoutUseCase` katmanında ise mevcut satış dönülerek güvenli replay sağlanmaktadır.

---

### Senaryo 7: Silinmiş Ürünler İçin Placeholder Kayıtların Rapor Etkisi
- **İddia:** Silinmiş ürünler için açılan placeholder ürünler kasiyer ekranını bozmaz.
- **Karşıt Bulgu:** **DOĞRULANDI (BAŞARILI).**
- **Adli Kanıt:** `is_deleted = 1, is_active = 0, price_cents = 0` özellikleri sayesinde kasiyer ürün aramasında (`WHERE is_deleted = 0 AND is_active = 1`) görünmemekte; geçmiş satış cirosu (`SELECT SUM(total_cents) FROM sale_items`) ise kuruşu kuruşuna korunmaktadır.

---

### Senaryo 8: Türkçe Karakterler, Tırnaklar ve Sınır Değerleri
- **İddia:** Türkçe diakritikler, tırnak işaretleri ve kuruş sınırları bozulmaz.
- **Karşıt Bulgu:** **DOĞRULANDI (BAŞARILI).**
- **Adli Kanıt:** `"Öz Şükrü Çetin & Oğulları Gıda 'Köy Sofrası' San. Tic. Ltd. Şti."` ve `"Çamlıca Şekersiz Çilekli & Böğürtlenli 1,5L (Iğdır Üzümü Özel Seri)"` gibi tek tırnaklı ve Türkçe karakterli dizgiler SQLite parametreli sorguları sayesinde bozulmadan aktarılmıştır.

---

### Senaryo 9: Stok ve Müşteri Bakiyesi Bağımsız Hareket Mutabakatı
- **İddia:** Müşteri bakiyesi yalnızca customers tablosundan değil, defterden de doğrulanır.
- **Karşıt Bulgu:** **DOĞRULANDI (BAŞARILI).**
- **Adli Kanıt:** Eğer bir carinin bakiyesi ile defter toplamı (`v_customer_ledger_effect`) arasında açıklanamayan bir fark varsa (ör. 50 TL), sistem sessizce kabul etmemekte ve fail-closed korumasıyla durmaktadır.

---

### Senaryo 10: Uygulama İçi Dağıtım ve Çift Veritabanı Ayrışması (Dual-Database Split)
- **İddia:** Satış controller'ı Core Next etkinleştirildiğinde uçtan uca çalışır.
- **Karşıt Bulgu:** **MİMARİ BLOKAJ TESPİT EDİLDİ.**
- **Adli Kanıt:** `lib/presentation/controllers/sales_controller.dart` incelendiğinde:
  - `coreNextSalesEngineEnabledProvider = true` yapıldığında satış işlemi `CoreNextSaleExecutor` üzerinden `serenut_core_v2.db` içine yazılır.
  - Ancak satış tamamlandıktan sonra `SalesController`:
    ```dart
    return _saleRepository.findAll();
    ```
    satırını çalıştırır!
  - `_saleRepository`, `salesHistoryControllerProvider`, `productsControllerProvider`, `dashboardProvider` ve `syncProvider` bileşenlerinin tamamı **HALEN ESKİ VERİTABANINA (`serenut_pos.db`) BAĞLIDIR**.
  - Sonuç: Kasiyer satışı yapar; satış Core Next DB'ye yazılır; fakat ekrandaki satış listesi eski DB'yi sorguladığı için yeni yapılan satış ekranda **GÖRÜNMEZ**. Senkronizasyon servisi ise eski kuyruğu tetikler.

---

## 3. Karşıt Denetim Sonuç Özeti

222 benzersiz testin tamamı geçmektedir; ancak adli denetim canlıya geçişi imkansız kılan 3 kritik mimari blokaj ortaya çıkarmıştır:
1. **Migration Re-run Çökmesi:** `INSERT OR REPLACE` kuralının `sale_items` FK RESTRICT ile çatışması.
2. **Reverse Rollback Karma Ödeme & İade Bozulması:** Parçalı ödemelerin tekilleşmesi ve negatif iadelerin legacy şemayla uyumsuzluğu.
3. **Çift Veritabanı Ayrışması (Dual-Database Split):** Satış motoru Core Next'e yazarken, UI ve senkronizasyon katmanının Legacy DB'yi okumaya devam etmesi.
