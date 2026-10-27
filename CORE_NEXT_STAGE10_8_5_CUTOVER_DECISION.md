# CORE NEXT — STAGE 10.8.5 CUTOVER DECISION
**Karar Tarihi:** 14 Ekim 2026  
**Aşama:** Stage 10.8.5 — Migration Completeness, Reverse-Rollback Proof & Cutover Safety  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  

---

## 1. Kesin Güvenlik Kapısı Kararı

### `LIVE_GATE: BLOCKED`
### Teknik İnceleme Kararı: `CONDITIONALLY_READY_FOR_ISOLATED_PILOT`

> **DİKKAT:** Canlı sisteme (production) doğrudan geçiş (live cutover), dağıtım (deploy), feature flag varsayılanını `true` yapma veya gerçek kullanıcı veritabanı üzerinde işlem yapma yetkisi **VERİLMEMİŞTİR**. Bu aşamadaki onay yalnızca **kontrollü ve izole pilot ortamı** için geçerlidir.

---

## 2. Kararın Gerekçeleri ve Tamamlanan Kanıtlar

| Kriter | Durum | Kanıt |
| :--- | :--- | :--- |
| **Veri Taşıma Kapsamı** | **TAMAMLANDI** | `users`, `categories`, `products`, `customers`, `sales`, `sale_items`, `sale_payments`, `ledger_entries`, `sync_events` tabloları tam kapsamlı ve yabancı anahtarlarla taşınmaktadır. |
| **Parasal Hassasiyet & Mutabakat** | **TAMAMLANDI** | Kuruş hassasiyeti (0 tolerans), 0.01 TL, 0.1+0.2 kayan nokta aritmetiği, yüksek tutarlar ve negatif bakiyeler `(val * 100).round()` ile %100 doğrulanmıştır. |
| **Tersine Dönüş (Rollback) Güvenliği** | **TAMAMLANDI** | `ReverseMigrationEngine` geliştirildi ve test edildi. Core Next'te yapılan yeni satışlar, azalan stoklar, değişen cari bakiyeleri ve bekleyen outbox kayıtları eski şemaya kayıpsız aktarılmaktadır. |
| **Hata İzolasyonu & Atomiklik** | **TAMAMLANDI** | Tüm taşıma ve geri alma adımları SQLite `transaction` koruması altındadır. Süreç ortasında hata enjekte edildiğinde veritabanı kirli kayıt bırakmadan geri dönmektedir. |
| **İdempotency & Tekrar Çalışabilirlik** | **TAMAMLANDI** | Motorun ikinci ve üçüncü kez çalıştırılması mükerrer fiş, satış veya cari oluşturmamaktadır. |
| **SQLite Bütünlüğü** | **TAMAMLANDI** | `PRAGMA integrity_check` -> `ok`, `PRAGMA foreign_key_check` -> 0 ihlal. |
| **Test Kapsamı** | **TAMAMLANDI** | 213 benzersiz testin tamamı (191 core_next, 9 UI, 13 services) yeşil/başarılıdır. |

---

## 3. Canlı Geçiş Öncesi Zorunlu Koşullar (Prerequisites for Live Cutover)

Canlı cutover yapılabilmesi için aşağıdaki koşulların bağımsız bir pilot çalışmayla yerine getirilmesi şarttır:

1. **Tek Bir Cihazda İzole Pilot:**
   - Seçilen bir pilot terminalde, gerçek kullanıcının günlük iş akışını bozmadan izole bir veri kopyasıyla çalışılmalıdır.
2. **Canlı Outbox Senkronizasyon Onayı:**
   - Core Next Protocol 6 sunucusu ile senkronizasyonun canlı VPS ortamında çift taraflı (Push/Pull) watermark bazlı sorunsuz aktığı doğrulanmalıdır.
3. **Yedekleme ve Geri Dönüş Talimatnamesi:**
   - Saha personeli için `ReverseMigrationEngine` komutunu içeren acil durum geri dönüş runbook'u hazır bulundurulmalıdır.
4. **Feature Flag Kontrolü:**
   - `coreNextSalesEngineEnabledProvider` varsayılan değeri `false` olarak kalmalı, yalnızca pilot terminalinde konfigürasyonla açılmalıdır.

---

## 4. Sonuç ve Özet

Stage 10.8.5, Serenut OS Core Next mimarisinin en kritik gereksinimlerinden olan **tam kapsamlı veri migrasyonunu**, **çift yönlü geri dönüş (Reverse Rollback) güvencesini** ve **sıfır toleranslı parasal mutabakatını** teknik olarak kanıtlamıştır.

Sistem, izole pilot aşamasına geçiş için hazır olup; canlı üretim geçiş kapısı (`LIVE_GATE`) güvenlik prensipleri gereğince **BLOCKED** olarak korunmaktadır.
