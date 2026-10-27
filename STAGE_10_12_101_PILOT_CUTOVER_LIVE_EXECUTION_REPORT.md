# SERENUT OS — STAGE 10.12.101
## FAZ 3: Nutopia Kasasında Kontrollü Pilot Cutover & Canlı İşlem Doğrulama Raporu
**Tarih:** 23 Ekim 2026  
**Durum:** ✅ **FAZ 3 BAŞARIYLA TAMAMLANDI (%100 GREEN)**  
**Test Paketi:** `test/core_next/stage10_12_101_pilot_cutover_live_execution_test.dart` (12/12 Test PASS)

---

### 1. Yönetici Özeti ve Faz 3 Çıktıları

Canlıya geçiş ana planının (`core_next_pilot_ve_canliya_gecis_plani.md`) **Faz 3 (Nutopia Kontrollü Pilot Cutover)** aşaması, hedef `nutopia_core_next_live.db` veritabanı ve Faz 2 snapshot yedeği üzerinde icra edilmiştir.

Yapılan testler sonucunda:
1. **Ön Koşullar & Yedekleme Kanıtı:** Faz 2'de alınan atomik snapshot ve `snapshot_manifest.json` SHA-256 imzası birebir doğrulandı.
2. **Çok Kiracılı İzolasyon:** Erkul Çeyiz (`comp-1791194455402-bdc6d8d1`) veya yetkisiz kiracılar için fail-closed kuralı test edildi; sistem `blockedTenantMismatch` ile geçişi kesin olarak engelledi.
3. **Pilot Kapısı & Sağlayıcı Enjeksiyonu:** `PilotCutoverGate.evaluate()` Nutopia için `pilotActiveApproved` statüsü verdi; 4 kritik Core Next satış motoru sağlayıcısı (`SaleRepo`, `SaleExecutor`, `RefundExecutor`, `EnabledFlag`) eksiksiz Riverpod konteynerine bağlandı.
4. **Gerçek Perakende Satış Senaryoları:**
   - **Peşin Nakit Satış:** 2 Adet Danette Çikolatalı Puding (199.80 TL) satıldı. Stok 200'den 198'e düştü. `sales`, `sale_items`, `sale_payments`, `cash_transactions` (INFLOW) ve `sync_events` kaydedildi.
   - **POS / Kredi Kartı Satışı:** 1 Adet Eti Lifalif Bar (107.50 TL) kart ile satıldı. Stok 100'den 99'a düştü. Kasa nakit çekmecesine kart işlemi yazılmadı (tam yalıtım).
   - **Veresiye / Açık Hesap Satış:** Müşteri `MEHMET GÜVEN`'e 1 Adet Kajun Bar (37.50 TL) veresiye satıldı. Müşteri cari bakiyesi 115.00 TL'den 77.50 TL'ye (7.750 kuruş) düştü. `ledger_entries` tablosuna `debitSale` işlendi.
   - **Karma / Parçalı Ödeme Satışı:** 1 Adet Aktürk Gofret (59.90 TL) için 20.00 TL Nakit + 39.90 TL Kart tahsil edildi. Kasa çekmecesine sadece 20.00 TL nakit girişi yapıldı.
   - **Nakit İade:** 1 Adet Alpella Gofret (16.00 TL) iade alındı. Stok otomatik olarak eski haline (+1) restore edildi.
5. **Gün Sonu Mutabakatı:** Satış ödeme toplamları ile kasa nakit çekmecesi ve cari defter arasında 0 kuruş sapma olduğu doğrulandı.
6. **Acil Geri Dönüş (Safe Rollback) Güvencesi:** `ReverseMigrationEngine.rollbackToLegacy` motoru icra edildi; Core Next üzerinde kesilen fişler **403 ms** içinde (< 10 saniye SLA) eski SQLite (v60) şemasına kayıpsız aktarıldı. İkinci çalıştırmada 0 mükerrer satış (Idempotent Rollback) kanıtlandı.

---

### 2. Test Sonuçları Matrisi (STAGE 10.12.101)

| Grup | Test Adı | Beklenen | Gerçekleşen | Durum |
| :--- | :--- | :--- | :--- | :---: |
| **Grup 1** | 1.1 Faz 2 Manifest ve SHA-256 İmzası | Manifest eşleşmeli, SHA256 geçerli | `ok`, SHA256 tam eşleşme | **PASS** |
| **Grup 1** | 1.2 Hedef Core Next DB Bütünlüğü (v3) | PRAGMA ok, 37.682 ürün, 626 müşteri | Tam eşleşti, 0 FK ihlali | **PASS** |
| **Grup 1** | 1.3 Erkul Çeyiz Çapraz Kiracı Engeli | `blockedTenantMismatch`, overrides boş | Fail-closed engellendi | **PASS** |
| **Grup 1** | 1.4 Kill Switch Acil Devre Kesici | `blockedKillSwitch` | Anında durduruldu | **PASS** |
| **Grup 2** | 2.1 Nutopia Pilot Gate & Sağlayıcı Enjeksiyonu | `pilotActiveApproved`, 4 executor bağlı | Tamamı Riverpod'a bağlandı | **PASS** |
| **Grup 3** | 3.1 Peşin Nakit Satış (Danette 199.80 TL) | Stok -2, Kasa Girişi +199.80 TL, Sync Outbox | Stok 198, Kasa +199.80 TL | **PASS** |
| **Grup 3** | 3.2 Kredi Kartı POS Satışı (Lifalif 107.50 TL) | Stok -1, Kasa Girişi = 0 TL (Kart Yalıtımı) | Stok 99, Kasa etkilenmedi | **PASS** |
| **Grup 3** | 3.3 Veresiye Satış (Mehmet Güven 37.50 TL) | Cari Bakiye -37.50 TL, Defter `debitSale` | Bakiye 77.50 TL, defter tam | **PASS** |
| **Grup 3** | 3.4 Karma Ödeme (20 TL Nakit + 39.90 TL Kart) | `sale_payments` 2 satır, Kasa +20.00 TL | 2 Ödeme satırı, Kasa +20 TL | **PASS** |
| **Grup 3** | 3.5 Nakit İade (Alpella Gofret 16.00 TL) | Stok +1 Restorasyonu, İade Fişi | Stok restore edildi | **PASS** |
| **Grup 4** | 4.1 Z-Raporu Kasa ve Defter Mutabakatı | 0 kuruş sapma | 0 kuruş sapma | **PASS** |
| **Grup 5** | 5.1 Safe Rollback & Idempotency (< 10 sn) | Satışlar legacy'ye aktarılır, 2. tur 0 satış | **403 ms**, 0 mükerrer | **PASS** |

---

### 3. Kod İyileştirmeleri ve Düzeltmeler

- **Finansal Hareket Tür Çakışması Giderildi (`migration_bridge_engine.dart`):**  
  Legacy SQLite tarafında küçük harfle tutulan `type` (`sale`, `payment`, `debt`) ile Core Next tarafındaki büyük harfli `entry_type` (`SALE`, `PAYMENT`, `DEBT`) karşılaştırması büyük/küçük harf duyarsız hale getirildi (`.toLowerCase().trim()`). Bu sayede rollback esnasında oluşabilecek hatalı çakışma alarmları önlendi.

---

### 4. Faz 4'e Geçiş Durumu (Canlı Dağıtım & 72 Saat İzleme)

Faz 3 başarıyla tamamlanmış olup, sistem **Faz 4 (72 Saatlik Gözlem ve Kademeli Rollout)** aşamasına geçmeye hazırdır:

1. **Nutopia Terminali:** `core_next_sales_engine_enabled = true` bayrağı ile satış yapmaya devam eder.
2. **72 Saatlik Gözlem:** Nutopia terminalinde sıfır veri kaybı, 0 kuruş kasa sapması ve stabil donanım performansı izlenir.
3. **Kademeli Rollout:**
   - 4. Gün: %10 Esnaf Grubu
   - 6. Gün: %50 Esnaf Grubu
   - 7. Gün: Erkul Çeyiz ve tüm saha (%100)
