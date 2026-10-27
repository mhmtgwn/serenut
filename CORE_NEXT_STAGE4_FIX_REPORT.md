# SERENUT OS — STAGE 4: KONTROLLÜ FİNANSAL DÜZELTME RAPORU

**Belge Adı:** `CORE_NEXT_STAGE4_FIX_REPORT.md`  
**Uygulama Seviyesi:** 4. Aşama Kontrollü Finansal ve Matematiksel Düzeltme  
**Tarih:** 13 Ekim 2026  
**Mühendislik Rolü:** Kıdemli Flutter/Dart, SQLite ve Finansal Sistem Mühendisi  
**Proje Kök Dizini:** `c:\Users\notop\AndroidStudioProjects\shaman_new`  
**Durum:** **DÜZELTMELER TAMAMLANDI, TÜM TESTLER GEÇTİ, COMMİT ATILMADI, TALİMAT BEKLENİYOR**

---

## 1. Başlangıç Git Durumu ve Güvenlik Tespiti

- **Aktif Branch:** `main`
- **Başlangıç Commit Hash:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Başlangıç Git Durumu:**
  ```text
  ?? CORE_NEXT_INDEPENDENT_AUDIT.md
  ?? CORE_NEXT_SECOND_PASS_AUDIT.md
  ?? CORE_NEXT_STAGE3_FORENSIC_VERIFICATION.md
  ?? core_next/
  ?? test/core_next/
  ```
- **Canlı Veritabanı Değişmezlik Doğrulaması:**
  - Canlı Veritabanı Yolu: `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db`
  - Başlangıç SHA-256: `28a1f5fdcd77b318956c042af7b68b3d16f4dcb4fee479365856b9ed8e58c9ae`
  - İşlem Sonu SHA-256: `28a1f5fdcd77b318956c042af7b68b3d16f4dcb4fee479365856b9ed8e58c9ae`
  - **Hüküm:** Canlı veritabanına **SIFIR YAZMA (0 WRITE)** yapılmıştır. Tüm testler izole sandbox kopyaları ve geçici dosyalarda yürütülmüştür.

---

## 2. Değiştirilen Dosyalar ve Değişiklik Gerekçeleri

Yalnızca Aşama 4 kapsamında yetkilendirilen 3 kaynak dosya ve 3 test dosyası kontrollü olarak güncellenmiştir:

| Dosya Yolu | Değişiklik Türü | Gerekçe |
| :--- | :---: | :--- |
| `core_next/client_core/lib/domain/models/money_cents.dart` | Kaynak Kod | Dart Euclidean modulo (`%`) operatörünün negatif tutarlarda ters işaret ve yanlış küsurat üretmesi düzeltildi (`value.abs()`, `isNegative`). |
| `core_next/client_core/lib/presentation/sales/core_sales_flow_state.dart` | Kaynak Kod | Tartılı ürün hesaplamasında `~/ 1000` tamsayı kesmesinin 300g, 500g ve 999g'da 1 kuruş eksik tahsilat yapması giderildi; `(unitPrice * quantity + 500) ~/ 1000` ticari yarım-yukarı tamsayı formülü uygulandı. |
| `core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart` | Kaynak Kod | `balance_minor` bayat snapshot alanına körü körüne güvenilmesi kaldırıldı. `v_customer_ledger_effect` defteri ve `customers.balance` yetkili kaynak kabul edildi; bayat minor farkları (`CustomerDiscrepancy`) raporlanarak 3.320,00 TL alacak kaybı önlendi; defter ile kayıtlı bakiye uyuşmazlığında otomatik durdurma (`StateError`) eklendi. |
| `test/core_next/ledger_service_test.dart` | Birim Test | `-101`, `-100`, `-99`, `-50`, `-1`, `0`, `1`, `50`, `99`, `100`, `101` kuruş için sınır para formatlama testleri eklendi. |
| `test/core_next/checkout_use_case_test.dart` | Birim Test | 1g, 10g, 100g, 300g, 500g, 999g, 1000g için ticari yarım-yukarı yuvarlama ve indirimli tartılı satış sınır testleri eklendi. |
| `test/core_next/real_data_verification_test.dart` | Entegrasyon Testi | Canlı veritabanı kopyası üzerinde `-135.490,68 TL` defter mutabakatı, 2 müşterideki 3.320,00 TL sapmanın tespiti ve müşteri adlarının maskelenmesi doğrulandı. |
| `test/core_next/migration_bridge_test.dart` | Birim Test | Idempotency (ikinci çalıştırma), bayat `balance_minor` yakalama ve defter sapmasında güvenlik amacıyla abort etme testleri eklendi. |

---

## 3. Kod Değişikliklerinin Detayları

### 3.1. Aşama A: Migration Güvenliği (`migration_bridge_engine.dart`)
- **Eski Mantık:**
  ```dart
  if (row['balance_minor'] != null) {
    balanceCents = (row['balance_minor'] as num).toInt(); // 3.320 TL alacak kaybı!
  } else { ... }
  ```
- **Yeni Güvenli Mantık:**
  1. `v_customer_ledger_effect` görünümü varsa, her müşterinin defter hareket toplamı (`ledgerBalances`) alınır.
  2. `customers.balance` ile `v_customer_ledger_effect` toplamı kuruş kuruş karşılaştırılır. Eğer bir müşteride beklenmeyen fark varsa işlem **otomatik olarak durdurulur (`StateError`)**.
  3. `balance_minor` sütunundaki değer incelenir. Eğer Migration 60 stale hatası sebebiyle yetkili bakiyeden farklıysa (tespit edilen 2 müşteri), bu fark `CustomerDiscrepancy` listesine işlenir ve yeni sisteme **YETKİLİ DEFTER BAKİYESİ** aktarılır.
  4. İşlem `ConflictAlgorithm.replace` ile çalıştığı için tekrar çalıştırıldığında aynı sonucu verir (**Idempotent**).

### 3.2. Aşama B: Para Biçimlendirme (`money_cents.dart`)
- **Düzeltilen Metod:**
  ```dart
  String formatTL() {
    final isNegative = value < 0;
    final absVal = value.abs();
    final liraPart = absVal ~/ 100;
    final kurusPart = (absVal % 100).toString().padLeft(2, '0');
    return '${isNegative ? '-' : ''}$liraPart,$kurusPart ₺';
  }
  ```

### 3.3. Aşama C: Terazi Yuvarlaması (`core_sales_flow_state.dart`)
- **Düzeltilen Metod:**
  ```dart
  MoneyCents get lineTotal {
    if (isWeighed) {
      final int rawCents;
      if (quantity >= 0) {
        rawCents = (unitPrice.value * quantity + 500) ~/ 1000;
      } else {
        rawCents = (unitPrice.value * quantity - 500) ~/ 1000;
      }
      final discounted = rawCents - discount.value;
      return MoneyCents(discounted > 0 ? discounted : 0);
    } else {
      final discounted = (unitPrice.value * quantity) - discount.value;
      return MoneyCents(discounted > 0 ? discounted : 0);
    }
  }
  ```

---

## 4. Test Komutları ve Gerçek Çıktıları

### 4.1. Tam Test Koşumu Komutu
```bash
flutter test test/core_next/
```

### 4.2. Ham Test Konsol Çıktısı
```text
00:07 +9: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/hardware_worker_test.dart: TSPL Barcode Label Builder Tests TSPL komutları milimetrik boyut ve EAN13 barkod formatına uygun olmalıdır
00:07 +10: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/hardware_worker_test.dart: HardwareWorker Isolate Tests HardwareWorker izole Isolate başlatabilmeli ve dispose edilebilmelidir
00:13 +11: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/ledger_service_test.dart: MoneyCents Value Object Tests TL to Kuruş ve Kuruş to TL dönüşümünde sıfır kayıp olmalıdır
00:13 +12: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/ledger_service_test.dart: MoneyCents Value Object Tests Float yuvarlama hataları olmamalıdır (0.1 + 0.2 problemi)
00:13 +13: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/ledger_service_test.dart: MoneyCents Value Object Tests KDV yüzde hesabı kuruş hassasiyetinde doğru yuvarlamalıdır
00:13 +14: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/ledger_service_test.dart: MoneyCents Value Object Tests formatTL negatif ve pozitif tutarları doğru Türkçe formatında göstermelidir
00:13 +15: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/ledger_service_test.dart: LedgerService (Trigger-Free Double Entry Accounting) Tests Vadeli satış yapıldığında müşteri bakiyesi tam kuruş olarak azalmalı ve defter kaydı oluşmalıdır
00:13 +16: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/ledger_service_test.dart: LedgerService (Trigger-Free Double Entry Accounting) Tests Borç tahsilatı yapıldığında bakiye düzelmelidir
00:13 +17: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/ledger_service_test.dart: LedgerService (Trigger-Free Double Entry Accounting) Tests Kredi limiti aşıldığında işlem hata vermeli ve veritabanı kirlenmemelidir
00:21 +18: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/migration_bridge_test.dart: MigrationBridgeEngine (Eski SQLite -> Yeni Kuruş Şeması) Tests Eski tablolardaki double fiyat ve bakiyeler kuruş tamsayısına kayıpsız dönüştürülmelidir
00:23 +19: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/migration_bridge_test.dart: MigrationBridgeEngine (Eski SQLite -> Yeni Kuruş Şeması) Tests Bayat balance_minor değeri yetkili bakiye ile uyuşmadığında fark listelenmeli ve yetkili bakiye aktarılmalıdır
00:24 +20: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/migration_bridge_test.dart: MigrationBridgeEngine (Eski SQLite -> Yeni Kuruş Şeması) Tests Defter görünümü ile customers.balance arasında beklenmeyen sapma varsa migrasyon durdurulmalıdır
00:24 +21: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/real_data_verification_test.dart: (setUpAll)
00:30 +21: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/real_data_verification_test.dart: Gerçek Canlı Veritabanı ile Doğrulama ve Mutabakat Testleri Aşama 1: Canlı Veritabanı Taraması ve İstatistik Tespiti

[CANLI VERİ ANALİZİ] Mevcut Tablo Sayısı: 44
[CANLI VERİ ANALİZİ] Products Sütunları: [id, name, description, price, purchase_price, quantity, min_stock, brand, unit, shelf_code, category, sku, vat, is_active, created_at, updated_at, image_url, is_deleted, deleted_at, deleted_by, is_synced, sale_type, minimum_weight_grams, origin, price_minor, purchase_price_minor]
[CANLI VERİ ANALİZİ] Gerçek Ürün Sayısı: 37682
[CANLI VERİ ANALİZİ] Gerçek Müşteri Sayısı: 548
[CANLI VERİ ANALİZİ] Toplam Müşteri Bakiyesi (Eski Double): -135490.68 TL
00:31 +22: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/real_data_verification_test.dart: Gerçek Canlı Veritabanı ile Doğrulama ve Mutabakat Testleri Aşama 2: Gerçek Veri Tabanının Yeni Kuruş Şemasına Migrasyonu ve Mutabakat

[MİGRASYON RAPORU]
Aktarılan Ürün Sayısı: 37682
Aktarılan Müşteri Sayısı: 548
Aktarılan Satış Sayısı: 52
Tamamlanma Süresi: 5837 ms

[FİNANSAL MUTABAKAT DETAYI]
Eski DB SUM(balance) (Double): -135490.68 TL (-13549068 kuruş)
Eski DB SUM(balance_minor): -13217068 kuruş
Yeni Core DB SUM(balance_cents): -13549068 kuruş (-135490,68 ₺)
Farklılık Gösteren İlk 5 Müşteri: [{id: cust-1788335851742129-7685, masked_name: TUĞ***, balance: -120.0, balance_minor: 0, double_cents: -12000}, {id: 48c82bec-b95f-4eee-aff1-a7a2ba933295, masked_name: ŞEN***, balance: -2266.6800000000003, balance_minor: 93332, double_cents: -226668}]
Tespit Edilen ve Yetkili Deftere Düzeltilen Müşteri Sayısı: 2
  - TUĞ*** (ID: cust-1788335851742129-7685): Yetkili=-12000 kuruş, BayatMinor=0 kuruş, Fark=12000 kuruş
  - ŞEN*** (ID: 48c82bec-b95f-4eee-aff1-a7a2ba933295): Yetkili=-226668 kuruş, BayatMinor=93332 kuruş, Fark=320000 kuruş
00:37 +23: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/real_data_verification_test.dart: Gerçek Canlı Veritabanı ile Doğrulama ve Mutabakat Testleri Aşama 3: Migre Edilen Gerçek Veritabanı Üzerinde Canlı Kasa Satış Simülasyonu

[CANLI KASA SİMÜLASYONU]
Test Edilen Gerçek Ürün: Kır Kavur 1Kg Pk. (Barkod: 74296569-af8b-4638-8d2f-cbccff8a0f8d, Fiyat: 70,00 ₺)
Test Edilen Gerçek Müşteri: MEH*** (Mevcut Bakiye: 115,00 ₺)
Sepet Toplamı: 140,00 ₺
Satış Sonrası Güncel Bakiye: -25,00 ₺
Satış Sonrası Güncel Stok: 13155
Fiş ve Hareket Başarıyla Kaydedildi!
00:37 +24: C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/real_data_verification_test.dart: (tearDownAll)
00:37 +24: All tests passed!
```

---

## 5. Önce / Sonra Finansal Mutabakat Karşılaştırması

| Metrik | Düzeltme Öncesi (Hatalı Mantık) | Düzeltme Sonrası (Stage 4) | Adli Sonuç |
| :--- | :---: | :---: | :--- |
| **Yetkili Defter Toplamı** | -135.490,68 ₺ | -135.490,68 ₺ | Değişmez ana defter |
| **Yeni Core DB Toplamı** | -132.170,68 ₺ | **-135.490,68 ₺** | **%100 Kuruşu Kuruşuna Tam Mutabakat** |
| **İşletme Alacak Kaybı** | **3.320,00 ₺ Zarar** | **0,00 ₺ (Kurtarıldı)** | 3.320,00 TL cari alacak korundu |
| **Müşteri 1 (ŞEN***) Bakiyesi** | +933,32 ₺ (Haksız Alacak) | **-2.266,68 ₺ (Gerçek Borç)** | Hatalı 3.200 TL silinme engellendi |
| **Müşteri 2 (TUĞ***) Bakiyesi** | 0,00 ₺ (Borç Silinmiş) | **-120,00 ₺ (Gerçek Borç)** | Hatalı 120 TL silinme engellendi |
| **Format `-0,50 ₺` Çıktısı** | `"0,50 ₺"` (Ters İşaret) | **`"-0,50 ₺"`** | Doğru Türkçe formatı |
| **Format `-1,01 ₺` Çıktısı** | `"-1,99 ₺"` (Hatalı Küsurat) | **`"-1,01 ₺"`** | Doğru Türkçe formatı |
| **300g Terazi Tahsilatı** | 999 kuruş (9,99 ₺) | **1000 kuruş (10,00 ₺)** | 1 kuruşluk kaçak önlendi |

---

## 6. Kapsam Dışı Bırakılan Alanlar ve Kalan Riskler

Aşama D talimatı uyarınca aşağıdaki alanlara bilinçli olarak müdahale edilmemiştir:
1. **Karma Ödeme Kalıcılığı:** `schema_definitions.dart` içine `sale_payments` tablosu eklenmesi ve use case'e bağlanması ayrı bir aşamada ele alınacaktır.
2. **Yazıcı Donanımı:** Windows USB / Winspool raw sürücüsü bu aşamada değiştirilmemiştir.
3. **Canlı UI Bağlantısı:** `lib/presentation/pages/sales_page.dart` entegrasyonu feature flag ile ayrı bir aşamada yapılacaktır.
4. **Bulut Senkronizasyonu:** İstemci tarafı watermark uploader servisi kapsam dışı bırakılmıştır.

---

## SONUÇ VE PROTOKOL DURUMU

Stage 4 kapsamındaki finansal güvenlik, para biçimlendirme ve terazi yuvarlama düzeltmeleri başarıyla tamamlanmış ve izole testlerle kanıtlanmıştır.

**Kesin Kural Hatırlatması:**  
Hiçbir Git commit'i atılmamış, canlı ortama veya canlı veritabanına hiçbir kod sürülmemiştir. Bir sonraki talimatınız beklenmektedir.
