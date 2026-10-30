# 17 — Şablonlar ve Yasal Metin İskeletleri

> Bu belge, Nutopia Platformu'nda kullanılacak tüm işlemsel SMS ve E-posta bildirim metinlerini ve avukat/mali müşavir onayına sunulacak yasal sözleşme iskeletlerini içerir.
> Veri tablosu: `ops.notification_templates` ve `ops.content_pages`.

---

## BÖLÜM 1: İŞLEMSEL SMS ŞABLONLARI (Kısa, Net, Türkçe Karakter Maliyetine Uyumlu)

*Başlık: NUTOPIA (Alfanümerik Gönderici Başlığı)*

### 1.1 Kimlik & Güvenlik
- **Kod:** `auth.otp_login`
  - *Metin:* `Nutopia dogrulama kodunuz: {{code}}. Bu kodu kimseyle paylasmayiniz. B002`
- **Kod:** `auth.pickup_code`
  - *Metin:* `Nutopia findik alim kodunuz: {{code}}. Bahcenize gelen sofore bu kodu ileterek teslimati baslatabilirsiniz.`
- **Kod:** `auth.weighing_ack`
  - *Metin:* `{{net_kg}} kg findik tartim onay kodunuz: {{code}}. Sofore iletiniz.`

### 1.2 Mağaza (E-Ticaret)
- **Kod:** `shop.order_placed_bank_transfer`
  - *Metin:* `Siparisiniz alindi! No: {{order_no}}. Tutar: {{amount}} TL. Lutfen 48 sa icinde aciklamaya {{order_no}} yazarak havalenizi iletiniz. IBAN ve detaylar: {{link}}`
- **Kod:** `shop.order_shipped`
  - *Metin:* `Siparisiniz kargoya verildi! {{carrier}} Takip No: {{tracking_no}}. Takip etmek icin: {{link}} Afiyet olsun!`
- **Kod:** `shop.order_delivered`
  - *Metin:* `Nutopiano siparisiniz teslim edildi. Lezzet ve tazelik dolu gunler dileriz! Bizi degerlendirin: {{link}}`

### 1.3 Değirmen & Kurye
- **Kod:** `mill.request_approved`
  - *Metin:* `Findik isletme talebiniz onaylandi! No: {{request_no}}. Planlanan alim: {{pickup_date}} {{pickup_slot}}. Alim gunu irtibatta olacagiz.`
- **Kod:** `mill.driver_en_route`
  - *Metin:* `Soforumuz {{driver_name}} bahcenize dogru yola cikti. Tahmini varis: {{est_time}}. Iletisim: {{driver_phone}}`
- **Kod:** `mill.intake_completed`
  - *Metin:* `Mahsulunuz {{net_kg}} kg olarak teslim alindi. Tutanak ve fis detayiniz: {{link}} Lot No: {{lot_code}}. Isleme baslaniyor.`
- **Kod:** `mill.job_ready`
  - *Metin:* `Findiginiz degirmenimizde ozenle islendi ve paketlendi! Cikan urun: {{output_kg}} kg. Kesin ucret: {{final_amount}} TL. Teslimat plani: {{link}}`
- **Kod:** `mill.pickup_failed`
  - *Metin:* `Soforumuz adresinize ulasamadi. Lutfen yeni randevu icin bizi arayiniz: 05380288202`

---

## BÖLÜM 2: İŞLEMSEL E-POSTA ŞABLONLARI (HTML & Düz Metin)

### 2.1 Sipariş Onayı (`shop.order_confirmation`)
- **Konu:** `Nutopiano Siparişiniz Alındı — No: {{order_no}}`
- **Gövde Özeti:**
  - Logo ve Teşekkür mesajı: "Sayın {{customer_name}}, siparişiniz için teşekkür ederiz."
  - Sipariş No: `{{order_no}}` | Tarih: `{{order_date}}` | Ödeme Yöntemi: `{{payment_method}}`
  - Tablo:
    - Görsel | Ürün & Varyant | Adet | Birim Fiyat | Toplam Fiyat
  - Dip Toplam: Ara Toplam, İndirimler, Kargo Ücreti, **Genel Toplam**.
  - Teslimat ve Fatura Adresi dökümü.
  - Varsa Mesafeli Satış Sözleşmesi ve Ön Bilgilendirme PDF ekleri.

### 2.2 Kargo Bildirimi (`shop.order_shipped`)
- **Konu:** `Siparişiniz Yola Çıktı! — Takip No: {{tracking_no}}`
- **Gövde:** Kargo takip linki butonu (`Kargom Nerede`), gönderilen kalemlerin listesi, teslimat sırasında hasarlı koli kontrolü hatırlatması.

---

## BÖLÜM 3: YASAL SÖZLEŞME VE POLİTİKA İSKELETLERİ

### 3.1 Ön Bilgilendirme Formu İskeleti
```markdown
# ÖN BİLGİLENDİRME FORMU

1. SATICI BİLGİLERİ:
Unvan: Nutopia Fındık Değirmeni — Mehmet Güven
Adres: Hatipoğulları Alanı, Merkez, D:1 No:6/B, Ormanlı / Kdz. Ereğli / Zonguldak
Telefon: 0538 028 82 02 | E-posta: destek@nutopiano.com

2. SÖZLEŞME KONUSU ÜRÜN VE HİZMETİN NİTELİKLERİ:
Ürünlerin cinsi, miktarı, marka/modeli, rengi ve vergiler dahil satış bedeli sipariş özetinde belirtildiği gibidir.

3. TESLİMAT VE KARGO MASRAFLARI:
Kargo bedeli 750,00 TL ve üzeri siparişlerde SATICI tarafından karşılanmakta olup, bu tutarın altındaki siparişlerde ALICI'ya aittir. Teslimat süresi yasal 30 günlük süreyi aşmamak kaydıyla kargoya verilişten itibaren ortalama 1-3 iş günüdür.

4. CAYMA HAKKI VE İSTİSNALARI:
ALICI, Mesafeli Sözleşmeler Yönetmeliği uyarınca 14 gün içinde cayma hakkına sahiptir. ANCAK Yönetmeliğin 15/1-ç maddesi uyarınca; "Tesliminden sonra ambalaj, bant, mühür, paket gibi koruyucu unsurları açılmış olan mallardan; iadesi sağlık ve hijyen açısından uygun olmayanların" teslimine ilişkin sözleşmelerde CAYMA HAKKI KULLANILAMAZ. Bu doğrultuda koruyucu güvenlik kilidi veya vakumlu ambalajı açılmış fındık ezmesi, krema ve vakumlu paketli ürünlerde keyfi iade kabul edilmemektedir.
```

### 3.2 Mesafeli Satış Sözleşmesi İskeleti
```markdown
# MESAFELİ SATIŞ SÖZLEŞMESİ

MADDE 1 — TARAFLAR:
SATICI: Nutopia Fındık Değirmeni
ALICI: Sipariş esnasında adı ve iletişim bilgileri girilen gerçek veya tüzel kişi.

MADDE 2 — SÖZLEŞMENİN KONUSU:
İşbu sözleşmenin konusu, ALICI'nın SATICI'ya ait nutopiano.com internet sitesinden elektronik ortamda siparişini yaptığı ürünlerin satışı ve teslimi ile ilgili olarak 6502 sayılı Tüketicinin Korunması Hakkında Kanun ve Mesafeli Sözleşmeler Yönetmeliği hükümleri gereğince tarafların hak ve yükümlülüklerinin saptanmasıdır.

MADDE 3 — GENEL HÜKÜMLER:
3.1. ALICI, internet sitesinde sözleşme konusu ürünün temel nitelikleri, satış fiyatı ve ödeme şekli ile teslimata ilişkin ön bilgileri okuyup bilgi sahibi olduğunu ve elektronik ortamda gerekli teyidi verdiğini beyan eder.
3.2. Fiyat manipülasyonu, sistemsel yazılım hataları veya stok tükenmesi durumlarında SATICI siparişi iptal ederek tahsil edilen tutarı yasal süresi içinde iade etme hakkını saklı tutar.

MADDE 4 — YETKİLİ MAHKEME:
İşbu sözleşmeden doğan uyuşmazlıklarda ALICI'nın yerleşim yerindeki Tüketici Hakem Heyetleri ile Tüketici Mahkemeleri yetkilidir.
```

### 3.3 Değirmen Hizmet ve Fındık İşleme Sözleşmesi İskeleti
```markdown
# FINDIK İŞLEME VE DEĞİRMEN HİZMET KOŞULLARI

1. HİZMETİN TANIMI:
Üreticinin bahçesinden veya adresinden kurye ile alınan kabuklu fındığın, Nutopia Değirmeni tesislerinde kırılması, kavrulması, zarının soyulması, taş değirmende ezilmesi ve/veya hava almaz vakumlu paketlenmesi hizmetidir.

2. TARTI VE TUTANAK ESASLARI:
- Fındığın teslim alınması esnasında şoför ve üretici huzurunda yapılan dijital kantar tartısı (brüt, dara ve net kg) esastır.
- Tartı sonucu üreticiye SMS onay kodu ile teyit ettirilir ve dijital tutanak oluşturulur.
- Tesis kantarına girişte tespit edilen ±%1'i aşan tartı farklılıklarında üretici derhal bilgilendirilir.

3. RANDIMAN VE FİRE BİLGİLENDİRMESİ:
Kabuklu fındığın iç fındığa dönüşüm randımanı fındığın kalitesi, nem oranı ve çürük/boş oranına göre değişmekte olup ortalama %50 kabul edilir. Taş çekim ezme işleminde doğal buharlaşma ve yağ firesi oluşabileceği üretici tarafından kabul edilir.

4. ÜCRET VE ÖDEME:
Hizmet bedeli, teslim alınan kabuklu fındığın net kilogramı üzerinden hesaplanır. Ödeme teslimat anında nakit, mobil POS veya online ödeme linki ile tahsil edilir.
```

### 3.4 KVKK Aydınlatma Metni İskeleti
```markdown
# 6698 SAYILI KVKK UYARINCA AYDINLATMA METNİ

Veri Sorumlusu: Nutopia Fındık Değirmeni — Mehmet Güven.
Kişisel verileriniz (Ad, Soyad, Telefon, Adres, Konum Pini, IP Adresi, Sipariş ve Tartı Kayıtları);
- E-ticaret siparişlerinizin işlenmesi, paketlenmesi ve kargolanması,
- Fındık kırma, kavurma ve kurye hizmetlerinin yerine getirilmesi,
- Yasal muhasebe, vergi ve fatura yükümlülüklerinin ifası,
- İlgili mevzuat uyarınca yetkili kamu kurum ve kuruluşlarına bilgi verilmesi
amaçlarıyla 6698 sayılı Kanun’un 5. maddesinde belirtilen "sözleşmenin kurulması ve ifası", "veri sorumlusunun hukuki yükümlülüğü" ve "meşru menfaat" hukuki sebeplerine dayalı olarak işlenmektedir.

Kişisel verileriniz yalnızca anlaşmalı kargo firmaları, SMS sağlayıcıları ve yasal bildirim mercileri ile paylaşılmakta olup üçüncü taraflara ticari amaçla devredilmemektedir. Kanun'un 11. maddesi kapsamındaki haklarınızı kvkk@nutopiano.com adresine yazılı olarak iletebilirsiniz.
```

