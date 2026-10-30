# Nutopia Platform — Planlama Paketi

> Durum: **PLAN AŞAMASI — kurulum yok.** Bu paket, VPS ve domain hazır olduğunda doğrudan uygulamaya geçilecek şekilde yazılmıştır.
> Son güncelleme: 2026-10-30

## Amaç
Nutopia Fındık Değirmeni için kendi e-ticaret platformu:
1. **Mağaza (Nutopiano):** ürün satışı, sepet, ödeme, sipariş, kargo.
2. **Değirmen & Kurye:** çiftçiden bahçeden fındık alma, tartı, işleme (kırma/kavurma/ezme), geri teslim, ücretlendirme. Amaç değirmene müşteri çekmek.
3. **Yönetim:** ürün yükleme, sipariş, talep, kurye/şoför, raporlar.

İleride Mağaza ile Değirmen ayrı alan adı ve/veya servis olarak bölünebilir.

## Temel ilkeler
| # | İlke |
|---|---|
| 1 | **Serenut'tan tamamen ayrı:** ayrı repo, ayrı VPS, ayrı veritabanı, ayrı hesaplar, ayrı sırlar. Hiçbir ortak runtime bağımlılığı yok. |
| 2 | **Modüler monolit:** tek dağıtım, sert modül sınırları. Bölme gerekirse hazır. |
| 3 | **Önce doğruluk:** para, stok, ağırlık hesabı sunucuda, kuruş/gram tam sayı, testli. |
| 4 | **Sıkıcı teknoloji:** TypeScript, PostgreSQL, Docker, Nginx. Bilinen ve bakımı kolay. |
| 5 | **Eski siteye bağlı değil:** tasarım ve kod sıfırdan. Eski site yalnızca içerik/fiyat kaynağı ve 301 yönlendirme haritası. |
| 6 | **Her aşama yayınlanabilir:** dikey dilimlerle ilerlenir. |

## Belge dizini
| Dosya | İçerik |
|---|---|
| [01-urun-kapsam.md](01-urun-kapsam.md) | Personalar, kullanıcı hikâyeleri, MVP/sonrası, iş kuralları |
| [02-mimari.md](02-mimari.md) | Teknoloji kararları (ADR), repo yapısı, modüller, API, kimlik, işler |
| [03-veri-modeli.md](03-veri-modeli.md) | Tablo tablo veri modeli, kısıtlar, indeksler |
| [04-magaza.md](04-magaza.md) | Katalog, sepet, ödeme akışı, sipariş durumları, stok, kupon, kargo, iade |
| [05-degirmen-kurye.md](05-degirmen-kurye.md) | Talep → alım → tartı → işleme → teslim, ücret, şoför uygulaması |
| [06-odeme-finans.md](06-odeme-finans.md) | iyzico/PayTR, webhook, iade, mutabakat, fatura |
| [07-altyapi.md](07-altyapi.md) | VPS, domain/DNS, Docker, Nginx, yedek, izleme, CI/CD, geçiş planı |
| [08-guvenlik-yasal.md](08-guvenlik-yasal.md) | Tehdit modeli, sertleştirme, KVKK ve mevzuat kontrol listesi |
| [09-ux-seo.md](09-ux-seo.md) | Bilgi mimarisi, sayfalar, tasarım sistemi ilkeleri, SEO, erişilebilirlik |
| [10-yol-haritasi-test.md](10-yol-haritasi-test.md) | İş kırılımı, süre, tamamlanma ölçütü, test, risk |
| [11-hazirlik-ve-sorular.md](11-hazirlik-ve-sorular.md) | VPS/domain öncesi hazırlık listesi ve açık kararlar |

## Karar günlüğü (özet)
| ID | Karar | Durum |
|---|---|---|
| D-01 | Modüler monolit, TypeScript | Karar |
| D-02 | NestJS (Fastify) API + Next.js vitrin + ayrı admin SPA | Öneri (onay bekler) |
| D-03 | PostgreSQL 17, düz SQL (dbmate) göçleri, Kysely sorgu katmanı | **Karar (K2, K3, K4)** |
| D-04 | Kuyruk: `pg-boss` (Redis yok) | Öneri |
| D-05 | Ödeme: iyzico birincil, PayTR sağlayıcı arayüzü ile yedek | Öneri |
| D-06 | Nutopiano ve Serenut ayrı VPS | **Karar (kullanıcı)** |
| D-07 | Kurye: kendi şoför/araç, sistem talep+rota+tartı yönetir | **Karar (kullanıcı)** |
| D-08 | Ayrı repo `nutopia-platform` | Öneri |
| D-09 | Cloudflare önde (WAF/CDN), origin kilitli | Öneri |
| D-10 | Bildirim: SMS birincil, e-posta ikincil, WhatsApp yalnız resmi API ile | Öneri |
| D-11 | Mağaza: misafir alışveriş + isteğe bağlı hesap; Değirmen: SMS ile giriş | Varsayım |

## Sözlük
- **Kuruş (minor unit):** tüm para tutarları `integer` kuruş.
- **Gram:** tüm ağırlıklar `integer` gram.
- **Talep (mill request):** çiftçinin değirmen hizmeti isteği.
- **Alım (pickup):** şoförün bahçeden fındığı almak için yaptığı ziyaret.
- **Parti / lot:** tartılıp işlenen tek müşteri fındığı kümesi; izlenebilirlik birimi.
- **Randıman:** kabuklu fındıktan çıkan iç fındık oranı.

