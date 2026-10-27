# CORE NEXT STAGE 10.8.4 — AUTHORITATIVE STORE CUTOVER TASARIMI, MIGRATION BRIDGE DENETİMİ VE VERİ GEÇİŞİ RAPORU

**Tarih:** 2026-10-14  
**Aşama:** Stage 10.8.4 — Cutover Tasarımı, Migration Bridge Denetimi ve Veri Geçişi Provası  
**Başlangıç Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Bitiş Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Commit/Push/Deploy yapılmadı)  
**Nihai Karar:** `LIVE_GATE: BLOCKED` (Canlı Cutover Kapısı Kapalı)  
**İlişkili Raporlar:**
- [CORE_NEXT_STAGE10_8_4_MIGRATION_MAPPING.md](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/CORE_NEXT_STAGE10_8_4_MIGRATION_MAPPING.md)
- [CORE_NEXT_STAGE10_8_4_RECONCILIATION_REPORT.md](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/CORE_NEXT_STAGE10_8_4_RECONCILIATION_REPORT.md)

---

## 1. Çalışma Ağacı ve Başlangıç Güvenlik Kontrolü

```
$ git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

$ git diff --check
(0 hata, temiz)
```

Canlı veritabanına (`serenut_pos.db`) hiçbir yazma, silme veya şema değişikliği yapılmamıştır. Tüm testler ve provalar izole geçici SQLite dosyaları üzerinde icra edilmiştir.

---

## 2. Bölüm 2: `MigrationBridgeEngine` Adli Denetimi (10 Soru - 10 Kanıt)

### 1. Hangi legacy tabloları hangi Core Next tablolara dönüştürüyor?
- `products` -> `products` (Kuruş fiyat ve stok ile).
- `customers` -> `customers` (Kuruş bakiye ve defter doğrulaması ile).
- `sales` -> `sales` ve `sale_payments` (Nakit/kart/veresiye/karma ödeme parçaları ile).
- `app_settings` -> `legacy_migration_completed = 'true'`.

### 2. Her kaynak tablonun hedef karşılığı mevcut mu?
**HAYIR.** Legacy şemada yer alan `sale_items`, `financial_transactions`, `refunds`, `refund_items`, `sync_outbox_v4`, `users` ve `orders` tablolarının `MigrationBridgeEngine` içinde bir aktarım karşılığı **bulunmamaktadır**.

### 3. Ürünler, varyantlar, barkodlar, kalemler, ödemeler, defter, iadeler kapsanıyor mu?
- **Kapsananlar:** Ürünler (`products`), barkodlar, müşteriler (`customers`), satış başlıkları (`sales`), ödeme parçaları (`sale_payments`).
- **Kapsanmayanlar:** Satış kalemleri (`sale_items`), stok hareketleri (`stock_movements`), cari defter geçmişi (`ledger_entries`), iade ve iptaller (`refunds`, `refund_items`), kullanıcılar (`users`), çevrimdışı outbox (`sync_outbox_v4`).

### 4. Legacy `double` parasal alanlar Core Next `*_cents` alanlarına nasıl dönüştürülüyor?
`(amount * 100).round()` formülü ile tamsayı kuruşa çevrilir (`migration_bridge_engine.dart:116, 209, 296`). Sınır değerlerde ve kuruş hassasiyetinde sıfır toleransla çalışır.

### 5. Türkçe karakterler, benzersiz anahtarlar ve eski kimlikler nasıl korunuyor?
- Türkçe karakterler (`Ç, Ğ, İ, Ö, Ş, Ü, ı`) SQLite UTF-8 metin formatında bozulmadan aktarılır (`stage10_8_4_migration_rehearsal_test.dart: Test 1`).
- Eski UUID kimlikleri (`row['id']`) doğrudan hedef tabloda `id` olarak korunur.
- Benzersiz anahtarlar (`barcode`, `idempotency_key`, `receipt_no`) hedefte UNIQUE indekslerle güvenceye alınır.

### 6. Yabancı anahtarlar ve benzersizlik kısıtları hedefte korunuyor mu?
**EVET.** Core Next veritabanında `PRAGMA foreign_keys = ON;` aktiftir. Migrasyon sonrasında çalıştırılan `PRAGMA foreign_key_check` 0 ihlal (temiz) vermiştir. Hedefte olmayan bir `customer_id` varsa yabancı anahtar ihlalini önlemek için `customer_id = NULL` atanır.

### 7. Kaynak veritabanındaki eşzamanlı yazımlar migration sırasında nasıl ele alınıyor?
- Migrasyon öncesinde `serenut_pos.db` dosyasının fiziksel `.backup` kopyası alınır.
- Ancak canlıda eşzamanlı yazımların çakışmaması için cutover anında POS satış ekranı kilitlenmeli (`isWriteLocked = true`), tüm bekleyen asenkron transaction'lar `COMMIT` edilmelidir.

### 8. Yarım kalan migration tekrar başlatılırsa mükerrer kayıt veya kayıp oluşuyor mu?
**HAYIR.**
- Hedef yazımları `ConflictAlgorithm.replace` (ürünler ve müşteriler) ve `ConflictAlgorithm.ignore` (satışlar) kullanır.
- Ayrıca tüm işlem tek bir `targetDb.transaction(...)` içinde icra edilir; herhangi bir hata durumunda tüm hedef tablolar **otomatik ROLLBACK** olur (`fault_injection_migration_test.dart`).

### 9. Cutover sonrasında uygulamanın hangi servisleri yeni veritabanını kullanacak?
Cutover tamamlandığında:
- `SalesController` -> `SalesEngineAdapter` -> `CoreCheckoutUseCase`
- `InventoryService` -> `SqliteProductRepository` (Core Next)
- `CustomersController` -> `SqliteLedgerRepository` (Core Next)
- `SyncNotifier` -> `SyncV4OutboxProcessor` & `SyncV4PullWorker` (Core Next)

### 10. Eski sync worker'ın `sync_outbox_v4` kayıtlarıyla yeni `sync_events` kayıtlarının geçişi nasıl sağlanıyor?
**ŞU ANDA GEÇİŞ KODU BULUNMAMAKTADIR (BLOCKED RİSKİ).**
Legacy `sync_outbox_v4` tablosunda bekleyen (`state = 'PENDING'`) mutasyonlar `MigrationBridgeEngine` tarafından `sync_events` tablosuna aktarılmamaktadır. Eğer kasanın sunucuya göndermediği yerel satışlar varken cutover yapılırsa bu satışlar sunucuya asla iletilmez.

---

## 3. İzole Test Sonuçları (Tamamı Yeşil)

| Test Paketi | Test Sayısı | Başarılı | Başarısız | Süre | Sonuç |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `test/core_next/stage10_8_4_migration_rehearsal_test.dart` | 5 | 5 | 0 | 1.0s | **PASS** |
| `test/core_next/migration_bridge_test.dart` | 6 | 6 | 0 | 0.8s | **PASS** |
| `test/core_next/fault_injection_migration_test.dart` | 2 | 2 | 0 | 1.1s | **PASS** |
| `test/core_next/stage10_8_3_runtime_bootstrap_test.dart` | 10 | 10 | 0 | 1.0s | **PASS** |
| `test/ui/stage10_8_2_sales_controller_e2e_test.dart` | 4 | 4 | 0 | 1.0s | **PASS** |
| `test/core_next/` (Tüm paket) | 186 | 186 | 0 | 1m 55s | **PASS** |

---

## 4. Tek Yetkili Kaynak (Authoritative Store) ve Geri Dönüş (Rollback) Stratejisi

### A. Cutover Öncesi Hazırlık (Quiescence):
1. Kasa üzerinde açık sepet veya devam eden satış işlemi bulunmamalıdır (`isOperationInProgress == false`).
2. Legacy `sync_outbox_v4` kuyruğundaki tüm bekleyen (`PENDING`) kayıtlar sunucuya boşaltılmalı (`SyncNotifier.triggerSync()`), kuyruk sıfırlanmalıdır.
3. `DatabaseManager.isWriteLocked = true` yapılarak legacy veritabanına yeni yazımlar durdurulmalıdır.

### B. Geçiş ve Doğrulama:
1. `serenut_pos.db` dosyasının fiziksel yedeği `serenut_pos.db.backup` olarak kopyalanır.
2. `MigrationBridgeEngine.migrateFromLegacy()` çalıştırılır.
3. Kuruş ve bakiye mutabakatı (`report.isSuccess == true` ve `customerDiscrepancies.isEmpty`) doğrulanır.
4. `PRAGMA integrity_check` ve `PRAGMA foreign_key_check` çalıştırılır.

### C. Geri Dönüş (Rollback) Analizi ve İki Yönlü Sapma Riski:
- **Senaryo 1 (Yeni Motor Satış Yapmadan Önce):**
  - Eğer geçiş sırasında veya hemen sonrasında (henüz hiç yeni satış yapılmadan) hata tespit edilirse:
  - `serenut_core_v2.db` silinir, `serenut_pos.db.backup` geri yüklenir. **Süre: < 5 saniye, Veri Kaybı: SIFIR.**
- **Senaryo 2 (Yeni Motor Satış Yaptıktan Sonra):**
  - Yeni motor (`serenut_core_v2.db`) devreye girdikten sonra kasada yeni satışlar yapılmışsa, yalnızca eski `serenut_pos.db` dosyasını geri yüklemek **CİRO VE VERİ KAYBINA YOL AÇAR!**
  - Bu durumda geri dönüş için Core Next `sales` ve `ledger_entries` kayıtlarını legacy şemaya geri aktaracak bir **Ters Mutabakat Motoru (Reverse Migration)** veya sunucu üzerinden restore mekanizması zorunludur.

---

## 5. Eksikler ve Canlıya Geçiş Engelleri (Blockers)

Aşağıdaki kritik eksikler giderilmeden canlı cutover yapılamaz:

1. **`sale_items` Migrasyonunun Bulunmaması:** Geçmiş fiş kalemleri taşınmadığı için geçmiş fiş yazdırma ve iade işlemleri başarısız olur.
2. **`sync_outbox_v4` Taşınmaması:** Çevrimdışı mutasyonların kaybolma riski mevcuttur.
3. **`ledger_entries` Geçmişinin Taşınmaması:** Müşteri anlık bakiyesi doğru olsa bile geçmiş cari hareket dökümü görüntülenemez.
4. **Dart Paket Sınırı:** `lib/` kodlarının `core_next` modülüne `pubspec.yaml` path-dependency ile bağlanmamış olması.

---

## 6. Nihai Karar

```
LIVE_GATE: BLOCKED
```

**Gerekçe:**
İzole geçiş provası Türkçe karakterler, kuruş hassasiyeti, ödeme parçaları ve atomik rollback açısından başarıyla kanıtlanmıştır. Ancak `sale_items`, `ledger_entries` ve `sync_outbox_v4` aktarımları tamamlanmadan ve iki yönlü rollback güvencesi kurulmadan canlı cutover gerçekleştirilemez.
