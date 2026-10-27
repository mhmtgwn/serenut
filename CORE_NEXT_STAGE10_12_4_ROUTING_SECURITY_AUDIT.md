# SERENUT OS — STAGE 10.12.4: VERİTABANI YÖNLENDİRME GÜVENLİK VE İZOLE TEST RAPORU

**Tarih:** 16 Ekim 2026  
**Aşama:** Stage 10.12.4  
**Çalışma Alanı:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Amaç:** `DatabaseRoutingResolver` bileşeni üzerinden 12 zorunlu yönlendirme ve fail-safe senaryosunu izole ortamda doğrulamak; canlıya geçiş öncesi güvenlik kanıtlarını tamamlamak.  

---

## 1. GİT VE ÇALIŞMA AĞACI DURUMU

- **Commit HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Aktif Branch:** `main`
- **Sözdizimi / Format (`git diff --check`):** Temiz (0 hata).
- **Mutlak Güvenlik Sınırları:**
  - Canlı AppData veritabanı (`serenut_pos.db`) üzerinde hiçbir yazma, silme veya taşıma **yapılmamıştır**.
  - `core_next/nutopia_pos.db` dosyası aktif üretim veritabanı **yapılmamıştır**.
  - `coreNextSalesEngineEnabledProvider = false` **kapalı** tutulmuştur.
  - Canlı Erkul PostgreSQL bulut verisine **dokunulmamıştır**.
  - `DatabaseManager` üretim kodunda henüz hiçbir değişiklik **yapılmamıştır**.

---

## 2. ÖNCEKİ TEST DÜZELTMESİNİN DENETİMİ (GÖREV 1)

Stage 10.12.3'te `test/core_next/sync_v4_outbox_adapter_test.dart` dosyasının 270. satırında yapılan `(product.first['stock_quantity'] as num).toInt()` düzeltmesi denetlenmiştir:
- **Sonuç:** Test dosyasındaki düzeltme, SQLite FFI'den gelen `REAL/double` tipini güvenle karşılamaktadır.
- **5 Test Paketinin Toplu Doğrulaması:**
  ```text
  flutter test test/core_next/sync_v4_outbox_adapter_test.dart \
               test/core_next/sync_v4_recovery_audit_test.dart \
               test/core_next/stage10_8_12_financial_reconciliation_audit_test.dart \
               test/core_next/stage10_7_3_pull_worker_test.dart \
               test/core_next/stage10_12_1_migration_rehearsal_test.dart
  00:27 +42: All tests passed! (42/42 PASS, 0 Hata)
  ```
- **Üretim Koduna Etkisi:** Sıfır (Yalnızca test dosyası güncellenmiştir).

---

## 3. GÜÇLENDİRİLMİŞ TRIPLE-CHECK TASARIMI (GÖREV 2)

Veritabanı yönlendirmesi yalnızca dosya adına veya boyutuna dayandırılmamış; 6 katmanlı mutlak güvenlik kuralları (`DatabaseRoutingResolver`) getirilmiştir:

1. **Kalıcı Tenant ID Doğrulaması:**
   Açılmak istenen hedef DB içindeki `app_settings` tablosundaki `tenant_id` değeri ile istenen işletmenin kimliği birebir eşleşmelidir. Eşleşmezse işlem fail-closed olarak durdurulur.
2. **Şema Sürüm Kontrolü:**
   Hedef dosyanın `PRAGMA user_version` değeri kesin olarak `3` (Core Next v3) olmalıdır. Eski veya yanlış şemalar reddedilir.
3. **SQLite Bütünlük ve Yabancı Anahtar Kontrolü:**
   `PRAGMA integrity_check == 'ok'` ve `PRAGMA foreign_key_check` 0 ihlal vermelidir.
4. **Göç Durumu Doğrulaması:**
   `CoreNextMigrationState.completed` kaydedilmemişse hedef DB asla seçilmez; güvenli legacy dosya açılır.
5. **Kritik Tabloların Varlığı:**
   `products`, `customers`, `sales`, `ledger_entries`, `sync_events` tablolarının tamamı hedefte bulunmalıdır.
6. **Boş Dosya Yaratılmasının Engellenmesi:**
   Hedef dosya diskte fiziksel olarak yoksa veya < 512 bayt ise SQLite'ın sıfırdan boş dosya oluşturması engellenir; otomatik olarak mevcut `serenut_pos.db` dosyası açılır.

---

## 4. FAİL-SAFE VE SESSİZ GERİ DÖNÜŞ (ROLLBACK) KORUMASI (GÖREV 3)

### Kritik Risk: Yeni DB'ye Yazım Başladıktan Sonra Geri Dönüş
Eski sisteme otomatik geri dönmenin en tehlikeli tarafı:
*Eğer yeni veritabanına geçildikten sonra kasada 1 dahi satış yapılırsa ve sistem herhangi bir hata anında sessizce eski `serenut_pos.db` dosyasına dönerse, yeni yapılan satış görünmez olur, bakiye sapar ve senkronizasyonda mükerrerlik oluşur.*

### Çözüm ve Kural (Post-Write Rollback Lock):
- `DatabaseRoutingResolver.assertSafeRollback` metodu uygulanmıştır:
- Hedef veritabanında geçiş sonrasında (`created_at > cutoverTimestamp`) tek bir yeni kayıt dahi oluşmuşsa, **otomatik veya sessiz geri dönüş KESİNLİKLE YASAKLANMIŞTIR.**
- Bu durumda sistem sessizce eski dosyaya geçmek yerine açık bir **`UnsafeRollbackException`** fırlatarak yazmayı durdurur ve operatöre bildirir.

---

## 5. İZOLE ROUTING TESTLERİ VE GERÇEK ÇIKTILAR (GÖREV 4)

`test/core_next/database_routing_test.dart` test paketi 12 senaryonun tamamını izole geçici veritabanları üzerinde gerçek `DatabaseRoutingResolver` bileşenini çağırarak test etmiştir:

```text
flutter test test/core_next/database_routing_test.dart
00:00 +0: 1. Doğru tenant ID ve doğrulanmış hedef DB başarıyla seçilmelidir [PASS]
00:00 +1: 2. Eksik hedef dosya varsa ASLA boş DB açılmamalı, legacy açılmalıdır [PASS]
00:00 +2: 3. Bozuk veya sıfır baytlık hedef DB fail-closed ile reddedilmelidir [PASS]
00:00 +3: 4. Yanlış tenant ID tespit edildiğinde hedef dosya reddedilmelidir [PASS]
00:00 +4: 5. Hedef DB şema sürümü Core Next v3 değilse reddedilmelidir [PASS]
00:00 +5: 6. Migration durumu tamamlanmadıysa (inProgress) hedef dosya seçilmemelidir [PASS]
00:00 +6: 7. İşletme adı aynı olsa bile Tenant ID farklıysa hedef reddedilmelidir [PASS]
00:00 +7: 8. İki farklı işletme için izole ve farklı DB yolları çözülmelidir [PASS]
00:00 +8: 9. Aktarım sırasında kapanış veya kilit durumunda legacy fallback çalışmalıdır [PASS]
00:00 +9: 10. Yeni DB ye işlem yazıldıktan sonra sessiz geri dönüş UnsafeRollbackException fırlatmalıdır [PASS]
00:00 +10: 11. Hedef DB kapatılıp yeniden açıldığında tutarlılık korunmalıdır [PASS]
00:00 +11: 12. Outbox mutasyonları ve idempotency anahtarları korunmalıdır [PASS]
00:00 +12: All tests passed! (12/12 PASS, Çıkış Kodu: 0)
```

### Senaryo Denetim Matrisi

| Senaryo No | Test Edilen Durum | Beklenen Sonuç | Gerçekleşen Sonuç | Statü |
| :---: | :--- | :--- | :--- | :---: |
| **1** | Doğru Tenant ID + Doğrulanmış Hedef DB | `targetSelected` (nutopia_valid_target.db) | `targetSelected` | **PASS** |
| **2** | Eksik Hedef Dosya | Boş dosya açılmaz, `legacyFallback` | `legacyFallback` (0 bayt dosya oluşmadı) | **PASS** |
| **3** | Bozuk SQLite Dosyası | `blockedFailClosed` | `blockedFailClosed` | **PASS** |
| **4** | Yanlış Tenant ID (`tenant-erkul-02` vs `nutopia`) | Fail-closed blokajı | `blockedFailClosed` (Tenant mismatch) | **PASS** |
| **5** | Yanlış Şema Sürümü (`user_version = 1`) | Fail-closed blokajı | `blockedFailClosed` (Version mismatch) | **PASS** |
| **6** | Yarım Kalan Aktarım (`completed = false`) | `legacyFallback` | `legacyFallback` | **PASS** |
| **7** | İsim Aynı Fakat Tenant ID Farklı | İsim yanıltması engellenir | `blockedFailClosed` | **PASS** |
| **8** | Çift İşletme Aynı Cihazda | İzole dosya ayrımı | İki ayrı izole yol çözüldü | **PASS** |
| **9** | Çökme / Kesinti Durumu | Güvenli legacy fallback | `legacyFallback` | **PASS** |
| **10** | İlk Yazım Sonrası Geri Dönüş | `UnsafeRollbackException` fırlatılır | `UnsafeRollbackException` fırlatıldı | **PASS** |
| **11** | DB'nin Kapanıp Yeniden Açılması | Bütünlük ve tenant korunur | Başarıyla yeniden açıldı | **PASS** |
| **12** | Outbox ve İdempotency Korunumu | `sync_events` mutasyon sırası tam | Causal sequence = 1 korundu | **PASS** |

---

## 6. UYGULAMA ÖNCESİ İNCELEME VE KALAN RİSKLER (GÖREV 5)

1. **`DatabaseManager` Üretim Kodu:**  
   Bu aşamada `lib/infrastructure/database/database_provider.dart` dosyasına dokunulmamış; yönlendirme mantığı bağımsız `DatabaseRoutingResolver` bileşeninde izole olarak test edilmiştir.
2. **Kalan Tek Somut Ön Koşul:**  
   AppData altındaki hedef `databases\core_next\nutopia_pos.db` dosyası, Stage 10.12.1'de provası tamamlanan sıfır sapmalı motor ile yenilenmelidir. Bu dosya hazır olduğunda `DatabaseRoutingResolver` güvenle devreye sokulabilir.

---

## 7. NİHAİ KARAR

Stage 10.12.4 kapsamındaki tüm güvenlik gereksinimleri ve 12 izole routing senaryosu **eksiksiz olarak karşılanmış ve doğrulanmıştır (`PASS`).**

Canlı sistemde hiçbir veritabanı taşınmamış, feature flag açılmamış ve satış yapılmamıştır. Sonraki aşama için kullanıcı onayı beklenmektedir.
