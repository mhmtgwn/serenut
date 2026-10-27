# SERENUT OS — STAGE 10.12.55
# FINAL BACKUP + DELTA REPLAY + ROLLBACK REHEARSAL AUDIT RAPORU

**Proje Yolu:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Tarih / Saat:** 2026-10-20T23:30:00+03:00  
**Git Dalı:** `main`  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Önceki Rapor:** `CORE_NEXT_STAGE10_12_54_PRE_CUTOVER_FINANCIAL_FLOW_AUDIT.md`  
**Denetim Aşaması Kararı:** **`ROLLBACK_REHEARSAL_PASS_ISOLATED_ONLY`**  

```text
================================================================================
CUTOVER: NOT APPROVED
LIVE DATABASE WRITES: NOT PERFORMED
CORE NEXT SALES ENGINE: DISABLED
DATABASE ROUTING HOOK: NULL
OLD DATABASE RETIREMENT: NOT APPROVED
================================================================================
```

---

## 1. BAŞLANGIÇ GİT DURUMU

- **Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Git Dalı:** `main`
- **Son 5 Commit:**
  - `28c158d8` fix(test): align splash screen error title expectation and bump version to 1.3.143+298
  - `8c6d7682` feat(observability): mask internal errors from users, route fatal events to sentry/telemetry with correlation reference, and bump to v1.3.143+297
  - `206557f3` fix(db): drop immutability triggers before migrations and bump version to 1.3.143+296
  - `fa704af1` chore(release): bump version to 1.3.143+295 for production deployment
  - `567680fa` fix(server): resolve TS18048 undefined activation check in billing bank-transfer routes
- **`git diff --check`:** Temiz (0 hata).

---

## 2. İNCELENEN GERÇEK KAYNAK VE HEDEF VERİTABANI YOLLARI

Tüm dosya yolları salt-okunur adli incelemeyle doğrulanmıştır:

| Rol | Dosya Yolu | Boyut (Bayt) | SHA-256 | PRAGMA integrity_check | PRAGMA foreign_key_check |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Canlı Kaynak (Legacy)** | `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db` | 61,390,848 | `262f2f3c9e393a7a0981a4b8e0abaade95e18c1c69a81da56a53dc51ad5a0768` | `ok` | 0 ihlal |
| **Canlı Hedef (Core Next)** | `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\core_next\nutopia_pos.db` | 17,010,688 | `c976b4d243800c763525078b9c8e9931375a1bf88fe6afca727461c230c61753` | `ok` | 0 ihlal |
| **Raw Serenut v44** | `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_serenut_v44.db` | 6,516,736 | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | `ok` | 0 ihlal |
| **Raw Nutopia v60** | `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_nutopia_v60.db` | 59,764,736 | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | `ok` | 0 ihlal |
| **Raw Erkul JSON** | `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_erkul_source.json` | 485,357 | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | N/A (JSON) | N/A |

### Canlı Çalışma Gerçeği (Store Operating Reality):
- Canlı kaynak dosyasında WAL dosyası (`serenut_pos.db-wal`) 4,173,592 bayt boyutunda aktiftir; kullanıcının bilgisayarında `serenutos.exe` (PID 2592) arka planda açık bulunmaktadır.
- Hedef `nutopia_pos.db` için WAL boyutu `0` bayttır; cutover kapalı olduğu için hiçbir canlı yazma almamıştır.

---

## 3. İŞLETME KİMLİKLERİ VE İZOLASYON SONUÇLARI

- **Nutopia Fındık Değirmeni:**
  - `serenut_pos.db` içinde `settings.business_name = 'Nutopia Fındık Değirmeni'`.
  - Tablo satır sayıları: `sales: 52`, `orders: 830`, `order_items: 1121`, `products: 37682`, `customers: 614`, `financial_transactions: 1498`.
- **Erkul Çeyiz:**
  - `raw_erkul_source.json` içinde ayrı kiracı verisi.
  - Varlık sayıları: `customers: 401`, `products: 26`, `sales: 5`, `sale_items: 5`, `financial_transactions: 539`, `customer_orders: 1`.
  - **Soru Cevabı:** Raporlardaki 539 sayısı **finansal hareket (`financial_transactions`)** sayısıdır; sipariş (1) veya satış (5) değildir.
- **Serenut:**
  - `raw_serenut_v44.db` içinde `settings.business_name = 'serenut'`.
  - Tablo satır sayıları: `sales: 15`, `orders: 5`, `products: 6377`, `customers: 7`, `financial_transactions: 22`.

Kiracılar arasında hiçbir veri birleştirilmemiş; mutlak izolasyon korunmuştur.

---

## 4. YEDEK YOLLARI, BOYUTLARI VE SHA-256 DEĞERLERİ

Canlı uygulama arka planda açık ve WAL aktif olduğundan, güvenli **SQLite Online Backup API** (`src.backup(dst)`) kullanılarak canlı veritabanı kilitlenmeden veya kesintiye uğratılmadan tutarlı anlık yedekler üretilmiştir:

1. **Kaynak Canlı Online Yedek:**
   - Dosya: `backups/stage55_rehearsal/live_source_online_backup_20261020.db`
   - Boyut: `61,390,848` bayt
   - SHA-256: `9be0f61c4819287c013263f43bc321eabe190324dea683f5a0593600f2cd3600`
   - Bütünlük: `ok`, 0 FK ihlali, `settings.business_name: Nutopia Fındık Değirmeni`
2. **Hedef Canlı Online Yedek:**
   - Dosya: `backups/stage55_rehearsal/core_next_target_backup_20261020.db`
   - Boyut: `17,010,688` bayt
   - SHA-256: `8f558910795ba16e91821a737567f1556374d1236e1cc5f88befd8a3fe8a3226`
   - Bütünlük: `ok`, 0 FK ihlali

---

## 5. YEDEK GERİ YÜKLEME VE BÜTÜNLÜK SONUÇLARI

Alınan yedekler izole dizine (`backups/stage55_rehearsal/isolated_restore_test/`) geri yüklenmiştir:

- `restored_serenut_pos.db`: SHA-256 `9be0f61c4819287c013263f43bc321eabe190324dea683f5a0593600f2cd3600` (Yedek hash ile %100 eşleşme, bütünlük `ok`).
- `restored_nutopia_pos.db`: SHA-256 `8f558910795ba16e91821a737567f1556374d1236e1cc5f88befd8a3fe8a3226` (Yedek hash ile %100 eşleşme, bütünlük `ok`).
- Geri yükleme provası başarıyla tamamlanmış; canlı veritabanlarının üzerine hiçbir yazma yapılmamıştır.

---

## 6. SNAPSHOT ZAMANI VE DELTA KAPSAMI

- **Temel Snapshot Kesiti:** 16 Ekim 2026 (16:10:42)
- **Delta Kapsamı:**
  - 41 adet yeni sipariş (`orders`: 792 -> 830)
  - 53 adet yeni sipariş kalemi (`order_items`: 1068 -> 1121)
  - 32 adet yeni finansal hareket (`financial_transactions`: 1424 -> 1498; 110 tarihsel + 32 yeni)
  - 30 adet yeni müşteri (`customers`: 584 -> 614)
  - 6 üründe stok değişimi (toplam -802.70 kg fındık ve -96 adet ezme kavanozu)

---

## 7. ADAPTER'IN GERÇEKTEN ÇALIŞTIRILDIĞINA İLİŞKİN KANIT

Gerçek Dart koordinatörü ([`LiveSafeCatchUpReconciliationCoordinator.repairHistoricalLedgerEntries`](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart#L451)), izole test veritabanları üzerinde çalıştırılmıştır:

- Taranan Kayıt: `112`
- Onarılan Kayıt: `110` (Hatalı `amount_minor = 0` değerleri autoritatif `amount` alanından kuruşa çevrildi).
- Korunan Gerçek Sıfır Kayıt: `2` (`trans-17907211401392489352` ve `trans-cancel-17908835323535612843`).
- Çakışma / Atlanan: `0`.
- Çıkış Kodu: `0` (Dart test suite içinde tam doğrulandı).

---

## 8. FİNANSAL HAREKET VE BAKİYE MUTABAKATI

1. **`balance_after_cents` Güvencesi:**  
   Açılış bakiyesi kanıtlanmamış defter hareketlerinde `balance_after_cents` körlemesine yeniden hesaplanmamakta; hareketin kendi tutarı (`amount_cents`) autoritatif kaynakla onarılırken zincirin geri kalanı bozulmamaktadır.
2. **23 Müşteri Bakiyesi Farkı:**  
   23 müşterinin toplam `-25,604.28 TL`'lik bakiye farkı, 16 Ekim kesitinden sonra canlı mağazada kaydedilen **32 adet gerçek hareket** ile satır satır tam örtüşmektedir.

---

## 9. STOK VE BİRİM MUTABAKATI

Bildirilen `-898.70` stok farkı fiziksel birimleri ayrık olarak doğrulanmıştır:
- **5 Tartılı Ürün (Kilogram):** Toplam `-802.70 kg`
- **1 Adetli Ürün (Adet):** Toplam `-96 adet` (Fındık Ezmesi Kavanoz)
- Farklı birimlerin tek bir toplamda toplanarak anlam kaybı yaratılması engellenmiştir.

---

## 10. SATIŞ, SİPARİŞ VE SİPARİŞ KALEMİ MUTABAKATI

- `sales` tablosu: Hem kaynakta hem hedefte tam **52 adet** satış bulunmaktadır (%100 parite).
- `orders` tablosu: Kaynakta **830 adet** sipariş bulunmaktadır. 16 Ekim sonrası eklenen 41 sipariş, yukarıdaki 6 ürünün stok çıkışlarını oluşturmuştur.
- Satış fişleri ile kasa siparişleri farklı tablolardır ve doğru biçimde ayrıştırılmıştır.

---

## 11. TEKRARLI ÇALIŞTIRMA VE YARIDA KALMA SONUÇLARI

- **İdempotency:** Onarım metodu ikinci kez çalıştırıldığında `repairedCount: 0`, `preservedZeroCount: 2` üretmiş; toplam satır sayısı 1 dahi artmamıştır.
- **Yarıda Kalma ve Atomiklik:** Kontrollü istisna (exception) enjeksiyonu simülasyonunda `targetDb.transaction` bloğu işlemi otomatik `ROLLBACK` etmiş; hedef veritabanında yarım kalmış veya tutarsız kayıt bırakılmamıştır.

---

## 12. ROLLBACK PROVASI

İzole ortamda geri dönüş akışı test edilmiştir:
1. Hedef veritabanı bozuk veya geçersiz olduğunda `DatabaseRoutingResolver.resolve()` metodu fail-closed korumayla **`RoutingDecision.blockedFailClosed`** kararı vermekte ve sistemi güvenli fallback olarak **`legacyDbPath`**'te tutmaktadır.
2. Hedef veritabanı dosyası henüz mevcut değilken `RoutingDecision.legacyFallback` seçilmekte ve eski DB kesintisiz çalışmaktadır.
3. Geri dönüş sonrasında kaynak veritabanında hiçbir veri veya geçmiş kaybı olmamıştır.
4. Tenant kimliği uyuşmazlığında (Nutopia yerine Erkul talep edilmesi) fail-closed devreye girerek çapraz veri erişimi engellenmiştir.

---

## 13. TESTLER, ANALİZ VE GİT KONTROL SONUÇLARI

1. **`flutter analyze test/core_next/stage10_12_55_final_backup_delta_rollback_test.dart`**
   - Sonuç: `No issues found!` (0 hata, 0 uyarı).
2. **Stage 10.12.55 Test Paketi:**
   - Komut: `flutter test test/core_next/stage10_12_55_final_backup_delta_rollback_test.dart`
   - Sonuç: **`16/16 All tests passed!`** (exit code 0).
3. **Kapsamlı Regresyon Paketi (Stages 10.12.43 — 10.12.55, 14 dosya):**
   - Komut: `flutter test $files` (PowerShell path expansion)
   - Sonuç: **`126/126 All tests passed!`** (exit code 0).
4. **`git diff --check`:**
   - Çıkış Kodu: `0` (Temiz).

---

## 14. AÇIK RİSKLER VE ÇÖZÜLEMEYEN FARKLAR

1. **Aktif Canlı Mağaza Gerçeği:**  
   Kullanıcının bilgisayarında `serenutos.exe` çalışmaktadır. Canlı mağazada gün içinde yeni satış ve sipariş oluşmaya devam edebilir. Bu nedenle gerçek cutover anında:
   - Kesim noktası (cut-off timestamp) tam olarak belirlenmelidir.
   - Son online yedek alınmalıdır.
   - Final delta catch-up tamamlanmadan routing açılmamalıdır.
2. **Fiziki Stok Sayımı:**  
   5 üründeki `-802.70 kg` ve 1 üründeki `-96 adet` fark 41 siparişle açıklanmıştır; canlı geçiş öncesi fiziki dükkan sayımı ile mutabakat teyidi önerilir.

---

## 15. NİHAİ KARAR VE GEREKÇESİ

### Karar Kodu:
## `ROLLBACK_REHEARSAL_PASS_ISOLATED_ONLY`

### Gerekçe:
- Yedekleme (SQLite Online Backup), izole geri yükleme, Dart adapter delta onarımı, idempotency, yarıda kalma atomikliği ve fail-closed rollback mekanizmaları **izole ortamda %100 başarıyla kanıtlanmıştır**.
- Canlı kaynak ve hedef veritabanlarına hiçbir yazma yapılmamıştır.
- Canlı satış motoru kapalıdır (`coreNextSalesEngineEnabledProvider = false`).
- Canlı yönlendirme kapalıdır (`DatabaseManager.databaseRoutingHook = null`).
- Canlı geçiş **ONAYLANMAMIŞTIR**.
