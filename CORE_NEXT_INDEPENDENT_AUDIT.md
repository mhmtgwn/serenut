# SERENUT OS CORE NEXT v2.0 — BAĞIMSIZ TEKNİK DOĞRULAMA VE GERÇEKLİK DENETİMİ RAPORU

**Denetim Tarihi:** 12 Ekim 2026  
**Denetçi Rolü:** Bağımsız Kıdemli Yazılım Denetçisi, Flutter/Dart Mimarı, Veri Bütünlüğü ve Finansal Mutabakat Uzmanı  
**Depo / Çalışma Dizini:** `c:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git Durumu:** Branch `main`, Son Commit `28c158d8 fix(test): align splash screen error title expectation and bump version to 1.3.143+298`  
**Nihai Üretime Hazırlık Kararı:** **KOŞULLU (CONDITIONAL)**

---

## 1. Yönetici Özeti

Bu denetim, Serenut OS Core Next v2.0 için öne sürülen mimari iddiaların, finansal mutabakat hesaplarının, SQLite şema kararlarının, Isolate donanım yapısının ve 20/20 test sonuçlarının **bağımsız, tarafsız ve tekrarlanabilir teknik kanıtlarla** doğrulanması amacıyla gerçekleştirilmiştir.

### Temel Sonuçlar:
1. **Çekirdek Motor ve Veri Mutabakatı Gerçekten Başarılı:**
   - 58.7 MB boyutundaki canlı üretim veritabanı (`serenut_pos.db`) üzerinde yapılan testte **37.682 ürün** ve **548 cari müşteri** başarıyla yeni kuruş şemasına aktarılmış; `balance_minor` ile `balance_cents` toplamı arasında **sıfır kuruş fark** (%100 matematiksel mutabakat) kanıtlanmıştır.
   - `test/core_next/` altındaki **20 test senaryosunun tamamı çalıştırılmış ve %100 yeşil (exit code 0)** ile geçmiştir.
2. **Kritik Gerçeklik Uçurumu (Unwired Prototype):**
   - İddia edilenin aksine, `core_next/` çekirdeği **mevcut uygulamanın UI ekranlarına (`lib/presentation/pages/sales_page.dart`), başlangıç akışına (`lib/main.dart`) ve mevcut controller'lara HENÜZ BAĞLANMAMIŞTIR**. `git status` incelemesinde `lib/` altında tek bir değişiklik veya `core_next` import'u bulunmamaktadır.
   - Dolayısıyla `core_next`, üretime geçirilmiş bir sistem değil; **bağımsız olarak tamamlanmış, test edilmiş, ancak henüz canlı arayüze entegre edilmemiş bir yeşil alan (greenfield) temelidir.**
3. **Mühendislik Kusurları:**
   - Tartılı ürünlerde terazi kuruş hesabında ticari yuvarlama yerine tamsayı bölme (`~/ 1000`) kullanıldığı için bazı gramajlarda 1 kuruş aşağı kırpma (truncation) riski saptanmıştır (AUDIT-002).
   - `MoneyCents.formatTL()` metodunda `-100 < value < 0` aralığında (örn. -50 kuruş) eksi işaretinin kaybolduğu saptanmıştır (AUDIT-005).
   - Donanım Isolate'inde USB ve Bluetooth yazdırma akışları kodlanmamış, stub (yorum satırı) olarak bırakılmıştır (AUDIT-003).
   - Yeni SQLite şemasında parçalı ödemelerin (nakit + kart kırılımı) kaydedileceği bir `sale_payments` tablosu eksiktir (AUDIT-004).

---

## 2. Denetimin Kapsamı ve Sınırları

- **İncelenen Dizinler:** `core_next/`, `test/core_next/`, `lib/` (özellikle `database_provider.dart`, `sales_page.dart`, `db_triggers.dart`), `.agents/AGENTS.md`.
- **Canlı Veritabanı Dosyası:** `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db` (Salt okunur erişimle incelendi; yazma/test işlemleri sistem geçici dizininde izole kopyada yürütüldü).
- **Sınırlar:** Fiziksel bir ESC/POS termal yazıcı veya COM port terazisi USB portuna bağlı olmadığından donanım testleri Isolate döngüsü ve bayt doğrulama seviyesinde sınırlandırılmıştır.

---

## 3. Git ve Çalışma Ortamının Başlangıç Durumu

- **Branch:** `main`
- **Son Commit:** `28c158d8 fix(test): align splash screen error title expectation and bump version to 1.3.143+298`
- **`git status --short` Çıktısı:**
  ```text
  ?? core_next/
  ?? test/core_next/
  ```
- **Bulgu:** `lib/` klasöründe hiçbir uncommitted değişiklik yoktur. `core_next/` ve `test/core_next/` henüz git index'ine eklenmemiş (untracked) dizinlerdir.

---

## 4. İddialar ve Doğrulama Durumları Tablosu

| İddia No | İddia Konusu | Denetim Durumu | Özet Kanıt |
| :---: | :--- | :---: | :--- |
| **C-01** | Core Next v2.0 mimarisi mevcut mu? | **DOĞRULANDI** | `core_next/` altında DDD katmanları (domain, infrastructure, presentation, sync, web_portal) mevcuttur. |
| **C-02** | Strangler Fig geçişi canlıda devrede mi? | **YANLIŞLANDI** | `lib/` içinde `core_next` import'u 0 adettir. Arayüz hâlâ 100% legacy kodla çalışmaktadır. Paralel modül aşamasındadır. |
| **C-03** | `MoneyCents` tamsayı kuruş bazlı mı? | **DOĞRULANDI** | `MoneyCents` sınıfı `final int value` tutar. Aritmetik operatörler tamsayı kuruş üretir. |
| **C-04** | SQLite trigger'ları kaldırıldı mı? | **KISMEN DOĞRULANDI** | `core_next` şemasında 0 trigger vardır. Ancak `lib/` legacy kodunda 8 adet trigger hâlâ mevcuttur. |
| **C-05** | Yeni şemada 11 tablo ve FK var mı? | **DOĞRULANDI** | `schema_definitions.dart` içinde tam 11 tablo ve 12 indeks tanımlıdır. `PRAGMA foreign_keys = ON;` aktiftir. |
| **C-06** | Donanım Isolate üzerinde mi çalışıyor? | **KISMEN DOĞRULANDI** | `HardwareWorker` gerçek `Isolate.spawn` kullanır. Ancak USB/BT kodları stub'dır; yalnızca TCP/IP soketi yazılmıştır. |
| **C-07** | Gerçek 58.7 MB veri ile mutabakat yapıldı mı? | **DOĞRULANDI** | 58.699.776 baytlık gerçek DB kopyasında 37.682 ürün ve 548 cari aktarılmış, kuruş farkı 0 çıkmıştır. |
| **C-08** | 20/20 test iddiası doğru mu? | **DOĞRULANDI** | `flutter test test/core_next/` komutu 20 testin tamamını 0 hata ile geçmiş, çıkış kodu 0 olmuştur. |
| **C-09** | PostgreSQL sync idempotent mi? | **KISMEN DOĞRULANDI** | Server `watermark_sync_service.ts` idempotenttir (`ON CONFLICT DO NOTHING`). Ancak client Dart sync client'ı henüz yazılmamıştır. |
| **C-10** | Sistem hemen canlıya alınabilir mi? | **YANLIŞLANDI** | UI entegrasyonu yapılmadığı ve USB yazıcı stub olduğu için doğrudan canlıya alınamaz. |

---

## 5. Bağımsız Mühendislik Bulguları (Audit Findings)

### AUDIT-001: Strangler Fig Canlı Entegrasyon Durumu (Unwired Core)
- **Alan:** Mimari & Entegrasyon
- **İddia:** Sistem Strangler Fig ile canlıya kademeli geçiş halindedir.
- **Durum:** **YANLIŞLANDI**
- **Kanıt:** 
  - `git grep "core_next" lib/` komutu: **0 sonuç**.
  - `lib/presentation/pages/sales_page.dart` satır 9-30 incelendiğinde hâlâ `sales_controller.dart`, `sales_flow_controller.dart` ve legacy repository'leri kullandığı görülmüştür.
- **Risk:** Yazılan `core_next` kodları tek başına harika çalışsa da, kasiyerlerin kullandığı mevcut POS arayüzüne hiçbir etkisi yoktur.
- **Öneri:** `sales_page.dart` ve `main.dart` dosyalarına Feature Flag veya Adapter eklenerek `coreSalesFlowProvider`'a bağlanmalıdır.

---

### AUDIT-002: Tartılı Ürün Satırında Kuruş Kırpma (Truncation vs Half-Up Rounding)
- **Alan:** Finansal Hesaplama
- **İddia:** Tartılı terazi hesaplarında sıfır kuruş kaybı vardır.
- **Durum:** **KISMEN DOĞRULANDI**
- **Kanıt:** `core_next/client_core/lib/presentation/sales/core_sales_flow_state.dart` satır 25:
  ```dart
  final rawCents = (unitPrice.value * quantity) ~/ 1000;
  ```
  `~/ 1000` operatörü Dart'ta tamsayı bölme (truncation / aşağı yuvarlama) yapar. Örneğin kilogramı 33,33 TL (3333 kuruş) olan bir üründen 300 gram satıldığında: `(3333 * 300) = 999.900`. `999.900 ~/ 1000 = 999 kuruş` (9,99 TL) hesaplanır. Gerçek ticari yuvarlamada 999,9 kuruş -> 1000 kuruş (10,00 TL) olmalıdır. 1 kuruşluk eksik hesaplama riski vardır.
- **Risk:** Perakende terazili satışlarda kümülatif kuruş zararı.
- **Öneri:** `((unitPrice.value * quantity) / 1000).round()` veya `((unitPrice.value * quantity + 500) ~/ 1000)` ticari yuvarlama formülü kullanılmalıdır.

---

### AUDIT-003: Donanım Isolate'inde USB/Bluetooth Stub Durumu ve Kalıcı Kuyruk Eksikliği
- **Alan:** Donanım ve Yazıcı Güvenilirliği
- **İddia:** Donanım katmanı tamamlanmıştır.
- **Durum:** **KISMEN DOĞRULANDI**
- **Kanıt:** `core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart` satır 138-155:
  `_dispatchBytes` metodu yalnızca `PrinterTransportType.tcpIp` (Ethernet/Ağ) soket bağlantısını implemente etmiştir. USB ve Bluetooth taşımaları için kod yazılmamış, yorum satırı olarak bırakılmıştır. Ayrıca `printReceipt` komutları Isolate `SendPort` üzerinden in-memory iletilmektedir; SQLite tabanlı kalıcı bir `print_spooler` tablosu yoktur.
- **Risk:** Kasadaki USB yazıcılar bu kodla çalışamaz. Yazdırma sırasında elektrik kesilirse iş kaybolur.
- **Öneri:** USB/Serial port taşımaları platform kanalıyla bağlanmalı ve yazdırma kuyruğu `sync_events` veya `print_spooler` tablosuna kaydedilmelidir.

---

### AUDIT-004: Yeni Şemada Parçalı Ödeme (Payment Splits) Tablosunun Bulunmaması
- **Alan:** Veritabanı Bütünlüğü & Muhasebe
- **İddia:** Parçalı (karma) ödemeler veritabanında saklanmaktadır.
- **Durum:** **KISMEN DOĞRULANDI**
- **Kanıt:** `core_next/client_core/lib/infrastructure/database/schema_definitions.dart` incelendiğinde 11 tablo arasında bir `sale_payments` tablosu bulunmamaktadır. `sales` tablosunda yalnızca kümülatif `paid_cents` ve `debt_cents` sütunları vardır. `SaleOrderEntity` içindeki `List<PaymentSplitEntity> payments` listesi veritabanına yazılmamakta, sadece bellek içinde kalmaktadır.
- **Risk:** Kasiyer 50 TL nakit, 50 TL kredi kartı aldığında, gün sonu kasa raporunda nakit ve kart kırılımı SQLite üzerinden sorgulanamaz.
- **Öneri:** Şemaya `sale_payments (id, sale_id, payment_type, amount_cents, reference_note)` tablosu eklenmeli ve `checkout_use_case.dart` içinde kaydedilmelidir.

---

### AUDIT-005: `MoneyCents.formatTL()` Metodunda Negatif Kuruş İşareti Kaybı
- **Alan:** Finansal Formatlama
- **İddia:** Kuruş değerleri TL formatına hatasız dönüştürülür.
- **Durum:** **KISMEN DOĞRULANDI**
- **Kanıt:** `core_next/client_core/lib/domain/models/money_cents.dart` satır 27-31:
  ```dart
  String formatTL() {
    final liraPart = value ~/ 100;
    final kurusPart = (value % 100).abs().toString().padLeft(2, '0');
    return '$liraPart,$kurusPart ₺';
  }
  ```
  Değer `-50` kuruş (-0,50 TL) olduğunda: `-50 ~/ 100 = 0` olur. Sonuç: `"0,50 ₺"` basılır; eksi işareti kaybolur.
- **Risk:** Bakiye -0,01 TL ile -0,99 TL arasında borçlu olan müşteriler ekranda alacaklı veya sıfır gibi görünebilir.
- **Öneri:** `if (value < 0 && value > -100) return '-0,$kurusPart ₺';` kontrolü eklenmelidir.

---

### AUDIT-006: İstemci Tarafında Bulut Senkronizasyon İletişim Eksikliği
- **Alan:** Bulut Senkronizasyonu
- **İddia:** Bulut senkronizasyonu hazırdır.
- **Durum:** **KISMEN DOĞRULANDI**
- **Kanıt:** Sunucu tarafında `core_next/server_core/src/sync/watermark_sync_service.ts` yazılmıştır. Ancak `client_core` içinde bu servise HTTP/REST ile bağlanan bir senkronizasyon yöneticisi (`sync_client.dart`) bulunmamaktadır. `sync_events` tablosu şemada mevcuttur ancak istemci tarafından sunucuya gönderilmemektedir.
- **Risk:** VPS sunucusu ile istemci arasında otomatik veri akışı bu haliyle çalışamaz.
- **Öneri:** `client_core` içine `sync_events` tablosunu okuyup `processPush` endpoint'ine gönderen bir `WatermarkSyncClient` eklenmelidir.

---

## 6. Gerçek Veri Mutabakat Kanıtları (Forensic Evidence)

Canlı üretim ortamındaki dosyanın bağımsız adli inceleme verileri:

- **Dosya Yolu:** `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db`
- **Dosya Boyutu:** **58.699.776 bayt (58.70 MB)**
- **SHA-256 Özeti:** `28A1F5FDCD77B318956C042AF7B68B3D16F4DCB4FEE479365856B9ED8E58C9AE`
- **SQLite Başlık user_version Değeri:** `60` (Legacy DatabaseManager sürümüyle tam uyuşuyor)
- **Mevcut Tablo Sayısı:** 44 tablo

### Mutabakat Sonuçları:
```text
Kaynak Ürün Sayısı:           37.682 adet
Aktarılan Ürün Sayısı:        37.682 adet (%100)
Kaynak Müşteri Sayısı:        548 kişi
Aktarılan Müşteri Sayısı:     548 kişi (%100)
Eski DB SUM(balance_minor):   -13.217.068 kuruş
Yeni Core DB SUM(balance_cents): -13.217.068 kuruş (-132.170,68 ₺)
Matematiksel Kuruş Farkı:     0 Kuruş (%100 Mutabakat)
```

*Not:* Eski veritabanındaki `balance` (`double`) sütunu toplamı `-135.490,68 TL` idi. Yapılan incelemede eski sistemin Migration 59 öncesi kayan nokta hataları yüzünden `balance` ile `balance_minor` arasında 3.320,00 TL'lik geçmiş düzeltilmemiş kayıt farkı olduğu saptandı. `MigrationBridgeEngine` doğru bir kararla `balance_minor`'ı baz alarak tam mutabakat sağlamıştır.

---

## 7. Test Sonuçları ve Tekrarlanabilirlik

Aşağıdaki komut bağımsız denetçi ortamında çalıştırılmış ve çıktısı kaydedilmiştir:

```bash
flutter test test/core_next/ --reporter expanded
```

- **Toplam Bulunan Test:** 20
- **Çalıştırılan Test:** 20
- **Başarılı Test:** 20
- **Başarısız Test:** 0
- **Atlanan Test:** 0
- **Çıkış Kodu (Exit Code):** 0
- **Toplam Süre:** ~38.9 saniye (58.7 MB gerçek DB kopyalanması ve 37.682 ürün aktarımı dahil)

```text
[PASS] checkout_use_case_test.dart (4 senaryo)
[PASS] database_integration_test.dart (3 senaryo)
[PASS] hardware_worker_test.dart (3 senaryo)
[PASS] ledger_service_test.dart (6 senaryo)
[PASS] migration_bridge_test.dart (1 senaryo)
[PASS] real_data_verification_test.dart (3 senaryo)
```

---

## 8. Üretime Çıkış Kararı ve Öncelikli Yol Haritası

### NİHAİ KARAR: **KOŞULLU (CONDITIONAL)**

Sistem, **"Veri Tabanı Şeması, Kuruş Hesaplama Motoru ve Gerçek Veri Migrasyonu"** açısından rüştünü ispat etmiş, hatasız ve sağlamdır. Ancak **aşağıdaki 4 engelleyici madde giderilmeden üretim ortamına ("Canlıya Geçtik") denilemez**:

| Öncelik | Engelleyici Madde | Açıklama |
| :---: | :--- | :--- |
| **P0** | **UI Adapter & Wiring** | `lib/presentation/pages/sales_page.dart` yeni `coreSalesFlowProvider`'a bağlanmalı; kasiyer satışı bu motor üzerinden yapmalıdır. |
| **P1** | **Parçalı Ödeme Tablosu** | `schema_definitions.dart` içine `sale_payments` tablosu eklenmeli ve transaction içinde kaydedilmelidir. |
| **P2** | **Fiziksel USB Yazıcı** | `HardwareWorker._dispatchBytes` içine Windows/Android USB ve COM port yazıcı entegrasyonu eklenmelidir. |
| **P3** | **Format ve Terazi Düzeltmesi** | `MoneyCents.formatTL()` negatif sıfır hatası (AUDIT-005) ve `CoreCartItem.lineTotal` terazi yuvarlaması (AUDIT-002) düzeltilmelidir. |

Bu 4 madde tamamlandığında Serenut OS Core Next v2.0, %100 güvenle canlı üretime açılabilir.
