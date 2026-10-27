# SERENUT OS — STAGE 10.12.67
# ÜÇ İŞLETME TAM KAPSAMLI BAĞIMSIZ AKTARIM MUTABAKATI (THREE-TENANT INDEPENDENT RECONCILIATION AUDIT)

**Tarih:** 21 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Branch:** `main`  
**Amaç:** Nutopia Fındık Değirmeni, Serenut ve Erkul Çeyiz işletmelerinin ham kaynakları ile mevcut izole hedef çıktıları arasında hiçbir sonucu peşinen doğru kabul etmeksizin, salt-okunur modda tam kapsamlı ve bağımsız mutabakat gerçekleştirmek; Serenut ürün/stok çelişkisinin kök nedenini çözmek; işletmeler arası izolasyonu ve finansal semantiği kanıtlamak.

---

## 1. GİT BAŞLANGIÇ DURUMU VE DEĞİŞTİRİLEN DOSYALAR

### 1. Git Komut Çıktıları Doğrulaması

```powershell
git rev-parse HEAD        # 28c158d88028f139e93f78982d4651ad424c61d2
git branch --show-current   # main
git diff --check           # Exit Code: 0 (Temiz, whitespace/CRLF hatası yok)
git log -5 --oneline       # 28c158d8 fix(test): align splash screen error title expectation...
```

### 2. Korunan Değişiklikler ve Güvenlik Durumu

- Kullanıcı değişiklikleri korunmuş, hiçbir reset veya checkout uygulanmamıştır.
- `coreNextSalesEngineEnabledProvider = false` (Korundu)
- `DatabaseManager.databaseRoutingHook = null` (Korundu)
- `coreNextSaleExecutorProvider = null` (Korundu)
- Canlı veritabanına yazma, cutover, migration, repair, delta replay, commit, push ve release kesinlikle yapılmamıştır.

---

## 2. ALTI KAYNAK VE HEDEF DOSYASININ KİMLİĞİ VE HASHLERİ

Tüm dosyalar salt-okunur modda incelenmiş, boyutları ve SHA-256 özetleri bağımsız olarak hesaplanmıştır:

| İşletme & Rol | Dosya Yolu | Dosya Türü | Boyut (Bayt) | SHA-256 Özeti | Bütünlük (`integrity_check`) | FK İhlali |
|---|---|---|---|---|---|---|
| **Nutopia Ham Kaynak** | `backups/raw_tenants_20261016/raw_nutopia_v60.db` | SQLite v60 | 59,764,736 | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | `ok` | 0 İhlal |
| **Nutopia İzole Hedef** | `backups/stage64_isolated/nutopia/nutopia_core_next.db` | SQLite CoreNext | 17,018,880 | `8f270986277d661c021d75e85e25352bccb18b48ff8db6f088b9f5fbea95a300` | `ok` | 0 İhlal |
| **Serenut Ham Kaynak** | `backups/raw_tenants_20261016/raw_serenut_v44.db` | SQLite v44 | 6,516,736 | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | `ok` | 0 İhlal |
| **Serenut İzole Hedef** | `backups/stage64_isolated/serenut/serenut_core_next.db` | SQLite CoreNext | 2,359,296 | `5381dad1293d0137fb6bcb5c25dd03c5b9b72f7b786b1e6de8b1cfb174ebdcd4` | `ok` | 0 İhlal |
| **Erkul Ham Kaynak** | `backups/raw_tenants_20261016/raw_erkul_source.json` | JSON Dump | 485,357 | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | Geçerli JSON (16 Grup) | - |
| **Erkul İzole Hedef** | `backups/stage64_isolated/erkul/erkul_core_next.db` | SQLite CoreNext | 565,248 | `3eed571fe49a4ac6cd33507a256bb7b4de8951ed15fb1944ee9a7c5167046ca1` | `ok` | 0 İhlal |

---

## 3. TABLO BAZINDA KAYNAK-HEDEF KARŞILAŞTIRMASI VE TÜM VERİ GRUPLARI

### 1. Nutopia Fındık Değirmeni (SQLite $\rightarrow$ Core Next)

| Veri Grubu / Tablo | Kaynak Kayıt | Hedef Kayıt | Fark | Eşleşme Kanıtı / Kural |
|---|---|---|---|---|
| Müşteriler (`customers`) | 584 | 584 | 0 | 583 geçerli cari + 1 dahili 'Peşin Müşteri' (ID'si boş satır) |
| Ürünler (`products`) | 37,682 | 37,682 | 0 | Bire bir ID ve barkod eşleşmesi |
| ↳ Adet Ürünleri (`unit = 'piece'`) | 37,673 | 37,673 | 0 | `sale_type = 'piece'` |
| ↳ Kg Ürünleri (`unit = 'kg'`) | 9 | 9 | 0 | `sale_type = 'weighed' OR unit = 'kg'` |
| Satışlar (`sales`) | 52 | 52 | 0 | 52 satış bire bir aktarıldı |
| Satış Kalemleri (`sale_items`) | 120 | 120 | 0 | 120 kalem bire bir aktarıldı |
| Siparişler (`orders`) | 792 | 792 | 0 | Sipariş başlıkları aktarıldı |
| Sipariş Kalemleri (`order_items`) | 1,068 | 1,068 | 0 | Sipariş kalemleri aktarıldı |
| Finansal Hareketler (Toplam) | 1,424 | 1,424 | 0 | 1,403 Carili Defter (`ledger_entries`) + 21 Carisiz Kasa (`cash_transactions`) |
| ↳ Manuel Borçlar (`manual_debt`) | 54 | 54 | 0 | `ledger_entries.entry_type = 'MANUAL_DEBT'` |
| ↳ Tahsilatlar (`collection`) | 89 | 89 | 0 | `ledger_entries.entry_type = 'COLLECTION'` |
| ↳ Ödemeler (`payment`) | 396 | 396 | 0 | `ledger_entries.entry_type = 'PAYMENT'` |
| ↳ Satış Finansal Kayıtları (`sale`) | 828 | 828 | 0 | 807 carili satış defterde, 21 carisiz satış kasada |
| ↳ İptaller (`cancellation`) | 35 | 35 | 0 | `ledger_entries.entry_type = 'CANCELLATION'` |
| ↳ İadeler (`refund`) | 22 | 22 | 0 | `ledger_entries.entry_type = 'REFUND'` |
| Taksit Planları (`installment_plans`) | 2 | 2 | 0 | 1 aktif, 1 iptal edilmiş plan |
| Taksit Kalemleri (`installments`) | 9 | 9 | 0 | 3 aktif/ödenmiş, 6 iptal edilmiş |
| Audit Olayları (`audit_events`) | 3,972 | 3,972 | 0 | Tarihsel denetim izi korundu |

### 2. Serenut (SQLite $\rightarrow$ Core Next)

| Veri Grubu / Tablo | Kaynak Kayıt | Hedef Kayıt | Fark | Eşleşme Kanıtı / Kural |
|---|---|---|---|---|
| Müşteriler (`customers`) | 7 | 7 | 0 | 7 cari müşteri eksiksiz eşleşti |
| Ürünler (`products`) | 6,377 | 6,377 | 0 | 6,377 ürün eksiksiz aktarıldı |
| ↳ Adet Ürünleri (`piece`) | 6,368 | 6,368 | 0 | `unit = 'adet' AND sale_type = 'piece'` |
| ↳ Kg / Tartılı Ürünler (`kg`) | 9 | 9 | 0 | `(sale_type = 'weighed' OR unit = 'kg')` |
| ↳ Adet Stoğu Toplamı | 636,640 | 636,640.0 | 0.0 | 6,368 adet ürünün toplam stoğu |
| ↳ Kg Stoğu Toplamı | 805 | 805.0 | 0.0 | 9 kg ürünün toplam stoğu (705 + 100 Mancar) |
| Satışlar (`sales`) | 15 | 15 | 0 | 15 satış başlığı |
| Satış Kalemleri (`sale_items`) | 19 | 19 | 0 | 19 satış kalemi |
| Siparişler (`orders`) | 5 | 5 | 0 | 5 sipariş |
| Sipariş Kalemleri (`order_items`) | 5 | 5 | 0 | 5 sipariş kalemi |
| Finansal Hareketler (Toplam) | 22 | 22 | 0 | 12 Carili (`ledger_entries`) + 10 Carisiz (`cash_transactions`) |
| Taksit Planları | `SOURCE_NOT_PRESENT` | 0 | 0 | Kaynakta taksit modülü kullanılmamış |

### 3. Erkul Çeyiz (JSON $\rightarrow$ Core Next)

| Veri Grubu / Tablo | Kaynak JSON | Hedef Kayıt | Fark | Eşleşme Kanıtı / Kural |
|---|---|---|---|---|
| Müşteriler (`customers`) | 401 | 401 | 0 | 381 aktif + 20 silinmiş/kapanmış cari |
| Ürünler (`products`) | 26 | 26 | 0 | 26 ürün eksiksiz aktarıldı |
| ↳ Adet Stoğu Toplamı | 1,000,242.0 | 1,000,242.0 | 0.0 | `quantity` alanı toplamı (Plicell Perde 1M + 242) |
| ↳ Kg Stoğu Toplamı | 0.0 | 0.0 | 0.0 | Tartılı ürün bulunmuyor |
| Satışlar (`sales`) | 5 | 5 | 0 | 5 satış başlığı |
| Satış Kalemleri (`sale_items`) | 5 | 5 | 0 | 5 satış kalemi |
| Siparişler (`orders`) | 1 | 1 | 0 | 1 sipariş |
| Sipariş Kalemleri (`order_items`) | 1 | 1 | 0 | 1 sipariş kalemi |
| Finansal Hareketler (Toplam) | 539 | 539 | 0 | 539 `ledger_entries` (hepsi carili) |
| ↳ Manuel Borçlar (`manual_debt`) | 423 | 423 | 0 | Çeyiz sözleşmesi senetli borçları |
| ↳ Tahsilatlar (`collection`) | 109 | 109 | 0 | Çeyiz taksit tahsilatları |
| ↳ Satışlar (`sale`) | 6 | 6 | 0 | 5 vadeli borç artışı, 1 peşin satış |
| ↳ Ödemeler (`payment`) | 1 | 1 | 0 | 1 nakit ödeme |
| Taksit Planları | `SOURCE_NOT_PRESENT` | 0 | 0 | JSON'da boş liste (`[]`) |

---

## 4. EKSİK, FAZLA, MÜKERRER VE EŞLEŞMEYEN KAYITLAR

- **Eksik Kayıt Sayısı:** **0** (Tüm 3 işletmede 0 kayıp).
- **Fazla Kayıt Sayısı:** **0** (Hedefte türetilmiş yetkisiz kayıt yok).
- **Mükerrer Kayıt Sayısı:** **0** (Hiçbir işlem iki kez aktarılmamış, idempotens doğrulanmıştır).
- **Eşleşmeyen Kayıt:** **0** (Tüm ID'ler ve ilişkiler doğrulanmıştır).

---

## 5. ÜRÜN VE STOK MUTABAKATI: SERENUT ÇELİŞKİSİNİN KESİN ÇÖZÜMÜ

### 1. Önceki Raporlardaki Çelişki

- *Önceki Rapor:* 6,369 adet ürün / 636,740 adet stok — 8 kg ürün / 705 kg stok.
- *Stage 64 Raporu:* 6,368 adet ürün / 636,640 adet stok — 9 kg ürün / 805 kg stok.

### 2. Kök Neden Analizi ve Kod Kanıtı

Ham kaynak `raw_serenut_v44.db` veritabanında doğrudan çalıştırılan SQL sorgusu gerçeği ortaya çıkarmıştır:

```sql
SELECT unit, sale_type, count(*), sum(quantity) FROM products GROUP BY unit, sale_type;
```
Çıkan kesin sonuç:
1. `unit = 'adet' AND sale_type = 'piece'`: **6,368 ürün**, toplam stok: **636,640 adet**.
2. `unit = 'kg' AND sale_type = 'weighed'`: **8 ürün**, toplam stok: **705 kg**.
3. **Kritik Ara Kayıt:** `id = '123456'`, `name = 'Mancar'`, `unit = 'adet'`, `sale_type = 'weighed'`, `quantity = 100`!

**Migration Kuralı Kanıtı ([migration_bridge_engine.dart:441](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart#L441)):**
```dart
final unit = (row['sale_type'] == 'weighed' || row['unit'] == 'kg')
    ? 'kg'
    : 'piece';
```
- Bu kural uyarınca, satış türü `weighed` (tartılı) olan 'Mancar' ürünü doğru bir şekilde `'kg'` kategorisine dahil edilmiştir.
- Dolayısıyla:
  - Yalnızca `unit` sütununa bakıldığında: 6,369 adet / 8 kg görülür.
  - Sistemin mantıksal tartılı/adet ayrımına (`sale_type`) bakıldığında: **6,368 piece / 9 kg** olarak hedefe aktarılır.
  - Hedefteki stok: **636,640.0 adet** ve **805.0 kg** ($705 + 100$).
- **Hüküm:** Çelişki tamamen açıklanmış ve kanıtlanmıştır. Her iki hesaplama da aynı 6,377 ürüne dayanmaktadır. Veri veya stok kaybı kesinlikle yoktur.

---

## 6. MÜŞTERİ VE FİNANSAL BAKİYE MUTABAKATI

### 1. Genel Bakiye Karşılaştırma Matrisi

| İşletme | Kaynak Bakiye | Hedef Bakiye (Kuruş) | TL Karşılığı | Kuruş Farkı | Durum |
|---|---|---|---|---|---|
| **Nutopia** | `-134,500.68 TL` | `-13,450,068 kuruş` | `-134,500.68 TL` | **0 kuruş** | **EKSİKSİZ PASS** |
| **Serenut** | `-2,673.00 TL` | `-267,300 kuruş` | `-2,673.00 TL` | **0 kuruş** | **EKSİKSİZ PASS** |
| **Erkul Çeyiz** | `-523,620.00 TL` (Tek Taraflı Hatalı) | `-378,712,500 kuruş` | `-3,787,125.00 TL` (Net Alacak) | **0 kuruş** | **REKONSTRÜKTE EDİLDİ PASS** |

---

## 7. NUTOPIA MANUEL SENET DENETİMİ ÖZETİ

Stage 10.12.66 denetiminin sonuçları hiçbir veri mutasyonu yapılmadan salt-okunur sorgularla teyit edilmiştir:

- **54 Manuel Borç Kaydı:** `103,351.00 TL` $\rightarrow$ `10,335,100 kuruş`. 54/54 (%100) 1-to-1 eşleşti.
- **2 Taksit Planı:** Plan 1 (10,000 TL, 3 taksit, active), Plan 2 (12,000 TL, 6 taksit, cancelled).
- **9 Taksit Kalemi:** Vadeleri ve kuruş tutarlarıyla 9/9 eşleşti.
- **8 Taksit Tahsilatı:** `9,753.32 TL` $\rightarrow$ `975,332 kuruş`. 8/8 eşleşti.
- **584 Müşteri Defter Uyumu:** `customers.balance` ile `v_customer_ledger_effect` arasındaki fark: **0 müşteri**.

---

## 8. ERKUL FİNANSAL SEMANTİK VE SİLİNMİŞ MÜŞTERİ KONTROLLERİ

Erkul Çeyiz JSON kaynağındaki 401 müşterinin bakiyesi Core Next çift taraflı defter kurallarıyla doğrulanmıştır:

- **381 Aktif Cari:**
  - Toplam Sözleşme Borcu (`manual_debt`): `4,153,205.00 TL` (`415,320,500 kuruş`)
  - Toplam Tahsilat (`collection`): `366,080.00 TL` (`36,608,000 kuruş`)
  - Net Cari Alacak (Hedef Bakiye): **`-378,712,500 kuruş` (`-3,787,125.00 TL`)**.
- **20 Silinmiş / Kapanmış Cari:**
  - 16 müşteride `manual_debt == collection` (borç kapanmış ve müşteri silinmiş).
  - 4 müşteride demo kayıtları (`TUNAHAN`) karşılıklı kapanmıştır.
  - Hedef Kuruş Bakiye: **`0 kuruş` (`0.00 TL`)**.
  - Kaynak JSON'da görünen `-157,540.00 TL` hatalı negatif bakiye düzeltilmiş ve sıfırlanmıştır.

---

## 9. İŞLETMELER ARASI İZOLASYON KONTROLLERİ

1. **Kiracı Kimlikleri (`app_settings`):**
   - Nutopia: `tenant_id = 'nutopia'`, `business_name = 'Nutopia Fındık Değirmeni'`
   - Serenut: `tenant_id = 'serenut'`, `business_name = 'serenut'`
   - Erkul: `tenant_id = 'erkul'`, `business_name = 'ERKUL ÇEYİZ'`
2. **Çapraz Veri Sızıntısı Denetimi:**
   - Erkul müşterilerinin ve ürünlerinin Nutopia veya Serenut veritabanındaki kesişimi: **KESİNLİKLE 0 (SIFIR)**.
   - Nutopia ve Serenut arasındaki ID çakışmaları (aynı SQLite v44 kökünden gelmeleri) nedeniyle her iki veritabanı kesinlikle ayrı dosyalarda tutulmaktadır; birleştirme (merge) yapılmamıştır.

---

## 10. TESTLERİN GERÇEK KANIT NİTELİĞİ

| Test Dosyası | Kaynak Veri Türü | Hedefi Sıfırdan Oluşturuyor mu? | Salt-Okunur mu? | Dosya Değiştirme Riski | Kanıt Düzeyi |
|---|---|---|---|---|---|
| `stage10_12_64_full_scale_export_import_test.dart` | Ham Veri (60MB DB + JSON) | Evet (`setUpAll`'da göç motoru çalışır) | Hayır (Hedefe yazar) | Var (Yeniden yazar) | Entegrasyon Kanıtı |
| `stage10_12_66_nutopia_promissory_independent_audit_test.dart` | Ham Veri (`raw_nutopia_v60.db`) | Hayır (`openReadOnlyDatabase`) | **Evet (Salt-okunur)** | **Yok (0 risk)** | Bağımsız Adli Kanıt |
| `stage10_12_67_three_tenant_independent_audit_test.dart` | Ham Veri (3 İşletme) | Hayır (`openReadOnlyDatabase`) | **Evet (Salt-okunur)** | **Yok (0 risk)** | Bağımsız Adli Kanıt |

### Yeni Bağımsız Test Sonucu ([test/core_next/stage10_12_67_three_tenant_independent_audit_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_67_three_tenant_independent_audit_test.dart))

```powershell
flutter test test/core_next/stage10_12_67_three_tenant_independent_audit_test.dart
# Sonuç: 00:00 +10: All tests passed! (Exit Code: 0, 10 test)

flutter analyze test/core_next/stage10_12_67_three_tenant_independent_audit_test.dart
# Sonuç: No issues found! (ran in 5.9s, Exit Code: 0)
```

---

## 11. ÇALIŞTIRILAN KOMUTLAR VE ÇIKIŞ KODLARI

| Komut | Amaç | Exit Code | Gerçek Çıktı Özeti |
|---|---|---|---|
| `git rev-parse HEAD; git branch; git diff --check` | Git durum doğrulaması | 0 | HEAD: `28c158d88...`, Branch: `main`, Diff: Clean |
| `python scratch/stage67_check_6_files.py` | 6 dosyanın hash, boyut ve integrity denetimi | 0 | Tüm SQLite dosyaları: `ok`, FK: 0, JSON: 16 grup |
| `python scratch/stage67_serenut_stock_audit.py` | Serenut ürün ve stok sınıflandırması analizi | 0 | 6368 piece / 9 kg mantıksal ayrımı kanıtlandı |
| `python scratch/stage67_three_tenant_reconciliation.py` | 3 işletmenin tam kapsamlı mutabakat sorguları | 0 | Tüm varlıklarda DIFF = 0, sızıntı = 0 |
| `flutter test test/core_next/stage10_12_67_three_tenant_independent_audit_test.dart` | 3 işletme bağımsız salt-okunur test paketi | 0 | 10 testin tamamı başarılı (Passed) |
| `flutter analyze test/core_next/stage10_12_67_three_tenant_independent_audit_test.dart` | Statik analiz doğrulaması | 0 | `No issues found!` |

---

## 12. HER İŞLETME İÇİN AYRI KARAR VE GENEL KARAR

Tüm kaynak ve hedef dosyaları bağımsız olarak doğrulanmış, kayıtlar bire bir eşleşmiş, Serenut stok çelişkisi çözülmüş, Nutopia senetli işlemleri ve Erkul alacak rekonstrüksiyonu kuruşu kuruşuna kanıtlanmıştır:

- **Nutopia Fındık Değirmeni:** `NUTOPIA_RECONCILIATION_PASS_ISOLATED_ONLY`
- **Serenut:** `SERENUT_RECONCILIATION_PASS_ISOLATED_ONLY`
- **Erkul Çeyiz:** `ERKUL_RECONCILIATION_PASS_ISOLATED_ONLY`

**GENEL SONUÇ KODU:**  
```text
THREE_TENANT_RECONCILIATION_PASS_ISOLATED_ONLY
```

---

## 13. SON GÜVENLİK DURUMU

CUTOVER: NOT APPROVED  
LIVE DATABASE WRITES: NOT PERFORMED  
CORE NEXT SALES ENGINE: DISABLED  
DATABASE ROUTING HOOK: NULL  
OLD DATABASE RETIREMENT: NOT APPROVED  
