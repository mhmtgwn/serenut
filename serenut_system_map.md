# SERENUT WEBSITE — COMPLETE SYSTEM MAP

## 1. Executive Summary
Serenut OS web platformu ve bağlı backend mimarisi, bulut POS (Point of Sale) SaaS otomasyon sisteminin merkezî yönetim, lisanslama, abonelik, ödeme altyapısı ve güncellemelerini yöneten dağıtık bir sistemdir.
Sistem temel olarak 4 ana bölümden oluşur:
1. **Public Website:** Müşterileri bilgilendiren, paket fiyatlarını sunan ve statik sayfaları barındıran halka açık kurumsal web sitesidir.
2. **Customer Portal (Müşteri Yönetim Portalı):** Müşterilerin şirket ayarlarını, şubelerini, personellerini, donanımlarını, lisanslarını, faturalarını ve destek taleplerini yönettikleri ve yazılım paketlerini indirdikleri Single Page Application (SPA) arayüzüdür.
3. **Admin Control Center (Yönetim Paneli):** Platform yöneticilerinin (sysadmin) tüm şirketleri, kullanıcıları, lisansları, banka hesaplarını, ödeme yöntemlerini, sürümleri, destek taleplerini ve sistem sağlığı verilerini yönettikleri gelişmiş bir yönetim panelidir.
4. **Backend REST API & WebSockets (Node.js/TypeScript):** Tüm bu arayüzlerin yetkilendirme, veri kaydı, iş akışları, kuyruk işlemleri (BullMQ) ve gerçek zamanlı senkronizasyon (WebSocket) süreçlerini yürüten ve PostgreSQL ile Redis kullanan ana sunucu uygulamasıdır.

### Forensic Genel Değerlendirme
Sistem mimarisi ve veri akış zincirleri büyük ölçüde tamamlanmıştır. Ancak, **Windows kurulum dosyasının eksik olması (404 riski)** ve **Iyzico Callback eşleştirme algoritmasındaki mantıksal zafiyet** gibi kritik P0/P1 bulgular tespit edilmiştir. Frontend tarafında ise Iyzico ödemesini başlatan endpoint çağrısının uyumsuz olması nedeniyle **kredi kartı checkout akışı kırık durumdadır.**

---

## 2. Architecture Map
Aşağıda Serenut OS web platformunun kullanıcı arayüzlerinden veri tabanına kadar uzanan tam veri akış ve entegrasyon mimarisi gösterilmiştir:

```text
                                Kullanıcı (Ziyaretçi / Müşteri / Admin)
                                                   ↓
                    [Public Website]     [Customer Portal]     [Admin Panel]
                     (Vanilla HTML/JS)       (Vanilla SPA)       (Vanilla SPA)
                                                   ↓
                                           [api-client.js]
                                                   ↓
                                        [HTTP / REST Endpoints]
                                                   ↓
                                             [server.ts]
                             (enforceSchemaHandshake & cors & helmet)
                                                   ↓
                                         [Route Controllers]
                                   (auth, portal, admin, billing...)
                                                   ↓
                                      [Backend Domain Services]
                                (AuthService, LicenseService, Iyzico...)
                                                   ↓
                                         [Repository / ORM]
                                       (pgPool / pg-queries)
                                                   ↓
                         +-------------------------+-------------------------+
                         ↓                                                   ↓
            [PostgreSQL (SaaS DB)]                                 [Redis (Caching & Queue)]
         - Row Level Security (RLS)                             - plans:list (Cache Warmup)
         - RLS bypass (app.bypass_rls)                          - BullMQ (notification-queue)
```

### Klasör Yapısı
*   `/server/public/website/`: Statik kurumsal sayfalar (HTML, CSS, JS).
*   `/server/public/portal/`: Müşteri portalı dosyaları (SPA index.html ve modüler JS scriptleri).
*   `/server/public/admin/`: Yönetim paneli dosyaları (SPA index.html ve modüler JS scriptleri).
*   `/server/public/shared/`: Arayüzler arası ortak kullanılan API istemcisi, yetkilendirme modülü, UI elementleri ve Lucide ikon kütüphanesi.
*   `/server/src/modules/`: Backend iş mantığı modülleri (controllers, services ve veri şemaları).
*   `/server/db/`: PostgreSQL veritabanı şeması (`schema.sql`) ve incremental geçiş scriptleri (`schema_v1.sql` - `schema_v37.sql`).

---

## 3. Complete Route Inventory

### Public Routes (Halka Açık Sayfalar)
Public sayfalarda yetkilendirme (authentication) gerekmez.
*   **Route:** `/` veya `/index.html` (Kurumsal Ana Sayfa)
    *   *Amaç:* Ürün tanıtımı, temel özellikler ve CTA butonları.
    *   *Hedef Kullanıcı:* Ziyaretçi / Potansiyel Müşteri.
*   **Route:** `/platform`
    *   *Amaç:* Serenut OS özelliklerinin detaylı tanıtımı.
    *   *Hedef Kullanıcı:* Ziyaretçi.
*   **Route:** `/plans`
    *   *Amaç:* Lisans abonelik paketleri fiyatlarının listelenmesi. Dinamik olarak backend'den `/api/v1/billing/plans` endpoint'ini çağırır.
    *   *Hedef Kullanıcı:* Ziyaretçi / Müşteri.
*   **Route:** `/downloads`
    *   *Amaç:* Serenut OS istemci uygulamalarının indirildiği ve sürüm geçmişinin listelendiği sayfa.
    *   *Hedef Kullanıcı:* Ziyaretçi / Mevcut Müşteri.
*   **Route:** `/contact`
    *   *Amaç:* Ziyaretçilerin iletişim formu doldurduğu sayfa.
    *   *Hedef Kullanıcı:* Ziyaretçi.
*   **Route:** `/kvkk`, `/privacy`, `/terms`
    *   *Amaç:* Yasal ve mevzuat uyumluluk metinlerinin gösterimi.
    *   *Hedef Kullanıcı:* Ziyaretçi.

### Customer Portal Routes (Müşteri Portalı)
Müşteri portalı `/portal/index.html` dosyasında bir SPA olarak kurgulanmıştır ve URL hash'leri (`#dashboard`, `#subscription`, `#licenses`, `#users`, `#stores`, `#devices`, `#downloads`, `#support`, `#settings`, `#register`) üzerinden sanal yönlendirme yapar.
*   **Erişim Koşulu:** `sessionStorage.portal_token` varlığı (Authentication Guard).
*   **Hash: `#dashboard`** (Genel Özet Raporu)
*   **Hash: `#subscription`** (Abonelik, Ödeme ve Fatura Listesi)
*   **Hash: `#licenses`** (Şirkete ait aktif ve süresi dolmuş lisans anahtarları)
*   **Hash: `#users`** (Personel ve kasiyer listesi ve yetkileri)
*   **Hash: `#stores`** (Şirket şubelerinin yönetimi)
*   **Hash: `#devices`** (POS terminallerinin durum takibi)
*   **Hash: `#downloads`** (Yetkilendirilmiş yazılım paketi indirme merkezi)
*   **Hash: `#support`** (Destek talepleri açma ve mesajlaşma arayüzü)
*   **Hash: `#settings`** (Profil bilgileri, şifre değiştirme ve şirket logosu güncelleme)

### Admin Panel Routes (Yönetim Paneli)
Yönetim paneli `/admin/index.html` dosyasında bir SPA olarak kurgulanmıştır ve `data-tab` / URL hash yapısı ile yönetilir.
*   **Erişim Koşulu:** `sessionStorage.admin_token` ve kullanıcının rolünde `'sysadmin'` bulunması (Admin Guard).
*   **Tab: `dashboard`** (Genel sistem durum grafikleri ve MRR bilgileri)
*   **Tab: `companies`** (Kayıtlı müşteri şirketleri listesi, askıya alma/silme)
*   **Tab: `transfers`** (Bekleyen banka havalesi bildirimlerinin listesi ve onaylama arayüzü)
*   **Tab: `payments`** (Fatura takip listesi ve manuel ödeme onayları)
*   **Tab: `payment-methods`** (Dinamik Payment Provider Registry ayarları ve bağlantı testleri)
*   **Tab: `plans`** (Lisans paket fiyat ve özellik ayarları)
*   **Tab: `licenses`** (Tüm aktif lisans anahtarlarını listeleme, lisans üretme ve askıya alma)
*   **Tab: `devices`** (Tüm şubelerdeki POS terminallerini izleme, bloklama ve swap)
*   **Tab: `releases`** (OTA güncellemeleri için yeni yazılım yükleme ve adoption izleme)
*   **Tab: `support`** (Tüm müşteri destek taleplerine yanıt verme ve dahili not ekleme)
*   **Tab: `audit`** (Yöneticilerin sistem üzerinde yaptığı tüm işlemlerin denetim günlükleri)
*   **Tab: `health`** (WebSocket durumları, telemetri, crash logları ve SMS durumları)

---

## 4. Page-by-Page Analysis

### plans.html (Fiyatlandırma Sayfası)
*   *Dosya Konumu:* [plans.html](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/public/website/plans.html) ve [plans.js](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/public/website/js/plans.js)
*   *Görünüm:* Aylık/Yıllık geçiş toggle'ı ve lisans paket kartları (Free, Basic, Pro, Enterprise).
*   *Veri Kaynağı:* `/api/v1/billing/plans` API endpoint'i.
*   *Aksiyon:* Paket kartındaki butona tıklandığında `sessionStorage` alanına `selected_plan_id` ve `selected_billing_period` kaydedilir ve kullanıcı `/portal/#register` sayfasına yönlendirilir.

### downloads.html (Sürümler ve İndirme Sayfası)
*   *Dosya Konumu:* [downloads.html](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/public/website/downloads.html) ve [downloads.js](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/public/website/js/downloads.js)
*   *Görünüm:* Sürüm kartları ve İndir butonları. Sürüm kartlarında işletim sistemi (Windows/Android), versiyon kodu ve yayın tarihi görünür.
*   *Veri Kaynağı:* `/api/v1/releases/history` endpoint'i.
*   *Aksiyon:* İndir butonuna tıklanıldığında kullanıcının aktif oturumu (`getAuthToken()`) sorgulanır. Oturum yoksa müşteri portalı giriş ekranına yönlendirilir; oturum varsa token eklenerek `/api/v1/releases/download/:releaseId` üzerinden dosya indirme tetiklenir.

### Customer Portal — `#subscription` (Abonelik Tabı)
*   *Dosya Konumu:* [billing.js](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/public/portal/js/billing.js) ve [subscription.js](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/server/public/portal/js/subscription.js)
*   *Görünüm:* Aktif plan detayları, dönem sonu tarihi, ödeme durumu, fatura tablosu, iptal/yeniden aktifleştirme butonları ve paket yükseltme seçenekleri.
*   *Aksiyonlar:*
    1.  *İptal Etme:* `POST /api/v1/billing/cancel` çağrılarak dönem sonunda iptal talebi oluşturulur.
    2.  *Yeniden Aktifleştirme:* `POST /api/v1/billing/reactivate` çağrılır.
    3.  *PDF Fatura İndirme:* `/api/v1/billing/invoices/:id/pdf` üzerinden indirme stream'i başlatılır.
    4.  *Havale Bildirimi Formu:* `/api/v1/billing/request-bank-transfer` ve `/api/v1/billing/notify-transfer` endpoint zinciri tetiklenir.

---

## 5. UI Interaction Inventory (Buttons & Forms)

### Önemli Butonlar Akış Denetimi

| Sayfa / Tab | Buton ID / Element | Kullanıcı Beklentisi | Frontend Handler | API Endpoint | Gerçek Sonuç | Durum |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Halka Açık Site | İletişim Formu Gönder | Mesajın gönderilmesi | `setupContactForm()` | `POST /support/public-contact` | Destek veritabanına kayıt atılır. | ✅ CONFIRMED |
| plans.html | Hemen Başla | Kayıt ekranına yönlendirme | `selectPlan(planId)` | Yok (Session storage set) | Portal kayıt sayfasına yönlendirir. | ✅ CONFIRMED |
| Portal Auth | Giriş Yap | Oturum açma | `handleLogin()` | `POST /auth/login` | Token alınır ve portal açılır. | ✅ CONFIRMED |
| Portal Auth | Kayıt Ol | Şirket ve kullanıcı açma | `handleRegister()` | `POST /auth/register` | Şirket oluşturulur ve otomatik giriş yapılır. | ✅ CONFIRMED |
| Portal / settings | Profil/Logo Kaydet | Profil güncelleme / Logo yükleme | `submitSaveProfile()` / `submitSaveLogo()` | `PUT /portal/users/:id` | Bilgiler veritabanında güncellenir. | ✅ CONFIRMED |
| Portal / billing | Bu Planı Seç | Ödeme yöntemi seçme veya Checkout başlatma | `initiatePlanPurchase()` | `GET /billing/payment-methods` | Ödeme yöntemleri modalını tetikler. | ⚠️ KISMEN ( CC kırık) |
| Portal / billing | Kredi Kartı Seçeneği | Kredi Kartı Checkout Formu Açma | `initiateIyzicoCheckout()` | `POST /billing/checkout` | **404 HATA (Endpoint `/checkout` backend'de mevcut değil, `/subscribe` var)** | ❌ ÇALIŞMIYOR |
| Portal / billing | Havale Bildir ve Tamamla | Banka Havale Bildirimi Gönderme | `submitBankTransferNotification()` | `POST /billing/request-bank-transfer` ve `POST /billing/notify-transfer` | Bekleyen onay kaydı oluşur. | ✅ CONFIRMED |
| Admin / transfers | Onayla | Havale Ödemesini Onaylama | `loadPendingTransfers()` bind | `PUT /admin/invoices/:id/approve` | **404 HATA (admin.controller'daki route `/invoices/:id/approve` fakat API `/admin/invoices/:id/approve` olarak mount edildi)** | ❌ ÇALIŞMIYOR |

---

## 6. Frontend → Backend API Matrix

| Arayüz Modülü | HTTP Method | Endpoint Path | Backend Controller Dosyası | DB Tablosu / İşlem | E2E Durum | Kanıt Seviyesi |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Website / Contact | `POST` | `/api/v1/support/public-contact` | `support.controller.ts` | `support_tickets` insert | ✅ Çalışıyor | CONFIRMED |
| Website / plans | `GET` | `/api/v1/billing/plans` | `billing.controller.ts` | `plans` (Redis list cache) | ✅ Çalışıyor | CONFIRMED |
| Portal / Auth | `POST` | `/api/v1/auth/login` | `auth.controller.ts` | `users`, `sessions` insert | ✅ Çalışıyor | CONFIRMED |
| Portal / Auth | `POST` | `/api/v1/auth/register` | `auth.controller.ts` | `companies`, `users`, `subscriptions` | ✅ Çalışıyor | CONFIRMED |
| Portal / Dashboard | `GET` | `/api/v1/portal/dashboard` | `portal.controller.ts` | `sales`, `orders` (RLS kapsamında) | ✅ Çalışıyor | CONFIRMED |
| Portal / Invoices | `GET` | `/api/v1/portal/invoices` | `portal.controller.ts` | `invoices` select | ✅ Çalışıyor | CONFIRMED |
| Portal / PDF | `GET` | `/api/v1/billing/invoices/:id/pdf` | `billing.controller.ts` | Fatura PDF okuma/stream | ✅ Çalışıyor | CONFIRMED |
| Portal / billing | `GET` | `/api/v1/billing/payment-methods` | `billing.controller.ts` | `payment_providers` select | ✅ Çalışıyor | CONFIRMED |
| Portal / billing | `POST` | `/api/v1/billing/request-bank-transfer` | `billing.controller.ts` | `invoices` & `bank_transfer_notifications` insert | ✅ Çalışıyor | CONFIRMED |
| Portal / billing | `POST` | `/api/v1/billing/notify-transfer` | `billing.controller.ts` | `bank_transfer_notifications` update | ✅ Çalışıyor | CONFIRMED |
| Portal / support | `POST` | `/api/v1/portal/tickets` | `portal.controller.ts` | `support_tickets` insert | ✅ Çalışıyor | CONFIRMED |
| Admin / companies | `GET` | `/api/v1/admin/companies` | `admin.controller.ts` | `companies` select | ✅ Çalışıyor | CONFIRMED |
| Admin / licenses | `POST` | `/api/v1/admin/licenses` | `admin.controller.ts` | `license_entitlements` insert | ✅ Çalışıyor | CONFIRMED |
| Admin / providers | `PUT` | `/api/v1/admin/payment-methods/:id` | `admin.controller.ts` | `payment_providers` update & Iyzico Test | ✅ Çalışıyor | CONFIRMED |

### UNUSED BACKEND ENDPOINTS
Aşağıdaki backend endpoint'leri tanımlanmış olmasına rağmen frontend (portal veya admin) tarafında doğrudan bir çağrısı bulunmamaktadır:
*   `POST /api/v1/support/tickets` (Yerine `/api/v1/portal/tickets` kullanılmaktadır)
*   `GET /api/v1/support/tickets` (Yerine `/api/v1/portal/tickets` kullanılmaktadır)
*   `GET /api/v1/support/tickets/:id` (Yerine `/api/v1/portal/tickets/:id` kullanılmaktadır)
*   `PATCH /api/v1/support/tickets/:id/status`
*   `POST /api/v1/support/tickets/:id/pin`

### BROKEN FRONTEND API CALLS
Arayüzlerin çağırdığı ancak backend üzerinde karşılığı bulunmayan veya route tanımlama hatası nedeniyle 404 dönen endpoint'ler:
*   `POST /api/v1/billing/checkout` (Kredi Kartı ödemesi başlatırken çağrılır; backend'de karşılık gelen endpoint `/api/v1/billing/subscribe` olarak adlandırılmıştır.)
*   `PUT /api/v1/invoices/:id/approve` (Havale onayında admin arayüzünün tetiklediği route; backend'de admin controller `/api/v1/admin` namespace'i altında mount edildiği için gerçek yol `/api/v1/admin/invoices/:id/approve` olmalıdır. Bu yüzden admin onay butonu 404 hatası verir!)

---

## 7. Authentication & Authorization Akışı
Sistem yetkilendirme ve kimlik doğrulama süreçleri JWT (JSON Web Token) ve Refresh Token Rotation (RTR) prensiplerine göre çalışır:

```text
    [Login Form] 
         ↓
    POST /api/v1/auth/login
         ↓
    [Auth Controller]
         ↓
    [Auth Service]  ----(Bcrypt / Legacy SHA-256 transparent upgrade)----> verifyPassword()
         ↓
    [Token Generation] 
    - Access Token (JWT, 15dk ömürlü, issuer: serenut.com, audience: serenut-pos)
    - Refresh Token (Sertifikalı Güvenli Random Byte)
         ↓
    [DB & Client Storage]
    - Session tablosuna refresh token kaydı atılır.
    - Client tarafında sessionStorage üzerinde 'portal_token' veya 'admin_token' olarak saklanır.
```

### Güvenlik Risk Analizi:
1.  **JWT_SECRET Kontrolü:** Sunucu başlangıcında `JWT_SECRET` değeri doğrulanır; 32 karakterden kısa veya tanımsız ise sunucu hata vererek çalışmayı durdurur.
2.  **Row Level Security (RLS) Bypass:** Modüller veritabanı işlemlerinde genellikle `runBypassingRLS` fonksiyonunu kullanır. Bu durum RLS mekanizmalarını tamamen devre dışı bıraktığından, kod seviyesinde doğru yetki kontrolleri yapılmazsa veri sızıntısı riski oluşturur.

---

## 8. Payment Provider Registry Mimarı Analizi
Ödeme sağlayıcıları dinamik olarak veritabanındaki `payment_providers` tablosunda tutulur. Bu tablo `schema_v37.sql` migrasyonu ile eklenmiştir:

*   **Registry Yapısı:** default olarak `bank_transfer` (Havale/EFT) ve `iyzico` (Kredi Kartı) sağlayıcıları tanımlanmıştır.
*   **Aktivasyon & Öncelik:** Admin panelinden `is_enabled` bayrağı ile dinamik olarak pasifleştirilip aktifleştirilebilirler.
*   **Secrets Güvenliği:** Iyzico API anahtarları gibi hassas veriler veritabanına kaydedilirken `crypto_helper.ts` içindeki `encryptSecret` (AES-256-GCM) fonksiyonu ile şifrelenir. Okunurken `decryptSecret` ile çözülür. Arayüze listelenirken `GET /payment-methods` endpoint'inde bu alanlar maskelenerek `'********'` şeklinde döner.
*   **Webhook Signature:** Iyzico webhook callback endpoint'lerinde (`/webhook/iyzico`) HMAC imza doğrulaması teoride mevcuttur ancak sandbox ortamlar için fallback esneklikleri bulunur.

---

## 9. Subscription (Abonelik) Sistemi
*   **Plan Kaynağı:** Fiyat paketleri veritabanındaki `plans` tablosundan dinamik olarak çekilir ve sunucu başlangıcında `plans:list` Redis anahtarına önbelleklenir.
*   **Abonelik Akışı:**
    1.  Kredi kartı ile başarılı ödeme yapıldığında abonelik durumu `active` olur, lisans ve cihaz limitleri anında tanımlanır.
    2.  Banka havalesi seçildiğinde abonelik `suspended`, son ödeme durumu `pending` olarak fatura ile birlikte bekletilir. Admin onayladığında aktif edilir.
*   **İptal & Grace Period:** Müşteri aboneliğini iptal ettiğinde (`/billing/cancel`), abonelik anında sonlanmaz. `cancel_at_period_end` değeri `true` set edilir ve dönem sonuna kadar erişime izin verilir. Ayrıca plan bazında tanımlı `offline_grace_hours` (varsayılan 72 saat) ile internet kesintilerinde cihazların çalışmaya devam etmesi sağlanır.

---

## 10. License (Lisans) Sistemi
Lisans doğrulama akışı cihazın ilk aktivasyonundan periyodik kalp atışı (heartbeat) kontrollerine kadar uçtan uca kriptografik koruma ile sağlanır:

```text
    Ödeme Onayı (SaaS)
         ↓
    CommercialLifecycleService (Lisans & Limit Tanımlama)
         ↓
    İstemci Aktivasyon İsteği (POST /api/v1/licenses/activate)
         ↓
    Veritabanı Kayıt & Donanım Parmak İzi Doğrulama (device_fingerprints)
         ↓
    Canonical JSON İmzası Oluşturma (RSA-SHA256 ile licenseInfo şifreleme)
         ↓
    İstemciye Yanıt Gönderme (İmza ve lisans verisi teslim edilir)
         ↓
    İstemci Tarafında Çevrimdışı RSA Doğrulaması (SHA256Digest ve Modulus doğrulama)
```

### Kriptografik Ayrıntılar:
*   İmzalama işleminde sunucudaki `RSA_PRIVATE_KEY` çevresi kullanılır. Bu anahtar yoksa güvenlik uyarısı verilerek gömülü geliştirici anahtarı (fallback developer key) kullanılır.
*   İstemci uygulaması (`lib/domain/services/license_service.dart`), imza doğrulaması için sunucudaki fallback anahtarın aynısı olan `_rsaModulusHex` ve `_rsaExponentHex` (65537) değerlerini barındırır.
*   Çevrimdışı doğrulama için istemci sistem saatinin geriye alınmasını (clock tampering) engellemek adına son işlem zamanı SQLite veritabanındaki `sales` ve `orders` tablolarının en son `created_at` zamanı ile karşılaştırılır.

---

## 11. Download & Sürüm OTA Sistemi
*   **Dosya Yönetimi:** Sürümler PostgreSQL'deki `app_versions` tablosunda takip edilir.
*   **Runtime 404 Hatası:** Windows için `win-v1-stable` id'li kayıt, diskte `public/website/downloads/SerenutOSSetup.exe` dosyasını arar. Ancak bu dosya dizinde mevcut olmadığından **Windows indirmeleri 404 hatası vermektedir.** Android APK dosyası (`serenut.apk`) ise diskte mevcuttur ve başarıyla indirilebilir.
*   **OTA (Over-the-Air) Güncelleme:** İstemciler `/api/v1/updates/check` endpoint'ini kullanarak platform ve mevcut versiyon kodlarını gönderir. Sunucu, `is_mandatory` (zorunlu güncelleme) ve `rollout_percentage` (kademeli dağıtım) kurallarına göre yeni bir güncelleme olup olmadığını JSON formatında döner.

---

## 12. User Journey Verification (Kullanıcı Senaryoları)

### Senaryo A — Yeni Müşteri Kaydı ve Havale Satın Alımı
1.  Kullanıcı fiyatlandırma sayfasından plan seçer -> `sessionStorage` set edilir.
2.  Kayıt formundan hesap açar -> `POST /auth/register` çalışır.
3.  Portal otomatik açılır -> Plan referansı ile havale modali tetiklenir.
4.  Banka bilgileri girilip onaylandığında -> `/request-bank-transfer` ve `/notify-transfer` çalışır. `bank_transfer_notifications` tablosuna `pending_review` kaydı atılır.
5.  *KOPAN NOKTA:* Admin panelinde yöneticinin onay butonuna basması durumunda `PUT /invoices/:id/approve` isteği atılır ancak route 404 döner. Lisans aktifleştirilemez.

### Senaryo B — POS Cihazı Aktivasyon ve Senkronizasyon
1.  Kullanıcı POS uygulamasını açar.
2.  Müşteri portalındaki lisans anahtarını girer.
3.  Uygulama `POST /api/v1/licenses/activate` endpoint'ine cihaz UUID ve donanım parmak izini gönderir.
4.  Sunucu cihaz limitini kontrol eder, limiti aşmamışsa kaydı onaylar ve RSA-SHA256 ile imzalanmış lisans paketini döner.
5.  POS uygulaması çevrimdışı imza doğrulamasını yaparak çalışmaya başlar ve delta sync kanalını açar.

---

## 13. Broken Integrations & Critical Bugs

> [!CAUTION]
> ### 1. Iyzico Callback Eşleştirme Hatası (İş Mantığı & Güvenlik Zafiyeti)
> `billing.controller.ts` içindeki `/iyzico/callback` endpoint'i, ödeme yapan iyzico token'ına göre işlem yapmak yerine **veritabanındaki en son eklenen pending faturayı alıp onaylamaktadır (`ORDER BY created_at DESC LIMIT 1`)**:
> ```typescript
> const tokenInfoRes = await runBypassingRLS("SELECT * FROM invoices WHERE status = 'pending' ORDER BY created_at DESC LIMIT 1");
> ```
> Bu durum, birden fazla müşteri aynı anda ödeme yapmaya çalıştığında faturanın ve aboneliklerin yanlış şirketlere onaylanmasına sebep olur.

> [!WARNING]
> ### 2. Windows Kurulum Dosyası Eksik (404 Hatası)
> Sunucu başlangıcında veritabanına Windows için kararlı sürüm kaydı (`win-v1-stable`) atılır ve dosya yolu `public/website/downloads/SerenutOSSetup.exe` olarak gösterilir. Ancak bu dosya disk üzerinde fiziksel olarak mevcut olmadığından indirme istekleri 404 hatası vermektedir.

> [!WARNING]
> ### 3. Kredi Kartı Checkout API 404 Hatası
> Müşteri portalı `billing.js` dosyası kredi kartı ödemesini başlatmak için `/billing/checkout` endpoint'ine POST isteği göndermektedir. Ancak backend tarafında bu isimde bir endpoint tanımlanmamıştır; bunun yerine `/api/v1/billing/subscribe` endpoint'i mevcuttur. Bu durum kredi kartı satın alım akışını tamamen bozmaktadır.

> [!IMPORTANT]
> ### 4. Admin Paneli Havale Onay 404 Hatası
> Admin panelindeki havale onay butonu `PUT /invoices/:id/approve` isteği atmaktadır. Ancak backend tarafındaki route `/admin/invoices/:id/approve` altında tanımlıdır. Namespace uyuşmazlığı nedeniyle onay işlemi 404 vermektedir ve yöneticiler arayüzden onaylama yapamamaktadır.

---

## 14. Dead Code & Unused APIs
1.  **Eski Bildirim İşçisi:** `server/src/modules/notification/notification_worker.ts` dosyası, BullMQ entegrasyonu sonrasında kullanılmayan eski setInterval polling kodlarını barındırmaktadır. Sadece eski doğrulama testleri tarafından referans alınmaktadır, bootstrap sürecinde aktif değildir.
2.  **Kullanılmayan Support API Endpointleri:** `support.controller.ts` içindeki doğrudan ticket yönetim yolları (`/support/tickets`) ne portal ne de admin tarafında çağrılmamaktadır. Portal `/portal/tickets`, admin ise `/admin/tickets` yollarını kullanmaktadır.

---

## 15. Final Feature Status Matrix

| Özellik Adı (Feature) | UI Durumu | API Entegrasyonu | Backend Service | Veritabanı Etkisi | Dış Servis (External) | E2E Durumu |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| dynamic plans listing | Var | `/billing/plans` | Warmed up via Redis | `plans` okuma | Yok | ✅ OK (Confirmed) |
| public contact form | Var | `/support/public-contact` | support ticket registration | `support_tickets` | SMTP (mock fallback) | ✅ OK (Confirmed) |
| bank transfer request | Var | `/billing/request-bank-transfer` | reference code generator | `invoices` & `bank_transfer_notifications` | Yok | ✅ OK (Confirmed) |
| credit card checkout | Var | **KIRIK (404 `/checkout` vs `/subscribe`)** | `IyzicoService` | Yok (Hata döner) | Iyzico | ❌ Kırık |
| admin transfer approve | Var | **KIRIK (404 namespace mismatch)** | `activatePaidSubscription` | `subscriptions`, `license_entitlements` | Yok (Hata döner) | ❌ Kırık |
| license activation | Var | `/licenses/activate` | RSA-SHA256 imzalama | `device_activations`, `device_fingerprints` | Yok | ✅ OK (Confirmed) |
| OTA update check | Var | `/updates/check` | mandatory & rollout percentage checker | `app_versions` | Yok | ✅ OK (Confirmed) |
| public release download | Var | `/releases/download/:id` | file download stream | `app_versions` | Yok | ⚠️ Windows 404 |

---

## 16. Priority Findings (Öncelikli Bulgular)

### P0 — Kritik (Acil Müdahale Gerekenler)
*   **Windows Setup 404:** `public/website/downloads/SerenutOSSetup.exe` dosyasının sunucuya yüklenmesi gerekmektedir. Aksi takdirde Windows indirmeleri başarısız olmaya devam edecektir.
*   **Iyzico Callback Race Condition:** Callback endpoint'indeki `ORDER BY created_at DESC LIMIT 1` mantığı acilen iyzico'dan dönen token/conversationId eşleştirmesi ile faturayı spesifik olarak sorgulayacak şekilde değiştirilmelidir.

### P1 — Yüksek
*   **Checkout Endpoint Uyuşmazlığı:** Portal `billing.js` içindeki `/billing/checkout` istek yolu `/billing/subscribe` olarak revize edilmelidir.
*   **Admin Approve Route Uyuşmazlığı:** Admin panelindeki havale onay API çağrı yolu `/admin/invoices/:id/approve` şeklinde güncellenmelidir.

### P2 — Orta
*   **Dead Code Temizliği:** Eski `notification_worker.ts` polling mekanizması ve kullanılmayan `/support/tickets` yolları projeden arındırılmalıdır.
*   **RLS Bypass İyileştirmesi:** RLS bypass kullanan fonksiyonlar veri güvenliği denetiminden geçirilmeli ve tenant izolasyonunun sızdırmazlığı doğrulanmalıdır.

### P3 — Düşük
*   **SEO Sitemap URL Harmonization:** `sitemap.xml` içindeki `.html` uzantılı adresler, sitenin kullandığı temiz URL'ler (`/plans`, `/platform`) ile eşitlenmelidir.
