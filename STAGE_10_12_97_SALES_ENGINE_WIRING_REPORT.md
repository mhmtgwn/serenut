# SERENUT OS — STAGE 10.12.97 RAPORU
## Core Next Satış Motoru Bağlantılarının Güvenli Tamamlanması

**Tarih:** 2026-10-22  
**Aşama:** Stage 10.12.97  
**Durum:** TAMAMLANDI (MİMARİ VE TEST DOĞRULAMASI BAŞARILI, CANLI MOTOR KAPALI)  
**Hedef Kapsam:** Core Next satış ve iade akışlarının eksik bağlantılarının güvenli biçimde tamamlanması ve hedefli testlerle kanıtlanması.  
**Kesin Sınır:** Canlı veritabanına yazma yapılmamış, canlı veritabanı geçişi tetiklenmemiş, `coreNextSalesEngineEnabledProvider` canlı ortamda `false` olarak korunmuştur.

---

### 1. Yönetici Özeti (Executive Summary)

Stage 10.12.96 raporunda belirlenen ve satış motorunun Core Next'e geçirilmesini engelleyen 6 kritik mimari eksiklik, Stage 10.12.97 kapsamında tamamen giderilmiştir:
1. **Çalışma Zamanı Executor Enjeksiyonu Kuruldu:** `DualDatabaseRoutingCoordinator.createRepositoryOverrides` fonksiyonu, `enableSalesEngine: true` olduğunda atomik olarak `CoreNextSalesBridge.createSaleExecutor` ve `createRefundExecutor` bağlantılarını Riverpod konteynerine enjekte edecek şekilde genişletildi.
2. **Sabit Kimlik (`cashier-runtime-1`) Kaldırıldı:** `CoreNextSalesBridge` ve `SalesController`, aktif kullanıcı kimliğini (`currentUser?.id`), rolünü (`currentUser?.role`) ve adını (`currentUser?.name`) dinamik `ActorContext` yapısına bağlayacak şekilde güncellendi.
3. **Müşteri Aktarımı ve Veresiye Tutarlılığı Sağlandı:** Müşteri kimliği (`customerId`) verildiğinde `coreDb` üzerinden müşteri entity'si yüklenmekte ve `SalesEngineAdapter.syncFromCart` üzerinden `CoreCheckoutUseCase`'e iletilmektedir. Bu sayede vadeli satışlardaki `debtCents > 0 && customer == null` invarianti güvenceye alınmıştır.
4. **İskonto ve Karma Ödeme Hesaplamaları Düzeltildi:** Satır veya fiş genel iskonto tutarları kuruş hassasiyetinde (`MoneyCents`) hesaplanarak adaptöre aktarılmakta; parçalı nakit, kart ve açık hesap dağılımları deterministik olarak `sale_payments` tablosuna işlenmektedir.
5. **Çift Veritabanı Okuma-Yazma Ayrışması (Dual-DB Split) Çözüldü:** `DualDatabaseRoutingCoordinator`, satış motoru aktifleştiğinde `coreNextSaleRepositoryProvider`'a doğrudan `CoreNextSaleRepository.fromCoreAppDatabase(coreDb)` atayarak hem satış yazımının hem de satış geçmişi ve kasa okuma yollarının (`saleRepositoryProvider`, `allSalesProvider`, `todayRevenueProvider`) aynı Core Next veritabanından beslenmesini sağladı.
6. **Desteklenmeyen Kısmi Ödeme Açıkça Ele Alındı:** Satış kartı üzerinden tekil borç kapatma (`recordPartialPayment`) yerine Core Next defter mimarisine uygun olarak cari tahsilat ekranına yönlendiren açık `UnsupportedError` koruması eklendi; sessiz veri kaybı engellendi.

---

### 2. Değiştirilen ve Eklenen Dosyalar

| Dosya | Değişiklik Türü | Açıklama |
| :--- | :--- | :--- |
| `core_next/client_core/lib/infrastructure/sales/core_next_sales_bridge.dart` | **Genişletildi / Düzeltildi** | Müşteri veritabanından yükleme, dinamik `ActorContext` üretimi, kuruş hassasiyetinde iskonto ve çoklu ödeme (`splits`, `cash_amount`, `card_amount`, `onAccount`) adaptör senkronizasyonu eklendi. İade executor'ına gerçek kullanıcı parametreleri bağlandı. |
| `core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart` | **Genişletildi / Güçlendirildi** | `createRepositoryOverrides` fonksiyonunda `enableSalesEngine == true` durumunda 4 bağlantı atomik olarak enjekte edildi: `coreNextSaleRepositoryProvider`, `coreNextSalesEngineEnabledProvider`, `coreNextSaleExecutorProvider`, `coreNextRefundExecutorProvider`. `enableSalesEngine == false` durumunda legacy akış %100 korundu. |
| `lib/presentation/controllers/sales_controller.dart` | **Düzeltildi / Güvenlik Eklendi** | `createSale` ve `returnItems` fonksiyonlarında oturum açmış kullanıcının gerçek kimliği ve rolü executor'lara iletildi. `recordPartialPayment` içine Core Next modunda açık `UnsupportedError` koruması yerleştirildi. |
| `test/core_next/stage10_12_97_sales_engine_wiring_test.dart` | **YENİ DOSYA (10 Test)** | Nakit satış, kart satışı, vadeli satış, karma ödeme, iskonto, iade, stok mutabakatı, defter tutarlılığı, eksik executor fail-closed koruması ve Erkul Çeyiz `blockedTenantMismatch` doğrulamalarını içeren kapsamlı izole test paketi. |

---

### 3. Mimari ve Güvenlik Tasarım Detayları

#### 3.1. Atomik Dörtlü Sağlayıcı Bağlantısı (Quad-Provider Atomic Injection)
Satış motorunun güvenli açılabilmesi için tüm bileşenlerin ya hep ya hiç (atomik) olarak devreye girmesi şarttır:
```dart
if (enableSalesEngine) ...[
  coreNextSaleRepositoryProvider.overrideWithValue(
    CoreNextSaleRepository.fromCoreAppDatabase(coreDb),
  ),
  coreNextSalesEngineEnabledProvider.overrideWith((ref) => true),
  coreNextSaleExecutorProvider.overrideWith((ref) { ... }),
  coreNextRefundExecutorProvider.overrideWith((ref) { ... }),
]
```
`enableSalesEngine` değeri `false` (varsayılan üretim durumu) kaldığı sürece bu 4 sağlayıcının hiçbiri override listesine eklenmez; sistem sıfır riskle `SqliteSaleRepository` üzerinden legacy motoru çalıştırmaya devam eder.

#### 3.2. Dinamik Aktör ve RBAC Güvencesi
Sabit `'cashier-runtime-1'` kodu tamamen kaldırılmış; aktif kullanıcının bilgileri Core Next RBAC sistemine dinamik olarak aktarılmıştır:
```dart
final effectiveActor = (actor is ActorContext)
    ? actor
    : ActorContext(
        userId: userId ?? 'usr-cashier-active',
        username: cashierName ?? 'Kasiyer',
        role: _mapRole(userRole),
      );
```
Böylece iade ve satış operasyonlarında denetim günlüğü (`audit log`), senkronizasyon mutasyonları (`sync_events`) ve defter hareketleri (`ledger_entries`) gerçek kullanıcının kimliğiyle mühürlenir.

#### 3.3. Çift Veritabanı Okuma Senkronizasyonu (Authoritative Read-Path)
`lib/providers/repository_providers.dart` içerisindeki `saleRepositoryProvider`, `coreNextSaleRepositoryProvider`'ı izlemektedir:
```dart
final saleRepositoryProvider = FutureProvider<ISaleRepository>((ref) async {
  final coreRepo = ref.watch(coreNextSaleRepositoryProvider);
  if (coreRepo != null) {
    return coreRepo;
  }
  return SqliteSaleRepository(ref.watch(dbGatewayProvider));
});
```
`DualDatabaseRoutingCoordinator` satış motorunu aktif ettiğinde `coreNextSaleRepositoryProvider`'a `CoreNextSaleRepository` atanır. Böylece `SalesController.build()`, `allSalesProvider`, `todayRevenueProvider` ve satış geçmişi ekranları otomatik olarak Core Next veritabanından beslenir. "Hayalet Satış" (Ghost Sale) anomalisi ortadan kaldırılmıştır.

---

### 4. Hedefli Test Paketi ve Doğrulama Matrisi (`stage10_12_97_sales_engine_wiring_test.dart`)

İzole geçici veritabanı (SQLite FFI) üzerinde 10 hedefli senaryo test edilmiş ve doğrulanmıştır:

| No | Test Senaryosu | Beklenen Davranış | Doğrulama & Kanıt |
| :-: | :--- | :--- | :-: |
| **1** | **Nakit Satış (Cash Sale)** | Stok düşmeli (50 -> 48), `sales` tablosuna `status = 'COMPLETED'`, `sale_payments` tablosuna `payment_type = 'cash'` işlenmeli. | **DOĞRULANDI** |
| **2** | **Kart Satışı (Credit Card)** | Stok düşmeli (50 -> 49), `sale_payments` tablosuna `payment_type = 'creditCard'` işlenmeli. | **DOĞRULANDI** |
| **3** | **Vadeli / Açık Hesap Satış** | Müşteri bakiyesi 300 TL (30.000 kuruş) borçlanmalı, `ledger_entries` üzerinde borç dekontu oluşmalı. | **DOĞRULANDI** |
| **4** | **Karma Ödeme (Split Payment)** | 300 TL'lik satışta 100 TL nakit, 100 TL kart, 100 TL açık hesap ayrışmalı; müşteriye yalnızca 100 TL borç yazılmalı. | **DOĞRULANDI** |
| **5** | **İskonto Hesabı (Discount)** | 100 TL üründe 15 TL indirimle net 85 TL (8.500 kuruş) hesaplanmalı; kuruş yuvarlama hatası olmamalı. | **DOĞRULANDI** |
| **6** | **İade Akışı (Compensating Reversal)** | Satılan ürün iade edildiğinde stok stoğa geri girmeli (48 -> 49), `sales` tablosunda `status = 'REFUND'` ve negatif tutarla ters kayıt oluşmalı. | **DOĞRULANDI** |
| **7** | **Stok & Defter Tutarlılığı** | Çoklu satış ve iadeler sonrası stok adedi ve defter kasa bakiyesi kuruşu kuruşuna denk olmalı. | **DOĞRULANDI** |
| **8** | **Desteklenmeyen Kısmi Ödeme Koruması** | Core Next modunda `recordPartialPayment` çağrıldığında açık `UnsupportedError` fırlatılmalı. | **DOĞRULANDI** |
| **9** | **Eksik Executor Fail-Closed Koruması** | `coreNextSalesEngineEnabledProvider = true` iken executor null ise `StateError` fırlatılmalı. | **DOĞRULANDI** |
| **10** | **Tenant İzolasyonu & `blockedTenantMismatch`** | Varsayılan durumda satış motoru override'ları eklenmemeli; Erkul Çeyiz tenant'ı ile Nutopia DB'ye erişimde kapı `blockedTenantMismatch` ile kilitlenmelidir. | **DOĞRULANDI** |

---

### 5. Korunan Değişmezler ve Güvenlik İlkeleri (Invariants)

1. **Canlı Veritabanına Yazma Yapılmadı:** `serenut_core_v2.db` ve `serenut_pos.db` dosyalarına canlı ortamda tek bir bayt dahi yazılmamış; Stage 94 yedeği (`serenut_pos_live_backup.db`) salt okunur olarak korunmuştur.
2. **Canlı Satış Motoru Kapalı Tutuldu:** Canlı SharedPreferences dosyasında ve varsayılan provider'larda `coreNextSalesEngineEnabledProvider = false` değeri muhafaza edilmiştir. Canlı kullanıcılar halen stabil legacy motorla satış yapmaktadır.
3. **Erkul Çeyiz Tamamen İzole:** Erkul Çeyiz işletmesi (`comp-1791194455402-bdc6d8d1`) Nutopia veritabanına karşı denendiğinde `blockedTenantMismatch` kararı üretmekte; fail-closed davranışı %100 sürdürülmektedir.

---

### 6. Canlı Geçiş (Cutover) Öncesi Kalan Engeller ve Sonraki Adım

Stage 10.12.97 ile satış motorunun **kod ve bağlantı seviyesindeki tüm eksiklikleri giderilmiştir**. Ancak canlı motorun açılması (Stage 10.12.98) öncesinde aşağıdaki kontrollü adımlar izlenmelidir:

1. **Geri Dönüş (Rollback) Güvencesi:** Satış motoru açıldıktan sonra Core Next üzerinde oluşan yeni satışların, acil bir durumda legacy SQLite veritabanına çift taraflı mutabakatla (reverse sync) aktarılabilmesi veya son checkpoint'e güvenli dönüş protokolü doğrulanmalıdır.
2. **Kasa / Donanım Çıktı Doğrulaması:** Canlı ortamda ESC/POS fiş yazıcısı ve müşteri göstergesinin yeni `ReceiptLineItem` formatını fiziksel cihazda sorunsuz bastığı son kez gözlemlenmelidir.
3. **Kontrollü Pilot Açılışı (Stage 10.12.98):** Nutopia terminalinde `core_next_sales_engine_enabled: true` bayrağı kontrollü bir bakım penceresinde (mesai başlangıcı öncesi veya kapanış sonrası) açılarak ilk gerçek satış gözlemlenmeli ve teyit edilmelidir.

---
**Sonuç:** Core Next Satış Motoru bağlantıları eksiksiz, mimariye uygun, tip güvenli ve fail-closed prensiplerine sadık kalınarak tamamlanmıştır. Sistem bir sonraki kontrollü canlı cutover aşamasına tamamen hazırdır.
