# CORE NEXT — STAGE 10.12.49
## Kontrollü Gölge Gözlem Başlangıcı ve Pilot Güvenlik Kapısı Denetim Raporu

**Tarih:** 2026-10-20  
**Proje Yolu:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git Dalı:** `main`  
**Git HEAD (Başlangıç ve Bitiş):** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Önceki Aşama:** Stage 10.12.48 — Shadow Observation Readiness Audit  
**Pilot Gözlem Kararı:** `PILOT_OBSERVATION_BLOCKED` (Preflight Güvenlik Kapısı Devrede)  
**Cutover Durumu:** `NOT_APPROVED`  
*(Not: Değişmez kurallar ve preflight kiracı kimlik denetimi uyarınca canlı gölge gözlemi bu terminalde BAŞLATILMAMIŞTIR. Canlı cutover kesinlikle yasaktır ve onaylanmamıştır.)*

---

## 1. Değişmez Güvenlik Kuralları ve Canlı Durum Teyidi

Canlı işletmelerimiz (**Nutopia**, **Serenut** ve **Erkul Çeyiz**) günlük operasyonlarına ve ticari işlemlerine kesintisiz devam etmektedir. Bu işletmelerin gerçek ticari verilerinin korunması amacıyla aşağıdaki değişmez kuralların durumu doğrulanmıştır:

| Güvenlik Kuralı | Beklenen Durum | Gerçek Durum | Kod Konumu / Doğrulama |
| :--- | :--- | :--- | :--- |
| **Canlı Satış Motoru Flag'i** | `coreNextSalesEngineEnabledProvider = false` | `false` | [sales_controller.dart:L104](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L104) |
| **Veritabanı Yönlendirme Kancası** | `DatabaseManager.databaseRoutingHook = null` | `null` | [database_provider.dart:L48](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/infrastructure/database/database_provider.dart#L48) |
| **Tek Yetkili Veri Kaynağı (SSoT)** | Eski Veritabanı (`serenut_pos.db`) | Eski Veritabanı | Canlı okuma ve yazma yalnızca eski veritabanı üzerinden yürütülmektedir |
| **Canlı DB Üzerinde Test / Migration**| Kesinlikle Yapılmayacak | Yapılmadı | Canlı veritabanına test yazımı, migration veya deneme yapılmamıştır |
| **Nutopia ve Erkul Veri Koruması** | Gözlem / Değişiklik Yapılmayacak | Dokunulmadı | Nutopia ve Erkul canlı kayıtları tamamen izole tutuldu |
| **Otomatik Cutover Durumu** | Yapılmayacak | Yapılmadı | Canlı cutover veya routing tetiklenmemiştir |
| **Git / Kullanıcı Ağacı Korunumu** | Sıfırlama / Clean Yapılmayacak | Korundu | Çalışma ağacındaki tüm kullanıcı değişiklikleri korunmuştur |

---

## 2. Pilot İşletme Değerlendirmesi ve Kritik Adli Tespit (Tenant Identity Collision)

Stage 10.12.49 kapsamında ilk pilot aday olarak **Serenut** işletmesi değerlendirilmiş ve sahadaki aktif dosyalar üzerinde adli inceleme yapılmıştır. Bu inceleme sonucunda hayati bir güvenlik bulgusu ortaya çıkarılmıştır:

### 🚨 Kritik Güvenlik Tespiti: Aktif Veritabanı Kimlik Uyuşmazlığı
- **Aktif Çalışan Veritabanı Dosyası:**  
  `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db`
- **Dosya Adı:** `serenut_pos.db` (Serenut OS uygulamasının varsayılan dosya adı)
- **Veritabanı İçindeki `settings.business_name` Kaydı:** **`Nutopia Fındık Değirmeni`**!
- **Aktif Kayıt Sayıları:**  
  - Satışlar: 52 adet
  - Ürünler: 37,682 adet
  - Müşteriler: 614 adet
  - Finansal Hareketler: 1,498 adet
  - Çevrimdışı Senkronizasyon Kuyruğu (`sync_outbox_v4`): 21 adet

### ⚠️ Neden Serenut Pilot Gölge Gözlemi Bu Terminalde Başlatılamaz?
1. **Kiracı İhlali (Tenant Collision):** Bu terminalde aktif olarak çalışan ve günlük işlem gören canlı veritabanı **Nutopia Fındık Değirmeni**'dir. Dosya adının `serenut_pos.db` olması sistemin genel yazılım adından kaynaklanmaktadır.
2. **Değişmez Kural İhlali:** Kuralımız: *"Nutopia ve Erkul Çeyiz üzerinde bu aşamada gözlem başlatma veya veri değiştirme işlemi yapma. Canlı işletme ve DB kimliği kesin doğrulanamıyorsa pilot başlatma."*
3. **Çapraz Kirlenme Riski (Cross-Tenant Contamination):** Eğer bu aktif DB üzerinde Serenut gölge hedefi (`core_next/serenut_pos.db`: 6,377 ürün, 15 satış) ile bir gölge gözlem başlatılsaydı, Nutopia'nın 37,682 ürünü ve 52 satışı Serenut hedefiyle mutabakat yapmaya zorlanacak ve işletmeler arası veri kirliliği oluşacaktı.
4. **Preflight Güvenlik Kapısı Kararı:** Preflight kontrolleri kiracı kimliğini doğrulamış ve Serenut pilot gölgesinin bu terminaldeki aktif Nutopia veritabanı üzerinde başlatılmasını **Fail-Closed olarak DERHAL ENGELLEMİŞTİR**.

---

## 3. Yedek ve Başlangıç Kanıtları Sicili

Tüm kaynak, yedek ve hedef veritabanları incelenmiş, boyutları, SHA-256 parmak izleri ve bütünlükleri doğrulanmıştır:

| Veritabanı / Dosya | Rol / Format | Boyut | SHA-256 Checksum | `PRAGMA integrity_check` | İşletme Kimliği (`business_name`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Aktif Kasa DB** (`serenut_pos.db`) | Canlı Kaynak (SQLite) | 61,390,848 B | `fb9806c68467eceb6d6d0d30abf012e8e5832731d2b358646363f19ec260b77d` | `ok` | **Nutopia Fındık Değirmeni** |
| **Canlı Yedek 2026-10-20** | Güncel Yedek (SQLite) | 57,679,872 B | `ef0cfcc925a2d8f13444c90715254f4044db838bedc3a9502ef4e507dcebcbd4` | `ok` | Nutopia Fındık Değirmeni |
| **Canlı Yedek 2026-10-19** | Standalone Yedek (SQLite)| 61,390,848 B | `da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89` | `ok` | Nutopia Fındık Değirmeni |
| **RAW Serenut v44** (`raw_serenut_v44.db`) | Resmi Serenut Yedek | 6,516,736 B | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | `ok` | **serenut** (15 Satış, 6,377 Ürün) |
| **RAW Nutopia v60** (`raw_nutopia_v60.db`) | Resmi Nutopia Yedek | 59,764,736 B | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | `ok` | Nutopia (52 Satış, 37,682 Ürün) |
| **RAW Erkul JSON** (`raw_erkul_source.json`)| Resmi Erkul Snapshot | 485,357 B | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | N/A (JSON) | Erkul Çeyiz (5 Satış, 26 Ürün) |
| **Core Next Serenut** | Hedef SQLite | 2,355,200 B | `a7cc9d22e2d4489789a9536b6c3f3018c699a5ca5daecbe2be04b32a7c7e2273` | `ok` | Serenut Hedefi (15 Satış) |
| **Core Next Nutopia** | Hedef SQLite | 17,010,688 B | `c976b4d243800c763525078b9c8e9931375a1bf88fe6afca727461c230c61753` | `ok` | Nutopia Hedefi (52 Satış) |

---

## 4. Gözlem Başlatma Kapısı (Preflight Gate Analizi)

Gölge gözlem başlatılmadan önce 8 zorunlu güvenlik kapısı değerlendirilmiştir:

```
[PREFLIGHT GATE 1] Doğru pilot işletme ve aktif kaynak DB kimliği kanıtlandı mı?
  -> ❌ BAŞARISIZ: Aktif DB Nutopia'ya aittir. Serenut verisi değildir.
[PREFLIGHT GATE 2] Hedef DB izole ve doğru işletmeye ait mi?
  -> ⚠️ RİSKLİ: Aktif terminalde hedef 'serenut_core_v2.db' açılırsa Nutopia verisi Serenut hedefine karışır.
[PREFLIGHT GATE 3] Başlangıç yedeği alınmış ve doğrulanmış mı?
  -> ✅ BAŞARILI: 2026-10-20 10:40:57 tarihli SHA-256 ve PRAGMA onaylı yedek mevcut.
[PREFLIGHT GATE 4] Kaynak DB yazma yapılmadan okunabiliyor mu?
  -> ✅ BAŞARILI: Salt-okunur (RO) SQLite bağlantısı ve WAL non-blocking okuma kanıtlandı.
[PREFLIGHT GATE 5] Hedef yazımlarının yalnızca shadow hedefe gittiği kanıtlandı mı?
  -> ✅ BAŞARILI: Kod analizinde kaynak DB'ye hiçbir yazma sorgusu gitmediği kanıtlandı.
[PREFLIGHT GATE 6] Kasa işlemlerinden bağımsız hata ve zaman aşımı davranışı doğrulandı mı?
  -> ✅ BAŞARILI: _executeWithRetry ve fail-closed çökme izolasyonu kanıtlandı.
[PREFLIGHT GATE 7] Gözlem kayıtları ve watermark kalıcı ve yeniden başlatılabilir mi?
  -> ✅ BAŞARILI: lastMigrationCutoffTimestamp epoch ms watermark mekanizması doğrulandı.
[PREFLIGHT GATE 8] Başlangıç mutabakatında açıklanmamış finansal fark yok mu?
  -> ❌ BLOKE: Aktif DB (Nutopia 52 satış) ile Serenut (15 satış) arasında kiracı farkı var.
```

### Preflight Sonucu: `PILOT_OBSERVATION_BLOCKED`
Kapı 1 ve Kapı 8 başarısız olduğu için Serenut pilotunun canlı gözlemi bu terminalde **BAŞLATILMAMIŞTIR**.

---

## 5. Güvenli Hata ve Preflight Test Paketi (Stage 49)

[stage10_12_49_pilot_gate_preflight_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_12_49_pilot_gate_preflight_test.dart) test paketi ile preflight ve kimlik ayrımı kuralları bağımsız olarak test edilmiştir:

1. **Preflight Senaryosu 1 (Kiracı Kimlik Ayrımı):**
   - Aktif DB `Nutopia Fındık Değirmeni` olduğunda, sistemin `serenut` pilot adayını eşleştirmeyip fail-closed durduğu kanıtlanmıştır.
2. **Preflight Senaryosu 2 (Salt Okunurluk Değişmezi):**
   - Kaynak veritabanının SHA-256 parmak izi işlem öncesi ve sonrasında karşılaştırılmış, kaynağa 1 bit dahi yazılmadığı test edilmiştir.
3. **Preflight Senaryosu 3 (Watermark ve Kalıcı Durum Koruması):**
   - Watermark ve `app_settings` durum kayıtlarının kalıcılığı test edilmiştir.

---

## 6. Tam Regresyon Test Paketi Sonuçları (Stages 43 - 49)

```bash
$ flutter test \
  test/core_next/stage10_12_43_automatic_lossless_migration_test.dart \
  test/core_next/stage10_12_44_live_safe_export_import_test.dart \
  test/core_next/stage10_12_45_automatic_cutover_integration_test.dart \
  test/core_next/stage10_12_46_critical_data_loss_remediation_test.dart \
  test/core_next/stage10_12_47_shadow_verification_test.dart \
  test/core_next/stage10_12_48_shadow_observation_readiness_test.dart \
  test/core_next/stage10_12_49_pilot_gate_preflight_test.dart
```

### Gerçek Test Çıktısı:
```text
00:00 +0: loading test/core_next/stage10_12_43_automatic_lossless_migration_test.dart
...
00:29 +60: All tests passed!
Exit code: 0
```
- **Toplam Test:** 60 test
- **Başarılı:** 60
- **Başarısız:** 0
- **Atlanan:** 0

---

## 7. Gözlem Nasıl Durdurulur? (Acil Durum Prosedürü)

Herhangi bir aşamada gölge gözlem başlatıldığında veya durdurulması gerektiğinde:
1. **Yazılımsal Durdurma:**
   - `coreNextSalesEngineEnabledProvider = false` ve `databaseRoutingHook = null` olduğu için uygulama varsayılan olarak eski mimaridedir.
   - Arka plan gözlem görevi iptal edilmek istendiğinde `CoreNextBootstrapCoordinator.resetExecutionLock()` çağrılır veya uygulama yeniden başlatılır.
2. **Fiziksel / Veritabanı İzolasyonu:**
   - Hedef `serenut_core_v2.db` dosyası salt-okunur yapılarak veya silinerek gölge süreç anında `failedRecoverable` durumuna düşürülür; eski veritabanı hiçbir şekilde etkilenmez.
3. **Canlı SSoT Garantisi:**
   - Kasa satışları, tahsilatları ve donanım yazıcı kuyrukları eski `serenut_pos.db` üzerinde %100 izole olarak çalışmaya devam eder.

---

## 8. Nihai Rapor ve Teslimat Özeti

- **Pilot İşletme ve DB Yolları:**
  - Aktif Kasa Dosyası: `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db`
  - Aktif İşletme Kimliği: **Nutopia Fındık Değirmeni**
  - Hedef Serenut Dosyası: `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\core_next\serenut_pos.db`
- **Yedek ve Başlangıç Kanıtları:**
  - `serenut_pos_backup_20261020_104057.db` (57,679,872 B, SHA-256 `ef0cfcc925a2...`, Bütünlük: `ok`).
  - `raw_serenut_v44.db` (6,516,736 B, SHA-256 `9145443f2c94...`, Bütünlük: `ok`).
- **Gerçek Test Sonuçları:** 60/60 Test Geçti (%100 Başarı).
- **Gözlem Gerçekten Başlatıldı mı?:** **HAYIR.** (Aktif DB'nin Nutopia olması ve kiracı kirliliği riski nedeniyle preflight aşamasında güvenle durduruldu).
- **İlk Gözlem ve Mutabakat:** Canlı gözlem başlatılmadığı için kiracı kirlenmesi önlenmiş, veri kaybı riski sıfıra indirilmiştir.
- **Açıklanmamış Farklar ve Riskler:** Fark bulunmamaktadır; risk kiracı uyuşmazlığı olarak tespit edilmiş ve engellenmiştir.
- **Gözlem Nasıl Durdurulur?:** SSoT eski veritabanında olduğundan kilitler ve koordinatör durdurulduğunda operasyon sıfır kesintiyle devam eder.
- **Sonraki Aşama İçin Gereken Kanıtlar:** 
  1. Ya Serenut işletmesine ait bağımsız terminal/veritabanı aktif hale getirilmeli,
  2. Ya da pilot işletme önceliği mevcut terminaldeki aktif veritabanının sahibi olan **Nutopia Fındık Değirmeni**'ne devredilmelidir.
- **Cutover Durumu:** **`NOT_APPROVED`** (Canlı cutover onaylanmamıştır).
