# 09 — UX, Tasarım Sistemi, SEO

> Mevcut sitenin tasarımına bağlı değiliz. Aşağıda yön ve kurallar var; görsel kimlik (renk/tipografi/logo) Aşama 0'da bir tasarım "sprint"i ile kesinleşir (11-hazirlik S-06).

## 1. Marka yönü (öneri, onay bekler)
- **Ton:** sıcak, dürüst, zanaatkâr, "değirmenden sofraya". Abartısız; kanıtlanabilir iddialar.
- **Görsel kişilik:** doğal malzeme, krem/kâğıt zemin, koyu fındık kahvesi metin, orman yeşili vurgu, altın/bal rengi ikincil. Gerçek fotoğraf (değirmen, usta eli, bahçe) stok görselden önde.
- **İki dünya, tek çatı:** Mağaza (hafif, gurme, fotoğraf ağırlıklı) ve Değirmen (net, işlevsel, büyük yazı, güven). Ortak logo, bileşenler ve tonlama; Değirmen sayfaları daha yüksek kontrast/okunaklılık.
- Ayrılma günü için: marka bileşenleri `packages/ui`'da, Mağaza/Değirmen "tema" ile farklılaşabilir.

## 2. Bilgi mimarisi
```
/                         Ana sayfa (iki yönlü giriş)
/urunler                  Tüm ürünler
/urunler/[kategori]
/urun/[slug]
/sepet  /odeme  /siparis/[token]  /takip
/hesap  (siparişler, adresler, bilgiler, izinler)
/degirmen                 Tanıtım + fiyat + hesaplayıcı
/degirmen/talep           Sihirbaz
/degirmen/taleplerim      Durum takibi
/hakkimizda  /iletisim  /sss
/teslimat-iade  /gizlilik  /kvkk  /mesafeli-satis  /cerez
/blog (v1.1, SEO: tarifler, fındık rehberi)
```
Menü: Ürünler · Değirmen Hizmeti · Hakkımızda · İletişim · (Hesap) · Sepet. Mobilde alt çubuk: Ana · Ürünler · Değirmen · Sepet · Hesap.

## 3. Temel akışlar ve UX ilkeleri
**Mağaza**
- Ürün kartı: net görsel, ad, "300 g'dan başlayan" fiyat, hızlı ekle (varyant seçimi gerekmeden tek varyantlıysa).
- Ürün sayfası: fiyat/gramaj/stok belirgin; "içindekiler & alerjen" **katlanmadan görünür**; teslimat tahmini; güven rozetleri (yalnız doğrulanabilirse).
- Sepet: çekmece + tam sayfa; kargo bedava ilerleme çubuğu; kupon alanı ikincil (kupon avcılığı dönüşümü düşürür, gizli yerine "kuponum var" bağlantısı).
- Ödeme: tek sayfa, misafir öncelikli, otomatik adres tamamlama (il/ilçe/mahalle), yöntem kartları (kart, havale %5, kapıda), canlı toplam, tek net buton "Siparişi onayla ve öde"; sözleşme onay kutusu açık metinli.
- Hata dili: ne oldu + ne yapmalı. Satır içi doğrulama. Sepet kaybı yok.
**Değirmen**
- Hesap makinesi *ilk ekranda*: "Kaç kg fındığınız var?" → fiyat.
- Talep sihirbazı 3 adım, her adımda tek ana soru; büyük dokunma hedefleri (≥ 48 px), 18 px+ gövde yazısı, yüksek kontrast.
- Telefonla talep her adımda görünür ("Yardım için arayın").
- Durum sayfası: görsel zaman çizelgesi, bir sonraki adım ve ne zaman, kimi arayacağı.

## 4. Tasarım sistemi (`packages/ui`)
- **Tasarım belirteçleri (tokens):** renk (anlamsal: `surface`, `text`, `primary`, `accent`, `danger`, `success`), boşluk ölçeği (4 px), yarıçap, gölge, tipografi ölçeği (modüler), hareket süreleri.
- **Tipografi:** serif başlık + sans gövde; web fontu kendi sunucumuzdan (`woff2`, alt küme Türkçe karakterli, `font-display: swap`). Harici font CDN yok (KVKK/performans).
- **Bileşenler:** Button, Input, Select, Checkbox/Radio, QuantityStepper, Card, ProductCard, PriceTag, Badge, Alert, Toast, Dialog/Drawer, Tabs, Accordion, Stepper, Timeline, Table, EmptyState, Skeleton, Pagination, FormField, AddressPicker, MapPin, Rating, Breadcrumb.
- **Belgeleme:** Storybook; her bileşende durumlar (hover, odak, devre dışı, hata, yükleniyor), a11y testi (axe).
- **Koyu mod:** MVP dışı; belirteçler hazır.
- **Görsel yönergeler:** ürün fotoğrafı arka plan/oran standardı (1:1 + 4:3), alt metin yazım kuralı, optimize edilmiş boyutlar.

## 5. Erişilebilirlik (WCAG 2.2 AA hedefi)
- Kontrast ≥ 4,5:1 (metin), 3:1 (büyük metin/UI). Odak halkası her zaman görünür. Klavye ile tam kullanım, "ana içeriğe geç" bağlantısı.
- Formlarda `label` zorunlu, hata `aria-describedby`/`aria-live`. Modal odak tuzağı + ESC.
- Hareket azaltma tercihi (`prefers-reduced-motion`). Görsellerde anlamlı `alt`.
- Dokunma hedefi ≥ 44–48 px. Zoom %200'de bozulmaz.
- Otomatik test: axe CI + manuel ekran okuyucu (NVDA/VoiceOver) temel akış kontrolü.

## 6. Performans bütçesi
| Metrik | Hedef (mobil 4G) |
|---|---|
| LCP | ≤ 2,5 sn |
| INP | ≤ 200 ms |
| CLS | ≤ 0,1 |
| İlk JS (vitrin) | ≤ 150 KB gz |
| Görsel | LCP görseli ≤ 120 KB, AVIF/WebP, `srcset` |
- Sunucu bileşenleri, minimum istemci JS; sepet/ödeme adacıkları (islands).
- Önbellek: ISR (ürün/kategori), `stale-while-revalidate`; Cloudflare statik varlık önbelleği.
- Lighthouse CI'da eşik altı → PR başarısız.

## 7. SEO
- **Teknik:** SSR/ISR, temiz URL, kanonik, `sitemap.xml` (ürün+kategori+içerik), `robots.txt` (admin/staging engelli), `hreflang` gerekmez, 301 haritası (eski yollar), 404/410 doğru.
- **Yapılandırılmış veri:** `Product` (+ `Offer`, `AggregateRating` yalnız gerçek yorum varsa), `Organization`, `LocalBusiness` (değirmen: adres, saat, telefon), `BreadcrumbList`, `FAQPage`.
- **İçerik:** ürün sayfalarına özgün metin (üretici kopya içerik yok); "Zonguldak/Kdz. Ereğli fındık kırma/kavurma/ezme" yerel anahtar kelime sayfaları; blog (tarifler, fındık ezmesi nedir, kavurma farkı); SSS.
- **Yerel SEO:** Google İşletme Profili (fotoğraf, saat, hizmetler, ürünler), NAP tutarlılığı (ad-adres-telefon), yorum toplama süreci.
- **Merchant:** Google Merchant Center ürün akışı (ürün feed'i API'den üretilir) — ücretsiz listeleme.
- Sosyal: OpenGraph/Twitter kartları, paylaşılabilir ürün görseli.
- Analitik: çerez gerektirmeyen (Umami/Plausible self-host) öncelik; GA4 kullanılırsa izin bandı.

## 8. İçerik ve metin yazımı
- Dil: sade Türkçe, 6. sınıf okuma düzeyi (özellikle Değirmen). Cümle kısa, eylem fiili ile buton ("Talep oluştur", "Sepete ekle").
- Yasak/dikkat: sağlık iddiası, kanıtsız rakam ("10.000+ müşteri"), karşılaştırmalı üstünlük iddiası.
- Fotoğraf çekim listesi (planlama): değirmen genel, makineler (kırma/kavurma/ezme), usta eli, bahçe/hasat (sezon: Ağustos), ürün stüdyo çekimi (her varyant), paketleme, ekip portre, şoför/araç.
- Mikro metin envanteri: boş sepet, stok yok, hata, başarı, SMS şablonları, e-posta konu satırları — tek tabloda yönetilir.

## 9. E-posta ve SMS tasarımı
- E-posta: yalın tek sütun, koyu mod uyumlu, metin sürümü, logo+sipariş özeti+takip bağlantısı+iletişim. SPF/DKIM/DMARC zorunlu. Sipariş e-postası "işlemsel", pazarlama ayrı alan adı/akışı.
- SMS: gönderici başlığı (alfanumerik başlık) onayı (operatör/SMS sağlayıcı sürecinde zaman alır), türkçe karakter (UCS-2 → 70 karakter parça) maliyetine dikkat; ASCII'ye yakın yazım opsiyonu.

## 10. Tasarım teslim süreci
1. Marka seansı: 3 yön moodboard → seçim.
2. Wireframe (düşük detay): ana sayfa, ürün, sepet/ödeme, Değirmen sihirbazı, durum sayfası, admin liste/detay, şoför ekranı.
3. Yüksek doğrulukta tasarım (Figma): mobil önce; bileşen kitaplığı.
4. Kullanıcı testi: 5 çiftçi + 5 alıcı ile prototip (telefon başı), bulgular backlog'a.
5. Tasarım→kod: tokens JSON → CSS değişkenleri, Storybook onayı.

