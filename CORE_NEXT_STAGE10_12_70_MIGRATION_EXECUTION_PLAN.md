# SERENUT OS — STAGE 10.12.70
# GEÇİŞ UYGULAMA PLANI VE KONTROLLÜ CUTOVER TASARIMI RAPORU

**Tarih:** 21 Ekim 2026  
**Aşama:** STAGE 10.12.70 — Test Döngüsünü Bitir, Geçiş Planı Çıkar  
**Hedef Rapor:** `CORE_NEXT_STAGE10_12_70_MIGRATION_EXECUTION_PLAN.md`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (`main` branch)  
**Nihai Karar:** `READY_FOR_CONTROLLED_CUTOVER_PLANNING` (Kontrollü Canlı Geçiş Planlamasına Hazır)  

---

## 1. MEVCUT DURUMUN KISA ÖZETİ

Bu aşamada test döngüleri ve tekrarlayan denetim süreçleri sonlandırılmıştır. Mevcut doğrulanmış kod tabanı, test sonuçları ve izole veritabanları temel alınarak üç işletmenin (Nutopia Fındık Değirmeni, Serenut ve Erkul Çeyiz) canlı sistemlerini veri kaybı yaşamadan Core Next SQLite mimarisine geçirecek **uçtan uca uygulanabilir geçiş planı** çıkarılmıştır.

### Görev 1 Sorularının Doğrulanmış Yanıtları:

1. **İzole hedef veritabanları mevcut ve kullanılabilir mi?**  
   **EVET.** `backups/stage64_isolated/` dizini altındaki 3 hedef veritabanı (`nutopia_core_next.db`, `serenut_core_next.db`, `erkul_core_next.db`) mevcuttur, SHA-256 bütünlükleri doğrulanmıştır ve temel aktarım (baseline) için eksiksiz olarak hazırdır.
2. **Hangi önemli finansal ve veri doğrulamaları zaten raporlandı?**  
   Üç işletmede toplam **1.985 finansal hareketin** tamamı satır satır (1-to-1) kuruşu kuruşuna doğrulanmıştır (Nutopia: 1.403 defter + 21 kasa; Serenut: 12 defter + 10 kasa; Erkul: 539 defter). Erkul Çeyiz'deki bakiye uyuşmazlığı çözülmüş; eski sistemin borcu değil yalnızca tahsilatları eksi bakiye olarak tuttuğu (%99 kuralı) ve gerçek net alacağın **3.787.125,00 TL** olduğu, 20 silinmiş müşterinin bakiyesinin ise **tam 0 kuruş** olduğu matematiksel olarak kanıtlanmıştır. Serenut Mancar tartılı ürün kuralı ve Nutopia 54 adet senet borcu (103.351,00 TL) doğrulanmıştır.
3. **Hangi gerçek engel hâlâ çözülmemiş?**  
   Teknik/mimari bir kod engeli kalmamıştır. Kalan engeller **operasyoneldir**:
   - Erkul Çeyiz yetkilisinden 3.787.125,00 TL açık senet portföyünün yazılı işletme teyidi.
   - 16 Ekim 2026 snapshot'ı ile geçiş anı arasında oluşan yeni canlı hareketlerin (delta) aktarımı için çalışma saatleri dışı (gece/hafta sonu) **bakım penceresinin (Downtime Window)** belirlenmesi.
4. **Bir sonraki adım için yeni test gerçekten gerekli mi, yoksa mevcut kanıt yeterli mi?**  
   **YENİ TEST GEREKLİ DEĞİLDİR.** Mevcut kanıtlar ve kod tabanındaki koordinatörler (`LiveSafeCatchUpReconciliationCoordinator`, `CutoffMaintenanceLock`, `ReverseMigrationEngine`) uygulanabilir bir geçiş için tamamen yeterlidir.

---

## 2. ZATEN TAMAMLANDIĞI RAPORLANAN İŞLER

| Varlık / Bileşen | Durum | Kanıt Kaynağı |
| :--- | :--- | :--- |
| **Nutopia 1.424 Finansal Hareket** | %100 Doğrulandı (0 Eksik, 0 Fark) | `Stage 68-69 Denetimi`, `stage10_12_68_...test.dart:L172-L211` |
| **Serenut 22 Finansal Hareket** | %100 Doğrulandı (0 Eksik, 0 Fark) | `Stage 68-69 Denetimi`, `stage10_12_68_...test.dart:L213-L252` |
| **Erkul 539 Finansal Hareket** | %100 Doğrulandı (0 Eksik, 0 Fark) | `Stage 68-69 Denetimi`, `stage10_12_68_...test.dart:L254-L278` |
| **Erkul Bakiye Semantiği** | Çözümlendi (`manual_debt - collection`) | `Stage 68-69 Denetimi`, 397/401 cari %99 ispatı |
| **Nutopia Senetli İşlemler** | 54 senet (103.351 TL) aktarıldı | `Stage 66 Denetimi`, `stage10_12_66_...test.dart` |
| **Serenut Mancar Ürün Sınıfı** | `sale_type=weighed` -> kg aktarımı | `Stage 67 Denetimi`, `migration_bridge_engine.dart:L441` |
| **Kiracı İzolasyonu** | 0 Çapraz Sızıntı | `Stage 67 Denetimi`, `app_settings` doğrulaması |
| **Veritabanı Motoru** | Şifresiz Standart SQLite | `AGENTS.md Kural 1`, `sqflite` FFI |
| **Sürümleme Standardı** | `+` Karakteri UI/Dosya Adından Kaldırıldı | `AGENTS.md Kural 2` |

---

## 3. GERÇEKTEN ÇÖZÜLMEMİŞ ENGELLER VE RİSKLER

Geçişin başarıyla sonuçlanması için aşılması gereken 3 somut engel:

1. **Engel 1 — Erkul Çeyiz İşletme / Muhasebe Teyidi:**  
   Eski Erkul yazılımı müşteri kartlarında borçları göstermeyip bakiye hanesine yalnızca `-tahsilat` yazdığı için, yeni Core Next ekranında 381 aktif müşterinin toplam **3.787.125,00 TL** borçlu çıkması Erkul personeli için ilk bakışta "yanlış bakiye" izlenimi yaratabilir. Bu nedenle dökümün işletme sahibine sunulup *"Sözleşmeli senetlerinizin kalan ana alacak toplamı 3.787.125 TL'dir, onaylıyor musunuz?"* teyidi alınmalıdır.
2. **Engel 2 — Canlı Delta Tazeliği (Freshness Catch-up):**  
   İzole hedefler 16 Ekim 2026 tarihli ham snapshot ile oluşturulmuştur. Canlı geçiş anında, aradan geçen günlerde yapılan satış ve ödemelerin `LiveSafeCatchUpReconciliationCoordinator` ile hedefe çekilmesi gerekir.
3. **Engel 3 — Geçiş Sırasında Eşzamanlı Yazma (Concurrency) Riski:**  
   Geçiş sürerken kasiyerlerin veya arka plan servislerinin eski veritabanına yazması durumunda veri kaybı veya çift kayıt oluşabilir. Bu risk, `CutoffMaintenanceLock` ile kesin olarak önlenmelidir.

---

## 4. ÜÇ İŞLETME İÇİN AYRI AYRI UYGULANABİLİR GEÇİŞ ADIMLARI

Geçiş süreci tek seferde tüm işletmeler yerine, **Risk Seviyesine Göre Aşamalı (Phased Pilot Cutover)** olarak yürütülecektir:

```
[Faz 1: SERENUT (Düşük Risk)]  ──▶  [Faz 2: NUTOPIA (Orta Risk)]  ──▶  [Faz 3: ERKUL ÇEYİZ (Yüksek Finansal)]
 (22 hareket, 6.377 ürün)           (1.424 hareket, 54 senet)            (539 hareket, 3.78M TL portföy)
```

### Her İşletme İçin 11 Standart Adım:

#### Adım 1: Kaynak Veritabanı ve İşletme Kimliği Doğrulaması
Canlı veritabanından `tenant_id` ve `business_name` okunarak hedef işletmenin doğruluğu teyit edilir. Yanlış veritabanı yolu kesinlikle engellenir.

#### Adım 2: Canlı Veriye Dokunmadan Tutarlı Yedek Alma (Zero-Mutation Backup)
Canlı SQLite bağlantısı üzerinden `VACUUM INTO '<backup_path>'` veya SQLite Online Backup API çalıştırılarak çalışan uygulamayı durdurmadan donmuş (point-in-time consistent) bir anlık yedek alınır.

#### Adım 3: Yedeğin SHA-256 ve SQLite Bütünlük Doğrulaması
Alınan yedek dosyasının bayt boyutu, SHA-256 özeti hesaplanır ve `PRAGMA integrity_check;` çalıştırılarak sonucun `ok` olduğu doğrulanır. Bozuk yedekle geçişe başlanmaz.

#### Adım 4: Doğrulanmış Temel Verinin Kullanımı (Baseline Target)
`backups/stage64_isolated/<tenant>/<tenant>_core_next.db` dosyası temel veritabanı olarak kopyalanır. 16 Ekim'e kadar olan veriler yeniden migrate edilmez; doğrulanmış durum doğrudan kullanılır.

#### Adım 5: İçe Aktarma Sonrası Temel Doğrulama
Temel hedefte ürün, müşteri, stok, satış, ödeme, vadeli hareket, senet ve sipariş kayıt sayılarının Stage 68-69 denetimindeki sayılarla tam eşleştiği teyit edilir.

#### Adım 6: Son Veri Farklarının Tespiti (Delta Catch-up)
16 Ekim snapshot zaman damgası (`lastMigrationCutoffTimestamp`) baz alınarak, bu tarihten sonra canlı veritabanında `created_at` veya `updated_at` damgası taşıyan tüm yeni/güncellenen satırlar tespit edilir.

#### Adım 7: İdempotent Fark Aktarımı ve Çift Kayıt Önleme
Tespit edilen delta kayıtları, `LiveSafeCatchUpReconciliationCoordinator.performCatchUpAndReconcile` fonksiyonu üzerinden tek bir transaction içinde hedefe aktarılır. `ON CONFLICT(id) DO UPDATE` ve tekil `idempotency_key` sayesinde aynı kayıt iki kez yazılmaz; stoklar mükerrer düşmez.

#### Adım 8: Son Fark Aktarımı Sırasında Yazma Kilidi (Cutoff Maintenance Lock)
Delta aktarımının son dakikalarında `CutoffMaintenanceLock.acquireLock()` devreye alınır:
- Kasiyer ekranında *"Sistem bakım ve veri güvenliği geçişi modunda"* afişi çıkarılır.
- Satış butonu ve yeni sipariş girişi kilitlenir.
- Devam eden arka plan yazmaları (draining) tamamlanana kadar beklenir.
- Canlı eski DB'ye yazma tamamen durduğunda son delta çekilir.

#### Adım 9: Kesin Geçiş Kapıları (Cutover Gates G1 - G7)
Hedef veritabanı aktif edilmeden önce 7 aşamalı kontrol kapısı çalıştırılır (Bkz. Bölüm 6).

#### Adım 10: Güvenli Geri Dönüş (Rollback) Hazırlığı
Herhangi bir kapı başarısız olursa tek tuşla/komutla eski sisteme dönüş yapılır; veri kaybı 0'dır (Bkz. Bölüm 7).

#### Adım 11: Eski Veritabanının Arşivlenmesi (Retirement Policy)
Başarılı geçişten sonra eski veritabanı silinmez; 90 gün boyunca salt-okunur yedek olarak saklanır (Bkz. Bölüm 8).

---

## 5. SON FARK AKTARIMI (DELTA CATCH-UP) VE ÇİFT KAYIT ÖNLEME YÖNTEMİ

Mevcut kod tabanında bu mekanizma zaten eksiksiz olarak mevcuttur:
- **Koordinatör:** [core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart)
- **Kilit Motoru:** [core_next/client_core/lib/infrastructure/migration/cutoff_maintenance_lock.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/cutoff_maintenance_lock.dart)

### İdempotency ve Tutarlılık Kuralları:

1. **Ürünler & Stoklar:**
   ```sql
   INSERT INTO products (...) VALUES (...)
   ON CONFLICT(id) DO UPDATE SET
     stock_quantity = excluded.stock_quantity,
     price_cents = excluded.price_cents,
     updated_at = excluded.updated_at
   WHERE excluded.updated_at >= products.updated_at;
   ```
   Monoton zaman damgası kontrolü sayesinde eski bir güncellemenin yeni stok verisini ezmesi engellenir.
2. **Cari Defter Hareketleri (`ledger_entries`):**
   ```sql
   INSERT OR IGNORE INTO ledger_entries (
     id, customer_id, reference_sale_id, entry_type, amount_cents, ...
   ) VALUES (?, ?, ?, ?, ?, ...);
   ```
   `id` alanı birincil anahtar (Primary Key) olduğundan, aynı hareket iki kez gelse bile `INSERT OR IGNORE` ile atlanır; mükerrer borç/tahsilat yazımı %100 engellenir.
3. **Satışlar ve Ödemeler:**
   `sales.idempotency_key = 'idem_$saleId'` ve `sale_payments.id` tekilliği ile korunur. Fiş durumu `CANCELLED` veya `REFUNDED` ise tamamlandıya geri dönemez.

---

## 6. KESİN GEÇİŞ KAPILARI (G1 - G7 CUTOVER GATES)

Core Next satış motoru ve veritabanı yönlendirmesi açılmadan önce şu 7 kapı ardışık olarak `%100 BAŞARILI` olmak zorundadır:

```
[G1: Yedek & SHA-256] ──▶ [G2: Yazma Kilidi] ──▶ [G3: Delta Catch-Up] ──▶ [G4: Bakiye Mutabakatı]
          │
          ▼
[G5: Foreign Key Bütünlüğü] ──▶ [G6: Kasiyer UI Onayı] ──▶ [G7: Routing & Motor Aktivasyonu]
```

- **G1 (Yedekleme Kapısı):** Canlı DB'nin kopyası alınmış, SHA-256 hesaplanmış ve `integrity_check = ok` olmalıdır.
- **G2 (Yazma Kilidi Kapısı):** `CutoffMaintenanceLock.phase == CutoffMaintenancePhase.locked` olmalı, aktif yazma sayısı 0'a inmiş olmalıdır.
- **G3 (Delta Aktarım Kapısı):** Son delta çalıştırmasında aktarılan ve atlanan kayıtlar raporlanmalı, hata listesi boş olmalıdır.
- **G4 (Finansal Mutabakat Kapısı):** Kaynak ile hedefin toplam satış cirosu (kuruş), toplam stok miktarı ve müşteri alacak bakiyeleri arasındaki fark tam `0` (sıfır) olmalıdır.
- **G5 (İlişkisel Bütünlük Kapısı):** `PRAGMA foreign_key_check;` sonucu 0 ihlal vermelidir.
- **G6 (Kullanıcı Salt-Okunur İnceleme Kapısı):** Kasiyer/işletme sahibi yeni arayüzde son fişleri ve müşteri bakiyelerini gözle onaylamalıdır.
- **G7 (Aktivasyon Kapısı):** Yalnızca G1-G6 tamamlandığında:
  - `DatabaseManager.databaseRoutingHook = coreNextRoutingHook`
  - `coreNextSalesEngineEnabledProvider = true`
  yapılarak geçiş tamamlanır.

---

## 7. GERİ DÖNÜŞ (ROLLBACK) YÖNTEMİ

Herhangi bir beklenmeyen durumda sistemin eski haline döndürülmesi 2 senaryoda güvenceye alınmıştır:

### Senaryo A: Aktivasyon Öncesi Geri Dönüş (Instant Abort)
G1 - G6 kapılarından herhangi biri başarısız olursa:
1. `CutoffMaintenanceLock.releaseLock()` çağrılır.
2. Bakım afişi kaldırılır.
3. Eski veritabanına hiçbir şey yazılmadığı için sistem 1 saniye içinde normal çalışmasına devam eder. Veri kaybı riski: **%0**.

### Senaryo B: Aktivasyon Sonrası Geri Dönüş (Reverse Rollback)
Yeni sistem devreye alındıktan sonra beklenmeyen bir çalışma hatası çıkarsa:
1. Satış motoru kapatılır (`coreNextSalesEngineEnabledProvider = false`).
2. Core Next devredeyken yapılan yeni satışlar ve cari hareketler, kod tabanında hazır ve test edilmiş olan **`ReverseMigrationEngine.rollbackToLegacy()`** ([migration_bridge_engine.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart)) motoru ile eski SQLite şemasına geri aktarılır.
3. Yönlendirme kancası sıfırlanır (`DatabaseManager.databaseRoutingHook = null`).
4. Eski uygulama sıfır veri kaybıyla çalışmaya devam eder.

---

## 8. ESKİ VERİTABANININ SAKLANMASI VE KULLANIMDAN KALDIRILMASI (RETIREMENT POLICY)

Eski veritabanı geçiş biter bitmez **KESİNLİKLE SİLİNMEZ**.

- **İlk 30 Gün (Canlı Salt-Okunur Dönem):** Eski veritabanı dosyası yerel diskte salt-okunur (`attrib +r`) olarak saklanır. Uygulama içerisinden "Geçmiş Arşiv İnceleme" moduyla görüntülenebilir, ancak yazma yapılamaz.
- **31 - 90 Gün (Soğuk Arşivleme):** Dosya AES-256 ile şifrelenip tarih mühürlü bir arşiv zip'ine (`legacy_archive_YYYYMMDD.zip`) dönüştürülür ve yerel yedek dizininde tutulur.
- **90+ Gün (Kullanımdan Kaldırma - Retirement):** Üç aylık ticari ve mali dönem kapandıktan sonra, işletme sahibinin yazılı onayıyla harici güvenli depolama birimine (NAS/harici disk) taşınır; yerel çalışma dizininden temizlenir.

---

## 9. GEÇİŞİN HANGİ KOŞULLARDA BAŞLATILABİLECEĞİ (GO / NO-GO CHECKLIST)

Canlı cutover butonuna basılabilmesi için gereken ön şartlar:

- [ ] **Erkul Onayı:** Erkul Çeyiz işletme sahibinin 3.787.125,00 TL'lik senet portföy dökümünü onaylamış olması.
- [ ] **Zamanlama:** İşletmenin kapalı olduğu bir zaman diliminde (örn. Pazar akşamı 22:00 - 02:00) 2 saatlik bakım penceresi açılması.
- [ ] **Yedek Alanı:** İstemci bilgisayarında en az 2 GB boş disk alanı bulunması.
- [ ] **İnternet/VPS:** Sunucu senkronizasyon kuyruğunun (`sync_outbox_v4`) geçiş öncesinde boşaltılmış (drained) olması.
- [ ] **Kullanıcı Bilgilendirmesi:** Kasiyerlere bakım süresince satış yapılmayacağının bildirilmesi.

---

## 10. NİHAİ KARAR

```text
================================================================================
AŞAMA KARARI: READY_FOR_CONTROLLED_CUTOVER_PLANNING
(KONTROLLÜ CANLI GEÇİŞ PLANLAMASINA HAZIR)

Açıklama:
Test döngüsü başarıyla tamamlanmıştır. Veri mutabakatı, bakiye semantiği,
idempotent delta catch-up motoru, yazma kilidi ve geri dönüş mekanizmaları
kod tabanında doğrulanmıştır. Kalan adımlar tamamen operasyonel planlama
ve bakım penceresi koordinasyonudur.
================================================================================
```

### Zorunlu Güvenlik Durumu (Mevcut Durum Koruması):

```text
CUTOVER: NOT APPROVED (Canlı geçiş henüz tetiklenmedi)
LIVE DATABASE WRITES: NOT PERFORMED (0 Canlı Yazma)
CORE NEXT SALES ENGINE: DISABLED (coreNextSalesEngineEnabledProvider = false)
DATABASE ROUTING HOOK: NULL (DatabaseManager.databaseRoutingHook = null)
OLD DATABASE RETIREMENT: NOT APPROVED
RELEASE: NOT PUBLISHED
```
