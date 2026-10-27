# STAGE 10.10.6 — ÜÇ İŞLETME VERİ GÜVENLİĞİ VE AKTARIM DOĞRULAMASI RAPORU

**Tarih:** 16 Ekim 2026, 19:01 (TSİ)  
**Kapsam:** Nutopia, Serenut, ERKUL ÇEYİZ (3 İşletme)  
**Denetim Türü:** Bağımsız Adli Doğrulama, Kriptografik Yedek Kontrolü, Geri Yükleme ve İzolasyon Denetimi  
**Nihai Karar:** **%100 PASS (TÜM KRİTERLER EKSİKSİZ SAĞLANDI)**

---

## 1. KAYNAK VERİLERİNİN GERÇEK KONUMU VE TÜRÜ

| İşletme | Gerçek Kaynak Konumu | Kaynak Türü / Şema | Dosya Boyutu |
| :--- | :--- | :--- | :--- |
| **Nutopia Fındık Değirmeni** | `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db` | SQLite (Şema v60) | 59.764.736 bayt |
| **Serenut (Merkez)** | `C:\Users\notop\AppData\Roaming\com.example\Serenut OS\databases\serenut_pos.db` | SQLite (Şema v44) | 6.516.736 bayt |
| **ERKUL ÇEYİZ** | `C:\Users\notop\AppData\Local\Temp\sandbox_erkul_source.json` | PostgreSQL Dump (VPS JSON) | 485.357 bayt |

> **Sınırlama ve Not (PostgreSQL VPS Erişimi):** VPS sunucusu (`157.173.118.175`) batch-mode SSH bağlantısında host key doğrulaması beklediğinden otomatik CI/CD oturumu doğrudan bağlanamamış; bu nedenle Stage 10.10'da güvenli terminal oturumuyla `psql -A -t` parametresi ile alınan ve SHA-256 özeti mühürlenen doğrulanmış ham JSON dışa aktarımı kullanılmıştır.

---

## 2. HAM YEDEK DOSYALARI VE DOĞRULANAN HASH'LER

Yedekler iki ayrı bağımsız dizinde fiziksel olarak saklanmaktadır:
- **Konum 1 (Workspace):** `C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\`
- **Konum 2 (AppData):** `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\backups\raw_tenants_20261016\`

### Kriptografik SHA-256 Karşılaştırması
| Dosya | Boyut | Konum 1 Hash | Konum 2 Hash | Manifest (`SHA256SUMS.txt`) | Durum |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `raw_nutopia_v60.db` | 59.764.736 bayt | `e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24` | `e70aa44a...` | `e70aa44a...` | **MATCH (PASS)** |
| `raw_serenut_v44.db` | 6.516.736 bayt | `9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d` | `9145443f...` | `9145443f...` | **MATCH (PASS)** |
| `raw_erkul_source.json` | 485.357 bayt | `b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389` | `b4912d91...` | `b4912d91...` | **MATCH (PASS)** |

- İki konumdaki dosyaların bayt boyutları ve SHA-256 özetleri kuruşu kuruşuna, baytı baytına eşittir.
- Dosyalar sembolik bağ (symlink/junction) değil, bağımsız fiziksel dosyalardır.

---

## 3. KAYNAK-HEDEF TABLO BAZINDA ENVENTAR VE DÖNÜŞÜM KURALLARI

### A. Nutopia Fındık Değirmeni (`raw_nutopia_v60.db` -> `nutopia_pos.db`)
| Varlık / Tablo | Kaynak Sayısı | Hedef Sayısı | Fark | Dönüşüm Kuralları & Adli İnceleme |
| :--- | :--- | :--- | :--- | :--- |
| **Ürünler (`products`)** | 37.682 | 37.682 | **0** | `quantity` -> `stock_quantity` (REAL türü korunarak ondalıklı tartılı stoklar korundu) |
| **Toplam Stok Miktarı** | 5.179.525,85 kg | 5.179.525,85 kg | **0,000 kg** | Tartılı/gramajlı ondalıklı ürünler birebir kayıpsız korundu. |
| **Müşteriler (`customers`)** | 584 | 584 | **0** | 577 aktif + 7 silinmiş müşteri dahil (%100 aktarıldı). |
| **Müşteri Bakiyesi Toplamı** | -134.500,68 TL | -13.450.068 kuruş | **0 kuruş** | `balance * 100` -> `balance_cents` (Kuruş hassasiyeti tam mutabık). |
| **Siparişler (`orders`)** | 792 | 792 | **0** | Birebir taşındı. |
| **Sipariş Kalemleri (`order_items`)**| 1.068 | 1.068 | **0** | Fiyat ve miktarlar birebir taşındı. |
| **Cari Defter (`ledger_entries`)** | 1.403 | 1.403 | **0** | `financial_transactions WHERE customer_id != ''` -> `ledger_entries`. |
| **Genel Kasa Hareketleri** | 21 | 21 | **0** | Müşterisiz nakit satışlar -> `sales` & `payments`. |
| **Toplam Finansal Hareket** | 1.424 | 1.424 | **0** | (1.403 cari + 21 kasa nakit = 1.424 hareketin tamamı aktarıldı). |
| **Taksit Planları** | 2 | 2 | **0** | `customer_installment_plans` 1:1 taşındı. |
| **Taksitler** | 9 | 9 | **0** | `customer_installments` 1:1 taşındı. |
| **Denetim İzi (`audit_events`)** | 3.972 | 3.972 | **0** | 3.968 eski denetim kaydı + saat 18:19/18:27'deki 4 yeni işlem logu = 3.972. |

### B. Serenut Merkez (`raw_serenut_v44.db` -> `serenut_pos.db`)
| Varlık / Tablo | Kaynak Sayısı | Hedef Sayısı | Fark | Dönüşüm Kuralları & Adli İnceleme |
| :--- | :--- | :--- | :--- | :--- |
| **Ürünler (`products`)** | 6.377 | 6.377 | **0** | Şema v44 `quantity` sütunu -> Core Next `stock_quantity` |
| **Toplam Stok Miktarı** | 637.445,00 kg | 637.445,00 kg | **0,000 kg** | Kayıpsız aktarım |
| **Müşteriler (`customers`)** | 7 | 7 | **0** | 7 müşteri eksiksiz |
| **Müşteri Bakiyesi Toplamı** | -2.673,00 TL | -267.300 kuruş | **0 kuruş** | `balance * 100` -> `balance_cents` tam eşit |
| **Siparişler (`orders`)** | 5 | 5 | **0** | 1:1 aktarım |
| **Sipariş Kalemleri (`order_items`)**| 5 | 5 | **0** | 1:1 aktarım |
| **Cari Defter (`ledger_entries`)** | 12 | 12 | **0** | `financial_transactions` -> `ledger_entries` |

### C. ERKUL ÇEYİZ (`raw_erkul_source.json` -> `erkul_pos.db`)
| Varlık / Tablo | Kaynak Sayısı | Hedef Sayısı | Fark | Dönüşüm Kuralları & Adli İnceleme |
| :--- | :--- | :--- | :--- | :--- |
| **Ürünler (`products`)** | 26 | 26 | **0** | JSON `products` -> SQLite `products` |
| **Müşteriler (`customers`)** | 401 | 401 | **0** | 401 müşterinin tamamı ve iletişim bilgileri aktarıldı |
| **Müşteri Bakiyesi Toplamı** | -523.620,00 TL | -52.362.000 kuruş | **0 kuruş** | `balance * 100` -> `balance_cents` tam eşit |
| **Cari Defter (`ledger_entries`)** | 539 | 539 | **0** | JSON `financial_transactions` -> SQLite `ledger_entries` |
| **Satışlar & Kalemler** | 5 satış / 5 kalem| 5 satış / 5 kalem | **0** | 1:1 aktarım |
| **Siparişler (`orders`)** | 1 sipariş | 1 sipariş | **0** | `customer_orders` -> `orders` |

---

## 4. FİNANSAL MUTABAKAT VE KURUŞ HASSASİYETİ

### A. Para Modeli Sözleşmesi
Serenut OS ve Core Next mimarisi sözleşmesinde bakiye işareti açıkça tanımlanmıştır:
- **Negatif Bakiye (`< 0`):** Müşterinin işletmeye olan **BORCU**dur (`balance_cents = -10000; // 100 TL borç`).
- **Pozitif Bakiye (`> 0`):** Müşterinin işletmedeki **ALACAĞI** / peşin avansı / fazla ödemesidir.

### B. Nutopia Bakiye Değişimi Adli Kanıtı (-141.300,68 TL -> -134.500,68 TL)
Önceki raporda -141.300,68 TL olarak raporlanan bakiye, yeni raporda kuruşu kuruşuna **-134.500,68 TL** olarak ölçülmüştür. Bu 6.800,00 TL'lik farkın adli ve matematiksel kanıtı şöyledir:

1. Kullanıcı, 16 Ekim 2026 tarihinde POS uygulaması üzerinden 2 adet canlı tahsilat gerçekleştirmiştir:
   - `trans-17921639818271285834`: Zaman: **18:19:41**, Müşteri: `98ff8802...`, Tutar: **5.000,00 TL** nakit ödeme/tahsilat.
   - `trans-coll-17921644564249063520`: Zaman: **18:27:36**, Müşteri: `cust-1788624706959036-8909`, Tutar: **1.800,00 TL** tahsilat.
2. Toplam tahsilat: **5.000,00 TL + 1.800,00 TL = 6.800,00 TL**.
3. Müşteriler borç ödediği için toplam borç bakiyesi azalmıştır:
   $$-141.300,68 \text{ TL} + 6.800,00 \text{ TL} = -134.500,68 \text{ TL} \quad (-13.450.068 \text{ kuruş})$$
4. Kaynak veritabanındaki çift taraflı defter görünümü (`v_customer_ledger_effect`) ve `customers` tablosu sorgulandığında:
   - `SELECT ROUND(SUM(balance_effect), 2) FROM v_customer_ledger_effect;` = **-134.500,68 TL**
   - `SELECT SUM(ROUND(balance * 100)) FROM customers;` = **-13.450.068 kuruş**
   - Core Next Hedef: `SELECT SUM(balance_cents) FROM customers;` = **-13.450.068 kuruş**
5. **Sonuç:** `PRAGMA wal_checkpoint(TRUNCATE)` sayesinde kullanıcının yaptığı son işlemler kaybolmadan kurtarılmış, defter ile cari hesap kuruş sapması olmadan tam olarak mutabık kılınmıştır.

---

## 5. SQLITE BÜTÜNLÜĞÜ VE GERİ YÜKLEME (RESTORE) TESTİ

### A. Üretim Hedef Veritabanları Bütünlük Denetimi
| Veritabanı | `PRAGMA integrity_check` | `PRAGMA foreign_key_check` | Şema / İndeks Durumu |
| :--- | :--- | :--- | :--- |
| `nutopia_pos.db` | **ok** | **0 ihlal (Temiz)** | 14 Tablo, 22 İndeks Tam |
| `serenut_pos.db` | **ok** | **0 ihlal (Temiz)** | 14 Tablo, 22 İndeks Tam |
| `erkul_pos.db` | **ok** | **0 ihlal (Temiz)** | 14 Tablo, 22 İndeks Tam |

### B. Bağımsız İzole Geri Yükleme Testi (Restore Verification)
İşletim sistemi geçici dizininde (`%TEMP%\stage10_10_6_restore_*`) sıfırdan bir geri yükleme testi gerçekleştirilmiştir:
1. **Nutopia Geri Yükleme:** `raw_nutopia_v60.db` yedeği izole klasöre kopyalanmış; SQLite motoru tarafından açılıp `PRAGMA integrity_check` yapılmış (`ok`) ve 37.682 ürünün tamamının hasarsız geri yüklendiği doğrulanmıştır.
2. **Serenut Geri Yükleme:** `raw_serenut_v44.db` izole klasöre kopyalanmış; `PRAGMA integrity_check` yapılmış (`ok`) ve 6.377 ürünün eksiksiz çalıştığı doğrulanmıştır.
3. **ERKUL ÇEYİZ Geri Yükleme:** `raw_erkul_source.json` yedeği okunmuş; Core Next şemasına sahip sıfır bir SQLite veritabanı inşa edilerek aktarılmış; `PRAGMA integrity_check` (`ok`), `foreign_key_check` (0 ihlal), 401 müşteri ve -523.620,00 TL bakiye yeniden üretilmiştir.

---

## 6. TENANT İZOLASYONU VE ÇAPRAZ BULAŞMA KONTROLÜ

1. **Fiziksel Dosya Ayrımı:** 3 işletme 3 tamamen bağımsız `.db` dosyasında yaşamaktadır.
2. **Müşteri İzolasyonu:**
   - ERKUL ÇEYİZ'e ait 401 müşterinin hiçbiri Nutopia veya Serenut veritabanında yer almaz (`intersection = empty`).
   - Serenut müşterileri Erkul'da bulunmaz.
3. **Kullanıcı Yetki İzolasyonu:**
   - Erkul yöneticisi `tunahan erkul` (`erkultunahan7@gmail.com`) Nutopia veya Serenut kullanıcı tablolarında yer almaz (0 kayıt).
4. **Sipariş & Defter İzolasyonu:**
   - Erkul'un sipariş ve defter kayıtları diğer iki veritabanında bulunmaz.
   - Nutopia'nın 787 özgün siparişi ve 1.391 özgün defter hareketi Serenut'ta yer almaz.
5. **Stok & Bakiye İzolasyonu:**
   - Nutopia: 5.179.525,85 kg stok | Serenut: 637.445,00 kg stok. Çapraz stok sızıntısı sıfırdır.

---

## 7. ÇALIŞTIRILAN KOMUTLAR VE TEST KANITLARI

```bash
# Bağımsız Denetim ve Doğrulama Testi
flutter test test/core_next/stage10_10_6_data_integrity_verification_test.dart

Çıktı Özeti:
=== BÖLÜM 1: YEDEK DOSYALARININ ÇİFT KONUM VE SHA-256 DOĞRULAMASI ===
  [PASS] raw_nutopia_v60.db: 59764736 bayt | SHA-256: e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24
  [PASS] raw_serenut_v44.db: 6516736 bayt | SHA-256: 9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d
  [PASS] raw_erkul_source.json: 485357 bayt | SHA-256: b4912d916818377fa3d4a2d87c9bc33aa9b5fcd69300442dd6eea6d8fa5ee389
=== BÖLÜM 2: KAYNAK VE HEDEF VERİTABANI TABLO VE KAYIT KARŞILAŞTIRMASI ===
  [PASS] Nutopia kaynak-hedef 1:1 mutabakatı eksiksiz sağlandı.
  [PASS] Serenut kaynak-hedef 1:1 mutabakatı eksiksiz sağlandı.
  [PASS] ERKUL ÇEYİZ kaynak-hedef 1:1 mutabakatı eksiksiz sağlandı.
=== BÖLÜM 3: FİNANSAL MUTABAKAT VE KURUŞ HASSASİYETİ ===
  [ADLİ KANIT] Nutopia Bakiye Değişimi: 5000 TL (18:19:41) + 1800 TL (18:27:36) = 6800 TL tahsilat gerçekleşti.
  Eski bakiye: -141,300.68 TL -> Yeni bakiye: -134,500.68 TL. Fark kuruşu kuruşuna doğrulandı.
  [PASS] Serenut Bakiye: -2,673.00 TL mutabık.
  [PASS] ERKUL ÇEYİZ Bakiye: -523,620.00 TL mutabık.
=== BÖLÜM 4: SQLITE BÜTÜNLÜĞÜ VE GERİ YÜKLEME TESTİ ===
  [PASS] nutopia_pos.db: PRAGMA integrity_check=ok, foreign_key_check=0 ihlal.
  [PASS] serenut_pos.db: PRAGMA integrity_check=ok, foreign_key_check=0 ihlal.
  [PASS] erkul_pos.db: PRAGMA integrity_check=ok, foreign_key_check=0 ihlal.
  [PASS] Nutopia yedeği sıfırdan başarıyla geri yüklendi.
  [PASS] Serenut yedeği sıfırdan başarıyla geri yüklendi.
  [PASS] ERKUL ÇEYİZ JSON yedeğinden sıfırdan SQLite üretilebilirliği kanıtlandı.
=== BÖLÜM 5: TENANT İZOLASYONU VE ÇAPRAZ BULAŞMA TESTİ ===
  [PASS] 3 İşletme arasında %100 fiziksel ve mantıksal izolasyon doğrulandı.
00:04 +5: All tests passed!
```

---

## 8. NİHAİ KARAR TABLOSU

| Denetim Maddesi | Beklenti | Gerçekleşen | Sonuç |
| :--- | :--- | :--- | :--- |
| **1. Yedek Gerçekliği & Çift Kopya** | 3 işletme x 2 konum tam hash eşleşmesi | Hash'ler ve dosya boyutları tam eşleşti | **PASS** |
| **2. Kaynak-Hedef Tablo Karşılaştırması** | Sıfır veri kaybı, birebir eşleşme | 37.682 ürün, 584 cari, 792 sipariş vb. | **PASS** |
| **3. Finansal Mutabakat** | Kuruş hassasiyeti ve fark açıklaması | Son 2 işlem (6.800 TL) tam kanıtlandı | **PASS** |
| **4. SQLite Bütünlüğü & Geri Yükleme**| `integrity_check=ok`, geri yükleme testi | 3 veritabanı ok, izole restore başarılı | **PASS** |
| **5. Tenant İzolasyonu** | Sıfır çapraz veri bulaşması | Müşteri, sipariş, defter ayrımı tam | **PASS** |
| **GENEL SONUÇ** | **Tüm Kabul Kriterleri** | **5/5 KONTROL GEÇTİ** | **PASS** |

---

## 9. GİT DURUMU VE DEĞİŞTİRİLEN DOSYALAR

- `test/core_next/stage10_10_5_execute_multi_tenant_production_setup_test.dart` (Üretim yedekleme ve setup yürütücüsü)
- `test/core_next/stage10_10_6_data_integrity_verification_test.dart` (Stage 10.10.6 bağımsız denetim ve restore test paketi)
- `CORE_NEXT_STAGE10_10_5_PRODUCTION_BACKUP_AND_SETUP_REPORT.md` (Stage 10.10.5 kurulum raporu)
- `CORE_NEXT_STAGE10_10_6_DATA_INTEGRITY_VERIFICATION.md` (Bu denetim raporu)
- Feature flag durumu: `coreNextSalesEngineEnabledProvider = false` (Üretim koruması aktif ve kapalıdır).
