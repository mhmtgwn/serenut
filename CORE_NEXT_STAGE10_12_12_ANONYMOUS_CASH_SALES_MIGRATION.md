# SERENUT OS — STAGE 10.12.12
# 21 MÜŞTERİSİZ NAKİT SATIŞIN KAYIPSIZ VE İDEMPOTENT GÖÇÜ RAPORU

**Tarih:** 16 Ekim 2026  
**Git Commit / HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Branch: `main`)  
**Kapsam:** 21 Müşterisiz Nakit Satışın Mimari Eşlemesi, `cash_transactions` Aktarımı, Finansal Mutabakat ve Regresyon Doğrulaması  
**Güvenlik Prensibi:** Canlı Nutopia SQLite (`%APPDATA%/serenut_pos.db`) ve Erkul Çeyiz Bulut PostgreSQL veritabanlarına sıfır müdahale. Tüm işlemler izole test kopyaları üzerinde salt-okunur kaynaklarla yürütülmüştür.

---

## 1. YÖNETİCİ ÖZETİ VE ÜÇ AYRI NİHAİ KARAR

| Karar Alanı | Nihai Karar | Gerekçe Özeti |
|---|---|---|
| **A. 21 Müşterisiz Satışın Kayıpsız ve İdempotent Göçü** | **✅ PASS** | Kaynak 21 adet müşterisiz nakit satış, `cash_transactions` tablosuna `type = 'INFLOW'`, `category = 'SALE'` olarak 1:1 ve kuruşu kuruşuna denk (12.197,00 TL / 1.219.700 kuruş) aktarılmıştır. İkinci çalıştırmada (idempotency) 21 kayıt ve 12.197 TL sabit kalmış; hata enjeksiyonunda atomik rollback kanıtlanmıştır. |
| **B. Tüm İşletme Verisinin Eksiksiz Göçü** | **✅ PASS** | 37.682 ürün, 584 müşteri (-134.500,68 TL bakiye), 52 satış (31.282,25 TL), 120 satış kalemi, 792 sipariş (1.226.806,30 TL), 9 taksit ve toplam 1.424 finansal hareket (1.403 `ledger_entries` + 21 `cash_transactions`) sıfır veri kaybı ile Core Next kuruş şemasına tam mutabık aktarılabilmektedir. |
| **C. Migration'ın Uygulama Açılışına Bağlanması** | **✅ READY (TEKNİK OLARAK HAZIR / KONTROLLÜ GEÇİŞE AÇIK)** | Veri motorundaki 21 kayıtlık açık giderilmiş, `PRAGMA integrity_check = ok`, `PRAGMA foreign_key_check = 0` ve fail-closed geri dönüş güvenceleri (`assertSafeRollback`) kanıtlanmıştır. Kod tabanı canlı başlatma entegrasyonu aşamasına hazırdır. |

---

## 2. DEĞİŞİKLİK ÖNCESİ VE SONRASI KOD KONTROLÜ

### Git Durumu
- **HEAD Commit:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Aktif Branch:** `main`
- **Git Diff Kontrolü (`git diff --check`):** 0 hata / 0 çakışma (Temiz).
- **Önceki Değişiklikler:** Stage 10.12.6 - 10.12.11 arasındaki hiçbir değişiklik silinmemiş veya geri alınmamıştır.

### Yapılan Değişiklikler ve Gerekçesi
- **Dosya:** [core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart)
  - **Gerekçe:** Stage 10.12.11'de tespit edilen, `customer_id` boş olan 21 nakit satışın `continue` ile atlanarak kaybolması riski giderildi.
  - **Uygulanan Mantık:**
    ```dart
    // ── MÜŞTERİSİZ NAKİT SATIŞLAR: cash_transactions'a aktar ──
    if (cid.trim().isEmpty || !validCustomerIds.contains(cid)) {
      if (rawType == 'sale') {
        if (rawRefId == null || !validSalesSet.contains(rawRefId)) {
          throw StateError(
            'GEÇERSİZ MÜŞTERİSİZ SATIŞ REFERANSI: İşlem ${row['id']} için reference_id ($rawRefId) sales tablosunda bulunamadı!',
          );
        }
        final entryId = row['id']?.toString() ?? 'ft-cash-$cashTxCount';
        batch.insert(
          'cash_transactions',
          {
            'id': entryId,
            'type': 'INFLOW',
            'amount_cents': amountCents,
            'category': 'SALE',
            'description': (row['description']?.toString().isNotEmpty == true)
                ? row['description']!.toString()
                : 'Nakit Satış ($rawRefId)',
            'created_at': createdAtMs,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        cashTxCount++;
        batchCount++;
        // ...
        continue;
      } else {
        throw StateError(
          'TANIMSIZ MÜŞTERİSİZ FİNANSAL HAREKET: İşlem ${row['id']} müşterisiz ancak türü "$rawType". Finansal bütünlük gereği durduruldu.',
        );
      }
    }
    ```
  - **Sonuç:** Müşterili 1.403 hareket `ledger_entries` tablosuna, müşterisiz 21 peşin nakit satış ise `cash_transactions` tablosuna aktarılacak şekilde ayrıştırılmıştır. Müşteri carilerine hiçbir sahte bakiye veya sentetik kayıt karıştırılmamıştır.

---

## 3. KAYNAK VERİTABANLARININ FİZİKSEL DOKUNULMAZLIĞI

Tüm testler öncesinde ve sonrasında SHA-256 kriptografik özetleri doğrulanmış, kaynak dosyalar %100 değişmeden korunmuştur:

| Kaynak / İşletme | Dosya Yolu | Boyut (Bayt) | Doğrulanan SHA-256 Özeti | Durum |
|---|---|---|---|---|
| **Nutopia** | `backups/raw_tenants_20261016/raw_nutopia_v60.db` | 59.764.736 | `E70AA44A43C53F47F61C7B82A0A8C290D82E9F849AEC68486782BC2917430D24` | **DEĞİŞMEDİ (%100 Korundu)** |
| **Serenut** | `backups/raw_tenants_20261016/raw_serenut_v44.db` | 6.516.736 | `9145443F2C94A03DEA7478605DE974A1214B548523DA0406C18501918DA7D77D` | **DEĞİŞMEDİ (%100 Korundu)** |
| **Erkul Çeyiz** | `backups/raw_tenants_20261016/raw_erkul_source.json` | 485.357 | `B4912D916818377FA3D4A2D87C9BC33AA9B5FCD69300442DD6EEA6D8FA5EE389` | **DEĞİŞMEDİ (%100 Korundu)** |

---

## 4. 21 MÜŞTERİSİZ NAKİT SATIŞIN HEDEF / KAYNAK MUTABAKAT TABLOSU

Gerçekleştirilen izole dry-run sonucunda, 21 kaydın kaynak `financial_transactions` ile hedef `cash_transactions` arasındaki birebir eşleşmesi:

| # | Kaynak İşlem ID (`ft.id`) | Kaynak Satış ID (`sales.id`) | Tutar (TL) | Hedef Tablo | Hedef Alanlar (`type` / `category` / `amount_cents`) |
|---|---|---|---|---|---|
| 1 | `trans-17852550015567359331` | `sale-e774315b-fcd8-4267-b8de-27e094f81086` | 1.390,00 | `cash_transactions` | `INFLOW` / `SALE` / 139.000 kuruş |
| 2 | `trans-17852550140540603441` | `sale-d975bc80-e5f3-4495-be29-828bba85e684` | 180,00 | `cash_transactions` | `INFLOW` / `SALE` / 18.000 kuruş |
| 3 | `trans-17852550413659953942` | `sale-e4846393-7871-4a03-818f-c2ab0bc2f6e2` | 80,00 | `cash_transactions` | `INFLOW` / `SALE` / 8.000 kuruş |
| 4 | `trans-17852551097971748840` | `sale-b0de7600-64ac-4a2f-9d38-b8dc7c047db3` | 120,00 | `cash_transactions` | `INFLOW` / `SALE` / 12.000 kuruş |
| 5 | `trans-17852570662183538798` | `sale-131f4cc5-3ad5-4704-8bd9-c764d561793f` | 20,00 | `cash_transactions` | `INFLOW` / `SALE` / 2.000 kuruş |
| 6 | `trans-17852570774634905820` | `sale-8d5859e0-aab7-43c4-a664-5349ce57b650` | 700,00 | `cash_transactions` | `INFLOW` / `SALE` / 70.000 kuruş |
| 7 | `trans-17852570925577962011` | `sale-5b153984-90f2-4d1a-bf8a-c92b4a518cf9` | 20,00 | `cash_transactions` | `INFLOW` / `SALE` / 2.000 kuruş |
| 8 | `trans-17852571030732889765` | `sale-8457e231-0561-4f65-87f4-b7339a4c78bc` | 20,00 | `cash_transactions` | `INFLOW` / `SALE` / 2.000 kuruş |
| 9 | `trans-17853387615502870102` | `sale-9bb05f30-672a-490d-9c03-a8a8e48e2c66` | 500,00 | `cash_transactions` | `INFLOW` / `SALE` / 50.000 kuruş |
| 10 | `trans-17853436740291100213` | `sale-29f73dd1-c2eb-4ca9-bf0e-8858ce559988` | 118,00 | `cash_transactions` | `INFLOW` / `SALE` / 11.800 kuruş |
| 11 | `trans-17858343476949405343` | `sale-7aa7e7fd-bebf-419b-b88d-e679ad90850c` | 578,00 | `cash_transactions` | `INFLOW` / `SALE` / 57.800 kuruş |
| 12 | `trans-17858366820340712828` | `sale-11eb5b80-8da5-46c4-a2c8-ffad9c7dea46` | 289,00 | `cash_transactions` | `INFLOW` / `SALE` / 28.900 kuruş |
| 13 | `trans-17858367216399479506` | `sale-2e015549-05e3-4a5d-95c5-f44946155187` | 578,00 | `cash_transactions` | `INFLOW` / `SALE` / 57.800 kuruş |
| 14 | `trans-17858441072097966972` | `sale-8c96b30c-ae79-4178-9669-c2c3fc82ace7` | 59,00 | `cash_transactions` | `INFLOW` / `SALE` / 5.900 kuruş |
| 15 | `trans-17858441534781740473` | `sale-9e588310-aa79-4374-b1da-9c5bf14ba8a2` | 460,00 | `cash_transactions` | `INFLOW` / `SALE` / 46.000 kuruş |
| 16 | `trans-17858441882558330353` | `sale-899c988f-6d83-4ded-95d7-b18bb72b7f81` | 519,00 | `cash_transactions` | `INFLOW` / `SALE` / 51.900 kuruş |
| 17 | `trans-17862718718479920471` | `sale-23546096-2be5-4f90-87b4-3914f9f42074` | 763,50 | `cash_transactions` | `INFLOW` / `SALE` / 76.350 kuruş |
| 18 | `trans-17862719648869790571` | `sale-7f758d09-0f22-41da-8002-3de2f3cc752f` | 422,50 | `cash_transactions` | `INFLOW` / `SALE` / 42.250 kuruş |
| 19 | `trans-17888610013628381590` | `sale-799f9f35-f08c-4fa8-8298-b610fb3bca0f` | 80,00 | `cash_transactions` | `INFLOW` / `SALE` / 8.000 kuruş |
| 20 | `trans-17898167939063583370` | `sale-eb641cf9-94c4-43d9-bf1c-0d4d3e15f029` | 2.650,00 | `cash_transactions` | `INFLOW` / `SALE` / 265.000 kuruş |
| 21 | `trans-17898168269292281750` | `sale-a16cb120-3d38-44c3-924d-a590c05cb225` | 2.650,00 | `cash_transactions` | `INFLOW` / `SALE` / 265.000 kuruş |
| **TOPLAM** | **21 Kayıt** | **21 Satış Eşleşmesi (%100)** | **12.197,00 TL** | **`cash_transactions`** | **1.219.700 Kuruş (Fark: 0,00 TL)** |

---

## 5. TEST SONUÇLARI VE ÇALIŞTIRMA KANITLARI

Yeni yazılan [test/core_next/stage10_12_12_anonymous_cash_sales_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_12_anonymous_cash_sales_test.dart) ve regresyon testi [test/core_next/stage10_10_9_full_reconciliation_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_10_9_full_reconciliation_test.dart) çalıştırılmıştır:

### 1. 21 Müşterisiz Satışın Kesin Göçü ve Mutabakatı (Test 1)
```
=== TEST 1: 21 MÜŞTERİSİZ NAKİT SATIŞIN KESİN GÖÇÜ VE MUTABAKATI ===
  [PASS] 21 Müşterisiz nakit satış tam 12.197,00 TL olarak cash_transactions tablosuna aktarıldı.
  [PASS] 1.403 Müşteri defteri ve -134.500,68 TL müşteri bakiyesi sıfır sapma ile korundu.
  [PASS] PRAGMA integrity_check = ok, PRAGMA foreign_key_check = 0.
```

### 2. İkinci Çalıştırma (Idempotency) Doğrulaması (Test 2)
```
=== TEST 2: İKİNCİ ÇALIŞTIRMA (IDEMPOTENCY) DOĞRULAMASI ===
  [PASS] İkinci çalıştırma %100 idempotent: Sayı 21, Tutar 12.197,00 TL mükerrersiz korundu.
  [PASS] ledger_entries 1.403 kayıt olarak değişmeden korundu.
```

### 3. Hata Enjeksiyonu ve Atomik Rollback Denetimi (Test 3)
```
=== TEST 3: HATA ENJEKSİYONU VE ATOMİK ROLLBACK DENETİMİ ===
  Kasıtlı Hata: Satış tablosunda olmayan sahte referanslı müşterisiz işlem enjekte edildi.
  Sonuç: StateError fırlatıldı ('GEÇERSİZ MÜŞTERİSİZ SATIŞ REFERANSI').
  [PASS] Hata anında tüm tablolar atomik olarak ROLLBACK edildi; hedefte 0 yarım kayıt bırakıldı.
```

### 4. Ödeme ve Finansal Tipler Regresyon Testi (Test 4)
```
=== TEST 4: ÖDEME VE TİP REGRESYON TESTLERİ ===
  - 52 Satış başlığı ve kalemleri mutabık.
  - 31 Nakit, 19 vadeli (onAccount), 2 karma ödeme mutabık.
  - 22 İade defter hareketi (11.977,00 TL) kuruş kuruşuna mutabık.
  [PASS] Müşterili nakit, müşterisiz nakit, vadeli borç, karma ve iade tipleri eksiksiz mutabık.
```

### 5. Tüm Varlıkların Regresyon Mutabakatı (Stage 10.10.9 Testi)
```
00:27 +4: All tests passed!
  - Nutopia 1.403 cari hareket + 21 kasa nakit hareketi = 1.424 hareket tam mutabık.
  - Serenut (6.377 ürün, 7 müşteri) ve Erkul Çeyiz (401 müşteri) sıfır veri sızıntısıyla korundu.
  - PRAGMA integrity_check = ok.
```

---

## 6. MUTABAKAT VE KONTROL MATRİSİ (PASS / FAIL / NOT VERIFIED)

| # | Denetim Başlığı | Hedef Değer / Ölçüt | Gerçekleşen Sonuç | Karar |
|---|---|---|---|---|
| 1 | Müşterisiz Satış Sayısı | 21 adet | 21 adet | **PASS** |
| 2 | Müşterisiz Satış Toplamı | 12.197,00 TL (1.219.700 kuruş) | 12.197,00 TL (1.219.700 kuruş) | **PASS** |
| 3 | Satış Tablosu Eşleşmesi | 21 / 21 (%100 referans bağı) | 21 / 21 (%100 referans bağı) | **PASS** |
| 4 | Müşteri Cari Bakiyelerine Etki | 0 TL sapma (-134.500,68 TL sabit) | -134.500,68 TL (Sıfır sapma) | **PASS** |
| 5 | Cari Defter (`ledger_entries`) Sayısı | 1.403 adet | 1.403 adet | **PASS** |
| 6 | Kasa Defteri (`cash_transactions`) Sayısı | 21 adet | 21 adet | **PASS** |
| 7 | İkinci Çalıştırma İdempotency | Mükerrer kayıt = 0 | Mükerrer kayıt = 0 | **PASS** |
| 8 | Atomik Rollback Davranışı | Hata anında 0 kısmi kayıt | Hata anında 0 kısmi kayıt | **PASS** |
| 9 | SQLite Bütünlüğü | `PRAGMA integrity_check = ok` | `ok` | **PASS** |
| 10 | İlişkisel Yabancı Anahtar Bütünlüğü | `PRAGMA foreign_key_check = 0` | 0 hata | **PASS** |
| 11 | Kaynak Dosyaların Dokunulmazlığı | SHA-256 Before == After | %100 Eşleşti | **PASS** |

---

## 7. ÇIKARILAN SONUÇLAR VE SONRAKİ AŞAMA GEREKSİNİMLERİ

1. **Veri Modeli Uyumsuzluğu Tamamen Çözüldü:**  
   Core Next mimarisinde peşin nakit satışların `cash_transactions` tablosuna akması kuralı sayesinde, hem `ledger_entries.customer_id NOT NULL` kuralı korunmuş hem de 12.197,00 TL tutarındaki 21 satışın kaybolması engellenmiştir.
2. **Kalan Riskler:**  
   Veri modeli ve migration motoru hazır olmakla birlikte, canlı cutover yapılmamış, `AppBootstrap.initPreApp()` henüz üretimde yeni DB yoluna yönlendirilmemiştir.
3. **Önerilen Sonraki Aşama:**  
   Artık veri kaybı riski kalmadığından, kontrollü biçimde `AppBootstrap` açılış akışında `DatabaseRoutingResolver` ve feature flag entegrasyonu aşamasına geçilebilir.
