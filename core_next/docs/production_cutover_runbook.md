# Serenut OS — Canlıya Geçiş ve Dağıtım Koşu Kitabı
## (Production Cutover & Rollout Runbook)

> [!IMPORTANT]
> **Zorunlu Prensip**: Bu koşu kitabı, sahadaki esnafın günlük operasyonunu ve cirosunu sıfır kesintiyle korumak amacıyla hazırlanmıştır. Herhangi bir aşamada beklenmeyen bir hata tespit edilirse, sistem otomatik olarak yedeklenen `.backup` SQLite dosyasına döner.

---

## 1. Geçiş Öncesi Kontrol Listesi (Pre-Flight Checklist)

Canlıya çıkıştan 24 saat önce aşağıdaki kontroller tamamlanmalıdır:

- [ ] **Birim Testleri Doğrulandı:** `flutter test test/core_next/` komutu ile 13 birim ve entegrasyon testinin tamamı yeşil olmalı.
- [ ] **Yedekleme Mekanizması Hazır:** Eski `serenutos.db` dosyasının fiziksel kopyasının alınacağı disk alanı doğrulanmalı.
- [ ] **Ağ Bağımsızlığı Doğrulandı:** Kasa internetsiz modda en az 5 satış yapıp deftere yazabilmeli.
- [ ] **Yazıcı Isolate Testi:** Test fişi ve etiket basımı sırasında UI FPS düşüşü yaşanmadığı teyit edilmeli.

---

## 2. Pilot Şube Geçiş Adımları (Aşama 1 — 72 Saat)

Pilot esnaf kasasında geçiş şu sırayla uygulanır:

### Adım 1: Uygulamanın İlk Açılışı
1. Yeni Serenut OS v2.0 paketi kasaya yüklenir.
2. Uygulama açılırken `MigrationBridgeEngine.isMigrationCompleted()` kontrolü yapar.
3. Değer `false` ise:
   * `serenutos.db` dosyası `serenutos.db.backup` olarak kopyalanır.
   * `MigrationBridgeEngine.migrateFromLegacy()` tek bir SQLite transaction'ında çalışır.
   * Kuruş dönüşümü (`price * 100`) ve cari bakiye aktarımı tamamlanır.
   * `app_settings` tablosuna `legacy_migration_completed = true` bayrağı yazılır.

### Adım 2: Kasa Kapanış ve Gün Sonu Mutabakatı
1. Kasiyer gün sonunda Z-Raporu ve Kasa Sayımı alır.
2. Eski ciro toplamı ile yeni kuruş bazlı ciro toplamı kuruşu kuruşuna karşılaştırılır.
3. Müşteri borç ekstreleri kontrol edilir.

---

## 3. Geri Alma (Rollback) Prosedürü

Eğer geçiş sırasında veya sonrasında kritik bir uyumsuzluk tespit edilirse:

```bash
# Geri Alma Adımları:
1. Uygulamayı kapatın.
2. serenut_core_v2.db dosyasını silin.
3. serenutos.db.backup dosyasını serenutos.db olarak geri yükleyin.
4. Eski sürüm APK/EXE ile sistemi anında yeniden başlatın.
```
* **Geri Alma Süresi:** < 10 saniye.
* **Veri Kaybı:** Sıfır (Eski veritabanı dosyasına hiçbir zaman yazma/silme yapılmaz).

---

## 4. Genel Canlıya Dağıtım (Aşama 2 — Kademeli Rollout)

Pilot şube 72 saati sıfır hata ile tamamladıktan sonra:
* **Gün 1:** %10 Esnaf Grubu (OTA Dağıtım)
* **Gün 3:** %50 Esnaf Grubu
* **Gün 5:** %100 Tüm Canlı Saha

---

## 5. Sağlık ve Doğrulama Komutları

Geçiş sonrası veritabanı bütünlüğünü doğrulamak için:
```sql
-- SQLite Bütünlük Kontrolü
PRAGMA integrity_check;
PRAGMA foreign_key_check;

-- Eşleşmeyen veya Bozuk Bakiye Kontrolü
SELECT id, name, balance_cents FROM customers WHERE balance_cents IS NULL;
```
