# 13 — Ekran Taslakları ve Arayüz Akışları

> Bu belge, vitrin (Mağaza ve Değirmen), yönetim paneli ve şoför PWA arayüzlerinin tüm ekranlarını, bileşen ağacını, veri bağlama kurallarını, validasyonlarını, boş/hata/yükleniyor durumlarını en ince ayrıntısına kadar tanımlar.
> Bağlayıcı mimari: `12-mimari-kilit-kararlar.md` (K6, K7, K23). Veri kaynağı: `14-sql-sema.md`.

---

## BÖLÜM 1: MAĞAZA (NUTOPIANO VİTRİN - Next.js App Router)

### 1.1 Ortak Header, Gezinme ve Bildirim Şeritleri
- **Üst Duyuru Bandı (Top Announcement Bar):**
  - Dinamik metin: `core.settings` üzerinden çekilen `shop.free_shipping_threshold_kurus` ve duyuru metni ("🚚 750 ₺ Üzeri Kargo Bedava · 🎖️ Şehit Yakını & Gazilere %20 İndirim").
  - İletişim kısayolu: `tel:05380288202` ve Değirmen canlı durum rozeti (`🟢 Değirmen Açık: Bugün taze kavurma yapılıyor`).
- **Ana Header (Desktop & Mobile):**
  - **Logo:** Sol blokta `Nutopia Fındık Değirmeni` markası ve logo ikonu. Tıklama `/` rotasına yönlendirir.
  - **Ana Gezinme Linkleri:**
    - `Ana Sayfa` (`/`)
    - `Değirmen Hizmetleri` (`/degirmen`) -> Vurgulu rozet ("Kendi Fındığını İşlet").
    - `Nutopiano Gurme Ürünler` (`/urunler`) -> Açılır mega menü (Ezme & Krema, Kavrulmuş & Krokan, Çiğ & Kabuklu).
    - `Hakkımızda` (`/hakkimizda`)
    - `İletişim & Konum` (`/iletisim`)
  - **Aksiyon İkonları (Sağ Blok):**
    - Arama butonu / açılır input (canlı FTS araması).
    - Müşteri Giriş / Profil ikonu (Giriş yapılmamışsa SMS OTP modalını açar; yapılmışsa `/hesap` linki).
    - Sepet Butonu: Sepetteki toplam adet (`badge`), tıklandığında sağdan açılan `Cart Drawer` tetiklenir.
  - **Mobil Menü (Hamburger):** Ekran < 768px olduğunda alttan veya soldan açılan tam ekran çekmece menü.

---

### 1.2 Ana Sayfa (`/`)
1. **İki Yönlü Karar Hero Alanı (Dual Decision Hero):**
   - *Başlık:* "Fındık dalda yetişir. Gerçek yolculuğu değirmende başlar."
   - *Alt Açıklama:* "İster kendi bahçenden çıkan mahsulü değirmenimizde işleyelim, ister katkısız Nutopiano ürünlerimizle sofranıza lezzet katalım."
   - *Bölünmüş Kartlar (Split Cards):*
     - **Kart A (Çiftçi / Üretici):** Görsel (Kırma & Kavurma Makinesi), Başlık: "Fındığım Var, İşletmek İstiyorum", Özellikler: "Bahçeden Alım Kuryesi · Şeffaf Tartı · Taş Değirmende Ezme", CTA Buton: `Değirmen Ücretini Hesapla & Randevu Al →` (`/degirmen`).
     - **Kart B (Gurme / Tüketici):** Görsel (Nutopiano Cam Kavanozlar ve Çifte Kavrulmuş Fındık), Başlık: "Katkısız Fındık Ürünleri Almak İstiyorum", Özellikler: "%100 Doğal · Palm Yağı ve İlave Şeker Yok · Aynı Gün Taze Dolum", CTA Buton: `Nutopiano Mağazasına Git →` (`/urunler`).
2. **Güven ve Standartlar Şeridi (Trust Bar):**
   - 4'lü Grid: 
     - 🌰 *%100 Karadeniz Mahsulü* (Kdz. Ereğli Ormanlı yöresi seçme fındıkları).
     - 🌿 *Sıfır Palm Yağı & Koruyucu* (Yalnızca fındık ve pancar şekeri/kakao).
     - 🚚 *Darbe Korumalı Vakum & Kargo* (750 ₺ üzeri ücretsiz).
     - 🎖️ *Şehit Yakını & Gazi İndirimi* (Daimi %20 minnet desteği).
3. **Öne Çıkan Ürünler (Featured Products Grid):**
   - Başlık: "Değirmenin İmza Lezzetleri"
   - 4'lü Ürün Kartı (Sütlü Krema, Kakaolu Krema, %100 Fındık Ezmesi, Çifte Kavrulmuş Fındık).
   - Kart Bileşeni: Görsel, Kategori etiketi, Ürün Adı, Gramaj Hapları (Varyant seçici), Fiyat etiketi, `Hızlı Ekle` butonu.
4. **Zanaat ve Üretim Döngüsü (Story Steps):**
   - 5 Aşamalı Yatay Çizgi: Hasat -> Doğal Kurutma -> Hassas Kırma -> Usta Kavurması -> Taş Değirmende Soğuk Çekim.
5. **Şeffaf Tesis ve Değirmen Tanıtımı (Video/Görsel Bölümü):**
   - Ormanlı tesisinden kareler, üreticilerin değirmende canlı izleme alanı, Hijyen ve Gıda Onay sertifikaları.
6. **Müşteri Geri Bildirimleri & Değerlendirmeler:**
   - Onaylanmış alıcı yorumları (satın alım doğrulamalı).

---

### 1.3 Ürün Listeleme & Kategori Sayfası (`/urunler`, `/urunler/[kategori]`)
- **Filtre ve Arama Çubuğu (Toolbar):**
  - Kategori Çipleri: `Tümü (7)`, `Ezme & Krema (3)`, `Kavrulmuş & Krokan (2)`, `İç & Kabuklu (2)`.
  - Canlı Arama Input'u (`debounce: 300ms`, PostgreSQL FTS uç noktası `/v1/products?q=`).
  - Sıralama Menüsü: "Önerilen", "Fiyat: Düşükten Yükseğe", "Fiyat: Yüksekten Düşüğe", "En Yeniler".
- **Ürün Izgarası (Product Grid):**
  - Masaüstünde 3 sütun, mobilde 1 veya 2 sütun.
  - **Ürün Kartı Bileşeni (`ProductCard`):**
    - Üst Rozet: İndirim yüzdesi / Yeni / Çok Satan / Şekersiz.
    - Resim Alanı: 1:1 oran, WebP/AVIF, lazy loading, hover durumunda 2. görsel/kavanoz içi dokusu.
    - Başlık ve Kısa Açıklama.
    - Varyant Seçici (Radio / Pill Button): Örn. `300 g (₺165)` | `700 g (₺340)`. Seçilen varyanta göre kart üzerindeki fiyat dinamik güncellenir.
    - Stok Durumu: `Tükendi` ise buton pasif ve "Gelince Haber Ver" tetikleyicisi; `Son X adet` uyarısı.
    - Hızlı Aksiyonlar: `Sepete Ekle` butonu (Loading spinner animasyonu ile) ve `Besin Değerleri & Detay` bağlantısı.
- **Boş Durum (Empty State):** "Aramanızla eşleşen ürün bulunamadı. Filtreleri temizleyin."

---

### 1.4 Ürün Detay Sayfası (`/urun/[slug]`)
- **Galeri Alanı (Sol Kolon):**
  - Ana görsel (zoom özellikli, yüksek çözünürlüklü).
  - Küçük resimler (Thumbnails carousel/grid).
  - Görsel Alt Metinleri: SEO için erişilebilir açıklamalar.
- **Satın Alma & Varyant Alanı (Sağ Kolon):**
  - Ekmek Kırıntısı (Breadcrumbs): `Ana Sayfa > Ürünler > Ezme & Krema > %100 Fındık Ezmesi`.
  - Ürün Adı (`h1`) ve Kısa Tanıtım.
  - Fiyat Gösterimi: Liste Fiyatı (büyük puntolu) ve Varsa Üstü Çizili Eski Fiyat.
  - Varyant Seçimi: Gramaj butonları (Net gramaj, birim kg maliyeti örn: `550 ₺/kg`).
  - Adet Seçici (`QuantityStepper`): Eksi / Artı butonları, min: 1, max: `variant.max_per_order`.
  - Sepete Ekle Butonu (`CTA`): Geniş, dikkat çekici buton. Tıklandığında `shop.carts` tablosuna atomik ekler ve `Cart Drawer`'ı açar.
  - Güvence İkonları: "Aynı Gün Kargo (14:00 öncesi)", "Gıda Güvenliği & Hijyenik Vakum", "Kırılmaz Özel Ambalaj".
- **Tab / Akordeon Detay Alanı:**
  - **Tab 1: İçindekiler & Alerjen Uyarısı:** %100 Karadeniz Fındığı; gluten, palm yağı, ilave tuz ve şeker içermez uyarısı. Alerjen: `Fındık içerir. Eser miktarda diğer sert kabuklu meyveler içerebilir.`
  - **Tab 2: Besin Değerleri Tablosu (100 g için):**
    - Enerji (kcal), Yağ (Doymuş Yağ), Karbonhidrat (Şeker), Lif, Protein, Tuz.
    - Tablonun altında analiz raporu referans numarası (`nutrition_source`).
  - **Tab 3: Saklama Koşulları & Raf Ömrü:** "Güneş görmeyen, serin ve kuru yerde saklayınız. Doğal fındık yağı kavanoz üstünde toplanabilir; bu ürünün saf ve katkısız olduğunu gösterir. Karıştırarak tüketiniz. Raf ömrü: 12 Ay."
  - **Tab 4: Teslimat ve İade Politikası:** Türk Gıda Kodeksi uyarınca koruyucu ambalajı açılmamış ürünlerde hasarlı/ayıplı teslimat değişim prosedürü.

---

### 1.5 Sepet Çekmecesi & Sepet Sayfası (`CartDrawer` & `/sepet`)
- **Ücretsiz Kargo İlerleme Çubuğu:**
  - "Ücretsiz kargo için `₺X` değerinde ürün ekleyin!"
  - Eşik aşıldığında: "🎉 Tebrikler! Kargo Bedava!" (Yeşil bar).
- **Sepet Kalemleri Listesi:**
  - Küçük resim, Varyant adı, Birim fiyat, Adet artır/azalt/sil kontrolleri, Satır toplamı.
  - Canlı stok uyarısı (sepetteki adet stoktan fazlaysa otomatik sınırlama ve bilgilendirme).
- **Kupon / İndirim Kodu Alanı:**
  - Text input + "Uygula" butonu.
  - Geçerli kupon uygulandığında: İndirim kalemi yeşil renkle görünür, iptal butonu ("Kaldır").
- **Ödeme Yöntemi Tercihi (Erken Seçim):**
  - Radio: `Kredi Kartı` | `Havale / EFT (%5 İndirim)` | `Kapıda Ödeme`.
  - Havale seçildiğinde dip toplamda %5 düşüş canlı gösterilir.
- **Şehit Yakını / Gazi İndirimi Kutusu:**
  - `[ ] Şehit Yakını / Gaziyim (%20 Minnet İndirimi İste)`
  - Bilgi notu: Sipariş oluşturulduğunda doğrulanmış hesap değilse belge onay adımı gerekecektir.
- **Dip Toplam:**
  - Ara Toplam: `₺X`
  - Kupon İndirimi: `-₺Y`
  - Havale İndirimi: `-₺Z`
  - Kargo Ücreti: `Ücretsiz` veya `₺45,00`
  - **Genel Toplam: `₺TOPLAM`**
- **Aksiyon Butonları:**
  - `Güvenli Ödemeye Geç →` (Doğrudan `/odeme` sayfasına)
  - `WhatsApp ile Hızlı Sipariş Ver` (Alternatif kanal: sepet özetini metinleştirip işletme hattına iletir).

---

### 1.6 Ödeme Sayfası (`/odeme` - Checkout Funnel)
*Tek sayfa akordeon / adım mimarisi (Single-page Step Checkout):*
1. **Adım 1: İletişim Bilgileri:**
   - E-posta adresi (sipariş teyidi ve e-Arşiv fatura için).
   - Cep Telefonu (05xx... - Kargo SMS ve takip bildirimleri).
   - "Hesabınız var mı? Giriş yapın" hızlı butonu.
2. **Adım 2: Teslimat Adresi:**
   - Ad, Soyad.
   - İl (Dropdown - `core.geo_places` city listesi).
   - İlçe (Seçilen ile göre dinamik yüklenir).
   - Mahalle (İsteğe bağlı veya ilçe altından seçilir).
   - Açık Adres (Cadde, sokak, bina, daire no).
   - Adres Başlığı (Ev, İş vb.).
   - "Fatura adresim teslimat adresimle aynı" checkbox'ı (İşaret kaldırılırsa Kurumsal Fatura / Farklı Fatura Adresi formu açılır: VKN, Vergi Dairesi, Şirket Unvanı).
3. **Adım 3: Kargo Seçeneği:**
   - Standart Anlaşmalı Kargo (Yurtiçi/Aras/MNG) - Teslimat süresi: 1-3 iş günü.
4. **Adım 4: Ödeme Seçeneği:**
   - **Opsiyon A: Kredi/Banka Kartı (iyzico Hosted / Responsive Form):**
     - Kart Numarası, Son Kullanma Tarihi, CVV.
     - 3D Secure Doğrulama zorunlu bilgilendirmesi.
   - **Opsiyon B: Havale / EFT (%5 Ekstra İndirimli):**
     - Banka hesap listesi (Ziraat Bankası, İş Bankası vb. IBAN ve Alıcı Adı).
     - Açıklama kodu uyarısı: "Sipariş sonrasında verilecek `NT-XXXXXX` kodunu havale açıklamanıza yazınız."
   - **Opsiyon C: Kapıda Ödeme:**
     - Nakit veya Kredi Kartı ile kapıda ödeme şartları (varsa kapıda ödeme hizmet bedeli dökümü).
5. **Adım 5: Yasal Onaylar ve Siparişi Tamamla:**
   - `[X]` Ön Bilgilendirme Koşulları'nı okudum, kabul ediyorum.
   - `[X]` Mesafeli Satış Sözleşmesi'ni okudum, onaylıyorum.
   - Sözleşme linklerine tıklandığında sayfa terk edilmeden Modal içinde dinamik metin gösterilir.
   - `[Siparişi Onayla ve ₺... Öde]` Ana Butonu (Çift tıklama korumalı, `Idempotency-Key` kontrollü).

---

### 1.7 Sipariş Başarılı / Takip Sayfası (`/siparis/[token]`, `/takip`)
- **Teşekkür & Durum Başlığı:** "Siparişiniz Alındı! Sipariş Numaranız: NT-2026-000142"
- **İşlem Adımları (Status Tracker):**
  - `Sipariş Alındı` -> `Ödeme Onaylandı` -> `Hazırlanıyor / Paketleniyor` -> `Kargoya Verildi` -> `Teslim Edildi`.
- **Havale Bilgileri (Havale seçilmişse):**
  - Kırmızı kutu: "Lütfen 48 saat içinde ₺X tutarını aşağıdaki IBAN'a iletiniz. Açıklama: NT-2026-000142".
- **Kargo Takip Kutusu (Kargolandığında):**
  - Kargo Firması, Takip Numarası, "Kargom Nerede?" harici takip butonu.
- **Sipariş Detay Özeti:** Ürün listesi, teslimat adresi, ödeme yöntemi dökümü, e-Arşiv fatura indirme butonu (`ops.invoices` hazır olduğunda).

---

## BÖLÜM 2: DEĞİRMEN & KURYE VİTRİNİ (`/degirmen`)

### 2.1 Değirmen Tanıtım ve Fiyat Listesi (`/degirmen`)
1. **Hero:** "Fındığınız Size Ait, Ustalığı Bize Emanet."
   - Bahçenizden çıkan çuvalları kapınızdan alıyoruz; kırma, kavurma, zar soyma ve ezme işlemlerinden sonra adresinize teslim ediyoruz.
2. **Şeffaf Fiyat Tablosu:**
   - Kırma: `40 ₺/kg`
   - Kavurma: `70 ₺/kg`
   - Kırma + Kavurma: `65 ₺/kg`
   - Kırma + Kavurma + 1 kg Vakum: `70 ₺/kg`
   - Kırma + Kavurma + 500 g Vakum: `80 ₺/kg`
   - Kırma + Kavurma + 250 g Vakum: `90 ₺/kg`
   - Taş Değirmende Fındık Ezmesi: `130 ₺/kg`
3. **Akıllı Değirmen Maliyet Hesaplayıcı (Bileşen):**
   - *Girdi 1:* Kabuklu Fındık Miktarı (kg) Slider / Input (Örn: `150 kg`).
   - *Girdi 2:* İstenen Hizmet Paketi Dropdown.
   - *Girdi 3:* Teslim Şekli (`Kurye Bahçemden Alsın` / `Değirmene Kendim Getireceğim`).
   - *Girdi 4:* Şehit Yakını / Gazi İndirimi (%20) Seçeneği.
   - *Canlı Sonuç Kartı:*
     - Tahmini İç Fındık / Ezme Çıktısı: `~75 kg` (%50 randıman bazında bilgilendirme).
     - Tahmini İşleme Bedeli: `₺X.XXX`
     - Kurye / Alım Bedeli: `Ücretsiz` (Belirli kg üzeri) veya `₺YYY`.
     - `Bu Hesaplama İle Talep Oluştur →` Butonu.

---

### 2.2 Kurye & Değirmen Talep Sihirbazı (`/degirmen/talep`)
*Çiftçiler ve üreticiler için 3 Adımlı, Büyük Yazı Karakterli, Dokunmatik Dostu Arayüz:*

#### Adım 1: Mahsul ve Hizmet Bilgisi
- Hizmet Paketi Seçimi: Kartlar halinde büyük butonlar (Kırma, Kırma+Kavurma, Ezme).
- Tahmini Miktar: Sayısal input (kg) ve yardımcı çuval sayısı seçici (1 Çuval ≈ 50 kg).
- Geri Teslim Şekli:
  - `[ ] İşlendikten sonra kuryeniz adresime geri getirsin.`
  - `[ ] Tesisinize gelip kendim teslim alacağım.`

#### Adım 2: Bahçe & Alım Konumu
- İl / İlçe Seçimi (Başlangıçta Kdz. Ereğli, Alaplı, Ormanlı, Çaycuma vb. aktif bölgeler).
- Köy / Mahalle Adı.
- Yol / Mevki Açık Tarifi: "Örn: Ormanlı Cami yanı, sarı traktörün durduğu bahçe yolu."
- Harita Üzerinde Pin Bırakma (Leaflet / OSM tabanlı interaktif harita pin'i; GPS konumu butonla alınabilir).
- Saha İrtibat Kişisi: "Bahçede fındığı teslim edecek kişi farklıysa Ad ve Telefonu".

#### Adım 3: İletişim ve Randevu Tercihi
- Üretici Adı Soyadı.
- Cep Telefonu Numarası.
- `[SMS Onay Kodu Gönder]` Butonu -> 6 Haneli OTP Giriş Kutusu.
- Tercih Edilen Alım Günü (Takvimden gün seçimi) ve Zaman Dilimi (`Sabah: 09:00 - 13:00`, `Öğleden Sonra: 13:00 - 18:00`).
- Ek Notlar (Örn: "Yol dar, büyük kamyon giremez, transit araçla gelin").
- Yasal Onay: `Değirmen İşleme ve Taşıma Koşulları Sözleşmesi` onayı.
- `[Talebi Tamamla ve Gönder]` Butonu.

---

### 2.3 Üretici Talep Takip Ekranı (`/degirmen/taleplerim/[token]`)
- **Talep Başlık Kartı:** "Talep No: DG-2026-000089 - Durum: Şoför Yolda 🚚"
- **Aşama Zaman Çizelgesi (Timeline):**
  - `1. Talep Alındı` (Tarih/Saat)
  - `2. Değirmen Tarafından Onaylandı` (Planlanan Tarih: 12 Kasım Salı)
  - `3. Şoför Atandı ve Yolda` (Şoför Adı, Araç Plakası, İletişim Butonu)
  - `4. Yerinde Tartıldı & Teslim Alındı` (Kesin Kilo: 412 kg, Brüt/Dara Detayı, Fiş Resmi)
  - `5. Değirmende İşleniyor (Lot No: L26-000089)`
  - `6. İşlem Tamamlandı & Paketlendi` (Çıkan Randıman ve Net Ürün: 206 kg)
  - `7. Teslim Edildi & Ödeme Tamamlandı`
- **Tartı ve Tutanak Belgesi (İndirilebilir PDF / Web Görünümü):**
  - Şoförün sahada girdiği brüt, dara, çuval adedi ve net kilo dökümü.
  - Alım anında çekilen kantar fişi fotoğrafı.
- **Ödeme Durumu ve Online Ödeme:**
  - Tartı sonrası kesinleşen işleme ücreti.
  - Varsa `[Kredi Kartı ile Güvenli Öde]` butonu veya `[Kapıda Nakit / POS]` seçeneği.

---

## BÖLÜM 3: YÖNETİM PANELİ (ADMIN - React Vite SPA)

### 3.1 Giriş & Güvenlik (`/admin/login`)
- E-posta ve Parola girişi.
- Başarılı şifre sonrası: **İki Adımlı Doğrulama (TOTP 2FA) Ekranı** (Google Authenticator / 6 haneli kod).
- Yedek Kurtarma Kodu seçeneği.
- IP kısıtlama uyarısı ve başarısız giriş sayacı.

---

### 3.2 Kontrol Paneli (Dashboard - `/admin`)
- **Üst Metrik Kartları:**
  - Bugünün Mağaza Cirosu (`₺XX.XXX`) ve Sipariş Sayısı.
  - Bekleyen / Hazırlanacak Siparişler (`X adet`).
  - Bekleyen Değirmen Talepleri (`Y adet`).
  - Sahadaki Aktif Şoförler ve Bugünkü Alım Hacmi (`Z kg`).
- **Acil Aksiyon Listesi (Action Required):**
  - Havale onayı bekleyen siparişler.
  - Randıman sapması olan değirmen partileri (Anomali uyarısı).
  - Kritik stok seviyesine düşen ürün varyantları.
- **Grafikler:**
  - Son 30 günlük satış trendi (Mağaza vs Değirmen).
  - Haftalık işlenen fındık hacmi (kg).

---

### 3.3 Mağaza Yönetimi (Katalog, Sipariş, Kargo)
1. **Ürün Yönetimi (`/admin/products`):**
   - Tablo: Görsel, Ürün Adı, Kategori, Fiyat Aralığı, Toplam Stok, Durum (Taslak/Yayında), Aksiyonlar.
   - **Ürün Ekleme / Düzenleme Ekranı:**
     - Sekmeli Form: `Genel Bilgiler`, `Varyantlar & Fiyat`, `Medya Galeri`, `Besin Değerleri & Alerjen`, `SEO`.
     - Varyant tablosu: Her satırda SKU, Etiket ("300 g"), Fiyat (₺), Kargo Ağırlığı (g), Barkod, Stok Miktarı, `Sil/Ekle`.
     - Görsel Sürükle-Bırak Alanı: Sıralama değiştirme, kapak görseli seçme.
     - Alerjen çoklu etiket seçimi (`TagInput`).
2. **Sipariş Yönetimi (`/admin/orders`):**
   - Filtreler: Durum (`pending_payment`, `paid`, `processing`, `shipped` vb.), Ödeme Yöntemi, Tarih Aralığı, Arama (Sipariş No, Müşteri Adı, Telefon).
   - **Sipariş Detay Ekranı (`/admin/orders/[id]`):**
     - Müşteri Bilgisi, Teslimat ve Fatura Adresi.
     - Sipariş Edilen Ürünler (Resim, SKU, Adet, Birim Fiyat, Vergi Oranı, Satır Toplamı).
     - Zaman Çizelgesi ve Durum Değiştirici (`Durumu 'Hazırlandı' Yap`, `Kargoya Verildi Yap`).
     - Kargo Entegrasyonu Alanı: Taşıyıcı seçimi, Takip Kodu Girişi, Kargo Barkod/Etiket Basma (`Print Packing Slip`).
     - Ödeme Detayı: Sağlayıcı referansı, iyzico işlem kodu, Havale Onaylama Butonu (`[Havale Alındı Olarak İşaretle]`).
     - İade / İptal Aksiyonu: Kısmi / Tam iade tutarı girme, İade nedeni seçme, `[İadeyi Gerçekleştir]` butonu (Çift onay diyalogu ile).
     - Sipariş İçi Notlar: Personele özel dahili not ekleme geçmişi.

---

### 3.4 Değirmen & Kurye Operasyon Ekranları
1. **Talep Kutusu (`/admin/mill/requests`):**
   - Liste Görünümü & Harita Görünümü (Talepler harita üzerinde pin olarak gösterilir).
   - Talep Onaylama Modalı: Tahmini kg kontrolü, bölge uygunluğu, Alım Günü ve Saat Dilimi Belirleme, `[Talebi Onayla & Çiftçiye SMS Gönder]`.
2. **Kurye Dağıtım & Planlama Panosu (`/admin/mill/dispatch`):**
   - Günlük Rota Planlama Ekranı (Tarih seçici).
   - Sol Kolon: O gün için planlanmamış onaylı alım talepleri listesi.
   - Sağ Kolon: Şoför Sütunları (Örn: `Şoför Ahmet - 34 AB 1234 - Kapasite: 1500 kg`).
   - Sürükle-bırak ile talebi şoföre atama ve rota sırasını belirleme (`1. Durak`, `2. Durak`).
   - Kapasite Barı: Atanan toplam tahmini kg / Araç kapasitesi göstergesi.
   - `[Günlük Planı Yayınla]` Butonu -> Şoförün mobil ekranına düşer ve çiftçilere alım kodu SMS'i tetiklenir.
3. **Tartı & Randıman Denetim Ekranı (`/admin/mill/weighing`):**
   - Sahadan gelen tartı kayıtları listesi.
   - Brüt / Dara / Net kg kontrolü, kantar fişi fotoğrafı önizlemesi.
   - Değirmene giriş ikinci tartısı ile saha tartısı arasındaki fark göstergesi (`±%1` tolerans aşımında kırmızı uyarı).
4. **Değirmen İş Emri (Lot) Takibi (`/admin/mill/jobs`):**
   - Partiler (Örn: `L26-000104`).
   - Durum butonları: `Kırmaya Alındı` -> `Kavurmaya Alındı` -> `Değirmene Alındı` -> `Paketlendi & Hazır`.
   - Çıkan nihai ürün miktarını girme (`Net Çıkan: 104 kg`) -> Otomatik randıman hesaplama (`%50,9`) -> Müşteriye hazır SMS'i gönderme.

---

### 3.5 Ayarlar & Sistem Yönetimi (`/admin/settings`)
- **İş Kuralları ve Eşikler:** Kargo bedava limiti (₺), Havale indirim oranı (%), Gazi minnet indirim oranı (%), Sepet rezerv süresi (dk).
- **Kapsama Alanları & Fiyatlandırma:** İlçe/Köy bazlı kurye servis ücretleri tablosu, minimum alım kg sınırları.
- **Personel & Yetkilendirme:** Personel listesi, rol atama (`owner`, `manager`, `packer`, `driver`), yeni personel davet etme.
- **SMS & E-Posta Şablonları:** Şablon metinlerini canlı düzenleme, değişken etiketleri (`{{musteri_adi}}`, `{{talep_no}}`).
- **Denetim Günlüğü (`/admin/audit`):** Kim, hangi tarihte, hangi IP'den, hangi kaydı değiştirdi (`before / after` JSON diff görünümü).

---

## BÖLÜM 4: ŞOFÖR MOBİL UYGULAMASI (DRIVER PWA)

*Mobil ekran (< 450px) için özel tasarlanmış, saha kullanımına ve eldivenli dokunmaya uygun, yüksek kontrastlı arayüz:*

### 4.1 Şoför Girişi & Günlük Özet (`/driver`)
- PIN Kodu veya Hızlı Biyometrik/Kalıcı Oturum ile Giriş.
- Üst Bilgi: "Merhaba Ahmet · Bugün: 14 Alım, 2 Teslimat · Toplam Yük: 850 / 1500 kg".
- `[Güne Başla]` Butonu.

---

### 4.2 Günün Rota Listesi (`/driver/today`)
- Sıralı Durak Kartları:
  - Sıra Numarası (Büyük daire içinde: `1`, `2`, `3`).
  - Müşteri Adı ve Bölge ("Ormanlı - Merkez").
  - Tahmini Miktar ("~150 kg - 3 Çuval").
  - Hizmet Türü ("Kırma + Ezme").
  - Hızlı İletişim Aksiyonları:
    - `[📞 Ara]` (Doğrudan arama başlatır).
    - `[📍 Yol Tarifi]` (Google Maps / Yandex Navigasyon uygulamasını koordinatla açar).
  - Durum Butonu: `[Yola Çıktım]` -> Vardığında: `[Adrese Ulaştım]`.

---

### 4.3 Alım & Tartı Ekranı (`/driver/pickups/[id]`)
*Alım noktasına varıldığında açılan operasyon sihirbazı:*
1. **Adım 1: Güvenlik / Müşteri Teyidi:**
   - Müşterinin telefonuna giden 4 haneli Alım Kodu sorulur ve girilir (`[Alım Kodunu Doğrula]`).
2. **Adım 2: Tartı Girişi (Büyük Sayısal Klavye):**
   - Çuval Adedi: `[ + ] [ - ]` butonları veya sayı girişi (Örn: `4`).
   - Brüt Ağırlık (kg): `212.5`
   - Dara Ağırlığı (kg): Standart çuval darası otomatik önerilir (`0.8 kg`) veya manuel değiştirilir.
   - Net Ağırlık (Hesaplanan): `211.7 kg` (Büyük yeşil puntolarla gösterilir).
3. **Adım 3: Kantar Fişi / Çuval Fotoğrafı:**
   - `[Fotoğraf Çek / Ekle]` butonu (Cihaz kamerasını doğrudan açar).
4. **Adım 4: Müşteri Tartı Onayı:**
   - Müşteriye anında SMS ile giden onay kodu girilir veya ekrandan dijital paraf alınır.
   - Varsa özel not: "Fındık hafif nemli, kurutma gerekebilir."
5. **Adım 5: Alımı Tamamla:**
   - `[Alımı Onayla ve Tamamla]` Butonu.
   - Veri anında API'ye iletilir; internet yoksa yerel `IndexedDB` kuyruğuna alınır, bağlantı gelince otomatik senkronize edilir.
   - Müşteriye "Fındığınız 211.7 kg olarak teslim alınmıştır" SMS'i otomatik tetiklenir.

---

### 4.4 Geri Teslimat & Tahsilat Ekranı (`/driver/deliveries`)
- İşlenmiş ürünlerin çiftçiye geri teslimi turu:
  - Teslim edilecek paket/kavanoz adedi ve net ağırlık teyidi.
  - Tahsil Edilecek Tutar Kartı: `₺2.750,00`.
  - Tahsilat Yöntemi: `[Nakit Alındı]` | `[Mobil POS ile Çekildi]` | `[Zaten Online Ödendi]`.
  - Teslim Alan Kişi Adı Soyadı.
  - `[Teslimatı Tamamla]` Butonu -> Günlük şoför kasa hesabına tahsilat işlenir.

