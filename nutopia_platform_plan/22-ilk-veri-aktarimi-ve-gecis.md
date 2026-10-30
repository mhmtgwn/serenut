# 22 — İlk İçe Aktarım, Tohumlama ve Geçiş Planı (Data Migration & 301)

> Bu belge, mevcut statik siteden (`nutopiano_website`) yeni platforma aktarılacak katalog verilerinin dönüşüm kurallarını, ilk veritabanı tohumlama (seed) verilerini ve SEO gücünü korumak için zorunlu olan eski URL -> yeni URL 301 yönlendirme haritasını içerir.

---

## 1. ESKİ STATİK VERİ DÖNÜŞÜM KURALLARI (`data.js` -> `14-sql-sema.md`)

Mevcut `data.js` dosyasındaki ürün ve hizmet verileri, yeni SQL tablolarına aktarılırken aşağıdaki veri dönüşüm kurallarına (Transformation Rules) tabi tutulacaktır:

| Eski Veri Alanı | Eski Biçim | Hedef SQL Tablosu & Sütun | Dönüşüm Kuralı |
|---|---|---|---|
| Ürün Fiyatı | `165` (Number) | `shop.variants.price_kurus` | `price * 100` (`16500` kuruş - `bigint`) |
| Kategori | `'ezme'`, `'kavurma'`, `'ic'` | `shop.categories.slug` | `ezme` -> `ezme-krema`, `kavurma` -> `kavrulmus-krokan`, `ic` -> `cig-kabuklu` |
| Değirmen Fiyatı | `40` (Number) | `mill.pricing_rules.unit_price_kurus` | `price * 100` (`4000` kuruş / kg) |
| Ağırlık / Boyut | `'300 g kavanoz'` (Text) | `shop.variants.net_content_g` | Regex ile `\d+` ayıklanıp tam sayı grama çevrilir (`300`) |
| Alerjenler | Serbest metin | `shop.products.allergens` & `allergen_tags` | Düz metin saklanır + etiket dizisi `{'findik','laktoz'}` üretilir |
| Besin Analizi | `{ kcal: 542, ... }` | `shop.products.nutrition` | Standart JSONB formatı (`100g` standardında) |
| Telefon Numarası | `'0538 028 82 02'` | `core.customers.phone` | `+905380288202` (E.164 uluslararası format) |

---

## 2. İLK TOHUMLAMA (SEED) SQL DOSYASI (`seed_catalog.sql`)

Aşama 0 kurulumunda `dbmate up` tamamlandıktan sonra çalıştırılacak başlangıç iş verisi tohumlama komutları:

```sql
-- 1. Kategoriler
INSERT INTO shop.categories (id, slug, name, description, sort) VALUES
  ('0192d4f8-0001-7000-8000-000000000001', 'ezme-krema', 'Ezme & Krema', 'Taş değirmen çekimi katkısız fındık ezmeleri ve gurme kahvaltılık kremalar.', 1),
  ('0192d4f8-0001-7000-8000-000000000002', 'kavrulmus-krokan', 'Kavrulmuş & Krokan', 'Fırınlanmış çıtır çifte kavrulmuş fındık ve karamelize krokanlar.', 2),
  ('0192d4f8-0001-7000-8000-000000000003', 'cig-kabuklu', 'Çiğ & Kabuklu Fındık', 'Dalından yeni toplanmış, kurutulmuş ve seçilmiş doğal Karadeniz mahsulü.', 3)
ON CONFLICT (slug) DO NOTHING;

-- 2. Değirmen Hizmetleri
INSERT INTO mill.services (code, name, description, step_order) VALUES
  ('kirma', 'Fındık Kırma', 'Kabuklu fındığı kırma makinesinde sağlam iç fındığa ayırır.', 1),
  ('kavurma', 'Fırın Kavurma', 'Kontrollü sıcaklıkta homojen kavurma işlemi.', 2),
  ('zar_soyma', 'Zar Soyma', 'Kavrulmuş fındığın acı dış zarını temizler.', 3),
  ('ezme', 'Taş Değirmende Ezme', 'Soğuk öğütmeyle saf ve ipeksi fındık ezmesi elde edilir.', 4),
  ('paket_vakum', 'Vakumlu Paketleme', 'Hava almaz paketlerde uzun aylar süren tazelik garantisi.', 5)
ON CONFLICT (code) DO NOTHING;

-- 3. Değirmen Başlangıç Fiyat Tarifeleri (Kuruş/kg)
INSERT INTO mill.pricing_rules (service_codes, package_code, package_name, basis, unit_price_kurus, valid_from) VALUES
  ('{"kirma"}', 'kirma', 'Yalnızca Kırma', 'input_kg', 4000, '2026-01-01'),
  ('{"kavurma"}', 'kavurma', 'Yalnızca Kavurma', 'input_kg', 7000, '2026-01-01'),
  ('{"kirma","kavurma"}', 'kirma-kavurma', 'Kırma + Kavurma', 'input_kg', 6500, '2026-01-01'),
  ('{"kirma","kavurma","paket_vakum"}', 'kk-1kg', 'Kırma + Kavurma + 1 kg Vakum', 'input_kg', 7000, '2026-01-01'),
  ('{"kirma","kavurma","paket_vakum"}', 'kk-500', 'Kırma + Kavurma + 500 g Vakum', 'input_kg', 8000, '2026-01-01'),
  ('{"kirma","kavurma","paket_vakum"}', 'kk-250', 'Kırma + Kavurma + 250 g Vakum', 'input_kg', 9000, '2026-01-01'),
  ('{"kavurma","ezme"}', 'ezme', 'Kavurma + Taş Değirmende Ezme', 'input_kg', 13000, '2026-01-01')
ON CONFLICT DO NOTHING;

-- 4. Kapsama Alanları (Kdz. Ereğli & Ormanlı Çevresi Başlangıç)
INSERT INTO mill.coverage (city_code, district_code, neighborhood_code, pickup_fee_kurus, min_kg, is_active) VALUES
  ('67', 'KDZ_EREGLI', 'ORMANLI', 0, 50, true),
  ('67', 'KDZ_EREGLI', 'MERKEZ', 15000, 100, true),
  ('67', 'ALAPLI', NULL, 20000, 150, true)
ON CONFLICT DO NOTHING;
```

---

## 3. SEO GÜCÜNÜ KORUMA: 301 KALICI YÖNLENDİRME HARİTASI

Mevcut sitenin Google ve diğer arama motorlarındaki organik indeksini, geri bağlantılarını (backlink) ve kullanıcı yer imlerini kaybetmemek için Nginx seviyesinde zorunlu tutulacak `301 Moved Permanently` eşleştirme tablosu:

| Eski URL / Yol | Yeni Platform Karşılığı | HTTP Kodu | Gerekçe / SEO Notu |
|---|---|---|---|
| `/index.html` | `/` | 301 | Ana sayfa standartlaştırma (Canonical) |
| `/urunler.html` | `/urunler` | 301 | Ürün ana listeleme |
| `/degirmen.html` | `/degirmen` | 301 | Değirmen hizmet tanıtımı ve hesaplayıcı |
| `/hakkimizda.html` | `/hakkimizda` | 301 | Kurumsal hikaye ve tesis sayfası |
| `/iletisim.html` | `/iletisim` | 301 | İletişim, harita ve yol tarifi sayfası |
| `/images/urun-sutlu.png` | `/media/products/sutlu-kremasi.webp` | 301 | Görsel indeksinin yeni optimize WebP'ye aktarımı |
| `/images/urun-kakaolu.png`| `/media/products/kakaolu-kremasi.webp` | 301 | Görsel indeks aktarımı |
| `/images/urun-ezme.png` | `/media/products/100-findik-ezmesi.webp` | 301 | Görsel indeks aktarımı |
| `/images/urun-kavrulmus.png` | `/media/products/kavrulmus-findik.webp` | 301 | Görsel indeks aktarımı |
| `/images/findik-kase-doga.png` | `/media/products/cig-ic-findik.webp` | 301 | Görsel indeks aktarımı |
| `/images/nutopia-onluk.png` | `/media/products/kabuklu-findik.webp` | 301 | Görsel indeks aktarımı |

### 3.1 Nginx 301 Yapılandırma Bloğu (`/etc/nginx/conf.d/redirects.conf`)
```nginx
# Eski .html uzantılarını temiz URL'lere kalıcı yönlendir
location = /index.html { return 301 /; }
location = /urunler.html { return 301 /urunler; }
location = /degirmen.html { return 301 /degirmen; }
location = /hakkimizda.html { return 301 /hakkimizda; }
location = /iletisim.html { return 301 /iletisim; }

# Bilinmeyen eski görseller için koruyucu kural
location ~ ^/images/(.*)\.png$ {
    try_files /media/products/$1.webp /media/$1.png @fallback_images;
}
location @fallback_images {
    return 301 /;
}
```

---

## 4. CANLI GEÇİŞ GÜNÜ (SWITCH-OVER) KONTROL VE ADIM SIRASI

1. **T - 48 Saat:** Cloudflare DNS üzerinde `nutopiano.com` TTL süresi `300` saniyeye (5 dakika) indirilir.
2. **T - 2 Saat:** Eski statik site Nginx'te dondurulur, tüm form istekleri bakım moduna alınır.
3. **T - 1 Saat:** Yeni VPS üzerinde `dbmate up` çalıştırılır ve `seed_catalog.sql` ile tüm ürün kataloğu içeri alınır.
4. **T - 15 Dakika:** Canlı iyzico anahtarları ve SMS sağlayıcı bilgileri `.env` dosyasına girilip API ve Web konteynerleri ayağa kaldırılır.
5. **T - 0 (Geçiş Anı):** Cloudflare DNS A kaydı, yeni Nutopiano VPS IP'sine yönlendirilir.
6. **T + 10 Dakika:** `curl -I https://nutopiano.com` ve `https://nutopiano.com/urunler.html` test edilerek 301 yönlendirmelerinin çalıştığı doğrulanır.
7. **T + 30 Dakika:** Gerçek kredi kartı ile 165 TL'lik canlı bir test siparişi verilir; SMS onayı, sipariş ekranı ve ardından yönetim panelinden tam iade (refund) testi yapılarak geçiş tamamlanır.

