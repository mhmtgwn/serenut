# SERENUT OS — STAGE 10.8.11 TEST INDEPENDENCE REPORT
## Test Bağımsızlığı, Gerçek Ortam Doğrulaması ve Adversarial Senaryo Raporu

**Tarih:** 2026-10-15  
**Kapsam:** SQLite FFI Ortamı, Gerçek Disk Veritabanı, Mock Bağımsızlığı, Yabancı Anahtar (PRAGMA foreign_keys = ON) ve Adversarial Senaryolar.

---

## 1. TEST YÜRÜTME ORTAMI VE MOCK BAĞIMSIZLIĞI

Stage 10.8.11 kapsamında yürütülen testler hiçbir mock SQLite motoruna veya sahte InMemory sorgulayıcıya dayanmaz:
1. **Gerçek SQLite FFI:**
   Tüm testler `sqflite_common_ffi` üzerinden Windows yerel SQLite DLL kütüphanesi kullanılarak çalıştırılmıştır.
2. **Geçici Disk Dosyaları (`Directory.systemTemp`):**
   Her test grubu için disk üzerinde gerçek `.db` dosyaları oluşturulmuş, WAL modu ve foreign key pragma kuralları aktif tutulmuştur.
3. **Foreign Key Zorunluluğu (`PRAGMA foreign_keys = ON`):**
   `CoreAppDatabase` başlatılırken `PRAGMA foreign_keys = ON;` işletilmektedir. Alt kayıt varken üst kaydı silme veya geçersiz yabancı anahtar referansları doğrudan SQLite C motoru tarafından engellenmiştir.
4. **Idempotency ve Adversarial Şartlar:**
   Testler kendi varsayımlarını tekrar etmek yerine sistemin sınırlarını zorlayacak adversarial girdilerle kurgulanmıştır (negatif tutar, mükerrer istek, yetersiz stok, Türkçe özel harfler, transaction ortasında hata).

---

## 2. 18 ADVERSARIAL TEST SENARYOSUNUN AYRINTILI DÖKÜMÜ

| No | Test Senaryosu | Odaklandığı Güvenlik Açığı / Kritik Kural | Sonuç |
|---|---|---|---|
| **1** | Eski DB'den Yeni DB'ye İlk Migration | Tam kapsamlı veri transferi ve kuruş/tamsayı dönüşümü | **GEÇTİ** |
| **2** | Migration'ın İki Kez Çalıştırılması | `ON CONFLICT DO UPDATE` ile FK RESTRICT hatasız veri güncellemesi | **GEÇTİ** |
| **3** | Migration Ortasında Hata & Yeniden Başlatma | Hatalı legacy satırında transaction rollback ve sıfır veri sızıntısı | **GEÇTİ** |
| **4** | Ürün Güncellemesinde Satış Kalemi Korunumu | Ürün adı ve fiyatı değiştiğinde satış kaleminin FK bütünlüğü | **GEÇTİ** |
| **5** | Stok Yetersizliği ve Eşzamanlı Satış | Stokta 2 olan üründen 3 satılmaya çalışıldığında StateError ve rollback | **GEÇTİ** |
| **6** | Satış, Karma Ödeme ve Satış Geçmişi | Çoklu ödeme satışı ve `CoreNextSaleRepository.findById` doğrulaması | **GEÇTİ** |
| **7** | Kısmi İade, Tam İade ve Idempotency | Kısmi iadede stok artışı; aynı isteğin tekrarında stokun çift artmaması | **GEÇTİ** |
| **8** | Tahsilatın İki Kez İşlenmesi | Mükerrer tahsilatta `balance_cents` değerinin ikinci kez değişmemesi | **GEÇTİ** |
| **9** | Müşteri Bakiyesi ve Ledger Mutabakatı | Borç satışı + tahsilat işlemlerinin çift taraflı defter dengesi | **GEÇTİ** |
| **10** | Çevrimdışı Satış ve Outbox Kuyruğu | Satış anında `sync_events` tablosunda atomik PENDING kaydı | **GEÇTİ** |
| **11** | Aynı Senkronizasyon Olayının Tekrarı | `event_id` bazlı UNIQUE constraint ile tekilleştirme | **GEÇTİ** |
| **12** | Sunucu Hatası ve Yeniden Deneme | Geçici sunucu hatasında `attempts = 1` ve `TRANSIENT_ERROR` durumu | **GEÇTİ** |
| **13** | Legacy Modda Regresyon | `coreNextSalesEngineEnabledProvider = false` iken core depoların null kalması | **GEÇTİ** |
| **14** | Core Next Tam Yaşam Döngüsü | Ürün oluşturma -> Müşteri -> Veresiye Satış -> Kısmi İade tam zincir | **GEÇTİ** |
| **15** | Disk Kalıcılığı (Persistence) | Veritabanı kapatılıp yeniden açıldığında verilerin diskten okunması | **GEÇTİ** |
| **16** | Türkçe Karakter ve Arama | `sqliteTurkishFold` ve `normalizeTurkish` ile 'incir' -> 'İNCİR' eşleşmesi | **GEÇTİ** |
| **17** | Zorla Hata ile ACID Rollback | Transaction ortasında fırlatılan hatada hiçbir yarım kaydın kalmaması | **GEÇTİ** |
| **18** | Kuruş Bazında Mutabakat | 33.33 + 33.33 + 33.34 = 100.00 TL kuruş mutabakatı | **GEÇTİ** |

---

## 3. TEST SAYILARI VE İSTATİSTİKLER

- **Çalıştırılan Toplam Test:** 33
- **Başarılı Test (Passed):** 33 (%100)
- **Başarısız Test (Failed):** 0
- **Çalıştırılmayan Test (Skipped):** 0
- **Test Paketleri Dağılımı:**
  - `test/core_next/stage10_8_11_runtime_audit_test.dart` -> 18 Test (18 Geçti)
  - `test/core_next/stage10_8_10_runtime_audit_test.dart` -> 4 Test (4 Geçti)
  - `test/ui/stage10_8_2_sales_controller_e2e_test.dart` -> 4 Test (4 Geçti)
  - `test/core_next/checkout_use_case_test.dart` -> 7 Test (7 Geçti)
