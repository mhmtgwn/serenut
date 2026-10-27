# SERENUT OS — İKİNCİ AŞAMA BAĞIMSIZ DENETİM VE META-DENETÇİ RAPORU

**Belge Adı:** `CORE_NEXT_SECOND_PASS_AUDIT.md`  
**Denetim Seviyesi:** İkinci Aşama Bağımsız Meta-Denetim (Denetçinin Raporunu Denetleme)  
**Tarih:** 13 Ekim 2026  
**Denetçi Uzmanlık Rolü:** Bağımsız Kıdemli Sistem Denetçisi, Veri Bütünlüğü ve Finansal Adli Bilişim Uzmanı  
**Denetlenen Rapor:** `CORE_NEXT_INDEPENDENT_AUDIT.md` (İlk Aşama Denetim Raporu)  
**Proje Kök Dizini:** `c:\Users\notop\AndroidStudioProjects\shaman_new`  
**Nihai Üretime Çıkış Kararı:** **ONAYLANAMAZ (UNACCEPTABLE / REJECTED)**

---

## BÖLÜM 1: İlk Rapordaki Doğru İddialar

Aşağıdaki bulgular, doğrudan kaynak kodları, Git versiyon kontrol sistemi ve yerel üretim veritabanı kopyası üzerinde bağımsız olarak çalıştırılan adli sorgularla **DOĞRULANMIŞTIR**:

| İddia Konusu | İlk Rapordaki İfade | İkinci Denetim Adli Kanıtı | Durum |
| :--- | :--- | :--- | :---: |
| **Git Çalışma Ağacı Temizliği** | `core_next/` ve `test/core_next/` dizinleri untracked; `lib/` ellenmemiş. | `git status --short` çıktısında `lib/` dizinine ait tek bir değiştirilmiş dosya dahi yoktur. Mevcut `lib/` tamamen korunmaktadır. | **DOĞRULANDI** |
| **Canlı Kodun Bağımsızlığı (Unwired)** | `lib/` içinde `core_next` sıfır sonuç veriyor. | `git grep "core_next" lib/` komutu çıkış kodu 1 (0 satır eşleşmesi) üretmiştir. Canlı POS arayüzü yeni motora henüz bağlanmamıştır. | **DOĞRULANDI** |
| **Legacy SQLite Trigger Sayısı** | Eski sistemde tam 8 adet SQLite trigger'ı mevcuttur. | Kod taramasında: `lib/data/database/db_triggers.dart` içinde 5 adet (`trg_ft_block_update`, `trg_ft_block_delete`, `trg_ft_insert`, `trg_ft_update`, `trg_ft_delete`) ve `lib/data/database/fts/product_search_index.dart` içinde 3 adet (`products_search_fts_ai`, `products_search_fts_ad`, `products_search_fts_au`) olmak üzere **tam 8 trigger** tespit edilmiştir. | **DOĞRULANDI** |
| **Yeni Şema Tablo ve İndeks Sayısı** | Yeni Core Next şemasında 11 tablo ve 12 B-Tree indeks vardır. | `core_next/client_core/lib/infrastructure/database/schema_definitions.dart` dosyasında tam 11 tablo (`schema_migrations`, `stores`, `cash_registers`, `users`, `products`, `customers`, `customer_ledger`, `sales`, `sale_items`, `stock_ledger`, `sync_events`) ve 12 CREATE INDEX ifadesi tanımlanmıştır. | **DOĞRULANDI** |
| **Test Senaryosu Koşumu** | `flutter test test/core_next/` 20 testin tamamını geçmektedir. | `flutter test test/core_next/` komutu bağımsız olarak çalıştırılmış, 20 test senaryosu da exit code 0 ile `All tests passed!` vermiştir. | **DOĞRULANDI** |
| **Üretim Veritabanı Boyutu ve Özeti** | Gerçek DB boyutu 58.699.776 bayttır. | `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db` dosyasının boyutu tam **58.699.776 bayt**, SHA-256 hash değeri `28A1F5FDCD77B318956C042AF7B68B3D16F4DCB4FEE479365856B9ED8E58C9AE` ve SQLite `PRAGMA user_version` değeri `60` olarak doğrulanmıştır. | **DOĞRULANDI** |

---

## BÖLÜM 2: İlk Raporda Yetersiz Kanıtlanan İddialar

İlk denetim raporunda doğrulanmış gibi sunulan ancak adli derinlemesine incelemede kanıtları eksik, yüzeysel veya yanıltıcı bulunan hususlar şunlardır:

1. **`real_data_verification_test.dart` Testinin Gerçek Veri Kapsamı:**
   - *İlk Raporun İddiası:* Gerçek veritabanından 548 müşteri, 1.488 ürün, 10.421 satışın aktarıldığı ve bakiyelerin kusursuz mutabakatla doğrulandığı iddia edilmiştir.
   - *Adli Gerçeklik:* [KISMEN DOĞRULANDI / YETERSİZ KANITLANMIŞ]. Test, veritabanını okumaktadır; ancak cari bakiyeleri test ederken sadece `balance_minor` sütununa bakmıştır. Müşteri cari hareketlerinin asıl yasal defteri olan `customer_ledger` tablosu ve `v_customer_ledger_effect` VIEW'ı ile hiçbir çapraz sorgu (cross-reconciliation) yapmamıştır.

2. **İdempotency ve Senkronizasyon İddiası:**
   - *İlk Raporun İddiası:* Sunucu PostgreSQL tarafındaki `ON CONFLICT (id) DO NOTHING` ifadesine dayanılarak senkronizasyonun tamamen idempotent ve üretime hazır olduğu iddia edilmiştir.
   - *Adli Gerçeklik:* [YETERSİZ KANITLANMIŞ]. Senkronizasyon bir çift yönlü protokoldür. İstemci tarafında `sync_events` kuyruğuna kayıt atan bir use case kodu olmadığı gibi, bu kayıtları HTTP ile VPS'e gönderen hiçbir istemci servisi mevcut değildir. Uçtan uca çalışmayan bir sistem için "idempotent ve güvenli" denemez.

3. **Yazdırma Donanımı Desteği:**
   - *İlk Raporun İddiası:* Donanım katmanının hazır olduğu, sadece USB için küçük bir stub kaldığı belirtilmiş ve üretime "Koşullu Onay" verilmiştir.
   - *Adli Gerçeklik:* [YETERSİZ KANITLANMIŞ]. Perakende POS sektöründe yazıcıların %90'ı USB ve Seri (COM) port üzerinden bağlanır. `HardwareWorker` içinde USB yazdırma `// TODO: platform USB print` seviyesindedir. Kasiyer fiş kesemez durumdayken bu eksikliği "küçük bir koşul" olarak nitelemek yetersiz kanıttır.

---

## BÖLÜM 3: Yanlış veya Çelişkili Sonuçlar

İlk denetim raporunun en vahim yanılgıları ve sistemik hataları aşağıdadır:

### 3.1. 3.320,00 TL'lik Mutabakat Yanılsaması (Büyük Tehlike)
- **İlk Rapordaki Hata:** İlk denetçi, eski tablodaki `SUM(balance_minor)` değeri (-13.217.068 kuruş = -132.170,68 TL) ile yeni aktarılan müşterilerin kuruş toplamı eşit çıkınca bunu *"0 kuruş farkla tam mutabakat"* olarak ilan etmiştir.
- **Adli Bulgumuz:** Bu kabul **TAMAMEN YANLIŞTIR**. Eski veritabanında asıl yetkili bakiye `balance` sütununda ve `v_customer_ledger_effect` defterindedir:
  $$\text{Defter Bakiyesi (Gerçek)} = -135.490,68 \text{ TL}$$
  $$\text{balance\_minor Toplamı} = -132.170,68 \text{ TL}$$
  $$\text{Açık (Fark)} = +3.320,00 \text{ TL} \quad (+332.000 \text{ kuruş})$$
- `MigrationBridgeEngine.dart` satır 180'de körü körüne `balance_minor`'ı baz aldığı için:
  - **Müşteri `48c82bec-b95f-4eee-aff1-a7a2ba933295` (ŞEN***):** Defterde gerçek borcu **-2.266,68 TL** iken, bozuk `balance_minor` nedeniyle yeni sisteme **+933,32 TL ALACAKLI** olarak aktarılmaktadır! (3.200,00 TL işletme aleyhine açık).
  - **Müşteri `cust-1788335851742129-7685` (TUĞ***):** Gerçek borcu **-120,00 TL** iken, `balance_minor = 0` olduğu için borcu **tamamen silinmektedir!**
- **Hüküm:** **YANLIŞLANDI / HATALI KABUL**. Bu migrasyon canlıya alınırsa işletmenin 3.320,00 TL alacağı buharlaşacak ve borçlu müşteriye 933 TL haksız alacak yazılacaktır!

### 3.2. İlk Raporun "Koşullu Onaylanabilir" Kararı
- **İlk Rapordaki Hata:** "4 engeli kaldırın ve canlıya alın" denmiştir.
- **Adli Bulgumuz:** Bu karar **ÇELİŞKİLİ VE GEÇERSİZDİR**. Cari alacakları silen, borçlu müşteriye ekranda pozitif bakiye gösteren, tartılı ürünlerde her tartıda eksik tahsilat yapan ve parçalı ödemeleri veritabanına yazmayan bir mimariye hiçbir şart altında "Onay" verilemez.

---

## BÖLÜM 4: Yeniden Üretilen Finansal Hesaplamalar

Üretim veritabanı kopyası üzerinde çalıştırılan SQL sorguları ile mali durum santim santim yeniden hesaplanmıştır:

```sql
-- 1. Yetkili Defter Toplamı
SELECT ROUND(SUM(effect_amount), 2) AS total_ledger_tl FROM v_customer_ledger_effect;
-- Çıktı: -135490.68 TL

-- 2. customers tablosundaki balance (Double) Toplamı
SELECT ROUND(SUM(balance), 2) AS total_balance_double_tl FROM customers;
-- Çıktı: -135490.68 TL (Defterle %100 tam denk!)

-- 3. customers tablosundaki balance_minor (Integer) Toplamı
SELECT SUM(balance_minor) / 100.0 AS total_balance_minor_tl FROM customers;
-- Çıktı: -132170.68 TL (3.320,00 TL EKSİK!)
```

### Soruların Yanıtları:
1. **`balance_minor` hangi migration'da oluşturulmuş?**
   - Migration 60 (`migration_v60_ledger_snapshot_and_minor_units.dart`) dosyasında `ALTER TABLE customers ADD COLUMN balance_minor INTEGER;` ile eklenmiş ve `UPDATE customers SET balance_minor = CAST(ROUND(balance * 100) AS INTEGER)` formülüyle doldurulmuştur.
2. **Neden `balance` ile `balance_minor` arasında fark var?**
   - Kod tabanı incelendiğinde (`lib/data/database/database_provider.dart`), `_reconcileAllCustomerBalances()` metodu periyodik olarak çalışarak müşteri bakiyelerini defterden (`v_customer_ledger_effect`) çekip `customers.balance` alanına yazmaktadır.
   - Ancak geliştirici bu uzlaştırma fonksiyonuna `balance_minor = CAST(ROUND(balance * 100) AS INTEGER)` güncellemesini eklemeyi **unutmuştur**! Dolayısıyla Migration 60'tan sonra cari hesabı değişen müşterilerde `balance` güncellenmiş fakat `balance_minor` eski (stale) kalmıştır.
3. **Müşteri bazında durum nedir?**
   - 548 müşteriden 546 tanesinde `balance * 100 == balance_minor` tam eşleşmektedir.
   - Farkın %100'ü yalnızca 2 müşteriden kaynaklanmaktadır:
     - `48c82bec-b95f-4eee-aff1-a7a2ba933295`: Defter `-2266.68 TL`, Minor `+933.32 TL` (Fark: `+3200.00 TL`)
     - `cust-1788335851742129-7685`: Defter `-120.00 TL`, Minor `0.00 TL` (Fark: `+120.00 TL`)
4. **Farklar birbirini götürüyor mu?**
   - Hayır. Her iki fark da borcu eksiltici yöndedir. Toplam borç defterde `135.490,68 TL` iken `balance_minor`'da `132.170,68 TL`'ye inmektedir.

---

## BÖLÜM 5: Testlerin Ham Sonuçları (Forensic Reproductions)

### 5.1. `MoneyCents.formatTL()` Negatif Sayı Testi
`scratch/audit_stage2_forensic.dart` betiği ile gerçek `MoneyCents` sınıfı doğrudan çağrılmış ve şu çıktılar alınmıştır:

```text
=== MONEY CENTS FORMAT TL HAM TESTİ ===
Girdi: -101 kuruş  | Beklenen: "-1,01 ₺" | Üretilen: "-1,99 ₺" | [BAŞARISIZ]
Girdi: -100 kuruş  | Beklenen: "-1,00 ₺" | Üretilen: "-1,00 ₺" | [BAŞARILI]
Girdi: -99 kuruş   | Beklenen: "-0,99 ₺" | Üretilen: "0,01 ₺"  | [BAŞARISIZ - İŞARET POZİTİF OLDU!]
Girdi: -50 kuruş   | Beklenen: "-0,50 ₺" | Üretilen: "0,50 ₺"  | [BAŞARISIZ - İŞARET POZİTİF OLDU!]
Girdi: -1 kuruş    | Beklenen: "-0,01 ₺" | Üretilen: "0,99 ₺"  | [BAŞARISIZ - İŞARET POZİTİF OLDU!]
Girdi: 0 kuruş     | Beklenen: "0,00 ₺"  | Üretilen: "0,00 ₺"  | [BAŞARILI]
Girdi: 1 kuruş     | Beklenen: "0,01 ₺"  | Üretilen: "0,01 ₺"  | [BAŞARILI]
Girdi: 50 kuruş    | Beklenen: "0,50 ₺"  | Üretilen: "0,50 ₺"  | [BAŞARILI]
Girdi: 99 kuruş    | Beklenen: "0,99 ₺"  | Üretilen: "0,99 ₺"  | [BAŞARILI]
Girdi: 100 kuruş   | Beklenen: "1,00 ₺"  | Üretilen: "1,00 ₺"  | [BAŞARILI]
Girdi: 101 kuruş   | Beklenen: "1,01 ₺"  | Üretilen: "1,01 ₺"  | [BAŞARILI]
```

**Matematiksel İzah:**
Dart dilinde `%` operatörü Euclidean modülasyondur:
$$-101 \pmod{100} = 99, \quad -50 \pmod{100} = 50$$
Ayrıca `-50 ~/ 100 = 0` olduğundan eksi işareti tamamen kaybolmaktadır.

### 5.2. Terazi Tartı Kuruş Kırpma Sınır Testleri
Birim fiyat: `3.333 kuruş/kg (33,33 TL/kg)`. Mevcut kod formülü: `(unitPrice.value * quantity) ~/ 1000`.

```text
=== TERAZİ SINIR TESTLERİ HAM ÇIKTISI ===
Ağırlık: 1 gram    | Ham: 3.333 kuruş    | ~/ 1000: 3 kuruş    | round: 3 kuruş    | Fark: 0
Ağırlık: 10 gram   | Ham: 33.330 kuruş   | ~/ 1000: 33 kuruş   | round: 33 kuruş   | Fark: 0
Ağırlık: 100 gram  | Ham: 333.300 kuruş  | ~/ 1000: 333 kuruş  | round: 333 kuruş  | Fark: 0
Ağırlık: 300 gram  | Ham: 999.900 kuruş  | ~/ 1000: 999 kuruş  | round: 1000 kuruş | Fark: -1 kuruş EKSİK!
Ağırlık: 500 gram  | Ham: 1666.500 kuruş | ~/ 1000: 1666 kuruş | round: 1667 kuruş | Fark: -1 kuruş EKSİK!
Ağırlık: 999 gram  | Ham: 3329.667 kuruş | ~/ 1000: 3329 kuruş | round: 3330 kuruş | Fark: -1 kuruş EKSİK!
Ağırlık: 1000 gram | Ham: 3333.000 kuruş | ~/ 1000: 3333 kuruş | round: 3333 kuruş | Fark: 0
```
**Bulgu:** `~/ 1000` tamsayı kesmesi yaptığı için, virgülden sonraki `0,5` kuruş ve üzeri değerler ticari standartlara (half-up) aykırı olarak aşağı atılmakta ve kasada eksik para alınmaktadır.

---

## BÖLÜM 6: Gerçek Veri Mutabakatının Kapsamı ve Sınırları

- **Kapsam:** Üretim veritabanındaki 548 müşteri, 1.488 ürün, 10.421 satış faturası ve 14.863 fatura kalemi başarıyla okunabilmektedir.
- **Sınırlar ve Kısıtlar:**
  1. `customers` tablosundaki `balance_minor` sütunu güvenilmezdir. Güvenilir ve yasal tek dayanak `balance` sütunu ve `v_customer_ledger_effect` defter görünümüdür.
  2. Eski sistemdeki satışlar geçmişe dönük olarak tek parça ödeme gibi tutulmuştur; geçmiş satışlardan parça ödeme detayları üretilemez.
  3. Veritabanında hiçbir müşteri bilgisi şifreli değildir (SQLCipher kuralına uygundur).

---

## BÖLÜM 7: Doğrulanmış Eksikler

1. **`MigrationBridgeEngine` Müşteri Bakiyesi Aktarım Hatası (KRİTİK):**
   - Kod satırı: `migration_bridge_engine.dart:180`
   - Bozuk `balance_minor` sütunu yetkili kabul edildiği için işletmenin 3.320,00 TL alacağı silinmektedir.
2. **`MoneyCents.formatTL()` Negatif Gösterim Faciası (KRİTİK):**
   - Kod satırı: `money_cents.dart:28-30`
   - Borçlu müşterilerin borcu pozitif bakiye veya yanlış küsurat olarak ekranda görünmektedir.
3. **Tartılı Satışlarda Yarım Kuruş Kırpılması (ÖNEMLİ):**
   - Kod satırı: `core_sales_flow_state.dart:46`
   - `~/ 1000` kesmesi sebebiyle terazi satışlarında 1 kuruş eksik tahsilat yapılmaktadır.
4. **Karma (Parçalı) Ödeme Kalıcılık Eksikliği (ÖNEMLİ):**
   - `schema_definitions.dart` ve `checkout_use_case.dart` içinde `sale_payments` tablosu yoktur. 50 TL nakit + 50 TL kart ödemesi yapıldığında bu ayrım veritabanına kaydedilmemekte, Z raporu için nakit/kart dökümü alınamamaktadır.
5. **Yazdırma Katmanında USB ve Seri Port Yokluğu (ÖNEMLİ):**
   - `hardware_worker.dart` içinde yalnızca Ethernet TCP/IP soketi vardır; USB ve Seri portlar stub'dır.
6. **İstemci Tarafı Çevrimdışı Senkronizasyon Eksikliği (ORTA):**
   - `sync_events` tablosu olmasına rağmen hiçbir use case event üretmemekte ve hiçbir servis bu eventleri VPS'e göndermemektedir.
7. **Kullanıcı Arayüzü Entegrasyonunun Olmaması (ÖNEMLİ):**
   - `sales_page.dart` ve ilgili UI bileşenleri tamamen eski `sales_controller.dart` üzerindedir; yeni motora bağlı değildir.

---

## BÖLÜM 8: Önceliklendirilmiş Düzeltme Önerileri

Aşağıdaki sıra, sistemin üretime hazır hale gelmesi için zorunlu uygulama sırasıdır:

1. **P0 (Can Kurtaran): `migration_bridge_engine.dart` Düzeltmesi:**
   - `balance_minor` kontrolü kaldırılmalı; daima `(row['balance'] * 100).round()` ve `v_customer_ledger_effect` esas alınmalıdır. 3.320 TL alacak kaybı engellenmelidir.
2. **P0 (Finansal Gösterim): `money_cents.dart` `formatTL()` Düzeltmesi:**
   - Modulo yerine mutlak değer (`value.abs()`) alınmalı ve negatif sayılarda başa eksi işareti eklenmelidir.
3. **P1 (Kasa Doğruluğu): `core_sales_flow_state.dart` Terazi Yuvarlama Düzeltmesi:**
   - `~/ 1000` yerine `((unitPrice.value * quantity) / 1000).round()` ticari yarım yukarı yuvarlaması uygulanmalıdır.
4. **P1 (Kalıcılık): `sale_payments` Tablosu ve Repository Eklenmesi:**
   - SQLite şemasına `sale_payments` tablosu eklenmeli, nakit ve kart kırılımları atomic transaction içinde kaydedilmelidir.
5. **P1 (Donanım): Windows USB/Win32 RAW Yazıcı Desteği:**
   - `HardwareWorker` içine Windows yazıcı biriktiricisine (winspool) doğrudan ESC/POS baytları basan transport eklenmelidir.
6. **P1 (Arayüz): Feature Flag ile UI Bağlantısı:**
   - `sales_page.dart` yeni `coreSalesFlowProvider`'a bağlanmalı, eski ve yeni motor arasında güvenli geçiş sağlanmalıdır.
7. **P2 (Senkronizasyon): İstemci Sync Event Gönderici Servisi:**
   - Satış ve stok hareketlerinde `sync_events` kaydı atılmalı ve arka plan worker'ı ile VPS'e ulaştırılmalıdır.

---

## BÖLÜM 9: Üretim Kabul Kriterleri (Production Acceptance Matrix)

Sistem canlıya alınmadan önce aşağıdaki matristeki her bir maddenin bağımsız testle doğrulanması şarttır:

| Kabul Alanı | Gerekli Kanıt ve Doğrulama | Gerçek Durum | Engelleyici mi? |
| :--- | :--- | :---: | :---: |
| **Finansal Doğruluk** | Defter (`-135.490,68 TL`) ile yeni şema kuruş toplamının %100 denk olması. | Şu an 3.320 TL açık var. | **EVET (BLOCKER)** |
| **Negatif Para Formatı** | Borç bakiyelerinin ekranda `-0,50 ₺`, `-1,01 ₺` olarak doğru görünmesi. | Şu an `0,50 ₺` ve `-1,99 ₺` çıkıyor. | **EVET (BLOCKER)** |
| **Terazi Yuvarlaması** | 300g tartımda 1.000 kuruş (10,00 TL) tahsil edilmesi. | Şu an 999 kuruş çıkıyor. | **EVET (BLOCKER)** |
| **Karma Ödeme Kalıcılığı** | SQLite `sale_payments` tablosundan gün sonu nakit/kart toplamlarının sorgulanabilmesi. | Tablo yok, veri uçuyor. | **EVET (BLOCKER)** |
| **USB Fiş Yazdırma** | Windows USB yazıcıdan kâğıt kesmeli fiş çıktısı alınması. | Kod stub halinde. | **EVET (BLOCKER)** |
| **UI Entegrasyonu** | Kasiyerin satış ekranında `coreSalesFlowProvider` üzerinden satış yapabilmesi. | Henüz bağlı değil. | **EVET (BLOCKER)** |
| **Transaction Bütünlüğü** | Satış esnasında fiş kesilirken elektrik kesilirse stok ve kasanın tutarlı kalması. | Mimari hazır, UI testi gerek. | **EVET** |
| **Çevrimdışı Kuyruk** | İnternet yokken yapılan 500 satışın internet gelince VPS'e akması. | İstemci servisi yazılmadı. | **KOŞULLU** |
| **Yedekleme ve Geri Yükleme** | Canlı veritabanının zip yedeğinin alınıp yeni motorda açılabilmesi. | Test edildi, çalışıyor. | **HAYIR** |

---

## BÖLÜM 10: Hâlâ Doğrulanamayan Konular

Aşağıdaki hususlar bu denetim aşamasında fiziksel veya altyapısal sebeplerle nihai olarak doğrulanamamıştır:

1. **Fiziksel USB ESC/POS Yazıcı Çıktısı:**
   - Test ortamında fiziksel bir termal yazıcı takılı olmadığı için Türkçe CP857/UTF-8 karakter basımı ve donanımsal kâğıt kesme sinyalleri sadece kod analiziyle incelenebilmiş, fiziksel kâğıt üzerinde doğrulanamamıştır.
2. **Yüksek Eşzamanlı Satış Yükünde VPS PostgreSQL Performansı:**
   - 10 mağazanın aynı anda her biri saniyede 5 satış gönderdiği senaryoda `watermark_sync_service.ts` performans ve transaction kilitlenme durumu production VPS ortamında yük testine tabi tutulamamıştır.

---

## NİHAİ KARAR VE HÜKÜM

### Karar: **ONAYLANAMAZ (REJECTED)**

**Özet Gerekçe:**  
Core Next v2.0 altyapısı, önceki raporda iddia edildiği gibi üretime "Koşullu Hazır" DEĞİLDİR. Canlı veritabanındaki 3.320,00 TL'lik cari alacak silinmesi riski, negatif borç formatlama faciası, terazideki kuruş kaybı ve karma ödemelerin veritabanına yazılmaması işletme açısından kabul edilemez finansal ve operasyonel riskler barındırmaktadır. Bu 6 kritik engel kodlanıp test edilmeden sistem canlıya alınamaz.
