# SERENUT OS — STAGE 10.12.94: NUTOPIA CANLI GEÇİŞİ, TAZE YEDEKLEME, DELTA EŞİTLEME VE PİLOT AKTİVASYON RAPORU

**Tarih / Saat:** 22 Ekim 2026, 15:21 (TSİ)  
**Aşama:** Stage 10.12.94  
**Hedef İşletme:** Nutopia Fındık Değirmeni (`comp-1785241628448-c7f5677d`)  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (`main` branch)  
**Yürütülen Script:** `scripts/stage10_12_94_live_backup_and_delta.py`  
**Nihai Karar:** **`NUTOPIA_LIVE_CUTOVER_COMPLETED_AND_PILOT_APPROVED`**

---

## 1. YÜRÜTÜLEN İŞLEMLER VE CANLI KORUMA PROTOKOLÜ

Stage 10.12.93 raporunda tespit edilen son canlı hareket (22 Ekim 13:47:35 satışı) ve kilit riskleri doğrultusunda, canlı kasanın kapatılmasının ardından Stage 10.12.94 canlı cutover operasyonu başarıyla icra edilmiştir:

1. **Uygulama Süreç Güvencesi:**  
   `serenutos.exe` süreci denetlenmiş; işletim sistemi ve veritabanı dosyaları üzerinde hiçbir aktif kilit veya eşzamanlı yazma kalmadığı doğrulanmıştır.
2. **Canlı Taze Yedekleme:**  
   Canlı `%APPDATA%\...\serenut_pos.db` (-wal ve -shm dosyalarıyla birlikte) ve `shared_preferences.json` dosyaları `backups\nutopia_live_20261022_stage94\` altına atomik olarak kopyalanmıştır.
3. **WAL Checkpoint & Bütünlük Denetimi:**  
   Kopyalanan yedek veritabanı üzerinde `PRAGMA wal_checkpoint(TRUNCATE)` yürütülerek tüm geçici hareketler ana DB dosyasına gömülmüş; `PRAGMA integrity_check` ve `PRAGMA foreign_key_check` ile dosya mühürlenmiştir.
4. **Delta Eşitlemesi (Catch-Up):**  
   21 Ekim sonrası gerçekleşen canlı işlemler ve kalemleri taranmış; hedef `serenut_core_v2.db` ve onun alt kopyası `core_next\serenut_core_v2.db` ile birebir eşitlenmiştir.
5. **Çok Boyutlu Finansal & Stok Mutabakatı:**  
   Katalog stok toplamı, cari hesap adetleri, bakiye toplamı ve defter kayıtları doğrulanmıştır.
6. **Mühürleme (Sealing):**  
   - `serenut_core_v2.db` `app_settings` tablosuna `legacy_migration_completed = 'true'` kaydı işlenmiştir.
   - `shared_preferences.json` üzerinde `core_next_bootstrap_migration_state = 'completed'` bayrağı yazılmıştır.

---

## 2. ADLİ YEDEK VE DOSYA BÜTÜNLÜK TABLOSU

| Dosya Tanımı | Konum / Kesin Yol | Boyut (Bayt) | SHA-256 Özeti | Bütünlük / Durum |
|---|---|---|---|---|
| **Canlı Taze Yedek (WAL Checkpoint Sonrası)** | `backups\nutopia_live_20261022_stage94\serenut_pos_live_backup.db` | 61.685.760 | `1806447ae162f297de0fcbd704577893ba42fa0b1b175c915634743affde5ad5` | `integrity_check: ok`, 0 FK İhlali |
| **Ön-Geçiş Ayar Yedeği** | `backups\nutopia_live_20261022_stage94\shared_preferences_pre_cutover.json` | 173.343 | `4635677d...` | Canlı kasanın kesim anındaki kopyası |
| **Referans Stage 84 Yedeği** | `backups\nutopia_pre_cutover_20261021_stage84\serenut_pos_live_backup.db` | 61.468.672 | `72BA16C493634BAF595E1DCAEDF6FCBD74C63CAC28A66BD31F2878E48223C476` | Korunan dondurulmuş yedek (+217 KB canlı delta farkı) |
| **Hedef Canlı Core Next DB**| `%APPDATA%\...\databases\serenut_core_v2.db` | 17.235.968 | `ok` | Eşitlenmiş, `legacy_migration_completed = true` |
| **Hedef Core Next Alt DB**  | `%APPDATA%\...\databases\core_next\serenut_core_v2.db` | 17.235.968 | `ok` | Master kopyayla %100 eşit |
| **Canlı Güncel Ayarlar**    | `%APPDATA%\...\shared_preferences.json` | 177.895 | — | `migration_state: completed`, `pilot_enabled: true` |
| **Adli Kanıt Dosyası**      | `backups\nutopia_live_20261022_stage94\stage94_cutover_result.json` | 746 | Doğrulandı | Otomasyon kanıt çıktısı |

---

## 3. ÇOK BOYUTLU MUTABAKAT VE KANIT MATRİSİ

| Metrik / Alan | Hedef Değer (Core Next) | Kaynak Değer (Legacy Yedek) | Fark / Uyum | Durum |
|---|---|---|---|---|
| **Aktif Ürün Sayısı** | 17 adet vitrin ürünü | 17 adet aktif ürün | **0 Fark** | ✅ Birebir Eşit |
| **Toplam Katalog Stoğu** | 244.786,65 birim | 244.786,65 birim | **0.00 Fark** | ✅ Kuruşu Kuruşuna |
| **Müşteri / Cari Sayısı** | 626 aktif müşteri | 626 müşteri | **0 Fark** | ✅ Tüm Cariler Aktarıldı |
| **Müşteri Bakiye Toplamı** | -135.263,18 TL (-13.526.318 kuruş) | -135.263,18 TL | **0 Kuruş** | ✅ Sıfır Yuvarlama Farkı |
| **Toplam Satış Adedi** | 52 adet | 52 adet | **0 Fark** | ✅ Eksiksiz |
| **Toplam Defter Hareketi** | 1.505 kayıt | 1.505 kayıt | **0 Fark** | ✅ Tüm Hareketler Korundu |
| **Manuel Borçlar (`manual_debt`)** | 54 adet / 103.351,00 TL | 54 adet / 103.351,00 TL | **0 Kuruş** | ✅ Tam Defter Eşleşmesi |
| **Yabancı Anahtar Bütünlüğü** | 0 ihlal | 0 ihlal | **0 İhlal** | ✅ `PRAGMA fk_check: ok` |

---

## 4. PİLOT CUTOVER GATE VE RUNTIME YÖNLENDİRME DOĞRULAMASI

Canlı `shared_preferences.json` üzerinde yapılan mühürleme sonrası `PilotCutoverGate` ve `AppBootstrap.initPreApp()` mimarisi:

1. **Nutopia Tenant Doğrulaması:**
   - `merchant_id: comp-1785241628448-c7f5677d` $\leftrightarrow$ `tenant_id: nutopia` eşleşmesi tamdır.
   - `core_next_pilot_enabled == true`
   - `core_next_kill_switch == false`
   - `core_next_bootstrap_migration_state == 'completed'`
   - **Sonuç:** **`PilotGateStatus.pilotActiveApproved`** (Pilot aktif ve Core Next veritabanına yönlendirilmiş).
2. **Repository Yönlendirmesi (Pilot Modu):**
   - `productRepositoryProvider` $\rightarrow$ `CoreNextProductRepository`
   - `customerRepositoryProvider` $\rightarrow$ `CoreNextCustomerRepository`
   - `financialTransactionRepositoryProvider` $\rightarrow$ `CoreNextFinancialTransactionRepository`
   - `saleRepositoryProvider` $\rightarrow$ `SqliteSaleRepository` *(Satış motoru pilot güvenlik kuralı gereği legacy modunda fail-safe korunmaktadır)*.
3. **Erkul Çeyiz İzolasyon Güvencesi:**
   - Erkul Çeyiz lisans token'ı (`comp-1791194455402-bdc6d8d1`) ile sorgulama yapıldığında sistem fail-closed davranarak **`PilotGateStatus.blockedTenantMismatch`** üretmektedir.
   - Nutopia veritabanına Erkul Çeyiz'in temas etmesi imkansız kılınmıştır.
4. **Geri Dönüş (Rollback) Güvencesi:**
   - `backups\nutopia_live_20261022_stage94\` altındaki dondurulmuş yedek ve `migration_bridge_engine.dart` altındaki `ReverseMigrationEngine` motoru acil bir durumda tek tıkla eski legacy sisteme dönme yeteneğine sahiptir.

---

## 5. SONUÇ VE KARAR

### **NİHAİ KARAR: `NUTOPIA_LIVE_CUTOVER_COMPLETED_AND_PILOT_APPROVED`**

1. **Veri Kayıpsızlığı Kanıtlandı:** Nutopia Fındık Değirmeni'nin tüm ürünleri, stokları, cari hesapları, manuel borçları ve satışları kuruşu kuruşuna Core Next hedef veritabanına eşitlenmiştir.
2. **Canlı Taze Yedek Alındı:** 22 Ekim 15:21 itibarıyla en güncel canlı veritabanı (`1806447ae162...`, 61,6 MB) yedeklenip adli olarak kilitlenmiştir.
3. **Cutover Mühürlendi:** Canlı `shared_preferences.json` ve Core Next `app_settings` üzerinde geçiş tamamlandı (`completed`) olarak tescil edilmiştir.
4. **Pilot Kapısı Açıldı:** `PilotCutoverGate` yeşil ışık yakmış (`pilotActiveApproved`), sistem taze Stage 91 Release paketiyle Core Next pilotunda çalışmaya hazır hale getirilmiştir.
5. **Erkul Çeyiz ve Satış Motoru Korundu:** Tenant sınırları ve satış güvenliği eksiksiz muhafaza edilmiştir.
