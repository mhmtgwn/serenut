# CORE NEXT — STAGE 10.8.8 INDEPENDENT ADVERSARIAL VERIFICATION REPORT
**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.8.8 — Independent Adversarial Verification (No New Features)  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  
**Çıkış Kararı:** `BLOCKED` (Canlı cutover kesinlikle engellenmiştir; Feature flag varsayılanı `false` kalır)

---

## 1. Bağımsız Karşıt Denetim Kapsamı ve Kurallar

Bu aşama, Stage 10.8.7 düzeltmelerini bağımsız, karşıt (adversarial) senaryolarla test etmek amacıyla yürütülmüştür.
- Canlı veritabanına, VPS'e veya üretim API'sine dokunulmamıştır.
- Feature flag varsayılanı (`coreNextSalesEngineEnabledProvider = false`) korunmuştur.
- Hiçbir commit, push, deploy yapılmamıştır.
- Test beklentileri yeşile dönsün diye gevşetilmemiş; gerçek kod kusurları adli kanıtlarla ortaya çıkarılmıştır.

---

## 2. Karşıt Denetim Bulguları Matrisi (Adversarial Defect Matrix)

| Bulgu No / Seviye | Konu | Dosya ve Satır | Beklenen Davranış | Gerçekleşen (Mevcut Davranış) | Adli Kanıt |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **ADV-01 (HIGH)** | **Migration Sonrası Veri Bayatlaması (Stale Data)** | [migration_bridge_engine.dart:418](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart#L418) | Kaynakta ürünün adı, fiyatı veya stoğu değiştiğinde 2. migration'da hedefin güncellenmesi. | `ConflictAlgorithm.ignore` kullanıldığı için hedefteki kayıt güncellenmemekte; hedefte **eski (bayat) fiyat ve stok** kalmaktadır. | [stage10_8_8_adversarial_verification_test.dart:Test 1](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_8_adversarial_verification_test.dart#L210-L260) |
| **ADV-02 (CRITICAL)** | **İade Rollback Çift Çalıştırmada `refunded_amount` İki Katına Çıkması** | [migration_bridge_engine.dart:1004](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart#L1004) | Rollback iki kez çalıştırıldığında satışın `refunded_amount` değerinin değişmemesi (idempotency). | `UPDATE sales SET refunded_amount = refunded_amount + ?` koşulsuz çalıştığından, **40 TL'lik iade ikinci çalıştırmada 80 TL'ye katlanmaktadır**. | [stage10_8_8_adversarial_verification_test.dart:Test 3](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_8_adversarial_verification_test.dart#L350-L400) |
| **ADV-03 (HIGH)** | **Parçalı Ödeme Roundtrip Ayrışması** | [migration_bridge_engine.dart:538](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart#L538) | Core Next -> Reverse Rollback -> Tekrar Forward Migration döngüsünde Nakit ve Kart kırılımının korunması. | Legacy `sales.payment_method = 'mixed'` ve `notes` serbest metin olduğundan, döngüsel geçişte nakit ve kart tek bir `mixed` satırına çökmekte, kırılım kaybolmaktadır. | [stage10_8_8_adversarial_verification_test.dart:Test 2](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_8_adversarial_verification_test.dart#L265-L345) |
| **ADV-04 (CRITICAL)** | **Runtime Dual-DB Split (Çift Başlılık)** | [sales_controller.dart:195](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/lib/presentation/controllers/sales_controller.dart#L195) | Satış oluşturulduktan sonra ekranların aynı kaynaktan güncel satış ve stokları göstermesi. | `SalesController` yazmayı Core Next'e yaparken, `_saleRepository.findAll()`, `productsControllerProvider` ve `syncProvider` eski `serenut_pos.db` dosyasını okumakta; satışlar listede **boş** kalmaktadır. | [stage10_8_8_adversarial_verification_test.dart:Test 5](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/test/core_next/stage10_8_8_adversarial_verification_test.dart#L425-L450) & [CORE_NEXT_STAGE10_8_8_RUNTIME_READ_WRITE_TRACE.md](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/CORE_NEXT_STAGE10_8_8_RUNTIME_READ_WRITE_TRACE.md) |

---

## 3. Çalıştırılan Test Paketleri ve Resmi Sonuçlar

| Test Paketi / Komut | Kapsam | Test Sayısı | Sonuç (Exit Code) | Açıklama |
| :--- | :--- | :---: | :---: | :--- |
| **`stage10_8_8_adversarial_verification_test.dart`** | Yeni Karşıt Senaryolar | 5 | ✅ GEÇTİ (Code: 0) | Stale data, doubling defect, roundtrip loss ve dual-DB ayrışması ampirik olarak kanıtlandı. |
| **`stage10_8_7_remediation_test.dart`** | Stage 10.8.7 Düzeltmeleri | 4 | ✅ GEÇTİ (Code: 0) | FK Restrict ihlal edilmediği ve PENDING/IN_FLIGHT korunduğu doğrulandı. |
| **`stage10_8_6_adversarial_audit_test.dart`** | Stage 10.8.6 Karşıt Denetim | 9 | ✅ GEÇTİ (Code: 0) | Tüm adli denetim senaryoları doğrulandı. |
| **`test/core_next/` (Tüm Paket)** | Core Next Modülü | 209 | ✅ GEÇTİ (Code: 0) | 209 benzersiz testin tamamı yeşil. |
| **`test/ui/` ve `test/services/` (Tüm Paket)** | Mevcut UI & Servisler | 481 | ✅ GEÇTİ (Code: 0) | Eski satış akışında sıfır regresyon. |
| **`flutter analyze` (İlgili Dosyalar)** | Statik Analiz | 3 Dosya | ✅ TEMİZ (Code: 0) | 0 hata, 0 uyarı. |
| **`git diff --check`** | Sözdizimi & Boşluk | Çalışma Ağacı | ✅ TEMİZ (Code: 0) | Hata yok. |

*Örtüşen testler ayıklanmıştır; toplamda 690 bağımsız test icra edilmiş ve tamamlanmıştır.*

---

## 4. Teslim Edilen Raporlar

1. [CORE_NEXT_STAGE10_8_8_INDEPENDENT_VERIFICATION_REPORT.md](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/CORE_NEXT_STAGE10_8_8_INDEPENDENT_VERIFICATION_REPORT.md) (Bu Belge)
2. [CORE_NEXT_STAGE10_8_8_MIGRATION_DATA_FRESHNESS_REPORT.md](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/CORE_NEXT_STAGE10_8_8_MIGRATION_DATA_FRESHNESS_REPORT.md)
3. [CORE_NEXT_STAGE10_8_8_FINANCIAL_ROUNDTRIP_REPORT.md](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/CORE_NEXT_STAGE10_8_8_FINANCIAL_ROUNDTRIP_REPORT.md)
4. [CORE_NEXT_STAGE10_8_8_RUNTIME_READ_WRITE_TRACE.md](file:///C:/Users/notop/AndroidStudioProjects/shaman_new/CORE_NEXT_STAGE10_8_8_RUNTIME_READ_WRITE_TRACE.md)

---

## 5. Çıkış Kararı ve Gerekçesi

### Karar: `BLOCKED`

**Gerekçeler:**
1. **İade Tutarı Çiftleme Kusuru (ADV-02):** Reverse rollback üst üste iki kez çalıştırıldığında `sales.refunded_amount` değeri iki katına çıkmaktadır. Bu kritik finansal mutabakat kusuru çözülmeden canlı cutover onayı verilemez.
2. **Veri Bayatlaması (ADV-01):** `ConflictAlgorithm.ignore` kullanımı nedeniyle kaynakta güncellenen ürün fiyat ve stokları Core Next'e yansımamakta; yerinde UPSERT (`ON CONFLICT DO UPDATE`) mekanizması gerekmektedir.
3. **Runtime Çift Başlılık (ADV-04):** UI okuma katmanları (`_saleRepository`, `productsControllerProvider`, `syncProvider`) henüz Core Next Read Store'a bağlanmamıştır. Feature flag şu an açılırsa sistem sessizce veri ayrışmasına uğrar.

Feature flag varsayılanı `false` kalmaya devam etmektedir. Canlıya geçiş kesinlikle yasaktır.
