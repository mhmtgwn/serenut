# SERENUT OS — STAGE 10.12.96: CORE NEXT SATIŞ MOTORU GEÇİŞ HAZIRLIĞI VE ENGEL ANALİZ RAPORU

**Tarih / Saat:** 22 Ekim 2026, 16:35 (TSİ)  
**Aşama:** Stage 10.12.96 (Satış Motoru Cutover Hazırlığı)  
**Hedef İşletme:** Nutopia Fındık Değirmeni (`comp-1785241628448-c7f5677d` / `tenant_id: nutopia`)  
**İzole İşletme:** Erkul Çeyiz (`comp-1791194455402-bdc6d8d1` / `blockedTenantMismatch`)  
**Mevcut Durum:** `coreNextSalesEngineEnabledProvider = false` (Fail-Safe Legacy Koruma)  
**Nihai Karar:** **`STAGE_10_12_96_CUTOVER_READINESS_EVALUATED_AND_ROADMAP_DEFINED`**

---

## 1. YÖNETİCİ ÖZETİ VE GEÇİŞİN TEMEL NEDENİ

Stage 10.12.94 ve 10.12.95 aşamalarında Nutopia'nın ürün, stok, müşteri (cari) ve finansal defter modülleri başarıyla Core Next veritabanına (`serenut_core_v2.db`) yönlendirilmiş; kuruşu kuruşuna mutabakat sağlanmıştır.

Ancak satış motoru kasıtlı olarak **`coreNextSalesEngineEnabledProvider = false`** durumunda tutulmuştur. Bu durumun arkasındaki somut teknik ve mimari gerçekler şunlardır:

1. **Çalışma Zamanı Executor Enjeksiyonu Eksiktir:** `AppBootstrap.initPreApp()` içinde `coreNextSaleExecutorProvider` ve `coreNextRefundExecutorProvider`'a çalışma zamanında somut bir executor bağlanmamıştır (varsayılan: `null`). Bu bayrak açıldığı anda `SalesController` doğrudan `StateError` fırlatacak ve kasa satış yapamaz hale gelecektir.
2. **Bridge İçinde Müşteri ve İskonto Boşluğu:** `CoreNextSalesBridge.createSaleExecutor`, `customerId` ve `discountAmount` parametrelerini almasına rağmen bunları sepet senkronizasyonuna (`adapter.syncFromCart`) aktarmamaktadır. Bu nedenle **veresiye satışlar `CoreCheckoutUseCase` seviyesinde ("Müşteri seçilmelidir") hatasıyla çökmektedir**.
3. **Karma ve Kısmi Ödeme Eksikliği:** Bridge katmanı yalnızca tekil bir ödeme tipi oluşturmakta; nakit + kart veya peşin + veresiye (karma) ödeme parçalarını Core Next `PaymentSplitEntity` yapısına dönüştürmemektedir.
4. **Çift Yönlü Satış Deposu Uyuşmazlığı:** Satış motoru açıldığında hem yazma (`CoreNextSaleExecutor`) hem okuma (`CoreNextSaleRepository`) depolarının aynı anda Core Next'e geçmesi şarttır. Biri açık diğeri kapalı kaldığında "hayalet satış" (yapılan satışın geçmişte görünmemesi) oluşmaktadır.

---

## 2. SOMUT ENGELLER MATRİSİ (KANIT, ETKİ, KAPATMA KOŞULU)

Aşağıdaki tablo, satış motorunun Core Next'e geçirilmesi önündeki tüm somut engelleri listelemektedir:

| Engel No | Engel Tanımı | Kod ve Mimari Kanıtı | Canlı Sisteme Etkisi | Kapatma Koşulu (Gereksinim) |
|:---:|---|---|---|---|
| **E-01** | **`coreNextSaleExecutorProvider`'ın `null` Olması** | `lib/infrastructure/bootstrap/app_bootstrap.dart:L269-L292` içinde `overrideGenerator` yalnızca repo override'ları üretir. `coreNextSaleExecutorProvider` atanmaz. `sales_controller.dart:L170`: `if (coreNextExecutor == null) throw StateError(...)`. | Bayrak açılırsa kasiyer satış tamamla dediğinde uygulama anında çöker (`StateError`). | `AppBootstrap` veya `DualDatabaseRoutingCoordinator` içinde `CoreCheckoutUseCase`'e bağlı somut bir `CoreNextSaleExecutor` ProviderScope'a enjekte edilmelidir. |
| **E-02** | **`coreNextRefundExecutorProvider`'ın `null` Olması** | `app_bootstrap.dart` içinde iade executor'ı enjekte edilmez. `sales_controller.dart:L249`: `if (coreNextRefundExecutor == null) throw StateError(...)`. | Bayrak açılırsa iade işlemi yapılamaz (`StateError`). | `CoreRefundUseCase`'e bağlı somut bir `CoreNextRefundExecutor` ProviderScope'a enjekte edilmelidir. |
| **E-03** | **Bridge'de Veresiye Müşterisinin Sepete Aktarılmaması** | `core_next_sales_bridge.dart:L74-L78` içinde `adapter.syncFromCart(...)` çağrılırken `customer` ve `discount` parametreleri geçilmemektedir. `checkout_use_case.dart:L108-L112`: `if (debtCents.value > 0 && customer == null) throw StateError(...)`. | Nutopia'da müşteriye veresiye satış yapıldığında sepet müşterisiz kaldığı için işlem başarısız olur; veresiye satılamaz. | `CoreNextSalesBridge.createSaleExecutor`, `customerId` ile müşteriyi bulup `syncFromCart(customer: ..., discount: ...)` şeklinde iletmelidir. |
| **E-04** | **Karma / Parçalı Ödeme (`mixed`) Ayrıştırmasının Yapılmaması** | `core_next_sales_bridge.dart:L65-L72` yalnızca tek bir `PaymentSplitEntity` üretir. Çoklu ödeme veya veresiye bakiye kalması durumunda ikinci bir split üretilmez. | Nakit + Kart veya Nakit + Veresiye satışlarında ödeme dağılımı tek kaleme indirgenir; kasa ve POS mutabakatı bozulur. | `CoreNextSalesBridge`, `paymentMethod == 'karma'` veya `paidAmount < totalAmount` olduğunda kalan tutarı otomatik `PaymentType.onAccount` olarak split listesine eklemelidir. |
| **E-05** | **Aktör / Kullanıcı Kimliğinin Hardcoded Olması** | `core_next_sales_bridge.dart:L84-L88`: `userId: 'cashier-runtime-1'` sabit yazılmıştır. | Canlıda Mehmet Güven (`usr-1785241628452-41128da6`) oturumu açıkken, Core Next satışları sahte bir kullanıcıya yazar; denetim izi bozulur. | Aktif `currentUserProvider`'dan kullanıcının gerçek ID, isim ve rolü alınıp `ActorContext` oluşturulmalıdır. |
| **E-06** | **Satış Okuma Deposu (`saleRepositoryProvider`) Eşzamanlılığı** | `DualDatabaseRoutingCoordinator.createRepositoryOverrides:L119`: `if (enableSalesEngine) coreNextSaleRepositoryProvider...`. Şu an `enableSalesEngine = false`. | Satış motoru Core Next'e yazsa bile UI satış geçmişi legacy DB'yi okursa yeni satışlar ekranda görünmez ("hayalet satış"). | `enableSalesEngine = true` yapıldığında `coreNextSaleRepositoryProvider` zorunlu olarak `CoreNextSaleRepository`'ye bağlanmalıdır. |
| **E-07** | **Satış İptali (`cancelSale`) Use-Case Entegrasyonu Eksikliği** | `CoreNextSalesBridge`'de iade (`refund`) vardır ancak fiş/satış iptali (`cancelSale`) için bir adapter bulunmamaktadır. | Kasiyer gün içinde hatalı satışı iptal etmek istediğinde Core Next satış ve defter kayıtları tutarsız kalabilir. | Core Next üzerinde `CoreCancelSaleUseCase` köprüsü kurulmalıdır. |
| **E-08** | **Taksit / Senet Tahsilatının Core Next Defterine Entegrasyonu** | `sqlite_installment_repository.dart` doğrudan `installments` tablosunu kullanır; Core Next v3 şemasında senetler `ledger_entries`'de temsil edilir. | Taksit tahsilatı yapıldığında Core Next defteri ile eski taksit durumu arasında desentez riski doğabilir. | Taksit tahsilatlarının Core Next `financialTransactionRepository` üzerinden deftere tam bağlandığı doğrulanmalıdır. |

---

## 3. MODÜL VE HAREKET BAZINDA TUTARLILIK DURUMU

Nutopia'nın ticari hareketlerinin Core Next uyumluluk haritası:

| İşlem Türü | Mevcut Durum | Core Next Uyumu | Kalan İş |
|---|---|:---:|---|
| **Peşin Satış (Nakit / Kart)** | Legacy motor (`SalesService`) | %85 Hazır | `coreNextSaleExecutorProvider` enjeksiyonu ve aktör bilgisi bağlanmalı. |
| **Veresiye Satış (Açık Hesap)** | Legacy motor | %60 Hazır | Bridge'de müşteri entity'sinin sepete aktarılması zorunlu (E-03). |
| **Karma / Parçalı Satış** | Legacy motor | %50 Hazır | Çoklu split (`PaymentSplitEntity`) desteği bridge'e eklenmeli (E-04). |
| **Cari Tahsilat (Nakit / POS)** | Core Next Cari & Finans Depoları | **%100 Hazır** | Zaten Stage 94'te Core Next'e bağlandı. |
| **Manuel Borç Ekleme** | Core Next Cari & Finans Depoları | **%100 Hazır** | Zaten Stage 94'te Core Next'e bağlandı. |
| **Ürün İadesi (`returnItems`)** | Legacy motor | %75 Hazır | `coreNextRefundExecutorProvider` runtime bootstrap'ine bağlanmalı. |
| **Satış İptali (`cancelSale`)** | Legacy motor | %40 Hazır | Core Next iptal ve ters defter kaydı köprüsü eklenmeli. |
| **Senet / Taksit Tahsilatı** | Legacy SQLite | %70 Hazır | Defter hareketleri eşitlenmiş, yerel UI kontrolü gereklidir. |

---

## 4. TENANT İZOLASYONU VE KORUMA PROTOKOLÜ (ERKUL ÇEYİZ)

Satış motorunun Core Next'e geçişi sırasında Erkul Çeyiz verilerinin korunması:
1. `PilotCutoverGate` içindeki fail-closed tenant eşleşmesi (`app_settings.tenant_id == 'nutopia'`) kesin olarak korunacaktır.
2. Erkul Çeyiz lisans token'ı (`comp-1791194455402-bdc6d8d1`) devreye girdiğinde satış motoru override'ları asla üretilmeyecek, `blockedTenantMismatch` durumu muhafaza edilecektir.
3. Erkul Çeyiz'in veritabanı `databases/core_next/erkul_pos.db` (557 KB) salt okunur kalmaya devam edecek; Nutopia'nın hiçbir yeni satışı bu veritabanına yazılmayacaktır.

---

## 5. ÇALIŞMA AĞACI VE GİT DURUMU

- **Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (`main`)
- **Değiştirilen Kod:** 0 satır.
- **`coreNextSalesEngineEnabledProvider` Durumu:** Dokunulmadı, `false` korundu.
- **Canlı Veritabanı:** Dokunulmadı, Stage 94 yedeği mühürlü.

---

## 6. ÖNERİLEN TEK SONRAKİ UYGULAMA ADIMI (STAGE 10.12.97)

Yukarıdaki 8 somut engelin kapatılması ve satış motorunun güvenle açılması için önerilen tek sonraki adım:

> **Öneri: Stage 10.12.97 — CoreNextSalesBridge ve Bootstrap Runtime Enjeksiyonu (E-01, E-02, E-03, E-04 ve E-05 Düzeltmesi)**  
> 1. `CoreNextSalesBridge.createSaleExecutor` fonksiyonuna `customerId` üzerinden müşteri entity'si bulma (`syncFromCart(customer: ..., discount: ...)`), karma ödeme split'leri ve aktif kullanıcı aktörü (`ActorContext`) yetenekleri eklenmelidir.  
> 2. `DualDatabaseRoutingCoordinator.createRepositoryOverrides` içinde `coreNextSaleExecutorProvider`, `coreNextRefundExecutorProvider` ve `coreNextSaleRepositoryProvider` bağlantıları tek bir atomik pakette üretilmelidir.  
> 3. Bu düzenlemeler önce birim/izole testlerle doğrulanmalı, ardından kontrollü cutover denemesi yapılmalıdır.
