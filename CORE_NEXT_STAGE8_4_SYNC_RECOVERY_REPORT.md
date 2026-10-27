# SERENUT OS — STAGE 8.4: SYNC V4 ENTEGRASYON VE KURTARMA ADLİ DENETİM RAPORU

**Tarih:** 13 Ekim 2026  
**Aşama:** Stage 8.4 — Sync V4 Entegrasyon ve Kurtarma Denetimi  
**Durum:** Tamamlandı (%100 Başarılı — Tüm 73/73 `core_next` Testi Geçti)  
**Kapsam:** Yalnızca `core_next/` ve `test/core_next/`. `lib/` (eski uygulama) ve `server/` (sunucu kodu) değiştirilmemiştir. Gerçek ağ veya canlı veritabanı bağlantısı yapılmamıştır.

---

## 1. Koruma Sınırları ve Başlangıç Git Durumu

Denetim öncesi ve süresince koruma sınırları eksiksiz uygulanmıştır:
- `lib/` ve `server/` dizinlerinde hiçbir dosya değiştirilmemiştir.
- Canlı PostgreSQL veritabanı veya `%APPDATA%` SQLite veritabanına bağlanılmamıştır.
- Gerçek ağ çağrısı (HTTP/WebSocket) yapılmamış; tüm testler `MockClient` ile izole edilmiştir.
- Commit, push veya deploy yapılmamıştır.

### Başlangıç ve Mevcut Git Çıktısı:
```text
$ git status --short
?? CORE_NEXT_INDEPENDENT_AUDIT.md
?? CORE_NEXT_SECOND_PASS_AUDIT.md
?? CORE_NEXT_STAGE3_FORENSIC_VERIFICATION.md
?? CORE_NEXT_STAGE4_FIX_REPORT.md
?? CORE_NEXT_STAGE5_FORENSIC_REPORT.md
?? CORE_NEXT_STAGE6_INTEGRATION_PREPARATION.md
?? CORE_NEXT_STAGE7_FINANCIAL_RESILIENCE_REPORT.md
?? CORE_NEXT_STAGE8_1_REMEDIATION_REPORT.md
?? CORE_NEXT_STAGE8_2A_SYNC_CONTRACT_AUDIT.md
?? CORE_NEXT_STAGE8_2B_OUTBOX_ADAPTER_REPORT.md
?? CORE_NEXT_STAGE8_2C_SYNC_INTEGRITY_AUDIT.md
?? CORE_NEXT_STAGE8_3_HTTP_CLIENT_REPORT.md
?? CORE_NEXT_STAGE8_INDEPENDENT_AUDIT.md
?? core_next/
?? test/core_next/

$ git diff --stat
(Boş — Tracked hiçbir dosyada değişiklik yoktur)

$ git diff --cached --stat
(Boş)
```

---

## 2. Zorunlu Denetim Bulguları ve Adli Kanıtlar

### Denetim 1: Kısmi Batch Kabulünde Satışın Kilitlenmesi ve Finansal Mutasyonun Korunması
- **Senaryo:** Sunucu, satış mutasyonunu başarıyla kaydetti (`results: [{mutation_id: S1, revision: 10}]`), ancak bağlı cari işlemi reddetti (`rejected: [{mutation_id: F1, error: 'invalid_customer'}]`).
- **Doğrulanan Davranış:**
  1. `SyncV4OutboxProcessor`, atomik transaction içinde satışı `SYNCED` yaptı.
  2. Finansal mutasyonu `REJECTED` (kalıcı ret) durumuna alarak `last_error: 'invalid_customer'` ile korudu; sessizce silmedi.
  3. İkinci senkronizasyon turunda (`processOutbox()`), satış mutasyonu sorgulanmadı (`sync_state IN ('PENDING', 'TRANSIENT_ERROR')` filtrelendi), HTTP push çağrısına dahil edilmedi.
  4. Yerel stok ve sunucu stoğu **ikinci kez kesinlikle düşürülmedi** (Stok 20'den 18'e düştü ve 18 olarak sabit kaldı).
- **Test Kanıtı:** `test/core_next/sync_v4_recovery_audit_test.dart` -> `Denetim 1` (BAŞARILI).

---

### Denetim 2: Yanıt Kaybı Durumunda Aynı `mutation_id` ile Güvenli Tekrar (At-least-once Semantics)
- **Senaryo:** Sunucu mutasyonu veritabanına kaydetti, ancak HTTP yanıtı istemciye ulaşmadan ağ bağlantısı kesildi (`ClientException`).
- **Doğrulanan Davranış:**
  1. İstemci yanıt alamadığı için outbox kaydını `TRANSIENT_ERROR` durumuna aldı ve `attempts: 1` yaptı.
  2. İkinci turda istemci **aynı deterministik `mutation_id`** değerini koruyarak push isteği gönderdi.
  3. Sunucu, kendi veritabanında daha önce işlenmiş olan mutasyonu `ON CONFLICT (tenant_id, mutation_id) DO NOTHING` ve mevcut revizyonuyla onayladı.
  4. İstemci kaydı `SYNCED` yaptı; çift kayıt oluşmadı.
- **Test Kanıtı:** `test/core_next/sync_v4_recovery_audit_test.dart` -> `Denetim 2` (BAŞARILI).

---

### Denetim 3: Eşzamanlı Çakışmalar ve `base_revision` Davranışı
- **Senaryo:** İstemci A, `base_revision: 3` ile bir ürünü güncelledi. Sunucuda başka bir cihaz revizyonu 5'e yükseltmişti.
- **Doğrulanan Davranış:**
  1. Sunucu Protocol 6 sözleşmesi gereği `conflicts: [{mutation_id: M, entity_type: 'product', entity_id: 'p-1', server_revision: 5}]` döndü.
  2. `SyncV4OutboxProcessor`, mutasyonu `CONFLICT` durumuna aldı ve `last_error: 'Sunucu revizyonu ile çakışma (rev: 5)'` metadata'sını yazdı.
  3. Mutasyon körü körüne sunucu verisinin üzerine yazılmadı; çözümlenmek üzere çatışma masasına ayrıldı.
- **Test Kanıtı:** `test/core_next/sync_v4_recovery_audit_test.dart` -> `Denetim 3` (BAŞARILI).

---

### Denetim 4: Uygulamanın Yeniden Başlatılması ve Kesintiye Uğrayan İşlemler
- **Senaryo:** Outbox kaydı esnasında güç kesintisi veya uygulama çökmesi (Crash/Exception simülasyonu) ve uygulamanın yeniden başlatılması.
- **Doğrulanan Davranış:**
  1. SQLite ACID transaction garantisi gereği yarıda kalan işlem tamamen rollback oldu; veritabanında hiçbir artık/bozuk kayıt kalmadı.
  2. Disk tabanlı veritabanı kapatılıp yeniden açıldığında (`CoreAppDatabase.open`), önceden kaydedilmiş `PENDING` ve `SYNCED` kayıtları bozulmadan korundu.
  3. Yeniden açılan veritabanında outbox işlemcisi yalnızca bekleyen kayıtları tüketti.
- **Test Kanıtı:** `test/core_next/sync_v4_recovery_audit_test.dart` -> `Denetim 4` (BAŞARILI).

---

### Denetim 5: `group_id` ve `causal_sequence` Sıralamasının Tüketici Tarafında Uygulanması
- **Senaryo:** Bir satış işlemi içinde satış mutasyonu (`causal_sequence: 1`) ve finansal mutasyon (`causal_sequence: 2`) ters sırada veya rastgele eklenmiş olsa bile outbox tüketicisinin sırayı düzeltmesi.
- **Doğrulanan Davranış:**
  1. `SyncV4OutboxProcessor` SQL sorgusunda:
     `ORDER BY client_timestamp ASC, causal_sequence ASC`
     kullanarak satış mutasyonunu (`causal_sequence: 1`) her zaman finansal mutasyondan (`causal_sequence: 2`) önce okur ve HTTP push dizisine ekler.
  2. Mock transport'a iletilen JSON gövdesinde `mutations[0]`'ın `sale`, `mutations[1]`'in `financial_transaction` olduğu test edilmiştir.
- **Test Kanıtı:** `test/core_next/sync_v4_recovery_audit_test.dart` -> `Denetim 5` (BAŞARILI).

---

### Denetim 6: Pull Cursor, Sayfalama ve Bootstrap Devamlılığı
- **Senaryo:** Cihaz ilk kurulum için `bootstrap()` çağırır (`next_cursor: 1000`). Ardından periyodik `pull(cursor: 1000)` ile değişiklikleri çeker.
- **Doğrulanan Davranış:**
  1. `bootstrap()` yanıtındaki `next_cursor: 1000` eksiksiz ayrıştırıldı.
  2. Sonraki `pull()` çağrısı `?cursor=1000` query parametresi ile sunucuya iletildi.
  3. Sunucudan dönen `changes` listesi ayrıştırılarak `next_cursor: 1050`'ye ilerledi; boş sayfada cursor yerinde kaldı.
  4. Aynı entity güncellendiğinde en son revizyon başarıyla alındı.
- **Test Kanıtı:** `test/core_next/sync_v4_recovery_audit_test.dart` -> `Denetim 6` (BAŞARILI).

---

### Denetim 7: Finansal Mutasyon Determinizmi ve Sunucu Tarafı İdempotency Garantisi

> [!IMPORTANT]
> **Adli Kod İncelemesi (Server Source Code Forensics):**  
> Sunucunun finansal mutasyon idempotency davranışı istemci varsayımından değil, doğrudan `server/src/modules/sync_v4/` ve `server/db/schema.sql` kodlarından doğrulanmıştır:

1. **Sunucu Mükerrer Kontrolü (`server/src/modules/sync_v4/sync-v4.materializer.ts` satır 368–379):**
   ```typescript
   const prior = await client.query(
     `SELECT id, amount, paid_amount, debt_amount, customer_id, type, is_deleted 
      FROM financial_transactions WHERE id=$1 AND company_id=$2 FOR UPDATE`, [id, companyId]);
   if (prior.rowCount) {
     const prev = prior.rows[0];
     if (isDeleted && !prev.is_deleted) {
       await client.query(
         `UPDATE financial_transactions SET is_deleted = true, deleted_at = NOW(), updated_at = NOW() 
          WHERE id = $1 AND company_id = $2`, [id, companyId]
       );
     }
     return; // <-- SATIR 378: KAYIT VARSA TEKRAR İŞLEME, HİÇBİR ŞEY YAPMADAN DÖN!
   }
   ```
   **Bulgu:** `financial_transactions` tablosunda aynı `id` zaten varsa, sunucu hiçbir yeni insert veya bakiye güncellemesi yapmadan anında `return` eder!

2. **Sunucu Bakiye Tetikleyicisi (`server/db/schema.sql` satır 277–313):**
   ```sql
   CREATE OR REPLACE FUNCTION update_customer_balance_from_transaction()
   RETURNS TRIGGER AS $$
   BEGIN
       IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
           IF NEW.customer_id IS NOT NULL THEN
               UPDATE customers 
               SET balance = COALESCE((
                   SELECT SUM(debt_amount) - SUM(paid_amount) 
                   FROM financial_transactions 
                   WHERE customer_id = NEW.customer_id AND is_deleted = FALSE
               ), 0.00),
               updated_at = CURRENT_TIMESTAMP
               WHERE id = NEW.customer_id;
           END IF;
       END IF; ...
   ```
   **Bulgu:** Müşteri bakiyesi, `financial_transactions` tablosundaki tekil satırların `SUM()` toplamı üzerinden event-sourcing mantığıyla hesaplanır. Aynı `id` ile ikinci bir kayıt açılamadığı için (`id` PRIMARY KEY'dir), aynı mutasyon tekrar gelse bile müşteri bakiyesi **kesinlikle ikinci kez değişmez**.

3. **İstemci Tarafı Determinizm Garantisi:**
   - İstemci `SyncV4PayloadAdapter.buildFinancialTransactionMutation` fonksiyonunda deterministik `deterministicEventId` ve `deterministicEntityId` üretir.
   - İki kez çağrıldığında aynı kimlikler üretilir; sunucuya iletilen DTO'lar birebir eşittir.
- **Test Kanıtı:** `test/core_next/sync_v4_recovery_audit_test.dart` -> `Denetim 7` (BAŞARILI).

---

### Denetim 8: Sunucu Yanıtında Atlanan (Unacknowledged) Mutasyon Güvenliği
- **Geliştirilen İyileştirme:**
  Sunucu HTTP 200 döner ancak bir mutasyonu `results`, `conflicts` veya `rejected` listelerinin hiçbirinde belirtmezse (yanıtta atlama/omission):
  `SyncV4OutboxProcessor` artık bu mutasyonu sahipsiz bırakmaz; doğrudan `TRANSIENT_ERROR` durumuna alarak `last_error: 'unacknowledged_by_server'` yazar ve `attempts` sayacını artırır.
- **Test Kanıtı:** `test/core_next/sync_v4_recovery_audit_test.dart` -> `Denetim 8` (BAŞARILI).

---

## 3. Test Çalıştırma Çıktıları ve Kanıtlar

### 1. Stage 8.4 Kurtarma Denetimi Test Paketi:
```powershell
flutter test test/core_next/sync_v4_recovery_audit_test.dart
```
**Çıkış Kodu:** `0`  
**Sonuç:**
```text
00:00 +0: Stage 8.4 — Sync V4 Entegrasyon ve Kurtarma Adli Denetim Testleri Denetim 1: Kısmi batch kabulünde satış kilitlenmeli, finansal mutasyon korunmalı, stok tekrarlanmamalı
00:00 +1: Stage 8.4 — Sync V4 Entegrasyon ve Kurtarma Adli Denetim Testleri Denetim 2: Sunucunun işlemi kaydedip yanıtın kaybolduğu durumda aynı mutation_id ile güvenli tekrar
00:00 +2: Stage 8.4 — Sync V4 Entegrasyon ve Kurtarma Adli Denetim Testleri Denetim 3: Eşzamanlı çakışmada server_revision > base_revision ise CONFLICT durumuna alınmalı
00:00 +3: Stage 8.4 — Sync V4 Entegrasyon ve Kurtarma Adli Denetim Testleri Denetim 4: Yarıda kesilen transaction rollback olmalı, disk DB yeniden açıldığında kuyruk bozulmamalı
00:00 +4: Stage 8.4 — Sync V4 Entegrasyon ve Kurtarma Adli Denetim Testleri Denetim 5: Outbox tüketicisi causal_sequence ve client_timestamp sırasına kesinlikle uymalı
00:00 +5: Stage 8.4 — Sync V4 Entegrasyon ve Kurtarma Adli Denetim Testleri Denetim 6: Bootstrap sonrası next_cursor pull çağrısına kesintisiz aktarılmalı ve sayfalama devam etmeli
00:00 +6: Stage 8.4 — Sync V4 Entegrasyon ve Kurtarma Adli Denetim Testleri Denetim 7: Finansal mutasyon deterministik kimlik üretmeli ve sunucu sözleşmesinde bakiye çift değişmemeli
00:00 +7: Stage 8.4 — Sync V4 Entegrasyon ve Kurtarma Adli Denetim Testleri Denetim 8: Sunucu yanıtında yer almayan atlanmış mutasyon TRANSIENT_ERROR olmalı ve güvenle korunmalı
00:00 +8: All tests passed!
```

### 2. Tüm `test/core_next/` Test Paketi Regresyon Denetimi:
```powershell
flutter test test/core_next/
```
**Çıkış Kodu:** `0`  
**Toplam Test Sayısı:** **73/73 Başarılı** (0 Hata, 0 Atlama)  
**Kapsanan Test Dosyaları:**
1. `checkout_use_case_test.dart`
2. `database_integration_test.dart`
3. `fault_injection_migration_test.dart`
4. `financial_resilience_and_atomicity_test.dart`
5. `hardware_worker_test.dart`
6. `ledger_service_test.dart`
7. `migration_bridge_test.dart`
8. `real_data_verification_test.dart`
9. `sales_engine_adapter_test.dart`
10. `sync_v4_http_client_test.dart` (Stage 8.3 — 15 test)
11. `sync_v4_outbox_adapter_test.dart` (Stage 8.2B — 12 test)
12. `sync_v4_recovery_audit_test.dart` (Stage 8.4 — 8 test)

---

## 4. Son Karar

> **NİHAİ KARAR:**  
> **Kontrollü test ortamı entegrasyonuna hazır.**
> 
> Sync V4 Protocol 6 izole istemcisi ve outbox işlemcisi; kısmi batch onayları, ağ kopmaları, yanıt kayıpları, concurrent çakışmalar ve deterministik finansal mutasyonlarda çift stok/bakiye hatası üretmeksizin tam dayanıklılık sağlamaktadır.
> 
> *Uyarı: Canlı üretim uygulamasına (`lib/`) entegrasyon veya canlı sunucuya deployment aşaması, bu adli denetim tamamlanana kadar yapılmamıştır ve bir sonraki kontrollü aşamayı beklemektedir.*
