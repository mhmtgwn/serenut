# CORE NEXT — STAGE 10.12.21
## KAYNAK-HEDEF VERİ TUTARSIZLIKLARINI ÇÖZME VE BAĞIMSIZ MUTABAKAT RAPORU

**Tarih:** 2026-10-17  
**Ortam:** Serenut OS Desktop (Windows 11 x64, Flutter 3.24.5 / Dart 3.5.4)  
**Denetçi / İcra Eden:** Antigravity Bağımsız Kod & Güvenlik Denetim Ajanı  
**Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2` (`main`)  
**Doğrulanan Kaynak Yedeği:** `backups/raw_tenants_20261016/raw_nutopia_v60.db`  
**Kaynak SHA-256 İmzası:** `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` (**EŞLEŞTİ — TAM DOĞRULANDI**)  
**Nihai Karar:** `RECONCILIATION PASSED — PILOT REVIEW MAY PROCEED`

---

## 1. YÜRÜTME ÖZETİ VE ÇELİŞKİ ÇÖZÜMLERİ

Stage 10.12.20 ve önceki aşama raporlarındaki iddialar bağımsız adli sorgulamaya tabi tutulmuş; raporlar arasındaki sayısal çelişkiler ham veritabanı şeması ve gerçek SQL aggregate sorguları üzerinden çözülmüştür:

1. **Ürün Sayısı Çelişkisi (17 Aktif / 37.665 Silinmiş vs 37.682 Aktif)**:
   - **Gerçek Durum**: Kaynak Nutopia veritabanında toplam **37.682** ürün bulunmaktadır.
   - **Durum Kırılımı**: `is_deleted = 0` ve `is_active = 1` olan tam **17** ürün; `is_deleted = 1` ve `is_active = 0` olan tam **37.665** ürün vardır.
   - **Çelişkinin Nedeni**: Stage 10.12.20 raporunda aktarılan ürün sayısı tablosuna yazılırken, toplam taşınan kayıt adedi (37.682) ile `is_deleted = 0` filtresi editoryal olarak karıştırılmış ve hatalı bir biçimde "37.682 aktif / 0 silinmiş" yazılmıştır. Gerçekte hem kaynakta hem de hedefte `is_deleted = 1` bayrağı 37.665 kayıtta bire bir korunmuştur.
2. **Satış Kalemi Çelişkisi (72 Kalem vs 120 Kalem)**:
   - **Gerçek Durum**: Kaynak `raw_nutopia_v60.db` dosyasında tam **52 satış** ve bu satışlara bağlı **120 satış kalemi** (`sale_items`) bulunmaktadır.
   - **Çelişkinin Nedeni**: 72 sayısı, Stage 10.10 çok kiracılı raporundaki 3 kiracının toplam satış başlığı sayısıdır (52 Nutopia + 15 Çeyiz + 5 Şaman = 72 Satış). Stage 10.12.20 raporunun yazımı sırasında bu 72 satış adedi ile satış kalemleri kavramsal olarak karışmış ve sehven "72 satış kalemi" yazılmıştır. Gerçekte Nutopia yedeğinde 120 satış kalemi vardır ve 120 kalemin tamamı hedef veritabanına aktarılmaktadır.
3. **Müşteri Bakiyesi ve Kuruş Dönüşümü**:
   - 584 müşterinin toplam yetkili (authoritative) bakiyesi tam olarak **-134.500,68 TL** (-13.450.068 kuruş) tutarındadır. Kaynakta 38 eski müşteride `balance_minor` alanının güncellenmeyip 0 kaldığı, float `balance` alanının ise doğru olduğu ve `MigrationBridgeEngine`'in bu bayat minor değerleri yetkili bakiye ile düzelttiği adli olarak doğrulanmıştır.
4. **Müşterisiz Nakit Satışlar**:
   - 21 adet müşterisiz nakit satış fişi (toplam 12.197,00 TL / 1.219.700 kuruş), hedef veritabanında `outbox` kaydı olarak değil, doğrudan hedef SQLite tablosu olan `cash_transactions` (`category = 'SALE'`, `type = 'INFLOW'`) içerisine yazılmaktadır.
5. **Kayıp veya Fazla Kayıt Durumu**:
   - Ürünler, müşteriler, satışlar, satış kalemleri, siparişler, sipariş kalemleri, taksit planları ve taksit dilimleri dahil tüm tablolarda eksik (missing in target) veya fazla (extra in target) kayıt listesi: **`[]` (Boş Küme)**.

---

## 2. KESİN GÜVENLİK SINIRLARI DENETİMİ

| Sınır / Güvenlik Kriteri | Beklenen | Gerçekleşen | Durum |
| :--- | :--- | :--- | :---: |
| **Canlı Nutopia SQLite DB** | Yazma yapılmamalı | 0 bayt yazıldı / dokunulmadı | **PASS** |
| **Erkul PostgreSQL** | Bağlantı kurulmamalı | 0 bağlantı / dokunulmadı | **PASS** |
| **Kaynak Yedek İmzası** | `e70aa44a43...` | `e70aa44a43...` (Değişmedi) | **PASS** |
| **Üretim Migration Runner** | `runner == null` | `runner: null` korundu | **PASS** |
| **Database Routing Hook** | `hook == null` | `databaseRoutingHook: null` korundu | **PASS** |
| **Satış Motoru Bayrağı** | `false` | `sales_engine_core_next_enabled == false` | **PASS** |
| **Git Çalışma Ağacı** | Temiz / Reset yok | Hiçbir commit/reset/revert yapılmadı | **PASS** |
| **Deney İzolasyonu** | Geçici Temp kopyalar | `%TEMP%\stg10_12_21_*` altında izole çalışıldı | **PASS** |

---

## 3. ADLİ SORGULAR VE ÇELİŞKİLERİN ÇÖZÜMÜ

### 3.1. Ürün Sayısı ve Durum Analizi (PASS)

#### Kaynak SQL Sorgusu:
```sql
SELECT 
  count(*) as total,
  sum(case when is_deleted = 0 then 1 else 0 end) as active_by_del,
  sum(case when is_deleted = 1 then 1 else 0 end) as deleted_by_del,
  sum(case when is_active = 1 then 1 else 0 end) as active_by_act,
  sum(case when is_active = 0 then 1 else 0 end) as inactive_by_act
FROM products;
```
**Kaynak Sonucu**:
- Toplam Ürün: **37.682**
- `is_deleted = 0`: **17** | `is_deleted = 1`: **37.665**
- `is_active = 1`: **17** | `is_active = 0`: **37.665**
- Kesişim: Tam 17 aktif ürün (`is_active = 1 AND is_deleted = 0`), tam 37.665 silinmiş ürün (`is_active = 0 AND is_deleted = 1`).

#### Hedef SQL Sorgusu:
```sql
SELECT 
  count(*) as total,
  sum(case when is_deleted = 0 then 1 else 0 end) as active_by_del,
  sum(case when is_deleted = 1 then 1 else 0 end) as deleted_by_del,
  sum(case when is_active = 1 then 1 else 0 end) as active_by_act,
  sum(case when is_active = 0 then 1 else 0 end) as inactive_by_act
FROM products;
```
**Hedef Sonucu**:
- Toplam Ürün: **37.682**
- `is_deleted = 0`: **17** | `is_deleted = 1`: **37.665**
- `is_active = 1`: **17** | `is_active = 0`: **37.665**

**Çözüm Açıklaması**:
Kaynak ve hedef arasında ürün sayısı veya durumu bakımından hiçbir tutarsızlık yoktur. Stage 10.12.20 rapor metnindeki "37.682 aktif / 0 silinmiş" ifadesi, tablodaki satır sayısı ile `is_deleted = 0` filtresinin raporda yanlış etiketlenmesinden kaynaklanmış bir editoryal hatadır. Gerçekte 37.665 ürün silinmiş/arşiv statüsünde hedef veritabanına aktarılmıştır.

---

### 3.2. Satış ve Satış Kalemleri Analizi (PASS)

#### Kaynak SQL Sorguları:
```sql
-- Satış başlıkları
SELECT count(*), sum(total_amount), sum(total_amount_minor) FROM sales;
-- Çıktı: (52 adet, 31.282,25 TL, 3.128.225 kuruş)

-- Satış kalemleri
SELECT count(*), sum(subtotal), sum(subtotal_minor) FROM sale_items;
-- Çıktı: (120 adet, 31.307,25 TL, 3.130.725 kuruş)

-- Yetim kalem kontrolü
SELECT count(*) FROM sale_items WHERE sale_id NOT IN (SELECT id FROM sales);
-- Çıktı: 0 adet
```

#### Hedef SQL Sorguları:
```sql
-- Hedef satış başlıkları
SELECT count(*), sum(total_cents) FROM sales;
-- Çıktı: (52 adet, 3.128.225 kuruş)

-- Hedef satış kalemleri
SELECT count(*), sum(total_cents) FROM sale_items;
-- Çıktı: (120 adet, 3.130.725 kuruş)
```

**Çözüm Açıklaması**:
Kaynak Nutopia veritabanında gerçekte **120** satış kalemi mevcuttur. Stage 10.12.20'de sehven raporlanan "72 satış kalemi", Stage 10.10'daki çok kiracılı testin toplam satış başlığı sayısıdır. Nutopia tekil yedeğinde 52 satış ve bu satışlara ait tam 120 satış kalemi bulunmakta ve hepsi kayıpsız aktarılmaktadır.

---

### 3.3. Finans Kayıtları ve Müşterisiz Nakit Satışlar (PASS)

#### Müşteriler ve Bakiye:
- **Kaynak Sorgu**: `SELECT count(*), sum(balance), sum(balance_minor) FROM customers;`
  - Müşteri Adedi: **584**
  - Float Bakiye Toplamı: **-134.500,68 TL** (-13.450.068 kuruş yetkili bakiye)
  - `balance_minor` Toplamı: -13.217.068 kuruş (38 eski kayıtta minor alanının 0 kaldığı tespit edilmiştir)
- **Hedef Sorgu**: `SELECT count(*), sum(balance_cents) FROM customers;`
  - Müşteri Adedi: **584**
  - Hedef Kuruş Bakiye Toplamı: **-13.450.068 kuruş** (-134.500,68 TL)
  - *Mutabakat: Tam kuruş denkliği, 0 sapma.*

#### Müşteri Defter Hareketleri (`ledger_entries`):
- **Kaynak Sorgu**:
  ```sql
  SELECT count(*) FROM financial_transactions 
  WHERE customer_id IS NOT NULL AND customer_id != '' AND customer_id IN (SELECT id FROM customers);
  ```
  - Kaynak Adedi: **1.403**
- **Hedef Sorgu**: `SELECT count(*) FROM ledger_entries;`
  - Hedef Adedi: **1.403**

#### Müşterisiz Nakit Satışlar (`cash_transactions`):
- **Kaynak Sorgu**:
  ```sql
  SELECT count(*), sum(amount), sum(amount_minor) FROM financial_transactions 
  WHERE (customer_id IS NULL OR customer_id = '' OR customer_id NOT IN (SELECT id FROM customers))
    AND type = 'sale';
  ```
  - Kaynak Adedi: **21**
  - Kaynak Tutar: **12.197,00 TL** (1.219.700 kuruş)
- **Hedef Sorgu**:
  ```sql
  SELECT count(*), sum(amount_cents) FROM cash_transactions WHERE category = 'SALE' AND type = 'INFLOW';
  ```
  - Hedef Adedi: **21**
  - Hedef Tutar: **1.219.700 kuruş** (12.197,00 TL)
  - *Kanıt*: Müşterisiz nakit fişleri outbox veya geçici tabloya değil, doğrudan hedef SQLite veritabanındaki `cash_transactions` tablosuna `INFLOW` ve `SALE` olarak yazılmıştır.

#### Siparişler ve Kalemler:
- Siparişler: **792** adet. Tutar toplamı: **1.226.806,30 TL** (122.680.630 kuruş).
- Sipariş Kalemleri (`order_items`): **1.068** adet.

#### Taksit Planları ve Dilimleri:
- `customer_installment_plans`: **2** plan.
- `customer_installments`: **9** taksit dilimi.

---

## 4. BİRE BİR ID FARKI VE ADLİ PARİTE TABLOSU

| Varlık / Tablo | Kaynak ID Sayısı | Hedef ID Sayısı | Hedefte Eksik ID (`src - tgt`) | Hedefte Fazla ID (`tgt - src`) | Durum |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Ürünler (`products`)** | 37.682 | 37.682 | `[]` (0 adet) | `[]` (0 adet) | **PASS** |
| **Müşteriler (`customers`)** | 584 | 584 | `[]` (0 adet)* | `[]` (0 adet) | **PASS** |
| **Satışlar (`sales`)** | 52 | 52 | `[]` (0 adet) | `[]` (0 adet) | **PASS** |
| **Satış Kalemleri (`sale_items`)**| 120 | 120 | `[]` (0 adet) | `[]` (0 adet) | **PASS** |
| **Siparişler (`orders`)** | 792 | 792 | `[]` (0 adet) | `[]` (0 adet) | **PASS** |
| **Sipariş Kalemleri (`order_items`)**| 1.068 | 1.068 | `[]` (0 adet) | `[]` (0 adet) | **PASS** |
| **Taksit Planları** | 2 | 2 | `[]` (0 adet) | `[]` (0 adet) | **PASS** |
| **Taksit Dilimleri** | 9 | 9 | `[]` (0 adet) | `[]` (0 adet) | **PASS** |
| **Müşterisiz Nakit Satışlar** | 21 | 21 | `[]` (0 adet) | `[]` (0 adet) | **PASS** |
| **Defter Kayıtları (`ledger`)** | 1.403 | 1.403 | `[]` (0 adet) | `[]` (0 adet) | **PASS** |

*\* Not: Kaynakta `id = ''` olan Peşin Müşteri kaydı, şema ve anahtar bütünlüğü gereği hedefte `'customer-pesin-default'` olarak temizlenmiştir.*

---

## 5. TEST PAKETİ İCRA SONUÇLARI

Tüm test paketleri sıfır varsayımla bağımsız olarak icra edilmiştir:

| Test Dosyası | Test Başlığı / Kapsamı | Test Sayısı | Başarılı | Başarısız | Çıkış Kodu | Durum |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Stage 10.12.21** | `stage10_12_21_source_target_reconciliation_test.dart` | 10 | 10 | 0 | 0 | **PASS** |
| **Stage 10.12.20** | `stage10_12_20_final_isolated_rehearsal_test.dart` | 17 | 17 | 0 | 0 | **PASS** |
| **Stage 10.12.19** | `stage10_12_19_fail_closed_ui_consent_test.dart` | 15 | 15 | 0 | 0 | **PASS** |
| **Stage 10.12.17** | `stage10_12_17_progress_consent_test.dart` | 13 | 13 | 0 | 0 | **PASS** |
| **Stage 10.12.16** | `stage10_12_16_audit_and_benchmark_test.dart` | 5 | 5 | 0 | 0 | **PASS** |
| **Stage 10.12.15** | `stage10_12_15_guarded_database_manager_test.dart` | 8 | 8 | 0 | 0 | **PASS** |
| **Stage 10.12.14** | `stage10_12_14_isolated_bootstrap_rehearsal_test.dart` | 15 | 15 | 0 | 0 | **PASS** |
| **Stage 10.12.12** | `stage10_12_12_anonymous_cash_sales_test.dart` | 4 | 4 | 0 | 0 | **PASS** |
| **TOPLAM** | **8 Test Paketi Kapsamlı Regresyonu** | **87** | **87** | **0** | **0** | **%100 PASS** |

### Statik Analiz ve Biçim Doğrulaması:
- **`flutter analyze`**:
  `Analyzing 6 items... No issues found! (ran in 12.1s)` -> **Exit Code: 0**
- **`git diff --check`**:
  `0 hata / 0 whitespace hatası` -> **Exit Code: 0**
- **`git status --short`**:
  Kullanıcının çalışma ağacı ve dosyaları eksiksiz korunmuştur.

---

## 6. NİHAİ DEĞERLENDİRME VE KARAR

- Gerçek kaynak hash doğrulaması: **PASS**
- Ürün sayısı ve silinme durumu çelişkisinin çözümü (17 aktif / 37.665 silinmiş): **PASS**
- Satış kalemleri uzlaştırması (120 kalem): **PASS**
- Finans ve müşteri bakiyesi mutabakatı (-134.500,68 TL): **PASS**
- Müşterisiz nakit satışların `cash_transactions` tablosuna aktarımı (21 adet, 12.197,00 TL): **PASS**
- Taksit ve defter hareketleri: **PASS**
- Yetim, yinelenen ve kayıp kayıt analizi: **PASS** (`missing = []`, `extra = []`)
- İdempotency (çift çalıştırmada sıfır mükerrerlik): **PASS**
- Regresyon testleri (87/87): **PASS**

### NİHAİ KARAR

```text
================================================================================
            RECONCILIATION PASSED — PILOT REVIEW MAY PROCEED
================================================================================
```

> **ÖNEMLİ HATIRLATMA:** Pilot incelemesine geçilmesine izin verilmesi doğrudan canlı üretime geçiş (production cutover) izni değildir. Üretim migration runner'ı ve routing hook'ları pilot onayına kadar kapalı tutulacaktır.
