# SERENUT OS — STAGE 10.8.10 CUTOVER READINESS GATE

**Tarih:** 2026-10-15  
**Proje:** `C:\Users\notop\AndroidStudioProjects\shaman_new`  
**Kapı Değerlendirmesi:** **`READY_FOR_FURTHER_ISOLATED_TESTING`**  
*(Canlı Cutover İzni: KAPALI / BEKLEMEDE)*

---

## 1. KAPI KONTROL LİSTESİ (CUTOVER CRITERIA CHECKLIST)

| Kontrol Kriteri | Durum | Kanıt & Not |
|---|---|---|
| **1. ADV-01 (Migration Veri Güncelliği)** | **GEÇTİ (PASS)** | `ON CONFLICT DO UPDATE` (In-Place UPSERT) ile FK RESTRICT hatasız veri güncellemesi kanıtlandı. |
| **2. ADV-02 (İade Idempotency)** | **GEÇTİ (PASS)** | `refunded_amount` alt sorguyla deterministik yeniden hesaplanıyor; iki kez çalıştırmada ikiye katlanmıyor. |
| **3. ADV-03 (Çoklu Ödeme Roundtrip)** | **GEÇTİ (PASS)** | Nakit, kart ve vadeli kırılımları yapısal `sale_payments` tablosuyla roundtrip döngüsünde kuruşu kuruşuna korunuyor. |
| **4. ADV-04 (Satış Okuma/Yazma Köprüsü)** | **GEÇTİ (PASS)** | `CoreNextSaleRepository` ve `saleRepositoryProvider` üzerinden UI satış geçmişi ve detayı Core Next'ten okunuyor. |
| **5. Ürün ve Stok Deposu Adaptasyonu** | **BEKLEMEDE (PENDING)** | Kasa ekranı (`productsControllerProvider`) hâlâ `serenut_pos.db` okuyor. `coreNextProductRepositoryProvider` köprüsü kurulmalıdır. |
| **6. Cari ve Müşteri Bakiyesi Adaptasyonu** | **BEKLEMEDE (PENDING)** | Müşteri ekranı (`customersControllerProvider`) hâlâ `serenut_pos.db` okuyor. `coreNextCustomerRepositoryProvider` köprüsü kurulmalıdır. |
| **7. İade Akışı Adaptasyonu** | **BEKLEMEDE (PENDING)** | `SalesController.returnItems` hâlâ `_salesService` üzerinden legacy DB'ye yazıyor. |
| **8. Açılışta Otomatik Migration Tetikleyicisi** | **BEKLEMEDE (PENDING)** | `app_bootstrap.dart` içinde ilk açılışta `serenut_pos.db`'den `serenut_core_v2.db`'ye otomatik taşıma tetikleyicisi bağlanmalıdır. |
| **9. Feature Flag Güvenliği** | **GÜVENLİ (PASS)** | `coreNextSalesEngineEnabledProvider` varsayılan değeri `false` tutulmaktadır. |
| **10. Regresyon ve Bağımsız Testler** | **GEÇTİ (PASS)** | 698 testin tamamı sıfır hata ile yeşildir. |

---

## 2. CANLI CUTOVER NEDEN ŞİMDİ YAPILAMAZ?

Tüm veritabanı motoru ve migration düzeltmeleri tamamlanmış olmasına rağmen, şu anda `coreNextSalesEngineEnabledProvider = true` yapılması durumunda:
1. Satış Core Next DB'ye kaydedilecek ve satış geçmişinde görünecektir.
2. ANCAK POS ekranındaki ürün stoğu `serenut_pos.db`'den okunduğu için ekrandaki stok adedi düşmeyecektir.
3. Vadeli satış yapıldığında müşterinin cari kartındaki borç bakiyesi güncellenmeyecektir (çünkü cari ekranı eski DB'ye bakmaktadır).

Bu durum kullanıcıya "Dual-DB Split" (iki başlı sistem) deneyimi yaşatır. Bu sebeple kapı kararı **`READY_FOR_FURTHER_ISOLATED_TESTING`** olarak belirlenmiştir.

---

## 3. STAGE 10.9 ENTEGRASYON PLANI (KAPININ AÇILMASI İÇİN GEREKENLER)

1. **Adım 1:** `productRepositoryProvider` için `CoreNextProductRepository` adaptörü yazılması.
2. **Adım 2:** `customerRepositoryProvider` için `CoreNextCustomerRepository` adaptörü yazılması.
3. **Adım 3:** `SalesController.returnItems` metodunun Core Next aktifken `RefundUseCase`'e yönlendirilmesi.
4. **Adım 4:** `app_bootstrap.dart` içine tek seferlik güvenli migration hook'u konulması.
5. **Adım 5:** Pilot kullanıcı için feature flag'in kontrollü açılması (`READY_FOR_CUTOVER_REVIEW`).
