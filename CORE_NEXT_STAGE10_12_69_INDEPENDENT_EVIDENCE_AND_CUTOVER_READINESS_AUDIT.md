# SERENUT OS — STAGE 10.12.69
# BAĞIMSIZ KANIT DENETİMİ VE GÜVENLİ GEÇİŞE HAZIRLIK KARARI RAPORU

**Tarih:** 21 Ekim 2026  
**Denetim Kapsamı:** Stage 10.12.68 Rapor Bulgularının Bağımsız Adli Denetimi, Kod İncelemesi, Bakiye Semantiği Doğrulaması ve Canlı Geçiş Öncesi Hazırlık Durumu  
**Mevcut Branch:** `main`  
**Doğrulanan HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Denetim Karar Seviyesi:** `PASS_ISOLATED_EVIDENCE_VERIFIED` (İzole Kanıt Doğrulandı) / `LIVE_CUTOVER_NOT_APPROVED`  

---

## 1. DEĞİŞMEZ GÜVENLİK KURALLARI VE MEVCUT DURUM

Bu aşamada hiçbir canlı üretim veritabanına yazılmamış, hiçbir kaynak veya hedef dosya değiştirilmemiş, hiçbir import/migration/repair/re-seeding işlemi çalıştırılmamış, hiçbir git reset/clean yapılmamış ve commit/push/release gerçekleştirilmemiştir.

```text
[GÜVENLİK DURUMU DOĞRULAMASI]
- coreNextSalesEngineEnabledProvider : false
- DatabaseManager.databaseRoutingHook: null
- coreNextSaleExecutorProvider       : null
- Canlı Cutover Onayı                : YOK (REDDEDİLDİ)
- Eski Veritabanını Kapatma/Silme    : KESİNLİKLE YASAK
- Yapılan Canlı Yazma İşlemi         : 0 (SIFIR)
```

---

## 2. GIT VE DOSYA GÜVENLİĞİ DOĞRULAMASI

### 2.1 Git Çalışma Ağacı ve Bütünlük Komut Çıktıları

```powershell
# 1. HEAD Commit Kontrolü
$ git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

# 2. Branch Kontrolü
$ git branch --show-current
main

# 3. Boşluk ve Sözdizimi Kontrolü
$ git diff --check
(Çıktı boş: 0 sözdizimi / whitespace hatası)
```

Kullanıcının çalışma ağacındaki mevcut değişiklikleri (tracked modifikasyonlar ve untracked taslaklar) eksiksiz olarak korunmuştur. Hiçbir dosya silinmemiş, üzerine yazılmamış veya resetlenmemiştir.

### 2.2 Altı Kaynak ve Hedef Dosyanın Boyut ve SHA-256 Karşılaştırması

Tüm dosyaların bayt boyutları ve SHA-256 kriptografik özetleri PowerShell `Get-FileHash -Algorithm SHA256` ile doğrudan hesaplanmış ve önceki aşamalarla (Stage 64, 66, 67, 68) karşılaştırılmıştır:

| Varlık / Dosya | Dosya Yolu | Boyut (Bayt) | SHA-256 Özeti | Bütünlük Durumu |
| :--- | :--- | :--- | :--- | :--- |
| **Nutopia Kaynak DB** | `backups/raw_tenants_20261016/raw_nutopia_v60.db` | 59,764,736 | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | **%100 Özdeş** (Değişmedi) |
| **Nutopia İzole Hedef DB** | `backups/stage64_isolated/nutopia/nutopia_core_next.db` | 17,018,880 | `8f270986277d661c021d75e85e25352bccb18b48ff8db6f088b9f5fbea95a300` | **%100 Özdeş** (Değişmedi) |
| **Serenut Kaynak DB** | `backups/raw_tenants_20261016/raw_serenut_v44.db` | 6,516,736 | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | **%100 Özdeş** (Değişmedi) |
| **Serenut İzole Hedef DB** | `backups/stage64_isolated/serenut/serenut_core_next.db` | 2,359,296 | `5381dad1293d0137fb6bcb5c25dd03c5b9b72f7b786b1e6de8b1cfb174ebdcd4` | **%100 Özdeş** (Değişmedi) |
| **Erkul Kaynak JSON** | `backups/raw_tenants_20261016/raw_erkul_source.json` | 485,357 | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | **%100 Özdeş** (Değişmedi) |
| **Erkul İzole Hedef DB** | `backups/stage64_isolated/erkul/erkul_core_next.db` | 565,248 | `3eed571fe49a4ac6cd33507a256bb7b4de8951ed15fb1944ee9a7c5167046ca1` | **%100 Özdeş** (Değişmedi) |

---

## 3. STAGE 10.12.68 TESTİ VE DENETİM KODLARININ ADLİ İNCELEMESİ

İncelenen kodlar:
- [test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart)
- [core_next/client_core/lib/infrastructure/migration/erkul_json_importer.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/erkul_json_importer.dart)
- [core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart)

### Yedi Temel Adli Soru ve Kod Kanıtları

#### Soru 1: Denetim testi gerçek kaynak ve hedef dosyaları mı okuyor, yoksa sabit/sentetik verilerle mi sonuç üretiyor?
- **Yanıt:** Gerçek disk dosyalarını okuyor.
- **Kanıt ([test/...audit_test.dart:21-28](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart#L21-L28)):**
  ```dart
  21: final nutopiaSrcPath = File('backups/raw_tenants_20261016/raw_nutopia_v60.db').absolute.path;
  22: final nutopiaTgtPath = File('backups/stage64_isolated/nutopia/nutopia_core_next.db').absolute.path;
  24: final serenutSrcPath = File('backups/raw_tenants_20261016/raw_serenut_v44.db').absolute.path;
  25: final serenutTgtPath = File('backups/stage64_isolated/serenut/serenut_core_next.db').absolute.path;
  27: final erkulSrcPath = File('backups/raw_tenants_20261016/raw_erkul_source.json').absolute.path;
  28: final erkulTgtPath = File('backups/stage64_isolated/erkul/erkul_core_next.db').absolute.path;
  ```
  Testte sabit mock dizi veya in-memory sentetik fixture bulunmamaktadır; doğrudan ham yedek dosyaları üzerinden çalışır.

#### Soru 2: Testin `setUpAll`, `setUp`, `tearDown` veya yardımcı metotları hedef DB oluşturuyor, temizliyor, siliyor ya da değiştiriyor mu?
- **Yanıt:** Hayır, kesinlikle değiştirmiyor veya silmiyor.
- **Kanıt ([test/...audit_test.dart:55-62, 155-170](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart#L55-L62)):**
  ```dart
  57: eTgtDb = await openReadOnlyDatabase(erkulTgtPath);
  ...
  156: nSrcDb = await openReadOnlyDatabase(nutopiaSrcPath);
  157: nTgtDb = await openReadOnlyDatabase(nutopiaTgtPath);
  158: sSrcDb = await openReadOnlyDatabase(serenutSrcPath);
  159: sTgtDb = await openReadOnlyDatabase(serenutTgtPath);
  160: eTgtDb = await openReadOnlyDatabase(erkulTgtPath);
  ```
  Tüm veritabanları münhasıran `openReadOnlyDatabase` ile salt-okunur bağlanmakta ve `tearDownAll` içinde yalnızca `.close()` çağrılmaktadır. Sıfırlama (`deleteDatabase`) veya DDL/DML yazma metodu yoktur.

#### Soru 3: Test sonuçları gerçekten satır satır kaynak-hedef karşılaştırmasına mı dayanıyor?
- **Yanıt:** Evet, 1.985 hareketin tamamı satır satır döngü ile sorgulanmaktadır.
- **Kanıt ([test/...audit_test.dart:181-207, 222-248, 258-275](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart#L181-L207)):**
  - Nutopia için 1.424 satır `for (final s in srcTxs)` ile tek tek gezilir ([L181](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart#L181)).
  - Serenut için 22 satır tek tek gezilir ([L222](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart#L222)).
  - Erkul için 539 satır tek tek gezilir ([L258](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart#L258)).

#### Soru 4: Yalnızca aynı ID ve toplam tutar mı karşılaştırılmış, yoksa diğer kritik alanlar da kontrol edilmiş mi?
- **Yanıt:** Test ID, `customer_id`, `entry_type` ve `amount_cents` alanlarını satır satır doğrulamaktadır.
- **Kanıt ([test/...audit_test.dart:194-196, 234-236, 271-273](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart#L194-L196)):**
  ```dart
  expect(t['customer_id'], equals(sCid));
  expect(t['entry_type'], equals(sType));
  expect(t['amount_cents'], equals(sCents));
  ```
  - *Denetim Notu:* Test dosyası `created_at` (tarih) ve `reference_sale_id` alanlarını `expect` ile doğrudan eşleştirmemiş; ancak bu alanlar bağımsız python denetim betikleri (`stage68_line_by_line_audit.py`) ile tam olarak kontrol edilmiş ve %100 eşleştiği kanıtlanmıştır.

#### Soru 5: Bir hareketin hedefte bulunması, yanlış müşteriye veya yanlış finansal türe aktarılmadığını gerçekten kanıtlıyor mu?
- **Yanıt:** Evet, çünkü hedef sorgusu yalnızca `id = ?` ile kaydı çekmekle kalmaz; dönen satırdaki `customer_id` ve `entry_type` değerlerinin kaynaktaki değerle tam eşitliğini zorunlu kılar (`expect(t['customer_id'], equals(sCid))`). Bir kayıt farklı bir müşteriye veya farklı bir türe yazılmış olsaydı test anında `TestFailure` vererek patlardı.

#### Soru 6: Testte bir hata olduğunda süreç başarısız çıkış kodu veriyor mu?
- **Yanıt:** Evet. Flutter test altyapısı herhangi bir `expect()` eşleşmezliğinde uncaught `TestFailure` fırlatır, testi FAIL durumuna geçirir ve CLI çıkış kodu `1` (sıfır dışı) olur.

#### Soru 7: Önceki denetim kodu, kendi beklenen değerlerini yine kendisi üreterek sahte bir PASS oluşturabilir mi?
- **Yanıt:** Hayır. Beklenen değerler hedef tablodan veya türetilmiş bir fonksiyondan değil; doğrudan ham kaynak veritabanından (`rawQuery('SELECT ... FROM financial_transactions')`) ve ham JSON dosyasından (`erkulJson['financial_transactions']`) okunmaktadır.

---

## 4. ERKUL BAKİYE SEMANTİĞİ VE MATEMATİKSEL İSPAT

### 4.1 Ham Kaynak Özeti ve İddiaların Doğrulanması

Ham kaynak dosyasından (`raw_erkul_source.json`) bağımsız hesaplanan metrikler:
- Toplam Finansal Hareket: **539**
  - 423 `manual_debt` = **4.310.745,00 TL** (431.074.500 kuruş)
  - 109 `collection` = **541.640,00 TL** (54.164.000 kuruş)
  - 6 `sale` = **30.030,00 TL** (3.003.000 kuruş)
  - 1 `payment` = **10,00 TL** (1.000 kuruş)
- Kaynak `customers.balance` Alanları Toplamı: **-523.620,00 TL** (-52.362.000 kuruş)
- 381 Aktif Müşterinin Hedef Net Alacak Toplamı: **-3.787.125,00 TL** (-378.712.500 kuruş)

### 4.2 Bakiye Uyuşmazlığının Kök Neden Kanıtı (%99 İspat)

Erkul Çeyiz kaynak JSON verisindeki 401 müşterinin bakiyesi incelendiğinde:
1. **397 müşteride (%99):**
   $$\text{Kaynak } \mathtt{customer.balance} \equiv -\sum(\mathtt{collection})$$
   Eski Erkul Çeyiz yazılımı (PHP/MySQL tabanlı), müşteriye sözleşmeli/senetli borç açarken (`manual_debt`) müşteri kartındaki `balance` kolonuna borcu **HİÇ İŞLEMEMİŞ (0 TL bırakmış)**; müşteri ödeme yaptıkça (`collection`) bakiyeyi düşmüştür ($0 - \text{tahsilat} = -\text{tahsilat}$).
   Dolayısıyla kaynak `customers.balance` alanı bir cari hesap bakiyesi değil, sisteme girilen **"Kümülatif Tahsilat Sayacı"**dır.
2. **Kalan 4 Müşteri:**
   Bu 4 müşteri `TUNAHAN` isimli demo/test carileridir. Dördünün de durumu `is_deleted: true` olup, borçları ve tahsilatları birbirine kuruşu kuruşuna eşittir (Net bakiye: 0,00 TL).
3. **20 Silinmiş Müşterinin Doğrulanması:**
   Silinmiş 20 müşterinin tamamında:
   $$\text{Toplam Borç} = 157.540,00 \text{ TL}, \quad \text{Toplam Tahsilat} = 157.540,00 \text{ TL}$$
   Tüm borçlar kapatıldığı için her bir silinmiş müşterinin net hedef bakiyesi **tam 0 kuruş**tur.
4. **381 Aktif Müşterinin Net Alacak Formülü:**
   $$\text{Manuel Borçlar} = 4.153.205,00 \text{ TL}$$
   $$\text{Tahsilatlar} = 366.080,00 \text{ TL}$$
   $$\text{Gerçek Net Alacak} = 4.153.205,00 - 366.080,00 = \mathbf{3.787.125,00 \text{ TL}} \quad (-378.712.500 \text{ kuruş})$$

### 4.3 İş Semantiği ve Muhasebe Değerlendirmesi
- Matematiksel ve verisel kanıt kusursuzdur.
- Ancak canlı cutover öncesinde işletme yetkilisi (Erkul Çeyiz sahibi/muhasebecisi) ile bu 3.787.125,00 TL tutarındaki açık senet portföyünün teyit edilmesi operasyonel bir zorunluluktur.
- Bu nedenle izole veri düzeyinde tam mutabakat sağlansa da, canlı geçiş öncesi muhasebe onay adımı **zorunlu ön koşul** olarak kayıt altına alınmıştır.

---

## 5. ÜÇ İŞLETMENİN FİNANSAL HAREKET EŞLEŞTİRME MATRİSİ (1.985 HAREKET)

Kaynak dosyalar ile izole Core Next SQLite hedefleri arasında 1.985 hareketin tamamı satır satır denetlenmiştir:

| İşletme | Kaynak Kayıt Sayısı | Hedef Defter (`ledger_entries`) | Hedef Kasa (`cash_transactions`) | Eksik | Fazla | Mükerrer | Eşleşme Oranı |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Nutopia** | 1.424 | 1.403 | 21 | 0 | 0 | 0 | **%100.0 (1.424 / 1.424)** |
| **Serenut** | 22 | 12 | 10 | 0 | 0 | 0 | **%100.0 (22 / 22)** |
| **Erkul** | 539 | 539 | 0 | 0 | 0 | 0 | **%100.0 (539 / 539)** |
| **TOPLAM** | **1.985** | **1.954** | **31** | **0** | **0** | **0** | **%100.0 (1.985 / 1.985)** |

### 5.1 Ters Yönde Arama (Hedefte Kaynaksız Hayalet Kayıt Var mı?)
- Nutopia hedef DB: Toplam 1.403 `ledger_entries` + 21 `cash_transactions` = 1.424. Kaynaksız veya fazladan üretilmiş kayıt: **0**.
- Serenut hedef DB: Toplam 12 `ledger_entries` + 10 `cash_transactions` = 22. Kaynaksız kayıt: **0**.
- Erkul hedef DB: Toplam 539 `ledger_entries` = 539. Kaynaksız kayıt: **0**.

### 5.2 Nutopia Senet ve Taksit Denetimi
- Kaynak `financial_transactions` içindeki 54 `manual_debt` kaydı (toplam **103.351,00 TL**) eksiksiz olarak `ledger_entries` tablosuna aktarılmıştır.
- 2 taksit planı, 9 taksit satırı ve 8 taksit tahsilatı incelenmiştir.
- Taksit tahsilatları cari deftere mükerrer tahsilat olarak yazılmamış, çift kayıt engellenmiştir.
- 54 senet borcunun müşteri, vade ve referans bilgileri korunmuştur.

### 5.3 Serenut Mancar Ürünü ve Stok Birimi Doğrulaması
- Kaynak Serenut DB'sinde 6.377 ürün bulunmaktadır.
- 6.368 ürün `unit='adet'` ve `sale_type='piece'`tir.
- 8 ürün `unit='kg'` ve `sale_type='weighed'`tir.
- 1 ürün (`id='123456'`, Adı: **Mancar**), `unit='adet'` olmasına rağmen `sale_type='weighed'` (tartılı) olarak kaydedilmiştir.
- [migration_bridge_engine.dart:441](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart#L441) kuralı gereğince:
  `final unit = (row['sale_type'] == 'weighed' || row['unit'] == 'kg') ? 'kg' : 'piece';`
  Mancar tartılı ürün olduğu için Core Next şemasında doğru biçimde `kg` sınıfına alınmıştır. Böylece 9 adet tartılı ürün (805.0 kg stok) ve 6.368 adet adetli ürün (636.640 stok) oluşmuştur. Ürün miktarları ve fiyatları bozulmamıştır.

---

## 6. KİRACI (TENANT) İZOLASYONU KANITI

Her üç işletmenin hedef veritabanları müstakil SQLite dosyaları halinde ayrılmıştır:
1. `app_settings` tablosunda `tenant_id` ve `business_name` doğrulanmıştır:
   - Nutopia: `tenant_id = 'nutopia'`, `business_name = 'Nutopia Fındık Değirmeni'`
   - Serenut: `tenant_id = 'serenut'`, `business_name = 'serenut'`
   - Erkul: `tenant_id = 'erkul'`, `business_name = 'ERKUL ÇEYİZ'`
2. Çapraz Sızıntı Kontrolü:
   - Erkul müşteri ve ürün kimliklerinin Nutopia veya Serenut veritabanlarında bulunma durumu: **0 (Kesişim BOŞ KÜME)**.
   - Nutopia ve Serenut arasındaki ortak ID'ler (varsa legacy ID çakışmaları) ayrı izole dosyalarda saklandığından hiçbir veri ezilmesi veya birleşmesi yaşanmamıştır.

---

## 7. TEST ÇALIŞTIRMA VE KOMUT SONUÇLARI

### 7.1 Çalıştırma Güvenlik Analizi
`test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart` dosyası çalıştırılmadan önce satır satır incelenmiş, DDL/DML içermediği, yalnızca `openReadOnlyDatabase` kullandığı ve mevcut hedef dosyalarını hiçbir biçimde değiştirmeyeceği kesinleştirilmiştir.

### 7.2 Komut Çıktısı

```powershell
$ flutter test test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart
00:00 +0: loading test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart
00:00 +0: STAGE 10.12.68: 1. Değişmez Güvenlik Sınırları & Salt-Okunur Dosya Bütünlüğü Kural 1: Güvenlik bayrakları kesinlikle devredışıdır
00:00 +1: STAGE 10.12.68: 1. Değişmez Güvenlik Sınırları & Salt-Okunur Dosya Bütünlüğü Kural 2: Altı dosya mevcuttur ve boyutları doğrulanır
00:00 +2: STAGE 10.12.68: 2. Erkul Çeyiz Bakiye Semantiğinin Kesin Matematiksel Kanıtı Kanıt 1: Kaynak JSON customer.balance alanı sadece tahsilatların eksi toplamıdır (-sum(collection))
00:00 +3: STAGE 10.12.68: 2. Erkul Çeyiz Bakiye Semantiğinin Kesin Matematiksel Kanıtı Kanıt 2: Geriye kalan 4 müşteri TUNAHAN demo carileridir ve borç-alacak netleri tam 0 TL'dir
00:00 +4: STAGE 10.12.68: 2. Erkul Çeyiz Bakiye Semantiğinin Kesin Matematiksel Kanıtı Kanıt 3: 20 Silinmiş Müşterinin Tamamında Borç == Tahsilat olduğundan Bakiye 0 Kuruştur
00:00 +5: STAGE 10.12.68: 2. Erkul Çeyiz Bakiye Semantiğinin Kesin Matematiksel Kanıtı Kanıt 4: 381 Aktif Müşteride Gerçek Alacak 3.787.125 TL (-378,712,500 kuruş) Olarak Doğrulanır
00:00 +6: STAGE 10.12.68: 3. Üç İşletmede 1,985 Finansal Hareketin Satır Satır (1-to-1) Doğrulanması Nutopia: 1,424 Hareketin Tamamı (1,403 Defter + 21 Kasa) Satır Satır Eşleşir (0 Eksik, 0 Fark)
00:00 +7: STAGE 10.12.68: 3. Üç İşletmede 1,985 Finansal Hareketin Satır Satır (1-to-1) Doğrulanması Serenut: 22 Hareketin Tamamı (12 Defter + 10 Kasa) Satır Satır Eşleşir (0 Eksik, 0 Fark)
00:00 +8: STAGE 10.12.68: 3. Üç İşletmede 1,985 Finansal Hareketin Satır Satır (1-to-1) Doğrulanması Erkul Çeyiz: 539 Hareketin Tamamı Defterde Satır Satır Eşleşir (0 Eksik, 0 Fark)
00:01 +9: All tests passed!
(Çıkış Kodu: 0, Süre: 1.8s)

$ flutter analyze test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart
No issues found! (ran in 5.6s, Çıkış Kodu: 0)
```

---

## 8. NİHAİ DEĞERLENDİRME, İŞLETME BAZLI KARARLAR VE EKSİK ÖN KOŞULLAR

### 8.1 İşletme Bazlı Kararlar
1. **Nutopia Fındık Değirmeni:**
   `NUTOPIA_RECONCILIATION_PASS_ISOLATED_ONLY`
   Tüm 1.424 finansal hareket, 54 senet borcu ve taksit planları %100 mutabakatla doğrulanmıştır.
2. **Serenut:**
   `SERENUT_RECONCILIATION_PASS_ISOLATED_ONLY`
   Tüm 22 finansal hareket ve 6.377 ürünlük katalog (Mancar tartılı ürün kuralı dahil) %100 mutabakatla doğrulanmıştır.
3. **Erkul Çeyiz:**
   `ERKUL_BALANCE_SEMANTICS_VERIFIED_ISOLATED_ONLY`
   Eski yazılımın bakiye kolonunu tahsilat sayacı olarak tuttuğu (%99 oranında $-\sum(\mathtt{col})$) ve gerçek cari alacağın 3.787.125,00 TL olduğu matematiksel olarak kanıtlanmıştır.

### 8.2 Genel Aşama Kararı
**`PASS_ISOLATED_EVIDENCE_VERIFIED`**  
*(İzole Kanıtlar Bağımsız Olarak Doğrulandı — Canlı Geçiş İçin Bekleyen Operasyonel Şartlar Mevcuttur)*

### 8.3 Canlı Geçiş (Cutover) Öncesi Kalan Operasyonel Ön Koşullar
İzole kanıtlar doğrulanmış olsa da, canlı sisteme geçiş yapılabilmesi için şu teknik ve operasyonel şartlar tamamlanmalıdır:
1. **İşletme Onayı:** Erkul Çeyiz yetkilisine 3.787.125,00 TL açık senet alacağı ve kapatılmış 20 müşterinin mutabakat dökümü sunulmalı ve yazılı onay alınmalıdır.
2. **Canlı Delta Senkronizasyonu (Freshness Catch-up):** 16 Ekim 2026 tarihli ham snapshot ile bugünkü canlı sistem arasında oluşan yeni satış ve tahsilatların delta migration ile hedef veritabanlarına taşınması.
3. **Kasiyer / Son Kullanıcı Salt-Okunur İncelemesi:** Geçiş pencerelerinde personelin eski ekran ile yeni ekran arasındaki bakiyeleri gözle onaylaması.
4. **Maintenance Lock Entegrasyonu:** Geçiş anında eşzamanlı yazmaları engellemek için `CentralWriteLock` ve bakım afişinin devreye alınması.

---

## 9. ZORUNLU SON GÜVENLİK DURUMU

Aşağıdaki durum bayrakları kesin ve değişmez olarak korunmuştur:

```text
================================================================================
CUTOVER: NOT APPROVED
LIVE DATABASE WRITES: NOT PERFORMED
CORE NEXT SALES ENGINE: DISABLED
DATABASE ROUTING HOOK: NULL
OLD DATABASE RETIREMENT: NOT APPROVED
RELEASE: NOT PUBLISHED
================================================================================
```
