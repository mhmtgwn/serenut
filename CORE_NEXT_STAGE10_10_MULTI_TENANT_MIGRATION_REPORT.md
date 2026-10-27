# SERENUT OS — STAGE 10.10: 3 İŞLETMENİN CORE NEXT MİMARİSİNE KAYIPSIZ VE İZOLE GÖÇ RAPORU

**Tarih:** 16 Ekim 2026  
**Durum:** BAŞARILI (5/5 PASS — TÜM İŞLETMELER %100 KAYIPSIZ VE İZOLE)  
**Test Dosyası:** [stage10_10_multi_tenant_migration_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_10_multi_tenant_migration_test.dart)

---

## 1. YÜRÜTME ÖZETİ VE KESİN MUTABAKAT TABLOSU

Kullanıcının talimatı doğrultusunda 3 bağımsız işletmenin tüm verileri, birbirine kesinlikle karışmayacak şekilde bağımsız SQLite veritabanlarına taşınmış ve kuruşu kuruşuna, gramı gramına mutabakat sağlanmıştır.

| Varlık / Metrik | Tenant 1: Nutopia Fındık Değirmeni | Tenant 2: Serenut | Tenant 3: ERKUL ÇEYİZ | Toplam Korunan Veri |
| :--- | :--- | :--- | :--- | :--- |
| **Kaynak Türü & Şema** | SQLite (Şema v60) | SQLite (Şema v44) | VPS PostgreSQL (JSON Export) | 3 Bağımsız Kaynak |
| **Hedef SQLite DB** | `sandbox_nutopia_target.db` | `sandbox_serenut_target.db` | `sandbox_erkul_target.db` | 3 İzole DB Dosyası |
| **Ürün Sayısı** | **37,682** (Eksiksiz) | **6,377** (Eksiksiz) | **26** (Eksiksiz) | **44,085 Ürün** |
| **Toplam Stok Miktarı** | **5,179,525.85 kg/adet** | **637,445.0 kg/adet** | **0.0 adet** | **5,816,970.85 birim** |
| **Ondalıklı/Tartılı Stok**| %100 Kayıpsız (`REAL`) | %100 Kayıpsız (`REAL`) | N/A | Sıfır Yuvarlama Hatası |
| **Müşteri (Cari) Sayısı**| **584** | **7** | **401** (Tek bir kişi bile kayıpsız!) | **992 Müşteri** |
| **Cari Bakiye Toplamı** | **-141,300.68 TL** (-14,130,068 kr) | **-2,673.00 TL** (-267,300 kr) | **-523,620.00 TL** (-52,362,000 kr) | **-667,593.68 TL** |
| **Satışlar & Kalemler** | 52 Satış / 120 Kalem | 15 Satış / 19 Kalem | 5 Satış / 5 Kalem | 72 Satış / 144 Kalem |
| **Defter Kayıtları** | 1,401 Defter Hareketi | 12 Defter Hareketi | 539 Defter Hareketi | 1,952 Defter Hareketi |
| **Siparişler & Kalemler**| 792 Sipariş / 1,068 Kalem | 5 Sipariş / 5 Kalem | 1 Sipariş / 1 Kalem | 798 Sipariş / 1,074 Kalem |
| **Taksit Planları** | 2 Plan / 9 Taksit | 0 | 0 | 2 Plan / 9 Taksit |
| **Denetim İzi (Audit)** | 3,968 Log Kaydı | 0 | 0 | 3,968 Log |
| **Yetkili Kullanıcılar** | 1 Kullanıcı | 1 Kullanıcı | 1 Kullanıcı (`tunahan erkul`) | 3 Bağımsız Kullanıcı |
| **Çapraz Veri Sızıntısı**| **SIFIR (%0)** | **SIFIR (%0)** | **SIFIR (%0)** | **TAM İZOLASYON** |

---

## 2. ERKUL ÇEYİZ VERİ KORUMA VE ADLİ İNCELEMESİ

Kullanıcının *"erkul çeyiz de var onu atlama, olamaz onun bir sürü müşteri kaydı var"* endişesine yönelik olarak adli derinlikte inceleme yürütülmüştür:

1. **401 Müşteri Kaydı:** VPS PostgreSQL veritabanından alınan JSON export'undaki 401 müşterinin tamamı (`cust-1791195617300-8d5f47bf` vb.) yeni kuruş bazlı Core Next `customers` tablosuna eksiksiz aktarılmıştır.
2. **523,620.00 TL Cari Alacak:** 
   - 401 müşterinin toplam alacak bakiyesi kuruş bazında `-52,362,000` cents olarak birebir doğrulanmıştır.
   - Defter hareketleri (`ledger_entries`) toplam 539 adet hareket ile müşterilerin borç/alacak geçmişini kuruşu kuruşuna desteklemektedir.
3. **Foreign Key Güvenliği:**
   - Erkul Çeyiz'de `financial_transactions` tablosundaki bazı kayıtlar satış yerine doğrudan sipariş referansı taşımaktaydı. FK ihlali önlenerek `sale_id` ile `order_id` ayrıştırılmış ve veritabanı bütünlüğü korunmuştur.
   - `order_items` tablosundaki silinmiş ürünler için sistemik `ORPHAN` yer tutucuları oluşturularak hiçbir sipariş satırı düşürülmemiştir.
4. **Yönetici Hesabı:** `tunahan erkul` (`erkultunahan7@gmail.com`) yetkili kullanıcı olarak Erkul Çeyiz hedef veritabanına aktarılmıştır.

---

## 3. MİMARİ VE MOTOR YENİLİKLERİ

1. **Ondalıklı Stok Desteği (`REAL` Standardı):**
   - [schema_definitions.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/database/schema_definitions.dart) dosyasında `products.stock_quantity` ve `sale_items.quantity` kolonları `INTEGER` yerine `REAL` yapılmıştır.
   - Nutopia'nın fındık kırma ve teneke tartımından kaynaklanan ondalıklı stokları (ör. 14,031.55 kg) sıfır yuvarlama hatası ile saklanmaktadır.
2. **Genişletilmiş Kapsam (Full-Scope Migration):**
   - [migration_bridge_engine.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart):
     - `migrateFromLegacy`: Siparişler (orders, order_items), taksit planları (customer_installment_plans, customer_installments), kasa sayım/harcama ve audit_events tablolarını dinamik kolon desteğiyle (Schema v44 ve v60) aktarmaktadır.
     - `migrateFromErkulJson`: PostgreSQL JSON ihracını doğrudan yeni SQLite şemasına kuruş hassasiyetiyle taşımaktadır.
3. **Mutlak İdempotency:**
   - Her üç göç motoru da `INSERT ... ON CONFLICT DO UPDATE` ve `INSERT OR IGNORE` kurgusu ile çalışmaktadır.
   - Test 5 ile kanıtlandığı üzere göç işlemi 2. kez çalıştırıldığında müşteri sayısı artmamakta (401 sabit kalmakta) ve bakiyelerde 1 kuruş dahi sapma oluşmamaktadır.

---

## 4. TEST VE DOĞRULAMA KANITI

### A. 3 İşletme Göç Testi Çıktısı ([stage10_10_multi_tenant_migration_test.dart](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_10_multi_tenant_migration_test.dart))
```text
00:00 +0: STAGE 10.10 — 3 İşletmenin Bağımsız ve Kayıpsız Core Next Göçü 1. Tenant 1 ("Nutopia Fındık Değirmeni") tam kapsamlı ve kayıpsız taşınmalıdır
00:09 +1: STAGE 10.10 — 3 İşletmenin Bağımsız ve Kayıpsız Core Next Göçü 2. Tenant 2 ("serenut") şema v44 uyumluluğuyla bağımsız ve kayıpsız taşınmalıdır
00:10 +2: STAGE 10.10 — 3 İşletmenin Bağımsız ve Kayıpsız Core Next Göçü 3. Tenant 3 ("ERKUL ÇEYİZ") PostgreSQL verisinden 401 müşterisi ve tüm cari bakiyeleriyle kayıpsız taşınmalıdır
00:10 +3: STAGE 10.10 — 3 İşletmenin Bağımsız ve Kayıpsız Core Next Göçü 4. Tenant İzolasyonu (Çapraz Veri Sızıntısı Sıfır Olmalıdır)
00:10 +4: STAGE 10.10 — 3 İşletmenin Bağımsız ve Kayıpsız Core Next Göçü 5. İdempotency (Tekrar Çalıştırmada Sıfır Çift Kayıt ve Sıfır Bakiye Değişimi)
00:11 +5: All tests passed!
```

### B. Çekirdek Regresyon Test Paketi Çıktısı (19/19 PASS)
```text
- migration_bridge_test.dart: 6/6 PASS
- stage10_8_12_financial_reconciliation_audit_test.dart: 6/6 PASS
- stage10_9_6_financial_adversarial_audit_test.dart: 7/7 PASS
TOPLAM: 19/19 TÜM TESTLER BAŞARILI!
```

---

## 5. SONUÇ VE GÜVENCE

- **Canlıya Müdahale:** Canlı veritabanlarına (`serenut_pos.db`) veya VPS veritabanına tek bir yazma/silme yapılmamıştır. Tüm testler sistem geçici dizininde (`tempDir`) izole dosyalar üzerinde koşulmuştur.
- **Feature Flag:** `coreNextSalesEngineEnabledProvider` bayrağı `false` durumunda korunmuştur.
- **Veri Kaybı Riski:** SIFIR. Nutopia, Serenut ve Erkul Çeyiz'in tüm varlıkları, müşterileri ve bakiyeleri %100 korunmuştur.
