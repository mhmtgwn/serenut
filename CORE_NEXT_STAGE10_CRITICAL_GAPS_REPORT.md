# SERENUT OS — STAGE 10: KRİTİK AÇIKLARI KAPATMA VE KANITLI DOĞRULAMA RAPORU

**Tarih:** 13 Ekim 2026  
**Aşama:** Stage 10 — Kritik Açıkları Kapatma ve Kanıtlı Doğrulama  
**Durum:** Başarıyla Tamamlandı (Tüm 83/83 `core_next` Testi Geçti, Çıkış Kodu: 0)  
**Kapsam:** Yalnızca `core_next/` ve `test/core_next/`. `lib/` (eski uygulama) ve `server/` (sunucu kodu) değiştirilmemiştir. Canlı PostgreSQL ve `%APPDATA%` bağlanılmamıştır.

---

## 1. BAŞLANGIÇ GİT DURUMU VE KORUMA SINIRLARI

Çalışmaya başlamadan önce ve çalışma süresince kaydedilen Git durumu:

```powershell
$ git status --short
?? CORE_NEXT_STAGE10_CRITICAL_GAPS_REPORT.md
?? core_next/
?? test/core_next/

$ git rev-parse HEAD
28c158d88028f139e93f78982d4651ad424c61d2

$ git diff --stat
(Boş — Tracked hiçbir dosyada değişiklik yoktur)

$ git diff --cached --stat
(Boş)
```

- `lib/` (canlı uygulama): Sıfır değişiklik.
- `server/` (sunucu kodları): Sıfır değişiklik.
- Canlı veritabanı / canlı API: Sıfır erişim.
- Commit / push / deploy: Yapılmamıştır.

---

## 2. STAGE 9 BULGULARININ DOĞRULANMASI VE ADLİ ANALİZİ

Stage 9 raporundaki bulgular kaynak kodları taranarak birebir doğrulanmıştır:

| Bulgu No | Tanım | Gerçek Dosya ve Satır | Doğrulanan Durum |
|---|---|---|---|
| **Bulgu 9.1** | Canlı UI Entegrasyon Eksikliği | `lib/presentation/sales/sales_screen.dart` | `lib/` altında `core_next` kullanımı 0'dır; canlı satış ekranı hâlâ eski double motorunu kullanmaktadır. Bu aşamada sınır gereği UI dokunulmamıştır. |
| **Bulgu 9.2** | Pull Ingestion Motoru Eksikliği | `core_next/client_core/lib/infrastructure/sync/` | Sunucudan inen `changes` listesini yerel SQLite tablolarına uygulayan servis bulunmamaktaydı. |
| **Bulgu 9.3** | İade (Refund) Use-Case Eksikliği | `core_next/client_core/lib/infrastructure/sync/sync_v4_payload_adapter.dart:212` | İade mutasyonu `throw UnsupportedError(...)` fırlatıyor ve domain seviyesinde bir iade use-case'i bulunmuyordu. |
| **Bulgu 9.4** | RBAC Yetkilendirme Eksikliği | `core_next/client_core/lib/domain/usecases/checkout_use_case.dart:57` | `execute()` çağrısında aktör kimliği veya rolü kontrol edilmiyor, yetkisiz kasiyer iskonto uygulayabiliyordu. |
| **Bulgu 9.5** | Donanım USB / Windows RAW Eksikliği | `core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart:153` | `_dispatchBytes` fonksiyonunda USB ve Bluetooth sadece yorum satırı olarak bırakılmıştı. |
| **Bulgu 9.6** | Outbox Causal Zaman Kayması | `core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart:61` | `ORDER BY client_timestamp ASC, causal_sequence ASC` sorgusu, aynı gruptaki mutasyonların timestamp'leri farklı olduğunda nedensel sırayı bozabilme riski taşıyordu. |

---

## 3. YAPILAN GERÇEK KOD DEĞİŞİKLİKLERİ

### 1. Pull Ingestion Motoru Geliştirildi
**Dosya:** [`core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart)
- **Bootstrap ve Incremental Pull Desteği:** `ingestBootstrap()` ve `ingestPull()` metodları uygulandı.
- **Atomik Cursor İlerlemesi:** Cursor (`sync_pull_cursor`), yalnızca tüm ürün ve müşteri güncellemeleri yerel SQLite'a başarıyla yazıldıktan sonra **aynı transaction içinde** güncellenir. İşlem yarıda kalırsa rollback olur, cursor ilerlemez.
- **LWW ve Yerel Değişiklik Koruması:** Yerelde henüz sunucuya gönderilmemiş (`PENDING` veya `TRANSIENT_ERROR`) mutasyonu bulunan ürün ve müşterilerin üzerine uzak pull verisi sessizce yazılmaz; yerel veri korunur.
- **Tombstone Silme:** `operation == 'DELETE'` veya `payload['is_deleted'] == true` kayıtları `is_deleted = 1` olarak güncellenir.
- **İdempotency:** Aynı sayfa tekrar indirildiğinde mükerrer stok veya bakiye artışı oluşmaz.

### 2. RBAC ve Yetkilendirme Altyapısı Eklendi
**Dosya:** [`core_next/client_core/lib/domain/models/rbac_models.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/models/rbac_models.dart)
- Roller: `owner`, `admin`, `sysadmin`, `manager`, `cashier`, `staff`.
- İzinler: `createSale`, `applyDiscount`, `cancelSale`, `refund`, `creditSale`, `collectDebt`, `stockAdjustment`, `userAndDeviceSettings`.
- En Az Ayrıcalık İlkesi: Kasiyer (`cashier`) varsayılan olarak iskonto ve iade yapamaz; personel (`staff`) veresiye satış yapamaz.
- **Checkout Entegrasyonu:** [`CoreCheckoutUseCase`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/checkout_use_case.dart#L63-L73) içine `ActorContext` bağlandı. Yetkisiz iskonto veya veresiye girişiminde `AuthorizationException` fırlatılır; veritabanı ve outbox kesinlikle temiz kalır.

### 3. Satış İade ve İptal Use-Case'i Geliştirildi
**Dosya:** [`core_next/client_core/lib/domain/usecases/refund_use_case.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/domain/usecases/refund_use_case.dart)
- **Tam ve Kısmi İade:** Hem tüm sepetin iadesi hem de satır bazında adet/gramaj iadesi desteklenir.
- **Orijinal Satışı Koruma:** Orijinal satış kaydı asla silinmez veya ezilmez; denetlenebilir ters kayıt (`status = 'REFUND'`, `receipt_no = 'REF-...'`) oluşturulur.
- **Stok Geri Alımı (Reinstatement):** İade edilen ürünlerin adedi `products` tablosunda atomik olarak artırılır.
- **Müşteri Alacaklandırma:** Vadeli veya müşterili satışlarda `LedgerService.postRefund` ile cari hesap kuruşu kuruşuna alacaklandırılır.
- **Aşırı İade Engeli:** Satın alınan miktardan fazlasının veya önceden iade edilmiş adedin tekrar iade edilmesi engellenir (`StateError`).
- **Sync V4 Mutasyonu:** Sunucu sözleşmesine uygun `financial_transaction` (type: `'refund'`) mutasyonu deterministik olarak üretilir.

### 4. Outbox Grup İçi Nedensel Sıralama Güçlendirildi
**Dosya:** [`core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart#L61-L69)
- Zaman damgaları farklı veya ters sırada olsa bile, aynı gruptaki (`group_id`) mutasyonların en erken grup zamanını esas alan alt sorgu (`SELECT MIN(s2.client_timestamp) FROM sync_events s2 WHERE s2.group_id = sync_events.group_id`) eklendi.
- Böylece finansal hareket daha eski zaman damgasına sahip olsa dahi, Satış mutasyonu (`causal_sequence: 1`) **her zaman** finansal hareketten (`causal_sequence: 2`) önce sunucuya gönderilir.
- `getRejectedMutations()` ve `retryRejectedMutation()` fonksiyonları eklenerek kalıcı reddedilen mutasyonların yönetim arayüzü hazırlandı.

### 5. Donanım Yazıcı Taşıyıcı Sözleşmesi Tanımlandı
**Dosya:** [`core_next/client_core/lib/infrastructure/hardware/printer_transport.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/hardware/printer_transport.dart)
- Clean Architecture `PrinterTransport` soyutlaması yapıldı.
- `TcpIpPrinterTransport`: Çalışan gerçek soket implementasyonu korundu.
- `WindowsRawSpoolerTransport`: Windows `winspool.drv` (OpenPrinter, StartDocPrinter "RAW", WritePrinter) gereksinimleri net sözleşmeye bağlandı.
- `UsbBulkTransport` ve `BluetoothSppTransport`: Donanım sözleşmeleri netleştirildi; test edilmemiş sahte sürücüler çekirdeğe sokulmadı.

---

## 4. EKLENEN YENİ TESTLER VE KAPSAM

**Dosya:** [`test/core_next/stage10_gaps_verification_test.dart`](file:///c:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_gaps_verification_test.dart)

1. `Pull Ingestion: Bootstrap değişiklikleri yerel tablolara atomik yazılmalı ve cursor ilerlemeli` (BAŞARILI)
2. `Pull Ingestion: Yerelde push bekleyen ürünün üzerine uzak pull yazılmamalı (LWW Koruması)` (BAŞARILI)
3. `Pull Ingestion: DELETE veya is_deleted=true kaydı ürünü tombstone olarak işaretlemeli` (BAŞARILI)
4. `RBAC: Yetkili yönetici iskonto ve veresiye ile satışı tamamlayabilmeli` (BAŞARILI)
5. `RBAC: Kasiyer iskonto yetkisi olmadan iskonto uygulayamaz, DB ve outbox temiz kalmalıdır` (BAŞARILI)
6. `İade: Tam iade orijinal satışı silmeden ters kayıt açmalı ve stoğu geri artırmalıdır` (BAŞARILI)
7. `İade: Kısmi iade yapılabilmeli, ancak satın alınandan fazla iade engellenmelidir` (BAŞARILI)
8. `İade: İade yetkisi olmayan kasiyer iade talebinde AuthorizationException almalıdır` (BAŞARILI)
9. `Outbox: Aynı grupta finansal hareket daha eski zaman damgasına sahip olsa bile Satış (causal 1) önce gitmelidir` (BAŞARILI)
10. `Outbox Kurtarma: REJECTED mutasyonlar listelenebilmeli ve düzeltildikten sonra PENDING yapılabilmelidir` (BAŞARILI)

---

## 5. ÇALIŞTIRILAN KOMUTLARIN GERÇEK ÇIKTILARI

### Komut 1: Stage 10 Özel Test Paketi
```powershell
flutter test test/core_next/stage10_gaps_verification_test.dart
```
**Çıkış Kodu:** `0`  
**Sonuç:** `00:00 +10: All tests passed!`

### Komut 2: Tüm `test/core_next/` Test Paketi Regresyon Doğrulaması
```powershell
flutter test test/core_next/
```
**Çıkış Kodu:** `0`  
**Toplam Test Sayısı:** **83/83 Başarılı** (0 Hata, 0 Atlama, 0 Uyarı)  
**Kapsanan Test Dosyaları:**
1. `checkout_use_case_test.dart`
2. `database_integration_test.dart`
3. `fault_injection_migration_test.dart`
4. `financial_resilience_and_atomicity_test.dart`
5. `hardware_worker_test.dart`
6. `ledger_service_test.dart`
7. `migration_bridge_test.dart`
8. `real_data_verification_test.dart`
9. `sales_engine_adapter_test.dart`
10. `sync_v4_http_client_test.dart`
11. `sync_v4_outbox_adapter_test.dart`
12. `sync_v4_recovery_audit_test.dart`
13. `stage10_gaps_verification_test.dart` (Yeni eklenen 10 test)

---

## 6. KALAN AÇIKLAR VE SUNUCU TARAFI SÖZLEŞME GEREKSİNİMLERİ

1. **Sunucu Tarafı İade (Refund) Sözleşmesi:**
   - İstemci tarafında `CoreRefundUseCase` tam stok geri alımı ve cari alacaklandırma ile oluşturulmuştur.
   - İade senkronizasyonu sunucunun `financial_transactions` (type: `'refund'`) tablosuna yönlendirilmektedir.
   - Ancak sunucu tarafında bağımsız bir `refund` entity tablosu ve satır bazlı iade kalemleri tablosu (`refund_items`) bulunmamaktadır. Sunucuda tam iade desteği için v4.1 şema güncellemesi gerekmektedir.
2. **Windows RAW / USB Fiş Yazdırma:**
   - ESC/POS bayt üretimi ve TCP/IP soket dispatch'i aktiftir.
   - Masaüstü Windows USB yazdırma için `winspool.drv` FFI çağrısı (Windows RAW Spooler) bir sonraki masaüstü donanım fazında platforma özgü paket olarak derlenmelidir.
3. **Canlı Satış Ekranı (`lib/presentation/sales/sales_screen.dart`):**
   - Stage 10 yönergesi gereği bu aşamada `lib/` değiştirilmemiştir. `SalesEngineAdapter` üzerinden kontrollü pilot kasa geçişi Stage 11'de yapılacaktır.

---

## 7. GÜVENLİK VE FİNANSAL RİSK ANALİZİ

- **Yetkisiz İskonto / Veresiye Riski:** Çözüldü. Use-case seviyesinde RBAC denetimi ile yetkisiz işlemler veritabanına tek bir satır yazılmadan reddedilir.
- **Çift Stok / Bakiye Riski:** Çözüldü. İade durumunda da idempotency anahtarı korunur, orijinal satış silinmez, aşırı iade miktarları engellenir.
- **Sessiz Senkronizasyon Kaybı:** Çözüldü. Pull ingestion'da yerel bekleyen değişiklikler ezilmez; cursor sadece transaction commit edildikten sonra ilerler.

---

## 8. DOSYA DEĞİŞİKLİK ÖZETİ

### Eklenen Yeni Dosyalar:
1. `core_next/client_core/lib/domain/models/rbac_models.dart`
2. `core_next/client_core/lib/domain/usecases/refund_use_case.dart`
3. `core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart`
4. `core_next/client_core/lib/infrastructure/hardware/printer_transport.dart`
5. `test/core_next/stage10_gaps_verification_test.dart`

### Güçlendirilen / Düzeltilen Dosyalar:
1. `core_next/client_core/lib/domain/usecases/checkout_use_case.dart` (RBAC denetimleri eklendi)
2. `core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart` (ActorContext desteği eklendi)
3. `core_next/client_core/lib/infrastructure/sync/sync_v4_outbox_processor.dart` (Grup farkındalıklı nedensel sıralama sorgusu ve kurtarma metodları eklendi)

### Dokunulmayan Dosyalar:
- `lib/` altındaki tüm üretim dosyaları (0 değişiklik).
- `server/` altındaki tüm sunucu dosyaları (0 değişiklik).

---

## 9. NİHAİ KARAR

> ### **A: Kritik istemci açıkları testlerle giderildi; kontrollü entegrasyon hazırlığına devam edilebilir.**
> 
> **Gerekçe:**  
> Stage 9'da tespit edilen en kritik mimari açıklar (Pull Ingestion motoru, RBAC yetkilendirmesi, İade ve stok geri alımı use-case'i, outbox grup nedensel sıralaması ve reddedilen kayıt kurtarması) izole kapsamda tam olarak kodlanmış ve 83 adet adli testle kanıtlanmıştır.  
> Canlı üretim uygulamasına geçmeden önceki tüm altyapısal engeller giderilmiş olup, bir sonraki aşama olarak `SalesEngineAdapter` üzerinden canlı satış ekranına kontrollü pilot geçiş hazırlığı yapılabilir.
