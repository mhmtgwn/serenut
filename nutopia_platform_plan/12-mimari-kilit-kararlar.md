# 12 — Mimari Kilit Kararlar ve Evrim Güvencesi

> Bu belge **bağlayıcıdır**. Önceki belgelerle çelişirse bu belge geçerlidir (çelişkiler aynı gün düzeltilir).
> Amaç: "sonradan şu mimari yanlış çıktı, yama yapalım" durumunu tasarım gereği ortadan kaldırmak. Bunun yolu yanlış yapmamak değil, **yanlış çıkabilecek yerleri önceden izole etmektir**.

## 0. Yama üretmeyen mimarinin 8 ilkesi
1. **Kararlı çekirdek, değişken kenar.** İş kuralları (para, stok, sipariş, tartı) çekirdekte; sağlayıcılar (ödeme, SMS, kargo, fatura, harita, depolama) arayüz (port) arkasında. Sağlayıcı değişimi = yalnız adaptör yazmak.
2. **İnce istemciler.** Web, admin, şoför PWA'da **iş kuralı yok**; yalnız API istemcisi + görüntü. Ön yüz çerçevesi değişirse (Next.js → başka) iş kaybı olmaz.
3. **Veri tek gerçek kaynaktır, şema SQL ile yönetilir.** Kısıtlar (CHECK, UNIQUE, FK, kısmi indeks) veritabanında; uygulama hatası kaydı bozamaz. ORM değişse şema değişmez.
4. **Her şey sürümlü sözleşmedir:** API, olay (event), veritabanı göçü, yapılandırma. Kırıcı değişiklik yalnız "genişlet → geçiş → daralt" (expand/contract) ile.
5. **Sahiplik sınırı = taşıma sınırı.** Her tablo tek modüle aittir; modüller arası veri alışverişi servis arayüzü/olay ile. Ayrılma günü, sınırı kopyalamaktan ibaret.
6. **Geri alınabilirlik.** Her dağıtım, her göç, her kritik yönetici işlemi (fiyat, iade) geri alma yolu tanımlı.
7. **Gözlemlenebilirlik hazır doğar.** Her kritik akışta log, metrik, uyarı; sonradan eklenmez.
8. **Basit çalışan sistem, karmaşık çalışmayan sistemden iyidir.** Redis, Kubernetes, mikroservis, olay kaynağı (event sourcing) bilerek **yok**; yokluklarının yükseltme yolu belgelenmiştir (§13).

## 1. Kilitli teknoloji kararları (spike yok, açık uç yok)
| # | Karar | Neden kilit | Geri dönüş maliyeti | Değişim tetikleyicisi |
|---|---|---|---|---|
| K1 | **TypeScript (strict), Node.js 22 LTS** | Tek dil, tip paylaşımı | Yüksek (ama beklenmez) | Yok |
| K2 | **PostgreSQL 17** (tek DB, çok şema: `core`,`shop`,`mill`,`payments`,`ops`) | İlişkisel bütünlük, işlem, FTS, LISTEN/NOTIFY, kısmi indeks | Çok yüksek | Yok; sürüm yükseltme yıllık planlı |
| K3 | **Şema yönetimi: düz SQL göç dosyaları, `dbmate`** | Araçtan bağımsız, servis ayrılınca taşınır, CHECK/tetikleyici/kısmi indeks doğal | Düşük | Yok |
| K4 | **Sorgu katmanı: Kysely + `kysely-codegen`** (DB'den tip üretimi) | SQL'e yakın, kilitleme/`SKIP LOCKED`/CTE rahat, ORM sihri yok | Orta | Yok |
| K5 | **API: NestJS (Fastify adaptörü), REST+OpenAPI** | Modül/DI yapısı sınır disiplinini kodlar | Orta | Yok |
| K6 | **Vitrin: Next.js (App Router), sürüm sabitli, ince katman** | SEO/SSR olgunluğu; ince olduğu için değiştirilebilir | **Düşük** (iş kuralı yok) | Çerçeve destek sonu |
| K7 | **Admin+Şoför: React + Vite + TanStack Router/Query + kendi bileşen kitimiz (Radix tabanlı)** | SEO gerekmez, tam kontrol, hazır admin çerçevesine kilitlenme yok | Orta | Yok |
| K8 | **Kuyruk: `pg-boss` (arayüz `JobQueue` arkasında)** | Transaction ile atomik, ek altyapı yok | Düşük | Gün > 50k iş veya çok düğüm → arayüz altında Redis/BullMQ veya NATS |
| K9 | **Oturum: sunucu tarafı, `httpOnly` çerez, Postgres** | İptal edilebilir, basit | Düşük | Mobil native → ek olarak kısa ömürlü erişim jetonu uçları |
| K10 | **Gerçek zamanlı: SSE + Postgres LISTEN/NOTIFY** | WebSocket altyapısı gerekmez; çok örnekte de çalışır | Düşük | Çift yönlü gerekirse WS ekle |
| K11 | **Önbellek: süreç içi LRU + HTTP önbelleği + Cloudflare** (Redis yok) | RAM ve işletme yükü | Düşük | Çok düğüm + tutarlı önbellek ihtiyacı → `Cache` arayüzü altında Redis |
| K12 | **Hız sınırı: `RateLimiter` arayüzü; kimlik uçları Postgres destekli (UNLOGGED), genel trafik Cloudflare+bellek** | Çok örnekte tutarlı | Düşük | — |
| K13 | **Depolama: `StorageDriver` arayüzü; ilk sürüm yerel disk + `restic`; S3 uyumlu sürücü hazır yazılır** | Tek VPS'te basit, çok VPS'e hazır | Düşük | 2. düğüm → S3'e geçiş (yalnız yapılandırma) |
| K14 | **Yedek: pgBackRest ile WAL arşivleme (gün-1) + günlük tam/artımlı, şifreli, dış depo** | RPO ≤ 5 dk, PITR | Düşük | — |
| K15 | **Dağıtım: Docker Compose, tek ana makine; API/web durumsuz, N kopya çalışabilir** | Basitlik; yatay ölçek yolu açık | Düşük | Gün > hedef → ikinci düğüm (§13) |
| K16 | **Cloudflare önde, origin kilitli** | WAF/DDoS/CDN | Düşük | CF kesintisi runbook'u (§10) |
| K17 | **ID: UUIDv7 (dahili), okunur numara (yıl-sıra) dışa dönük, takip için ayrı rastgele jeton** | Sıralı dizin performansı + tahmin edilemezlik | Orta | — |
| K18 | **Para: `bigint` kuruş; vergi satır bazında net/KDV/brüt saklı** | Fatura ile birebir uyum | **Çok yüksek** — bu yüzden şimdi kilit | — |
| K19 | **Zaman: `timestamptz` (UTC) + iş günü `date` (Europe/Istanbul); iş saatleri yapılandırılabilir** | DST olmasa bile doğru; ileride çok bölge mümkün | Orta | — |
| K20 | **Kimlik: `customers` + `customer_identities` (telefon/e-posta ayrı satır)** | Numara değişimi, birleştirme, çoklu kimlik | **Yüksek** — şimdi kilit | — |
| K21 | **Vergi: `tax_classes` + `tax_rates(valid_from)`; siparişte oran anlık kopya** | KDV değişimi geçmişi bozmaz | **Yüksek** | — |
| K22 | **`business_unit` (`shop`/`mill`) tüm finansal kayıtlarda** | Ayrı muhasebe/ayrı tüzel kişilik ihtimali | **Yüksek** | — |
| K23 | **Optimistik kilit: değişebilir her toplulukta (`version` sütunu)** | Çoklu yönetici düzenleme çakışması | Orta | — |
| K24 | **Değişmez defterler: `stock_ledger`, `audit_log`, `order_events`, `ledger_entries` UPDATE/DELETE tetikleyiciyle yasak** | Denetlenebilirlik | Düşük | — |
| K25 | **Belge numaralandırma: boşluksuz sayaç tablosu (kilitli)** | Fatura/makbuz yasal sıra | Orta | — |
| K26 | **Monorepo: `pnpm` + Turborepo, ayrı repo `nutopia-platform`** | Tip paylaşımı | Düşük | — |
| K27 | **Test: Vitest, gerçek PostgreSQL (Testcontainers), Playwright, k6** | Gerçeğe yakın güven | Düşük | — |
| K28 | **Gözlem: pino + OpenTelemetry SDK (dışa aktarım kapalı başlar) + Sentry + Uptime Kuma** | Sonradan izleme eklemek yamadır | Düşük | Trafik büyürse OTLP → Grafana Cloud/Tempo |
| K29 | **SMS/E-posta/Ödeme/Kargo/Fatura/Harita: arayüz + ilk adaptör; en az iki adaptör yazılabilir olduğu kanıtlanır (fake + gerçek)** | Satıcı değişimi | Düşük | — |
| K30 | **Türkçe tek dil, ama metinler anahtar tabanlı sözlükte** | İngilizce/Arapça sonradan yama olmasın | Düşük | — |

## 2. Bilinçle kabul edilen sınırlar (dürüstlük listesi)
| Sınır | Sonuç | Ne zaman sorun olur | Çözüm yolu (hazır) |
|---|---|---|---|
| Tek VPS | Donanım arızası = kesinti (RTO ~4 sa) | Sipariş yoğun / kesinti maliyeti yüksek | §13-S2: ikinci düğüm + DB replika, DNS/LB |
| Tek DB | Mağaza ve Değirmen aynı DB'de | Ayrı ekip/ayrı ölçek | Şema sınırları sayesinde `mill` şeması taşınır (§4) |
| Redis yok | Paylaşımlı önbellek yok | 3+ API kopyası | `Cache` arayüzü |
| Next.js sürüm hızı | Ana sürüm yükseltmeleri | Yılda ~1 | İnce katman: yükseltme maliyeti düşük; sürümler sabit, yılda 1 planlı pencere |
| pg-boss | Tek DB'ye bağlı kuyruk | Çok yüksek iş hacmi | `JobQueue` arayüzü |
| Elle rota planlama | Optimal rota yok | Günde 10+ alım | Rota sağlayıcı arayüzü (`RoutePlanner`) |
| Resmî olmayan WhatsApp yok | Müşteriye SMS | WhatsApp isteği | Resmî WhatsApp Business adaptörü eklenir (arayüz hazır) |

## 3. Port ve adaptör sözleşmeleri (çekirdeğin dışına açılan kapılar)
| Port | Sorumluluk | İlk adaptör | Alternatif adaptör (hazır olduğu kanıtlanacak) | Test çifti |
|---|---|---|---|---|
| `PaymentProvider` | başlat, doğrula, iade, iptal, webhook doğrula | iyzico | PayTR | `FakePaymentProvider` |
| `SmsProvider` | gönder, teslim raporu, bakiye | seçilen TR sağlayıcı | ikinci sağlayıcı (yedek geçiş) | `FakeSms` (konsol/DB) |
| `EmailProvider` | işlemsel gönderim | SMTP/API sağlayıcı | ikinci sağlayıcı | `FakeEmail` |
| `CarrierProvider` | ücret teklifi, gönderi oluştur, etiket, takip | `ManualCarrier` (elle takip no) | seçilen kargo API | `FakeCarrier` |
| `InvoiceProvider` | fatura oluştur/iptal/PDF | `CsvExport` (muhasebeye) | özel entegratör | `FakeInvoice` |
| `StorageDriver` | put/get/delete/signedUrl | yerel disk | S3 uyumlu | bellek içi |
| `MapProvider` | adres arama, ters geokod, statik harita | OSM tabanlı | Google | sabit çıktı |
| `RoutePlanner` | alım sıralama | `ManualPlanner` | basit en-yakın-komşu → ticari API | sabit |
| `JobQueue` | işi sıraya at/zamanla/yeniden dene | pg-boss | Redis/NATS | bellek içi |
| `Cache` | get/set/invalidate | süreç içi | Redis | — |
| `RateLimiter` | tüket/kontrol | bellek + Postgres | Redis | — |
| `Clock` | `now()` | sistem | — | sabit saat |
| `IdGenerator` | UUIDv7, belge no, jeton | — | — | deterministik |
| `FeatureFlags` | bayrak değerlendirme | DB | — | sabit |
**Kural:** çekirdek kod sağlayıcı SDK'sını içe aktaramaz (CI'da dependency-cruiser). Sağlayıcıya özgü alanlar `raw_redacted jsonb` içinde kalır, alan modeline sızmaz.

## 4. Sahiplik ve ayrılma yolu
### 4.1 Tablo sahipliği
| Şema | Sahip modül | Başka modül okuyabilir mi? |
|---|---|---|
| `core.customers/identities/addresses` | `identity` | Servis arayüzüyle (`CustomerDirectory`) |
| `core.staff/roles/sessions` | `identity` | hayır |
| `core.settings/flags/audit/outbox` | `platform` | `SettingsService`, `Audit` |
| `shop.*` | `catalog/inventory/pricing/cart/orders/shipping` kendi tabloları | yalnız servis |
| `mill.*` | `mill/dispatch` | yalnız servis |
| `payments.*` | `payments` | `PaymentsService` (hedef türü `shop_order`/`mill_request` genel referans) |
| `ops.*` | `notifications/invoicing/reporting` | servis |
Raporlama modülü istisna: **salt-okunur görünümler (`reporting` şeması)** üzerinden çapraz okur; görünümler sözleşmedir, ayrılırken yeniden yazılır.

### 4.2 Değirmeni ayırma adımları (şimdiden bilinen reçete)
1. Aynı repoda `apps/mill-api` kabuğu: `mill` ve `dispatch` modüllerini ayrı süreç olarak başlat (aynı DB, aynı kod) — **veri taşımadan**.
2. `identity` ve `payments`'a erişimi HTTP/içeri iletişim istemcisine çevir (modül sınırı zaten servis arayüzü).
3. `mill` şemasını ayrı veritabanına `pg_dump -n mill` ile taşı; `customer_id` alanları artık yabancı anahtar değil **referans**tır (şimdiden FK yerine "yumuşak referans + doğrulama servisi" tasarımı: `mill` şeması `core.customers`'a FK vermez; `customer_ref uuid` + `customer_snapshot jsonb`).
4. Alan adı ayrılır (`degirmen.<alan>`); vitrin `apps/web` temayla çoğaltılır veya ayrı yayın.
5. Ortak oturum çerezi alan adı kapsamı veya SSO (OTP kimliği iki yerde bağımsız doğrulanır).
**Bu yüzden:** `mill.*` tablolarında `core.*`'a FK yok (tek istisna: `staff` → şoför referansı da yumuşak). `payments.*` hedef referansı polimorfik, FK'siz; bütünlük servis + gece uyum denetimi ile.

### 4.3 Mağazayı ayırma
Daha olası değil ama aynı reçete: `shop.*` taşınır. `inventory` ortak değil; mağaza stoku yalnız `shop`'tadır.

## 5. Sözleşme ve sürüm politikası
| Sözleşme | Kural |
|---|---|
| **API** | `/v1` sabit; ekleme geriye uyumlu (opsiyonel alan); kaldırma/anlam değişimi → `/v2` + 6 ay `Deprecation`/`Sunset` başlıkları; OpenAPI diff CI'da kırıcı değişikliği yakalar |
| **Olaylar** | `{ type, schemaVersion, occurredAt, id, data }`; eski sürüm tüketicisi çalışmaya devam eder (upcaster); olay şeması paketi `contracts` içinde |
| **Veritabanı** | Göçler ileri uyumlu: 1) yeni sütun/tablo ekle (null/varsayılan), 2) kod çift yazar/okur, 3) veri doldur, 4) kodu geçir, 5) eskiyi kaldır **ayrı sürümde**. `ALTER TABLE` kilit süresi bütçesi (< 1 sn; büyük tablolarda `CONCURRENTLY`, parça parça güncelleme). Göç kilit analizi CI'da (squawk benzeri linter). |
| **Yapılandırma** | `settings` anahtarları şemalı (zod), varsayılanlı; bilinmeyen anahtar reddedilir; değişiklikler `audit_log`'a |
| **Özellik bayrakları** | Her yeni riskli özellik bayrakla; bayrak yaşam süresi ≤ 90 gün (sonra kaldır) |
| **Admin/Şoför istemci sürümü** | PWA hizmet işçisi sürüm uyumsuzluğunda "yenile" der; API `X-Client-Version` ile minimum sürüm zorunluluğu verir |

## 6. Alan modelinde baştan çözülen genişleme noktaları
Aşağıdakiler MVP'de kullanılmasa bile **şemada ve arayüzde hazırdır**; sonradan eklemek göç+kod yaması olurdu.
| # | Genişleme | Şimdi ne yapılıyor | Hangi senaryo |
|---|---|---|---|
| E1 | `customer_identities` | telefon/e-posta ayrı satır, `verified_at`, `is_primary`, birleştirme günlüğü | numara değişimi, aynı kişinin iki kaydı, e-posta+telefon bağlama |
| E2 | `tax_classes`/`tax_rates` | oran tarihçeli; kalem anlık kopya | KDV oranı değişikliği, farklı ürün sınıfları |
| E3 | Paket/kit ürün | `product_kind = simple/bundle`, `bundle_components` | hediye kutusu, kurumsal paket |
| E4 | Fiyat listeleri | `price_lists`, `price_list_items`, `customer_groups` | kurumsal/toptan, kampanya dönemleri |
| E5 | Kısmi gönderim | `shipment_items` | iki paket, stok yetersiz parça gönderim |
| E6 | `business_unit` | finans kayıtlarında zorunlu | ayrı muhasebe |
| E7 | Cari hesap | `receivable_accounts`, `receivable_entries` (borç/alacak), kredi limiti | **veresiye/sonra öde**: çiftçiler hasat satışından sonra öder |
| E8 | Ayni ödeme | `settlement_method = in_kind`; `mill_inventory_movements` | ücret yerine fındıktan kesinti (kg) |
| E9 | Ücret kuralı genelliği | `mill_pricing_rules(basis: input_kg/output_kg/flat/per_bag, tiers, season)` | kademeli, sezonluk, çıktı kg'a göre fiyat |
| E10 | Alanda iletişim kişisi | `site_contact_name/phone`, tarif, `geo_point`, erişim notu | bahçede bekçi/komşu, kapı bulma |
| E11 | Çoklu kontak kanalı | `contact_channels` + tercih (SMS/e-posta), `notification_preferences` | WhatsApp'a geçiş |
| E12 | İşlem imzası (onay kanıtı) | `acknowledgements(type, subject, code_hash, method, at, ip/device)` | tartı onayı, sözleşme, teslim |
| E13 | Çoklu ambalaj/birim | `variants.unit` + `net_content_g` alanları | gram bazlı etiket |
| E14 | Sipariş düzenleme | siparişte `version`, `order_amendments` (adres/kalem değişikliği geçmişi) | paketlemeden önce düzenleme |
| E15 | Hediye kartı/sadakat | `credits(customer, amount, expires)` + `credit_entries` | iade yerine kredi, kampanya |
| E16 | Yorum/puan | `reviews` tabloları ve moderasyon durumu | v1.1 |
| E17 | Webhook alt yapısı (giden) | `outbound_webhooks` abone tablosu | muhasebe/ERP entegrasyonu |
| E18 | Belge deposu | `documents(type, owner, storage_key, sha256, visibility)` | tutanak PDF, fatura, gazi belgesi |
| E19 | Çok depo/lokasyon | `stock_locations` (tek lokasyonla başla) | sonradan ikinci depo |
| E20 | Kurye yöneticisi dışı personel rolleri | rol/izin veri olarak | yeni rol ekleme kodsuz |

## 7. Tutarlılık matrisi
| İşlem | Garanti | Nasıl |
|---|---|---|
| Sipariş oluşturma + stok rezerv | Atomik | Tek transaction; `UPDATE ... WHERE available >= qty` |
| Ödeme durumu + sipariş durumu + stok commit | Atomik | Webhook işleyicisi tek transaction |
| Sağlayıcıya çağrı + DB yazısı | Nihai tutarlı | Önce DB'ye `initiated`, sonra çağrı; reconcile işi |
| Olay yayını | En az bir kez | Outbox; tüketici idempotent |
| SMS gönderimi | En az bir kez, tekilleştirme anahtarı | `notifications.dedupe_key` |
| Stok sayımı | Kesin | Defter + özet tablosu aynı transaction; gece uzlaştırma işi (defter toplamı = `on_hand`) |
| Para toplamları | Kesin | `order.grand_total = Σ lines + shipping − discounts` DB `CHECK` (satır tabloları özetlenerek tetikleyici/uygulama + gece denetimi) |
| Tartı kaydı | Değişmez | Düzeltme = yeni satır (`supersedes_id`), eski satır kalır |
| Belge numarası | Boşluksuz, benzersiz | Kilitli sayaç satırı (transaction içinde) |

## 8. Yarış koşulu kataloğu
| Durum | Önlem |
|---|---|
| İki kişi son ürünü alıyor | Atomik koşullu güncelleme, kaybeden net hata alır |
| Webhook ile callback aynı anda | `payments` satırı `SELECT … FOR UPDATE`, durum geçişi kontrolü |
| Yönetici iki sekmede aynı siparişi düzenliyor | `version` uyuşmazlığı → 409 + fark gösterimi |
| Aynı alım iki şoföre atanıyor | `pickups` kısmi benzersiz indeks (aktif alım başına tek şoför) |
| Aynı kupon aynı anda iki kez | Kupon kullanım satırı + `max_uses` koşullu artış (atomik sayaç) |
| Çift tıklama ödeme | `Idempotency-Key` + sipariş başına aktif `payment` tek |
| Rezerv süresi dolarken ödeme geliyor | Ödeme geçişi, rezerv `FOR UPDATE`; süresi dolmuş ise stok yeniden denenir, yoksa iade |
| İki süreç aynı işi yapıyor | `pg-boss` tekil iş anahtarı + işlem içinde kilit |
| Fiyat değişimi sepetteyken | Ödeme anında yeniden fiyatla, farkı göster, onay iste |
| Aynı telefon iki OTP hızlıca | Son istek öncekini geçersiz kılar |

## 9. Kapasite modeli (planlama)
Varsayım (sezon zirvesi, cömert): 300 sipariş/gün, 100 değirmen talebi/gün, 20.000 ziyaretçi/gün, 1.000.000 API isteği/gün (≈ 12 istek/sn ort., 100 istek/sn tepe).
| Kaynak | Hesap | Sonuç |
|---|---|---|
| API CPU | tepe 100 rps × ~10 ms | 2 vCPU rahat |
| DB boyutu | sipariş+kalem+olay ~ 10 KB/sipariş × 300 × 365 | ≈ 1 GB/yıl; audit/notifications dahil ≈ 3–5 GB/yıl |
| Medya | 7 ürün × 8 görsel × 5 boyut × 150 KB | < 100 MB başlangıç; tutanak foto 300 KB × 100/gün | ≈ 10 GB/yıl |
| SMS | 4–6/sipariş-talep | ≈ 2.000 SMS/gün zirve |
| WAL | yazma yoğunluğu düşük | birkaç GB/ay |
| Disk 80 GB | | 3+ yıl rahat |
Sonuç: tek VPS 10x trafik büyümesini kaldırır. Darboğaz CPU değil **operasyon** (sipariş hazırlama, şoför kapasitesi).

## 10. Hata modları (failure mode) ve davranışlar
| Hata | Etki | Tespit | Davranış | Kurtarma |
|---|---|---|---|---|
| DB düştü | Her şey | `/health/ready`, Uptime | API 503, vitrin statik önbellekten ürün gösterir "sipariş geçici kapalı" | Konteyner yeniden başlat / yedekten PITR |
| Ödeme sağlayıcı kapalı | Kart ödemesi | başlatma hatası oranı | Kart seçeneği geçici gizlenir (bayrak otomatik), havale/kapıda açık | Sağlayıcı dönünce açılır |
| SMS sağlayıcı kapalı | OTP/bildirim | gönderim hata oranı | İkinci sağlayıcıya otomatik geçiş (adaptör sırası) | Kuyrukta yeniden dene |
| Kargo API kapalı | Etiket | hata | Elle takip no girişi modu | Sonra senkron |
| Disk doldu | Yazma durur | disk uyarısı %80/%90 | Log/imaj temizliği, medya taşıma | Disk genişlet |
| Yedek başarısız | Risk | pgBackRest `check` + uyarı | Yüksek öncelikli uyarı | Aynı gün düzelt |
| Göç başarısız | Dağıtım durur | CI/dağıtım betiği | Otomatik geri alma + eski sürüm devam | Düzelt, yeniden |
| Cloudflare kesintisi | Erişim | harici izleme | Bypass runbook'u: DNS'i origin'e doğrudan (TTL kısa), origin Cloudflare IP kilidini geçici gevşet | Geri kilitle |
| Sertifika süresi | Erişim | SSL izleme (30/14/7 gün) | Otomatik yenileme + uyarı | Elle yenile |
| Webhook kaybı | Siparişler bekler | reconcile | Sorgu ile tamamlanır | — |
| Saat kayması | OTP/imza hataları | `chrony` izleme | Uyarı | Senkron |
| Bellek yetersiz | OOM | konteyner yeniden başlatma sayacı | Sınırlar, swap | Sınırları gözden geçir |
| Şoför internetsiz | Veri girişi | — | Cihaz kuyruğu, çakışmada sunucu kuralları | Senkron |
| Tek kişilik operasyon aksar | Siparişler birikir | "bekleyen sipariş yaşı" metriği | Panelde kırmızı uyarı, SMS | Yedek kişi/yardım |
| İç kullanıcı hatası (yanlış fiyat) | Zarar | fiyat değişim eşiği uyarısı (±%30) | Onay isteme | Audit + geri al |

## 11. Satıcı bağımlılığı ve çıkış stratejisi
| Satıcı | Bağımlılık | Çıkış |
|---|---|---|
| VPS sağlayıcı | Düşük (standart Linux/Docker) | Yedekten yeni sağlayıcıda kalk (RTO 4 sa) |
| Cloudflare | DNS/WAF/CDN | DNS'i başka sağlayıcıya taşı; CDN yokluğunda origin cache başlıkları zaten doğru |
| iyzico | Ödeme | `PaymentProvider` ikinci adaptör; geçiş dönemi iki sağlayıcı |
| SMS | OTP/bildirim | Yedek adaptör sürekli etkin (düşük hacim) |
| Alan adı kaydı | Kritik | Başka kayıt şirketine transfer (kilit açma süreci bilinir) |
| GitHub | Kod | Yerel/ikincil uzak depo yansıması |
| Sentry | Hata izleme | Kapat/GlitchTip |
| Yedek depo | Yedek | İkinci hedef (haftalık) |
Veri taşınabilirliği: tüm veri standart PostgreSQL + dosyalar; özel biçim yok.

## 12. Varsayım kaydı (yanlış çıkarsa ne olur?)
| ID | Varsayım | Doğrulama | Yanlışsa |
|---|---|---|---|
| V1 | Tek işletme (tek tüzel kişi) | Mali müşavir | `business_unit` + tüzel kişi tablosu (E6 hazır) |
| V2 | KDV fiyatı dahil gösterilir | Mevzuat/müşavir | Vergi alanları zaten net/KDV/brüt; gösterim bayrağı |
| V3 | Tek şoför/araç başlangıç | Siz | `dispatch_drivers` çoklu zaten |
| V4 | Çiftçilerin çoğu mobil + SMS kullanır | Saha pilotu | Telefonla talep + yönetici ekranı (MVP içinde) |
| V5 | Alım yalnız Ereğli çevresi | Siz | `mill_coverage` veri olarak |
| V6 | Ödeme çoğunlukla havale/kapıda (değirmen) | Siz | Çevrimiçi tahsilat zaten tasarlandı |
| V7 | Ücret tartıdan sonra kesinleşir | Siz | Tahmini ücret ön ödeme seçeneği (cari/ödeme modeli destekler) |
| V8 | Gazi indirimi belgeyle | Hukuk | Belgesiz doğrulama (dernek kodu) — akış yapılandırılabilir |
| V9 | Ürün kataloğu küçük (<100) | — | FTS yeterli, büyürse arama motoru adaptörü |
| V10 | Fındık fiyatı değişken (sezon) | Siz | Fiyat listesi geçerlilik tarihli, ürün fiyatı hızlı güncellenebilir |
| V11 | Trafik 10x'e kadar tek VPS | Yük testi | İkinci düğüm yolu (§13) |
| V12 | Türkiye içi satış | — | Yurtdışı: gümrük/para birimi/vergi (v3, `currency` alanı var) |

## 13. Evrim senaryoları (hepsi önceden planlı)
| Senaryo | Nasıl yapılır | Maliyet | Yama gerekir mi? |
|---|---|---|---|
| S1 Değirmeni ayrı alan adına al | Tema + alan adı; aynı uygulama | Gün | Hayır |
| S2 İkinci sunucu | Postgres → birincil+replika (yalnız okuma), API/web kopyaları, medya S3, LB | 3–5 gün | Hayır (durumsuz tasarım) |
| S3 Değirmen ayrı servis | §4.2 | 1–2 hafta | Hayır |
| S4 Ödeme sağlayıcı değişimi | Yeni adaptör, iki sağlayıcı paralel | 3–5 gün | Hayır |
| S5 Kargo API'ye geçiş | `CarrierProvider` adaptörü | 3–5 gün | Hayır |
| S6 Native şoför uygulaması | Aynı API; oturum jetonu ucu | 2–3 hafta | Küçük (jeton ucu) |
| S7 Pazaryeri (Trendyol/HB) | Katalog/sipariş dışa aktarma adaptörleri; `channel` alanı siparişte | 2–3 hafta | Hayır (`channel` baştan var) |
| S8 B2B/Toptan | Fiyat listeleri+müşteri grupları (E4) + teklif akışı | 2 hafta | Hayır |
| S9 Çok dil | Metin sözlükleri çevir, `Accept-Language`, ürün çeviri tablosu | 1–2 hafta | `product_translations` ayrı tablo (baştan) |
| S10 Abonelik (düzenli ezme/kutu) | `subscriptions` + zamanlı iş + saklı ödeme | 3 hafta | Saklı kart gerekir (yeni) |
| S11 Çok depo | `stock_locations` (E19) | 1 hafta | Hayır |
| S12 Mobil uygulama (müşteri) | Aynı API | 4–6 hafta | Hayır |
| S13 ERP/Muhasebe entegrasyonu | Giden webhook (E17) + fatura adaptörü | 1–2 hafta | Hayır |
| S14 Managed DB'ye geçiş | pgBackRest geri yükle → yönetilen servis, bağlantı dizesi | 1 gün + bakım penceresi | Hayır |
| S15 Çoklu mağaza/marka | `store_id` sütunu gerekir | 2–4 hafta | **Evet** — bilerek yapılmadı (V1) |
| S16 Kubernetes | Gerekmeyecek | — | — |

## 14. Mimari uygunluk testleri (fitness functions, CI'da zorunlu)
1. **Bağımlılık kuralları:** `dependency-cruiser` — modül sınırı ihlali, çekirdekte SDK içe aktarma, `web/admin`'de DB/iş kuralı kodu → CI kırılır.
2. **Şema:** `squawk`/özel linter — kilit riskli göç, FK'siz `mill→core` kuralı (K-§4.2), her tabloda `created_at/updated_at`, her değişebilir tabloda `version`, para sütunları `bigint`, değişmez tablolarda tetikleyici var.
3. **API:** OpenAPI diff — kırıcı değişiklik yasak (sürüm yükselmeden).
4. **Sorgu bütçesi:** entegrasyon testlerinde uç başına sorgu sayısı üst sınırı (N+1 önleme).
5. **Para:** özellik testleri — yuvarlama toplamı, vergi ayrıştırma, iade ≤ ödeme.
6. **Durum makinesi:** tüm geçiş tablosu test edilir; tanımsız geçiş reddedilir.
7. **Güvenlik:** her uç için yetki testi (matris üretilir), IDOR testleri.
8. **Performans:** Lighthouse CI + k6 eşik testi; bundle boyutu bütçesi.
9. **Gözlem:** kritik her uçta log+metrik varlığı (lint kuralı/test).
10. **Yedek:** haftalık otomatik geri yükleme + satır sayısı karşılaştırma.
11. **Kodlama:** `strict`, ESLint `no-floating-promises`, `no-explicit-any` (istisna listesi), sır tarama.

## 15. "Bu yüzden sonradan yama olmaz" kontrol soruları (her büyük değişiklikte sorulur)
1. Bu karar bir **port** arkasında mı? 2. Şema değişikliği **genişlet/daralt** ile mi? 3. İş kuralı **çekirdekte** mi, istemcide mi? 4. Olay/API **sürümlü** mü? 5. Geri alma yolu **yazılı** mı? 6. Gözlem eklendi mi? 7. Bu bir **Kilit Karar** (K#) ile çelişiyor mu? Çelişiyorsa önce bu belgeyi ADR ile değiştiririz, kodu değil.
