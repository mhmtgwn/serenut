# 11 — Hazırlık Listesi ve Açık Kararlar

## A. VPS ve domain öncesi yapılacak hazırlıklar (kurulum yok, hepsi evrak/hesap/karar)

### A1. Hesaplar (Nutopia'ya özel, Serenut'tan ayrı)
| # | İş | Not | Sahip |
|---|---|---|---|
| 1 | Alan adı satın alma/transfer + 2FA + kayıt kilidi | `nutopiano.com` mevcutsa kayıt hesabının kimde olduğunu doğrula | Kullanıcı |
| 2 | Cloudflare hesabı (Nutopia'ya ayrı) | ücretsiz plan başlangıç | Kullanıcı |
| 3 | VPS sağlayıcısı seçimi ve hesap | §B S-03 | Kullanıcı |
| 4 | GitHub organizasyonu/repo `nutopia-platform` (özel) | Serenut'tan ayrı hesap/kuruluş | Kullanıcı |
| 5 | Dış yedek depolama hesabı (farklı sağlayıcı) | B2/Storage Box | Kullanıcı |
| 6 | Sentry (ücretsiz) projesi | | Ben/Kullanıcı |
| 7 | Parola yöneticisi kasası (Nutopia) + acil erişim kodları | | Kullanıcı |
| 8 | İş e-posta adresleri (`siparis@`, `destek@`, `no-reply@`, `kvkk@`) | e-posta sağlayıcı (Workspace/Zoho/…) | Kullanıcı |

### A2. Ticari başvurular (uzun sürenler ÖNCE)
| # | İş | Süre riski |
|---|---|---|
| 9 | **iyzico** (ve yedek PayTR) başvurusu: vergi levhası, imza sirküleri, banka hesabı, web sitesi/alan adı vb. | Yüksek |
| 10 | **SMS sağlayıcısı** hesap + gönderici başlığı onayı + OTP için uygunluk | Orta |
| 11 | **Kargo firması** anlaşması (kurumsal müşteri, kapıda ödeme opsiyonu) | Orta |
| 12 | **e-Arşiv/e-Fatura** için mali müşavir ile süreç (özel entegratör mü, GİB portalı mı) | Orta |
| 13 | **Gıda işletme kaydı/izinleri** kontrolü (İl Tarım ve Orman Müdürlüğü) ve etiket/analiz | Yüksek |
| 14 | **ETBİS**, **İYS**, **VERBİS** yükümlülük kontrolü (avukat/mali müşavir) | Orta |
| 15 | Ticari tartı: damgalı terazi ve muayene durumu | Orta |
| 16 | Şoför/araç: ruhsat, sigorta, taşıma kapsamı, İSG | Orta |
| 17 | Google İşletme Profili doğrulama, Merchant hesabı | Düşük |

### A3. İçerik hazırlığı
| # | İş |
|---|---|
| 18 | Ürün listesi tablosu: ad, varyant, SKU, barkod, fiyat, KDV oranı, ağırlık, içindekiler, alerjen, besin analizi (lab belgesi), raf ömrü, saklama |
| 19 | Fotoğraf çekimi (09 §8 listesi) |
| 20 | Fiyat politikası: Mağaza + Değirmen birim fiyatlar, alım ücreti, kapsama listesi (mahalle bazlı) |
| 21 | Hizmet ve satış koşulları taslakları (avukat) |
| 22 | SSS içeriği, hakkımızda metni, marka hikâyesi |
| 23 | SMS/e-posta şablon metinleri (Türkçe, kısa) |
| 24 | Operasyon prosedürü: lot ayırma, ikinci tartı, kalite tespiti, fire kuralı |

### A4. Teknik hazırlık (VPS gelmeden, bilgisayarda)
| # | İş |
|---|---|
| 25 | Yeni repo ve proje iskeleti planı onayı (Aşama 0.1) |
| 26 | Yerel geliştirme ortamı: Node 22, pnpm, Docker Desktop |
| 27 | `tr_geo` (il/ilçe/mahalle) açık veri kaynağının bulunması ve lisans kontrolü |
| 28 | Harita/adres: pin için harita sağlayıcı (OpenStreetMap + Leaflet/MapLibre, ücretsiz) vs Google Maps (ücretli) kararı |
| 29 | Eski sitedeki URL/içerik envanteri → 301 haritası taslağı |
| 30 | Serenut ayırma kontrol listesi (07 §11) için mevcut hesap/anahtar envanteri |

## B. Açık kararlar (öneriyle birlikte)
| ID | Soru | Öneri | Etki |
|---|---|---|---|
| S-01 | Teknoloji: NestJS+Next.js+Postgres | **Evet** (D-02) | tüm kod |
| S-02 | Tek repo/ayrı repo | Ayrı repo `nutopia-platform` | süreç |
| S-03 | VPS sağlayıcı/konum | Türkiye veya AB; 4 GB/2 vCPU; snapshot, TL fatura | maliyet/KVKK |
| S-04 | Değirmen ayrı alan adı olacak mı | Şimdilik `/degirmen`; ileride alt alan adı/ayrı alan adı | URL planı |
| S-05 | Müşteri hesabı | Mağazada misafir+isteğe bağlı, Değirmen'de SMS ile | UX |
| S-06 | Marka/tasarım | Yeni görsel dil, logo mevcut kalabilir mi? Logo ve renk bağlayıcı mı? | tasarım |
| S-07 | Gazi/şehit yakını indirimi doğrulaması | Belge yükleme + yönetici onayı + hesapta geçerlilik; onaysızsa indirim yok | akış/KVKK |
| S-08 | Ürün sayısı ve varyant yapısı | Şimdilik 7 ürün, her birinde 2 gramaj; büyüyebilir | veri |
| S-09 | Taksit sunulacak mı | Peşin ile başla | ödeme |
| S-10 | Kapıda ödeme | Açık, ek ücret + sınırlar | ödeme |
| S-11 | Ücretsiz kargo eşiği ve kargo ücret tablosu | 750 ₺; 750 ₺ altı için ücret tablosu kargo anlaşmasından | iş kuralı |
| S-12 | Kargo firması | Anlaşmaya göre; MVP'de tek firma | entegrasyon |
| S-13 | Fatura/muhasebe programı | CSV dışa aktarım ile başla, entegratör sonra | v1.1 |
| S-14 | Şoför sayısı/araç/kapsama bölgesi | Başlangıç 1 şoför, 1 araç; ilçe listesini belirle | planlama |
| S-15 | Değirmen fiyatı kimin adına/nasıl faturalanır | Mali müşavire danışılacak | hukuk/vergi |
| S-16 | Alım randevusu: gün/saat bloğu veya "gün içi" | Gün + 2 zaman dilimi (sabah/öğleden sonra) | kapasite |
| S-17 | Müşteri malı sigortası | Araştır | risk |
| S-18 | SMS sağlayıcı | Netgsm/İleti Merkezi vb. karşılaştır | maliyet |
| S-19 | E-posta sağlayıcı (gönderim) | Brevo/Mailgun/SES vb.; teslim edilebilirlik testi | teslimat |
| S-20 | Personel sayısı ve roller | owner + 1 paketleme + 1 şoför + 1 destek? | yetki |
| S-21 | Yorum/puan sistemi (MVP dışı) | Sonra | kapsam |
| S-22 | Analitik | Umami/Plausible (çerezsiz) | KVKK |
| S-23 | Yedek hedefi ve saklama süresi | B2 + 14 gün / 8 hafta / 12 ay | maliyet |
| S-24 | Değirmene gelen müşteri randevusu (kurye yok) | Basit randevu formu v1.1 | kapsam |
| S-25 | "Ürünü değirmen hizmetiyle birlikte sipariş" (tek sepet) | v2 | kapsam |
| S-26 | Birden fazla dil (EN/AR) | Hayır (başlangıç) | kapsam |

## C. Sabaha kadar planlama gündemi (sıra önerisi)
1. S-03, S-04, S-06, S-07, S-11, S-14 kararlarını netleştirelim (tek tek soru-cevap).
2. Ürün tablosunu birlikte dolduralım (A3-18) — `data.js` verisinden başlangıç taslağı çıkarırım.
3. Değirmen iş kurallarını örnek senaryolarla sınayalım (05 §9): sayısal örnekler, ücret hesabı tablosu.
4. Ekran taslakları: ana sayfa, ürün, ödeme, talep sihirbazı, şoför ekranı, admin (düşük detaylı wireframe belgeleri/mermaid).
5. API sözleşmesi taslağı (OpenAPI iskeleti) ve DB DDL taslağı (dbmate SQL şeması) — **dosya olarak**, kurulum olmadan.
6. SMS/e-posta şablon metinleri ve hukuki belge iskeletleri (avukata verilecek taslak).
7. Test senaryoları listesi (kabul kriterleri Gherkin).
8. VPS/Domain kurulum **runbook'u**: komut komut hazır yazılsın, VPS gelince uygulayalım.

## D. Bir sonraki adımda üretilecek belgeler (öneri)
| Belge | İçerik |
|---|---|
| `12-ekran-taslaklari.md` | Her sayfa için bölümler, alanlar, durumlar, boş/hata hâlleri |
| `13-api-taslagi.md` | Uç nokta tabloları, istek/yanıt örnekleri, hata kodları |
| `14-sql-sema.md` | Kanonik DDL ve SQL şeması (dbmate) |
| `15-kabul-kriterleri.md` | Özellik başına Gherkin senaryoları |
| `16-sablonlar.md` | SMS/e-posta/yasal metin iskeletleri |
| `17-runbook-vps-kurulum.md` | Sunucu kurulum ve dağıtım adımları (komutlar) |
| `18-urun-icerik-tablosu.md` | Ürün/varyant/besin/alerjen başlangıç tablosu |

