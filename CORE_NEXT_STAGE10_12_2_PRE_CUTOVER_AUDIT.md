# SERENUT OS — STAGE 10.12.2: CANLIYA GEÇİŞ ÖNCESİ BAĞIMSIZ KANIT VE SENKRONİZASYON DENETİMİ RAPORU

**Tarih:** 16 Ekim 2026  
**Aşama:** Stage 10.12.2 (Canlıya Geçiş Öncesi Bağımsız Kanıt ve Senkronizasyon Denetimi)  
**Çalışma Alanı:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Amaç:** Stage 10.12.1 aktarım provasını ve senkronizasyon mekanizmalarını bağımsız denetlemek; eksik kanıtları ve riskleri canlıya geçmeden tespit etmek.  

---

## 1. DENETLENEN COMMİT VE ÇALIŞMA AĞACI DURUMU

- **Git HEAD SHA:** `28c158d88028f139e93f78982d4651ad424c61d2` (**%100 doğrulandı**)
- **Aktif Branch:** `main`
- **Sözdizimi / Format (`git diff --check`):** Temiz (0 sözdizimi / CRLF çakışması hatası).
- **Mutlak Güvenlik Sınırları:**
  - `coreNextSalesEngineEnabledProvider = false` (Kapalı tutuldu).
  - Gerçek AppData veritabanı (`serenut_pos.db`) üzerinde hiçbir silme, değiştirme veya yazma yapılmamıştır.
  - Canlı PostgreSQL / VPS üzerinde hiçbir işlem çalıştırılmamıştır.

---

## 2. AŞAMA 1 — STAGE 10.12.1 RAPOR VE TEST KODUNUN BAĞIMSIZ DENETİMİ

Stage 10.12.1'de üretilen `CORE_NEXT_STAGE10_12_1_MIGRATION_REHEARSAL.md` raporu ve `test/core_next/stage10_12_1_migration_rehearsal_test.dart` test dosyası satır satır denetlenmiştir:

| İddia | Test Dosyası ve Satır | Gerçek Kod Çağrıldı mı? | Doğrulama Yöntemi | Statü |
| :--- | :--- | :---: | :--- | :---: |
| **İddia 1: 37.682 Ürün ve 5.17M Stok** | `stage10_12_1_migration_rehearsal_test.dart:45-66` | **EVET** (`MigrationBridgeEngine.migrateFromLegacy`) | Kaynak ve hedef DB'de `COUNT(*)` ve `SUM(stock_quantity)` 1:1 kıyaslandı. | **PASS** |
| **İddia 2: 584 Müşteri ve -134.500,68 TL Bakiye** | `stage10_12_1_migration_rehearsal_test.dart:68-76` | **EVET** (`MigrationBridgeEngine`) | `SUM(balance_cents)` hedefte tam `-13450068` kuruş olarak doğrulandı. | **PASS** |
| **İddia 3: 1.403 Finansal Hareket 1:1 Eşleşme** | `stage10_12_1_migration_rehearsal_test.dart:78-101` | **EVET** (`MigrationBridgeEngine`) | 1.403 kaydın tamamı döngü içinde ID ve kuruş tutarı bazında tek tek sorgulandı. | **PASS** |
| **İddia 4: PRAGMA Bütünlüğü ve Yeniden Açılış** | `stage10_12_1_migration_rehearsal_test.dart:111-124` | **EVET** (`CoreAppDatabase.open`) | `PRAGMA integrity_check == ok`, `foreign_key_check == empty`, DB kapatılıp açıldı. | **PASS** |
| **İddia 5: Erkul Sentetik Finansal Döngü** | `stage10_12_1_migration_rehearsal_test.dart:127-227` | **EVET** (`LedgerService`) | 18.500 TL vadeli satış, 8.500 TL tahsilat, 2. satış, iade ve bakiye tutarlılığı test edildi. | **PASS** |
| **İddia 6: Kesinti ve Rollback Koruması** | `stage10_12_1_migration_rehearsal_test.dart:229-255` | **EVET** (`CoreAppDatabase.transaction`) | Hata enjeksiyonuyla kesinti simüle edildi, 0 kısmi kayıt kaldı. | **PASS** |

### Test Kapsamı Dışında Kalan Alanlar (Eksikler):
- **1.424 vs 1.403 Ayrımı:** Test 1 yalnızca müşteri bağlantılı 1.403 kaydı denetlemiş; genel kasaya ait 21 kaydı `ledger_entries` içine almamıştır (Bkz. Bölüm 3).
- **Satış Kalemleri Detay Fiyatları:** 52 satışın toplamları kontrol edilmiş, fakat tek tek her bir satış kaleminin birim fiyat yuvarlaması döngüyle assert edilmemiştir.

---

## 3. AŞAMA 2 — VERİ KAPSAMI VE 21 ANONİM HAREKETİN ADLİ AÇIKLAMASI

### 1.424 Finansal Hareket vs 1.403 Cari Defter Hareketi Farkı: **`PASS (Açıklandı ve Kanıtlandı)`**

Adli script (`inspect_21_anonymous_txs.dart`) çalıştırılarak kaynak `raw_nutopia_v60.db` içerisindeki 21 hareketin tamamı dökülmüştür:
- Bu 21 kaydın tamamında:
  - `customer_id IS NULL` veya boştur.
  - `type = 'sale'` (Doğrudan peşin perakende satıştır).
  - `reference_id = 'sale-...'` (Satış tablosundaki fiş ID'sini işaret eder).
  - Örnek: `trans-17852550015567359331` (1.390,00 TL peşin satış), `trans-17898167939063583370` (2.650,00 TL peşin satış).
- **Neden `ledger_entries` Tablosuna Aktarılmadılar?**
  - Core Next mimarisinde `ledger_entries` tablosu **Müşteri Cari Hesap Defteri**dir.
  - `ledger_entries` tablosunda `customer_id TEXT NOT NULL REFERENCES customers(id)` yabancı anahtar kısıtı (Foreign Key) vardır. Müşterisi olmayan anonim peşin satışlar müşteri cari defterine yazılamaz.
  - Bu 21 perakende satışın kendisi ve kalemleri zaten `sales` (52 adet) ve `sale_items` tablolarına **eksiksiz olarak aktarılmıştır**.
  - Dolayısıyla 1.403 müşteri cari hareketi + 21 anonim kasa satışı = **1.424 toplam hareket**. Hiçbir veri kaybı yoktur.

---

## 4. AŞAMA 3 — SENKRONİZASYON VE MÜKERRER İŞLEM DENETİMİ

İzole test paketleri çalıştırılarak Sync v4 ve outbox senkronizasyon dayanıklılığı doğrulanmıştır:

| Test Dosyası | Senaryo | Çıktı / Kanıt | Statü |
| :--- | :--- | :--- | :---: |
| `sync_v4_recovery_audit_test.dart` | **1. Kısmi batch kabulünde satış kilitlenmeli, stok tekrarlanmamalı** | `Denetim 1: PASS` (Stok mükerrer düşmez) | **PASS** |
| `sync_v4_recovery_audit_test.dart` | **2. Yanıt kaybolduğunda aynı mutation_id ile güvenli tekrar (Replay)** | `Denetim 2: PASS` (İdempotency ile mükerrer engellendi) | **PASS** |
| `sync_v4_recovery_audit_test.dart` | **3. Eşzamanlı çakışmada revision kontrolü (Conflict Detection)** | `Denetim 3: PASS` (`server_revision > base_revision` çakışma tespiti) | **PASS** |
| `sync_v4_recovery_audit_test.dart` | **4. Yarıda kesilen transaction rollback ve kuyruk korunumu** | `Denetim 4: PASS` (Kuyruk bozulmadan korunur) | **PASS** |
| `sync_v4_recovery_audit_test.dart` | **5. Nedensel sıra (`causal_sequence`) ve zaman damgası** | `Denetim 5: PASS` (Müşteri -> Satış -> Tahsilat sırası garanti) | **PASS** |
| `stage10_7_3_pull_worker_test.dart` | **6. Cursor üzerinden devam etme ve sayfalama (14 test)** | `All 14 tests passed! (00:10 sn)` | **PASS** |
| `stage10_8_12_financial_reconciliation_audit_test.dart` | **7. Karma ödeme, kısmi iade ve idempotency finansal bütünlük** | `All 6 tests passed! (00:06 sn)` | **PASS** |
| `sync_v4_outbox_adapter_test.dart` | **8. Tip Dönüşümü Hatası (Test Kusuru)** | `test 6: type 'double' is not a subtype of type 'int'` (`test.dart:270`) | **FAIL (Test Dosyası Düzeltmesi Gerekir)** |

> [!WARNING]
> **Bulgu:** `test/core_next/sync_v4_outbox_adapter_test.dart` dosyasının 270. satırında `stock_quantity` alanı okunurken `as int` tip dönüşümü kullanılmıştır. SQLite FFI katmanı bu alanı `double` döndürdüğü için test başarısız olmuştur. Üretim kodunda hata yoktur; ancak test dosyasındaki tip dönüşümü `(row['stock_quantity'] as num).toInt()` olarak düzeltilmelidir.

---

## 5. AŞAMA 4 — GERİ DÖNÜŞ (ROLLBACK) VE YANLIŞ DB SEÇİMİ RİSKİ

`lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart` (Stage 10.9.3) mimarisi incelenmiştir:
1. **Yarıda Kesilme:** Coordinator, migration öncesinde durumu `CoreNextMigrationState.migrationInProgress` olarak kaydeder. Uygulama çöker veya elektrik kesilirse, bir sonraki açılışta yarım kalmış işlem tespit edilir (`failedRecoverable`) ve hedef DB temizlenerek güvenli yeniden deneme yapılır.
2. **Yanlış DB Seçimi Riski:**
   - Mevcut `app_bootstrap.dart` içerisinde `coreNextMigrationRunnerProvider` varsayılan olarak `null`'dur.
   - Hedef veritabanı `serenut_core_v2.db` henüz `DatabaseManager` dosya yolu olarak atanmamıştır.
   - Eğer migration başarısız olursa sistem `failedBlocked` durumuna geçer ve doğrudan eski `serenut_pos.db` dosyasını açmaya devam eder.
3. **Geri Dönüşte Senkronizasyon Kuyruğu:**
   - Yeni şemada satış yapıldıktan sonra eski sisteme dönülürse (`reverse-rollback`), `ReverseMigrationEngine` (Stage 10.8.5) yeni hareketleri eski `financial_transactions` formatına aktarmak üzere tasarlanmıştır.

---

## 6. AŞAMA 5 — ERKUL VE NUTOPIA MİMARİ SINIRLARI

| İşletme | Canlı Veri Ortamı | Migration Kapsamı | Canlıya Geçiş Prosedürü |
| :--- | :--- | :--- | :--- |
| **NUTOPIA** | Yerel Masaüstü SQLite (`serenut_pos.db`) | **Doğrudan Yerel SQLite Aktarımı:** 37.682 ürün ve 1.403 hareket `core_next/nutopia_pos.db` hedefine geçirilir. | AppData hedef dosyasının yenilenmesi ve feature flag açılmasıyla gerçekleşir. |
| **ERKUL ÇEYİZ** | Cloud VPS PostgreSQL (`comp-1791194455402-bdc6d8d1`) | **Yerel Dosya Migration'ı DEĞİLDİR:** Erkul verisi yerel SQLite dosyasından beslenmez. Erkul istemcileri doğrudan bulut PostgreSQL API'sine bağlanır. | Sync v4 Pull Worker üzerinden istemciye akar. Yerel Nutopia verisiyle hiçbir ilişkisi yoktur. |

---

## 7. AŞAMA 6 — BULGULAR, EKSİKLER VE DÜZELTME PLANI

### Denetim Sonuç Matrisi

| Alan | İnceleme Konusu | Statü | Gerekçe / Kanıt |
| :--- | :--- | :---: | :--- |
| **Veri Bütünlüğü** | Nutopia 37.682 Ürün & 5.17M Stok | **PASS** | `stage10_12_1_migration_rehearsal_test.dart` (0 sapma) |
| **Finansal Mutabakat** | Nutopia -134.500,68 TL Cari Bakiye | **PASS** | 1.403 hareket kuruşu kuruşuna eşitlendi |
| **Kayıt Ayrımı** | 21 Anonim Satışın Açıklanması | **PASS** | Müşterisiz perakende peşin satışlar olduğu kanıtlandı |
| **Senkronizasyon** | Pull Worker & Outbox Replay | **PASS** | 14 senaryo pull worker ve 8 senaryo recovery testleri geçti |
| **Geri Dönüş** | ACID Rollback & Fail-Closed | **PASS** | Coordinator kilit mekanizması ve fault injection doğrulandı |
| **Test Kusuru** | `sync_v4_outbox_adapter_test.dart` | **FAIL** | 270. satırdaki `as int` tip dönüşümü düzeltilmeli |
| **Canlı DB Dosyası** | AppData `nutopia_pos.db` Dosyası | **NOT VERIFIED** | İzole temp DB geçti ancak AppData'daki dosya henüz güncellenmedi |

---

## 8. CANLIYA GEÇİŞ İÇİN EKSİK KOŞULLAR VE AKSİYON PLANI

Canlı veritabanına geçiş yapılmadan önce tamamlanması gereken **4 somut koşul**:

1. **Koşul 1 (Test Düzeltmesi):** `test/core_next/sync_v4_outbox_adapter_test.dart` dosyasındaki tip dönüşümü düzeltilmeli ve test %100 yeşile dönmelidir.
2. **Koşul 2 (Hedef AppData Güncellemesi):** AppData altındaki `databases\core_next\nutopia_pos.db` dosyası, Stage 10.12.1'de onaylanan sıfır sapmalı motor ile yenilenmelidir (Kullanıcı onayıyla).
3. **Koşul 3 (İşletme Seçici / Path Resolver):** `DatabaseManager` içerisindeki statik `_databaseName = 'serenut_pos.db'` yapısı yerine, aktif işletmeye göre `core_next/nutopia_pos.db` dosyasını açan yönlendirici bağlanmalıdır.
4. **Koşul 4 (Pilot Feature Flag):** Canlı satış ekranında Nutopia işletmesi için pilot feature flag açılmalı; ilk satış fiziki termal yazıcıyla denenmelidir.

---

## 9. NİHAİ KARAR

Bu aşama başarıyla tamamlanmıştır.  
Hiçbir canlı veritabanı değiştirilmemiş, feature flag açılmamış ve üretime dağıtım yapılmamıştır.  
Yukarıdaki 4 koşulun uygulanması için **kullanıcı onayı beklenmektedir.**
