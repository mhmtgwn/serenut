# SERENUT OS — STAGE 10.8.10 DATA FLOW MATRIX

**Tarih:** 2026-10-15  
**Proje:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Kapsam:** Tüm Uygulama Veri Akışlarının (Yazma, Okuma, Stok, Cari, Fiş, İade, Senkronizasyon) Uçtan Uca Haritası

---

## 1. TÜM SİSTEM VERİ AKIŞLARI MATRİSİ

Aşağıdaki tablo, uygulamanın temel veri akışlarını `coreNextSalesEngineEnabledProvider` bayrağının kapalı (`false`) ve açık (`true`) olduğu durumlarda karşılaştırmalı olarak göstermektedir:

| Akış No | Veri Akışı | Bileşen / Controller | Kullanılan Repository & Provider | Hedef Veritabanı (Flag = false) | Hedef Veritabanı (Flag = true) | Durum & Değerlendirme |
|---|---|---|---|---|---|---|
| **1** | **Satış Oluşturma (Yazma)** | `SalesController.createSale` | `coreNextSaleExecutorProvider` / `SalesService` | `serenut_pos.db` | `serenut_core_v2.db` | **EŞLEŞTİ (GÜVENLİ)**: Flag açıkken atomik transaction ile Core Next'e yazar. |
| **2** | **Satış Listesi (Okuma)** | `salesHistoryControllerProvider` | `saleRepositoryProvider` | `serenut_pos.db` (`SqliteSaleRepository`) | `serenut_core_v2.db` (`CoreNextSaleRepository`) | **EŞLEŞTİ (GÜVENLİ)**: `CoreNextSaleRepository` sayesinde yeni veritabanını okur. |
| **3** | **Satış Detayı (Okuma)** | `saleDetailProvider(saleId)` | `saleRepositoryProvider` | `serenut_pos.db` (`SqliteSaleRepository`) | `serenut_core_v2.db` (`CoreNextSaleRepository`) | **EŞLEŞTİ (GÜVENLİ)**: Kalemler ve ödeme detayları Core Next DB'den gelir. |
| **4** | **Ürün Kataloğu & Stok (Kasa Ekranı)** | `ProductsController`, `salesProductsControllerProvider` | `productRepositoryProvider` | `serenut_pos.db` (`SqliteProductRepository`) | `serenut_pos.db` (`SqliteProductRepository`) | **DUAL-DB AYRIŞMASI**: Flag açıkken Core Next stok düşer ancak kasa ekranı eski DB'deki stoğu gösterir! |
| **5** | **Müşteri Bakiyesi & Cari Defter** | `CustomersController`, `customerTransactionsProvider` | `customerRepositoryProvider`, `financialTransactionRepositoryProvider` | `serenut_pos.db` (`SqliteCustomerRepository`) | `serenut_pos.db` (`SqliteCustomerRepository`) | **DUAL-DB AYRIŞMASI**: Vadeli satış Core Next `ledger_entries`'e yazılırken cari ekranı eski DB'den okur! |
| **6** | **Fiş / Yazdırma Akışı** | `_printReceipt` (`sales_page.dart`) | `SaleEntity` + `settingsNotifierProvider` | `SaleEntity` bellekteki nesneden üretilir. | `SaleEntity` bellekteki nesneden üretilir. | **GÜVENLİ**: Fiş içeriği `createSale`'den dönen güncel `SaleEntity` üzerinden basılır. |
| **7** | **İade / İptal İşlemleri** | `SalesController.returnItems` | `_salesService.returnItems` | `serenut_pos.db` (`SqliteRefundMutationStore`) | `serenut_pos.db` (`SqliteRefundMutationStore`) | **DUAL-DB AYRIŞMASI**: Core Next satışının iadesi eski DB tablolarına yazılır! |
| **8** | **Senkronizasyon (İstemci)** | `syncProvider` vs `coreSyncPullWorkerProvider` | `SyncService` vs `SyncV4PullWorker` | `serenut_pos.db` (`sync_outbox_v4`) | `serenut_core_v2.db` (`sync_events`) | **PARALEL KUYRUK**: İki motor ayrı veritabanlarındaki bağımsız kuyrukları işler. |

---

## 2. VERİ TUTARLILIĞI VE ATOMİKLİK SINIRLARI

### 2.1. Flag Kapalıyken (Legacy Modu - Varsayılan)
- **Bütünlük:** %100 Tek Yetkili Kaynak (`Single Source of Truth`).
- **Veritabanı:** Tüm bileşenler istisnasız `serenut_pos.db` ile konuşur.
- **Güvenlik:** Hiçbir ayrışma riski yoktur; 481 legacy testinin tamamı bu modda yeşildir.

### 2.2. Flag Açıkken (Core Next Modu - Hibrit Durum)
- **Satış ve Fiş Hattı:** Tamamen `serenut_core_v2.db` üzerinde tutarlıdır (Satış kaydı, kalemler, ödemeler, satış geçmişi ve detayları).
- **Katalog ve Cari Hattı:** Henüz `productRepositoryProvider` ve `customerRepositoryProvider` için Core Next adaptörü yazılmadığı için, `serenut_pos.db`'yi sorgulamaya devam eder.

---

## 3. SONUÇ VE ADAPTASYON YOL HARİTASI

Canlı cutover yapılabilmesi için aşağıdaki 3 adaptasyon tamamlanmalıdır:
1. `coreNextProductRepositoryProvider` tanımlanarak `productRepositoryProvider`'a bağlanmalı.
2. `coreNextCustomerRepositoryProvider` tanımlanarak `customerRepositoryProvider`'a bağlanmalı.
3. `SalesController.returnItems` metodu, Core Next aktifken `RefundUseCase` ile `serenut_core_v2.db`'ye yönlendirilmelidir.
