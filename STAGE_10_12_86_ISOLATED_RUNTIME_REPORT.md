# SERENUT OS — STAGE 10.12.86: İZOLE FLUTTER RUNTIME VE GÜVENLİK DOĞRULAMA RAPORU

**Tarih / Saat:** 21 Ekim 2026, 23:28 (TSİ)  
**Hedef İşletme:** Nutopia Fındık Değirmeni (`comp-1785241628448-c7f5677d`)  
**Denetlenen Mimari:** Güncel Kaynak Kod (`lib/` ve `core_next/`) Flutter Runtime Entegrasyonu  
**Test Türü:** %100 İzole Geçici Dizin Tabanlı Flutter Runtime Testi (Zero-Live-Mutation)  
**Son Karar:** **`ISOLATED_RUNTIME_PASS`**

---

## 1. YÖNETİCİ ÖZETİ VE DOĞRULAMA AMACI

Kullanıcının daha önce çalıştırdığı yüklü `serenutos.exe` dosyasının 12 Ekim 2026 tarihli olması sebebiyle, kullanıcının yaptığı deneme işlemleri doğal olarak Legacy `serenut_pos.db` üzerine yazılmıştı. 

Bu aşamada (**Stage 10.12.86**); güncel kaynak kodun Nutopia için Core Next veritabanını (`serenut_core_v2.db`) çalışma anında gerçekten açtığı, doğru repository sınıflarını Riverpod'a enjekte ettiği, tenant izolasyonunu tam koruduğu ve canlı sistem verilerine **en ufak bir yazma yapmadığı** izole bir Flutter çalışma zamanı (runtime) ortamında kanıtlanmıştır.

---

## 2. KESİN KORUMA KURALLARININ SAĞLANMASI VE YOL İZOLASYONU

### 2.1. Canlı Süreç ve Veri Koruması
- **Masaüstündeki Canlı Süreç:** `serenutos.exe` (PID: 3424) kapatılmamış, durdurulmamış veya müdahale edilmemiştir.
- **Canlı Ayar ve Veritabanı:** Canlı `shared_preferences.json`, canlı `serenut_pos.db`, canlı `serenut_core_v2.db` ve Erkul veritabanlarına hiçbir yazma yapılmamıştır.
- **Kullanıcı İşlemleri:** Kullanıcının Stage 85'te gerçekleştirdiği 56 TL'lik manuel borç ve iptal kayıtları aynen korunmuştur.

### 2.2. Yol İzolasyonu Mimarisi
Flutter Windows uygulamalarında varsayılan yol çözümü `SHGetKnownFolderPath(FOLDERID_RoamingAppData)` üzerinden canlı `%APPDATA%` klasörüne gittiği için, `flutter run -d windows` komutunun varsayılan parametrelerle çalıştırılması durumunda canlı verilere erişme riski mevcuttur. Bu risk şu yöntemle %100 bertaraf edilmiştir:

1. **İzole Geçici Dizin:** Windows `Directory.systemTemp` altında benzersiz bir dizin açıldı:
   `C:\Users\notop\AppData\Local\Temp\serenut_stage86_isolated_aea42031\`
2. **Platform Arayüzü İzolasyonu (`PathProviderPlatform`):**  
   `PathProviderPlatform.instance = IsolatedPathProviderPlatform(isolatedDir)` atanarak `getApplicationDocumentsPath()`, `getApplicationSupportPath()` ve `getTemporaryPath()` çağrılarının tamamı izole dizine hapsedildi.
3. **Veritabanı Yolu İzolasyonu (`DatabaseManager`):**  
   `DatabaseManager.overrideDatabasePath` ve `DatabaseManager.overrideCoreNextDatabasePath` doğrudan izole dizin içindeki dosyalara yönlendirildi.
4. **Fixture Kopyalama (Zero Symlink/Junction):**  
   Canlı dosyalara bağlanan hiçbir sembolik bağlantı veya junction kullanılmadı. Doğrulanmış yedek fixture'ları doğrudan izole klasöre bayt bayt kopyalandı.
5. **İzole SharedPreferences:**  
   `SharedPreferences.setMockInitialValues` ile pilot etkinleştirmesi (`core_next_pilot_enabled: true`) yalnızca izole bellek ortamında yapıldı.

---

## 3. ÇALIŞTIRILAN KOMUTLAR VE ÇALIŞMA ZAMANI KANITLARI

### 3.1. Çalıştırılan Komut
```powershell
flutter test test/core_next/stage10_12_86_isolated_runtime_test.dart
```

### 3.2. Gerçek Runtime Çıktısı ve Log Kanıtları
```text
00:00 +0: (setUpAll)
================================================================
[STAGE 10.12.86] CANLI VERİTABANI BAŞLANGIÇ HASH DEĞERLERİ:
  Canlı Legacy DB (C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db):
    SHA-256: cad5c91ff970b84ebf8270af8cce58f72dcf6b4bda4b4dd48a74f675c17234f3
  Canlı Core Next DB (C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_core_v2.db):
    SHA-256: 854611f801684d20004d9880ef8ed408630069646b4d473722a84a13e3024a59
================================================================

--- TEST 1: Nutopia İzole Runtime Pipeline Başlatılıyor ---
  İzole Çalışma Dizini: C:\Users\notop\AppData\Local\Temp\serenut_stage86_isolated_aea42031
  İzole Legacy DB Yolu: C:\Users\notop\AppData\Local\Temp\serenut_stage86_isolated_aea42031\databases\serenut_pos.db
  İzole Core Next DB Yolu: C:\Users\notop\AppData\Local\Temp\serenut_stage86_isolated_aea42031\databases\serenut_core_v2.db

[DatabaseManager] 🛡️ All schema invariants verified successfully.
[AppBootstrap] 🚀 Core Next Pilot Yönlendirmesi AKTİF: Tüm pilot cutover kontrolleri (%100 bütünlük, şema v3, yedekleme kanıtı, tenant eşleşmesi) doğrulandı.
  PilotGate Sonucu:
    isPilotActive: true
    status: PilotGateStatus.pilotActiveApproved
    reason: Tüm pilot cutover kontrolleri (%100 bütünlük, şema v3, yedekleme kanıtı, tenant eşleşmesi) doğrulandı.
    targetDbPath: C:\Users\notop\AppData\Local\Temp\serenut_stage86_isolated_aea42031\databases\serenut_core_v2.db

  Gerçek Repository Türleri:
    Product: CoreNextProductRepository
    Customer: CoreNextCustomerRepository
    Financial: CoreNextFinancialTransactionRepository
    Sale: SqliteSaleRepository

  İzole Depodan Okunan Kayıtlar:
    Aktif Ürün Sayısı: 17
    Aktif Müşteri Sayısı: 619

  İzole DB Tablo Toplamları:
    products: 37682
    customers: 626
    ledger_entries: 1505
    orders: 846
  [PASS] Test 1 başarıyla tamamlandı.

--- TEST 2: Erkul Çeyiz Çapraz Erişim Engeli Test Ediliyor ---
[DatabaseManager] 🛡️ All schema invariants verified successfully.
[AppBootstrap] 🛡️ Core Next Pilot Kapalı (Legacy Aktif): Tenant ID uyuşmazlığı: İstenen "comp-1791194455402-bdc6d8d1" != DB "nutopia".
  Erkul PilotGate Sonucu:
    isPilotActive: false
    status: PilotGateStatus.blockedTenantMismatch
    reason: Tenant ID uyuşmazlığı: İstenen "comp-1791194455402-bdc6d8d1" != DB "nutopia".
  Erkul Repository Türleri:
    Product: SqliteProductRepository
    Customer: SqliteCustomerRepository
  [PASS] Test 2 başarıyla tamamlandı.

--- TEST 3: Canlı Veritabanı Değişmezlik Doğrulaması ---
  Canlı Legacy DB (C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db):
    Önceki: cad5c91ff970b84ebf8270af8cce58f72dcf6b4bda4b4dd48a74f675c17234f3
    Sonraki: cad5c91ff970b84ebf8270af8cce58f72dcf6b4bda4b4dd48a74f675c17234f3
  Canlı Core Next DB (C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_core_v2.db):
    Önceki: 854611f801684d20004d9880ef8ed408630069646b4d473722a84a13e3024a59
    Sonraki: 854611f801684d20004d9880ef8ed408630069646b4d473722a84a13e3024a59
  [PASS] Canlı veritabanlarının sıfır mutasyon ile korunduğu kesin olarak kanıtlandı.

00:07 +3: All tests passed!
```

---

## 4. BULGULAR VE KANITLAR TABLOSU

| Kontrol Maddesi | Beklenen Değer | Runtime Çıktısı | Durum |
| :--- | :--- | :--- | :--- |
| **Nutopia Pilot Kapısı** | `PilotGateStatus.pilotActiveApproved` | `PilotGateStatus.pilotActiveApproved` | **BAŞARILI** |
| **Yönlendirilen DB Yolu** | İzole `serenut_core_v2.db` | `C:\...\Temp\...\databases\serenut_core_v2.db` | **BAŞARILI** |
| **Ürün Deposu Sınıfı** | `CoreNextProductRepository` | `CoreNextProductRepository` | **BAŞARILI** |
| **Müşteri Deposu Sınıfı** | `CoreNextCustomerRepository` | `CoreNextCustomerRepository` | **BAŞARILI** |
| **Finans Deposu Sınıfı** | `CoreNextFinancialTransactionRepository` | `CoreNextFinancialTransactionRepository` | **BAŞARILI** |
| **Satış Motoru Sınıfı** | `SqliteSaleRepository` (Güvenli Pilot) | `SqliteSaleRepository` | **BAŞARILI** |
| **Aktif Ürün Sayısı** | 17 adet | 17 adet | **BAŞARILI** |
| **Aktif Müşteri Sayısı** | 619 adet | 619 adet | **BAŞARILI** |
| **Toplam Tablo Satırları**| 37.682 ürün, 626 müşteri, 1.505 ledger | 37.682 ürün, 626 müşteri, 1.505 ledger | **BAŞARILI** |
| **Erkul Çeyiz İzolasyonu** | `PilotGateStatus.blockedTenantMismatch` | `PilotGateStatus.blockedTenantMismatch` | **BAŞARILI** |
| **Erkul Depo Sınıfları** | `SqliteProductRepository` (Legacy) | `SqliteProductRepository` (Legacy) | **BAŞARILI** |
| **Canlı DB Değişmezliği**| SHA-256 Before == After | Birebir Eşit (Sıfır Mutasyon) | **BAŞARILI** |

---

## 5. CANLI VERİTABANLARININ HASH DEĞİŞMEZLİK KANITI

Test öncesi ve sonrası canlı dosya SHA-256 değerleri adli olarak karşılaştırılmıştır:

1. **Canlı Legacy Veritabanı (`serenut_pos.db`):**
   - **Konum:** `%APPDATA%\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_pos.db`
   - **Test Öncesi SHA-256:** `cad5c91ff970b84ebf8270af8cce58f72dcf6b4bda4b4dd48a74f675c17234f3`
   - **Test Sonrası SHA-256:** `cad5c91ff970b84ebf8270af8cce58f72dcf6b4bda4b4dd48a74f675c17234f3`
   - **Fark:** **0 bayt (Kusursuz Değişmezlik)**

2. **Canlı Core Next Veritabanı (`serenut_core_v2.db`):**
   - **Konum:** `%APPDATA%\Serenut OS Software Technologies A.Ş\Serenut OS\databases\serenut_core_v2.db`
   - **Test Öncesi SHA-256:** `854611f801684d20004d9880ef8ed408630069646b4d473722a84a13e3024a59`
   - **Test Sonrası SHA-256:** `854611f801684d20004d9880ef8ed408630069646b4d473722a84a13e3024a59`
   - **Fark:** **0 bayt (Kusursuz Değişmezlik)**

---

## 6. KALAN ENGELLER VE SONUÇ

### Kalan Somut Engel
Güncel kaynak kod, izole runtime testinde Core Next yönlendirmesini, veri okumasını ve tenant ayrımını **%100 başarıyla** gerçekleştirmiştir. 

Ancak kullanıcının Windows masaüstünde tıkladığı `C:\Program Files\Serenut OS\serenutos.exe` dosyası **12 Ekim 2026** tarihli kurulu eski sürümdür. Bu nedenle kullanıcı canlı arayüzde test yaptığında Windows bu eski binary'yi çalıştırmakta ve doğal olarak legacy veritabanına bağlanmaktadır.

### Son Karar
**`ISOLATED_RUNTIME_PASS`**

- Güncel kaynak kod mimari olarak Core Next'e geçişe ve Nutopia tenant yönlendirmesine **tamamen hazırdır**.
- Canlı veritabanları ve kullanıcı oturumu sıfır hasar ve sıfır mutasyonla korunmuştur.
- Bir sonraki aşamada kullanıcının gerçek arayüzde Core Next'i görebilmesi için, güncel kodların `flutter build windows` ile derlenip production paketine dönüştürülmesi veya geliştirme ortamından kontrollü bir şekilde çalıştırılması gerekmektedir.
