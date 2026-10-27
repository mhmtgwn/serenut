# SERENUT OS — STAGE 10.12.3: TEST DÜZELTMESİ VE VERİTABANI YÖNLENDİRME TASARIM RAPORU

**Tarih:** 16 Ekim 2026  
**Aşama:** Stage 10.12.3  
**Çalışma Alanı:** `c:\Users\notop\AndroidStudioProjects\shaman_new`  
**Amaç:** `sync_v4_outbox_adapter_test.dart` testindeki tip kusurunu düzeltmek, 5 kritik test paketinin %100 başarısını kanıtlamak ve canlı `DatabaseManager` yönlendirmesi için güvenli tasarım ve test planını hazırlamak.  

---

## 1. GİT VE ÇALIŞMA AĞACI DURUMU

- **Git HEAD SHA:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Aktif Branch:** `main`
- **Sözdizimi / Format (`git diff --check`):** Temiz (0 hata).
- **Değiştirilen Dosyalar:**
  - `test/core_next/sync_v4_outbox_adapter_test.dart` (Yalnızca 270. satırdaki test içi tip dönüşümü düzeltildi).
  - Üretim kodunda hiçbir dosya değiştirilmemiştir.
  - Canlı veritabanlarına dokunulmamış, `coreNextSalesEngineEnabledProvider = false` kapalı tutulmuştur.

---

## 2. GÖREV 1 — TEST KUSURUNUN DOĞRULANMASI VE DÜZELTİLMESİ

### A. Başarısızlığın Nedeni
`test/core_next/sync_v4_outbox_adapter_test.dart` dosyasının 6. testinde (`Satış ve Finansal Mutasyonlar Tek Transaction İçinde Oluşturuluyor`) 270. satırda:
```dart
// HATALI KOD (Satır 270):
stockQuantity: product.first['stock_quantity'] as int,
```
Core Next SQLite şemasında `products.stock_quantity` sütunu `REAL` (ondalıklı/tartılı terazi desteği için) olarak tanımlanmıştır. SQLite FFI katmanı bu değeri `double` (ör. `10.0`) olarak döndürdüğü için Dart çalışma zamanında şu hata oluşmaktaydı:
```text
type 'double' is not a subtype of type 'int' in type cast
test\core_next\sync_v4_outbox_adapter_test.dart 270:56 main.<fn>.<fn>
```

### B. Uygulanan Düzeltme
Yalnızca test dosyasındaki ilgili satır, hem `int` hem `double` değerleri güvenle karşılayacak şekilde güncellendi:
```dart
// DÜZELTİLEN KOD (Satır 270):
stockQuantity: (product.first['stock_quantity'] as num).toInt(),
```

### C. Test Çıktısı
Düzeltme sonrasında test paketi tek başına çalıştırıldı:
```text
flutter test test/core_next/sync_v4_outbox_adapter_test.dart
00:00 +11: All tests passed! (11/11 PASS, Çıkış Kodu: 0)
```

---

## 3. GÖREV 2 — 5 KRİTİK TEST PAKETİNİN GERÇEK ÇIKTILARI

5 temel test paketi ardışık olarak çalıştırılmış ve tamamının **%100 PASS** verdiği doğrulanmıştır:

| Test Dosyası | Test Sayısı | Süre | Gerçek Çıktı Özeti | Statü |
| :--- | :---: | :---: | :--- | :---: |
| `test/core_next/sync_v4_outbox_adapter_test.dart` | 11 | 00:08 | DTO uyumu, karma ödemeler, tek transaction, nedensel sıra (`causal_sequence`). | **PASS** |
| `test/core_next/sync_v4_recovery_audit_test.dart` | 8 | 00:07 | Replay koruması, çakışma kontrolü (`server_revision`), atomik outbox rollback. | **PASS** |
| `test/core_next/stage10_8_12_financial_reconciliation_audit_test.dart` | 6 | 00:08 | Kuruş yuvarlama sınırları, kısmi/tam iade, mükerrer istek finansal bütünlük. | **PASS** |
| `test/core_next/stage10_7_3_pull_worker_test.dart` | 14 | 00:10 | Çok sayfalı pull, cursor ilerletme, retry sınıflandırması, fail-closed cihaz kontrolü. | **PASS** |
| `test/core_next/stage10_12_1_migration_rehearsal_test.dart` | 3 | 00:10 | 37.682 ürün, 5.17M stok, -134.500,68 TL bakiye, 1.403 hareket 1:1 derin mutabakat. | **PASS** |

**Toplam:** 42 Senaryo Testi — **42/42 BAŞARILI (%100 PASS)**.

---

## 4. GÖREV 3 — VERİTABANI YÖNLENDİRME (ROUTING) MİMARİ TASARIMI

Henüz `DatabaseManager` koduna dokunulmamıştır. Canlı geçişte `serenut_pos.db` yerine `core_next/nutopia_pos.db` dosyasının güvenle açılabilmesi için mimari gereksinimler ve 8 temel sorunun analizi aşağıdadır:

### A. Temel Mimari Sorular ve Çözümleri

#### 1. Aktif işletme kimliği nereden ve ne zaman belirleniyor?
- **Ne Zaman:** `AppBootstrap.initPreApp` adım 4'te (`SharedPreferences.getInstance()`).
- **Nereden:** `SharedPreferences` içerisindeki kalıcı anahtarlar (`active_tenant_id`, `license_merchant_id` veya `active_database_target`).
- **Öncelik Sırası:**
  1. `SharedPreferences.getString('active_database_override')` (Varsa),
  2. `SharedPreferences.getString('license_merchant_id')`,
  3. Fallback: Mevcut `serenut_pos.db` (Fail-safe legacy).

#### 2. DB bağlantısı işletme kimliği bilinmeden açılabilir mi?
- **Kesinlikle Hayır.** Eğer işletme kimliği bilinmeden rastgele bir dosya açılırsa, boş bir SQLite dosyası oluşturulması veya yanlış işletmeye bağlanılması riski doğar. Bu nedenle yönlendirici (`DatabasePathResolver`), işletme kimliği SharedPreferences'ta henüz yoksa varsayılan olarak mevcut `serenut_pos.db` dosyasını açar.

#### 3. Yeni hedef dosya yoksa uygulama boş DB oluşturup mevcut veriyi görünmez hale getirebilir mi?
- **En Büyük Canlı Geçiş Riski!** SQLite `openDatabase` fonksiyonu dosya yoksa otomatik olarak sıfır baytlık boş bir veritabanı oluşturur. Bu durum kullanıcının 37.682 ürününü anında kaybolmuş gibi gösterir.
- **Önleyici Kapı (Triple-Check Invariant):**
  Yönlendirici hedef `nutopia_pos.db` dosyasını ancak ve ancak şu 3 koşul sağlanırsa açar:
  1. `File(targetPath).existsSync() == true`
  2. `File(targetPath).lengthSync() > 10 * 1024 * 1024` (Nutopia için dosya en az 10 MB olmalıdır; boş 0 KB dosyalar derhal reddedilir).
  3. `CoreNextBootstrapCoordinator.getPersistentState() == CoreNextMigrationState.completed`.
  Bu koşullardan biri dahi sağlanmazsa sistem **asla boş dosya açmaz**, otomatik olarak mevcut `serenut_pos.db` dosyasını açar.

#### 4. Eski ve yeni DB aynı anda yazılabilir mi (Split-Brain Riski)?
- **Kesinlikle Hayır.** Uygulamada tek bir `DatabaseManager` singleton nesnesi bulunur. `DatabaseManager.instance.getDatabase()` tek bir aktif bağlantı (`Database`) döner. Tüm repository'ler (`productRepositoryProvider`, `customerRepositoryProvider`, `saleRepositoryProvider`) aynı gateway üzerinden tek bir veritabanına bağlanır.

#### 5. Yarım kalan aktarım nasıl tespit edilecek?
- `CoreNextBootstrapCoordinator` (Stage 10.9.3) yaşam döngüsü durumlarını SharedPreferences'a yazar (`prefKeyMigrationState`). Durum `completed` değilse (`backupInProgress`, `migrationInProgress`, `verificationInProgress`), sistem açılışta işlemin yarım kaldığını anlar (`failedRecoverable`) ve hedef dosyayı aktif yapmaz.

#### 6. Eski sürüme dönüşte (Rollback) yeni DB'de oluşmuş kayıtlar nasıl korunacak?
- Eğer Core Next aktifken satış yapıldıktan sonra eski sürüme dönülmesi gerekirse:
  `ReverseMigrationEngine` (Stage 10.8.5) çalıştırılarak yeni `sales` ve `ledger_entries` kayıtları eski `financial_transactions` formatına aktarılır.
- Pilot aşamasında ise, tam geçiş onaylanana kadar her satış transactional outbox kuyruğunda da tutulduğu için çift yönlü veri kaybı engellenir.

#### 7. Senkronizasyon kuyruğu, benzersiz kimlikler ve idempotency anahtarları nasıl korunacak?
- Göç motoru (`MigrationBridgeEngine`), `sync_v4_outbox` tablosundaki kayıtları, mutasyon ID'lerini ve idempotency anahtarlarını 1:1 aktarır.
- UUIDv4 kimlikleri değiştirilmez; causal sequence sırası korunur.

#### 8. Mevcut kullanıcıların ilk açılışında yanlış tenant veya boş DB seçilmesini hangi kontrol engelleyecek?
- **Tenant Eşleştirme İmzası:**
  Hedef veritabanı açıldığında, içindeki `settings.business_name` veya `business_profiles.name` sorgulanır. Eğer Nutopia için açılıyorsa ve veritabanında "Nutopia Fındık Değirmeni" kaydı bulunmuyorsa veya ürün sayısı < 30.000 ise, veritabanı derhal kapatılır ve fail-closed olarak kaynak `serenut_pos.db` dosyasına dönülür.

### B. Karar Akış Şeması (Decision Flow)

```text
Uygulama Başlatma (AppBootstrap)
         │
         ▼
SharedPreferences Oku (active_tenant_id & migration_state)
         │
         ├─── migration_state != 'completed' ───────────► Mevcut serenut_pos.db Aç (GÜVENLİ LEGACY)
         │
         ▼
Hedef Dosya Kontrolü (File(nutopia_pos.db))
         │
         ├─── Dosya Yok veya Boyut < 10 MB ─────────────► Mevcut serenut_pos.db Aç (BOŞ DB ENGELİ)
         │
         ▼
Bütünlük ve Tenant Doğrulaması (PRAGMA integrity_check && Ürün > 30.000)
         │
         ├─── Doğrulama Başarısız ──────────────────────► Mevcut serenut_pos.db Aç (FAIL-CLOSED)
         │
         ▼
BAŞARILI: core_next/nutopia_pos.db Aç (KONTROLLÜ GEÇİŞ)
```

---

## 5. GÖREV 4 — İZOLE YÖNLENDİRME TEST PLANI

Kod değişikliği yapılmadan önce tanımlanan 8 zorunlu test senaryosu:

| Test Senaryosu | Giriş Koşulu | Beklenen Davranış | Başarı Kriteri |
| :--- | :--- | :--- | :--- |
| **Senaryo 1: İlk Kurulum** | Hiçbir DB dosyası yok. | Temiz başlangıç şeması oluşturulur. | Hata vermeden boş açılış. |
| **Senaryo 2: Mevcut Nutopia Kurulumu** | `serenut_pos.db` v60 var, hedef DB yok. | Kaynak `serenut_pos.db` açılır. | 37.682 ürün eksiksiz listelenir. |
| **Senaryo 3: Hedef DB Yok** | Göç state `completed` işaretlenmiş ama dosya silinmiş. | Boş dosya açılmaz; fail-closed legacy'ye döner. | 0 ürünlük boş ekran engellenir. |
| **Senaryo 4: Bozuk / Yarım Hedef DB** | Hedef dosya 0 KB veya eksik tablolu. | Boyut ve PRAGMA kontrolü hedefi reddeder. | Orijinal `serenut_pos.db` açılır. |
| **Senaryo 5: Tenant Kimliği Okunamıyor** | SharedPreferences silinmiş/boş. | Güvenli varsayılan olarak legacy DB açılır. | Çökme yaşanmaz. |
| **Senaryo 6: Çoklu İşletme Ayrımı** | Nutopia ve Serenut aynı bilgisayarda. | Tenant ID'ye göre izole DB dosyası seçilir. | Çapraz veri karışımı = 0. |
| **Senaryo 7: Ani Kapanış ve Yeniden Açılış** | İşlem ortasında ani kapanış simülasyonu. | WAL checkpoint ve kilit süpürülür, temiz açılır. | Kilitlenme / busy hatası = 0. |
| **Senaryo 8: Geri Dönüş ve Outbox Korunumu** | Core Next'ten Legacy'ye dönüş. | Outbox kuyruğu kaybolmaz, causal sıra korunur. | Senkronizasyon kesintisiz devam eder. |

---

## 6. ÖZET VE SONRAKİ ADIM İÇİN ÖNERİ

- `sync_v4_outbox_adapter_test.dart` testindeki tip hatası düzeltildi; 5 test paketinin tamamı (42/42 test) **%100 PASS** verdi.
- DB yönlendirme tasarımı, boş DB oluşumunu ve veri görünmezliğini imkansız kılan **Triple-Check Invariant** kuralıyla modellendi.
- **Önerilen Sonraki Adım:**
  1. AppData altındaki hedef `databases\core_next\nutopia_pos.db` dosyasının, doğrulanmış sıfır sapmalı motor ile yenilenmesi.
  2. Yukarıda tasarlanan `DatabasePathResolver` mantığının izole bir birim test paketiyle (`test/core_next/database_routing_test.dart`) doğrulanması.

Sonraki aşamaya geçmek için **kullanıcı onayı beklenmektedir.**
