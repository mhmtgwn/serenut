# CORE NEXT — STAGE 10.8.7 SINGLE-SOURCE-OF-TRUTH MAP
**Tarih:** 14 Ekim 2026  
**Aşama:** Stage 10.8.7 — Veri Akışı ve Tek Yetkili Veritabanı Haritası  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`  

---

## 1. Veri Akışı ve Veritabanı Haritalama Matrisi

Uygulamanın `SalesController`, `SalesService`, `SqliteSaleRepository`, `CoreNextSaleExecutor` ve Riverpod provider'ları üzerinden uçtan uca veri yolları denetlenmiş ve aşağıdaki matriste haritalanmıştır:

| İşlem / Ekran | Legacy Mod (`flag = false`) Yazma DB | Legacy Mod (`flag = false`) Okuma DB | Core Next Mod (`flag = true`) Yazma DB | Core Next Mod (`flag = true`) Okuma DB (Mevcut Durum) | Hedef Authoritative Cutover Mimarisi |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Satış Oluşturma (`createSale`)** | `serenut_pos.db` | N/A | `serenut_core_v2.db` | N/A | `serenut_core_v2.db` (Yalnızca Core) |
| **Satış Listesi Tazelem (`findAll`)** | N/A | `serenut_pos.db` | N/A | `serenut_pos.db` ⚠️ *(Ayrışma Noktası)* | `serenut_core_v2.db` (Read Store) |
| **Satış Detayı (`findById`)** | N/A | `serenut_pos.db` | N/A | `serenut_pos.db` ⚠️ *(Ayrışma Noktası)* | `serenut_core_v2.db` (Read Store) |
| **Stok Güncelleme** | `serenut_pos.db` | `serenut_pos.db` | `serenut_core_v2.db` | `serenut_pos.db` ⚠️ *(Ayrışma Noktası)* | `serenut_core_v2.db` (Katalog) |
| **Müşteri Bakiyesi** | `serenut_pos.db` | `serenut_pos.db` | `serenut_core_v2.db` | `serenut_pos.db` ⚠️ *(Ayrışma Noktası)* | `serenut_core_v2.db` (Defter) |
| **İade Alımı (`returnItems`)** | `serenut_pos.db` | `serenut_pos.db` | `serenut_pos.db` ⚠️ *(Legacy Servis)* | `serenut_pos.db` | `serenut_core_v2.db` (Refunds) |
| **Kısmi Ödeme (`recordPayment`)**| `serenut_pos.db` | `serenut_pos.db` | `serenut_pos.db` ⚠️ *(Legacy Servis)* | `serenut_pos.db` | `serenut_core_v2.db` (Ledger) |
| **Senkronizasyon Kuyruğu** | `serenut_pos.db` (v4 outbox) | `serenut_pos.db` | `serenut_core_v2.db` (sync_events) | `serenut_pos.db` ⚠️ *(Sync Provider)* | `serenut_core_v2.db` (Worker) |

---

## 2. Ayrışma Riskinin Analizi ve Koruma Kuralı

### Neden Hibrit (Çift Yazma / Shadow Write) Yasaktır?
Eğer `SalesController` hem `serenut_pos.db` hem de `serenut_core_v2.db` dosyalarına aynı anda yazmaya çalışırsa:
1. İki SQLite dosyası arasında iki fazlı commit (2PC) mekanizması bulunmadığından, elektrik kesintisi veya işletim sistemi çökmesinde **bir dosya güncellenip diğeri güncellenemez**.
2. İki veritabanının kimlikleri (ID) ve bakiye değerleri sessizce ayrışır (silent data divergence).
3. Adli muhasebe açısından hangi veritabanının authoritative olduğu bilinemez hale gelir.

### Uygulanan Koruma: Fail-Closed Authoritative Gate
1. **Varsayılan Durum:** `coreNextSalesEngineEnabledProvider = false` olarak korunur. Sistem %100 oranında `serenut_pos.db` ile tutarlı ve güvenli çalışır.
2. **Kör Geçiş Yasağı:** Yalnızca `createSale` metodunu Core Next'e yönlendiren kısmi geçişler canlıya açılmaz.
3. **Tam Cutover Kuralı:** Cutover anında `MigrationBridgeEngine` ile tüm legacy veriler `serenut_core_v2.db` dosyasına aktarılacak; ardından UI repository'leri tek seferde `CoreAppDatabase` üzerine yönlendirilecektir.

---

## 3. Authoritative Cutover ve Rollback Döngüsü

```
[ÖNCE: Canlı Çalışma]
Tüm Okuma & Yazmalar ──────> serenut_pos.db (v60)

[GEÇİŞ: Cutover Anı]
MigrationBridgeEngine ──────> serenut_pos.db'den tüm verileri serenut_core_v2.db'ye kopyalar.
                              (Kuruş tamsayıları, FK bütünlüğü, outbox PENDING/IN_FLIGHT/TRANSIENT)

[SONRA: Core Next Canlı]
Tüm Okuma & Yazmalar ──────> serenut_core_v2.db (v3)

[GERİ DÖNÜŞ GEREKİRSE: Reverse Rollback]
ReverseMigrationEngine ─────> serenut_core_v2.db'deki yeni satışları, karma ödemeleri,
                              stokları, bakiyeleri ve iadeleri serenut_pos.db'ye iade eder.
Tüm Okuma & Yazmalar ──────> Tekrar serenut_pos.db (v60)
```

Bu mimari sayesinde sistem hiçbir zaman iki başlı çalışmaz; her aşamada tek bir **Authoritative Source of Truth** bulunur.
