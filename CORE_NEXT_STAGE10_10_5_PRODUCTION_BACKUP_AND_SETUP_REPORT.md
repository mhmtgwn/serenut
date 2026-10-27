# STAGE 10.10.5 — 3 İŞLETMENİN GÜVENLİ YEDEKLENMESİ VE CORE NEXT MİMARİSİNE YERLEŞTİRİLMESİ RAPORU

**Tarih:** 16 Ekim 2026, 18:53 (TSİ)  
**Kapsam:** 3 Bağımsız İşletme (Nutopia, Serenut, ERKUL ÇEYİZ)  
**Durum:** %100 BAŞARILI (SIFIR VERİ KAYBI, TAM ADLİ MUTABAKAT, BÜTÜNLÜK DOĞRULANDI)

---

## 1. YÜRÜTME ÖZETİ

Kullanıcı talimatı doğrultusunda sistemdeki 3 işletmenin de tüm ham verileri (ürünler, tartılı stoklar, müşteriler, kuruş bakiyeleri, siparişler, cari defter hareketleri, taksit planları ve denetim izleri) donanımsal ve mantıksal olarak **çift lokasyonda** yedeklenmiş, SHA-256 kriptografik özetleri çıkarılmış ve ardından her işletme için Core Next mimarisine uygun bağımsız üretim veritabanları (`nutopia_pos.db`, `serenut_pos.db`, `erkul_pos.db`) sıfırdan inşa edilerek veriler yerleştirilmiştir.

Yedekleme esnasında SQLite WAL (Write-Ahead Log) katmanındaki sayfalar `PRAGMA wal_checkpoint(TRUNCATE)` ile ana veritabanına kalıcı olarak gömülmüş, bu sayede **saat 18:19 ve 18:27'de yapılan en son 2 tahsilat (toplam 6.800,00 TL)** dahil olmak üzere tek bir bayt dahi kaybolmadan kurtarılmış ve yeni mimariye eksiksiz aktarılmıştır.

---

## 2. GÜVENLİ HAM VERİ YEDEKLERİ (IMMUTABLE RAW BACKUPS)

Ham kaynak veriler iki ayrı bağımsız dizine kopyalanmış ve bütünlükleri mühürlenmiştir:
- **Workspace Yedek Deposu:** `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\`
- **AppData Güvenli Deposu:** `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\backups\raw_tenants_20261016\`

### Kriptografik Doğrulama Manifestosu (`SHA256SUMS.txt`)
| İşletme | Dosya Adı | Dosya Boyutu | SHA-256 Checksum | Durum |
| :--- | :--- | :--- | :--- | :--- |
| **Nutopia Fındık Değirmeni** | `raw_nutopia_v60.db` | 59.764.736 bayt (~57 MB) | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | Mühürlendi (OK) |
| **Serenut (Merkez)** | `raw_serenut_v44.db` | 6.516.736 bayt (~6.2 MB) | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | Mühürlendi (OK) |
| **ERKUL ÇEYİZ** | `raw_erkul_source.json` | 485.357 bayt (474 KB) | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | Mühürlendi (OK) |

---

## 3. YENİ CORE NEXT ÜRETİM VERİTABANLARI (PRODUCTION STORAGE)

Her işletme için `core_next` dizini altında izole SQLite veritabanı inşa edilmiş ve veriler yeni ilişkisel şemaya yerleştirilmiştir:
- **Dizin:** `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\core_next\`

| İşletme | Core Next Veritabanı | Boyut | SHA-256 Checksum | `integrity_check` | `foreign_key_check` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Nutopia** | `nutopia_pos.db` | 17.010.688 bayt | `c976b4d243800c763525078b9c8e9931375a1bf88fe6afca727461c230c61753` | **ok** | **0 ihlal (Temiz)** |
| **Serenut** | `serenut_pos.db` | 2.355.200 bayt | `a7cc9d22e2d4489789a9536b6c3f3018c699a5ca5daecbe2be04b32a7c7e2273` | **ok** | **0 ihlal (Temiz)** |
| **ERKUL ÇEYİZ** | `erkul_pos.db` | 557.056 bayt | `ad744fcf4aa5c4af0e0628b58fc7b15db1695d21173bdf5087655da5f1067860` | **ok** | **0 ihlal (Temiz)** |

---

## 4. ADLİ MUTABAKAT VE KURUŞU KURUŞUNA VERİ DOĞRULAMASI

### 1. Nutopia Fındık Değirmeni
- **Ürün Sayısı:** 37.682 (Kaynak: 37.682 | Core Next: 37.682) -> **Fark: 0**
- **Fiziksel Stok:** 5.179.525,85 kg (Tartılı kesirli gramajlar dahil %100 korundu) -> **Fark: 0,000 kg**
- **Müşteri (Cari):** 584 (Silinmiş ve pasif müşteriler dahil) -> **Fark: 0**
- **Cari Bakiye:** **-134.500,68 TL** (-13.450.068 kuruş) -> `v_customer_ledger_effect` defter toplamı ile kuruşu kuruşuna eşit.
  - *Not:* 18:19'daki 5.000 TL ve 18:27'deki 1.800 TL'lik tahsilatlar ile önceki -141.300,68 TL bakiye tam olarak -134.500,68 TL'ye güncellenmiş ve sıfır kayıpla aktarılmıştır.
- **Defter Hareketleri:** 1.403 müşteri hareketi + 21 kasa nakit satışı = 1.424 hareketin tamamı aktarıldı.
- **Siparişler:** 792 sipariş ve 1.068 sipariş kalemi -> **Fark: 0**
- **Taksitler:** 2 taksit planı, 9 vadeli taksit -> **Fark: 0**
- **Denetim İzi (Audit):** 3.968 güvenlik kaydı -> **Fark: 0**

### 2. Serenut (Merkez)
- **Ürün Sayısı:** 6.377 (Kaynak: 6.377 | Core Next: 6.377) -> **Fark: 0**
- **Fiziksel Stok:** 637.445,00 kg -> **Fark: 0,000 kg**
- **Müşteri (Cari):** 7 müşteri -> **Fark: 0**
- **Cari Bakiye:** **-2.673,00 TL** (-267.300 kuruş) -> **Kuruşu kuruşuna mutabık**
- **Defter Hareketleri:** 12 defter hareketi -> **Fark: 0**
- **Siparişler:** 5 sipariş, 11 sipariş kalemi -> **Fark: 0**

### 3. ERKUL ÇEYİZ (PostgreSQL VPS Aktarımı)
- **Ürün Sayısı:** 26 ürün -> **Fark: 0**
- **Müşteri (Cari):** 401 müşteri (401/401 müşteri kayıpsız yerleştirildi) -> **Fark: 0**
- **Cari Bakiye:** **-523.620,00 TL** (-52.362.000 kuruş borç) -> **Kuruşu kuruşuna mutabık**
- **Defter Hareketleri:** 539 müşteri cari hareketi -> **Fark: 0**
- **Satışlar & Siparişler:** 5 satış, 5 satış kalemi, 1 müşteri siparişi -> **Fark: 0**

---

## 5. VERİ GÜVENLİĞİ VE İZOLASYON GARANTİLERİ

1. **Çapraz Bulaşma Sıfır (Zero Cross-Tenant Bleed):**
   Her işletmenin verisi tamamen ayrı `.db` dosyalarındadır. Nutopia müşterisi Erkul Çeyiz'de veya Serenut'ta asla görünmez.
2. **Kriptografik İki Katmanlı Güvenlik:**
   Hem ham SQLite/JSON verileri hem de yeni Core Next veritabanları diskte korunmakta ve hash manifestolarıyla kilitlenmiş durumdadır.
3. **Fail-Closed Koruması:**
   Üretim ortamındaki feature flag (`coreNextSalesEngineEnabledProvider`) kapalı tutulmaktadır. Kullanıcı onay verene kadar canlı satış ekranı eski güvenli akışta kalır.
