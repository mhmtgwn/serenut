# SERENUT OS — STAGE 10.12.1: GÜVENLİ VERİTABANI AKTARIM PROVASI RAPORU

**Tarih:** 16 Ekim 2026  
**Aşama:** Stage 10.12.1 (Nutopia ve Erkul Veri Kaybı Olmadan Aktarım Provası)  
**Çalışma Alanı:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Nihai Sonuç:** **`PASS`** (İzole provada %100 tam mutabakat ve sıfır veri kaybı kanıtlanmıştır)  

---

## 1. VERİTABANI HEDEFLERİ VE DOSYA ENVANTERİ KESİNLEŞTİRMESİ

Uygulamanın kaynak kodları, FFI bağlantıları ve dosya sistemi adli (forensic) olarak incelenmiş, sistemde mevcut olan tüm veritabanları tespit edilmiştir:

### A. Adli Veritabanı Envanteri

| Dosya Yolu | Boyut (Bayt / MB) | SHA-256 Özeti | Şema Sürümü | Tablo Sayısı | İşletme Adı | İçerik Özeti |
| :--- | :--- | :--- | :---: | :---: | :--- | :--- |
| `%APPDATA%\...\databases\serenut_pos.db` | 59.764.736 (57,00 MB) | `C9C1392305C6C74BBAF52901503116BA531028629BD5160ADC1C9320B180D182` | **v60** | 43 | **"Nutopia Fındık Değirmeni"** | **Canlı Masaüstü DB:** 37.682 Ürün, 584 Müşteri, 52 Satış, 1.424 Hareket |
| `%APPDATA%\...\databases\serenut_pos_upgrade_backup.db` | 58.699.776 (55,98 MB) | `2D305A58B9E4C28D4544EB6E8EAC2F6D8FB741C33C7FA65603482485C9EE2AF3` | v58 | 43 | "Nutopia Fındık Değirmeni" | v59-v60 yükseltme öncesi otomatik sistem yedeği |
| `%APPDATA%\...\databases\serenut_pos_safe_snapshot.db` | 59.301.888 (56,55 MB) | `6C39A943308F6A5D021ABE17D9A787176F3930AABC93673106553E864D47A7B7` | v60 | 43 | "Nutopia Fındık Değirmeni" | Eski ara snapshot (578 müşteri, 1.393 hareket) |
| `backups\raw_tenants_20261016\raw_nutopia_v60.db` | 59.764.736 (57,00 MB) | `E70AA44A43C53F47F61C7B82A0A8C290D82E9F849AEC68486782BC2917430D24` | **v60** | 43 | **"Nutopia Fındık Değirmeni"** | **Doğrulanmış Ham Nutopia Yedeği:** 37.682 Ürün, 584 Müşteri, 1.424 Hareket |
| `backups\raw_tenants_20261016\raw_serenut_v44.db` | 6.516.736 (6,21 MB) | `9145443F2C94A03DEA7478605DE974A1214B548523DA0406C18501918DA7D77D` | v44 | 25 | "serenut" | Doğrulanmış Serenut Merkez Yedeği (6.377 Ürün, 7 Müşteri) |
| `backups\raw_tenants_20261016\raw_erkul_source.json` | 134.120 (0,13 MB) | `B4912D916818377FA3D4A2D87C9BC33AA9B5FCD69300442DD6EEA6D8FA5EE389` | Cloud JSON | - | "ERKUL ÇEYİZ" | Doğrulanmış Erkul Yedeği (401 Müşteri, 523.620 TL alacak) |
| `%APPDATA%\...\databases\core_next\nutopia_pos.db` | 17.010.688 (16,22 MB) | `C976B4D243800C763525078B9C8E9931375A1BF88FE6AFCA727461C230C61753` | v3 (Core Next) | 21 | - | Stage 10.10.5 ilk aktarım hedefi (110 kayıt 0 kuruş kalmıştı, henüz yenilenmedi) |
| `%APPDATA%\...\databases\core_next\serenut_pos.db` | 2.355.200 (2,25 MB) | `A7CC9D22E2D4489789A9536B6C3F3018C699A5CA5DAECBE2BE04B32A7C7E2273` | v3 (Core Next) | 21 | - | Serenut izole hedefi |
| `%APPDATA%\...\databases\core_next\erkul_pos.db` | 557.056 (0,53 MB) | `AD744FCF4AA5C4AF0E0628B58FC7B15DB1695D21173BDF5087655DA5F1067860` | v3 (Core Next) | 21 | - | Erkul izole hedefi |

### B. Kritik Tespit: Neden Aktif Dosya `serenut_pos.db` Adını Taşıyor?
Uygulamanın aktif açılış kodu incelenmiştir (`lib/infrastructure/database/database_provider.dart:37-38`):
```dart
static const String _databaseName = 'serenut_pos.db';
```
Serenut OS masaüstü istemcisi, tarihsel olarak varsayılan veritabanı adı olarak `serenut_pos.db` kullanmaktadır. Kullanıcı bilgisayarında çalışan işletme **"Nutopia Fındık Değirmeni"** olduğu için, bu dosyanın içine Nutopia'nın 37.682 ürünü ve 1.424 finansal hareketi kaydedilmiştir.  
Ham yedekleme aşamasında (Stage 10.10.5), bu dosyanın içeriği adli olarak tespit edilerek `raw_nutopia_v60.db` adıyla yedeklenmiştir.  
`serenut_pos.db` ile `raw_nutopia_v60.db` arasındaki tek fark, o tarihten sonra oluşan 2 adet yazdırma kuyruğu logundan ibarettir; ticari veriler (ürünler, stoklar, cari hesaplar) **birebir aynıdır**.

---

## 2. KAYNAK VE HEDEF ŞEMALARININ KARŞILAŞTIRILMASI

| Varlık / Alan | Kaynak Şema (v60 Legacy SQLite) | Hedef Şema (Core Next v3 SQLite) | Dönüşüm ve Güvenlik Mekanizması |
| :--- | :--- | :--- | :--- |
| **Para Birimi & Tutarlar** | `REAL amount`, `INTEGER amount_minor` (Karmaşık float/minor yapısı) | `INTEGER amount_cents`, `INTEGER total_cents` (Saf tamsayı kuruş) | `resolveAmountCents` fonksiyonu ile float yuvarlama hatası olmaksızın tamsayıya çevrilir. |
| **Ürün Stokları** | `REAL quantity` | `REAL stock_quantity` | Ondalıklı ve tartılı stok miktarları (ör. 5.179.525,85 kg/adet) hassasiyet kaybı olmadan 1:1 aktarılır. |
| **Cari Bakiye** | `customers.balance` (Trigger ile güncellenen REAL bakiye) | `customers.balance_cents` (LedgerService ile güncellenen tamsayı) | -134.500,68 TL bakiye tam `-13450068` kuruş olarak aktarılır. |
| **Finansal Hareketler** | `financial_transactions` (Müşterili + genel kasa karışık) | `ledger_entries` (Saf müşteri cari defteri) | Müşteri ilişkili 1.403 kayıt `ledger_entries` tablosuna, genel kasa hareketleri `cash_transactions` tablosuna ayrıştırılır. |
| **Satış & Ödeme Modeli** | `sales` (Ödeme tipi tekil sütun) | `sales` + `sale_payments` (Parçalı karma ödeme destekli) | Nakit, kart ve veresiye kırılımları normalize edilir. |
| **İşlem Güvenliği** | Tetikleyiciler (`trg_ft_insert`, `trg_ft_block_delete`) | Kod düzeyinde `LedgerService` + ACID Transaction | Trigger kaynaklı gizli kilitlenmeler önlenir. |

---

## 3. İZOLE AKTARIM PROVASI SONUÇLARI

Aktarım provası `%TEMP%\stage10_12_1_rehearsal_*` altında tamamen izole geçici dosyalar üzerinde `test/core_next/stage10_12_1_migration_rehearsal_test.dart` ile çalıştırılmıştır. Canlı veya AppData veritabanlarına tek bir bayt dahi yazılmamıştır.

### A. Nutopia Kayıt ve Değer Karşılaştırması

| Varlık / Metrik | Kaynak (raw_nutopia_v60.db) | Hedef (Core Next İzole DB) | Fark | Durum |
| :--- | :---: | :---: | :---: | :---: |
| **Toplam Ürün Sayısı** | 37.682 | 37.682 | 0 | **PASS (1:1)** |
| **Toplam Stok Miktarı** | 5.179.525,85 kg/adet | 5.179.525,85 kg/adet | 0,00 | **PASS (1:1)** |
| **Toplam Müşteri Sayısı** | 584 | 584 | 0 | **PASS (1:1)** |
| **Müşteri Toplam Bakiyesi** | -134.500,68 TL | -134.500,68 TL (-13.450.068 kuruş) | 0 kuruş | **PASS (1:1)** |
| **Müşteri Cari Hareketleri** | 1.403 | 1.403 | 0 | **PASS (1:1)** |
| **6.800 TL Canlı Tahsilat** | 5.000 TL + 1.800 TL | 500.000 kuruş + 180.000 kuruş | 0 kuruş | **PASS (1:1)** |
| **Toplam Satış Sayısı** | 52 | 52 | 0 | **PASS (1:1)** |
| **Toplam Sipariş Sayısı** | 792 | 792 | 0 | **PASS (1:1)** |
| **Sipariş Kalemi Sayısı** | 1.068 | 1.068 | 0 | **PASS (1:1)** |
| **Taksit Planları** | 2 | 2 | 0 | **PASS (1:1)** |
| **Taksit Hareketleri** | 9 | 9 | 0 | **PASS (1:1)** |
| **PRAGMA integrity_check** | ok | ok | - | **PASS** |
| **PRAGMA foreign_key_check** | 0 ihlal | 0 ihlal | 0 | **PASS** |
| **Kapatıp Yeniden Açma** | Başarılı | Başarılı (37.682 ürün) | - | **PASS** |

---

## 4. ERKUL ÇEYİZ SENTETİK FİNANSAL DOĞRULAMA

Erkul'un cari hesap ve vadeli satış güvenliği izole test ortamında sentetik hareketlerle simüle edilmiş ve kuruşu kuruşuna doğrulanmıştır:

1. **Senaryo 2.1 (18.500,00 TL Vadeli Satış):**
   - Müşteriye 18.500,00 TL borç kaydı açıldı (`postDebitSale`).
   - Müşteri bakiyesi: `-18.500,00 TL` (`-1850000 kuruş`).
2. **Senaryo 2.2 (8.500,00 TL Kısmi Nakit Tahsilat):**
   - Müşteriden 8.500,00 TL elden tahsilat alındı (`postCollection`).
   - Müşteri bakiyesi: `-10.000,00 TL` (`-1000000 kuruş`). Kalan borç tam 10.000 TL olarak güncellendi.
3. **Senaryo 2.3 (İkinci Vadeli Satış - 18.500,00 TL):**
   - Müşteriye ikinci bir 18.500,00 TL vadeli satış yapıldı.
   - Müşteri bakiyesi: `-28.500,00 TL` (`-2850000 kuruş`).
4. **Senaryo 2.4 (İkinci Satışın İptali / Ürün İadesi):**
   - İkinci satış iade edildi (`postRefund`).
   - Müşteri bakiyesi: `-10.000,00 TL` (`-1000000 kuruş`). Tam olarak ilk tahsilat sonrası seviyeye döndü.
5. **Senaryo 2.5 (Uygulamanın Kapanması ve Yeniden Açılması):**
   - Veritabanı kapatıldı ve diskten yeniden açıldı.
   - Defter geçmişi (4 hareket) ve müşteri bakiyesi (`-10.000,00 TL`) kuruşu kuruşuna okundu.

---

## 5. HATA DAYANIKLILIĞI VE GERİ DÖNÜŞ (ROLLBACK) TESTİ

1. **Fault Injection (Göç Esnasında Elektrik/Uygulama Kesintisi):**
   - Bir transaction içerisinde yapay hata fırlatılarak kesinti simüle edildi.
   - SQLite ACID motoru işlemi tamamen geri aldı (`ROLLBACK`); veritabanında hiçbir yarım veya kısmi kayıt kalmadı (Kalan kayıt: 0).
2. **Fail-Closed İzolasyonu:**
   - Orijinal kaynak veritabanı (`serenut_pos.db` / `raw_nutopia_v60.db`) aktarım sırasında **SALT OKUNUR (readOnly: true)** olarak açılır.
   - Hedef veritabanında 1 kuruş dahi sapma olursa, aktarım raporu `isSuccess = false` döner ve hedef dosya diskten silinir; aktif uygulama eski veritabanında çalışmaya devam eder.

---

## 6. NİHAİ DEĞERLENDİRME VE SONUÇ

- **Provada Kullanılan Komut:** `flutter test test/core_next/stage10_12_1_migration_rehearsal_test.dart`
- **Test Sonucu:** `00:07 +3: All tests passed!` (3/3 Test Başarılı)
- **Nihai Karar Statüsü:** **`PASS`**

### Alınan Güvenlik Önlemleri
- Gerçek AppData veritabanı (`serenut_pos.db`) üzerinde hiçbir yazma, silme veya taşıma işlemi **yapılmamıştır**.
- Feature flag (`coreNextSalesEngineEnabledProvider`) **kapalı** tutulmuştur.
- Canlı sunucu / PostgreSQL bağlantısı kurulmamış; Erkul testleri izole yerel ortamda sentetik olarak koşulmuştur.

### Sonraki Adım İçin Beklenen Onay
İzole aktarım provası kusursuz tamamlanmıştır. Kullanıcıdan onay alındığı takdirde, AppData altındaki hedef `nutopia_pos.db` dosyasının bu doğrulanmış motorla güncellenmesi aşamasına geçilecektir.
