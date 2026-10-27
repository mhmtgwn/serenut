# CORE NEXT — STAGE 10.8.5 REVERSE ROLLBACK REPORT
**Rapor Tarihi:** 14 Ekim 2026  
**Aşama:** Stage 10.8.5 — Reverse Rollback Proof & Disaster Recovery  
**Uygulanan Motor:** `ReverseMigrationEngine` (`core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart`)  
**Doğrulama Testi:** `test/core_next/stage10_8_5_reverse_rollback_test.dart` (Test 3)  
**Karar:** Geri Dönüş Mekanizması Kanıtlandı — Veri Kayıpsız Reverse Sync Mümkündür.

---

## 1. Neden Basit Dosya Geri Yüklemesi (File Restore) Yetersiz ve Tehlikelidir?

Canlı geçiş (cutover) yapıldıktan sonra sistem Core Next (`serenut_core_v2.db`) üzerinde çalışmaya başlar. Kullanıcılar yeni satışlar yapar, müşterilere veresiye borç yazılır, ödemeler alınır ve stoklar eksilir.

Eğer sistemde bir operasyonel sorun çıkıp eski sisteme (`serenut_pos.db`) geri dönülmesi gerekirse:
- **Tehlikeli Yanılgı:** Geçişten önceki `serenut_pos.db.backup` dosyasını kopyalayarak eski sistemi açmak.
- **Kritik Sonuç:** Cutover anı ile geri dönüş anı arasında yapılan **TÜM YENİ SATIŞLAR, CARİ TAHSİLATLAR, VERESİYE BORÇLARI VE STOK HAREKETLERİ TAMAMEN SİLİNİR**.
- **Mali Kayıp:** Bu durum adli muhasebe açısından **kurtarılamaz veri kaybı ve finansal mutabakat çöküşüdür**.

Bu nedenle Serenut OS mimarisinde basit dosya geri yüklemesi bir rollback çözümü olarak kabul edilmez.

---

## 2. Geliştirilen Çözüm: `ReverseMigrationEngine`

`ReverseMigrationEngine.rollbackToLegacy(Database legacyDb, CoreAppDatabase coreDb)` metodu, Core Next üzerinde geçen süre boyunca üretilen yeni verileri geriye dönük olarak eski SQLite (v60) şemasına aktarır:

1. **Yeni Satışların Tespiti ve Aktarımı:**
   - `coreDb`'de olup `legacyDb.sales` tablosunda bulunmayan yeni satışlar tespit edilir.
   - Kuruş tamsayıları `total_cents / 100.0`, `paid_cents / 100.0` ve `discount_cents / 100.0` ile double alanlara; `total_cents` ile minor integer alanlara yazılır.
   - Satışın kalemleri (`sale_items`) aynı şekilde miktarları ve birim fiyatlarıyla legacy `sale_items` tablosuna aktarılır.
   - Legacy `sales.customer_id` sütunundaki NOT NULL kısıtını korumak için, cari seçilmemiş satışlar `customer-pesin-default` carisine bağlanır.
2. **Stokların Eşitlenmesi:**
   - Core Next'te satış veya düzeltmelerle değişen ürün stokları (`stock_quantity`), legacy `products.quantity` sütununa birebir güncellenir.
3. **Müşteri Bakiyelerinin Eşitlenmesi:**
   - Core Next'te değişen müşteri bakiyeleri (`balance_cents`), legacy `customers.balance` (`balance_cents / 100.0`) ve `balance_minor` alanlarına yazılarak defterle mutabık hale getirilir.
4. **Defter Hareketlerinin Aktarımı:**
   - Core Next `ledger_entries` tablosundaki yeni hareketler legacy `financial_transactions` tablosuna aktarılır.
5. **Bekleyen Senkronizasyon Kuyruğu:**
   - Core Next `sync_events` tablosunda `sync_state = 'PENDING'` olan yeni mutasyonlar, sunucuya aktarılabilmesi için legacy `sync_outbox_v4` kuyruğuna eklenir.
6. **ACID Koruması:**
   - Tüm bu adımlar `legacyDb.transaction` içinde çalıştırılır. Süreç ortasında herhangi bir hata oluşursa işlem tamamen geri alınır; legacy veritabanı bozulmaz.
7. **Durum İşaretleme:**
   - Rollback tamamlandığında Core Next `app_settings` tablosundaki `legacy_migration_completed` anahtarı `'rolled_back'` olarak güncellenir.

---

## 3. İzole Test Senaryosu ve Adli Kanıtlar

`stage10_8_5_reverse_rollback_test.dart` (Test 3) kapsamında yürütülen provada şu adımlar başarıyla test edilmiş ve onaylanmıştır:

### A. Senaryo Başlangıç Durumu (Legacy)
- Ürün: `prod-un` (Hekimoğlu Un 5kg), Fiyat: 95,00 TL, Stok: 100 adet.
- Müşteri: `cust-firin-1` (Bereket Ekmek Fırını), Başlangıç Borcu: -500,00 TL (-50.000 kuruş).

### B. Core Next Cutover & Yeni İşlemler
- 2 adet un satışı yapıldı (Toplam: 190,00 TL / 19.000 kuruş).
- Ödeme: 90,00 TL (9.000 kuruş) Nakit, 100,00 TL (10.000 kuruş) Veresiye.
- Stok düşüldü: 100 -> 98 adet.
- Müşteri borcu arttı: -500,00 TL -> -600,00 TL (-60.000 kuruş).
- Yeni `ledger_entries` kaydı ve bekleyen `sync_events` kuyruk kaydı oluşturuldu.

### C. Reverse Rollback Sonuçları (Legacy DB Adli İnceleme)

```
[ReverseMigrationEngine Raporu]
Satışlar Aktarıldı:          1 adet (REC-V2-001)
Satış Kalemleri Aktarıldı:   1 adet (2x Hekimoğlu Un 5kg)
Ürün Stoğu Güncellendi:      1 adet (98.0 adet)
Müşteri Bakiyesi Güncellendi:1 adet (-600.00 TL)
Defter Hareketleri:          1 adet (100.00 TL Borç)
Bekleyen Outbox Mutasyonu:   1 adet (sync-v2-event-1)
İşlem Durumu:                BAŞARILI (isSuccess: true)
```

- **Legacy `sales` Tablosu:** `REC-V2-001` fişi 190.00 TL toplam ve 90.00 TL tahsilat ile eksiksiz bulundu.
- **Legacy `sale_items` Tablosu:** 2.0 adet x 95.00 TL = 190.00 TL subtotal ile bulundu.
- **Legacy `products` Tablosu:** Stok tam olarak 98.0 olarak doğrulandı.
- **Legacy `customers` Tablosu:** Bakiye tam olarak -600.00 TL olarak doğrulandı.
- **Legacy `sync_outbox_v4` Tablosu:** PENDING durumundaki yeni mutasyon bulundu.
- **PRAGMA integrity_check:** Her iki veritabanı için `ok` döndü.
- **PRAGMA foreign_key_check:** 0 ihlal.

---

## 4. Kurtarma ve İşletim Stratejisi

Eğer canlı cutover sonrasında teknik bir zorunluluk nedeniyle eski sürüme dönülmesi gerekirse uygulanacak operasyonel protokol:

1. Uygulama kapatılır.
2. `ReverseMigrationEngine.rollbackToLegacy()` çalıştırılır.
3. Legacy veritabanında `PRAGMA integrity_check` ve bakiye mutabakatı kontrol edilir.
4. Eski sürüm çalıştırılır ve kesintisiz devam edilir.
