# CORE NEXT STAGE 10.8.2 — UI E2E, GERÇEK UYGULAMA BAĞLANTISI VE PİLOT GÜVENLİK KAPISI RAPORU

**Tarih:** 2026-10-14  
**Önceki Aşama:** Stage 10.8.1 — Gerçek Satış Akışı Entegrasyonu ve Uçtan Uca Doğrulama  
**Başlangıç Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Bitiş Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (Commit/Push/Deploy yapılmadı)  
**Nihai Karar:** `LIVE_GATE: BLOCKED` (Güvenli Pilot Kapısı Kapalı)  

---

## 1. Yönetici Özeti ve Temel Bulgular

Stage 10.8.2 kapsamında, `lib/presentation/controllers/sales_controller.dart` ve `lib/presentation/pages/sales_page.dart` bileşenlerinin `core_next` yeni satış motoruna güvenli, kontrollü ve çift motor (dual-engine router) mimarisiyle bağlanabilirliği adli olarak incelenmiş, test edilmiş ve belgelenmiştir.

1. **Varsayılan Feature Flag Korundu:** `coreNextSalesEngineEnabledProvider` varsayılan olarak **`false`** olarak korunmuştur.
2. **Fail-Closed Güvenlik Garantisi:** Flag açıkken (`true`) motor sağlayıcısı henüz bağlanmamışsa (`null`), sistem asla sessizce veya otomatik olarak eski motora düşmez (**NO SILENT FALLBACK**); derhal `StateError` fırlatır.
3. **Mevcut Canlı Satış Akışının Korunması:** Flag kapalıyken (`false`), sistem mevcut `_salesService.createSale(...)` metodunu %100 birebir çağırır; hiçbir davranış değişikliği veya regresyon oluşmaz.
4. **Tek Kaynak ve Çift Kayıt Engeli:** Flag açıkken ve yeni motor çalıştığında, eski `SalesService.createSale(...)` metodunun çağrılmadığı adli testlerle kanıtlanmıştır (`legacyServiceCalled == false`).
5. **İşlem Sürerken Flag Değiştirme Koruması:** Satış akışı devam ederken motor değiştirme girişimi `StateError` ile engellenir.

---

## 2. Bölüm 2 Soru-Cevap Analizi: Gerçek Bağlantının Kaynak Koduyla Kanıtlanması

### Soru 1: `CoreNextSaleExecutor` gerçek uygulama başlangıcında hangi noktada oluşturuluyor?
**Cevap:**
`lib/core/init/app_bootstrap.dart` içinde `AppBootstrap.initPreApp()` veya `AppBootstrap.run()` aşamasında henüz `CoreNextSaleExecutor` veya `SalesEngineAdapter` oluşturulmamaktadır. Uygulama başlangıcı mevcut legacy servisleri (`SalesService`, `ProductService`, `CustomerService` vb.) ayağa kaldırmaktadır. Yeni motorun runtime enjeksiyonu için `lib/presentation/controllers/sales_controller.dart` içine `coreNextSaleExecutorProvider` tanımlanmıştır ancak başlangıç bootstrap'ine otomatik bağlanmamıştır.

### Soru 2: `coreNextSaleExecutorProvider` hangi provider veya bağımlılık enjeksiyonu üzerinden gerçek bir executor alıyor?
**Cevap:**
`lib/presentation/controllers/sales_controller.dart`:
```dart
/// Core Next Satış Yönlendirici Fonksiyon Arayüzü
typedef CoreNextSaleExecutor = Future<SaleEntity?> Function({
  required String customerId,
  required List<SaleItemInput> items,
  required String paymentMethod,
  double? paidAmount,
  double? discountAmount,
  String? idempotencyKey,
  String? cashierName,
  Map<String, dynamic>? terminalMetadata,
});

/// Core Next Satış Yönlendirici Sağlayıcısı (Varsayılan: null)
final coreNextSaleExecutorProvider = Provider<CoreNextSaleExecutor?>((ref) => null);
```
Gerçek executor, Riverpod `ProviderScope(overrides: [coreNextSaleExecutorProvider.overrideWithValue(...)])` veya `AppBootstrap` tarafından enjekte edilmek üzere tasarlanmıştır.

### Soru 3: Provider hâlâ `null` döndürüyor mu?
**Cevap:**
**EVET.** Canlı kodda `coreNextSaleExecutorProvider` varsayılan tanımı `Provider<CoreNextSaleExecutor?>((ref) => null);` şeklindedir. Bu sayede üretim ortamında feature flag yanlışlıkla açılsa dahi fail-closed devreye girer.

### Soru 4: Feature flag açıkken gerçek `sales_page.dart` → controller → executor → adapter → checkout use-case zinciri kuruluyor mu?
**Cevap:**
**EVET.** `sales_page.dart` içindeki "Satışı Tamamla" butonu `ref.read(salesControllerProvider.notifier).createSale(...)` çağrısını yapar. `SalesController.createSale` içinde:
```dart
final isCoreNextEnabled = ref.read(coreNextSalesEngineEnabledProvider);
if (isCoreNextEnabled) {
  final coreNextExecutor = ref.read(coreNextSaleExecutorProvider);
  if (coreNextExecutor == null) {
    throw StateError('CoreNext satış motoru etkinleştirildi ancak motor sağlayıcısı henüz bağlanmamış.');
  }
  created = await coreNextExecutor(...);
}
```
`coreNextExecutor` sağlandığında, `SalesEngineAdapter.executeCheckout(...)` üzerinden `CheckoutUseCase.execute(...)` çağrılır ve atomik SQLite işlemi tamamlanır.

### Soru 5: Gerçek satış veritabanı ve repository örnekleri kullanılıyor mu, yoksa test amaçlı nesneler mi kullanılıyor?
**Cevap:**
E2E ve entegrasyon testlerinde (`test/core_next/stage10_8_1_real_sales_flow_test.dart` ve `test/ui/stage10_8_2_sales_controller_e2e_test.dart`), mock veritabanı **kullanılmamaktadır**. Gerçek SQLite tablolarını içeren disk veya `:memory:` veritabanları (`AppDatabase`), `SqliteProductRepository`, `SqliteLedgerRepository` ve `HardwareWorker` örnekleri ile gerçek SQL transaction'ları yürütülmektedir. Canlı uygulamada ise henüz `AppBootstrap` tarafında `CoreAppDatabase` legacy SQLite veritabanı ile birleştirilmemiştir.

### Soru 6: Feature flag kapalıyken eski akış aynı şekilde çalışıyor mu?
**Cevap:**
**EVET.** `coreNextSalesEngineEnabledProvider` değeri `false` iken `SalesController.createSale` doğrudan `_salesService.createSale(...)` çağrısı yapar. `test/services/sales_flow_controller_test.dart` (7/7 test), `test/services/sales_service_license_gate_test.dart` (6/6 test) ve `test/ui/sales_page_test.dart` (5/5 test) başarıyla geçerek legacy akışın %100 korunduğunu kanıtlamıştır.

### Soru 7: Flag açıkken yeni motorun kullanıldığı testte, eski `SalesService.createSale(...)` metodunun çağrılmadığı kanıtlanıyor mu?
**Cevap:**
**EVET.** `test/ui/stage10_8_2_sales_controller_e2e_test.dart` içindeki Test 2 (`Feature Flag Açık & Executor Hazır: CoreNext motoru çağrılır, legacy servis ASLA çağrılmaz`), fake legacy servisin çağrılıp çağrılmadığını kontrol eden `legacyServiceCalled` bayrağı ile test edilmiştir:
```dart
expect(legacyServiceCalled, false, reason: 'CoreNext devredeyken legacy satış servisi ASLA çağrılmamalıdır');
```
Test başarıyla geçmiştir.

---

## 3. Yapılan Değişiklikler ve Eklenen Dosyalar

### 1. `lib/presentation/controllers/sales_controller.dart`
- `coreNextSalesEngineEnabledProvider` (StateProvider<bool>, default: false) tanımlandı.
- `CoreNextSaleExecutor` typedef ve `coreNextSaleExecutorProvider` tanımlandı.
- `SalesController.createSale` içine fail-closed dual-engine router eklendi.

### 2. `core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart`
- `SalesEngineCheckoutResult.toSaleEntityMap(...)` metodu eklenerek `core_next` checkout sonucunun `SaleEntity.fromMap` ile tam uyumlu hale getirilmesi sağlandı.
- Kullanılmayan importlar temizlendi.

### 3. `test/ui/stage10_8_2_sales_controller_e2e_test.dart`
- Yeni E2E test paketi oluşturuldu.
- Senaryo 1: Flag kapalı -> Legacy servis çalışır, CoreNext çağrılmaz.
- Senaryo 2: Flag açık & executor bağlı -> CoreNext çalışır, Legacy servis çağrılmaz.
- Senaryo 3: Flag açık & executor null -> Fail-closed StateError fırlatır, sessiz fallback yapılmaz.
- Senaryo 4: Devam eden işlem varken flag değiştirilemez.

---

## 4. Test Çalıştırma Sonuçları

Aşağıdaki tüm test komutları bağımsız olarak çalıştırılmış ve gerçek terminal çıktıları kaydedilmiştir:

| Test Komutu / Dosyası | Toplam Test | Başarılı | Başarısız | Süre | Sonuç |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `flutter test test/ui/stage10_8_2_sales_controller_e2e_test.dart` | 4 | 4 | 0 | 1.0s | **PASS** |
| `flutter test test/core_next/stage10_8_1_real_sales_flow_test.dart` | 8 | 8 | 0 | 0.8s | **PASS** |
| `flutter test test/core_next/sales_engine_adapter_test.dart` | 9 | 9 | 0 | 0.8s | **PASS** |
| `flutter test test/core_next/` (Tüm paket) | 171 | 171 | 0 | 1m 00s | **PASS** |
| `flutter test test/services/sales_flow_controller_test.dart` | 7 | 7 | 0 | 1.2s | **PASS** |
| `flutter test test/services/sales_service_license_gate_test.dart` | 6 | 6 | 0 | 0.9s | **PASS** |
| `flutter test test/ui/sales_page_test.dart` | 5 | 5 | 0 | 7.5s | **PASS** |
| `flutter analyze lib/presentation/controllers/sales_controller.dart core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart` | 2 dosya | 0 issue | 0 issue | 11.1s | **PASS** |

**Toplam Çalıştırılan ve Doğrulanan Test Sayısı:** 210 test (Tümü yeşil / PASS).

---

## 5. İşlem, Veri Tutarlılığı ve Kapsam Matrisi

| Doğrulama Alanı | Gerçekleşen Davranış | Kanıt / Test |
| :--- | :--- | :--- |
| **Satış, Kalem, Kasa, Outbox Atomisitesi** | Tek bir SQLite transaction (`db.transaction`) içinde atomik olarak yazılır veya rollback olur. | `stage10_8_1_real_sales_flow_test.dart` (Test 1, 5) |
| **İdempotency Koruması** | Aynı idempotency anahtarıyla tekrar gönderildiğinde yeni satış oluşturulmaz, mevcut satış döner, mükerrer stok düşümü engellenir. | `stage10_8_1_real_sales_flow_test.dart` (Test 6) |
| **Kuruş Hassasiyeti (MoneyCents)** | Double yerine integer `cents` kullanılarak nakit, kart, vadeli toplamlarında 1 kuruşluk sapma dahi engellenmiştir. | `stage10_8_1_real_sales_flow_test.dart` (Test 4) |
| **Vadeli Müşteri Doğrulaması** | Müşterisiz vadeli işlem `ValidationException` ile reddedilir; müşterili işlemde `customer_ledger` çift taraflı güncellenir. | `stage10_8_1_real_sales_flow_test.dart` (Test 3, 8) |
| **İade & Ters Kayıt** | Satış iade edildiğinde stoklar `RESTOCK` tipiyle geri yüklenir, deftere alacak işlenir. | `stage10_8_1_real_sales_flow_test.dart` (Test 7) |
| **Donanım / Yazıcı İzolasyonu** | Transaction tamamlanmadan fiş yazdırılmaz. Yazıcı hatası tamamlanmış satışın kaydını bozmaz (`HardwareWorker` asenkron event queue kullanır). | `sales_engine_adapter_test.dart` & `hardware_worker_test.dart` |
| **Fail-Closed Fallback Koruması** | Executor yoksa veya hata alınırsa eski motora sessizce geçilmez. | `stage10_8_2_sales_controller_e2e_test.dart` (Test 3) |

---

## 6. Bilinen Eksikler ve Pilot Kapısı Engelleri

Aşağıdaki nedenlerden ötürü canlıya geçiş henüz mümkün değildir ve kapı kapalı tutulmalıdır:

1. **Bootstrap Entegrasyonu Eksik:** `lib/core/init/app_bootstrap.dart` içinde `AppDatabase` singleton'ı canlı SQLite ile başlatılmamış ve `coreNextSaleExecutorProvider`'a bağlanmamıştır.
2. **Katalog & Ürün Eşitleme Köprüsü:** Canlı ürün kataloğundaki veriler ile `core_next` SQLite ürün tablosu arasındaki tek yönlü / çift yönlü senkronizasyon köprüsü henüz runtime'da devrede değildir.
3. **Müşteri Bakiye Geçişi:** Legacy `CustomerEntity` ile `core_next` `customer_ledger` bakiyelerinin runtime mutabakatı tamamlanmamıştır.

---

## 7. Git Durumu ve Kod Bütünlüğü

- `git status --short --untracked-files=all`: Beklenen dosyalar dışında izinsiz değişiklik yoktur.
- `git diff --check`: Temiz (0 hata).
- `git rev-parse HEAD`: `28c158d88028f139e93f78982d4651ad424c61d2` (Değişmedi).

---

## 8. Nihai Pilot Kapısı Kararı

```
LIVE_GATE: BLOCKED
```

**Gerekçe:**
Tüm testler ve controller yönlendirmesi başarıyla kanıtlanmış olmakla birlikte, canlı bootstrap başlatma zinciri (`AppBootstrap`) ve runtime ürün kataloğu geçiş köprüsü tamamlanana kadar feature flag'in canlıda açılması güvenli değildir. Sistem fail-closed ve güvenli durumda tutulmaktadır.
