# 16 — Kabul Kriterleri (Gherkin Senaryoları)

> Bu belge, Nutopia Platformu'nun tüm kritik iş kurallarını, kenar durumlarını ve operasyonel senaryolarını Gherkin (`Given-When-Then`) biçiminde tanımlar.
> Bu senaryolar, Playwright (E2E) ve Vitest (Entegrasyon) test paketlerinin doğrudan dayanağıdır.
> Bağlayıcı mimari: `12-mimari-kilit-kararlar.md`. Veri modeli: `14-sql-sema.md`.

---

## ÖZELLİK 1: STOK YÖNETİMİ VE EŞZAMANLI SİPARİŞLER (CONCURRENCY)

### Senaryo 1.1: Son Kalan Ürünün Eşzamanlı Satın Alınması (Race Condition)
```gherkin
Özellik: Stok Rezervasyonu ve Atomik Azaltma
  Kural: Bir ürünün kullanılabilir stoğu (available = on_hand - reserved) sıfırdan küçük olamaz.

  Senaryo: İki kullanıcı aynı anda son 1 adet ürünü satın almaya çalışır
    Diyelim ki "Sütlü Fındık Kreması 300g" varyantının mevcut stoğu 1 adettir
    Ve rezervasyon süresi 15 dakika olarak ayarlanmıştır
    Kullanıcı "A" ödeme adımında "Siparişi Tamamla" butonuna tıklar
    Ve aynı milisaniyede Kullanıcı "B" de "Siparişi Tamamla" butonuna tıklar
    O zaman sunucu istekleri sıraya alır ve veritabanında satır kilidi (FOR UPDATE) uygular
    O zaman Kullanıcı "A" için sipariş "pending_payment" durumuna geçer ve 1 adet rezerve edilir
    Ve Kullanıcı "B" 409 Conflict durum kodu ile "INSUFFICIENT_STOCK" hatası alır
    Ve toplam rezerve edilen miktar 1 adettir
    Ve Kullanıcı "B"'nin sepeti güncellenir ve stok tükenme uyarısı gösterilir
```

### Senaryo 1.2: Rezervasyon Süresinin Dolması ve Stoğun İadesi
```gherkin
  Senaryo: Ödeme yapılmayan siparişin rezervasyonu süre aşımına uğrar
    Diyelim ki Kullanıcı "A" 1 adet "%100 Fındık Ezmesi 320g" için ödeme başlatmıştır
    Ve varyant için 1 adet stok "active" durumunda rezerve edilmiştir
    Ve rezervasyon zaman aşımı 15 dakikadır
    Zaman 16 dakika ileri alındığında ve "inventory.release-expired" arka plan işi çalıştığında
    O zaman rezervasyon durumu "expired" olarak güncellenir
    Ve "shop.stock_levels.reserved" miktarı 1 azaltılır
    Ve ürünün "available" stoğu tekrar 1 artar
    Ve sipariş durumu "expired" olarak işaretlenir
```

---

## ÖZELLİK 2: SEPET VE İNDİRİM MOTORU (PRICING & COUPONS)

### Senaryo 2.1: Sepet İndirimlerinin Hiyerarşik ve Deterministik Hesaplanması
```gherkin
Özellik: İndirim Sırası ve Yuvarlama
  Kural: İndirimler satır fiyatı -> kupon -> havale -> kargo sırasıyla kuruş hassasiyetinde hesaplanır.

  Senaryo: Sepette Hoşgeldin Kuponu ve Havale İndirimi Birlikte Kullanılır
    Diyelim ki sepette 2 adet "Kavrulmuş Fındık 500g" (Birim: 275,00 ₺, Toplam: 550,00 ₺) vardır
    Ve sepette 1 adet "%100 Fındık Ezmesi 320g" (Birim: 195,00 ₺) vardır
    Ve ürünlerin brüt toplamı 745,00 ₺'dir
    Kullanıcı "HOSGELDIN10" kupon kodunu uyguladığında
    O zaman ürün brüt toplamına %10 indirim uygulanır (İndirim: 74,50 ₺)
    Ve indirimli ürün tutarı 670,50 ₺ olur
    Ve indirimli tutar 750,00 ₺ altında olduğu için 45,00 ₺ kargo ücreti eklenir
    Kullanıcı ödeme yöntemi olarak "Havale / EFT" (%5 indirim) seçtiğinde
    O zaman %5 indirim yalnız indirimli ürün tutarı (670,50 ₺) üzerinden hesaplanır: 33,52 ₺
    Ve Genel Toplam = 670,50 ₺ - 33,52 ₺ + 45,00 ₺ = 681,98 ₺ olarak belirlenir
    Ve kuruş yuvarlama farkı en büyük satır kalemine atomik eklenir
```

### Senaryo 2.2: Kupon Tekrar Kullanımının Engellenmesi
```gherkin
  Senaryo: İlk siparişe özel kupon ikinci kez kullanılamaz
    Diyelim ki "HOSGELDIN10" kuponu "first_order_only = true" ve müşteri başı limit 1 olarak tanımlıdır
    Ve Kullanıcı "05321112233" telefon numarası ile daha önce tamamlanmış bir siparişe sahiptir
    Kullanıcı yeni bir sepette "HOSGELDIN10" kodunu girdiğinde
    O zaman sistem isteği reddeder
    Ve 400 Bad Request ile "Bu kupon yalnızca ilk siparişlerde geçerlidir" mesajı döner
```

---

## ÖZELLİK 3: ÖDEME VE WEBHOOK İŞLEME (PAYMENT IDEMPOTENCY)

### Senaryo 3.1: iyzico Webhook İmzası ve Çift Olay Güvenliği
```gherkin
Özellik: Ödeme Webhook Entegrasyonu
  Kural: Webhook çağrıları imzalı olmalı ve aynı olay birden fazla gelse dahi tek bir muhasebe/stok etkisi yaratmalıdır.

  Senaryo: Sağlayıcı aynı başarılı ödeme webhook'unu ağ gecikmesi nedeniyle 2 kez iletir
    Diyelim ki "NT-2026-000184" numaralı sipariş "pending_payment" durumundadır
    Ve iyzico sisteminden geçerli HMAC-SHA256 imzalı "ORDER_PAID" webhook'u gelir
    Sunucu webhook'u aldığında:
      | Adım | Beklenen İşlem |
      | 1 | İmzayı doğrular ve geçerli bulur |
      | 2 | payments tablosunda conversation_id ile ödemeyi bulur |
      | 3 | Ödeme durumunu "captured" yapar |
      | 4 | Sipariş durumunu "paid" yapar ve stok rezervini kalıcı stoka dönüştürür |
      | 5 | outbox tablosuna OrderPaid olayını yazar |
      | 6 | payments.webhook_events tablosuna event_id'yi işlenmiş olarak kaydeder |
      | 7 | Sağlayıcıya 200 OK döner |
    Ve 2 saniye sonra sağlayıcı aynı event_id ile ikinci bir istek gönderdiğinde
    O zaman sunucu webhook_events tablosundaki benzersiz kısıt sayesinde olayın işlendiğini tespit eder
    Ve veritabanında hiçbir sipariş veya stok değişikliği yapmaz
    Ve sağlayıcıya anında 200 OK {"received": true} yanıtı verir
```

---

## ÖZELLİK 4: DEĞİRMEN VE KURYE SAHA OPERASYONLARI

### Senaryo 4.1: Şoförün Sahada Alım Kodunu Doğrulaması ve Tartı Yapması
```gherkin
Özellik: Değirmen Alım ve Yerinde Tartı Tutanak Güvenliği
  Kural: Şoför mahsulü teslim almadan önce çiftçiye iletilen 4 haneli alım kodunu doğrulamak zorundadır.

  Senaryo: Şoför çiftçinin bahçesine varır ve kantar tartısını kaydeder
    Diyelim ki "DG-2026-000072" numaralı talep için Şoför "Ahmet" atanmıştır
    Ve Çiftçi "Hasan"'a SMS ile "Alım Kodunuz: 7412" iletilmiştir
    Şoför mobil PWA uygulamasında "Adrese Ulaştım" butonuna basar
    Ve Çiftçi "Hasan"'dan 7412 kodunu alıp uygulamaya girer
    O zaman sistem alım kodunu doğrular ve Tartı Giriş ekranını açar
    Şoför kantar fişini fotoğraflar ve aşağıdaki değerleri girer:
      | Alan | Değer |
      | Çuval Adedi | 4 |
      | Brüt Ağırlık | 204.5 kg (204500 g) |
      | Çuval Darası | 0.8 kg (800 g) |
    O zaman sistem net ağırlığı 203.7 kg (203700 g) olarak hesaplar
    Ve Çiftçi "Hasan"'ın telefonuna SMS ile "Tartı Onay Kodunuz: 9021" gider
    Şoför onay kodunu girip "Alımı Tamamla" butonuna bastığında
    O zaman veritabanında "mill.weighings" tablosuna değişmez satır yazılır
    Ve talep durumu "picked_up" olarak güncellenir
    Ve kesin ücret 203.7 kg üzerinden yeniden hesaplanarak "mill.charges" tablosuna işlenir
    Ve Çiftçi "Hasan"'a "Fındığınız 203.7 kg olarak teslim alınmıştır" SMS'i gönderilir
```

### Senaryo 4.2: Değirmen İkinci Tartısında Tolerans Aşımı (Anomali Tespiti)
```gherkin
  Senaryo: Değirmen giriş tartısı ile saha tartısı arasında %1'den fazla fark oluşur
    Diyelim ki Sahada tartılan net miktar 500.0 kg'dır
    Mahsul araçla değirmene getirilir ve tesis kantarında tartılır
    Tesis operatörü değirmen giriş tartısını 490.0 kg olarak girdiğinde
    Sistem tartı farkını hesaplar: (500 - 490) / 500 = %2,0 kayıp
    Ve fark belirlenen %1,0 tolerans sınırını aştığı için
    O zaman sistem "mill.jobs" üzerinde "anomaly_flag = true" işaretler
    Ve Yönetici Kontrol Paneline "Acil: DG-XXXXXX Nolu Partide %2 Tartı Uyuşmazlığı" uyarısı düşer
    Ve ilgili parti yönetici inceleme onayına kadar işleme alınamaz
```

### Senaryo 4.3: Çiftçiye Geri Teslimat ve Kapıda Tahsilat
```gherkin
  Senaryo: İşlenmiş ürün çiftçiye teslim edilir ve nakit tahsil edilir
    Diyelim ki "DG-2026-000072" nolu talep için işleme tamamlanmıştır
    Ve çıkan ürün: 102 kg iç fındık (1 kg vakumlu paketler halinde)
    Ve kesin işleme bedeli 1.140,72 ₺'dir
    Şoför teslimat adresine gider ve paketleri çiftçiye teslim eder
    Şoför "Tahsilat: 1.140,72 ₺ - Nakit Alındı" seçeneğini işaretler
    Ve teslim alan kişinin imza onayını sisteme kaydeder
    O zaman talep durumu "delivered" ve "paid" olarak işaretlenir
    Ve payments tablosuna "method = cash" ve "status = captured" kaydı eklenir
    Ve şoförün günlük kasa kapanış hesabına 1.140,72 ₺ nakit borç yazılır
```

---

## ÖZELLİK 5: İADE VE CAYMA HAKKI İSTİSNASI (RETURNS & REFUNDS)

### Senaryo 5.1: Gıda Ürünlerinde Hijyen ve Ambalaj Açılması Durumu
```gherkin
Özellik: Mesafeli Sözleşmeler Yönetmeliği Uyarınca Gıda İade Prosedürü
  Kural: Koruyucu bandı açılmış gıda ürünlerinde cayma hakkı istisnası uygulanır; ayıplı ürünlerde değişim yapılır.

  Senaryo: Müşteri kavanozu açılmış fındık ezmesini keyfi olarak iade etmek ister
    Diyelim ki sipariş 3 gün önce teslim edilmiştir
    Müşteri hesap panelinden "Keyfi / Beğenmedim" gerekçesiyle iade talebi oluşturur
    O zaman sistem "Türk Gıda Kodeksi ve Mesafeli Sözleşmeler Yönetmeliği 15/ç maddesi gereğince ambalajı açılmış gıda ürünlerinde cayma hakkı geçerli değildir" uyarısını gösterir
    Ve sistem talebi otomatik olarak "rejected" statüsüne alır
    Ancak Müşteri "Kırık / Hasarlı / Bozuk Ürün" seçip kargo tutanağı ve fotoğraf yüklerse
    O zaman talep "approved" statüsüne geçer ve ücretsiz iade kargo kodu oluşturulur
    Ve ürün depoya ulaşıp kontrol edildiğinde sağlayıcı API'si üzerinden tam iade (refund) tetiklenir
```

