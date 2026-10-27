# STAGE 10.10.3 — SON VERİ KAYBI VE CANLIYA GEÇİŞ ENGELİ ADLİ DENETİM RAPORU

**Tarih:** 16 Ekim 2026  
**Denetim Seviyesi:** Bağımsız / Adli / Sıfır Tolerans  
**Kapsam:** Nutopia Fındık Değirmeni, Serenut, ERKUL ÇEYİZ  

---

## 1. 21 GENEL KASA HAREKETİNİN ADLİ EŞLEŞTİRMESİ (PASS)

Nutopia kaynak veritabanındaki 1.422 `financial_transactions` kaydı, adli seviyede iki ana gruba ayrılarak incelenmiş ve hedef tablolardaki karşılıkları birebir tespit edilmiştir:

### A. Dağılım ve Karakteristik
- **Toplam Hareket:** 1,422 adet
- **Müşteri Bağlantılı Hareketler (`customer_id IS NOT NULL`):** 1,401 adet
- **Müşterisiz Genel Kasa Hareketleri (`customer_id IS NULL OR ''`):** 21 adet

### B. 21 Kasa Hareketinin Birebir Hedef Eşleşmesi
Adli sorgu sonucunda bu 21 kaydın tamamının `type = 'sale'` olduğu, `debt_amount = 0.0` olduğu ve her birinin `reference_id` alanının `sales` tablosundaki bir perakende peşin satışa işaret ettiği kanıtlanmıştır:

```text
FT ID                          Tutar (TL)   Hedef Satış ID (sales)                     Hedef Ödeme (sale_payments)
-------------------------------------------------------------------------------------------------------------------
trans-17852550015567359331       1,390.00   sale-e774315b-fcd8-4267-b8de-27e094f81086   139,000 kr (CASH)
trans-17852550140540603441         180.00   sale-d975bc80-e5f3-4495-be29-828bba85e684    18,000 kr (CASH)
trans-17852550413659953942          80.00   sale-e4846393-7871-4a03-818f-c2ab0bc2f6e2     8,000 kr (CASH)
trans-17852551097971748840         120.00   sale-b0de7600-64ac-4a2f-9d38-b8dc7c047db3    12,000 kr (CASH)
trans-17852570774634905820         700.00   sale-8d5859e0-aab7-43c4-a664-5349ce57b650    70,000 kr (CASH)
trans-17852570925577962011          20.00   sale-5b153984-90f2-4d1a-bf8a-c92b4a518cf9     2,000 kr (CASH)
trans-17852571030732889765          20.00   sale-8457e231-0561-4f65-87f4-b7339a4c78bc     2,000 kr (CASH)
trans-17853387615502870102         500.00   sale-9bb05f30-672a-490d-9c03-a8a8e48e2c66    50,000 kr (CASH)
trans-17853436740291100213         118.00   sale-29f73dd1-c2eb-4ca9-bf0e-8858ce559988    11,800 kr (CASH)
trans-17858343476949405343         578.00   sale-7aa7e7fd-bebf-419b-b88d-e679ad90850c    57,800 kr (CASH)
trans-17858366820340712828         289.00   sale-11eb5b80-8da5-46c4-a2c8-ffad9c7dea46    28,900 kr (CASH)
trans-17858367216399479506         578.00   sale-2e015549-05e3-4a5d-95c5-f44946155187    57,800 kr (CASH)
trans-17858441072097966972          59.00   sale-8c96b30c-ae79-4178-9669-c2c3fc82ace7     5,900 kr (CASH)
trans-17858441534781740473         460.00   sale-9e588310-aa79-4374-b1da-9c5bf14ba8a2    46,000 kr (CASH)
trans-17858441882558330353         519.00   sale-899c988f-6d83-4ded-95d7-b18bb72b7f81    51,900 kr (CASH)
trans-17852570662183538798          20.00   sale-131f4cc5-3ad5-4704-8bd9-c764d561793f     2,000 kr (CASH)
trans-17862718718479920471         763.50   sale-23546096-2be5-4f90-87b4-3914f9f42074    76,350 kr (CASH)
trans-17862719648869790571         422.50   sale-7f758d09-0f22-41da-8002-3de2f3cc752f    42,250 kr (CASH)
trans-17888610013628381590          80.00   sale-799f9f35-f08c-4fa8-8298-b610fb3bca0f     8,000 kr (CASH)
trans-17898167939063583370       2,650.00   sale-eb641cf9-94c4-43d9-bf1c-0d4d3e15f029   265,000 kr (CASH)
trans-17898168269292281750       2,650.00   sale-a16cb120-3d38-44c3-924d-a590c05cb225   265,000 kr (CASH)
-------------------------------------------------------------------------------------------------------------------
TOPLAM: 21 Hareket              12,197.00 TL  21/21 Eşleşti                              1,219,700 kr Nakit Giriş
```

### C. Mimari Karşılaştırma ve Ayrım
1. **Legacy Sistem:** Müşterisiz peşin satış yapıldığında, hem `sales` tablosuna satışı hem de `financial_transactions` tablosuna gölge bir kopyayı (`trans-...`) yazmaktaydı.
2. **Core Next Mimarisi:** Core Next'te `ledger_entries` tablosu strictly **müşteri cari defteridir** (`customer_id TEXT NOT NULL REFERENCES customers(id)`). Müşterisiz perakende peşin satışlar ise doğrudan `sales` ve `sale_payments` tablolarında kuruş bazında tutulur.
3. **Nakit Giriş Mutabakatı:** 21 satışın tamamı (12,197.00 TL = 1,219,700 kuruş) hedefteki `sales` ve `sale_payments` tablolarına kuruşu kuruşuna aktarılmıştır. Hiçbir kayıt dışarıda kalmamıştır.

---

## 2. SİLİNMİŞ KAYITLARIN ADLİ DENETİMİ (PASS)

Nutopia kaynak veritabanında `is_deleted = 1` bayrağı taşıyan 7 müşterinin tamamı incelenmiştir:

```text
Müşteri ID                            İsim              Bakiye (TL)  Durum          İlişkili Satış/Defter/Sipariş
-------------------------------------------------------------------------------------------------------------------
7812e564-4692-46f4-a7d4-1d7cbf619a97   XSET                     0.00  is_deleted=1   1 Satış / 8 Defter / 6 Sipariş
5e21ff74-1f1c-4c03-811d-a4d637feb15c   ASDD                  -695.00  is_deleted=1   0 Satış / 5 Defter / 3 Sipariş
8abcbce0-0ff7-4ef5-976e-e6013e5028b8   ONUR ADAR            +1,099.00  is_deleted=1   1 Satış / 12 Defter / 4 Sipariş
cust-1785327416503825-2450             MUHAMMET AKDOĞAN     +2,625.00  is_deleted=1   1 Satış / 16 Defter / 6 Sipariş
cust-1788812573266975-1568             ASD                      0.00  is_deleted=1   0 Satış / 0 Defter / 0 Sipariş
e1a44c81-bd00-4305-af17-2b603aa4db8e   FATMA BEKTAŞ             0.00  is_deleted=1   0 Satış / 2 Defter / 1 Sipariş
d9cee560-6be4-40be-9fe5-4a9bf877fe19   FATMA BEKTAŞ             0.00  is_deleted=1   0 Satış / 2 Defter / 1 Sipariş
```

### İş Kuralı ve Muhasebe Gerekçesi (Retention Rationale):
1. **İlişkisel Bütünlük (Foreign Key Integrity):** Bu silinmiş müşterilerin geçmişe dönük 3 satışı, 45 adet defter hareketi ve 21 siparişi bulunmaktadır. Müşteriler silinseydi, bu hareketler yetim (orphan) kalacak veya FK ihlaliyle sistem patlayacaktı.
2. **Finansal Bütünlük (Balance Conservation):** Silinmiş müşterilerden 3 tanesinin bakiyesi sıfır değildir (`ASDD: -695 TL`, `ONUR ADAR: +1,099 TL`, `MUHAMMET AKDOĞAN: +2,625 TL` -> Net toplam: **+3,029.00 TL**). Bu müşteriler taşınmasaydı genel mizan ve denetim görünümünde 3,029.00 TL açıklanamayan sapma oluşacaktı.
3. **Soft-Delete Uyumluluğu:** Core Next hedef veritabanında `is_deleted = 1` ve `is_active = 0` bayrakları aynen korunmuştur. Müşteriler günlük satış ekranlarında gizlenmekte ancak resmi defterde ve denetim izinde muhafaza edilmektedir.

---

## 3. FİNANSAL VE STOK MUTABAKATI (PASS)

Üç işletmenin tamamında alan bazında doğrudan karşılaştırma sonuçları:

### A. Nutopia Fındık Değirmeni
- **Ürünler & Stok:** 37,682 kaynak ürün -> 37,682 hedef ürün. Kaynak `quantity` toplamı: **5,179,525.85 kg**, Hedef `stock_quantity` toplamı: **5,179,525.85 kg**. Fark: **0.000 kg**.
- **Müşteri Bakiyesi:** 584 kaynak müşteri -> 584 hedef müşteri. Kaynak `balance` toplamı: **-141,300.68 TL**, Hedef `balance_cents` toplamı: **-14,130,068 kr** (-141,300.68 TL). Fark: **0 kuruş**.
- **Müşteri Defteri:** 1,401 kaynak hareket -> 1,401 hedef `ledger_entries`. Fark: **0**.
- **Sipariş & Kalemleri:** 792 sipariş -> 792 hedef sipariş; 1,068 kalem -> 1,068 hedef kalem. Fark: **0**.
- **Taksitler:** 2 taksit planı, 9 taksit -> 2 taksit planı, 9 taksit. Fark: **0**.
- **Denetim İzi:** 3,968 audit olayı -> 3,968 audit olayı. Fark: **0**.

### B. Serenut (Şema v44)
- **Ürünler & Stok:** 6,377 ürün -> 6,377 hedef ürün. Stok toplamı: **637,445.0 birim**. Fark: **0.00**.
- **Müşteri Bakiyesi:** 7 müşteri -> 7 hedef müşteri. Toplam bakiye: **-2,673.00 TL** (-267,300 kr). Fark: **0 kuruş**.
- **Sipariş & Satış:** 15 satış / 19 kalem; 5 sipariş / 5 kalem -> Hedefte birebir eşit. Fark: **0**.

### C. ERKUL ÇEYİZ (PostgreSQL VPS Export)
- **Müşteriler:** **401 Müşteri** -> **401 Hedef Müşteri**. Kayıp: **SIFIR (%0)**.
- **Cari Alacak:** **-523,620.00 TL** -> **-52,362,000 kuruş**. Fark: **0 kuruş**.
- **Defter Hareketleri:** 539 hareket -> 539 hedef `ledger_entries`. Fark: **0**.
- **Ürünler:** 26 ürün -> 26 hedef ürün. Fark: **0**.
- **Satışlar:** 5 satış / 5 kalem -> 5 hedef satış / 5 kalem. Fark: **0**.
- **Siparişler:** 1 sipariş / 1 kalem -> 1 hedef sipariş / 1 kalem. Fark: **0**.
- **Yönetici Hesabı:** `tunahan erkul` (`erkultunahan7@gmail.com`) yetkili kullanıcı olarak hedefte oluşturuldu.

---

## 4. ERKUL ÇEYİZ DIŞA AKTARIM VE ŞEMA DOĞRULAMASI (PASS)

- **PostgreSQL İncelemesi:** `psql -A -t` parametresiyle Linux VPS üzerinde çalışan betik her tabloyu tekil JSON dizisi olarak çekmiş ve `/tmp/erkul_export.json` (485,357 bayt) dosyasına kaydetmiştir.
- **Kapsam Dışı Bırakılan Tabloların Kanıtı:**
  `schema.sql` içerisindeki `sessions`, `roles`, `permissions`, `licenses`, `device_licenses`, `plans`, `subscriptions`, `crash_logs`, `sync_v4_changes` tabloları SaaS platformunun genel altyapı tablolarıdır. Bu tablolarda Erkul Çeyiz'e ait hiçbir işletme verisi bulunmamaktadır.
- **İşletme Verisi Kaybı:** SIFIR.

---

## 5. İDAMPOTENCY VE TENANT İZOLASYONU (PASS)

- **İkinci Çalıştırma Değişmezliği:**
  Erkul Çeyiz göçü 2. kez art arda çalıştırılmış; 401 müşterinin her birinin bakiyesi, 26 ürünün fiyat ve stokları, satış ve defter kayıtları önceki çalıştırmayla birebir karşılaştırılmıştır. Bakiye mutasyonu veya çift kayıt artışı: **SIFIR (0)**.
- **Tenant İzolasyonu:**
  Nutopia ve Erkul Çeyiz hedef SQLite veritabanlarında aynı anda bağımsız müşteriler oluşturulmuş; çapraz sorgularda hiçbir verinin diğerine sızmadığı ve müşteri kimlik kümelerinin tamamen ayrık (`intersection.isEmpty == true`) olduğu kanıtlanmıştır.

---

## 6. CANLIYA GEÇİŞ ENGELLERİ (CRITICAL CUTOVER BLOCKERS)

Veri göç motoru ve veritabanı bütünlüğü kusursuz olsa da, **üretim kodunun canlıya geçişi için aşağıdaki somut engeller mevcuttur**:

1. **Feature Flag Kapalı:** `coreNextSalesEngineEnabledProvider` varsayılan değeri [sales_controller.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L104) içerisinde `false` olarak kilitlidir.
2. **UI & Repository Bağlantısı:** POS arayüzü (kasa satış ekranı, müşteri listesi, ürün katalog kartları) henüz Core Next `AppDatabase` motoruna değil, eski legacy `sqflite` repository sınıflarına (`SqliteProductRepository`, `SqliteCustomerRepository`) bağlı çalışmaktadır.
3. **Masaüstü Multi-Tenant Router Eksikliği:** Windows masaüstü istemcisi [app_bootstrap.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/bootstrap/app_bootstrap.dart) dosyasında tek bir statik dosya yoluna (`.../Serenut OS/databases/serenut_pos.db`) bağlanmaktadır. Nutopia, Serenut ve Erkul Çeyiz'in 3 ayrı `.db` dosyasını çalışma zamanında dinamik olarak seçecek bir "İşletme / Tenant Seçici" (Tenant Selector/Router) mekanizması masaüstü açılış ekranına henüz entegre edilmemiştir.
4. **İlk Açılış Canlı Migrasyon Ekranı:** Kullanıcı makinesinde ilk açılışta eski SQLite dosyasını yedekleyip (`.db.backup`) Core Next şemasına çevirecek olan `core_next_bootstrap_coordinator.dart` akışı için bir kullanıcı bilgilendirme / progress ekranı henüz UI seviyesinde bağlanmamıştır.
5. **Sync v4 Client Pull Entegrasyonu:** Outbox üzerinden VPS'e veri basma (Push) test edilmiş olsa da, VPS'ten gelen güncellemeleri istemci SQLite'a yazan Pull akışı henüz Core Next kuruş modellerine tam bağlanmamıştır.

---

## 📌 NİHAİ ADLİ KARARLAR

| Değerlendirme Alanı | Adli Karar | Durum İzahı |
| :--- | :--- | :--- |
| **1. Veri Bütünlüğü** | **KANITLANDI (PASS)** | 3 işletmenin tüm verileri (44,085 ürün, 992 müşteri, 5,816,970.85 kg stok, 667,593.68 TL bakiye) kuruşu kuruşuna, gramı gramına eksiksiz taşınmıştır. |
| **2. İşletme İzolasyonu**| **KANITLANDI (PASS)** | 3 işletme bağımsız SQLite veritabanlarında tutulmakta olup sıfır veri sızıntısı ve mutlak ayrıklık kanıtlanmıştır. |
| **3. Üretime Geçiş** | **HAZIR DEĞİL (BLOCKED)** | UI repository yönlendirmesi, masaüstü tenant seçici router ve feature flag açılış protokolü tamamlanmadan canlıya geçilemez. |
