# SERENUT OS — STAGE 10.12.68
# ERKUL BAKİYE SEMANTİĞİ VE ÜÇ İŞLETME FİNANSAL SON KANIT DENETİMİ (FINAL FORENSIC AUDIT REPORT)

**Tarih:** 21 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Branch:** `main`  
**Amaç:** Erkul Çeyiz kaynak bakiyesi (`-523,620.00 TL`) ile hedef bakiye (`-3,787,125.00 TL`) arasındaki farkın matematiksel ve sistemsel kök nedenini müşteri bazında adli kanıtlarla çözmek; 20 silinmiş müşteriyi ayrı ayrı analiz etmek; üç işletmenin toplam 1,985 finansal hareketini satır satır (1-to-1) eşleştirerek eksik, fazla, mükerrer hareket bulunmadığını bağımsız olarak kanıtlamak.

---

## 1. GİT BAŞLANGIÇ DURUMU DOĞRULAMASI

```powershell
git rev-parse HEAD        # 28c158d88028f139e93f78982d4651ad424c61d2
git branch --show-current   # main
git diff --check           # Exit Code: 0 (Temiz, whitespace hatası yok)
git log -5 --oneline       # 28c158d8 fix(test): align splash screen error title expectation...
```

- Kullanıcı değişiklikleri titizlikle korunmuş, hiçbir checkout/reset uygulanmamıştır.
- Değişmez Güvenlik Durumu:
  - `coreNextSalesEngineEnabledProvider = false`
  - `DatabaseManager.databaseRoutingHook = null`
  - `coreNextSaleExecutorProvider = null`
  - Canlı veritabanına yazma, cutover, migration, repair, commit, push ve release kesinlikle yapılmamıştır.

---

## 2. ALTI KAYNAK VE HEDEF DOSYASININ KİMLİĞİ VE SHA-256 ÖZETLERİ

Tüm dosyalar salt-okunur olarak incelenmiş, boyut ve SHA-256 özetleri doğrulanmıştır:

| İşletme & Dosya | Dosya Yolu | Boyut (Bayt) | SHA-256 Özeti | Bütünlük (`integrity_check`) |
|---|---|---|---|---|
| **Nutopia Ham Kaynak** | `backups/raw_tenants_20261016/raw_nutopia_v60.db` | 59,764,736 | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | `ok` (FK Violations: 0) |
| **Nutopia İzole Hedef** | `backups/stage64_isolated/nutopia/nutopia_core_next.db` | 17,018,880 | `8f270986277d661c021d75e85e25352bccb18b48ff8db6f088b9f5fbea95a300` | `ok` (FK Violations: 0) |
| **Serenut Ham Kaynak** | `backups/raw_tenants_20261016/raw_serenut_v44.db` | 6,516,736 | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | `ok` (FK Violations: 0) |
| **Serenut İzole Hedef** | `backups/stage64_isolated/serenut/serenut_core_next.db` | 2,359,296 | `5381dad1293d0137fb6bcb5c25dd03c5b9b72f7b786b1e6de8b1cfb174ebdcd4` | `ok` (FK Violations: 0) |
| **Erkul Ham Kaynak** | `backups/raw_tenants_20261016/raw_erkul_source.json` | 485,357 | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | Geçerli JSON (16 Grup) |
| **Erkul İzole Hedef** | `backups/stage64_isolated/erkul/erkul_core_next.db` | 565,248 | `3eed571fe49a4ac6cd33507a256bb7b4de8951ed15fb1944ee9a7c5167046ca1` | `ok` (FK Violations: 0) |

---

## 3. ERKUL BAKİYE FARKININ MÜŞTERİ BAZINDA ÇÖZÜMÜ VE KESİN KANITI

Erkul Çeyiz kaynak JSON dosyasındaki 401 müşterinin tamamı ve 539 finansal hareket satır satır analiz edilmiştir:

### 1. Yeniden Hesaplanan Temel Büyüklükler (Ham Dosyadan Doğrudan)

- **Toplam Müşteri:** **401 adet** (381 Aktif, 20 Silinmiş).
- **Toplam Finansal Hareket:** **539 adet**:
  - `manual_debt`: 423 adet | Tutar: `4,310,745.00 TL` | Borç: `4,310,745.00 TL` | Ödenen: `0.00 TL`
  - `collection`: 109 adet | Tutar: `541,640.00 TL` | Borç: `0.00 TL` | Ödenen: `541,640.00 TL`
  - `sale`: 6 adet | Tutar: `30,030.00 TL` | Borç: `18,030.00 TL` | Ödenen: `12,000.00 TL`
  - `payment`: 1 adet | Tutar: `10.00 TL` | Borç: `0.00 TL` | Ödenen: `10.00 TL`
- **Kaynak `customers.balance` Toplamları:**
  - 401 Müşterinin Tümü: `-523,620.00 TL`
  - 381 Aktif Müşteri: `-366,080.00 TL`
  - 20 Silinmiş Müşteri: `-157,540.00 TL`

### 2. Kök Neden Kanıtı: Kaynak Sistemdeki `balance` Alanının Anlamı

Erkul Çeyiz'in eski veritabanı kodunda ve verilerinde yapılan analiz şu açık gerçeği ortaya çıkarmıştır:
1. **Eski Sistem Borç Kaydını Bakiyeye İşlememiştir:**  
   Kasiyer bir müşteriye senetli çeyiz sözleşmesi (`manual_debt`) açtığında, müşterinin `balance` alanına borç tutarı EKLENMEMİŞ, bakiye `0.00 TL` olarak bırakılmıştır.
2. **Eski Sistem Yalnızca Tahsilatları Eksi Biriktirmiştir:**  
   Müşteri taksit ödediğinde (`collection`), eski sistem bu ödemeyi bakiyeden düşmüştür ($0.00 - \text{Tahsilat} = -\text{Tahsilat}$).
3. **Matematiksel İspat (397 / 401 Müşteri, %99):**  
   401 müşterinin 397'sinde kaynak `customers.balance` değeri, o müşteriye ait tahsilatların eksi toplamına ($-\sum \text{collection}$) **kuruşu kuruşuna eşittir**!
   - 381 aktif müşterinin toplam kaynak bakiyesi: **`-366,080.00 TL`**.
   - 381 aktif müşterinin toplam tahsilat tutarı: **`+366,080.00 TL`**.
   - Bu durum bir tesadüf değil; eski sistemin `balance` alanını bir net bakiye olarak değil, **"Kümülatif Ödeme Sayacı"** olarak kullandığının tartışmasız kanıtıdır.

### 3. Örnek Müşteri Tablosu (Neden Eski Bakiye Kullanılamaz?)

| Müşteri ID & Adı | Sözleşme Borcu (`manual_debt`) | Yapılan Tahsilat (`collection`) | Kaynak `balance` (Eski Sistem) | Gerçek Kalan Borç (Alacak) | Hedef `balance_cents` (Core Next) |
|---|---|---|---|---|---|
| `352c9f69` CEYHAN ERKUL | 7,800.00 TL | 0.00 TL | **0.00 TL** | **7,800.00 TL Borçlu** | **-780,000 kuruş** (-7,800 TL) |
| `0ff57e59` DURKADIN YÜKSEL | 26,700.00 TL | 0.00 TL | **0.00 TL** | **26,700.00 TL Borçlu** | **-2,670,000 kuruş** (-26,700 TL) |
| `a078b63e` GAMZE KARAHAN | 1,200.00 TL | 1,200.00 TL | **-1,200.00 TL** | **0.00 TL (Borcu Bitti)** | **0 kuruş** (0.00 TL) |
| `c0e52784` BEYTULLAH BİNGÜL | 35,900.00 TL | 0.00 TL | **0.00 TL** | **35,900.00 TL Borçlu** | **-3,590,000 kuruş** (-35,900 TL) |

> [!CRITICAL]
> Eğer kaynak `balance` alanı doğrudan aktarılsaydı:
> - Gamze Karahan (1.200 TL borcunu son kuruşuna kadar ödemiş ve kapatmış) sisteme **"Mağazadan 1.200 TL alacaklı"** olarak geçecekti!
> - Ceyhan Erkul ve Durkadın Yüksel (sırasıyla 7.800 TL ve 26.700 TL senet imzalamış ve henüz ödeme yapmamış) **"0 TL borçsuz"** görünecek ve 4,153,205.00 TL'lik senetli alacak buharlaşacaktı!

### 4. Hedef Bakiye Rekonstrüksiyon Formülü ve İspatı

Core Next ve Serenut OS çift taraflı defter standardı uyarınca:
$$\text{Reconstructed Balance} = - (\text{manual\_debt} + \text{sale\_debt}) + \text{collection} + \text{payment}$$
- **381 Aktif Müşteri İçin:**
  - Toplam Sözleşme Borcu: `4,153,205.00 TL`
  - Toplam Tahsilat: `366,080.00 TL`
  - Gerçek Müşteri Alacağı (Receivable): **`3,787,125.00 TL`**
  - Hedef Kuruş Bakiye Toplamı: **`-378,712,500 kuruş` (`-3,787,125.00 TL`)**.

---

## 4. ERKUL SİLİNMİŞ MÜŞTERİLERİNİN AYRI ANALİZİ (20 MÜŞTERİ)

Erkul Çeyiz'deki 20 silinmiş müşteri tek tek incelenmiştir:

| Müşteri ID & Adı | Borçlar Toplamı | Ödemeler Toplamı | Net Gerçek Bakiye | Kaynak `balance` | Hedef `balance_cents` |
|---|---|---|---|---|---|
| `31e32d8d` TUNAHAN | 6,000.00 TL | 6,000.00 TL | **0.00 TL** | 0.00 TL | **0** |
| `e3e36b0c` MEHMET GUVEN | 59.00 TL | 59.00 TL | **0.00 TL** | -59.00 TL | **0** |
| `03285fae` TUNAHAN | 4,700.00 TL | 4,700.00 TL | **0.00 TL** | -4,700.00 TL | **0** |
| `43b50a69` MEHMET TEKİN ORTACI | 5,000.00 TL | 5,000.00 TL | **0.00 TL** | -5,000.00 TL | **0** |
| `0028dece` AYTEN BİNGÜL | 8,650.00 TL | 8,650.00 TL | **0.00 TL** | -8,650.00 TL | **0** |
| `a3846e7d` AAAAA | 1,000.00 TL | 1,000.00 TL | **0.00 TL** | -1,000.00 TL | **0** |
| `154791d1` TUNA | 5,000.00 TL | 5,000.00 TL | **0.00 TL** | -5,000.00 TL | **0** |
| `6357fe13` ABDULLAH SEVİM | 75,550.00 TL | 75,550.00 TL | **0.00 TL** | -75,550.00 TL | **0** |
| `6202aec0` TUN | 4,000.00 TL | 4,000.00 TL | **0.00 TL** | -4,000.00 TL | **0** |
| `4893563b` BBBBB | 500.00 TL | 500.00 TL | **0.00 TL** | -500.00 TL | **0** |
| `3d8b3cd6` TUNAHAN | 60.00 TL | 60.00 TL | **0.00 TL** | -50.00 TL | **0** |
| `eee08eca` TUNAHAN | 75.00 TL | 75.00 TL | **0.00 TL** | -55.00 TL | **0** |
| `70d5cece` HİLAL ERKUL | 25,000.00 TL | 25,000.00 TL | **0.00 TL** | -25,000.00 TL | **0** |
| `9ce8242a` TUNAHAN | 0.00 TL | 0.00 TL | **0.00 TL** | 0.00 TL | **0** |
| `b930b990` TUNAHAN | 12,000.00 TL (vadeli) | 12,000.00 TL | **0.00 TL** | 0.00 TL | **0** |
| `0e3a6dbd` ABDULLAH SEVİM HAS. | 0.00 TL | 0.00 TL | **0.00 TL** | 0.00 TL | **0** |
| `b97a0544` DKLMVCMDL | 5,200.00 TL | 5,200.00 TL | **0.00 TL** | -5,200.00 TL | **0** |
| `f938cb80` QQWDSASADA | 5,000.00 TL | 5,000.00 TL | **0.00 TL** | -5,000.00 TL | **0** |
| `8789fbbf` NNNJKJKJ | 0.00 TL | 0.00 TL | **0.00 TL** | 0.00 TL | **0** |
| `b2f9c7e1` AJOSIUSUUIS | 17,776.00 TL | 17,776.00 TL | **0.00 TL** | -17,776.00 TL | **0** |

**Bulgular:**
1. 20 silinmiş müşterinin **20'sinde de borçlar ile ödemeler kuruşu kuruşuna birbirine eşittir** ($\text{Debts} \equiv \text{Paid}$).
2. Müşteriler borçlarını tamamen ödedikten sonra mağaza tarafından silinmiş/arşivlenmiştir.
3. Hedefte bu müşterilere `0 kuruş` bakiye verilmesi yapay bir sıfırlama değil, **çift taraflı defter hesabının doğal matematiksel sonucudur**.
4. Kaynakta görünen `-157,540.00 TL` negatif bakiye, sadece ödenen paraların birikmesinden ibarettir. Müşterilerin hiçbirinin mağazadan alacağı yoktur.

### Erkul Kararı

Aşağıdaki durum tartışmasız kanıtlanmıştır:
> **Durum 1:** Kaynak `customer.balance` alanı eski sistemde eksik veya farklı amaçla (yalnızca ödeme sayacı olarak) kullanılıyor; hedefte ledger üzerinden hesaplanan bakiye belgelenmiş iş kuralıyla kuruşu kuruşuna doğrudur.

**Karar Kodu:** `ERKUL_BALANCE_SEMANTICS_VERIFIED_ISOLATED_ONLY`

---

## 5. ÜÇ İŞLETMEDE 1,985 FİNANSAL HAREKETİN SATIR BAZINDA (1-TO-1) EŞLEŞTİRİLMESİ

Üç işletmenin kaynaklarındaki tüm finansal hareketler hedef veritabanlarındaki `ledger_entries` ve `cash_transactions` kayıtlarıyla ID, müşteri ID, işlem türü ve kuruş tutarı bazında tek tek eşleştirilmiştir:

| İşletme | Kaynak Finansal Hareket | Hedef Defter (`ledger_entries`) | Hedef Kasa (`cash_transactions`) | Bire Bir Eşleşen | Eksik Kayıt | Fazla Kayıt | Mükerrer | Tutar/Kuruş Farkı |
|---|---|---|---|---|---|---|---|---|
| **Nutopia** | 1,424 | 1,403 | 21 | **1,424 / 1,424 (%100)** | 0 | 0 | 0 | **0 kuruş** |
| **Serenut** | 22 | 12 | 10 | **22 / 22 (%100)** | 0 | 0 | 0 | **0 kuruş** |
| **Erkul Çeyiz** | 539 | 539 | 0 | **539 / 539 (%100)** | 0 | 0 | 0 | **0 kuruş** |
| **TOPLAM** | **1,985** | **1,954** | **31** | **1,985 / 1,985 (%100)** | **0** | **0** | **0** | **0 kuruş** |

- **ID Eşleşmesi:** 1,985 kaydın tamamında hedef `id` kaynak `id` ile karakteri karakterine özdeştir.
- **Carisiz Kasa Satışları Ayrımı:** Nutopia'da 21, Serenut'ta 10 adet müşteri kimliği boş olan nakit satış hareketi, cari defteri kirletmemek adına `cash_transactions` tablosuna aktarılmıştır.
- **Anlamı Belirsiz veya Eşleşmeyen Hareket Sayısı:** **0**.

---

## 6. NUTOPIA SENET İŞLEMLERİ VE SERENUT STOK DAĞILIMI DOĞRULAMASI

### 1. Nutopia Senet İşlemleri Korunma Doğrulaması

- 54 adet `manual_debt` kaydı (`103,351.00 TL` $\equiv$ `10,335,100 kuruş`) hedefte korunmaktadır.
- 2 taksit planı (1 aktif, 1 iptal edilmiş) ve 9 taksit kalemi hedefte korunmaktadır.
- 8 adet taksit tahsilatı (`9,753.32 TL` $\equiv$ `975,332 kuruş`) hedefte korunmaktadır.
- Satış kayıtlarıyla kesişim sıfırdır (`0`).

### 2. Serenut Stok Dağılımı Korunma Doğrulaması

- 6,368 adet / piece ürün (stok: `636,640.0`).
- 9 kg ürün (stok: `805.0` kg).
- 'Mancar' ürününün `sale_type = 'weighed'` kuralı uyarınca kg sınıfında olduğu ve çelişkinin tamamen çözüldüğü teyit edilmiştir.

---

## 7. TESTLERİN KANIT NİTELİĞİ VE SINIRLAMALARI

| Test Dosyası | Tip | Salt-Okunur mu? | Satır Satır 1-to-1 Kontrol | Sınırlama / Güvenlik Derecesi |
|---|---|---|---|---|
| `stage10_12_64_full_scale_export_import_test.dart` | Entegrasyon | Hayır (Hedefi baştan yazar) | Hayır (Sayaç ve bakiye toplamı) | Yalnızca göç motorunu doğrular, statik hedef denetimi için kullanılamaz. |
| `stage10_12_66_nutopia_promissory_independent_audit_test.dart` | Adli Denetim | **Evet (`openReadOnlyDatabase`)** | Evet (54 senet + 584 cari) | Nutopia için tam adli kanıt. |
| `stage10_12_67_three_tenant_independent_audit_test.dart` | Adli Denetim | **Evet (`openReadOnlyDatabase`)** | Kısmi (Grup sayaçları ve toplamlar) | Üç işletmenin kiracı kimliklerini ve genel mutabakatını kanıtlar. |
| `stage10_12_68_erkul_balance_and_financial_final_audit_test.dart` | Adli Denetim | **Evet (`openReadOnlyDatabase`)** | **Evet (1,985 hareketin tamamı satır satır)** | **En yüksek kanıt düzeyi (0 yazma, 1,985/1,985 eşleşme).** |

### Stage 68 Test Çıktısı

```powershell
flutter test test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart
# 00:01 +9: All tests passed! (Exit Code: 0, 1.8s)

flutter analyze test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart
# No issues found! (ran in 5.6s, Exit Code: 0)
```

---

## 8. ÇALIŞTIRILAN KOMUTLAR VE ÇIKIŞ KODLARI

| Komut | Amaç | Exit Code | Çıktı Özeti |
|---|---|---|---|
| `git rev-parse HEAD; git branch; git diff --check` | Git durum doğrulaması | 0 | HEAD: `28c158d88...`, Clean |
| `python scratch/stage68_erkul_balance_deep_dive.py` | Erkul müşteri bakiye semantiği derin analizi | 0 | 397/401 müşteride balance == -collections kanıtlandı |
| `python scratch/stage68_line_by_line_audit.py` | 1,985 finansal hareketin satır satır 1-to-1 kontrolü | 0 | Nutopia: 1424/1424, Serenut: 22/22, Erkul: 539/539 |
| `flutter test test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart` | Bağımsız adli test paketi | 0 | 9 testin tamamı başarılı (Passed) |
| `flutter analyze test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart` | Statik linter kontrolü | 0 | `No issues found!` |

---

## 9. NİHAİ KARARLAR

1. **Erkul Çeyiz:**  
   Kaynak `customer.balance` alanının yalnızca ödeme sayacı olduğu, borçların bakiyeye yansıtılmadığı, çift taraflı defter hesabıyla 381 aktif müşteride `3,787,125.00 TL` alacak (`-378,712,500 kuruş`) ve 20 silinmiş müşteride borçlar ödendiği için `0 kuruş` bakiye oluştuğu matematiksel kesinlikle kanıtlanmıştır.  
   **Karar:** `ERKUL_BALANCE_SEMANTICS_VERIFIED_ISOLATED_ONLY`

2. **Nutopia Fındık Değirmeni:**  
   54 manuel borç, 2 plan, 9 taksit, 8 taksit tahsilatı ve 1,424 hareketin tamamı satır satır kuruşu kuruşuna doğrulanmıştır.  
   **Karar:** `NUTOPIA_RECONCILIATION_PASS_ISOLATED_ONLY`

3. **Serenut:**  
   6,377 ürün (6,368 piece / 9 kg Mancar çözümü), 22 hareket ve -2,673.00 TL bakiye doğrulanmıştır.  
   **Karar:** `SERENUT_RECONCILIATION_PASS_ISOLATED_ONLY`

**GENEL NİHAİ SONUÇ:**  
```text
THREE_TENANT_RECONCILIATION_PASS_ISOLATED_ONLY
```

---

## 10. SON GÜVENLİK DURUMU

CUTOVER: NOT APPROVED  
LIVE DATABASE WRITES: NOT PERFORMED  
CORE NEXT SALES ENGINE: DISABLED  
DATABASE ROUTING HOOK: NULL  
OLD DATABASE RETIREMENT: NOT APPROVED  
