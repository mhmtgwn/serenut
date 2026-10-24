# Serenut OS — Sistem Mimarisi, Operasyonel Kullanım & Sorun Giderme Ana El Kitabı (Master Operating Manual)

> **Belge Sürümü:** 3.0.0 (The Definitive Master Architecture & Operations Manual)  
> **Hedef Sistem:** Serenut OS İstemcisi (Desktop Windows / Android) & Serenut Cloud (Node.js/TypeScript VPS & PostgreSQL)  
> **Amaç:** Kayıttan girişe, ürün yönetiminden cariye, donanımdan senkronizasyona, GİB e-Arşivden WhatsApp Business / Evolution QR entegrasyonuna, Patron Web Portalından Müşteri İkinci Ekranına, P2P görsel ağından kriptografik OTA sürüm imzalamaya kadar sistemin istisnasız tüm parçalarının ne şekilde çalıştığını açıklayan, sorun anında doğrudan referans alınabilecek nihai operasyonel ve teknik el kitabı.

---

## İÇİNDEKİLER

1. [Sistem Mimarisi & Temel İlkeler](#1-sistem-mimarisi--temel-ilkeler)
2. [Kullanıcı, Organizasyon (Tenant) & Cihaz Yönetimi (Kayıttan Girişe)](#2-kullanıcı-organizasyon-tenant--cihaz-yönetimi-kayıttan-girişe)
3. [Ürün Kataloğu, Fiyatlandırma, Barkodlar & Stok Motoru](#3-ürün-kataloğu-fiyatlandırma-barkodlar--stok-motoru)
4. [Müşteri, Cari Hesap, Veresiye, Senet & Defter Motoru (Ledger Engine)](#4-müşteri-cari-hesap-veresiye-senet--defter-motoru-ledger-engine)
5. [Kasa Satış, Sepet, Ödeme Motoru & Sepet Kurtarma](#5-kasa-satış-sepet-ödeme-motoru--sepet-kurtarma)
6. [Senkronizasyon Motoru (Sync V4 — Offline-First Replication)](#6-senkronizasyon-motoru-sync-v4--offline-first-replication)
7. [Donanım Entegrasyonları & Ağ Paylaşımlı Donanım (Hardware Layer)](#7-donanım-entegrasyonları--ağ-paylaşımlı-donanım-hardware-layer)
8. [Yerel Ağda Eşler Arası (P2P) Ürün Görseli Dağıtımı (LAN Peer Service)](#8-yerel-ağda-eşler-arası-p2p-ürün-görseli-dağıtımı-lan-peer-service)
9. [e-Dönüşüm & GİB e-Arşiv / e-Fatura Portalı (0 TL Maliyetli İstemci)](#9-e-dönüşüm--gib-e-arşiv--e-fatura-portalı-0-tl-maliyetli-istemci)
10. [WhatsApp Bildirim & İletişim Motoru (Evolution API & Meta Cloud)](#10-whatsapp-bildirim--iletişim-motoru-evolution-api--meta-cloud)
11. [Android SIM Kartlı SMS Ağ Geçidi (Yerel GSM Modemi)](#11-android-sim-kartlı-sms-ağ-geçidi-yerel-gsm-modemi)
12. [Patron Web Portalı & Canlı Ciro İzleme (Realtime Engine)](#12-patron-web-portalı--canlı-ciro-izleme-realtime-engine)
13. [Müşteri İkinci Ekranı (Customer Facing Display)](#13-müşteri-ikinci-ekranı-customer-facing-display)
14. [Yedekleme, Geri Yükleme, Lisanslama & Veri Aktarımı (Migration)](#14-yedekleme-geri-yükleme-lisanslama--veri-aktarımı-migration)
15. [Dağıtım, Güncelleme & Kriptografik İmzalama Standartları](#15-dağıtım-güncelleme--kriptografik-imzalama-standartları)
16. [Gözlemlenebilirlik, Telemetri & Loglama](#16-gözlemlenebilirlik-telemetri--loglama)
17. [Sorun Giderme Runbook'u & Acil Müdahale Prosedürleri](#17-sorun-giderme-runbooku--acil-müdahale-prosedürleri)
18. [Genişletilmiş Master Cheat Sheet Tablosu](#18-genişletilmiş-master-cheat-sheet-tablosu)

---

## 1. SİSTEM MİMARİSİ & TEMEL İLKELER

Serenut OS; perakende satış, market, kuruyemiş, şarküteri ve toptan ticaret yapan işletmeler için tasarlanmış, **"Offline-First" (Önce Çevrimdışı)** ve **"Zero-Loss Financial Guarantee" (Sıfır Finansal Kayıp)** prensiplerine dayalı dağıtık bir kurumsal işletim sistemidir.

```mermaid
graph TD
    subgraph "İSTEMCİ KATMANI (Windows / Android)"
        UI[Sunum Katmanı - Flutter / Riverpod]
        Domain[Domain Modelleri & Use Case'ler]
        SalesEngine[Kasa Satış & Checkout FSM]
        Ledger[Çift Taraflı Defter Motoru]
        HW[Donanım: Yazıcı, Terazi, Barkod, Paylaşımlı Cihazlar]
        P2P[P2P Görsel Dağıtımı: UDP 48732 / HTTP 48731]
        CustDisp[Müşteri 2. Ekranı - HDMI/VFD]
        GIB[GİB e-Arşiv Portalı İstemcisi]
        SMS[SIM Kartlı SMS Gateway]
        SQLite[(Yerel Standart SQLite)]
        Outbox[(Outbox Tablosu)]
    end

    subgraph "İLETİŞİM KANALLARI"
        HTTPS[HTTPS REST API / v1 / v4]
        WSS[WebSocket / Realtime Events]
        LAN[Yerel Ağ / LAN Broadcast]
    end

    subgraph "BULUT / VPS KATMANI"
        Gateway[Node.js / Express Gateway]
        SyncV4[Sync V4 Senkronizasyon Motoru]
        AuthSvc[Kimlik Doğrulama & Tenant İzolasyonu]
        WAPIEvo[WhatsApp Evolution API - QR Gateway]
        WAPIMeta[WhatsApp Meta Cloud API - WABA]
        Realtime[Realtime WebSocket Hub]
        WebPortal[Patron Web Yönetim Portalı]
        OTA[OTA Sürüm Dağıtım & İmza Doğrulama]
        Postgres[(PostgreSQL Ana Veritabanı)]
    end

    UI --> Domain
    Domain --> SalesEngine
    Domain --> Ledger
    Domain --> HW
    Domain --> CustDisp
    Domain --> GIB
    Domain --> SMS
    HW --> LAN
    P2P --> LAN
    SalesEngine --> SQLite
    Ledger --> SQLite
    SQLite --> Outbox
    Outbox --> HTTPS
    HTTPS --> Gateway
    WSS --> Realtime
    Realtime --> WebPortal
    Gateway --> SyncV4
    Gateway --> AuthSvc
    Gateway --> WAPIEvo
    Gateway --> WAPIMeta
    Gateway --> OTA
    SyncV4 --> Postgres
```

### 1.1. Temel Mimari Kararlar

1. **SQLCipher'ın Kaldırılması & Standart SQLite ([AGENTS.md Kural 1](file:///c:/Users/ecz/proje/shaman/shaman_new/.agents/AGENTS.md)):**
   - Mobil (Android) ve masaüstü (Windows) istemcilerinde şifreli `sqflite_sqlcipher` motoru tamamen kaldırılmıştır.
   - Yerel veritabanı motoru standart, şifresiz `sqflite` / `sqflite_common_ffi`'dir.
   - Veri güvenliği işletim sistemi izinleri (Android `/data/user/0/...` sandbox ve Windows `%APPDATA%` kullanıcı ACL'leri) ve VPS tarafındaki şifreli PostgreSQL bağlantısı ile sağlanır.
2. **Kuruş Bazlı Finansal Bütünlük (MoneyCents):**
   - Sistemde hiçbir para birimi SQLite `REAL` veya Dart/TS `double` olarak saklanamaz ve hesaplanamaz.
   - Tüm tutarlar, bakiyeler ve fiyatlar **kuruş cinsinden tam sayı (Integer)** olarak saklanır (ör. 100,50 TL = `10050` kuruş).
   - Bölme ve oran hesaplamalarında bankacılık standartlarında **Half-Up (0.5 ve üzeri yukarı)** yuvarlama uygulanır.
3. **Append-Only Defter (Ledger) Modeli:**
   - Cari hesaplarda hiçbir bakiye elle doğrudan `UPDATE` edilemez.
   - Defter kayıtları (`ledger_entries`) yalnızca eklenir (append-only); hata düzeltmeleri zıt yönlü düzeltme kaydı (`correction` / `reversal`) ile gerçekleştirilir.
4. **Offline-First Kesintisiz Satış:**
   - İnternet bağlantısı kopsa dahi istemci yerel SQLite veritabanı üzerinde 100 milisaniye altında tam hızla satış yapabilir, tahsilat alabilir, fiş kesebilir ve terazi okuyabilir.
   - Bağlantı geri geldiğinde `Sync V4` motoru biriken hareketleri kayıpsız olarak sunucuya aktarır.

---

## 2. KULLANICI, ORGANİZASYON (TENANT) & CİHAZ YÖNETİMİ (KAYITTAN GİRİŞE)

### 2.1. Organizasyon (Tenant) & Şube Yapısı

Her işletme bir `tenant` (kiracı) olarak izole edilir.
- **Tenant ID:** Benzersiz UUIDv4 (ör. `ten-019a28c3-4d56-7890-abcd-ef0123456789`).
- **Veri Ayrımı:** VPS üzerindeki PostgreSQL tablolarında (`tenants`, `users`, `products`, `customers`, `ledger_entries`, `sales`) her kayıtta zorunlu `tenant_id` kolonu bulunur ve Row-Level / Multi-Tenant indeksleri ile korunur.
- **Şube ve Depolar (`branches`):** Bir firmanın birden fazla kasası veya deposu olabilir. Her kasa bir şubeye bağlıdır.

### 2.2. Kullanıcı Kaydı & İlk Kurulum Akışı

```mermaid
sequenceDiagram
    autonumber
    actor Admin as İşletme Yetkilisi
    participant App as Serenut OS Uygulaması
    participant API as VPS /api/v1/auth
    participant DB as PostgreSQL

    Admin->>App: Şirket Adı, E-posta, Telefon, Şifre girer
    App->>API: POST /register (tenant & user payload)
    API->>DB: INSERT INTO tenants, INSERT INTO users (SuperAdmin)
    API->>DB: INSERT INTO default_categories, default_settings
    API-->>App: 201 Created (tenant_id, user_id, tokens)
    App->>App: Yerel SQLite veritabanını ilklendir
    App->>App: Varsayılan şablonları oluştur (Kasa 1, Ana Şube)
```

### 2.3. Cihaz Aktivasyonu & Donanım Parmak İzi (`device_fingerprint`)

Bir cihazın bir kasayı yönetebilmesi için organizasyon ile eşleştirilmesi gerekir:
1. İstemci ilk açılışında CPU ID, Anakart Seri No, Disk UUID ve MAC adresinden kriptografik bir `device_fingerprint` üretir ([DeviceFingerprintService](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/device_fingerprint_service.dart)).
2. Yönetici portalından veya ana kasadan bir **Cihaz Aktivasyon Kodu / Eşleştirme Tokeni** alınır.
3. İstemci `POST /api/v1/devices/activate` isteği ile aktivasyon kodunu ve donanım parmak izini gönderir.
4. Sunucu cihazı doğrular ve cihaza özel `device_token` tahsis eder. Bu token yerel SQLite `app_settings` tablosunda ve güvenli depolama alanında saklanır.

### 2.4. Giriş (Login) & Oturum Yönetimi

Sistemde iki seviyeli kimlik doğrulama bulunur:

#### A. Yönetici / İlk Kurulum Girişi (E-posta + Şifre)
- `POST /api/v1/auth/login`
- Yanıt: `accessToken` (kısa ömürlü, 15 dk - 1 saat), `refreshToken` (uzun ömürlü, 30 gün), `user` ve `permissions`.
- Token'lar istemcide `SecureStorage` ve yerel SQLite oturum tablosunda tutulur.

#### B. Kasiyer Hızlı Giriş (4 Haneli PIN Kodu)
- Kasa operasyonlarında kasiyer değişimi çok hızlı olmalıdır.
- Kullanıcının 4 haneli PIN kodu yerel SQLite veritabanında tuzlanmış (salted) PBKDF2/Argon2 özeti olarak saklanır.
- **Offline PIN Doğrulama:** İnternet olmasa dahi kasiyer PIN kodunu girdiğinde yerel veritabanındaki hash ile karşılaştırılır ve anında oturum açılır ([PasswordHashService](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/password_hash_service.dart)).

### 2.5. Rol Bazlı Yetkilendirme (RBAC)

| Rol | Yetkiler | Kısıtlamalar |
|---|---|---|
| **SuperAdmin / Firma Sahibi** | Tüm şubeler, kullanıcı açma, fiyat değiştirme, mali raporlar, silme/iptal işlemleri | Sınırsız |
| **Müdür (Manager)** | Kendi şubesinde stok girişi, fiyat görme, zayi/fire kaydı, iskonto yapabilme | Şirket silme ve lisans yönetimi kapalı |
| **Kasiyer (Cashier)** | Satış yapma, tahsilat alma, fiş yazdırma, ürün arama, müşteri bakiyesi görme | Mali raporları göremez, kısıtlı iskonto limiti, ürün fiyatını elden değiştiremez |
| **Depocu (Stock Clerk)** | Mal kabulü, sayım, stok hareketi girişi | Satış yapamaz, cari defter bakiyelerini göremez |

---

## 3. ÜRÜN KATALOĞU, FİYATLANDIRMA, BARKODLAR & STOK MOTORU

### 3.1. Veri Yapısı (`products`, `barcode_units`, `categories`)

- `products`:
  - `id`: UUID (ör. `prod-xxx`).
  - `tenant_id`: Organizasyon kimliği.
  - `name`: Ürün adı (ör. "Kavrulmuş Fındık 500g").
  - `category_id`: Kategori referansı.
  - `sale_price_cents`: Satış fiyatı (kuruş).
  - `purchase_price_cents`: Alış/maliyet fiyatı (kuruş).
  - `vat_rate`: KDV oranı (ör. 1, 10, 20).
  - `unit_type`: Birim (`piece` - Adet, `kg` - Kilogram, `gram`, `liter`).
  - `stock_tracking`: Boolean (Stok takip edilsin mi?).
  - `current_stock_grams_or_pieces`: Mevcut stok miktarı.
  - `is_weighed`: Tartılı ürün mü? (Terazili mi?).
  - `deleted_at`: Tombstone silme damgası.
- `barcode_units`:
  - Bir ürüne birden fazla barkod atanabilir (ör. koli barkodu, tekil barkod, tedarikçi barkodu).
  - `barcode`: EAN-13, EAN-8 veya dahili barkod.
  - `multiplier`: Adet çarpanı (ör. 1 koli = 24 adet).

### 3.2. Para & Kuruş Modeli (`MoneyCents`) Kuralları

Finansal tutarlarda **Floating Point KESİNLİKLE YASAKTIR**.
```dart
// DOĞRU:
final int priceCents = 14950; // 149.50 TL
final int quantityGrams = 450; // 450 gram
// 1 kg = 1000 gram
// Tutar = (14950 * 450 + 500) ~/ 1000 = 6728 kuruş (67.28 TL) (Half-Up Yuvarlama)
final int totalCents = ((priceCents * quantityGrams) + 500) ~/ 1000;

// YANLIŞ:
double price = 149.50;
double total = price * 0.450; // 67.27500000000002 -> Finansal kayıp ve çakışma riski!
```

### 3.3. Barkod Ekosistemi & Tartılı/Terazili Ürün Çözümlemesi

Sistem barkod okuyucudan gelen girdiyi anında analiz eder:

```mermaid
graph TD
    Input[Barkod Okundu] --> CheckLen{13 Hane & 27 veya 28 ile mi başlıyor?}
    CheckLen -- Evet --> ParseScale[Tartılı Terazi Barkodu Çözümleyici]
    ParseScale --> Extract[27 + PPPPP Ürün Kodu + WWWWW Gramaj + C Checksum]
    Extract --> QueryProd[Ürün Kodunu Veritabanında Ara]
    QueryProd --> Calc[Gramaj x Birim Fiyat ile Sepete Ekle]
    CheckLen -- Hayır --> QueryBarcode[Doğrudan barcode_units Tablosunda Ara]
    QueryBarcode --> AddPiece[Ürünü 1 Adet Olarak Sepete Ekle]
```

- **Standart Barkodlar:** EAN-13, EAN-8, Code 128, QR kodları doğrudan `barcode_units` tablosundan eşleştirilir.
- **Terazi Barkod Formatı (`27` ve `28` Serisi):**
  - Prefix: `27` veya `28` (2 hane)
  - PLU / Ürün Kodu: 5 hane (ör. `00142`)
  - Ağırlık / Değer: 5 hane (ör. `00450` -> 450 gram)
  - Kontrol Hanesi (Check Digit): 1 hane
  - Sonuç: Kasiyer teraziden basılmış etiketi okuttuğunda ekrana dokunmadan 450 gram fındık sepetine anında kuruşu kuruşuna eklenir.

### 3.4. Stok Hareketleri (Inventory Ledger)

Her stok değişimi bir `stock_movements` kaydı doğurur:
1. **`sale`:** Kasa satışı onaylandığında ilgili ürünlerin stoğu satılan miktar kadar düşürülür.
2. **`return`:** Müşteri iade getirdiğinde stok otomatik olarak artırılır.
3. **`purchase`:** Mal kabul / alış faturası girildiğinde stok artar ve alış maliyet fiyatı güncellenir.
4. **`waste` (Fire/Zayi):** Bozulan, kırılan ürünler stoktan açıklama ile düşülür.
5. **`count_adjustment` (Sayım Düzeltmesi):** Periyodik fiziki sayım sonucunda tespit edilen fark sisteme işlenir.

---

## 4. MÜŞTERİ, CARİ HESAP, VERESİYE, SENET & DEFTER MOTORU (LEDGER ENGINE)

### 4.1. Çift Girişli Append-Only Defter Modeli

Müşteri bakiyesi asla `customers.balance = 5000` şeklinde elle güncellenmez. Tüm mali geçmiş `ledger_entries` tablosunda sıralı ve değiştirilemez bir defter olarak tutulur.

```mermaid
graph LR
    subgraph "LEDGER_ENTRIES (Append-Only Defter)"
        E1["+10.000 Kuruş (sale_credit / Veresiye Satış)"]
        E2["-4.000 Kuruş (collection / Nakit Tahsilat)"]
        E3["+2.000 Kuruş (promissory_returned / Senet İadesi)"]
    end
    E1 --> Sum[Kanonik Bakiye Formülü]
    E2 --> Sum
    E3 --> Sum
    Sum --> Balance["Bakiye = +8.000 Kuruş (80,00 TL Borçlu)"]
```

### 4.2. Kanonik Bakiye Formülü

Tüm sistem genelinde (Dart istemci, SQLite sorguları, Node.js VPS ve PostgreSQL görünümünde) geçerli **TEK VE DEĞİŞMEZ** formül:

$$\text{balance\_cents} = \sum \begin{cases} +\text{amount\_cents}, & \text{eğer type} \in ('sale\_credit', 'manual\_debt', 'promissory\_returned') \\ -\text{amount\_cents}, & \text{diğer tüm tiplerde} ('collection', 'sale\_return\_credit', 'payment') \end{cases}$$

- **Pozitif Bakiye ($> 0$):** Müşteri işletmeye **BORÇLU**dur.
- **Negatif Bakiye ($< 0$):** Müşterinin işletmede **ALACAĞI / AVANSI** vardır.
- **Sıfır Bakiye ($= 0$):** Hesap kapalıdır.

> [!IMPORTANT]
> **Değiştirilemezlik (Append-Only) Kuralı:**  
> Bir defter kaydı oluştuktan sonra asla `DELETE` veya `UPDATE` edilemez. Yanlış girilen bir tahsilat veya borç kaydı için zıt yönlü yeni bir kayıt (`entry_type = 'correction'` veya `'reversal'`) eklenir.

### 4.3. Veresiye (Açık Hesap) Satış Akışı

1. Kasa ekranında sepete ürünler eklenir.
2. Ödeme adımında "Veresiye / Cari" seçildiğinde sistem **Müşteri Seçimini Zorunlu Kılar**. Müşteri seçilmemişse işlem bloke edilir.
3. Müşterinin açık hesap limiti kontrol edilir (limit tanımlıysa ve aşılıyorsa yönetici onayı istenir).
4. Satış tamamlandığında tek bir atomik SQLite transaction içinde:
   - `sales` kaydı oluşturulur (`payment_status = 'pending'`).
   - `sale_payments` tablosuna `veresiye` tipi ödeme işlenir.
   - `ledger_entries` tablosuna `sale_credit` kaydı eklenir.
   - `customers` tablosundaki `balance_cents` önbelleği kanonik formülle artırılır.
   - Müşteriye SMS/WhatsApp bilgi mesajı göndermek üzere kuyruğa (`outbox`) olay yazılır.

### 4.4. Senet (Promissory Notes) Yaşam Döngüsü

Senetli satışlarda senetler ayrı bir portföy tablosunda (`promissory_notes`) takip edilir:
- **`pending` (Beklemede / Kasada):** Vadesi gelmemiş senet.
- **`collected` (Tahsil Edildi):** Müşteri ödemesini yaptı; cari hesaba tahsilat işlenir, kasa giriş kaydı doğar.
- **`returned_protest` (Protesto / İade Edildi):** Vadesinde ödenmeyen senet. Cari hesaba `promissory_returned` tipi ile otomatik borç yazılır.
- **`legal` (İcrada / Hukukta):** Hukuki takibe intikal etmiş senetler.

---

## 5. KASA SATIŞ, SEPET, ÖDEME MOTORU & SEPET KURTARMA

### 5.1. Checkout Sonlu Durum Makinesi (Finite State Machine)

Satış süreci belirli durumlardan geçer ve her durum geçişi sıkı kurallara bağlıdır:

```mermaid
stateDiagram-v2
    [*] --> Idle: Kasa Açık / Beklemede
    Idle --> CartBuilding: İlk Ürün Eklendi
    CartBuilding --> CartBuilding: Ürün Ekle / Sil / Miktar Değiştir
    CartBuilding --> PaymentSelection: "Ödeme Al" Butonu
    PaymentSelection --> Processing: Nakit / Kart / Veresiye Seçildi
    Processing --> Completed: Ödeme Tamamlandı & Fiş Basıldı
    Processing --> Failed: Ödeme Hatası / Donanım Hatası
    Failed --> PaymentSelection: Yeniden Dene / Ödeme Değiştir
    CartBuilding --> Cancelled: "Sepeti İptal Et"
    PaymentSelection --> CartBuilding: "Sepete Geri Dön"
    Completed --> Idle: Sonraki Satışa Hazır
    Cancelled --> Idle: Sonraki Satışa Hazır
```

### 5.2. Sepet Kilitleme (`cart_lock`) & Çakışma Koruması

Eşzamanlı işlemleri engellemek için satış başlatıldığı anda sepet bellek üzerinde kilitlenir (`cart_lock = true`).
- Barkod okuyucu veya kasiyer ikinci bir tuşa bassa dahi işlem devam ederken sepet manipüle edilemez.
- İşlem SQLite transaction seviyesinde `runInTransaction` ile yürütülür. Herhangi bir adımda (ör. stok yetersizliği, donanım çökmesi) hata oluşursa tüm transaction `ROLLBACK` edilir; hayalet satış veya açıkta kalan ödeme engellenir.

### 5.3. Elektrik Kesintisi & Kapanma Koruması (`CartPersistenceService`)

Kasiyer 15 kalem ürün okuttuğu anda elektrik kesilirse veya bilgisayar aniden kapanırsa ne olur?
- [CartPersistenceService](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/cart_persistence_service.dart), sepet durumunu bellekte tutarken aynı zamanda her değişiklikte yerel diske atomik JSON snapshot olarak yazar (`active_cart_recovery.json`).
- Bilgisayar tekrar açıldığında Serenut OS bu dosyayı okur:
  - "Bekleyen açık bir sepet bulundu. Kurtarılsın mı?" uyarısı verir.
  - Kasiyer tek tuşla 15 kalem ürünü ve seçili müşteriyi aynen ekrana geri getirir; müşteriyi kasada bekletmeden kaldığı yerden devam eder.

### 5.4. Ödeme Yöntemleri & Karma (Split) Ödeme

Sistem esnek ödeme kombinasyonlarını destekler:
1. **Nakit:** Kasiyer alınan tutarı girer, para üstü ekranda büyük puntolarla gösterilir, nakit çekmecesi otomatik açılır (`\x1b\x70...`).
2. **Kredi Kartı / Harici POS:** Banka terminalinden geçiş yapılır; referans / slip no girilebilir.
3. **Veresiye:** Seçilen müşterinin cari hesabına borç kaydedilir.
4. **Karma (Split) Ödeme:** Tek faturada birden çok yöntem:
   - Örnek: Toplam 2.000 TL -> 500 TL Nakit + 1.000 TL Kredi Kartı + 500 TL Veresiye.
   - Her ödeme parçası `sale_payments` tablosuna ayrı ayrı kaydedilir; ödemelerin toplamı sepet toplamına eşit olmadan satış kapatılamaz.

### 5.5. İade ve Değişim Akışı

- **Satış Fişinden İade:** Müşteri fiş barkodunu getirdiğinde geçmiş satış çağrılır. İade edilmek istenen satırlar seçilir.
- **Belgesiz / Serbest İade:** Ürün ve miktar seçilerek iade fişi kesilir.
- **Mali Yansıma:**
  - İade edilen ürünler stoğa otomatik geri alınır (`stock_movements.type = 'return'`).
  - İade bedeli nakit ödendiyse kasadan nakit çıkışı (`cash_transactions.type = 'refund'`) yapılır.
  - Veresiye satışın iadesiyse müşterinin cari hesabına alacak (`sale_return_credit`) yazılır.

### 5.6. Gün Sonu ve Z-Raporu (Kasa Kapanışı)

1. **Gün Açılışı:** Kasaya sabah bırakılan devir nakit girilir.
2. **Gün İçi:** Kasa girişleri (tahsilat, nakit ekleme) ve çıkışları (masraf ödemesi, mal alımı) kaydedilir.
3. **Gün Sonu Kapanışı (Z-Raporu):**
   - Kasiyer kasadaki fiziki parayı sayar ve girer.
   - Sistem gün boyunca yapılan:
     - Toplam Nakit Satışlar
     - Toplam Kredi Kartı Satışları
     - Toplam Veresiye Satışlar
     - Toplam Tahsilatlar ve Masrafları hesaplar.
   - Beklenen Kasa ile Sayılan Kasa karşılaştırılır; varsa **Kasa Fazlası** veya **Kasa Eksiği** raporda belirtilir.
   - Z-Raporu termal yazıcıdan yazdırılır, `daily_registers` tablosunda kilitlenerek gün kapatılır ve **otomatik olarak işletme sahibinin WhatsApp'ına özet mesaj olarak gönderilir**.

---

## 6. SENKRONİZASYON MOTORU (SYNC V4 — OFFLINE-FIRST REPLICATION)

### 6.1. Mimari Prensip: Dağıtık Outbox Deseni

Tüm istemci değişiklikleri (satış, stok, müşteri, defter) yerel veritabanına kaydedilirken aynı transaction içinde `outbox` tablosuna bir mutasyon olayı olarak yazılır.

```mermaid
sequenceDiagram
    autonumber
    participant Kasa as İstemci (SQLite)
    participant Outbox as outbox Tablosu
    participant Worker as Sync Push Worker
    participant Cloud as VPS (Node.js + PostgreSQL)

    Note over Kasa,Outbox: 1. Satış Yapılır (Çevrimdışı veya Çevrimiçi)
    Kasa->>Outbox: INSERT mutation (idempotency_key, payload, seq)
    Note over Worker: 2. Worker periyodik uyanır / ağ kontrol eder
    Worker->>Outbox: SELECT pending mutations LIMIT 50
    Worker->>Cloud: POST /api/v4/sync/push (mutations array)
    Note over Cloud: 3. Sunucu İdempotent Doğrulama yapar (payloadDeepEqual)
    Cloud->>Cloud: PostgreSQL INSERT / UPDATE & server_seq ata
    Cloud-->>Worker: 200 OK (processed_ids, conflicts, server_timestamp)
    Worker->>Outbox: UPDATE status = 'synced' WHERE id IN (...)
```

### 6.2. Sunucu İdempotency & `payloadDeepEqual` Koruması

Ağ kopması durumunda istemci aynı mutasyonu tekrar gönderebilir.
- Sunucu `idempotency_key` (veya `mutation_id`) üzerinden geçmişi kontrol eder.
- **Kritik Çakışma Önleyici (`payloadDeepEqual`):** PostgreSQL `jsonb` kolonları JSON nesnelerinin anahtarlarını dahili olarak alfabetik ve uzunluğa göre yeniden sıralar. Düz `JSON.stringify` karşılaştırması sahte çakışma (`conflict`) üreteceği için `payloadDeepEqual` recursive fonksiyonu ile anlamsal eşitlik kontrol edilir. Aynı mutasyon geldiğinde hata fırlatılmaz, `already_processed` olarak onaylanır.

### 6.3. Pull Akışı (Sunucudan İstemciye Çekme)

- İstemci son aldığı `server_seq` numarasını bilir.
- `GET /api/v4/sync/pull?since_seq=1480` çağrısı yapar.
- Sunucu, 1480'den sonra organizasyona ait diğer cihazlar veya web portalından yapılan değişiklikleri döner.
- İstemci gelen verileri yerel SQLite tablolarına yansıtır (`SyncV4PullAdapter`).

### 6.4. Çakışma Çözümü (Conflict Resolution)

- **Kural:** Sunucu zaman damgası otoritesi ile Deterministik **Last-Write-Wins (LWW)** uygulanır.
- **Silinmeler (Tombstone):** Hiçbir satır fiziksel silinmez (`DELETE FROM ...` yapılmaz). `deleted_at = timestamp` alanı doldurulur ve diğer cihazlara bu şekilde yayılır.

---

## 7. DONANIM ENTEGRASYONLARI & AĞ PAYLAŞIMLI DONANIM (HARDWARE LAYER)

### 7.1. Termal Fiş Yazıcısı (ESC/POS)

Termal yazıcılar müşteri fişi, bilgi fişi, mutfak sipariş fişi ve gün sonu Z-raporu dökümünde kullanılır.
- **Protokol:** Raw ESC/POS komutları.
  - İnisiyalizasyon: `\x1b\x40` (`ESC @`)
  - Kağıt Kesme: `\x1d\x56\x00` (`GS V 0` Full Cut) veya `\x1d\x56\x01` (Partial Cut)
  - Çekmece Darbesi (Cash Drawer Kick): `\x1b\x70\x00\x19\xfa`
- **Bağlantı Kanalları:**
  - **USB:** Windows Spooler (`win32` API üzerinden Raw veri gönderme).
  - **Ağ (Ethernet / Wi-Fi):** Raw TCP soketi, varsayılan Port: `9100`.
  - **Seri (COM Port):** RS-232 seri arabirimi.
  - **Bluetooth:** Mobil cihazlarda SPP (Serial Port Profile) bağlantısı.
- **Türkçe Karakter Desteği:**
  - Yazıcının donanım karakter tablosuna göre `CP857` (PC857) kod sayfası dönüşümü yapılır (`ç, ğ, ı, ö, ş, ü, İ`).
  - Türkçe font ROM'u bulunmayan ucuz yazıcılarda sistem otomatik olarak **Raster Grafik Baskı Moduna** geçer; fişi 203 DPI siyah-beyaz bitmap resim olarak çizer ve yazıcıya görsel olarak aktarır ([PersistentPrintQueue](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/persistent_print_queue.dart)).

### 7.2. Barkod & Etiket Yazıcısı (TSPL / ZPL)

Ürün raf etiketleri ve koli etiketleri için TSPL (Taiwan Semiconductor / Xprinter / Argox) komut seti kullanılır:
```text
SIZE 40 mm, 30 mm
GAP 2 mm, 0 mm
DIRECTION 1
CLS
TEXT 20,20,"3",0,1,1,"SERENUT NUTOPIA FINDIK"
BARCODE 20,60,"EAN13",60,1,0,2,2,"8690123456789"
TEXT 20,130,"4",0,1,1,"149.50 TL"
PRINT 1,1
```

### 7.3. Elektronik Terazi (RS-232 Serial Worker)

Kasaya bağlı terazi ürün tartımında hızı ve doğruluğu sağlar.
- **Seri Port Ayarları:** Baud Rate `9600`, Data Bits `8`, Parity `None`, Stop Bits `1` (`9600-8-N-1`).
- **Desteklenen Protokoller:** CAS (AP-1, ER-Plus), TEM, Dibal, Bizerba, Desis.
- **Kararlılık (Stability) Koruması:**
  - Terazi veri akışında `ST` (Stable / Kararlı) ve `US` (Unstable / Hareketli) bayrakları gönderir.
  - Tartım titrerken kasiyerin hatalı gramajla satış yapmasını önlemek için sistem ekrandaki tartım butonunu `US` durumunda kilitler; terazi `ST` verdiğinde gramaj yeşile döner ve sepete eklenebilir.

### 7.4. Ağ Paylaşımlı Donanım Köprüsü (`SharedHardwareService`)

İşletmelerde her kasaya ayrı yazıcı veya terazi almak yüksek maliyetlidir.
- [SharedHardwareService](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/shared_hardware_service.dart) ve [SharedHardwareWorker](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/shared_hardware_worker.dart), USB üzerinden Ana Kasa'ya bağlı bir yazıcıyı ağda "Paylaşımlı Cihaz" olarak yayınlar.
- İkinci Kasa (ör. Android el terminali veya Kasa 2) satış yaptığında doğrudan ana kasaya veya bulut kuyruğuna bir `ClaimedHardwareJob` gönderir.
- Ana Kasa kuyruktaki işi alır, yerel termal yazıcısından fişi basar veya teraziden okuduğu ağırlığı Kasa 2'ye aktarır.

---

## 8. YEREL AĞDA EŞLER ARASI (P2P) ÜRÜN GÖRSELİ DAĞITIMI (LAN PEER SERVICE)

Binlerce ürünün yüksek çözünürlüklü fotoğraflarını bulut sunucusuna yüklemek sunucu maliyetlerini artırır ve mağazanın internet kotasını tüketir.

Serenut OS bu sorunu **P2P Local-Area Mesh** ile çözer:

```mermaid
graph LR
    subgraph "MAĞAZA YEREL AĞI (LAN)"
        Kasa1[Kasa 1: Fotoğraf Çekildi / Eklendi]
        Kasa2[Kasa 2: İkinci Bilgisayar]
        Tablet[Mobil Terminal: Android El Tableti]
    end

    Kasa1 -- "UDP 48732 Broadcast: 'Yeni Fotoğraf Var (SHA-256)'" --> Kasa2
    Kasa1 -- "UDP 48732 Broadcast: 'Yeni Fotoğraf Var (SHA-256)'" --> Tablet
    Kasa2 -- "HTTP 48731 GET /images/:hash" --> Kasa1
    Tablet -- "HTTP 48731 GET /images/:hash" --> Kasa1
    Kasa1 -. "Yalnızca Content-Addressed URI: device-image://hash" .-> Cloud[(Bulut / VPS)]
```

- **Sıfır Bulut Kota Tüketimi:** Bulut sunucusuna görsel dosyası yüklenmez! Yalnızca `device-image://<sha256>.jpg` referansı yazılır.
- **Otomatik Cihaz Keşfi ([ProductImagePeerService](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/product_image_peer_service.dart)):**
  - İstemciler yerel ağda **UDP Port 48732** üzerinden şirket anahtarını içeren broadcast anonsları yapar.
  - Bir kasada ürün resmi eklendiğinde, ağdaki diğer cihazlar saniyeler içinde bunu fark eder.
  - Diğer kasalar **HTTP Port 48731** üzerinden resmi doğrudan resmi çeken kasadan indirir ve `%APPDATA%\...\product_images` dizinine kaydeder.
  - Cihaz kapalı olsa bile bir sonraki açılışta eksik görseller yerel ağdan otomatik tamamlanır.

---

## 9. E-DÖNÜŞÜM & GİB E-ARŞİV / E-FATURA PORTALI (0 TL MALİYETLİ İSTEMCİ)

Serenut OS, özel entegratörlere her fatura başına kontör parası ödeme zorunluluğunu ortadan kaldıran resmi bir doğrudan entegrasyona sahiptir ([GibEArsivClient](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/gib_earsiv_client.dart)):

```mermaid
sequenceDiagram
    autonumber
    participant Kasa as Serenut OS
    participant GIB as GİB e-Arşiv Resmi Portalı (earsivportal.efatura.gov.tr)
    actor GibUser as Maliye / GİB SMS Hattı

    Kasa->>GIB: POST dispatch (kullanıcı kodu, şifre, Assos-Session)
    GIB-->>Kasa: Giriş Tokeni (token = abc123xyz)
    Note over Kasa: 2. Kasa Satışından Fatura JSON'u Üretilir
    Kasa->>GIB: POST dispatch (EARSIV_PORTAL_FATURA_OLUSTUR, payload)
    GIB-->>Kasa: Fatura Taslağı Oluşturuldu (fatura_uuid)
    Kasa->>GIB: POST dispatch (EARSIV_PORTAL_SMS_GONDER)
    GIB-->>GibUser: Cep Telefonuna SMS Onay Kodu Gider
    GibUser->>Kasa: Kasiyer Ekrana Gelen SMS Kodunu Girer
    Kasa->>GIB: POST dispatch (EARSIV_PORTAL_SMS_ONAY, sms_code)
    GIB-->>Kasa: 200 OK — Fatura Resmen İmzalandı & Mühürlendi!
    Kasa->>GIB: GET dispatch (EARSIV_PORTAL_FATURA_GOSTER / HTML-PDF)
    Kasa->>Kasa: Fatura PDF'ini Kaydet & Termalden Bilgi Fişi Bas
```

- **KDV & Matrah Dağılımı:** Kasa fişindeki her KDV oranı (%1, %10, %20) GİB kurallarına uygun olarak matrah ve KDV ayrımına tabi tutulur.
- **İptal & Gider Pusulası:** İade durumlarında faturanın GİB portalı üzerinden resmi iptal isteği (`EARSIV_PORTAL_FATURA_IPTAL`) gönderilebilir.

---

## 10. WHATSAPP BİLDİRİM & İLETİŞİM MOTORU (EVOLUTION API & META CLOUD)

Serenut OS'ta WhatsApp entegrasyonu basit bir sohbet aracı değildir; işletmenin kurumsal iletişim, tahsilat, fiş gönderme ve ciro takip omurgasıdır ([server/src/modules/whatsapp/](file:///c:/Users/ecz/proje/shaman/shaman_new/server/src/modules/whatsapp/)).

```mermaid
graph TD
    subgraph "İŞLETME TETİKLEYİCİLERİ"
        SaleEvent[Satış Yapıldı -> Fiş Gönder]
        DebtEvent[Veresiye Açıldı -> Borç Bildir]
        CollEvent[Tahsilat Alındı -> Makbuz Gönder]
        ZEvent[Gün Sonu Kapanışı -> Z-Raporunu Patrona İlet]
        OrderEvent[Sipariş Durumu: Hazırlanıyor/Kuryede]
    end

    subgraph "WHATSAPP AĞ GEÇİDİ (DUAL GATEWAY)"
        EvoAPI[1. Evolution API Gateway: QR Kod ile WhatsApp Web Bağlantısı]
        MetaAPI[2. Meta Cloud API: Kurumsal WABA Resmi Entegrasyonu]
    end

    subgraph "MÜŞTERİ & YÖNETİCİ"
        CustomerPhone[Müşteri WhatsApp'ı: Dijital Fiş & Bakiye Ekstresi]
        BossPhone[Patron WhatsApp'ı: Canlı Z-Raporu & Gün Sonu Hasılatı]
    end

    SaleEvent --> EvoAPI
    DebtEvent --> EvoAPI
    CollEvent --> EvoAPI
    ZEvent --> EvoAPI
    OrderEvent --> EvoAPI

    SaleEvent -. "Büyük Kurumsal Şirketler" .-> MetaAPI
    ZEvent -. "Büyük Kurumsal Şirketler" .-> MetaAPI

    EvoAPI --> CustomerPhone
    EvoAPI --> BossPhone
    MetaAPI --> CustomerPhone
    MetaAPI --> BossPhone
```

### 10.1. İkili Ağ Geçidi (Dual-Gateway) Mimarisi

İşletmeler iki yöntemden birini tercih edebilir:

1. **Evolution API Gateway (QR Kod ile 1 Dakikada Bağlantı):**
   - Şirket sahibi hiçbir Meta Developer hesabı açmadan, vergi levhası doğrulatmadan kendi cep telefonundaki normal WhatsApp veya WhatsApp Business uygulamasını sisteme bağlar.
   - Yönetim portalında "WhatsApp'ı Bağla" denildiğinde `POST /api/v1/whatsapp/evolution/instance` çağrılır ve ekrana bir **QR Kod** basılır (`GET /api/v1/whatsapp/evolution/qr`).
   - Telefonun WhatsApp uygulamasından "Bağlı Cihazlar $\rightarrow$ Cihaz Bağla" ile QR kod okutulur. Durum `open` olur ve şirket hemen kendi numarasından mesaj atmaya başlar!
2. **Meta Cloud API Gateway (Resmi Kurumsal WABA):**
   - Meta Business Manager üzerinden Embedded Signup (`Configuration ID: 2051947882108806`) ile kurumsal onaylı hat bağlanır.
   - Onaylanmış `UTILITY` şablonları üzerinden gönderim yapılır.

### 10.2. Otomatik Tetiklenen Olaylar ve Şablonlar

| Olay Adı | Alıcı | İçerik ve Amacı |
|---|---|---|
| `sale_created` | Müşteri | Satış tamamlandığında ürün kalemleri, toplam tutar ve dijital fiş bağlantısı gider. |
| `debt_created` | Müşteri | Veresiye satış yapıldığında yeni borç tutarı ve güncel toplam bakiye bildirilir. |
| `collection_recorded` | Müşteri | Nakit veya kredi kartıyla tahsilat alındığında borçtan düşüldüğünü belgeleyen dijital makbuz gider. |
| `balance_reminder` | Müşteri | Vadesi geçen veresiye hesaplara tek tıkla nezaket hatırlatması ve hesap özeti gönderilir. |
| `order_shipped` / `delivered` | Müşteri | Sipariş hazırlandı veya kurye yola çıktı bilgilendirmesi. |
| **`end_of_day_report`** | **Patron / Yönetici** | Kasiyer gün sonunda Z-Raporu aldığı anda patronun telefonuna **Günün Toplam Cirosu, Nakit, Kredi Kartı, Veresiye Dağılımı ve Kasa Farkı** anında WhatsApp mesajı olarak düşer. |

### 10.3. Webhook Mimarisi & İletim Durumları (Mavi Tik)

Sunucudaki `POST /api/v1/whatsapp/evolution/webhook` ve Meta webhook dinleyicisi mesajın her aşamasını takip eder:
- `accepted`: Sunucu mesajı sıraya aldı.
- `sent`: Mesaj WhatsApp sunucusuna iletildi (Tek gri tik).
- `delivered`: Müşterinin telefonuna ulaştı (Çift gri tik).
- `read`: Müşteri mesajı açıp okudu (Çift mavi tik).
- `failed`: Numara WhatsApp kullanmıyor veya interneti kapalı; sistem otomatik olarak **Android SIM SMS Gateway'e failover yapar**!

---

## 11. ANDROID SIM KARTLI SMS AĞ GEÇİDİ (YEREL GSM MODEMİ)

İşletmelerin toplu SMS firmalarına kontör parası ödemesini engelleyen patentli yerli mimari ([SmsGatewayService](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/sms_gateway_service.dart)):

```mermaid
sequenceDiagram
    autonumber
    participant Kasa as Windows Kasa 1 / Web
    participant Server as VPS Bildirim Kuyruğu (/api/v1/notifications)
    participant Phone as Çekmecedeki Android Cihaz (SIM Kartlı)
    participant GSM as Türk Telekom / Turkcell / Vodafone
    actor Customer as Müşteri Telefonu

    Kasa->>Server: Veresiye Satışı Yapıldı -> SMS Kuyruğuna Ekle
    Note over Phone: 2. Android Servisi 20 Saniyede Bir Uyanır
    Phone->>Server: GET /api/v1/notifications/sms-gateway/poll (device_id)
    Server-->>Phone: 200 OK — Bekleyen 3 Adet SMS Paketi
    Note over Phone: 3. Cihaz Kendi SIM Kartından Gönderir
    Phone->>GSM: Android SmsManager.sendTextMessage(numara, mesaj)
    GSM-->>Customer: Müşterinin Telefonuna Gerçek GSM SMS'i Düşer
    Phone->>Server: POST /sms-gateway/ack (mesaj_id = sent)
```

- **Maliyet:** 0 TL (İşletme hattındaki her yöne 1000-5000 SMS paketi kullanılır).
- **Yedeklilik:** WhatsApp kapalıysa veya müşterinin interneti yoksa bildirim motoru otomatik olarak bu kanala yönlenir.

---

## 12. PATRON WEB YÖNETİM PORTALI & CANLI CİRO İZLEME (REALTIME ENGINE)

İşletme sahibinin mağazada olmadan işletmeyi anbean cep telefonundan veya evdeki bilgisayardan yönetmesini sağlayan web portalı ([server/src/modules/portal/](file:///c:/Users/ecz/proje/shaman/shaman_new/server/src/modules/portal/)):

### 12.1. WebSocket Canlı Satış Akışı (Realtime Dashboard)

- Kasiyer kasada barkod okutup satışı bitirdiği anda (50 milisaniye içinde) WebSocket kanalı (`/api/v1/realtime`) üzerinden web portalına sinyal gönderilir.
- Patronun ekranındaki **Bugünkü Toplam Ciro, Yapılan Satış Adedi ve Kasa Grafiği** sayfa yenilenmeden canlı olarak artar.

### 12.2. Konsolide Şube ve Kasa Raporları

- Birden çok şubesi olan işletmelerde tüm kasaların hasılatı tek ekranda toplanır.
- Kar / Zarar Analizi: Alış fiyatları üzerinden satılan ürünlerin net brüt kar marjı kuruşu kuruşuna gösterilir.
- KDV Raporu: %1, %10 ve %20 KDV dilimlerine göre muhasebeye verilecek resmi KDV matrah dökümleri tek tıkla Excel/PDF olarak indirilir.

### 12.3. Uzaktan Fiyat ve Ürün Yönetimi

- Patron evindeyken portala girip "Fındık Fiyatını 180 TL yap" dediğinde, bu değişiklik bulut kataloğuna yazılır ve Sync V4 motoru ile mağazadaki tüm kasalara anında iner.

---

## 13. MÜŞTERİ İKİNCİ EKRANI (CUSTOMER FACING DISPLAY)

Kasada ödeme yapan müşterinin sepetini, indirimlerini ve para üstünü görmesini sağlayan çift monitör entegrasyonu:

- **Donanım Tipleri:**
  - **HDMI İkinci Ekran:** Kasaya takılı ikinci bir 10" - 15" LCD monitör.
  - **VFD / Seri Müşteri Göstergesi:** 2 satır 20 karakter yeşil floresan gösterge (COM Port / USB).
- **Çalışma Modları:**
  - **Kasa Boşken:** İşletmenin kampanyalarını, duyurularını ve kurumsal fotoğraflarını döner (Dijital Tabela / Reklam Modu).
  - **Satış Anında:** Kasiyer ürün okuttukça okunan ürünün adı, fotoğrafı, gramajı, birim fiyatı ve ara toplam ekranda büyük puntolarla belirir.
  - **Ödeme Alınırken:** Verilen para ve kasiyerin uzatacağı **Para Üstü** devasa rakamlarla ekrana yansıtılarak para üstü tartışmaları sıfırlanır.

---

## 14. YEDEKLEME, GERİ YÜKLEME, LİSANSLAMA & VERİ AKTARIMI (MIGRATION)

### 14.1. Güvenli Veritabanı Yedekleme & Geri Yükleme (`BackupService`)

- [BackupService](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/backup_service.dart), her akşam gün sonu Z-raporu alındığında veya her yazılım güncellemesi öncesinde otomatik devreye girer.
- **WAL Dondurma:** Yedek alınmadan önce veritabanında `PRAGMA wal_checkpoint(TRUNCATE)` çalıştırılarak `-wal` dosyasındaki tüm veri ana `.db` dosyasına dökülür.
- **Doğrulama:** Yedek dosyasının SHA-256 hash'i hesaplanır ve `PRAGMA integrity_check` yapılarak dosyanın sağlam olduğu tescillenmeden işlem bitirilmez.
- **Harici / Bulut Yedek:** İsteğe bağlı olarak Google Drive API entegrasyonu veya takılı bir USB belleğe `.serenut_backup` uzantılı arşiv dosyası olarak kopyalanır.

### 14.2. Lisanslama ve Çevrimdışı İntibak Süresi (Offline Grace Period)

- Lisans doğrulaması sunucunun RSA-4096 özel anahtarı ile imzalanmış bir dijital sertifika ile yapılır.
- **İnternet Kesintisi Güvencesi:** Sürekli interneti olmayan mağazalarda kasanın kapanmasını önlemek için **15 Günlük Çevrimdışı İntibak Süresi (Grace Period)** tanımlıdır. İnternet 15 gün boyunca hiç gelmese bile kasa satış yapmaya devam eder.

### 14.3. Dış Sistemlerden Veri Aktarımı (Excel / JSON Migration)

- [DataTransferPage](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/presentation/pages/data_transfer_page.dart) üzerinden işletmelerin eski yazılımlarından (Akınsoft, Mikro, Logo, NarBarkod vb.) dışa aktardığı Excel (`.xlsx`), CSV veya JSON dosyaları içe aktarılır.
- Ürün adları, barkodlar, birimler, alış/satış fiyatları ve mevcut stoklar kuruş modeline dönüştürülerek içe alınır.

---

## 15. DAĞITIM, GÜNCELLEME & KRİPTOGRAFİK İMZALAMA STANDARTLARI

Bu bölüm, `AGENTS.md` ve `docs/release-update-runbook.md` belgelerinde tanımlanan **zorunlu güvenlik ve yayın kurallarını** içerir.

```mermaid
graph TD
    subgraph "GELİŞTİRİCİ / CI"
        Pubspec[pubspec.yaml version: X.Y.Z+B]
        BuildWin[Windows Exe & Installer Derle]
        BuildApk[Android Release APK Derle]
        Sha[Küçük Harfli 64 Karakter SHA-256 Metnini Hesapla]
        RsaSign[RSA-4096 Özel Anahtarla Metni İmzala]
    end

    subgraph "YAYIN ARACI (publish-release.ts)"
        VerifyPre[Public Key ile İmzayı Doğrula]
        DeployVPS[VPS releases Dizinine Dosyaları Kopyala]
        UpdateDB[PostgreSQL releases Tablosunu Güncelle]
    end

    subgraph "İSTEMCİ (ReleaseManager)"
        CheckUpdate[GET /api/v1/updates/check]
        Download[Dosyayı İndir]
        VerifySha[İndirilen Dosyanın SHA-256'sını Hesapla]
        VerifyRsa[Yerel Public Key ile İmzayı Doğrula]
        Install[Kurulumu Sessizce / Onaylı Başlat]
    end

    Pubspec --> BuildWin
    Pubspec --> BuildApk
    BuildWin --> Sha
    BuildApk --> Sha
    Sha --> RsaSign
    RsaSign --> VerifyPre
    VerifyPre --> DeployVPS
    DeployVPS --> UpdateDB
    UpdateDB --> CheckUpdate
    CheckUpdate --> Download
    Download --> VerifySha
    VerifySha --> VerifyRsa
    VerifyRsa -- Başarılı --> Install
    VerifyRsa -- Başarısız --> Abort[Dosyayı Hemen Sil & Hata Günlüğü Üret]
```

### 15.1. Sürüm ve Dosya Adlandırma Kuralları (Professional Versioning)

- **`+` İletimi Yasaktır (Dosya Adları & Public UI - AGENTS.md Kural 2):**
  - Kullanıcıya sunulan veya web sitesinden indirilen dosyalarda `+` içeren dahili Flutter derleme numarası **ASLA KULLANILAMAZ** (Örnek: `SerenutOS-v1.3.144+299.exe` YASAKTIR).
  - **Doğru Format:**
    - Görünen ve İndirilen Dosya Adı: `SerenutOS-v1.3.144.exe` ve `SerenutOS-v1.3.144.apk`.
  - `pubspec.yaml` içerisindeki `+299` yapısı sadece dahili `versionCode` ve CI takibi içindir; yayın araçları ve indirme servisleri bunu otomatik semantik formata (`v1.3.144`) çevirir.

### 15.2. Değişmez İmza Sözleşmesi & OTA Standardı

1. **Android Paket İmzası (Keystore):**
   - Sertifika Parmak İzi (SHA-256): `server/release-signing-policy.json` dosyasındaki `androidPackageCertificateSha256` değeri ile birebir eşleşmelidir. Eşleşmeyen APK yayınlanamaz.
2. **Windows Authenticode İmzası:**
   - Tüm binary'ler (`.exe` ve `.dll`) Digicert zaman damgası ile SHA-256 PFX sertifikası kullanılarak imzalanır (`signtool.exe`).
3. **OTA RSA-SHA256 İmza Girdisi:**
   - **Kritik Kural:** İmzalanan şey dosyanın baytları değildir! Dosyanın küçük harfli 64 karakterlik SHA-256 özet metnidir (`utf-8`).
4. **Tek Yetkili Yayınlayıcı:**
   - Desteklenen tek yayınlayıcı: `server/src/scripts/publish-release.ts` (`dist/scripts/publish-release.js`).
   - `scripts/publish_v*.py` veya elle SQL yazarak sürüm yayınlamak **YASAKTIR**.
5. **Yayın Doğrulama:**
   - Her yayın sonrasında `node scripts/verify_published_release.js X.Y.Z+B` çalıştırılarak imza ve hash VPS üzerinde tam test edilmeden yayın tamamlanmış sayılmaz.

---

## 16. GÖZLEMLENEBİLİRLİK, TELEMETRİ & LOGLAMA

### 16.1. Yerel Loglama (Structured JSONL)

İstemci tüm çalışma loglarını işletim sistemine özel yerel dizinde saklar:
- **Windows:** `%APPDATA%\Serenut OS Software Technologies A.Ş\Serenut OS\logs\app.log`
- **Android:** `/data/user/0/com.serenutos.pos/files/logs/app.log`
- **Log Formatı:** JSON Lines (her satırda timestamp, level, subsystem, correlation_id, message, payload).

### 16.2. Sentry Entegrasyonu & Hata Fırtınası Filtreleri

Sentry crash reporting sistemi istemcideki gerçek kritik hataları yakalar.
- **Filtreleme Kuralları (`beforeSend`):**
  - Çevrimdışı modda çalışırken oluşan beklenen ağ hataları (`SocketException`, `ClientException`, `HttpException: Connection closed before full header was received`, `HandshakeException`) Sentry'ye gönderilmez ve kota israfı engellenir.
  - Sentry yalnızca yakalanmamış UI çöküşleri (`FlutterError.onError`), veritabanı bozulma alarmları ve donanım kritik istisnalarını raporlar.

---

## 17. SORUN GİDERME RUNBOOK'U & ACİL MÜDAHALE PROSEDÜRLERİ

### 17.1. Senaryo 1: Kasa Çevrimdışı Kaldı / Outbox Kuyruğu Birikti

**Belirti:** Satışlar yapılıyor ancak web panelinde veya diğer kasalarda görünmüyor. Sağ üst köşedeki bulut simgesi kırmızı/sarı.
1. **İnternet ve Sunucu Erişimi Kontrolü:**
   ```bash
   curl -I https://api.serenut.com/api/v1/health
   ```
2. **Kuyruktaki Bekleyen Mutasyonları Sorgula (SQLite):**
   ```sql
   SELECT count(*), status FROM outbox GROUP BY status;
   ```
3. **Hatalı / Dead Letter'a Düşmüş Mutasyonu Bul:**
   ```sql
   SELECT id, aggregate_type, error_message, retry_count FROM outbox WHERE status = 'failed' OR status = 'dead_letter';
   ```
4. **Çözüm / Yeniden Tetikleme:**
   - Ağ düzeldiğinde sistem otomatik push yapar.
   - Acil durumlarda Ayarlar -> Senkronizasyon -> "Şimdi Eşitle" butonuna basılır.

### 17.2. Senaryo 2: Müşteri Bakiyesi ile Defter Hareketleri Uyuşmuyor

**Belirti:** Müşteri kartında bakiye 500 TL yazıyor ancak hareket listesi toplandığında 400 TL çıkıyor.
1. **İnceleme:** `customers.balance_cents` önbellek kolonu harici bir işlem veya kesinti yüzünden güncelliğini yitirmiş olabilir.
2. **Kanonik Yeniden Hesaplama:**
   İstemcideki `LedgerService.recalculateCustomerBalance(customerId)` çalıştırılır veya SQLite üzerinde:
   ```sql
   UPDATE customers 
   SET balance_cents = (
       SELECT COALESCE(SUM(CASE WHEN type IN ('sale_credit', 'manual_debt', 'promissory_returned') THEN amount_cents ELSE -amount_cents END), 0)
       FROM ledger_entries 
       WHERE customer_id = customers.id AND deleted_at IS NULL
   )
   WHERE id = 'HEDEF_MUSTERI_ID';
   ```
3. Bakiye anında matematiksel olarak defterin gerçek toplamına eşitlenir.

### 17.3. Senaryo 3: SQLite Veritabanı Kilitlendi veya WAL Büyüdü

**Belirti:** `database is locked` veya `disk I/O error`.
1. **Bütünlük Kontrolü:**
   ```sql
   PRAGMA integrity_check;
   ```
   Çıktı `ok` olmalıdır.
2. **WAL Checkpoint:**
   Büyüyen `-wal` dosyasını ana veritabanına gömmek için:
   ```sql
   PRAGMA wal_checkpoint(TRUNCATE);
   ```
3. **Kurtarma:** Uygulama tamamen kapatılır, `%APPDATA%\...\databases\core_next` dizinindeki veritabanının yedeği alınır ve uygulama yeniden başlatılır.

### 17.4. Senaryo 4: Termal Yazıcı Fiş Basmıyor veya Türkçe Harfler Bozuk

1. **Bağlantı Kontrolü:**
   - USB yazıcı ise Windows Aygıt Yöneticisi'nde doğru yazıcı kuyruğu seçili mi?
   - Ağ yazıcısı ise IP adresine ping atılabiliyor mu (`ping 192.168.1.200`)?
2. **Türkçe Karakter Sorunu:**
   - Ayarlar -> Yazıcı Ayarları -> "Karakter Kod Sayfası" seçeneğini `CP857` yapın.
   - Sorun çözülmezse "Grafik/Resim Olarak Yazdır" seçeneğini açın (tüm karakterleri piksel olarak dökeceğinden %100 kusursuz Türkçe basacaktır).

### 17.5. Senaryo 5: Terazi Ağırlığı Okumuyor

1. Windows Aygıt Yöneticisi -> Bağlantı Noktaları (COM & LPT) altında terazi USB-Serial çeviricinin COM portunu (ör. `COM3`) kontrol edin.
2. Başka bir uygulamanın COM portunu işgal etmediğinden emin olun (COM portları tekil erişimlidir).
3. Ayarlar -> Donanım -> Terazi ekranından Baud Rate'in `9600` ve modelin doğru seçildiğini doğrulayın.

### 17.6. Senaryo 6: Güncelleme İndirildi Ama İmza Hatası Veriyor

**Belirti:** Güncelleme iniyor ancak "İmza doğrulanamadı" uyarısıyla iptal ediliyor.
1. İndirilen dosyanın SHA-256 hash'i sunucudaki hash ile uyuşmuyor olabilir (eksik indirme / proxy araya girmesi).
2. İstemcideki yerel güncelleme önbelleğini temizleyin:
   - Windows: `%TEMP%\serenut_updates` veya `%APPDATA%\...\updates` dizinini silin.
3. Cihazın sürümünün köprü sürüm gerektirip gerektirmediğini (`1.3.10+91` altı mı?) kontrol edin.

### 17.7. Senaryo 7: GİB e-Arşiv Portalı Fatura İmzalamıyor / Hata Veriyor

1. **GİB Portal Bakımı:** GİB portalı yoğunluk veya bakım saatlerinde (genelde gece 00:00 - 02:00) yanıt vermeyebilir. İstemcideki faturayı "Taslaklara Kaydet" ile yerelde tutun; portal açıldığında tek tıkla toplu imzalayın.
2. **SMS Doğrulama Zaman Aşımı:** SMS onay kodu 180 saniye içinde girilmelidir. Zaman aşımına uğradıysa yeni SMS isteği tetikleyin.
3. **Mükellef TCKN/VKN Kontrolü:** Alıcı TCKN veya VKN'si 10 ya da 11 hane olmalı, e-Fatura mükellefi olan kurumlara e-Arşiv değil doğrudan e-Fatura kesilmelidir.

### 17.8. Senaryo 8: WhatsApp Bağlantısı Koptu / Mesaj Gitmiyor

**Belirti:** Satış fişleri veya Z-raporu WhatsApp'a düşmüyor. Portalda WhatsApp durumu `disconnected` veya `reauthorization_required`.
1. **Bağlantı Tipini Kontrol Edin:**
   - **Evolution API (QR Kod Modu):** Portalda Ayarlar $\rightarrow$ Bildirimler $\rightarrow$ WhatsApp sekmesine gidin. "Yeniden Bağlan" butonuna tıklayıp çıkan QR kodu telefonunuzdaki WhatsApp uygulamasından okutun.
   - **Meta Cloud API (Resmi WABA):** Meta Business Manager'da kayıtlı ödeme kartının süresi bitmiş veya token süresi dolmuş olabilir. Portaldan "Embedded Signup Yenile" adımı yapılır.
2. **Kuyruktaki Mesajları Kontrol Edin:**
   ```sql
   SELECT status, count(*) FROM notification_queue WHERE channel = 'whatsapp' GROUP BY status;
   ```
3. **Failover (Yedek Hat):** WhatsApp kapalı olduğunda sistemin otomatik olarak SIM SMS Gateway'e geçip geçmediğini kontrol edin (`NOTIFICATION_ENABLED_CHANNELS=whatsapp,sms`).

### 17.9. Senaryo 9: Web Portalı Canlı Ciro Akışı Güncellenmiyor (WebSocket Düşmesi)

**Belirti:** Kasada satış yapılıyor ama patronun web ekranındaki canlı ciro artmıyor.
1. Web tarayıcısının F12 Konsolunda `WebSocket connection failed: wss://api.serenut.com/ws` hatası var mı bakın.
2. NGINX proxy üzerinde `Upgrade` ve `Connection "upgrade"` başlıklarının açık olduğunu doğrulayın.
3. VPS üzerinde WebSocket sunucusunu yeniden başlatın:
   ```bash
   pm2 restart serenut-server
   ```

### 17.10. Senaryo 10: Müşteri İkinci Ekranı Görüntü Vermiyor

1. Windows Masaüstü $\rightarrow$ Ekran Ayarları altında ikinci monitörün **"Bu ekranları genişlet" (Extend Desktop)** olarak ayarlandığından emin olun ("Bu ekranları yinele/Duplicate" modu kullanılmamalıdır).
2. Serenut OS Ayarlar $\rightarrow$ Ekran Ayarları $\rightarrow$ "Müşteri Ekranını Etkinleştir" anahtarını açın ve hedef monitörü seçin.
3. İkinci ekranda reklam slaytları için bir görsel klasörü seçildiğini doğrulayın.

### 17.11. Senaryo 11: Android SIM SMS Gateway Mesaj Göndermiyor

1. Kasadaki Android cihazda Serenut OS arka plan çalışma ve pil optimizasyonu istisnasının verildiğini kontrol edin (Android sistemi uygulamayı uyutmamalıdır).
2. Cihazın SIM kartında SMS paketi veya TL bakiyesi olduğunu doğrulayın.
3. Uygulama Ayarları $\rightarrow$ "Bu cihazı SIM SMS Ağ Geçidi yap" anahtarının açık olduğunu kontrol edin.

### 17.12. Senaryo 12: VPS Production Sunucusu Acil Müdahale Komutları

```bash
# Sunucu durumunu kontrol et
pm2 status

# Node.js backend loglarını canlı izle
pm2 logs serenut-server --lines 100

# Backend'i sıfır kesintiyle yeniden başlat
pm2 reload serenut-server

# PostgreSQL bağlantı durumunu incele
sudo -u postgres psql -d serenut_production -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

# Yayındaki sürümü doğrula
node scripts/verify_published_release.js 1.3.144+299
```

---

## 18. GENİŞLETİLMİŞ MASTER CHEAT SHEET TABLOSU

| Alan | Kanonik Kural | İlgili Dosya / Kod |
|---|---|---|
| **Veritabanı** | Standart SQLite (SQLCipher Yasak) | [db_schema.dart](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/database/schema/db_schema.dart) |
| **Para Birimi** | Kuruş / Integer (`MoneyCents`) | [money_cents.dart](file:///c:/Users/ecz/proje/shaman/shaman_new/core_next/client_core/lib/domain/money_cents.dart) |
| **Bakiye Formülü** | Pozitif = Borçlu, Negatif = Alacaklı | [db_triggers.dart](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/database/schema/db_triggers.dart) |
| **Dosya İsimleri** | `+` Yasak (`SerenutOS-vX.Y.Z.exe`) | [AGENTS.md Kural 2](file:///c:/Users/ecz/proje/shaman/shaman_new/.agents/AGENTS.md) |
| **OTA İmzalama** | Dosya SHA-256 Metninin RSA İmzası | [publish-release.ts](file:///c:/Users/ecz/proje/shaman/shaman_new/server/src/scripts/publish-release.ts) |
| **Yayın Doğrulama** | Zorunlu Kontrol Scripti | [verify_published_release.js](file:///c:/Users/ecz/proje/shaman/shaman_new/scripts/verify_published_release.js) |
| **Senkronizasyon** | Deep Equal JSONB (`payloadDeepEqual`) | [sync-v4.routes.ts](file:///c:/Users/ecz/proje/shaman/shaman_new/server/src/modules/sync_v4/sync-v4.routes.ts) |
| **GİB e-Arşiv** | 0 TL Maliyetli Resmi Portal İstemcisi | [gib_earsiv_client.dart](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/gib_earsiv_client.dart) |
| **WhatsApp Evolution** | QR Kod ile 1 Dakikada WhatsApp Bağlama | [whatsapp.controller.ts](file:///c:/Users/ecz/proje/shaman/shaman_new/server/src/modules/whatsapp/whatsapp.controller.ts) |
| **WhatsApp Meta** | Kurumsal Resmi WABA Embedded Signup | [WHATSAPP_BUSINESS_SETUP.md](file:///c:/Users/ecz/proje/shaman/shaman_new/docs/WHATSAPP_BUSINESS_SETUP.md) |
| **Patrona Z-Raporu** | Gün Sonu Kapanışında Otomatik WhatsApp Özeti | [end_of_day_page.dart](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/presentation/pages/end_of_day_page.dart) |
| **SIM SMS Gateway** | Android Telefonu GSM SMS Modemi Yapma | [sms_gateway_service.dart](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/sms_gateway_service.dart) |
| **Web Portalı** | Evden/Telefondan Canlı Ciro Takibi | [server/src/modules/portal/](file:///c:/Users/ecz/proje/shaman/shaman_new/server/src/modules/portal/) |
| **Müşteri 2. Ekranı** | HDMI / VFD Çift Ekran Kasa Yansıtma | [lib/presentation/pages/](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/presentation/pages/) |
| **P2P Görsel Ağı** | UDP 48732 / HTTP 48731 LAN Senkronu | [product_image_peer_service.dart](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/product_image_peer_service.dart) |
| **Ortak Donanım** | Kasalar Arası Ortak Yazıcı/Terazi | [shared_hardware_service.dart](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/shared_hardware_service.dart) |
| **Sepet Kurtarma** | Elektrik Kesilse Bile Sepeti Geri Getirme | [cart_persistence_service.dart](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/cart_persistence_service.dart) |
| **Yedekleme** | WAL Checkpoint & Integrity Check | [backup_service.dart](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/backup_service.dart) |
| **Yerel Loglar** | `%APPDATA%\...\logs\app.log` | [log_collection_service.dart](file:///c:/Users/ecz/proje/shaman/shaman_new/lib/infrastructure/services/log_collection_service.dart) |

---
*Bu el kitabı Serenut OS geliştirici ve operasyon ekipleri için birincil ve bağlayıcı referanstır. Her yeni mimari kararda ve sürüm geçişinde güncellenmelidir.*
