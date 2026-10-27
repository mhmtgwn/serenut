# CORE NEXT — STAGE 10.8.7 SYNC CUTOVER POLICY
**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.8.7 — Senkronizasyon Kuyruğu ve Kesintisiz Geçiş Politikası  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Referans Test Dosyası:** [stage10_8_7_remediation_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_7_remediation_test.dart) (Test 3)

---

## 1. Outbox Durum Tanımları ve Anlamları (Kaynak Kod Analizi)

Kaynak kod (`schema_definitions.dart`, `sync_v4_outbox_processor.dart`, `sync_v4_pull_ingestion_service.dart`):

| Durum (`state` / `sync_state`) | Kaynak Kod Anlamı | Sunucu Tarafı Durumu | Veri Kaybı Riski |
| :--- | :--- | :--- | :--- |
| **`PENDING`** | Yerel kuyruğa yazılmış, henüz sunucuya gönderilmemiş mutasyon. | Sunucuda henüz YOK. | **YÜKSEK**: Taşınmazsa yerel satış/stok verisi sunucuya asla ulaşmaz. |
| **`IN_FLIGHT`** | İstemci HTTP POST isteğini başlattı; ağ üzerinde veri uçuşta veya yanıt henüz istemciye ulaşmadı/işlenmedi. | **BELİRSİZ**: Sunucuya ulaşıp DB'ye yazılmış olabilir, ağ kesilmiş olabilir veya henüz ulaşmamış olabilir. | **KRİTİK**: Çoğu naif migration bu durumu terk eder ve sunucuya yazılmamış mutasyonlar sessizce kaybolur. |
| **`TRANSIENT_ERROR`** | Ağ zaman aşımı (timeout), 5xx sunucu hatası veya geçici bağlantı kopması nedeniyle işlem başarısız oldu; retry kuyruğunda bekliyor. | Sunucuda YOK (veya 500 anında yarıda kaldı). | **YÜKSEK**: Taşınmazsa retry döngüsü sonlanır ve mutasyon terk edilir. |
| **`SYNCED`** | Sunucudan 200 OK alındı; `server_revision` ve onay yerel veritabanına işlendi. | Sunucuda MEVCUT. | **YOK**: Zaten sunucuda kesinleştiğinden hedef outbox'a taşınmasına gerek yoktur. |
| **`REJECTED`** | 4xx İstemci/İş kuralı hatası veya kalıcı reddedilme. Retry edilmez. | Sunucuda REDDEDİLDİ. | İşlem tamamlanmıştır, yeniden gönderilmez. |
| **`CONFLICT`** | Çift taraflı çakışma oluştu; çözüm kuyruğunda bekliyor. | İnceleme altında. | Manuel veya otomatik çözüm kuralına tabidir. |

---

## 2. Güvenli Cutover Politikası (Fail-Closed Zero Data Loss)

### Kural: Onaylanmamış Tüm Mutasyonlar Hedefe Taşınır
Cutover veya rollback anında, sunucudan nihai onay (`SYNCED`) almamış **herhangi bir mutasyon** geride bırakılamaz:
```sql
WHERE sync_state IN ('PENDING', 'IN_FLIGHT', 'TRANSIENT_ERROR')
```

### Durum Dönüşüm ve Normalizasyon Tablosu

| Kaynak Durumu (Cutover Anı) | Hedef Durumu (`sync_events` / `sync_outbox_v4`) | Gerekçe ve Güvenlik Mekanizması |
| :--- | :--- | :--- |
| **`PENDING`** | **`PENDING`** | Normal akış; yeni motor ilk senkronizasyon döngüsünde sunucuya iletir. |
| **`IN_FLIGHT`** | **`PENDING`** (Reset) | Yanıt belirsiz kaldığından `attempts` korunarak durum `PENDING`'e çekilir. Protocol 6 sunucusu `mutation_id` üzerinden idempotent olduğundan, eğer istek sunucuya daha önce ulaştıysa sunucu mükerrer işlem yapmaz, `200 OK` dönerek olayı onaylar. Ulaşmadıysa normal biçimde işler. |
| **`TRANSIENT_ERROR`** | **`PENDING`** (Retry devam) | Önceki hata metni (`last_error`) ve deneme sayısı (`attempts`) korunarak yeni motora devredilir. |

---

## 3. Idempotency ve Uçuşta Kalan İsteklerin Belirsizliği Çözümü

### Senaryo: Uçuşta Kalan İstek (Network Partition / Crash)
1. İstemci `mut-001` nolu satış mutasyonunu sunucuya gönderir. Durum `IN_FLIGHT` yapılır.
2. Sunucu isteği alır, PostgreSQL veritabanına yazar ve 200 OK yanıtı döner.
3. Ancak tam bu milisaniyede istemcide elektrik kesilir, uygulama çöker veya cutover tetiklenir. İstemci 200 OK yanıtını yerel SQLite'a işleyemez; satır `IN_FLIGHT` olarak kalır.
4. **Cutover Çalışır:**
   - Güvenli Cutover Politikası gereği `mut-001` terk edilmez; Core Next `sync_events` tablosuna `event_id = 'mut-001'`, `sync_state = 'PENDING'` olarak taşınır.
5. **Core Next Senkronizasyonu Başlatır:**
   - Core Next outbox processor `mut-001`'i sunucuya tekrar gönderir.
6. **Sunucu Yanıtı (Protocol 6 Idempotency Guard):**
   - Sunucu `event_id / mutation_id` tekilliğini kontrol eder.
   - Bu mutasyonun daha önce uygulandığını görür.
   - İşlemi **tekrar uygulamaz** (stok düşmez, çift satış kaydı oluşturmaz).
   - Başarılı olduğunu belirten aynı idempotency onayını (`status: 'ALREADY_APPLIED'` veya `200 OK`) döner.
7. **Sonuç:** İstemci `sync_events` satırını güvenle `SYNCED` yapar. **Veri kaybı: 0, Mükerrer kayıt: 0.**

---

## 4. Olay Bütünlüğü ve Sıralama Garantileri

Migration esnasında aşağıdaki alanlar %100 birebir korunur:
- **`event_id` / `mutation_id`:** Orijinal UUID veya istemci mutasyon anahtarı asla değiştirilmez; sunucu idempotency koruması bu anahtara bağlıdır.
- **`causal_sequence`:** Legacy outbox'taki `id` (otomatik artan sıra) Core Next'teki `causal_sequence` alanına aktarılır; mutasyonların istemcideki oluşum sırası bozulmaz.
- **`payload_json`:** Satış, stok ve müşteri nesnelerinin tam JSON içeriği değişmeden taşınır.
- **`attempts`:** Deneme sayısı sıfırlanmaz; böylece sonsuz döngü koruması (dead-letter queue) aktif kalır.
- **`client_timestamp`:** Olayın gerçekleştiği orijinal milisaniye zaman damgası korunur.

---

## 5. Doğrulama ve Test Kanıtı

[stage10_8_7_remediation_test.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_7_remediation_test.dart) (Test 3):
- Legacy outbox'a 3 adet mutasyon yerleştirilmiştir:
  - 1x `PENDING` (`mut-pend`)
  - 1x `IN_FLIGHT` (`mut-flight`)
  - 1x `TRANSIENT_ERROR` (`mut-transient`)
- Migration çalıştırılmış ve Core Next `sync_events` tablosunda 3 mutasyonun tamamının eksiksiz yer aldığı, durumlarının güvenle `PENDING` olarak normalize edildiği ve orijinal `mutation_id` değerlerinin korunduğu doğrulanmıştır.
