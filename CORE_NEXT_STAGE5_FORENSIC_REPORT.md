# SERENUT OS — STAGE 5: BAĞIMSIZ ADLİ DENETİM VE HATA ENJEKSİYONU RAPORU

**Belge Adı:** `CORE_NEXT_STAGE5_FORENSIC_REPORT.md`  
**Denetim Seviyesi:** 5. Aşama Derinlemesine Adli İnceleme, Hata Enjeksiyonu ve Veri Bütünlüğü Doğrulaması  
**Tarih:** 13 Ekim 2026  
**Denetim Rolü:** Bağımsız Kıdemli Sistem Mimarı ve Finansal Adli Bilişim Uzmanı  
**Proje Kök Dizini:** `c:\Users\notop\AndroidStudioProjects\shaman_new`  
**Yayın ve Dağıtım Kararı:** **KESİNLİKLE YAYINLANAMAZ (BLOCKED / ONAYLANAMAZ)**

---

## 1. Git ve Çalışma Ağacı Bütünlüğü Denetimi

### 1.1. İzleme ve İndeks Durumu
- **Çalıştırılan Komut:** `git status --short; git diff HEAD`
- **HEAD Commit:** `28c158d8 fix(test): align splash screen error title expectation and bump version to 1.3.143+298` (origin/main ile eşit)
- **`git diff HEAD` Çıktısı:** **0 satır (TAMAMEN BOŞ)**.
- **Canlı Kod (`lib/`) Güvencesi:** Üretim dizinindeki tek bir dosya dahi değiştirilmemiştir.
- **Commit Durumu:** **Kesinlikle YENİ COMMİT ATILMAMIŞTIR**.

### 1.2. Untracked Dosyaların Denetimi
`git status --short` çıktısındaki untracked dizinler (`core_next/` ve `test/core_next/`) sürüm kontrolünde değildir ve izole prototip katmanında tutulmaktadır:
- `core_next/` dizininde 26 adet dosya (Entity modelleri, Use Case, SQLite şemaları, Hardware Worker, TypeScript senkronizasyon ve Web portal).
- `test/core_next/` dizininde 7 adet bağımsız test dosyası (toplam 26 test senaryosu).

---

## 2. Bağımsız Finansal Doğruluk: 548 Müşterinin Kuruş Kuruş Mutabakatı

### 2.1. Görünümden Bağımsız Ham Hesaplama (Dairesel Doğrulama Engeli)
`v_customer_ledger_effect` VIEW'ına güvenmekle yetinilmeyip, doğrudan ham `financial_transactions` tablosu üzerinde `scratch/stage5_financial_forensic.py` betiği ile bağımsız tahlil yapılmıştır:

$$\text{Balance} = \sum \left( \text{Tahsilat} + \text{İptal} + \text{İade} \right) - \sum \left( \text{Satış Borcu} + \text{Manuel Borç} \right)$$

- **Değerlendirilen Müşteri Sayısı:** 548 / 548
- **Ham Defter ile `customers.balance` Arasında Uyuşmazlık Gösteren Müşteri Sayısı:** **TAM 0 (SIFIR)**.
- **Hüküm:** 548 müşterinin tamamında kayıtlı bakiye, geçmişteki 1.314 finansal hareketin net toplamı ile kuruşu kuruşuna örtüşmektedir.

---

### 2.2. 3.320,00 TL Farkın ve 3.200 TL Tahsilatın Adli İncelemesi

> **Soru:** 3.200 TL tahsilat defterde bir kez mi, iki kez mi temsil edilmiştir?

Adli veritabanı sorgusu ve tetikleyici günlüğü (`trigger_audit_logs`) sonuçları:

1. **`financial_transactions` Tablosu Gerçeği:**
   - 3.200 TL'lik tahsilat defterde **YALNIZCA BİR KEZ** kayıtlıdır:  
     `trans-col-e9a384dc-74db-4ade-b14b-22febc61f102` (Taksit Peşinatı, 3.200,00 TL, 2026-10-10 22:13:18).
2. **Tetikleyici Geçmişi (`trigger_audit_logs` Log #1268 ve #1269):**
   - 10.10.2026 tarihinde taksit planı girilirken, eski sistem `manual_debt` satırına toplam tutar (10.000 TL) yerine peşinat düşülmüş vadeli tutarı (`debt_amount = 6800.00`) yazmıştır.
   - Tetikleyici `trg_ft_insert` önce bu 6.800 TL'yi borç olarak düşmüştür (`Before: 0.00 -> After: -6800.00`).
   - Hemen ardından gelen 3.200 TL'lik peşinat tahsilatını da artı olarak eklemiştir (`Before: -6800.00 -> After: -3600.00`).  
     **Böylece 3.200 TL peşinat bakiye seviyesinde 2 KEZ düşülmüş ve borç 3.200 TL eksik kaydedilmiştir.**
3. **Migration 59 Düzeltmesi:**
   - Migration 59 (`db_migrations.dart:1148`), `financial_transactions` tablosundaki bu hatayı fark edip `debt_amount`'u 6.800'den 10.000 TL'ye düzeltmiştir.
4. **Migration 60 ve Bayat Bakiye:**
   - Migration 60, defter henüz uzlaştırılmadan önce `customers.balance` sütunundaki o anki hatalı değeri `balance_minor = 93332` (+933,32 TL) olarak kaydetmiştir.
   - Daha sonra `_reconcileAllCustomerBalances()` defter hareketlerini yeniden toplayarak `customers.balance` alanını gerçek borç olan **`-2.266,68 TL`** seviyesine düzeltmiş; fakat `balance_minor`'ı güncellemeyi unutmuştur!

**Özet Tablo:**
| Müşteri | Defterdeki Gerçek Borç | `balance_minor` Değeri | Durum |
| :--- | :---: | :---: | :--- |
| **ŞEN*** (`48c82bec-...`) | **-2.266,68 ₺** | +933,32 ₺ | 3.200,00 TL haksız alacak yazılmıştı (Düzeltildi). |
| **TUĞ*** (`cust-178833...`) | **-120,00 ₺** | 0,00 ₺ | 120,00 TL borç silinmişti (Düzeltildi). |
| **TOPLAM İŞLETME ALACAĞI** | **-135.490,68 ₺** | **-132.170,68 ₺** | **3.320,00 ₺ kurtarıldı.** |

---

## 3. Migrasyon Hata Enjeksiyonu ve Atomik Rollback Doğrulaması

Yeni yazılan `test/core_next/fault_injection_migration_test.dart` test paketi ile migrasyon akışına kasıtlı hata enjekte edilmiş ve şu davranışlar test edilmiştir:

### 3.1. Senaryo 1: Cari Aşamasında Beklenmeyen Sapma Enjeksiyonu
- **Uygulama:** Ürünler başarıyla eklendikten sonra, bir müşterinin kayıtlı bakiyesi ile defter hareketleri arasına kasıtlı olarak 899 TL sapma yerleştirildi.
- **Gözlenen Sonuç:**
  - `migration_bridge_engine.dart` sapmayı tespit ederek `StateError` fırlattı ve işlemi durdurdu.
  - `report.isSuccess` değeri `false` döndü.
  - `isMigrationCompleted()` değeri `false` kaldı.
- **Rollback Kanıtı:** İlk adımda `txn.batch()` ile yazılmış olan 5 ürün ve tüm tablolar **TAMAMEN GERİ ALINDI (ROLLBACK)**. Hedef veritabanındaki `products`, `customers` ve `sales` tablolarında **0 kayıt** kaldı.

### 3.2. Senaryo 2: Hata Sonrası Yeniden Başlatma (Resumption)
- **Uygulama:** Hatalı defter verisi düzeltildikten sonra aynı hedef veritabanında migrasyon tekrar çalıştırıldı.
- **Gözlenen Sonuç:** Sıfır hata ile tamamlandı (5 ürün, 3 müşteri, 2 satış).
- **İdempotency Kanıtı:** Üçüncü kez çalıştırıldığında tablolar mükerrer kayıt üretmedi ve bakiye değişmedi.

---

## 4. Gerçek Veri Koruması ve SHA-256 Değişiminin Adli Teşhisi

> **Kritik Gözlem:** Testler sonrasında `serenut_pos.db` dosyasının SHA-256 değerinin değiştiği fark edilmiştir. Bunun nedeni adli olarak soruşturulmuştur:

1. **Test Kodunun Bağlantı Modu:**
   - [real_data_verification_test.dart:60](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/real_data_verification_test.dart#L60):  
     `openDatabase(sandboxLegacyDbPath, readOnly: true)`
   - Testler canlı dosyayı değil, işletim sisteminin geçici sandbox dizinindeki kopyayı açmaktadır. Testlerin canlı DB'ye yazması **imkânsızdır**.
2. **Canlı Dosyadaki Değişimin Gerçek Sebebi:**
   - Görev yöneticisinde çalışan `serenutos` uygulamasının (**PID 6240**) her 15-30 saniyede bir arka planda `SyncNotifier.triggerSync` çalıştırdığı tespit edilmiştir.
   - `client_telemetry_logs` tablosu sorgulandığında, arka plandaki uygulamanın saat `00:37:46`'da kendi telemetri günlüğüne operasyonel kayıt attığı kanıtlanmıştır.
   - `customers`, `products` ve `financial_transactions` tabloları incelenmiş, canlı ticari verilerin **tamamen el değmemiş olduğu** (`548 cari, -135.490,68 TL`) teyit edilmiştir.

---

## 5. Test Kapsamı ve Kalan Eksiklikler Matrisi

Mevcut test paketi **26 senaryoya** çıkarılmıştır:

| Test Dosyası | Senaryo Sayısı | Kapsanan Alan |
| :--- | :---: | :--- |
| `database_integration_test.dart` | 3 | Tablolar, indeksler, barkod arama, trigger'sız defter |
| `hardware_worker_test.dart` | 3 | ESC/POS fiş baytları, TSPL etiket komutları, Isolate yönetimi |
| `ledger_service_test.dart` | 7 | TL/Kuruş dönüşümü, KDV yuvarlama, `formatTL` (-101 ile +101 kuruş), vadeli satış, tahsilat |
| `checkout_use_case_test.dart` | 5 | Nakit satış, 450g tartı, terazi sınır testleri (1g - 1000g), indirimli tartı, veresiye kuralları |
| `migration_bridge_test.dart` | 3 | Kuruşa dönüşüm, bayat `balance_minor` yakalama, defter sapmasında durdurma |
| `fault_injection_migration_test.dart` | 2 | **Kasıtlı hata enjeksiyonu, atomik rollback ve yeniden başlatma (Resumption)** |
| `real_data_verification_test.dart` | 3 | 37.682 ürünlük canlı kopya taraması, kuruşu kuruşuna mutabakat, canlı satış simülasyonu |
| **TOPLAM** | **26 Test** | **%100 Başarılı (Exit Code: 0)** |

### ⚠️ Üretime Çıkış Öncesi Hâlâ Doğrulanmamış Konular:
1. **Fiziksel USB Yazıcı:** ESC/POS baytları hazırdır; ancak fiziksel Windows USB termal yazıcı donanımı porta takılı değildir.
2. **Karma Ödeme Kalıcılığı:** SQLite şemasında `sale_payments` tablosu henüz açılmamıştır.
3. **Canlı UI Entegrasyonu:** `sales_page.dart` henüz yeni motora bağlanmamıştır.
4. **Çevrimdışı Bulut Senkronizasyonu:** İstemci tarafı watermark upload worker'ı henüz yazılmamıştır.

---

## NİHAİ YAYIN ÖNCESİ KARAR

### Karar: **YAYIN VE DAĞITIM KESİNLİKLE ENGELLENMİŞTİR (BLOCKED / ONAYLANAMAZ)**

- Git commit'i ATILMAMIŞTIR.
- Canlı SQLite veritabanında migrasyon ÇALIŞTIRILMAMIŞTIR.
- Yeni satış motoru canlı UI ekranına BAĞLANMAMIŞTIR.
- Kalan 4 altyapı maddesi (USB sürücü, karma ödeme tablosu, UI feature flag ve bulut uploader) tamamlanana kadar sistem izole geliştirme ve denetim modunda tutulmaya devam edecektir.
