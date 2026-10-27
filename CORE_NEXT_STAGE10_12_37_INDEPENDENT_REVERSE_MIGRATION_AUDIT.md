# SERENUT OS — STAGE 10.12.37
## Bağımsız Ters Taşıma Denetimi, Delta Matematiği ve Finansal Veri Güvenliği Raporu

**Tarih:** 19 Ekim 2026  
**Repo:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Branch:** `main`  
**HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Sonuç:** `PASS` (İncelenen kapsamda kritik engel bulunmadı; bu sonuç canlı geçiş izni değildir.)

---

## 1. Git ve Dosya Durumu

- **`git rev-parse HEAD`**: `28c158d88028f139e93f78982d4651ad424c61d2`
- **`git branch --show-current`**: `main`
- **`git diff --check`**: 0 hata / whitespace sorunu bulunmamaktadır.
- **`git diff --stat`**: 22 dosya (1167 satır ekleme, 259 satır silme).
- **Untracked Dizinler**: Kullanıcıya ait `core_next/` ve `test/core_next/` dizinleri korunmuş, asla `git add` edilmemiştir.

---

## 2. İncelenen Gerçek Üretim Kodu

Denetlenen temel kaynak dosyalar:
- [migration_bridge_engine.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart) (`ReverseMigrationEngine.rollbackToLegacy`)
- [database_routing_resolver.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart) (`DatabaseRoutingResolver.assertSafeRollback`)
- [stage10_12_36_conflict_safe_reconciliation_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_36_conflict_safe_reconciliation_test.dart)
- [stage10_12_34_transaction_recovery_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_34_transaction_recovery_test.dart)
- [stage10_12_33_database_routing_rollback_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_33_database_routing_rollback_test.dart)
- [stage10_12_37_reverse_migration_adversarial_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_37_reverse_migration_adversarial_test.dart)

---

## 3. Delta Formülleri ve Baseline Kaynakları

### 3.1 Stok Değişim Deltası (`productDeltas`)
- **Kaynak:** Sadece Core Next'te gerçekleşen ve henüz Legacy'ye aktarılmamış yeni satışlar (`newSales`) ve iadeler (`refunds`).
- **Formül:**
  - Normal satış kalemi: $\Delta_{product} = \Delta_{product} - qty$
  - İade kalemi: $\Delta_{product} = \Delta_{product} + qty$
- **Baseline Doğrulaması:**
  - $Baseline_{beklenen} = Stock_{core} - \Delta_{product}$
  - Legacy veritabanından mevcut stok ($Stock_{legacy}$) sorgulanır.
  - Eğer $|Stock_{legacy} - Baseline_{beklenen}| > 0.001$ ise: **STOK ÇAKIŞMASI**. Sistem `StateError` fırlatır ve tüm işlemi geri alır (Rollback).
  - Eğer fark yoksa: $Stock_{yeni} = Stock_{legacy} + \Delta_{product} = Stock_{core}$ değeriyle Legacy `products.quantity` güncellenir.
- **Dokunulmayan Ürünler:** `newSales` içinde yer almayan ürünler Legacy DB'de kesinlikle sorgulanmaz veya güncellenmez.

### 3.2 Müşteri Cari Bakiyesi Deltası (`customerDeltasCents`)
- **Kaynak:** Core Next `ledger_entries` tablosundaki yeni hareketler.
- **Formül (Kuruş / Minor Cents cinsinden):**
  - Borç / Satış (`SALE`, `DEBT`): $\Delta_{cust} = \Delta_{cust} - amount\_cents$
  - Tahsilat / Ödeme (`PAYMENT`, `COLLECTION`): $\Delta_{cust} = \Delta_{cust} + amount\_cents$
- **Baseline Doğrulaması:**
  - $Baseline_{beklenen} = Balance_{core} - \Delta_{cust}$
  - Legacy DB `customers` tablosundan mevcut bakiye okunur.
  - Eğer `balance_minor` sütunu dolu ve sıfırdan farklıysa kuruş hassasiyetiyle doğrudan `balance_minor` kullanılır; aksi takdirde `(balance * 100).round()` kullanılır (floating-point hatalarını önlemek için).
  - Eğer $Balance_{legacy} \neq Baseline_{beklenen}$ ise: **MÜŞTERİ BAKİYE ÇAKIŞMASI**. Sistem `StateError` fırlatır ve işlemi durdurur.
  - Eşleştiğinde hem `balance` (TL) hem `balance_minor` (kuruş) alanları birlikte güncellenir.

---

## 4. Karşıt (Adversarial) Senaryolar ve Test Sonuçları

| No | Karşıt Senaryo | Beklenen Davranış | Test Sonucu | Kanıt |
| :--- | :--- | :--- | :--- | :--- |
| **1** | Legacy stok 100 -> 98 bağımsız değişmiş, Core Next -5 satmış | Çakışma yakalanmalı, Legacy 98 korunmalı, işlem abort edilmeli | **BAŞARILI** | Stage 36 Test 2.1 |
| **2** | Legacy stok 100 değişmemiş, Core Next -5 satmış | Delta doğru uygulanmalı, stok 95 olmalı | **BAŞARILI** | Stage 36 Test 2.3 |
| **3** | Aynı ürün için birden fazla satış ve iade (3 sat, 1 iade = net -2) | Net delta doğru toplanmalı (100 -> 98) | **BAŞARILI** | Stage 37 Test 2.1 |
| **4** | Müşteri bakiyesinde Legacy bağımsız tahsilat (-500 -> -400), Core Next vadeli satışı (-750) | Çakışma yakalanmalı, Legacy bakiye korunmalı | **BAŞARILI** | Stage 36 Test 2.2 |
| **5** | Aynı Satış ID iki tarafta var ama tutarları farklı (Content Divergence) | Sessizce atlanmamalı, çakışma hatasıyla durdurulmalı | **BAŞARILI** | Stage 37 Test 2.2 |
| **6** | Satış yazımı ortasında hata / kesinti | SQLite Transaction Rollback ile 0 kalıntı kalmalı | **BAŞARILI** | Stage 37 Test 2.3 |
| **7** | Ters taşıma 2 kez üst üste çalıştırılıyor (Idempotency) | İkinci çalıştırmada 0 yeni kayıt, 0 mükerrer satır oluşmalı | **BAŞARILI** | Stage 36 Test 3.1 & Stage 34 Test 3.4 |
| **8** | İade ve ters stok hareketi | `refunds` ve `refund_items` tablolarına bağlanmalı, `sales.refunded_amount` güncellenmeli | **BAŞARILI** | Stage 34 Test 3.3 |
| **9** | FK veya NOT NULL kısıt ihlali | Fail-closed durdurulmalı, kısmi veri kalmamalı | **BAŞARILI** | Stage 34 Test 3.5 & Stage 37 Test 2.3 |
| **10** | Kuruş hassasiyeti ve `balance_minor` senkronizasyonu | `balance` ve `balance_minor` kuruşu kuruşuna eşitlenmeli | **BAŞARILI** | Stage 37 Test 2.4 |
| **11** | Senkronizasyon kuyruğu (`sync_outbox_v4`) | Yalnızca bekleyen kayıtlar aktarılmalı, çift kuyruklama önlenmeli | **BAŞARILI** | Stage 34 Test 3.1 & kod denetimi |
| **12** | Stok hareketleri için ayrı tablo varlığı | Legacy şemada `stock_movements` yoktur, stok `products.quantity` üzerinden yönetilir | **DOĞRULANDI** | Tablo şema denetimi |

---

## 5. Transaction ve Idempotency Bulguları

1. **Tek Bir Atomik Transaction:**
   - Ters taşımanın tamamı `await legacyDb.transaction((txn) async { ... })` bloğu içinde yürütülmektedir.
   - Satışlar, kalemler, ödemeler, müşteri bakiyeleri, stoklar, cari defter hareketleri ve outbox kuyruğu aynı transaction bağlamındadır.
   - Herhangi bir aşamada istisna fırlatıldığında SQLite motoru tüm değişiklikleri atomik olarak geri almaktadır (`ROLLBACK`).
2. **Tam Tablo İdempotency Düzeyi:**
   - `sales`: Orijinal `id` ile eşleştirilir; tutar aynıysa atlanır, tutar farklıysa çakışma hatası fırlatılır.
   - `sale_items` & `sale_payments`: Orijinal ID'leri ile `ConflictAlgorithm.replace` veya `INSERT OR IGNORE` ile korunur.
   - `financial_transactions`: `existingFtMap` üzerinden ID ve tutar denetlenir; mükerrer satır oluşmaz.
   - `products`: Delta hesaplaması yalnızca yeni satışlara dayandığı için, ikinci çalıştırmada $\Delta = 0$ olur ve stok tekrar düşmez.
   - `sync_outbox_v4`: `mutation_id` kontrolü ile mevcutsa tekrar eklenmez.

---

## 6. Finansal Tutarlılık ve Stok Hareketleri Değerlendirmesi

- **Şema Doğrulaması:** Gerçek tenant arşivi `raw_nutopia_v60.db` üzerinde SQLite şeması incelenmiştir.
  - Legacy veritabanında ayrı bir `stock_movements` veya envanter defter tablosu bulunmamaktadır.
  - Stok takibi doğrudan `products.quantity` (ve `products_search_fts_*` arama tetikleyicileri) üzerinden yapılmaktadır. Dolayısıyla `products.quantity` alanının delta bazlı güncellenmesi legacy sistemle tam uyumludur.
- **Kuruş Hassasiyeti:**
  - Legacy DB'deki `customers.balance_minor` sütununa Core Next'in `balance_cents` değeri tam integer olarak yazılmaktadır.
  - TL cinsinden `balance` alanı ise `balance_cents / 100.0` olarak güncellenerek iki sütun arasındaki senkronizasyon garanti altına alınmıştır.

---

## 7. Bulunan Hatalar, Önem Dereceleri ve Düzeltmeler

| Hata / Risk | Önem Derecesi | Durum | Yapılan Düzeltme |
| :--- | :--- | :--- | :--- |
| **Aynı Satış ID Farklı Tutar (Content Divergence):** İki DB'de aynı ID olup tutarı farklı olduğunda kodun sessizce atlaması riski. | **YÜKSEK (Kritik)** | **DÜZELTİLDİ** | `legacySaleMap` üzerinden tutar karşılaştırması eklendi; tutar farklıysa `StateError('SATIŞ İÇERİK ÇAKIŞMASI TESPİT EDİLDİ!')` fırlatılır. |
| **Cari Bakiye Varsayılanı (SQLite Default 0 Uyuşmazlığı):** `customers.balance_minor` tablosunda varsayılan 0 değeri varken `balance` değerinin okunmaması riski. | **ORTA** | **DÜZELTİLDİ** | `balance_minor` sıfır veya tanımsızken `balance * 100` değerine geri çekilme (fallback) eklendi; güncellemede her iki sütun senkronize edildi. |
| **Finansal Hareket Çakışması:** `financial_transactions` tablosunda aynı ID farklı tutarla varsa sessizce atlama riski. | **ORTA** | **DÜZELTİLDİ** | `legacyFtMap` karşılaştırması eklenerek tutar uyuşmazlığında işlem durduruldu. |

---

## 8. Çalıştırılan Komutlar ve Gerçek Terminal Çıktıları

### 8.1 Stage 37 Karşıt Senaryo Testleri
**Komut:** `flutter test test/core_next/stage10_12_37_reverse_migration_adversarial_test.dart`
```text
00:00 +0: STAGE 10.12.37 — BÖLÜM 1: GÜVENLİK KAPISI VE DEĞİŞMEZLİK 1.1: Satış motoru ve routing hook varsayılan olarak kesinlikle kapalıdır
00:00 +1: STAGE 10.12.37 — BÖLÜM 1: GÜVENLİK KAPISI VE DEĞİŞMEZLİK 1.2: Kaynak arşiv fixture dosyası mevcuttur ve okunabilir durumdadır
00:00 +2: STAGE 10.12.37 — BÖLÜM 2: DELTA MATEMATİĞİ VE KARŞIT SENARYOLAR 2.1 (Senaryo 3 - Net Delta): Aynı ürün için birden fazla satış ve iade net delta olarak doğru toplanır
00:00 +3: STAGE 10.12.37 — BÖLÜM 2: DELTA MATEMATİĞİ VE KARŞIT SENARYOLAR 2.2 (Senaryo 5 - İçerik Çakışması): Aynı Satış ID iki tarafta farklı tutarla varsa sessizce atlanamaz, durdurulur
00:01 +4: STAGE 10.12.37 — BÖLÜM 2: DELTA MATEMATİĞİ VE KARŞIT SENARYOLAR 2.3 (Senaryo 6 & 9 - Atomik Rollback): Hata anında hiçbir ara tablo kısmi kayıt barındırmaz
00:02 +5: STAGE 10.12.37 — BÖLÜM 2: DELTA MATEMATİĞİ VE KARŞIT SENARYOLAR 2.4 (Senaryo 10 - Kuruş Hassasiyeti): balance_minor integer sütunu kuruşu kuruşuna güncellenir
00:03 +6: All tests passed!
```

### 8.2 Stage 36 Çakışma Güvenliği Testleri
**Komut:** `flutter test test/core_next/stage10_12_36_conflict_safe_reconciliation_test.dart`
```text
00:22 +8: All tests passed! (8/8 test başarılı)
```

### 8.3 Stage 34 Transaction Recovery Testleri
**Komut:** `flutter test test/core_next/stage10_12_34_transaction_recovery_test.dart`
```text
00:08 +13: All tests passed! (13/13 test başarılı)
```

### 8.4 Stage 33 Dual Database Routing & Rollback Testleri
**Komut:** `flutter test test/core_next/stage10_12_33_database_routing_rollback_test.dart`
```text
00:21 +18: All tests passed! (18/18 test başarılı)
```

### 8.5 Statik Kod Analizi
**Komut:** `flutter analyze core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart test/core_next/stage10_12_37_reverse_migration_adversarial_test.dart test/core_next/stage10_12_36_conflict_safe_reconciliation_test.dart test/core_next/stage10_12_34_transaction_recovery_test.dart`
```text
Analyzing 4 items...
No issues found! (ran in 10.2s)
```

---

## 9. Açık Kalan Riskler ve Operasyonel Sınırlar

1. **Dual-Write / Eşzamanlı Çift Yazma İmkansızlığı:**
   - Cutover gerçekleştikten sonra, eski sistemde bağımsız manuel işlemler (fiziksel stok sayımı, harici fiş girişi, bağımsız kasa tahsilatı) yapılırsa, ters uzlaştırma motoru baseline uyuşmazlığı tespit ederek geri dönüşü güvenlik amacıyla durdurur.
   - Bu davranış bir kusur değil, veriyi sessizce ezilmekten koruyan bir güvenlik kilididir.
2. **Untracked Dizinler:**
   - `core_next/` ve `test/core_next/` dizinleri Git tarafından takip edilmemektedir. Kullanıcı onayıyla bir sonraki sürüm kontrolü aşamasında ele alınmalıdır.

---

## 10. Canlı Veriye Dokunulmadığının Teyidi

Aşağıdaki değişmez kurallar titizlikle korunmuştur:
- `coreNextSalesEngineEnabledProvider = false` olarak kalmıştır.
- `DatabaseManager.databaseRoutingHook = null` olarak kalmıştır.
- `c:\Users\notop\AndroidStudioProjects\shaman_new\assets\db\nutopia.db` ve `raw_nutopia_v60.db` arşiv dosyalarına hiçbir yazma yapılmamıştır.
- Çalışan Serenut OS sürecine (PID 7096) ve canlı veritabanlarına dokunulmamıştır.
- Bütün testler geçici işletim sistemi dizininde (`Temp/stage37_*`) oluşturulan tek kullanımlık (disposable) SQLite dosyalarında çalıştırılmış ve test sonunda silinmiştir.

---

## Karar

**PASS**  
*(İncelenen kapsamda kritik engel bulunmadı; bu sonuç canlı geçiş izni değildir. Canlı pilot başlatılmamış, routing hook etkinleştirilmemiş, satış motoru açılmamış ve sürüm yayımlanmamıştır.)*
