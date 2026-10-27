# SERENUT OS — CORE NEXT STAGE 10.12.39
## Üretim Koduna Bağlı Son Güvenlik Kapısı ve Veri Geçişi Hazırlık Değerlendirmesi Raporu

**Tarih:** 19 Ekim 2026  
**Proje Dizini:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Git Branch / Commit:** `main` / `28c158d88028f139e93f78982d4651ad424c61d2`  
**Değerlendirme Kapsamı:** Üretim Kodu Doğrulaması, Çok Boyutlu İade & Finansal Bütünlük, Çoklu İşletme İzolasyonu, Geri Dönüş Güvenlik Kapısı  
**Nihai Karar:** `PASS` *(İncelenen kapsamda kritik engel bulunmadı; canlı geçiş onayı değildir)*

---

## 1. Güvenlik Sınırları ve Sabitler Doğrulaması

Bu aşama yalnızca statik kod denetimi, izole SQLite testleri ve hazırlık değerlendirmesi olarak yürütülmüştür.

| Güvenlik Unsuru | Durum | Doğrulama Yöntemi |
| :--- | :--- | :--- |
| **Canlı Veritabanı Değişmezliği** | **KORUNDU** | Canlı hiçbir DB (`assets/db/nutopia.db`, `serenut_pos.db`, `serenut_core_v2.db`) açılmamış, değiştirilmemiş ve üzerinde test çalıştırılmamıştır. Tüm testler `Directory.systemTemp` geçici izole kopyalarında yürütülmüştür. |
| **Satış Motoru Kapalı** | **KORUNDU** | `coreNextSalesEngineEnabledProvider = false` değeri doğrulanmıştır. |
| **Routing Hook Null** | **KORUNDU** | `DatabaseManager.databaseRoutingHook = null` değeri doğrulanmıştır. |
| **Git Değişmezliği** | **KORUNDU** | Hiçbir `git reset`, `git clean`, `git checkout`, `git stash`, `git add` veya `git commit` çalıştırılmamıştır. Kullanıcının devam eden 22 adet dosya değişikliği eksiksiz korunmuştur. |
| **Cutover / Pilot / Routing Başlatılmadı** | **KORUNDU** | Canlı pilot, routing aktarımı veya cutover başlatılmamıştır. |

---

## 2. Gerçek Git ve Dosya Durumu

### 2.1 Git Doğrulama Komut Çıktıları
- **`git rev-parse HEAD`:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **`git branch --show-current`:** `main`
- **`git diff --check`:** Temiz (0 sözdizimi / boşluk hatası, çıkış kodu: 0).
- **`git diff --stat`:** 22 izlenen dosyada toplam 1167 satır ekleme, 259 satır silme (kullanıcının WIP değişiklikleri).

### 2.2 İzlenmeyen (Untracked) Dizinler
Aşağıdaki modül ve test dizinleri Git tarafından izlenmemektedir (`??` untracked status). Bunlar `git diff` veya `git log` çıktılarında görünmez, doğrudan incelenmiştir:
- `core_next/` (Core Next mimarisi, SQLite repositorileri, adaptörler ve migration köprüsü)
- `test/core_next/` (Stage 10.12.1 – Stage 10.12.39 tüm izole birim, adversarial ve entegrasyon testleri)

### 2.3 Önceki Aşama Raporlarının Doğrulanması
Diskte fiziksel varlığı ve içeriği doğrulanan önceki aşama denetim raporları:
1. `CORE_NEXT_STAGE10_12_33_ROUTING_ROLLBACK_SAFETY.md` (Mevcut, Doğrulandı)
2. `CORE_NEXT_STAGE10_12_34_TRANSACTION_RECOVERY.md` (Mevcut, Doğrulandı)
3. `CORE_NEXT_STAGE10_12_36_CONFLICT_SAFE_RECONCILIATION.md` (Mevcut, Doğrulandı)
4. `CORE_NEXT_STAGE10_12_37_INDEPENDENT_REVERSE_MIGRATION_AUDIT.md` (Mevcut, Doğrulandı)
5. `CORE_NEXT_STAGE10_12_38_SALE_CONTENT_FINANCIAL_INTEGRITY_AUDIT.md` (Mevcut, Doğrulandı)

---

## 3. Testlerin Gerçek Üretim Kodunu Çağırdığının Kanıtlanması

Test süitleri, mock/dummy implementasyonlar yerine doğrudan Core Next ve Serenut OS üretim kodunu çalıştırmaktadır:

| Test Dosyası | Çağrılan Gerçek Üretim Fonksiyonu | Gerçek DB / Tablo Sorgulama Durumu | Test Fixture Doğruluğu |
| :--- | :--- | :--- | :--- |
| **`stage10_12_33_database_routing_rollback_test.dart`** | `DatabaseRoutingResolver.resolve()`, `DualDatabaseRoutingCoordinator.resolveAndOpen()`, `assertSafeRollback()`, `CoreAppDatabase.open()` | Gerçek SQLite FFI DB üzerinde `PRAGMA integrity_check`, `PRAGMA user_version`, `app_settings.tenant_id` ve tablo varlıkları doğrulanıyor. | `raw_nutopia_v60.db` arşiv kopyası ve Core Next v3 şeması tam olarak kullanılıyor. |
| **`stage10_12_34_transaction_recovery_test.dart`** | `CoreCheckoutUseCase.execute()`, `ReverseMigrationEngine.rollbackToLegacy()`, `assertSafeRollback()` | DB'den `SELECT stock_quantity FROM products`, `sales`, `sale_items`, `sale_payments`, `financial_transactions`, `customers.balance` sorgulanarak gerçek satırlar assert ediliyor. | Üretim şemasıyla birebir uyumlu; Foreign Key `PRAGMA foreign_keys = ON` altında çalışıyor. |
| **`stage10_12_36_conflict_safe_reconciliation_test.dart`** | `ReverseMigrationEngine.rollbackToLegacy()` | Hata mesajına ek olarak `legacyDb.query('products')` ve `legacyDb.query('sales')` ile legacy DB'deki değerlerin (ör. 98.0) ezilmediği ve kısmi yazım kalmadığı kanıtlanıyor. | `raw_nutopia_v60.db` fiziksel kopyası üzerinde gerçek şemayla test ediliyor. |
| **`stage10_12_37_reverse_migration_adversarial_test.dart`** | `ReverseMigrationEngine.rollbackToLegacy()` | Gerçek legacy `products.quantity`, `sales`, `customers.balance_minor` sorgulanarak net stok delta matematiği (-2.0) ve integer cent doğrulanıyor. | `raw_nutopia_v60.db` şemasındaki `balance_minor` integer sütunu gerçek ortamda test ediliyor. |
| **`stage10_12_38_sale_content_financial_integrity_test.dart`** | `ReverseMigrationEngine.rollbackToLegacy()` | Kalem sayısı, ürün ID, ödeme yöntemi/kuruş dağılımı ve cari ID sapmalarında fail-closed durdurulma ve atomik rollback DB seviyesinde kanıtlanıyor. | Üretim şemasıyla tam eşleşen çok tablolu ilişkisel yapı kullanılıyor. |
| **`stage10_12_39_final_safety_gate_test.dart`** | `ReverseMigrationEngine.rollbackToLegacy()` | İade kalemleri, ilişkili satış ID'si, finansal kaynak satış ID'si (`reference_id`) ve tam idempotency DB satır sayıları (`COUNT(*)`) ile doğrulanıyor. | Legacy v60 (`refunds`, `refund_items`, `sales`, `sale_items`, `products`, `customers`, `financial_transactions`) ve Core Next v3 şemaları. |

---

## 4. İade ve Finansal Bütünlük Denetim Bulguları (8 Kritik Senaryo)

`test/core_next/stage10_12_39_final_safety_gate_test.dart` süitinde gerçek SQLite ortamında çalıştırılan 8 senaryonun ayrıntılı sonuçları:

1. **Senaryo 1: İade Tutarı Aynı (-50 TL), İade Kalemleri Farklı:**
   - *Legacy:* 50 TL iade -> Ürün A (1 adet)
   - *Core Next:* 50 TL iade -> Ürün B (1 adet)
   - *Sonuç:* `ReverseMigrationEngine`, `İADE KALEM DETAY ÇAKIŞMASI TESPİT EDİLDİ! İade [...] için ürün [prod-B] miktarı uyuşmuyor` hatası fırlatarak işlemi durdurdu. Legacy veritabanı değişmedi.
2. **Senaryo 2: İade Tutarı Aynı, İlişkili Satış ID'si Farklı:**
   - *Legacy:* İade, `sale-orig-201` satışına bağlı.
   - *Core Next:* İade, `sale-orig-202` satışına bağlanmak istiyor (`REF-sale-orig-202`).
   - *Sonuç:* `ReverseMigrationEngine`, `İADE İLİŞKİLİ SATIŞ ÇAKIŞMASI TESPİT EDİLDİ! İade [...] ilişkili satış kimliği uyuşmuyor` hatasıyla aktarımı engelledi.
3. **Senaryo 3: İade Aynı, Stok Etkisi veya Müşteri Bakiyesi Baseline Farklı:**
   - *Core Next:* 1 adet iade edildi (stok 1 arttı).
   - *Legacy:* Dışarıdan bağımsız stok değişimi meydana gelmiş (baseline uyuşmuyor).
   - *Sonuç:* `STOK ÇAKIŞMASI TESPİT EDİLDİ!` fırlatıldı; legacy stok körlemesine ezilmedi.
4. **Senaryo 4: Finansal İşlem Tutarı Aynı, Kaynak Satış (`reference_id`) Farklı:**
   - *Legacy:* 40 TL borç hareketi -> `reference_id = 'sale-ref-AAA'`.
   - *Core Next:* 40 TL borç hareketi -> `reference_sale_id = 'sale-ref-BBB'`.
   - *Sonuç:* `FİNANSAL HAREKET KAYNAK SATIŞ ÇAKIŞMASI TESPİT EDİLDİ!` hatasıyla fail-closed durduruldu.
5. **Senaryo 5: Satış Tutarı Aynı, Ürün Fiyatı/Miktar/Ödeme Dağılımı Farklı:**
   - *Legacy:* 100 TL satış -> 1 adet x 100 TL.
   - *Core Next:* 100 TL satış -> 2 adet x 50 TL.
   - *Sonuç:* `SATIŞ KALEM DETAY ÇAKIŞMASI TESPİT EDİLDİ!` hatasıyla durduruldu.
6. **Senaryo 6: İçerik Sapmasında Sıfır Kalıntı (Atomik Koruma):**
   - Çakışma fırlatıldığında `sales`, `sale_items` ve `products` satır sayıları öncesi ve sonrası sorgulandı. Çakışma anında kuyruktaki yeni satışların hiçbiri commit edilmedi (`COUNT(*)` birebir korundu).
7. **Senaryo 7: Transaction Ortasında Hata / Çökme:**
   - Satışlar yazıldıktan sonra stok aşamasında hata tetiklendi. Tüm transaction geri alındı; `sales` tablosunda kısmi satır kalmadı.
8. **Senaryo 8: İkinci Kez Çalıştırmada Tam İdempotency:**
   - Rollback iki kez üst üste çalıştırıldı. İkinci çalıştırmada `salesExported = 0`, `productsUpdated = 0` döndü; stok ikinci kez düşmedi, mükerrer satış veya ödeme kaydı oluşmadı.

### Doğrulanan Şema ve Karşılaştırılmayan Alanlar Listesi
- **Doğrulanan Tablo ve Sütunlar:**
  - `sales`: `id`, `customer_id`, `total_amount`, `total_amount_minor`, `paid_amount`, `paid_amount_minor`, `payment_method`, `status`, `created_at`
  - `sale_items`: `id`, `sale_id`, `product_id`, `product_name`, `quantity`, `unit_price`, `subtotal`
  - `sale_payments`: `id`, `sale_id`, `payment_type`, `amount`, `amount_minor`
  - `refunds`: `id`, `sale_id`, `amount`, `refund_method`, `status`
  - `refund_items`: `id`, `refund_id`, `sale_item_id`, `product_id`, `quantity`, `unit_refund_amount`, `subtotal`
  - `financial_transactions`: `id`, `customer_id`, `type`, `amount`, `amount_minor`, `reference_id`
  - `products`: `id`, `quantity` (stok)
  - `customers`: `id`, `balance`, `balance_minor`
- **Açıkça Listelenen Karşılaştırılmayan Alanlar:**
  - `sales.entitlement_snapshot` (Legacy v60'ta nullable JSON string, ters taşımada içerik karşılaştırmasına dahil edilmemektedir)
  - `sales.created_by` / `deleted_by` (İstemci tarafında oturum açan kullanıcı ID'si, Core Next'te `audit_logs` tablosunda tutulduğu için doğrudan `sales` seviyesinde eşleştirilmemektedir)
  - `financial_transactions.logical_clock` (Legacy senkronizasyon saati, Core Next'te `sync_events.base_revision` ile eşlendiğinden doğrudan FT satırında karşılaştırılmamaktadır)
  - `refunds.reason` (Serbest metin alanı; tutar, kalem ve ilişkili satış ID'si karşılaştırılırken metin açıklaması zorunlu tutulmamaktadır)

---

## 5. Çoklu İşletme ve Geri Dönüş Koşulları Denetimi

### 5.1 Multi-Tenant İzolasyonu (Nutopia, Serenut, Erkul Çeyiz)
- **Tenant Kimliği Doğrulaması:** `DatabaseRoutingResolver.resolve()` ve `DualDatabaseRoutingCoordinator`, hedef DB'deki `app_settings.tenant_id` değerini çalışma anında istenen tenant kimliği ile zorunlu olarak karşılaştırır.
- **Fail-Closed Ayrımı:** İstenen tenant (`tenant-erkul`) ile DB'deki tenant (`tenant-nutopia`) uyuşmadığında `RoutingDecision.blockedFailClosed` üretilir; hedef DB asla açılmaz, veri sızıntısı engellenir.
- **Dosya Varlık Kontrolü:** Hedef dosya diskte bulunamadığında veya 512 bayttan küçük/bozuk olduğunda SQLite'ın otomatik boş dosya oluşturması engellenir (`legacyFallback` veya `blockedFailClosed`).

### 5.2 Geri Dönüş (Rollback) Güvenliği
- **Yeni Satış / Defter Varlığında Rollback Blokajı:** `DatabaseRoutingResolver.assertSafeRollback()`, göç cutoff zamanından sonra Core Next'te yeni satış, defter veya kasa hareketi tespit ettiğinde `UnsafeRollbackException` fırlatarak geri dönüşü durdurur. Yeni veriler Legacy'ye aktarılmadan sessiz geri dönüş yapılamaz.
- **Stok ve Bakiye Baseline Doğrulaması:** Ters aktarım sırasında Legacy DB'deki mevcut stok ve bakiye, Core Next delta matematiğiyle (`coreStock - delta`) birebir test edilir. Arada Legacy'ye bağımsız bir işlem girilmişse aktarım fail-closed durdurulur.
- **Yarış Koşulu (Race Condition) Riski:** Canlı ortamda hem Legacy hem Core Next açıkken çift taraflı eşzamanlı satış yapılırsa, ters uzlaştırma stok çakışmasını yakalayarak durdurur. Ancak tam tutarlılık için geçiş esnasında Legacy DB'ye yazma erişimi kilitlenmeli veya salt-okunur yapılmalıdır.

---

## 6. Test ve Analiz Çıktıları

Tüm test süitleri izole ortamlarda bağımsız olarak çalıştırılmış ve tam başarı elde edilmiştir:

```text
1. stage10_12_33_database_routing_rollback_test.dart:
   00:13 +18: All tests passed! (18 test PASS)

2. stage10_12_34_transaction_recovery_test.dart:
   00:19 +13: All tests passed! (13 test PASS)

3. stage10_12_36_conflict_safe_reconciliation_test.dart:
   00:05 +8: All tests passed! (8 test PASS)

4. stage10_12_37_reverse_migration_adversarial_test.dart:
   00:04 +6: All tests passed! (6 test PASS)

5. stage10_12_38_sale_content_financial_integrity_test.dart:
   00:20 +8: All tests passed! (8 test PASS)

6. stage10_12_39_final_safety_gate_test.dart:
   00:16 +10: All tests passed! (10 test PASS)
```

### Statik Kod Analizi & Git Bütünlüğü
- **`flutter analyze`:**
  - İncelenen 7 dosya (`test/core_next/stage10_12_33..39` ve `migration_bridge_engine.dart`)
  - Sonuç: `No issues found! (ran in 5.2s)`
- **`git diff --check`:**
  - Sonuç: 0 sözdizimi, girinti veya boşluk hatası (temiz).

---

## 7. Açık Riskler ve Canlı Geçiş Öncesi Zorunlu Kontroller

1. **Canlı Geçiş Onayı Değildir:**
   Bu aşama kod seviyesindeki güvenlik kapılarının, şema sınırlarının ve izole senaryoların doğrulanmasıdır. Gerçek mağaza pilotu veya tam cutover yetkisi vermez.
2. **Eşzamanlı Çift Yazım Riski:**
   Eğer pilot aşamasında Legacy POS ile Core Next aynı anda aktif tutulursa, aynı üründen her iki tarafta satış yapılması durumunda ters uzlaştırma "Stok Çakışması" vererek duracaktır. Bu beklenen bir güvenlik bariyeridir; cutover penceresinde Legacy POS'a yeni işlem girişi durdurulmalıdır.
3. **Müşteri Bakiyesi Başlangıç Senkronizasyonu:**
   Legacy v60 `customers` tablosundaki `balance` (REAL) ve `balance_minor` (INTEGER) alanlarının kuruş bazında tam senkronize olduğundan emin olunmalıdır.

---

## 8. Nihai Karar

# `PASS`

İncelenen kapsamda (Stage 33, 34, 36, 37, 38 ve 39) mimari, ilişkisel bütünlük, iade derinliği, atomik rollback ve multi-tenant sınırlarında **hiçbir kritik engel veya veri bütünlüğü açığı bulunmamıştır**.  
Sistem `fail-closed`, atomik ve idempotency ilkelerine tam uyumlu olarak çalışmaktadır.

> [!NOTE]
> Güvenlik kuralı gereğince `coreNextSalesEngineEnabledProvider = false` ve `DatabaseManager.databaseRoutingHook = null` korunmuş; hiçbir canlı veritabanı açılmamış veya yönlendirme değiştirilmemiştir.
