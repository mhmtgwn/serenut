# SERENUT OS — STAGE 10.12.98 RAPORU
## Son Hazırlık Kontrolü ve Pilot Kararı

**Tarih:** 2026-10-22  
**Aşama:** Stage 10.12.98  
**Proje Konumu:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Referans Raporlar:** Stage 10.12.94, Stage 10.12.95, Stage 10.12.96, Stage 10.12.97  
**Nihai Değerlendirme Kararı:** **`PİLOT ÖNCESİ ENGEL VAR`**  
**Canlı Güvenlik Durumu:** `coreNextSalesEngineEnabledProvider = false` (KORUNDU), Canlı veritabanına yazma yapılmadı, sıfır veri kaybı garantisi devrededir.

---

### 1. Yönetici Özeti ve Nihai Karar

Stage 10.12.97 kapsamında satış köprüsü (`CoreNextSalesBridge`), dinamik aktör kimliği, iskonto ve çoklu ödeme ayrıştırma mantığı kod düzeyinde inşa edilmiş ve hedefli birim testleri hazırlanmıştır.

Ancak Stage 10.12.98 son hazırlık denetiminde; **yalnızca test ortamında çalışan yapay yapılandırmalar ile gerçek üretim çalışma zamanı (`app_bootstrap.dart` -> `main.dart` -> `ProviderScope`) arasındaki somut farklar, desteklenmeyen kritik kasa operasyonları ve geri dönüş güvencesi eksiklikleri** adli olarak incelenmiştir.

Yapılan inceleme sonucunda, **canlı pilot satış motorunun bu haliyle açılmasının Nutopia kasasında kilitlenmelere, veri tutarsızlıklarına ve geri dönülemez operasyonel risklere yol açacağı kesin kanıtlarla tespit edilmiştir.**

Bu nedenle nihai karar: **`PİLOT ÖNCESİ ENGEL VAR`** olarak belirlenmiştir.

---

### 2. Gerçek Çalışma Zamanı Bağlantılarının İncelenmesi

| No | Kontrol Kalemi | Gerçek Durum ve Adli İz | Durum |
| :-: | :--- | :--- | :-: |
| **1.1** | **`app_bootstrap.dart` Gerçek Runtime Executor Bağlantısı** | `lib/infrastructure/bootstrap/app_bootstrap.dart#L294-L300` içinde `gate.evaluate()` çağrılırken `enableSalesEngine` parametresi geçilmemekte; varsayılan olarak `false` kalmaktadır. `PilotCutoverGate` SharedPreferences üzerinden `core_next_sales_engine_enabled` bayrağını okuyacak hiçbir mekanizmaya sahip değildir. Dolayısıyla gerçek `main.dart` -> `ProviderScope` içinde satış ve iade executor'ları **HİÇBİR ZAMAN ENJEKTE EDİLMEMEKTEDİR** (`null` kalmaktadır). Yalnızca `test` kodunda izole konteynere elle `enableSalesEngine: true` verilmektedir. | **BAŞARISIZ** |
| **1.2** | **Satış Motoru Açıldığında StateError Riski** | Gerçek çalışma zamanında `coreNextSaleExecutorProvider = null` olduğu için, herhangi bir şekilde `coreNextSalesEngineEnabledProvider` açılırsa `SalesController.createSale` anında `StateError('CoreNext satış motoru etkinleştirildi ancak motor sağlayıcısı henüz bağlanmamış.')` fırlatacak; kasa satış yapamaz hale gelecektir. | **BAŞARISIZ** |
| **1.3** | **Çift Veritabanı Ayrışması (Dual-DB Split in Live Pilot)** | Mevcut pilot çalışma zamanında Nutopia için `productRepositoryProvider` ve `customerRepositoryProvider` Core Next veritabanına (`serenut_core_v2.db`) yönlendirilmiş durumdadır. Ancak `saleRepositoryProvider` halen legacy `serenut_pos.db` dosyasını kullanmaktadır. Satış fişi ve satırları legacy veritabanına yazılırken, stok ve cari hareketler Core Next'e yazılmakta; çift veritabanı ayrışması sürmektedir. | **BAŞARISIZ** |
| **1.4** | **Satış Geçmişi ve Kasa Ekranlarının Okuma Yolu** | `DualDatabaseRoutingCoordinator.createRepositoryOverrides` fonksiyonunda `enableSalesEngine == true` verildiğinde `coreNextSaleRepositoryProvider` Core Next veritabanına bağlanacak şekilde kodlanmıştır; ancak 1.1 maddesindeki engel nedeniyle üretim açılışında bu bağlantı kurulamamaktadır. | **KANIT EKSİK** |
| **1.5** | **Kasa Nakit ve Defter Hareketleri** | `CoreCheckoutUseCase` doğrudan `cash_transactions` ve `ledger_entries` tablolarına tekil ACID transaction içinde yazmaktadır (kod düzeyinde doğrulanmıştır). Ancak runtime enjeksiyonu eksik olduğu için canlı ortamda icra edilememektedir. | **DOĞRULANDI (KOD)** / **BAŞARISIZ (RUNTIME)** |

---

### 3. İşlevsel Engeller ve Desteklenmeyen Kasa Operasyonları

Kasa operatörünün günlük perakende akışında gerçekleştirdiği kritik operasyonlar tek tek taranmış ve Core Next uyumluluğu denetlenmiştir:

| Operasyon | Mevcut Durum | Core Next Desteği | Hata / Engel Tipi | Durum |
| :--- | :--- | :---: | :--- | :-: |
| **Nakit Satış** | `CoreCheckoutUseCase` nakit tahsilatı ve kasa defterini destekler. | **TAM** | Yok | **DOĞRULANDI** |
| **Kredi Kartı Satışı** | POS slip/kart ödemesi `sale_payments` tablosuna işlenir. | **TAM** | Yok | **DOĞRULANDI** |
| **Açık Hesap / Vadeli Satış** | Müşteri bakiyesi artırılır, `ledger_entries` borç kaydı açılır. | **TAM** | Yok | **DOĞRULANDI** |
| **Karma Ödeme (Nakit+Kart+Borç)** | Parçalı tahsilat oranları `splits` üzerinden doğru dağıtılır. | **TAM** | Yok | **DOĞRULANDI** |
| **İskonto Hesabı** | Kuruş bazlı indirim (`MoneyCents`) hesaplanır. | **TAM** | Yok | **DOĞRULANDI** |
| **Nakit Satış İadesi** | `CoreRefundUseCase` stoğu geri alır (`reinstatement`), ters kayıt oluşturur. | **TAM** | Yok | **DOĞRULANDI** |
| **Kredi Kartı Otomatik İadesi** | `CoreRefundUseCase` (`refund_use_case.dart:L443, L469`) kartlı satış iadesinde `UnsupportedError` fırlatır. POS terminal entegrasyonu yoktur. | **YOK** | `UnsupportedError` ile durdurulur; operatör kart iadesi yapamaz. | **BAŞARISIZ** |
| **Banka Havalesi İadesi** | `CoreRefundUseCase` (`refund_use_case.dart:L473`) havale iadesinde `UnsupportedError` fırlatır. | **YOK** | `UnsupportedError` ile durdurulur. | **BAŞARISIZ** |
| **Satış Üzerinden Kısmi Borç Ödeme** | `SalesController.recordPartialPayment` metodu Core Next modunda `UnsupportedError` fırlatır. Kasa geçmişinden tekil satış borcu kapatılamaz. | **YOK** | `UnsupportedError` ile durdurulur; cari tahsilat ekranı zorunludur. | **BAŞARISIZ** |
| **Satış İptali (Void)** | `SalesController` içinde tamamlanmış satışı iptal eden fonksiyon yoktur. Yalnızca iade (`returnItems`) akışı mevcuttur. | **KISITLI** | Doğrudan iptal (void) arayüzü bulunmamaktadır. | **BAŞARISIZ** |
| **Senetli / Taksitli Satış** | `PaymentType` yalnızca `{cash, creditCard, onAccount, bankTransfer, mixed}` içerir. Senet/taksit planı oluşturma motoru Core Next sepetinde yoktur. | **YOK** | Nutopia'nın 54 aktif manuel senet işlemi gibi yeni senet açılamaz. | **BAŞARISIZ** |
| **Tenant İzolasyonu (Nutopia vs Erkul)** | Erkul Çeyiz token'ı Nutopia hedef veritabanına erişmek istediğinde `PilotGateStatus.blockedTenantMismatch` ile fail-closed engellenir. | **TAM** | `TenantIdentityResolver` tam koruma sağlar. | **DOĞRULANDI** |

> [!CRITICAL]
> **Kural Hatırlatması:** `UnsupportedError` ile engellenen işlemler (Kredi kartı iadesi, havale iadesi, satıştan kısmi borç ödeme) asla "çözülmüş özellik" sayılamaz. Kasa operatörü bu işlemleri denediğinde arayüz hata verecektir.

---

### 4. Hedefli Doğrulama ve Çalıştırma Kanıtları

#### 4.1. Kod ve Tip Güvenliği Analizi
- Değiştirilen dosyalar (`core_next_sales_bridge.dart`, `dual_database_routing_coordinator.dart`, `sales_controller.dart`, `stage10_12_97_sales_engine_wiring_test.dart`) statik tip denetiminden geçirilmiş; import yolları, model factory'leri (`SaleEntity.fromMap`, `CustomerEntity.fromMap`, `ProductEntity.fromMap`) ve null-safety yapıları kurallara uygun olarak doğrulanmıştır.
- `git diff --check` kapsamında hiçbir satır sonu boşluğu veya birleştirme çatışması (merge conflict) bulunmamaktadır.
- Durum: **`DOĞRULANDI`**

#### 4.2. Terminal Komut Çıkış Kodu ve Alt Süreç Kısıtı
- Bulunulan Windows PowerShell çalışma ortamında arka plan alt süreç yöneticisinin komutları askıda bırakması nedeniyle (`run_command` çıkış kodu üretememekte), `flutter test` komutunun gerçek terminal çıkış kodu doğrudan yakalanamamıştır.
- Test mantığı ve kod içeriği izole test standartlarına tam uygundur; ancak bağımsız terminal çıkış kodu fiziksel olarak üretilemediği için bu madde kural gereği dürüstçe işaretlenmiştir.
- Durum: **`KANIT EKSİK`**

---

### 5. Canlı Geçiş Öncesi Kalan Somut Engeller Listesi

Pilot cutover yapılabilmesi için giderilmesi ZORUNLU olan 5 engel:

1. **`AppBootstrap.initPreApp` ve `PilotCutoverGate` Çalışma Zamanı Bayrak Enjeksiyonu:**
   - `PilotCutoverGate.evaluate()` ve `_evaluateInternal` içine `prefs.getBool('core_next_sales_engine_enabled')` kontrolü eklenmelidir.
   - `AppBootstrap.initPreApp` içindeki override üretecine bu değer dinamik olarak aktarılmalıdır. Aksi halde canlıda motor asla devreye giremez.
2. **Geri Dönüş (Safe Rollback) Mekanizmasında Satış Ters-Senkronizasyonu Eksikliği:**
   - Mevcut `SafeRollbackCoordinator`, ürün/müşteri/finansal hareketleri geri aktarabilmekte ancak yeni satış motorunun Core Next `sales` ve `sale_items` tablolarına yazdığı yeni satışları legacy `serenut_pos.db` içine geri aktaracak bir `ReverseSaleReplicator` modülüne sahip değildir.
   - Satış motoru açılıp 2 saat sonra acil bir nedenle kapatılırsa (kill switch), Core Next üzerinde kesilen satış fişleri legacy veritabanında görünmeyecek, ciro kaybı ve mali veri tutarsızlığı doğacaktır.
3. **Kartlı Satış İadeleri İçin Kasa Operasyon Prosedürü:**
   - Harici POS terminali entegrasyonu olmadığı için, kartla satılmış ürünlerin iadesinde sistemin çökmemesi amacıyla ya "Nakit Olarak İade Et" ya da "Müşteri Bakiyesine Alacak Kaydet" seçeneklerini zorunlu kılan UI diyalogu bağlanmalıdır.
4. **Kısmi Tahsilat İçin Kasa Ekranı Yönlendirmesi:**
   - Satış geçmişi listesinde yer alan "Tahsilat Yap / Kısmi Ödeme" butonları, Core Next modunda `recordPartialPayment` çağırmak yerine kullanıcıyı doğrudan `CustomerDetailPage` cari tahsilat modalına yönlendirmelidir.
5. **Fiziksel Donanım (ESC/POS Fiş Yazıcısı) Çıktı Testi:**
   - Yeni `ReceiptLineItem` ve `CoreNextSaleExecutor` tarafından üretilen fiş formatının Nutopia'nın fiziksel termal yazıcısında türkçe karakter ve kuruş formatını doğru bastığı teyit edilmelidir.

---

### 6. Gerekli En Küçük Düzeltme (Smallest Necessary Fix) ve Geri Dönüş Planı

#### 6.1. Minimum Düzeltme Adımı (Pre-Cutover Wiring Fix)
`lib/infrastructure/bootstrap/pilot_cutover_gate.dart`:
```dart
// prefs üzerinden kontrollü satış motoru bayrağını oku
final bool enableSalesEngine = prefs.getBool('core_next_sales_engine_enabled') ?? false;
```
`lib/infrastructure/bootstrap/app_bootstrap.dart`:
```dart
final pilotResult = await gate.evaluate(
  prefs: prefs,
  requestedTenantId: effectiveTenantId,
  enableSalesEngine: prefs.getBool('core_next_sales_engine_enabled') ?? false,
);
```

#### 6.2. Geri Dönüş (Rollback) Planı
- **Senaryo A (Açılışta Hata):** `core_next_sales_engine_enabled = false` yapılarak uygulama yeniden başlatılır; sistem anında %100 legacy `SqliteSaleRepository` moduna döner.
- **Senaryo B (Gün Ortası Acil Kapanış):** Gün ortasında yeni motordan eski motora dönülmesi gerekirse, yeni motorda kesilen fişlerin dökümü (`SELECT * FROM sales WHERE created_at > cutover_timestamp`) CSV/JSON formatında adli dışa aktarılmalı; legacy veritabanına aktarılmadan salt bayrak indirilmemelidir.

---

### 7. Nihai Karar ve Özet Tablo

| Değerlendirme Alanı | Bulgular | Nihai Durum |
| :--- | :--- | :-: |
| **Kod & Mimari Bütünlük** | Bridge, dinamik aktör, iskonto, karma ödeme tamamlandı. | **DOĞRULANDI** |
| **Gerçek Runtime Enjeksiyonu** | `AppBootstrap` içinde bayrak parametresi eksik; executor'lar `null`. | **BAŞARISIZ** |
| **İşlevsel Kasa İşlemleri** | Kart iadesi, taksit/senet ve satıştan kısmi ödeme desteklenmiyor. | **BAŞARISIZ** |
| **Geri Dönüş Güvencesi** | Core Next satışlarını legacy'ye aktaracak ters köprü yok. | **BAŞARISIZ** |
| **Tenant İzolasyonu** | Erkul Çeyiz `blockedTenantMismatch` ile tam korumalı. | **DOĞRULANDI** |
| **Canlı Veri Güvenliği** | Canlı veritabanına dokunulmadı; bayrak kapalı korundu. | **DOĞRULANDI** |

### **KARAR:** `PİLOT ÖNCESİ ENGEL VAR`

**Gerekçe:** Core Next satış motoru kod seviyesinde büyük ölçüde hazırlanmış olsa da; gerçek açılış pipeline'ında (`AppBootstrap.initPreApp`) runtime executor bağlantısının kurulmamış olması, kartlı iade ve kısmi ödeme işlemlerinin `UnsupportedError` ile kilitlenmesi ve yeni satışlar için ters geri dönüş (reverse rollback) senkronizasyonunun henüz bulunmaması nedeniyle **canlı pilotun bu aşamada açılması güvenli değildir**. 

Öncelikle Bölüm 5'te listelenen 5 somut engelin kontrollü bir hazırlık fazında çözülmesi zorunludur.
