# SERENUT OS — STAGE 3: ADLİ BULGULARIN BAĞIMSIZ DOĞRULANMASI RAPORU

**Belge Adı:** `CORE_NEXT_STAGE3_FORENSIC_VERIFICATION.md`  
**Denetim Düzeyi:** 3. Aşama Bağımsız Adli Bilişim ve Finansal Mutabakat Doğrulaması  
**Tarih:** 13 Ekim 2026  
**Denetim Rolü:** Bağımsız Kıdemli Yazılım ve Finansal Veri Denetçisi  
**İncelenen Kaynaklar:** Gerçek SQLite Veritabanı (`serenut_pos.db`), Canlı Çalışma Süreci, `lib/` ve `core_next/` Kaynak Kodları  
**Proje Kök Dizini:** `c:\Users\notop\AndroidStudioProjects\shaman_new`  
**Nihai Üretime Çıkış Kararı:** **ONAYLANAMAZ (REJECTED / UNACCEPTABLE)**

---

## 1. Veritabanı Güvenliği ve Adli Kopya Doğrulaması

### 1.1. Canlı Süreç ve WAL Durumu Tespiti
- **Dosya Yolu:** `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\`
- **Çalıştırılan Komut:** `Get-Process -Name "*serenutos*", "*flutter*"`
- **Gözlenen Durum:** `serenutos` ana uygulaması **PID 6240** ile arka planda çalışır durumdadır.
- **Dizin Dosya Durumu:**
  - `serenut_pos.db`: 58.699.776 bayt
  - `serenut_pos.db-wal`: 13.340.592 bayt (13.3 MB birikmiş uncheckpointed WAL günlüğü!)
  - `serenut_pos.db-shm`: 32.768 bayt
- **Adli Risk:** Canlı uygulama çalışırken ve disk üzerinde 13.3 MB'lık aktif WAL dosyası varken, ana `.db` dosyasını tek başına kopyalamak veya dosyaları ayrı ayrı kopyalamak SQLite ACID garantilerini bozar ve bozuk (corrupted/torn read) snapshot üretir.

### 1.2. Tutarlı Adli Snapshot (SQLite Online Backup API)
Uygulamanın çalışmasını engellemeden ve canlı veritabanında hiçbir `INSERT`, `UPDATE`, `DELETE`, `ALTER` veya migrasyon çalıştırmadan, SQLite'ın resmi C-API seviyesindeki **Online Backup API**'si (`src_con.backup(dst_con)`) Python üzerinden çağrılarak izole dizine tam tutarlı bir adli kopya alınmıştır.

- **Kaynak Dosya SHA-256:** `28a1f5fdcd77b318956c042af7b68b3d16f4dcb4fee479365856b9ed8e58c9ae`
- **Adli Kopya Yolu:** `scratch/stage3_verified_backup.db`
- **Adli Kopya Boyutu:** 58.699.776 bayt
- **Adli Kopya SHA-256:** `96bcea725970d5fd4c7b19f21c3f3ae9117285e356424a0b1588d71c6799bd67` (WAL kareleri birleştirilmiş tam disk imajı)
- **Bütünlük Kontrolü (`PRAGMA integrity_check`):**
  - Ham Çıktı: `[('ok',)]`
- **Şema Versiyonu (`PRAGMA user_version`):** `60`
- **Nesne Sayımları (`sqlite_master`):**
  - Tablo Sayısı: **44 adet**
  - Görünüm (View) Sayısı: **2 adet**
  - Trigger Sayısı: **8 adet**
  - İndeks Sayısı: **87 adet**
- **Sınıflandırma:** **KANITLANMIŞ GERÇEK**

---

## 2. 3.320,00 TL Farkının Kök Neden Analizi (Root Cause Forensic)

### 2.1. `v_customer_ledger_effect` Görünümünün Gerçek SQL Tanımı
Veritabanı şemasından (`sqlite_master`) çekilen gerçek görünüm tanımı şöyledir:

```sql
CREATE VIEW v_customer_ledger_effect AS
SELECT 
  id,
  customer_id,
  type,
  amount,
  paid_amount,
  debt_amount,
  reference_id,
  created_at,
  is_deleted,
  CASE 
    WHEN COALESCE(is_deleted, 0) != 0 THEN 0.0
    WHEN type IN ('sale', 'manual_debt') THEN -(CASE WHEN debt_amount > 0 THEN debt_amount ELSE (amount - paid_amount) END)
    WHEN type IN ('payment', 'collection') THEN paid_amount
    WHEN type = 'cancellation' THEN (CASE WHEN debt_amount > 0 THEN debt_amount ELSE (amount - paid_amount) END)
    WHEN type = 'refund' AND paid_amount = 0 THEN amount
    ELSE 0.0
  END AS balance_effect
FROM financial_transactions;
```

**Kritik Gözlem:**
1. Görünüm, önceki raporda zannedildiği gibi `customer_ledger` tablosuna değil, `financial_transactions` tablosuna bakmaktadır.
2. Hesaplanan sütun adı `effect_amount` değil, `balance_effect`'tir.
3. Borçlar eksi (`-`), tahsilatlar artı (`+`) işaretlidir.

### 2.2. Bağımsız Agrega ve Karşılaştırma Sonuçları
İzole adli kopya üzerinde çalıştırılan sorgu sonuçları:

| Veri Kaynağı | Toplam Kayıt Sayısı | Toplam Tutar (TL) | Toplam Kuruş |
| :--- | :---: | :---: | :---: |
| `v_customer_ledger_effect.balance_effect` | 1.314 hareket | **-135.490,68 ₺** | -13.549.068 |
| `customers.balance` (Mevcut Tablo Sütunu) | 548 müşteri | **-135.490,68 ₺** | -13.549.068 |
| `customers.balance_minor` (Migration 60 Sütunu) | 548 müşteri | **-132.170,68 ₺** | -13.217.068 |

**Çapraz Denetim:**
- `customers.balance` ile `v_customer_ledger_effect` arasındaki fark: **TAM 0,00 TL (0 Kuruş)!**
- Tüm 548 müşteride `ABS(customers.balance - v_customer_ledger_effect) > 0.001` şartına uyan **TEK BİR MÜŞTERİ BİLE YOKTUR (0 UYUMSUZLUK)**.
- Buna karşın `customers.balance` ile `customers.balance_minor` arasında tam **+3.320,00 TL (+332.000 Kuruş)** fark vardır.

### 2.3. Farkın Oluşum Mekanizması ve Kod Satırları
Farkın neden sadece `balance_minor` alanında olduğu kod incelemesinde kesin olarak tespit edilmiştir:

1. **Migration 60 (`lib/infrastructure/database/schema/db_migrations.dart:1200-1203`):**
   ```dart
   UPDATE customers 
      SET balance_minor = CAST(ROUND(balance * 100) AS INTEGER), ...
   ```
   Migration 60, `2026-10-12T21:57:46` tarihinde çalışmış ve o an `customers.balance` alanında ne yazıyorsa onu `balance_minor` sütununa tek seferlik kopyalamıştır.

2. **Açılış Onarım Mekanizması (`lib/infrastructure/database/database_provider.dart:134-152`):**
   ```dart
   final repairedCount = await db.rawUpdate('''
     UPDATE customers
        SET balance = COALESCE((
          SELECT CASE
            WHEN ABS(SUM(balance_effect)) < 0.009 THEN 0.0
            ELSE SUM(balance_effect)
          END
            FROM v_customer_ledger_effect v
           WHERE v.customer_id = customers.id
        ), 0.0)
       WHERE ABS(balance - COALESCE(...)) > 0.001
   ''');
   ```
   **HATA KANITI:** Bu fonksiyon açılışta `balance` sütununu deftere (`v_customer_ledger_effect`) eşitlemekte, ancak `balance_minor` alanını güncellememektedir! `balance_minor` alanı bu kodda tamamen UNUTULMUŞTUR!

### 2.4. Farkı Yaratan İki Müşterinin İşlem Detayları (Maskeli)

#### Müşteri 1: `48c82bec-b95f-4eee-aff1-a7a2ba933295` (ŞEN***)
- `customers.balance`: **`-2.266,68 TL`** (2.266,68 TL BORÇLU)
- `customers.balance_minor`: **`+93332`** (933,32 TL ALACAKLI!)
- Net Sapma: **`+3.200,00 TL` (+320.000 kuruş)**
- **Adli Tetikleyici Kanıtı (`trigger_audit_logs`):**
  - Kayıt No 1268 (2026-10-10 19:13:18): `manual_debt` işlemi 10.000 TL borç, 3.200 TL peşin ödeme ile girilmiş. Eski SQLite trigger'ı `trg_ft_insert`, bakiyeyi `0.0 -> -6.800.0 TL` yapmıştır.
  - Kayıt No 1269 (2026-10-10 19:13:18): Sistem AYRICA bağımsız bir 3.200 TL'lik `collection` kaydı eklemiş ve trigger bakiyeyi `-6.800.0 -> -3.600.0 TL` yapmıştır. **(3.200 TL mükerrer alacak yazılmıştır!)**
  - Kayıt No 1277 (2026-10-11 09:18:28): Son tahsilat sonrası trigger müşterinin bakiyesini **`+933,32 TL`** olarak bırakmıştır.
  - Migration 60 çalıştığında `customers.balance` alanındaki bu hatalı `+933,32 TL` değeri `balance_minor = 93332` olarak dondurulmuştur.
  - Daha sonra `_reconcileAllCustomerBalances()` çalışmış; defter görünümü (`v_customer_ledger_effect`) 10.000 TL borç ve 7.733,32 TL tahsilatın neti olan gerçek **`-2.266,68 TL`** borcu doğru hesaplayarak `balance`'a yazmış; ancak `balance_minor`'a dokunmadığı için `balance_minor` 933,32 TL alacak olarak kalmıştır.

#### Müşteri 2: `cust-1788335851742129-7685` (TUĞ***)
- `customers.balance`: **`-120,00 TL`** (120,00 TL BORÇLU)
- `customers.balance_minor`: **`0`** (0 TL)
- Net Sapma: **`+120,00 TL` (+12.000 kuruş)**
- **Adli Tetikleyici Kanıtı (`trigger_audit_logs`):**
  - Kayıt No 1291 (2026-10-11 15:07:32): Trigger bir tahsilat sonrası bakiyeyi yanlışlıkla `0.0 TL` yapmış ve Migration 60 `balance_minor = 0` kaydetmiştir.
  - Defterdeki 12.000 TL borç ve 11.880 TL toplam tahsilatın neti olan `-120,00 TL`, `_reconcileAllCustomerBalances()` tarafından `balance` alanına onarılarak yazılmış, ancak `balance_minor` sıfırda bırakılmıştır.

### 2.5. Hüküm ve Yetkili Kaynak Tespiti
- `balance_minor` sütunu yetkili kaynak DEĞİLDİR; Migration 60 anındaki hatalı trigger durumunu yansıtan bayat (stale) bir kalıntıdır.
- Gerçek ve yasal yetkili kaynak, tüm işlem hareketlerini tutan `v_customer_ledger_effect` ve onunla %100 örtüşen `balance` sütunudur.
- **Tehlike:** `core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart` Satır 180'deki `if (row['balance_minor'] != null)` mantığı, bu bayat sütunu defterin üstüne yazarak **işletmenin 3.320,00 TL alacağını anında silmektedir**.
- **Sınıflandırma:** **KANITLANMIŞ GERÇEK**
- **Finansal Risk:** **KRİTİK / P0 (Doğrudan Kasa Kaybı)**

---

## 3. Para Biçimlendirme ve Tartı Yuvarlama Testleri

### 3.1. `MoneyCents.formatTL()` Negatif Sayı Testi
- **Dosya Yolu:** `core_next/client_core/lib/domain/models/money_cents.dart:27-31`
- **Mevcut Kod:**
  ```dart
  String formatTL() {
    final liraPart = value ~/ 100;
    final kurusPart = (value % 100).abs().toString().padLeft(2, '0');
    return '$liraPart,$kurusPart ₺';
  }
  ```
- **Çalıştırılan Test:** `dart run scratch/stage3_dart_test.dart`
- **Ham Test Çıktısı:**

```text
Girdi: -101 kuruş | Gözlenen: "-1,99 ₺" | Beklenen: "-1,01 ₺" | [BAŞARISIZ]
Girdi: -100 kuruş | Gözlenen: "-1,00 ₺" | Beklenen: "-1,00 ₺" | [BAŞARILI]
Girdi:  -99 kuruş | Gözlenen:  "0,01 ₺" | Beklenen: "-0,99 ₺" | [BAŞARISIZ - İŞARET DÖNDÜ!]
Girdi:  -50 kuruş | Gözlenen:  "0,50 ₺" | Beklenen: "-0,50 ₺" | [BAŞARISIZ - İŞARET DÖNDÜ!]
Girdi:   -1 kuruş | Gözlenen:  "0,99 ₺" | Beklenen: "-0,01 ₺" | [BAŞARISIZ - İŞARET DÖNDÜ!]
Girdi:    0 kuruş | Gözlenen:  "0,00 ₺" | Beklenen:  "0,00 ₺" | [BAŞARILI]
Girdi:    1 kuruş | Gözlenen:  "0,01 ₺" | Beklenen:  "0,01 ₺" | [BAŞARILI]
Girdi:   50 kuruş | Gözlenen:  "0,50 ₺" | Beklenen:  "0,50 ₺" | [BAŞARILI]
Girdi:   99 kuruş | Gözlenen:  "0,99 ₺" | Beklenen:  "0,99 ₺" | [BAŞARILI]
Girdi:  100 kuruş | Gözlenen:  "1,00 ₺" | Beklenen:  "1,00 ₺" | [BAŞARILI]
Girdi:  101 kuruş | Gözlenen:  "1,01 ₺" | Beklenen:  "1,01 ₺" | [BAŞARILI]
```

**Kök Neden:** Dart'ta `%` Euclidean modulo olduğu için negatif bölünenlerde pozitif kalan verir (`-101 % 100 = 99`). Ayrıca `-50 ~/ 100 = 0` olduğundan eksi işareti düşmektedir.  
**Sınıflandırma:** **KANITLANMIŞ GERÇEK**  
**Öncelik:** **KRİTİK / P0**

---

### 3.2. Tartılı Satış (Terazi) Kuruş Yuvarlama Testi
- **Dosya Yolu:** `core_next/client_core/lib/presentation/sales/core_sales_flow_state.dart:25`
- **Birim Doğrulaması:**
  - `unitPrice.value`: Kuruş / kg (Örn: 3.333 kuruş/kg = 33,33 TL/kg)
  - `quantity`: Gram
- **Mevcut Kod Formülü:** `(unitPrice.value * quantity) ~/ 1000`
- **Doğru Tamsayı Ticari Yarım-Yukarı Formülü:** `(unitPrice.value * quantity + 500) ~/ 1000`
- **Ham Test Çıktısı:**

```text
Ağırlık:    1 g | Ham:    3.333 kuruş | Mevcut (~/ 1000):    3 | Ticari Yarım-Yukarı:    3 | Fark:  0 kuruş
Ağırlık:   10 g | Ham:   33.330 kuruş | Mevcut (~/ 1000):   33 | Ticari Yarım-Yukarı:   33 | Fark:  0 kuruş
Ağırlık:  100 g | Ham:  333.300 kuruş | Mevcut (~/ 1000):  333 | Ticari Yarım-Yukarı:  333 | Fark:  0 kuruş
Ağırlık:  300 g | Ham:  999.900 kuruş | Mevcut (~/ 1000):  999 | Ticari Yarım-Yukarı: 1000 | Fark: -1 kuruş EKSİK!
Ağırlık:  500 g | Ham: 1666.500 kuruş | Mevcut (~/ 1000): 1666 | Ticari Yarım-Yukarı: 1667 | Fark: -1 kuruş EKSİK!
Ağırlık:  999 g | Ham: 3329.667 kuruş | Mevcut (~/ 1000): 3329 | Ticari Yarım-Yukarı: 3330 | Fark: -1 kuruş EKSİK!
Ağırlık: 1000 g | Ham: 3333.000 kuruş | Mevcut (~/ 1000): 3333 | Ticari Yarım-Yukarı: 3333 | Fark:  0 kuruş
```

**Bulgu:** `~/ 1000` tamsayı kesmesi, virgülden sonra `0,5` kuruş ve üzeri olan tartımlarda 1 kuruş eksik tahsilata yol açmaktadır.  
**Sınıflandırma:** **KANITLANMIŞ GERÇEK**  
**Öncelik:** **YÜKSEK / P1**

---

## 4. Ödeme Kalıcılığı, Yazıcı ve Senkronizasyon Analizi

### 4.1. Parçalı (Karma) Ödeme Kalıcılığı
- **Dosya Yolları:**
  - `core_next/client_core/lib/domain/usecases/checkout_use_case.dart:68-138`
  - `core_next/client_core/lib/infrastructure/database/schema_definitions.dart:75-145`
- **Gözlenen Kod Gerçeği:**
  - `checkout_use_case.dart` içindeki `_db.transaction` bloğunda `sales`, `sale_items`, `products` ve `ledger_entries` tablolarına yazma yapılmaktadır.
  - `state.paymentSplits` listesi SQLite'a **ASLA INSERT EDİLMEMEKTEDİR**.
  - `schema_definitions.dart` içinde `sale_payments` adında bir tablo **MEVCUT DEĞİLDİR**.
  - `paymentSplits` yalnızca bellek içi `SaleOrderEntity` nesnesine parametre olarak geçilmektedir (Satır 151).
- **Sonuç:** Uygulama kapatılıp açıldığında ödeme türleri yok olmakta, Z raporu için nakit/kart ayrımı SQLite üzerinden sorgulanamamaktadır.
- **Sınıflandırma:** **KANITLANMIŞ GERÇEK**
- **Öncelik:** **YÜKSEK / P1**

---

### 4.2. Yazıcı ve Donanım Katmanı
- **Dosya Yolu:** `core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart:132-156`

| Donanım Bileşeni | Kod Durumu | Kanıt Satırı / Dosya |
| :--- | :---: | :--- |
| **TCP/IP Ağ Yazıcısı** | **UYGULANDI** | `hardware_worker.dart:142` -> `Socket.connect(targetAddress, port)` |
| **USB Yazıcı** | **STUB / YORUM** | `hardware_worker.dart:153` -> Yalnızca `// Not: USB ve Bluetooth taşımaları...` yorumu vardır, kod yoktur. |
| **Bluetooth Yazıcı** | **STUB / YORUM** | Kod yoktur, sadece yorum mevcuttur. |
| **COM / Seri Terazi** | **HİÇ YOK** | `core_next` içinde COM port veya terazi veri dinleyicisi bulunmamaktadır. |
| **Kalıcı Yazdırma Kuyruğu** | **HİÇ YOK** | Kuyruk yalnızca RAM üzerindedir (`SendPort`). SQLite'ta `print_queue` tablosu yoktur. |

- **Sınıflandırma:** **KANITLANMIŞ GERÇEK**
- **Öncelik:** **YÜKSEK / P1**

---

### 4.3. Çevrimdışı Bulut Senkronizasyon Zinciri

| Zincir Adımı | Çağrı Noktası / Dosya | Durum |
| :--- | :--- | :---: |
| **1. SQLite Veri Değişikliği** | `checkout_use_case.dart:102` (`sales` insert) | **MEVCUT** |
| **2. Kalıcı Sync Event Üretimi** | `schema_definitions.dart:159` (`sync_events` tablosu var) | **EKSİK (Use case'de INSERT kodu yok)** |
| **3. İstemciden HTTP Upload** | `core_next/client_core` içinde HTTP sync client | **EKSİK (Hiçbir Dart HTTP servisi yok)** |
| **4. Sunucu İşleme & Doğrulama** | `core_next/server_core/src/sync/watermark_sync_service.ts:36` | **MEVCUT (Yalnızca TypeScript)** |
| **5. PostgreSQL Kaydı** | `watermark_sync_service.ts:70` (`sync_event_log`) | **MEVCUT (Yalnızca TypeScript)** |
| **6. Sunucu Yanıtı (Acknowledge)** | `watermark_sync_service.ts:114` | **MEVCUT (Yalnızca TypeScript)** |
| **7. İstemci Watermark Güncellemesi** | İstemcide ACK karşılama ve watermark kaydı | **EKSİK (İstemci kodu yok)** |

- **Hüküm:** Yalnızca sunucu tarafında bir TypeScript dosyasının bulunması, senkronizasyonun çalıştığı anlamına gelmez. İstemci ayağı tamamen boştur.
- **Sınıflandırma:** **KANITLANMIŞ GERÇEK**
- **Öncelik:** **ORTA / P2**

---

## 5. Güvenli Sonraki Adımlar ve Düzeltme Protokolü

Bu aşamada hiçbir kaynak kod veya veritabanı değiştirilmemiştir. Düzeltme aşamasına geçildiğinde izlenecek güvenli sıra:

1. **Adım 1 (P0): `migration_bridge_engine.dart` Düzeltmesi:**
   - Satır 180'deki `balance_minor` önceliği kaldırılmalı; doğrudan `(row['balance'] * 100).round()` alınarak defterle birebir mutabakat sağlanmalıdır.
2. **Adım 2 (P0): `money_cents.dart` `formatTL()` Düzeltmesi:**
   - `value.abs()` ve işaret kontrolü ile `-1,01 ₺`, `-0,50 ₺` negatif gösterimi matematiksel olarak düzeltilmelidir.
3. **Adım 3 (P1): `core_sales_flow_state.dart` Terazi Yuvarlama Düzeltmesi:**
   - `((unitPrice.value * quantity + 500) ~/ 1000)` tamsayı ticari yuvarlaması uygulanmalıdır.
4. **Adım 4 (P1): `schema_definitions.dart` & `checkout_use_case.dart` Parçalı Ödeme Tablosu:**
   - `sale_payments` tablosu eklenmeli ve atomic transaction içine dahil edilmelidir.
5. **Adım 5 (P1): Windows USB ESC/POS Yazıcı Entegrasyonu:**
   - `HardwareWorker` içine winspool veya platform kanalı ile USB yazdırma eklenmelidir.
6. **Adım 6 (P1): Canlı Satış Ekranı (`sales_page.dart`) Feature Flag Entegrasyonu:**
   - UI güvenli bayrakla yeni motora bağlanmalıdır.

---

## NİHAİ META-HÜKÜM

### Karar: **ONAYLANAMAZ (REJECTED)**
Stage 3 adli incelemesi; 3.320,00 TL'lik alacak silinmesi riskini, negatif para formatlama faciasını, terazideki kuruş kaybını ve parçalı ödeme kalıcılık eksikliğini doğrudan kod satırları, veri tabanı trigger günlükleri ve ham test çıktılarıyla **%100 kanıtlamıştır**. Sistem bu 6 madde düzeltilmeden ve regresyon testleri geçmeden **kesinlikle canlıya alınamaz**.
