# CORE NEXT — STAGE 10.8.8 RUNTIME READ-WRITE TRACE
**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.8.8 — Çalışma Zamanı Okuma/Yazma Yolu ve Dual-DB Ayrışma Raporu  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Referans Kaynak Dosyaları:**
- [sales_controller.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart)
- [app_bootstrap.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/core/init/app_bootstrap.dart)
- [core_providers.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/presentation/di/core_providers.dart)
- [repository_providers.dart](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/providers/repository_providers.dart)

---

## 1. Çağrı Zinciri İncelemesi (Runtime Call Chain)

Uygulamada feature flag (`coreNextSalesEngineEnabledProvider`) açık kabul edildiğinde gerçekleşen gerçek çağrı akışı izlenmiştir:

```
[KULLANICI SATIŞI ONAYLAR]
         │
         ▼
SalesController.createSale()
         │
         ├──► ref.read(coreNextSalesEngineEnabledProvider) == true
         │
         ├──► ref.read(coreNextSaleExecutorProvider) çağrılır
         │         │
         │         ▼
         │    CoreNextSaleExecutor.executeSale()
         │         │
         │         ▼
         │    CoreCheckoutUseCase.execute()
         │         │
         │         ├──► [YAZMA]: serenut_core_v2.db
         │         │      ├── sales tablosuna ekler
         │         │      ├── sale_items tablosuna ekler
         │         │      ├── sale_payments tablosuna ekler
         │         │      ├── products tablosunda stoğu düşer
         │         │      ├── ledger_entries / customers bakiyesini günceller
         │         │      └── sync_events tablosuna outbox ekler
         │         │
         │         └──► HardwareWorker: Fişi yazdırır
         │
         ├──► [GERİ DÖNÜŞ VE UI TAZELEME - AYRIŞMA NOKTASI!]
         │         │
         │         ├──► return _saleRepository.findAll();
         │         │         └──► [OKUMA]: serenut_pos.db (v60) ⚠️ BOŞ / ESKİ SATIŞLAR!
         │         │
         │         ├──► ref.invalidate(salesHistoryControllerProvider);
         │         │         └──► [OKUMA]: _saleRepository.findFiltered() -> serenut_pos.db ⚠️ YENİ SATIŞ LİSTEDE YOK!
         │         │
         │         ├──► ref.invalidate(productsControllerProvider);
         │         │         └──► [OKUMA]: productRepositoryProvider -> serenut_pos.db ⚠️ STOK DÜŞMEMİŞ GÖRÜNÜR!
         │         │
         │         ├──► ref.invalidate(customerBalanceDetailsProvider);
         │         │         └──► [OKUMA]: customerRepositoryProvider -> serenut_pos.db ⚠️ BAKİYE GÜNCELLENMEMİŞTİR!
         │         │
         │         └──► ref.read(syncProvider.notifier).triggerSync();
         │                   └──► [OKUMA]: sync_outbox_v4 (serenut_pos.db) ⚠️ CORE NEXT SYNC_EVENTS ÇALIŞMAZ!
```

---

## 2. Bileşen Düzeyinde Okuma / Yazma Matrisi

| Bileşen | Yazma Yaptığı Veritabanı | Okuma Yaptığı Veritabanı | Başarısızlık / Çatışma Davranışı | İki DB Arasında Kodda Köprü Var mı? |
| :--- | :--- | :--- | :--- | :--- |
| **`SalesController.createSale`** | `serenut_core_v2.db` (Flag=true iken) | N/A | Core Next hata verirse exception fırlatılır, işlem durur. | **HAYIR** (Yalnızca yazma yönlendirilmiş). |
| **Satış Listesi (`salesControllerProvider`)** | N/A | `serenut_pos.db` | Core Next'e yazılan yeni satışlar bu listede **GÖRÜNMEZ**. | **HAYIR** (Eski DB'yi okumaya devam eder). |
| **Satış Geçmişi (`salesHistoryControllerProvider`)**| N/A | `serenut_pos.db` | Sayfalı geçmiş ekranında yeni fiş/satış **YOKTUR**. | **HAYIR**. |
| **Satış Detayı (`saleDetailProvider`)** | N/A | `serenut_pos.db` | `findById` null döner, "Satış bulunamadı" hatası verir. | **HAYIR**. |
| **Stok Listesi (`productsControllerProvider`)** | N/A | `serenut_pos.db` | Raftaki ürünün stoğu Core Next'te düşer, ancak ekranda **düşmemiş görünür**. | **HAYIR**. |
| **Müşteri Bakiyesi (`customersControllerProvider`)**| N/A | `serenut_pos.db` | Veresiye satış sonrası müşterinin bakiyesi ekranda **0 TL / eski değerde kalır**. | **HAYIR**. |
| **İade Alımı (`returnItems`)** | `serenut_pos.db` | `serenut_pos.db` | İade işlemi Core Next'e DEĞİL, eski veritabanına yazılır! | **HAYIR** (Sessiz ayrışma). |
| **Kısmi Ödeme (`recordPayment`)**| `serenut_pos.db` | `serenut_pos.db` | Kısmi ödeme eski veritabanına yazılır, Core Next defteri habersiz kalır. | **HAYIR** (Sessiz ayrışma). |
| **Senkronizasyon Kuyruğu (`syncProvider`)** | `serenut_pos.db` (`sync_outbox_v4`) | `serenut_pos.db` | Eski senkronizasyon motoru tetiklenir; Core Next `sync_events` kuyruğu sunucuya gitmez. | **HAYIR**. |

---

## 3. Adli Sonuç ve Kök Neden Analizi

1. **Çift Başlılık (Dual-DB Split) Gerçektir:**
   - Kodda `SalesController` yazma metoduna bir `if (coreNextEnabled)` eklenmiştir; ancak uygulamanın geri kalan yüzlerce repository okuma çağrısı (`SqliteSaleRepository`, `SqliteProductRepository`, `SqliteCustomerRepository`) hala `AppDatabase.instance.database` (`serenut_pos.db`) nesnesine bağlıdır.
2. **Köprü (Bridge) Yalnızca Raporlarda ve Migration Aracında Vardır:**
   - `MigrationBridgeEngine` çalışma zamanında (runtime) iki veritabanı arasında gerçek zamanlı çift yönlü senkronizasyon yapan bir daemon veya event-bus DEĞİLDİR; tek seferlik bir batch aktarım motorudur.
3. **Canlı Geçiş Neden İmkansızdır?**
   - Eğer `coreNextSalesEngineEnabledProvider` şu an `true` yapılırsa, kasiyer satış yaptığında fiş yazdırılır ancak satış geçmişinde görünmez, stok düşmez, müşteri borcu işlenmez ve sunucuya senkronize edilmez.
   - Bu nedenle **Authoritative Store Cutover** gerçekleşene kadar feature flag **KAPALI KALMAK ZORUNDADIR (`LIVE_GATE: BLOCKED`)**.
