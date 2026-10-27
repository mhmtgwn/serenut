# SERENUT OS — STAGE 10.8.11 SYNC INTEGRITY REPORT
## Senkronizasyon Bütünlüğü, Outbox Ayrışması ve Tekil Akış Raporu

**Tarih:** 2026-10-15  
**Kapsam:** `sync_events` vs `sync_outbox_v4`, `SyncV4PullWorker`, Tekilleştirme, Yeniden Deneme (Retry Backoff) ve Çevrimdışı Kuyruk.

---

## 1. SENKRONİZASYON SORUNUNUN TESPİTİ VE ÇÖZÜMÜ

Stage 10.8.10 raporunda tespit edilen senkronizasyon ayrışması şuydu:
- UI'daki senkronizasyon tetikleyicisi (`syncProvider.triggerSync`) eski `SyncService`'i çalıştırıyor ve `sync_outbox_v4` tablosunu işliyordu.
- Core Next satış motoru ise olayları `sync_events` tablosuna yazıyor ve `SyncV4PullWorker` ile haberleşiyordu.

### Stage 10.8.11 İle Sağlanan Mimari Düzenleme:
1. `lib/providers/sync_provider.dart` içine `coreNextSyncExecutorProvider` tanımlandı.
2. `triggerSync()` metodu, Core Next modu devrede olduğunda `coreNextSyncExecutorProvider`'ı çağıracak şekilde güncellendi.
3. Böylece:
   - Core Next modunda iken legacy outbox tablosu tetiklenmez.
   - Aynı ticari olay (satış/iade/tahsilat) hem legacy hem Core Next outbox'ı tarafından sunucuya iki kez fırlatılamaz (Zero Double Emit).
   - Core Next modunda yapılan çevrimdışı satışlar `sync_events` tablosunda `sync_state = 'PENDING'` olarak tutulur ve bağlantı sağlandığında atomik olarak iletilir.

---

## 2. SENKRONİZASYON SÖZLEŞMELERİ VE GÜVENCELER

### 2.1. Olay Tekilleştirme (Duplicate Prevention)
- Core Next `sync_events` tablosunda `event_id` birincil anahtardır (`PRIMARY KEY` / `UNIQUE`).
- Ağ gecikmesi veya bağlantı kopması nedeniyle sunucudan aynı olay tekrar geldiğinde veya yerel kuyruğa aynı event_id ile ekleme yapıldığında `ConflictAlgorithm.ignore` devreye girer.
- Test Senaryosu 11 ile doğrulanmıştır: Aynı event_id iki kez kuyruğa eklendiğinde `COUNT(*)` 1 kalır; mükerrer işleme engellenir.

### 2.2. Hata Kuyruğu ve Yeniden Deneme (Retry Backoff)
- Sunucu geçici bir hata verdiğinde (500 Internal Server Error veya bağlantı zaman aşımı), olay silinmez.
- `sync_state` durumu `TRANSIENT_ERROR` olarak güncellenir ve `attempts` sayacı 1 artırılır.
- Son hata mesajı `last_error` alanına kaydedilerek görünürlük sağlanır.
- Test Senaryosu 12 ile doğrulanmıştır: Geçici hata durumunda `sync_state = TRANSIENT_ERROR` ve `attempts = 1` kaydı diskte korunur.

### 2.3. Çevrimdışı Satış ve Outbox Entegrasyonu
- Satış onaylandığı anda `sales`, `sale_items`, `sale_payments` ve `sync_events` kayıtları aynı SQLite transaction içinde oluşturulur.
- Satış başarılı olup senkronizasyon kuyruğunun oluşmaması veya senkronizasyon oluşup satışın kaydedilmemesi gibi yarım durumlar imkansızdır.
- Test Senaryosu 10 ile doğrulanmıştır: Çevrimdışı yapılan satış sonrasında `sync_events` tablosunda ilgili `s-off-1` kaydı `PENDING` olarak hazır bulunur.

---

## 3. BAĞIMSIZ TEST DOĞRULAMA KANITLARI

| Test No | Senaryo | Doğrulanan Kural | Sonuç |
|---|---|---|---|
| **Senaryo 10** | Çevrimdışı Satış & Outbox | Satış tamamlandığında `sync_events` kaydının atomik oluşumu | **BAŞARILI (1 kayıt, PENDING)** |
| **Senaryo 11** | Çift Olay Engeli (Duplicate) | Aynı event_id'nin iki kez işlenmesi | **BAŞARILI (Kayıt sayısı = 1)** |
| **Senaryo 12** | Hata ve Yeniden Deneme | Ağ hatası simülasyonu ve attempts artırımı | **BAŞARILI (attempts = 1, TRANSIENT_ERROR)** |
