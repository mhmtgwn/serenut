# 10 — Yol Haritası, İş Kırılımı, Test, Risk

> Süreler tek geliştirici + yapay zekâ destekli çalışma varsayımıyla kaba tahmindir; Aşama 0 sonunda gözden geçirilir. Gün = verimli gün.

## 1. Aşamalar ve çıktılar
| Aşama | Süre | Çıktı (demo edilebilir) | Çıkış ölçütü |
|---|---|---|---|
| **0 Temel** | 4–5 g | Repo, CI/CD, Docker, boş uygulama iskeleti, DB göç, kimlik iskeleti, staging yayında | Staging'e otomatik dağıtım; sağlık uçları yeşil |
| **1 Katalog + Admin çekirdeği** | 6–8 g | Personel girişi (2FA), ürün/varyant/medya/stok yönetimi, kategoriler, ayarlar | Ürün yükle → API'de görünür; testler yeşil |
| **2 Vitrin** | 6–8 g | Ana sayfa, kategori, ürün, arama, SEO temel, içerik sayfaları | LCP hedefi, a11y temel geçer |
| **3 Sepet + Sipariş (havale/kapıda)** | 8–10 g | Sepet, ödeme sayfası, sipariş, stok rezerv, durumlar, bildirim, admin sipariş ekranları | Uçtan uca sipariş E2E testi |
| **4 Kart ödemesi** | 5–7 g | iyzico entegrasyonu, webhook, iade, mutabakat raporu | Ödeme test matrisi (06 §12) tamam |
| **5 Hesap + yasal sayfalar** | 4–5 g | Müşteri hesabı, KVKK/çerez/sözleşmeler (hukuki metinler hazırsa), İYS izinleri | Hukuk onayı |
| **6 Değirmen: talep + yönetim** | 8–10 g | Hesaplayıcı, talep sihirbazı, SMS OTP, onay, kapsama/fiyat yönetimi | Çiftçi talep açar, yönetici onaylar |
| **7 Değirmen: kurye + tartı** | 8–10 g | Planlama panosu, şoför PWA, tartı/onay kodu, tutanak, lot/iş, kesin ücret, teslim, tahsilat | Saha pilotu (gerçek 3–5 çiftçi) |
| **8 Kargo + fatura + raporlar** | 6–8 g | Kargo API/etiket, takip, e-Arşiv bağlantısı, raporlar, Merchant feed | |
| **9 Sertleştirme + yayın** | 5–7 g | Yük/güvenlik testi, yedek tatbikatı, geçiş, 301, izleme | Go-live kontrol listesi tamam |
Toplam ≈ 60–80 gün (≈ 12–16 hafta). **MVP'ye erken çıkış önerisi:** Aşama 0–5 sonrası Mağaza yayına; Değirmen Aşama 6–7 ile ikinci dalga (satış hemen başlar, çiftçi tarafı pilotla olgunlaşır).

## 2. Aşama 0 detay (WBS)
| ID | İş | Çıktı |
|---|---|---|
| 0.1 | Yeni repo, `pnpm`+Turborepo, TS, ESLint/Prettier, commit kuralları, PR şablonu, CODEOWNERS | iskelet |
| 0.2 | dbmate göç iskeleti ve Kysely kod üretimi kurulumu; Radix tabanlı admin tasarım bileşen çekirdeği | Kod iskeleti |
| 0.3 | `apps/api` iskelet: yapılandırma, sağlık, pino, hata filtresi, OpenAPI | çalışan API |
| 0.4 | PostgreSQL + göç altyapısı + seed | `docker compose up` ile yerel |
| 0.5 | `packages/money`: kuruş/KDV/yuvarlama + property testleri | %100 kapsama |
| 0.6 | `packages/contracts`: zod + OpenAPI istemci üretimi | otomatik tip |
| 0.7 | `apps/web` Next.js iskelet, `apps/admin` Vite iskelet | boş sayfalar |
| 0.8 | CI: lint, tip, test, derleme, güvenlik taramaları, imaj yayını | yeşil boru hattı |
| 0.9 | Staging dağıtım betiği, Nginx/TLS şablonu, sırlar süreci | staging adresi |
| 0.10 | `docs/` taşıma + ADR şablonu + katkı rehberi | |

## 3. Aşama bağımlılıkları ve paralel yürüyen işler
Kod yazımından bağımsız, **hemen başlayabilir**: iyzico/PayTR başvurusu, SMS başlık (gönderici adı) onayı, domain/e-posta, kargo anlaşması, hukuki metinler, ürün fotoğrafı çekimi, ürün içerik/etiket/analiz doğrulama, marka tasarımı, ETBİS/gıda belgeleri kontrolü. Kritik yol genelde **ödeme başvuru süresi + SMS başlık onayı + hukuki metinler**.

## 4. Tamamlanma tanımı (DoD) — her özellik için
1. Kod incelemesi onaylı, CI yeşil.
2. Birim + entegrasyon testi (iş kuralları, yetki, hata yolları).
3. API sözleşmesi güncel (OpenAPI), göç geri alma planı.
4. Erişilebilirlik ve mobil kontrol (UI işleri).
5. Günlük/metrik/uyarı eklendi (kritik akışlarda).
6. Güvenlik kontrol listesi: yetki, girdi doğrulama, hız sınırı.
7. Belge güncel: modül README, runbook, kullanıcı notu.
8. Staging'de kabul testi, ürün sahibi onayı.

## 5. Test stratejisi
| Katman | Araç | Kapsam |
|---|---|---|
| Birim | Vitest | para/KDV/kupon/ücret/durum makineleri/validasyon (hedef kapsam %90 kritik modüller) |
| Özellik (property) | fast-check | yuvarlama toplamı = toplam, iade ≤ ödeme |
| Entegrasyon | Vitest + gerçek PostgreSQL (Testcontainers) | modül servisleri, göç, stok yarışı, outbox |
| Sözleşme | OpenAPI doğrulama, `schemathesis` | API ↔ istemci uyumu |
| E2E | Playwright | sepet→ödeme (sandbox), talep→teslim, admin süreçleri, mobil görünüm |
| Yük | k6 | 100 eşzamanlı ödeme sayfası, katalog 500 rps, son stok yarışı |
| Güvenlik | semgrep/CodeQL, ZAP, bağımlılık/imaj tarama, IDOR otomasyonu | |
| Erişilebilirlik | axe CI + manuel | |
| Görsel regresyon | Storybook/Chromatic benzeri (opsiyonel) | |
| Saha pilotu | gerçek çiftçilerle | şoför uygulaması dış mekân, sinyal, eldiven |
- Test verisi: seed + fabrikalar; **gerçek kişisel veri testte yok.**
- Ödeme: sağlayıcı sandbox kartları; gerçek canlı test küçük tutarlı sipariş + iade (go-live günü).

## 6. Go-live kontrol listesi (özet)
- [ ] Hukuki metinler yayında ve onaylı; ETBİS/izinler tamam.
- [ ] Ürün etiket bilgileri/alerjen doğrulandı; fotoğraflar tamam.
- [ ] Canlı ödeme anahtarı; gerçek kart test + iade başarılı.
- [ ] SMS gönderici başlığı onaylı; şablonlar test edildi.
- [ ] E-posta SPF/DKIM/DMARC geçti; spam testi.
- [ ] Yedek çalıştı **ve geri yükleme provası yapıldı**.
- [ ] İzleme/uyarılar tetiklendi ve kanal doğrulandı.
- [ ] 301 haritası ve sitemap hazır; Search Console doğrulandı.
- [ ] Yük testi ve güvenlik taraması bulguları kapalı.
- [ ] Yönetici ve personel eğitimi tamam; kısa kullanım kılavuzu (video + PDF).
- [ ] Geri dönüş planı (DNS) yazılı ve prova edildi.
- [ ] Kargo/kapıda ödeme anlaşması aktif.
- [ ] Fatura süreci (muhasebe) netleşti.

## 7. Operasyon (yayın sonrası)
- Haftalık: bağımlılık güncelleme penceresi, hata/uyarı gözden geçirme, yedek raporu.
- Aylık: geri yükleme testi, maliyet/kapasite, SEO/performans raporu, güvenlik yaması.
- Çeyreklik: erişim gözden geçirme, tehdit modeli güncelleme, felaket tatbikatı.
- Destek süreci: iletişim kanalları, yanıt süresi hedefi, şablon yanıtlar; sipariş/talep notu iç.
- Hizmet seviyesi hedefleri (SLO): erişilebilirlik %99,5, ödeme başarı oranı izleme, API p95 < 500 ms.

## 8. Risk kaydı
| ID | Risk | Olasılık | Etki | Azaltma |
|---|---|---|---|---|
| R1 | Ödeme sağlayıcı başvurusu gecikir/reddedilir | O | Y | Hemen başvur, PayTR yedek; ilk sürüm havale+kapıda |
| R2 | SMS gönderici başlığı onayı uzun sürer | O | O | Erken başvur; sayısal numara/ortak başlıkla başla |
| R3 | Hukuki/etiket/gıda mevzuat eksikleri yayını bekletir | O | Y | Paralel hukuki iş akışı, erken danışmanlık |
| R4 | Çiftçi benimsemesi düşük (dijital) | O | Y | Telefon ile talep açma, basit UI, saha eğitimi, pilot |
| R5 | Tartı anlaşmazlıkları | O | Y | Onay kodu, tutanak, fotoğraf, ikinci tartı, net kurallar |
| R6 | Tek VPS arızası | D | Y | Yedek+snapshot, RTO 4 sa runbook, ileride ikinci düğüm |
| R7 | Kapsam genişlemesi | Y | O | MVP kilidi, değişiklik kuralı, aşama sonu gözden geçirme |
| R8 | Stok/ödeme tutarsızlığı | D | Y | Atomik işlemler, reconcile, yarış testleri |
| R9 | Güvenlik açığı | D | Y | Tarama, sızma testi, dar yetki, bildirim planı |
| R10 | Sezon yoğunluğu (hasat) yük | O | O | Önbellek, yük testi, ölçekleme planı (VPS yükseltme) |
| R11 | Anahtar kişi bağımlılığı (tek geliştirici) | Y | Y | Belgeler, runbook, otomasyon |
| R12 | Kargo entegrasyonu zorlukları | O | D | Elle takip no ile başla, API sonra |
| R13 | SEO/trafik kaybı geçişte | O | O | 301, sitemap, yayın sonrası izleme |
| R14 | Serenut ayrımında karışıklık | D | O | Ayırma kontrol listesi, ayrı hesaplar |
(O: orta, Y: yüksek, D: düşük)

## 9. Karar eşikleri (ne zaman yeniden değerlendiririz)
- Sipariş/gün > 200 veya Değirmen talep/gün > 50 → ikinci VPS/ayrı veritabanı değerlendirmesi.
- Yedek RPO yetersiz → WAL arşivleme (pgBackRest/WAL-G).
- İki ürün hattı ayrı ekiplerce yönetilirse → Değirmen modülünü ayrı servis/alan adına taşıma.

