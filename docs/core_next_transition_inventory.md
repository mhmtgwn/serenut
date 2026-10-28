# Serenut OS — Core Next Geçiş Envanteri ve Kalan İşler Matrisi

**Tarih:** 29 Ekim 2026  
**Doküman Sürümü:** 1.0.0  
**İlgili P0 Görevi:** `docs/architecture-todo.md` ("Geçiş envanteri: hangi tablolar CoreNext katmanından, hangileri eski db_schema.dart katmanından çalışıyor; kalan işi çıkar.")

---

## 1. Genel Mimari Durum ve Çift Veritabanı Modeli

Serenut OS, veri güvenliğini garanti altına almak için **Fail-Closed Dual-Database Routing** modeliyle çalışmaktadır:
- **Legacy Katmanı (`serenut_pos.db` - schemaVersion: 61):** Doğrudan SQLite gateway (`DbGatewayImpl` / `DatabaseManager`) üzerinden çalışan geleneksel mimari.
- **Core Next Katmanı (`serenut_core_v2.db` - schemaVersion: 3):** Event-driven, kesin hesap defteri (`ledger_entries`) odaklı, immutability ve outbox senkronizasyonunu çekirdekte barındıran modern mimari (`CoreAppDatabase`).
- **Yönlendirme Koordinatörü (`DualDatabaseRoutingCoordinator` & `PilotCutoverGate`):** Sadece pilot bayrağı açık, tam veri bütünlüğü sağlanmış ve veri paritesi doğrulanmış (`customers` sayısı hedefte eksik olmayan) durumlarda hedef Core Next repository override'larını devreye alır; aksi durumda sistem %100 güvenli şekilde Legacy akışta çalışır.

---

## 2. Tablo Envanteri: Core Next vs Legacy

| # | Tablo Adı | Legacy (`db_schema.dart`) | Core Next (`schema_definitions.dart`) | Durum / Eşleşme Analizi |
|---|-----------|:-------------------------:|:-------------------------------------:|-------------------------|
| 1 | `users` | Var | Var | **Eşit:** Kimlik ve yetki tablosu. |
| 2 | `categories` | Yok (üründe kolon) | Var | Core Next kategorileri bağımsız normalize tabloya almıştır. |
| 3 | `products` | Var | Var | **Eşit:** Çift yönlü çalışabilmektedir. |
| 4 | `customers` | Var | Var | **Eşit:** Çift yönlü parite kontrolüyle senkronize edilmektedir. |
| 5 | `sales` | Var | Var | **Eşit:** Satış üst bilgisi. |
| 6 | `sale_items` | Var | Var | **Eşit:** Satış kalemleri. |
| 7 | `sale_payments` | Yok (alanlar `sales` içinde) | Var | Core Next çoklu ödeme tiplerini ayrık tabloda tutar. |
| 8 | `financial_transactions` | Var | Yok (Deftere dönüştü) | Core Next'te yerini `ledger_entries` tablosuna bırakmıştır. |
| 9 | `ledger_entries` | Yok | Var | Core Next'in append-only finansal defter çekirdeği. |
| 10 | `installments` / `customer_installments` | Var | Var | Taksit planları ve vadeler her iki tarafta mevcuttur. |
| 11 | `customer_installment_plans` | Var | Var | Taksit üst plan tablosu. |
| 12 | `cash_transactions` | Yok | Var | Kasa giriş-çıkışları `cash_transactions` ile izlenir. |
| 13 | `cash_expenses` | Var | Var | Masraf kayıtları. |
| 14 | `cash_counts` | Var | Var | Gün sonu kasa sayımları. |
| 15 | `sync_events` / `sync_outbox_v4` | `sync_outbox_v4` | `sync_events` | Core Next senkronizasyon outbox tablosudur. |
| 16 | `sync_applied_events` | `sync_cursor_v4` | `sync_applied_events` | Gelen sync olaylarının idempotency kaydı. |
| 17 | `sync_quarantine_v4` | Var | Yok (Henüz CN'e taşınmadı) | Hatalı sync payload'larının izolasyon karantinası. |
| 18 | `app_settings` / `settings` | `settings` | `app_settings` | Core Next key-value KV store kullanır. |
| 19 | `orders` | Var | Var | Sipariş başlığı (Core Next şemasında mevcut). |
| 20 | `order_items` | Var | Var | Sipariş kalemleri. |
| 21 | `order_number_sequence` | Var | Var | Günlük sipariş numarası üreteci. |
| 22 | `refunds` / `refund_items` | Var | `sales` / `ledger_entries` | Core Next'te iadeler negatif defter ve satış hareketiyle izlenir. |
| 23 | `audit_events` | Var | Var | İşlemsel denetim logları. |
| 24 | `stock_movements` | Yok (sadece ürün adedi) | Var | Core Next ürün stok giriş/çıkış/sayım hareket defteri. |
| 25 | `branches` | Yok | Var | Çoklu şube desteği. |
| 26 | `terminal_payment_intents` | Var | Var | POS terminal ödeme talepleri. |
| 27 | `warehouses` | Var | **Eksik** | Fındık/emtia depoları (Sadece Legacy katmanında). |
| 28 | `customer_hazelnut_escrow` | Var | **Eksik** | Emanet fındık hesapları (Sadece Legacy katmanında). |
| 29 | `warehouse_hazelnut_movements` | Var | **Eksik** | Depo fındık transferleri (Sadece Legacy katmanında). |
| 30 | `hazelnut_price_cuts` | Var | **Eksik** | Emanet fiyat kesim işlemleri (Sadece Legacy katmanında). |
| 31 | `print_queue`, `print_jobs`, `printer_*` | Var | **Eksik** | Donanım ve yazıcı kuyruk tabloları. |
| 32 | `sms_logs` | Var | **Eksik** | SMS bildirim ve gateway logları. |
| 33 | `business_profile`, `trial_anchor` | Var | `app_settings` | Lisans ve firma profili KV store içinde tutulabilir. |

---

## 3. Katman ve Servis Dağılımı (Repository & Controller Durumu)

### A. Core Next Üzerinden Çalışanlar (Pilot Açıkken Devreye Girenler)
1. **Müşteri Yönetimi:** `CoreNextCustomerRepository` (`customers` tablosu)
2. **Ürün ve Fiyat Yönetimi:** `CoreNextProductRepository` (`products` tablosu)
3. **Finansal Bakiye ve Hareketler:** `CoreNextFinancialTransactionRepository` (`ledger_entries` tablosu)
4. **Satış Motoru (Sales Engine Flag Açıkken):**
   - `CoreNextSaleRepository`
   - `CoreCheckoutUseCase`
   - `CoreRefundUseCase`
   - `SalesEngineAdapter` / `CoreSalesFlowNotifier`
   - `SyncV4OutboxProcessor` & `SyncV4PullIngestionService`

### B. Halen Legacy Katmanından (`db_schema.dart`) Çalışanlar
1. **Sipariş Motoru:** `orders_controller.dart` ve `SqliteOrderRepository` (Core Next'te tablolar hazır, repo henüz override'a bağlanmadı).
2. **Fındık & Emanet Yönetimi:** `SqliteHazelnutRepository` (Depolar, emanet hesapları, fındık hareketleri, fiyat kesimleri).
3. **Kasa / Masraf Ekranları:** `SqliteCashRepository` (Legacy kasa tabloları üzerinden çalışır).
4. **Yazıcı Kuyruğu & Donanım:** `PrintingEngine`, `print_queue`, `printer_devices`.
5. **SMS Servisi:** `SmsService`, `sms_logs`.
6. **Kullanıcı & Giriş:** `SqliteUserRepository` (Giriş doğrulaması Legacy `users` tablosundan yapılır).
7. **Sistem Ayarları:** `SqliteSettingsRepository` (`settings` tablosu).

---

## 4. Kalan İş Çıkarımı (Backlog & Roadmap)

Core Next'e %100 geçişin tamamlanması ve legacy katmanının emekliye ayrılması için tamamlanması gereken işler:

1. **İş Paketi 1 — Sipariş Katmanının Core Next'e Bağlanması:**
   - Core Next şemasında mevcut olan `orders`, `order_items` ve `order_number_sequence` tabloları için `CoreNextOrderRepository` hazırlanması.
   - `DualDatabaseRoutingCoordinator.createRepositoryOverrides` içine sipariş repo override'ının eklenmesi.
2. **İş Paketi 2 — Fındık ve Depo Tablolarının Core Next Şemasına Eklenmesi:**
   - `warehouses`, `customer_hazelnut_escrow`, `warehouse_hazelnut_movements` ve `hazelnut_price_cuts` tablolarının `schema_definitions.dart` içine eklenmesi (Core Next migration v4).
   - Core Next tarafında `CoreNextHazelnutRepository` oluşturulması veya legacy repo'nun çift yönlü DB adapter ile donatılması.
3. **İş Paketi 3 — Yazıcı Kuyruğu ve Donanım Katmanının İzolasyonu:**
   - Yazıcı kuyruğunun (`print_queue`, `print_jobs`) veritabanı bağımlılığının bellek içi kuyruk (in-memory persistent queue) veya KV store ile soyutlanması.
4. **İş Paketi 4 — Ayarlar ve Lisans KV Store Göçü:**
   - `settings` tablosundaki konfigürasyon alanlarının `app_settings` KV tablosuna dinamik eşlenmesi.
5. **İş Paketi 5 — Tam Kesim (Final Cutover Gate):**
   - Tüm tablolar Core Next'e aktarıldığında Legacy katmanının read-only arşive alınması (`LegacyDatabaseRetirementPolicy`).
