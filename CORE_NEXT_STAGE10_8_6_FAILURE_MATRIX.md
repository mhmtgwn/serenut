# CORE NEXT — STAGE 10.8.6 FAILURE MATRIX
**Tarih:** 14 Ekim 2026  
**Kapsam:** Karşıt Denetim Hata Matrisi ve Risk Sınıflandırması  
**Karar:** `BLOCKED`

---

## 1. Karşıt Denetim Hata ve Zafiyet Matrisi

| No | Denetim Alanı | Beklenen Davranış | Gerçekleşen Davranış | Adli Hata Kodu / Belirti | Şiddet Seviyesi | Canlı Geçiş Etkisi |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **F-01** | **Migration Re-run (Idempotency)** | Motor ikinci kez çalıştırıldığında sessizce güncellenmeli veya atlanmalı. | `products` üzerinde `INSERT OR REPLACE` çalışınca SQLite silme denedi; `sale_items` RESTRICT nedeniyle çöktü. | `SqliteException(1811): FOREIGN KEY constraint failed` | **CRITICAL** | Yarıda kesilen veya tekrarlanan migration'da çökme riski. |
| **F-02** | **Reverse Rollback: Karma Ödemeler** | Core Next'te yapılan nakit+veresiye gibi parçalı ödemeler legacy'ye tam dökümle aktarılmalı. | Legacy `sales.payment_method` tek bir string aldığı için yalnızca ilk ödeme yazıldı; ikinci yöntem kayboldu. | Veri kaybı (Payment Breakdown Loss) | **HIGH** | Geri dönüş sonrası muhasebe kasa/pos dengesi bozulur. |
| **F-03** | **Reverse Rollback: İadeler** | İadeler legacy `refunds` tablosuna aktarılmalı. | İadeler legacy `sales` tablosuna negatif tutarla yazıldı. Sonraki olası migration'da negatif kontrolü çöker. | Şema kuralı ihlali (`totalCents < 0`) | **HIGH** | Çift yönlü geçiş döngüsünü imkansız kılar. |
| **F-04** | **Outbox Durum Ayrımı** | Ağ kopması nedeniyle `IN_FLIGHT` veya `TRANSIENT_ERROR` durumunda kalan mutasyonlar taşınmalı. | Motor yalnızca `state = 'PENDING'` olanları taşıdı; diğer durumdaki çevrimdışı mutasyonlar terk edildi. | Veri kaybı (Dropped in-flight mutations) | **MEDIUM** | Cutover anında uçuşta olan mutasyonlar kaybolur. |
| **F-05** | **UI / Store Çift Başlılık (Dual-DB Split)** | Core Next etkinleştirildiğinde UI ekranları ve dashboard yeni veritabanını okumalı. | Satış Core DB'ye yazıldı; fakat `SalesController`, `_saleRepository.findAll()` ile Legacy DB'yi okumaya devam etti. | UI Tutarsızlığı (Yeni satış listede görünmüyor) | **CRITICAL** | Kasiyer satışı onaylar ama ekranda göremez; çift satış riski doğar. |
| **F-06** | **Fail-Closed Transaction** | Ara adımda hata çıkarsa hiçbir kirli satır kalmamalı. | Hata enjekte edildiğinde hedef veritabanında 0 satır kaldı; tam atomik rollback doğrulandı. | Yok (Başarılı) | **INFO (PASS)** | Güvenlik garantisi sağlandı. |
| **F-07** | **Idempotency Key Tekilliği** | Aynı anahtarla mükerrer fiş/ödeme yazılamamalı. | SQLite `UNIQUE constraint` ve UseCase seviyesinde deterministik replay sağlandı. | Yok (Başarılı) | **INFO (PASS)** | Mükerrer satış engellendi. |
| **F-08** | **Placeholder Ürün Güvenliği** | Silinmiş ürün kalemi için açılan placeholder kasiyeri yanıltmamalı. | `is_deleted = 1, is_active = 0` ile kasiyerden gizlendi; ciro raporunda korundu. | Yok (Başarılı) | **INFO (PASS)** | Raporlama bütünlüğü korundu. |
| **F-09** | **Türkçe Karakter ve Sınır Değerleri** | Diakritikler ve kuruş sınırları bozulmamalı. | UTF-8 ve tamsayı kuruş dönüşümü ile sıfır sapma kanıtlandı. | Yok (Başarılı) | **INFO (PASS)** | Parasal hassasiyet doğrulandı. |
| **F-10** | **Defter Bakiye Doğrulaması** | Açıklanamayan bakiye sapması olan cariler taşınmamalı. | 50 TL sapma tespit edildiğinde motor işlemi adli hata ile durdurdu. | Yok (Başarılı) | **INFO (PASS)** | Finansal güvenlik sağlandı. |

---

## 2. Şiddet Dağılımı Özeti

- **CRITICAL (2 Adet):** F-01 (Re-run FK Çatışması), F-05 (UI Dual-Database Split).
- **HIGH (2 Adet):** F-02 (Reverse Rollback Karma Ödeme Kaybı), F-03 (Reverse Rollback Negatif İade Şema Çatışması).
- **MEDIUM (1 Adet):** F-04 (In-Flight Outbox Kayıtlarının Terk Edilmesi).
- **PASS / VERIFIED (5 Adet):** F-06, F-07, F-08, F-09, F-10.

---

## 3. Değerlendirme

CRITICAL ve HIGH seviyedeki 4 mimari bulgu, mevcut sistemin **canlı ortama (production) kesinlikle geçirilemeyeceğini** kanıtlamaktadır. Bu bulgular çözülmeden yapılacak herhangi bir cutover, kasiyer arayüzünde görünmeyen satışlara, yarım kalan migration'larda veritabanı kilitlenmelerine ve geri dönüşte karma ödeme kırılımlarının kaybolmasına yol açacaktır.
