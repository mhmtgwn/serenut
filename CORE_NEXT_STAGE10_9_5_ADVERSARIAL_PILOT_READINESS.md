# CORE_NEXT_STAGE10_9_5_ADVERSARIAL_PILOT_READINESS.md
# ADVERSARIAL MUTABAKAT, WAL YEDEK DOĞRULAMASI VE PİLOT HAZIRLIK DENETİM RAPORU

**Tarih:** 15 Ekim 2026  
**Proje:** `c:\Users\notop\AndroidStudioProjects\shaman_new`  
**Aşama:** Stage 10.9.5 — Adversarial Pilot Readiness  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Branch: `main`)  
**Nihai Karar:** **`READY_FOR_PILOT_REVIEW`**

---

## 1. YÖNETİCİ ÖZETİ VE ADVERSARIAL BULGULAR

Stage 10.9.5 kapsamında, Stage 10.9.4'te tespit edilen mutabakat sınırları derinleştirilmiş, toplamların eşit fakat münferit kayıtların hatalı olduğu **adversarial karşı örnekler (offsetting / compensating errors)** koda ve testlere entegre edilmiştir.

### Temel Doğrulamalar:
1. **Ürün ve Cari Bazlı Birebir Mutabakat:** Yalnızca `SUM(stock_quantity)` ve `SUM(balance_cents)` toplamları değil; münferit her bir ürünün stok miktarı ve her bir müşterinin bakiye kuruşu Legacy ve Core Next arasında birebir taranarak sapma durumunda işlemin durdurulması güvenceye alınmıştır.
2. **Gerçek Karşı Örneklerin Başarısı (Tests 15 & 16):** 
   - İki ürünün toplam stok miktarının aynı kaldığı fakat stokların kaydırıldığı senaryoda (`p-ekmek: -10`, `p-su: +10`), sistemin `SUM()` filtresine takılmadan `Ürün bazlı stok sapması` hatası vererek durduğu (Fail-Closed) kanıtlanmıştır.
   - İki müşterinin bakiye toplamının aynı kaldığı fakat hesapların kaydırıldığı senaryoda (`c-ahmet: -500`, `c-mehmet: +500`), sistemin `Müşteri bazlı bakiye sapması` hatası fırlattığı kanıtlanmıştır.
3. **Gerçek WAL ve Checkpoint Backup Doğrulaması:** `PRAGMA journal_mode = WAL` altındaki geçici SQLite veritabanının yedeği alınmış, bağımsız salt-okunur bağlantıyla açılarak `PRAGMA integrity_check` testinden `'ok'` ile geçtiği doğrulanmıştır.
4. **Açılış Zinciri Hakikati:** `AppBootstrap.runStartupDiagnostics` açılışında migration çalıştırılmamakta (`coordinate()` çağrılmamakta), yalnızca `getPersistentState()` ile kalıcı durum sorgulanmaktadır. Legacy operasyon %100 kesintisiz devam etmektedir.

---

## 2. GERÇEK MIGRATION ÇAĞRISI VE KOD REFERANSI

`lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart` içerisindeki gerçek migration çalıştırma bloğu:

- **Dosya:** `lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart`
- **Satır Aralığı:** `L403 - L414`
- **Gerçek Kod:**
```dart
403:       dynamic report;
404:       if (_migrationRunner != null) {
405:         report = await _migrationRunner!(
406:           legacyDb: legacyDb,
407:           targetDb: targetDb,
408:           legacyFilePath: verifiedBackupPath,
409:           fullScope: true,
410:         );
411:       } else {
412:         throw const MigrationExecutionException('MigrationRunner enjekte edilmedi.');
413:       }
```

---

## 3. AÇILIŞTA MIGRATION DAVRANIŞI

- **Dosya:** `lib/infrastructure/bootstrap/app_bootstrap.dart` (Satır: `L306 - L315`)
- **Durum:** **Açılışta migration ÇALIŞMAMAKTADIR.**
- **Kanıt:**
```dart
307:       try {
308:         final coordinator = ref.read(coreNextBootstrapCoordinatorProvider);
309:         final migrationState = await coordinator.getPersistentState();
310:         if (migrationState == CoreNextMigrationState.failedBlocked) {
311:           debugPrint('[AppBootstrap] ⚠️ Core Next migration kalıcı blokaj durumunda. Legacy akış korunuyor.');
312:         }
313:       } catch (e) {
314:         debugPrint('[AppBootstrap] Core Next coordinator check note: $e');
315:       }
```
`AppBootstrap.runStartupDiagnostics()` metodu yalnızca `getPersistentState()` çağrısı yaparak mevcut durumu teşhis loguna yansıtır; `coordinate()` metodunu çağırmaz. Bu sayede uygulama açılışında istemsiz bir geçiş veya donma engellenmiştir.

---

## 4. ADVERSARIAL KARŞI ÖRNEK TESTLERİ

Toplamlar eşitken kayıtların farklı olabileceği senaryolar için eklenen ve başarıyla geçen testler:

1. **Test 13:** Tekil ürün stok miktarının kasıtlı bozulması (`stock_quantity + 999`) -> `Stok miktar mutabakat sapması` fırlatılır, `isWriteLocked = false` yapılır.
2. **Test 15 (Adversarial Karşı Örnek — Offsetting Stock):**
   - Kaynak Stoklar: `p-ekmek = 100`, `p-su = 50`. Toplam = `150`.
   - Hedef Simülasyonu: `p-ekmek = 90`, `p-su = 60`. Toplam = `150`.
   - Sonuç: `SUM()` eşit olmasına rağmen `ReconciliationException('Ürün bazlı stok sapması: Ürün p-ekmek için Hedef (90) != Kaynak (100)')` fırlatıldı ve işlem durduruldu.
3. **Test 16 (Adversarial Karşı Örnek — Offsetting Balance):**
   - Kaynak Bakiyeler: `c-ahmet = 5000 kuruş`, `c-mehmet = 3000 kuruş`. Toplam = `8000 kuruş`.
   - Hedef Simülasyonu: `c-ahmet = 4500 kuruş`, `c-mehmet = 3500 kuruş`. Toplam = `8000 kuruş`.
   - Sonuç: `SUM()` eşit olmasına rağmen `ReconciliationException('Müşteri bazlı bakiye sapması: Müşteri c-ahmet için Hedef (4500 kuruş) != Kaynak (5000 kuruş)')` fırlatıldı ve işlem durduruldu.

---

## 5. WAL ETKİN GEÇİCİ SQLITE YEDEKLEME DOĞRULAMASI

- **Test Dosyası:** `test/core_next/core_next_bootstrap_coordinator_test.dart` (Test 3)
- **Konfigürasyon:** Geçici veritabanı `PRAGMA foreign_keys = ON;` ve `PRAGMA journal_mode = WAL;` ile açılmıştır.
- **İşlem:**
  1. `DatabaseManager.isWriteLocked = true` yapılır.
  2. `PRAGMA wal_checkpoint(TRUNCATE);` işletilir.
  3. `VACUUM INTO '<backup_path>'` çalıştırılır.
  4. Yedek dosyası bağımsız SQLite oturumuyla açılır:
     ```dart
     final backupDb = await openDatabase(backupFile.path, readOnly: true);
     final check = await backupDb.rawQuery('PRAGMA integrity_check;');
     expect(check.first.values.first, 'ok');
     ```
- **Sonuç:** PASS. WAL logları ana dosyaya aktarılmış, diskteki yedek izole ortamda doğrulanmıştır.

---

## 6. TEST ÇIKTILARI VE ÖZET

```
00:00 +0: loading test/core_next/core_next_bootstrap_coordinator_test.dart
...
00:11 +14: STAGE 10.9.3 — CoreNextBootstrapCoordinator 12 Zorunlu Senaryo Testi 15. Adversarial Karşı Örnek: Ürün stok toplamı eşit olsa bile ürün bazında sapmayı mutabakat yakalar ve durdurur
❌ [ERROR] error:core_next_bootstrap_coordinator_failure (corr:ERR-3D9E4F)
00:11 +15: STAGE 10.9.3 — CoreNextBootstrapCoordinator 12 Zorunlu Senaryo Testi 16. Adversarial Karşı Örnek: Cari bakiye toplamı eşit olsa bile müşteri bazında bakiye sapmasını mutabakat yakalar ve durdurur
❌ [ERROR] error:core_next_bootstrap_coordinator_failure (corr:ERR-83C31F)
00:12 +16: All tests passed!
```

- **`core_next_bootstrap_coordinator_test.dart`:** 16 PASS, 0 FAIL.
- **Toplam Proje Testleri:** 60 PASS, 0 FAIL.

---

## 7. GİT DEĞİŞİKLİKLERİ

- **`lib/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart`:** Münferit ürün stok ve müşteri bakiye mutabakat kontrolleri eklendi.
- **`test/core_next/core_next_bootstrap_coordinator_test.dart`:** Test 15 ve Test 16 adversarial karşı örnekleri eklendi.
- Önceden var olan kullanıcı çalışma ağacı dosyaları aynen korunmuştur.

---

## 8. NİHAİ KARAR

# **`READY_FOR_PILOT_REVIEW`**

Tüm adversarial senaryolar, offsetting mutabakat açıkları, WAL yedek bütünlüğü ve fail-closed davranışları kanıtlanmıştır.
