# 08 — Güvenlik ve Yasal

> Yasal içerikler **bilgilendirme amaçlı kontrol listesidir; avukat ve mali müşavir onayı olmadan yayınlanmaz.** Mevzuat güncel metinlerden doğrulanacaktır.

## 1. Tehdit modeli (STRIDE özet)
| Varlık | Tehdit | Önlem |
|---|---|---|
| Müşteri hesapları/OTP | SMS bombalama, OTP kaba kuvvet, hesap ele geçirme | telefon+IP hız sınırı, deneme limiti, CAPTCHA (Turnstile) eşik üstünde, OTP tek kullanım |
| Admin paneli | Kimlik bilgisi doldurma, oturum çalma | 2FA zorunlu, `admin.` alan adı + Cloudflare Access/IP kısıtı, kısa oturum, `SameSite=Strict` |
| Sipariş/ödeme | Fiyat manipülasyonu, webhook sahteciliği, çift harcama | sunucu fiyatı, imza + sorgu doğrulama, idempotensi, DB kısıtları |
| Stok | Yarış koşulu, rezerv istismarı (stok kilitleme) | atomik güncelleme, rezerv süresi, kişi başı eşzamanlı rezerv limiti, bot koruma |
| Kupon | Kaba kuvvet tahmin | hız sınırı, uzun rastgele kodlar, kullanım limiti |
| Medya yükleme | Zararlı dosya, SVG/XSS, yol geçişi | tür+magic byte, yeniden kodlama (sharp), rastgele depolama adı, ayrı alan adı/başlık |
| Veritabanı | SQL enjeksiyonu, sızıntı | parametreli sorgu, en az yetkili DB kullanıcısı, ağ izolasyonu, yedek şifreleme |
| Şoför cihazı | Cihaz kaybı | PIN, oturum iptali, minimum veri, uzaktan çıkış |
| Gizli bilgiler | Depoda sızıntı | gitleaks, `sops`, anahtar döndürme |
| Tedarik zinciri | Zararlı paket | kilit dosyası, `npm audit`, Renovate, imaj tarama, minimal imaj |
| DDoS/Bot | Kazıma, yük | Cloudflare, hız sınırı, önbellek |
| İç tehdit | Personel kötüye kullanımı | rol/izin, `audit_log`, iade/fiyat onay eşiği |

## 2. OWASP ASVS / Top 10 kontrol eşlemesi
- **A01 Erişim kontrolü:** her uçta izin kontrolü (varsayılan red), satır düzeyi (şoför/müşteri yalnız kendi verisi), IDOR testleri otomatik.
- **A02 Kriptografi:** TLS her yerde, argon2id, hassas sütunlarda (TOTP sırrı) uygulama düzeyi şifreleme, yedek şifreleme.
- **A03 Enjeksiyon:** ORM/parametreli; ham SQL'de yalnız bağlı parametreler; çıktı kaçışı (React varsayılan), `dangerouslySetInnerHTML` yasak (içerik modülü için sanitize ile).
- **A04 Güvensiz tasarım:** tehdit modeli, durum makineleri, sınırlar.
- **A05 Yanlış yapılandırma:** sertleştirme listesi, başlıklar, gereksiz portlar kapalı.
- **A06 Eski bileşen:** otomatik tarama + haftalık güncelleme penceresi.
- **A07 Kimlik hataları:** OTP/2FA/oturum rotasyonu, kilitlenme, parola politikası (personel).
- **A08 Bütünlük:** imza doğrulama (webhook), imzalı imaj/etiket, CI korumalı dallar.
- **A09 Günlük/izleme:** audit, uyarı, PII maskeleme.
- **A10 SSRF:** sunucudan dışa istek yalnız izinli sağlayıcılar; kullanıcı URL'i çekilmez.

## 3. Uygulama güvenliği kuralları
- Girdi doğrulaması: `zod` şemaları, uzunluk/biçim/aralık; telefon E.164; adres alanları sınırlı.
- Çıktı: JSON başlıkları doğru; `X-Content-Type-Options: nosniff`.
- CSP: ödeme sağlayıcı, Turnstile, analitik alan adı izin listesi; `unsafe-inline` yok (nonce).
- Hata mesajları: kullanıcıya genel, günlükte ayrıntı; enumeration önleme (OTP yanıtı kayıtlı/değil aynı).
- Rate limit + tarpit; hesap kilidi yerine artan gecikme (DoS'a karşı).
- Dosya yükleme: antivirüs taraması opsiyonel (`clamav` RAM maliyeti — gazi belgeleri için gerekirse yönetici elle inceler).
- Gizlilik varsayılanları: gereksiz alan toplamama (veri minimizasyonu).
- Bağımlılık politikası: yeni paket eklerken lisans+bakım+indirme kontrolü.
- Güvenlik testi: SAST (CodeQL/semgrep), DAST (ZAP baseline), yayın öncesi manuel kontrol listesi, bağımsız küçük sızma testi (canlıya çıkmadan önce).

## 4. KVKK (6698) kontrol listesi
| Madde | Yapılacak |
|---|---|
| Veri envanteri | Hangi veri, neden, nerede, ne kadar süre (03 §7) |
| Aydınlatma metni | Mağaza ve Değirmen için ayrı; toplama anında göster/onay kaydı |
| Açık rıza | Yalnız zorunlu olmayan işlemler (pazarlama, konum); aydınlatmadan ayrı |
| Ticari elektronik ileti | **İYS** kaydı/izin, onay kanıtı, çıkış (iptal) yolu; yalnız işlemsel mesajlar izinsiz |
| Çerez | Zorunlu olmayanlar için tercih bandı; analitik izinle |
| VERBİS | Kayıt yükümlülüğü eşiği ve istisnalar **hukuk/mali müşavirle doğrulanır** |
| Veri sorumlusu iletişim | Başvuru formu/e-posta, 30 gün yanıt süreci, panelde dışa aktarım/silme/anonimleştirme |
| Yurt dışı aktarım | Bulut/SMS/e-posta/Cloudflare/Sentry sağlayıcıları için aktarım mevzuatı değerlendirmesi |
| Güvenlik tedbirleri | Bu belge §1–3; ihlal bildirimi prosedürü (72 saat) |
| Özel nitelikli veri | Gazi/şehit belgesi: gerekçe, asgari saklama, sınırlı erişim; **kaçınma seçeneği:** belge yerine derneğin onay SMS'i/numarası |
| Kayıt tutma | `consent_log`, işleme kayıtları |

## 5. E-ticaret ve tüketici mevzuatı (kontrol listesi)
- **6563 sayılı Elektronik Ticaretin Düzenlenmesi Hakkında Kanun / ilgili yönetmelikler:** hizmet sağlayıcı bilgileri, ticari ileti kuralları, ETBİS kaydı yükümlülüğü ve istisnaları (doğrulanacak).
- **6502 sayılı Tüketicinin Korunması Hakkında Kanun + Mesafeli Sözleşmeler Yönetmeliği:** ön bilgilendirme formu, mesafeli satış sözleşmesi, onay (sipariş öncesi açıkça), cayma hakkı bilgisi, **istisnalar (çabuk bozulabilen/son kullanma tarihi geçebilecek ürünler vb.)**, teslimat süresi (30 gün üst sınır), ödeme bilgilendirmesi, "Sipariş ver ve ödeme yap" buton ifadesi.
- Fiyat: KDV dahil, kargo ayrı gösterim, kampanya fiyatı yanıltıcı olmamalı (üstü çizili fiyat kuralı).
- Müşteri hizmetleri iletişim bilgileri görünür; şikâyet/hakem heyeti bilgisi (parasal sınırlar güncel kontrol).
- Sipariş onayı ve sözleşme kopyası kalıcı ortamda (e-posta) müşteriye iletilir; sözleşme sürümü sipariş kaydında saklanır (`consent_snapshot`).
- Üyelik koşulları (hesap açanlar için), kullanım koşulları.

## 6. Gıda mevzuatı kontrol listesi
- Türk Gıda Kodeksi **etiketleme**: ürün adı, içindekiler (azalan sırayla), alerjenler (vurgulu), net miktar, son tüketim/azami tüketim tarihi, parti no, üretici/paketleyici adres, saklama koşulu, menşei, besin değeri (zorunluysa).
- Web mağazasında etiket bilgisi **satın alma öncesi** gösterilir (içindekiler, alerjen, SKT bilgisi).
- İşletme: gıda işletme kaydı/onayı (İl Tarım ve Orman Müdürlüğü), üretim/paketleme için gereken izinler, mağaza satışı için uygun belge. **Etiketlerdeki "katkısız", "%100 doğal" gibi beyanlar kanıtlanabilir olmalı** (yanıltıcı beyan riski).
- Besin değerleri laboratuvar analizine dayanmalı; mevcut sitedeki değerler doğrulanmadı.
- Sağlık beyanı kullanımı: "bağışıklığı güçlendirir" gibi ifadeler yasaktır; kopya yazarken kontrol.
- Soğuk zincir gerekmiyor (kuru ürün) ama ezme için saklama/açıldıktan sonra tüketim süresi.

## 7. Değirmen hizmeti için yasal
- Hizmet koşulları (fire, randıman, sorumluluk, kalite tespiti, ödeme, iptal, gecikme).
- Tartı güvenilirliği: **ölçü ve ayar damgalı/yasal metrolojiye uygun terazi** kullanımı ve periyodik muayene (yerel yönetim/metroloji) — müşteri ile ticari tartı yapılıyorsa şart olabilir; doğrulanacak.
- Çiftçi faturalandırma/stopaj durumu (mali müşavir).
- Şoför: sürücü belgesi, araç sigorta/ruhsat, ticari taşıma kapsamı, iş kazası/İSG, personel sözleşmesi, konum izleme için çalışan aydınlatması (KVKK + iş hukuku).
- Müşteri malının sigortalanması (hasar/hırsızlık) araştırması.

## 8. Olay müdahale planı (IR)
1. Tespit (uyarı/şikâyet) → 2. Sınırlama (oturum iptali, anahtar döndürme, bakım modu) → 3. Kök neden → 4. Giderme → 5. Bildirim (KVKK kurulu/kişiler gerekiyorsa süre içinde) → 6. Ders çıkarma.
Rol ve iletişim listesi (kim, ne zaman, kime) hazırlanır; yılda bir tatbikat.

## 9. Erişim ve hesap yönetimi
- Her hesapta 2FA (alan adı, VPS, Cloudflare, GitHub, ödeme sağlayıcı paneli, SMS paneli, e-posta).
- Parola yöneticisi + acil durum erişim kasası (ikinci kişi/yedek kodlar).
- Personel girişi/çıkışı süreci: hesap aç/kapat, anahtar iptali.
- Çalışanlara "en az yetki": paketleme personeli ödeme/iade göremez.

## 10. Hukuki belge listesi (yayın öncesi hazır olacak)
Gizlilik/KVKK aydınlatma · Çerez politikası · Mesafeli satış sözleşmesi · Ön bilgilendirme formu · Teslimat ve iade politikası · Üyelik/kullanım koşulları · Değirmen hizmet koşulları · Pazarlama izin metni (İYS) · Gazi/şehit indirim koşulları · İletişim/şirket bilgileri sayfası (unvan, MERSİS/vergi no, adres, e-posta, KEP).

