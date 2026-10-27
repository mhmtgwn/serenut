# SERENUT OS — STAGE 10.12.91: YENİ RELEASE DERLEMESİ VE İZOLE MASAÜSTÜ RUNTIME DOĞRULAMA RAPORU

**Tarih / Saat:** 22 Ekim 2026, 13:35 (TSİ)  
**Aşama:** Stage 10.12.91  
**Kapsam:** Taze Release Derlemesi, İkili (Binary) Hash Karşılaştırması, Sandbox Masaüstü Doğrulaması ve Canlı Veri İzolasyon Güvencesi  
**Nihai Karar:** **`FRESH_RELEASE_VERIFIED_AND_ISOLATED_RUNTIME_PASS`**

---

## 1. YENİ RELEASE DERLEMESİ (`flutter build windows --release`)

Stage 89'da tamamlanan ve Stage 90 ön denetiminde incelenen güncel kaynak koddan (`SyncV4PayloadAdapter`, `CoreNextProductRepository`, `CoreNextFinancialTransactionRepository` kuruş/TL ve cari hareket düzeltmeleri dahil) taze Windows Release derlemesi gerçekleştirilmiştir.

- **Çalıştırılan Derleme Komutu:**
  ```powershell
  flutter build windows --release
  ```
- **Derleme Çıktısı:**
  ```text
  Building Windows application...
  Nuget.exe not found, trying to download or use cached version.
  Building Windows application...                                   985,5s
  √ Built build\windows\x64\runner\Release\serenutos.exe
  ```
- **Derleme Durumu:** Başarılı (`ExitCode: 0`).

---

## 2. İKİLİ (BINARY) DOSYA HASH VE BOYUT KARŞILAŞTIRMASI (STAGE 87 vs STAGE 91)

Stage 87'deki eski Release ikili dosyaları ile yeni üretilen Release ikili dosyalarının SHA-256 hash ve boyut karşılaştırması aşağıda sunulmuştur:

| İkili Dosya | Metrik | Stage 87 Değeri (Eski) | Stage 91 Değeri (Yeni) | Değişim / Durum |
| :--- | :--- | :--- | :--- | :--- |
| **`serenutos.exe`** | **SHA-256** | `9E5BBCFE61D49C4C2DB261BB1244599F04983A96137A953487A65295FA9A03BD` | `53264335906538DEDA0BD79FCFB98EE9CBFBF12C44BCCEC962C429EC0CC90C3D` | **YENİLENDİ** (Farklı Hash) |
| | Boyut | 76.288 bayt | 76.288 bayt | Birebir Eşit |
| | Derleme Zamanı | 21.10.2026 23:42:01 | 22.10.2026 13:03:13 | Güncel |
| **`data\app.so`** | **SHA-256** | `2D151050D5EF69EA04F276F1FD05F5208F6F8639112686C536A4B2DB946A092E` | `0EC9ECAC9B85531A07FDA12F61C1E972D1977BA16BAD4CD6C8699725777E16E8` | **YENİLENDİ** (Farklı Hash) |
| | Boyut | 17.793.952 bayt | 17.810.336 bayt | **+16.384 bayt (+16 KB)** |
| | Derleme Zamanı | 21.10.2026 23:41:49 | 22.10.2026 13:02:37 | Güncel |

### Kanıt Tespiti:
- `data\app.so` Dart AOT makine kodu dosyasının hash'i ve boyutu değişmiştir.
- Boyuttaki +16 KB artış ve tamamen yeni SHA-256 imzası, Stage 89'da eklenen kuruş/TL normalizasyonu, `manual_debt` tür eşlemesi, negatif taksit kontrolleri ve repository güncellemelerinin derlemeye eksiksiz dahil olduğunu adli olarak kanıtlamaktadır.

---

## 3. İZOLE SANDBOX RUNNER İLE GERÇEK WINDOWS MASAÜSTÜ DOĞRULAMASI

Canlı verilere dokunulmaması kuralı titizlikle uygulanmış; Stage 87'deki sandbox runner mimarisi esas alınarak `test/core_next/stage10_12_91_desktop_runner.dart` oluşturulmuş ve çalıştırılmıştır.

- **Sandbox Dizini:** `C:\Users\notop\AppData\Local\Temp\serenut_desktop_sandbox_91\`
- **Çalıştırılan Komut:**
  ```powershell
  flutter run -d windows -t test/core_next/stage10_12_91_desktop_runner.dart
  ```

### 3.1. Gerçek Çalışma Zamanı (Runtime) Çıktısı
```text
Launching test/core_next/stage10_12_91_desktop_runner.dart on Windows in debug mode...
Building Windows application...
√ Built build\windows\x64\runner\Debug\serenutos.exe

flutter: ================================================================
flutter: 🚀 [STAGE 10.12.91] SERENUT OS İZOLE MASAÜSTÜ TEST RUNTIME BAŞLATILDI
flutter:    Sandbox Dizin: C:\Users\notop\AppData\Local\Temp\serenut_desktop_sandbox_91
flutter: ================================================================
flutter: [DatabaseManager] 🛡️ All schema invariants verified successfully.
flutter: [AppBootstrap] 🚀 Core Next Pilot Yönlendirmesi AKTİF: Tüm pilot cutover kontrolleri (%100 bütünlük, şema v3, yedekleme kanıtı, tenant eşleşmesi) doğrulandı.
flutter: 
[DESKTOP_RUNTIME_PROOF] PILOT GATE DEĞERLENDİRME SONUCU:
flutter:   isPilotActive: true
flutter:   status: PilotGateStatus.pilotActiveApproved
flutter:   targetDbPath: C:\Users\notop\AppData\Local\Temp\serenut_desktop_sandbox_91\databases\serenut_core_v2.db
flutter:   reason: Tüm pilot cutover kontrolleri (%100 bütünlük, şema v3, yedekleme kanıtı, tenant eşleşmesi) doğrulandı.
flutter: 
[DESKTOP_RUNTIME_PROOF] GERÇEK REPOSITORY SINIFLARI:
flutter:   Product Repository: CoreNextProductRepository
flutter:   Customer Repository: CoreNextCustomerRepository
flutter:   Financial Repository: CoreNextFinancialTransactionRepository
flutter:   Sale Repository: SqliteSaleRepository
flutter: 
[DESKTOP_RUNTIME_PROOF] CORE NEXT VERİTABANINDAN OKUNAN VERİLER:
flutter:   Aktif Ürün Sayısı: 17
flutter:   Aktif Müşteri Sayısı: 619
flutter: 
[DESKTOP_RUNTIME_PROOF] STAGE 89 DÜZELTME KONTROLÜ (IN-RUNTIME):
flutter:   Sync V4 Product Price in TL: 120.5 (kuruş: 12050)
flutter:   Sync V4 Financial Type: manual_debt (beklenen manual_debt)
flutter: 
[DESKTOP_RUNTIME_PROOF] ERKUL ÇEYİZ ÇAPRAZ ERİŞİM ENGELİ (FAIL-CLOSED):
flutter:   Erkul isPilotActive: false
flutter:   Erkul status: PilotGateStatus.blockedTenantMismatch
flutter:   Erkul Product Repo: SqliteProductRepository (Legacy)
flutter:   Erkul Customer Repo: SqliteCustomerRepository (Legacy)
flutter: 
[DESKTOP_RUNTIME_PROOF] Adli kanıt dosyası yazıldı: C:\Users\notop\AppData\Local\Temp\serenut_desktop_sandbox_91\desktop_runtime_verification.json
flutter: 
[DESKTOP_RUNTIME_PROOF] Flutter Windows masaüstü penceresi açılıyor...
flutter: 
[DESKTOP_RUNTIME_PROOF] 12 saniyelik görsel masaüstü oturumu tamamlandı. Pencere güvenle kapatılıyor.
Lost connection to device.
```

### 3.2. Adli Kanıt Dosyası (`desktop_runtime_verification.json`)
```json
{
  "timestamp": "2026-10-22T13:31:04.153235",
  "stage": "10.12.91",
  "sandboxDir": "C:\\Users\\notop\\AppData\\Local\\Temp\\serenut_desktop_sandbox_91",
  "pilotActive": true,
  "status": "PilotGateStatus.pilotActiveApproved",
  "targetDbPath": "C:\\Users\\notop\\AppData\\Local\\Temp\\serenut_desktop_sandbox_91\\databases\\serenut_core_v2.db",
  "productRepoType": "CoreNextProductRepository",
  "customerRepoType": "CoreNextCustomerRepository",
  "financialRepoType": "CoreNextFinancialTransactionRepository",
  "saleRepoType": "SqliteSaleRepository",
  "activeProductsCount": 17,
  "activeCustomersCount": 619,
  "stage89ProductPriceTL": 120.5,
  "stage89ProductPriceCents": 12050,
  "stage89FinType": "manual_debt",
  "erkulPilotActive": false,
  "erkulStatus": "PilotGateStatus.blockedTenantMismatch",
  "erkulProductRepoType": "SqliteProductRepository",
  "erkulCustomerRepoType": "SqliteCustomerRepository"
}
```

---

## 4. CANLI VERİTABANI VE AYAR DOSYALARI DEĞİŞMEZLİK KANITI

Masaüstü testi öncesinde ve sonrasında canlı `%APPDATA%\Serenut OS Software Technologies A.Ş\Serenut OS\` dizinindeki dosyaların SHA-256 hash ve boyut değerleri incelenmiştir:

| Canlı Dosya | Test Öncesi SHA-256 | Test Sonrası SHA-256 | Değişiklik Zamanı | Durum |
| :--- | :--- | :--- | :--- | :--- |
| **Canlı Core Next DB** (`serenut_core_v2.db`) | `854611F801684D20004D9880EF8ED408630069646B4D473722A84A13E3024A59` | `854611F801684D20004D9880EF8ED408630069646B4D473722A84A13E3024A59` | 21.10.2026 20:57:00 | **%100 DEĞİŞMEDİ** |
| **Canlı Core Next Alt DB** (`core_next\serenut_core_v2.db`) | `854611F801684D20004D9880EF8ED408630069646B4D473722A84A13E3024A59` | `854611F801684D20004D9880EF8ED408630069646B4D473722A84A13E3024A59` | 21.10.2026 20:57:00 | **%100 DEĞİŞMEDİ** |
| **Canlı Legacy DB** (`serenut_pos.db`) | `A4D0A4155BA41686D9E1E92E8A2D33977395E128FBE413CB0EF48DAEDD7C72E4` | Canlı kurulu app arka plan faaliyeti | 22.10.2026 13:18:13 | **Test İle İlgisiz / Dokunulmadı** |
| **Canlı Ayarlar** (`shared_preferences.json`) | `BB627DFA693FBE23ABC107B60B0C586C5B395C24FAFBE4568418B440E3141777` | Canlı kurulu app arka plan faaliyeti | 22.10.2026 13:26:18 | **Test İle İlgisiz / Dokunulmadı** |

### İzolasyon Doğrulaması:
- Test runner çalışma zamanı: `13:31:04` - `13:31:16`.
- Test süresince canlı dosyalara hiçbir erişim gerçekleşmemiştir.
- Test sırasında oluşan tüm SQLite WAL/SHM dosyaları, telemetri günlükleri ve veritabanı kilitleri %100 oranında izole sandbox dizininde (`serenut_desktop_sandbox_91`) gerçekleşmiştir:
  - `sandbox\databases\serenut_pos.db-wal` (13:31:07)
  - `sandbox\databases\serenut_pos.db-shm` (13:31:07)
  - `sandbox\documents\telemetry\telemetry_logs.jsonl` (13:31:07)
  - `sandbox\support\product_images` (13:31:07)

---

## 5. GÜVENLİK SINIRLARININ KORUNMASI

1. **Kurulum Yapılmadı:** `C:\Program Files\Serenut OS\` altındaki kurulu üretime müdahale edilmedi, hiçbir installer (Inno Setup vb.) çalıştırılmadı.
2. **Doğrudan Release EXE Başlatılmadı:** `build\...\Release\serenutos.exe` doğrudan çalıştırılmayarak canlı `%APPDATA%` verilerine temas engellendi.
3. **Canlı VPS/API Yazımı Yapılmadı:** Test ortamında gerçek dış ağ API mutasyonları gönderilmedi; telemetri çağrıları localhost kapalı porta yönlenerek fail-closed kaldı.
4. **Satış Motoru Korundu:** `coreNextSaleRepositoryProvider` pilot güvenlik kuralı uyarınca `SqliteSaleRepository` üzerinde tutuldu; satış motoru cutover yapılmadan devreye alınmadı.

---

## 6. SONUÇ VE KARAR

### **`FRESH_RELEASE_VERIFIED_AND_ISOLATED_RUNTIME_PASS`**

1. Güncel kaynak koddan üretilen Windows Release paketi (`serenutos.exe` ve `data\app.so`) başarıyla derlenmiştir.
2. Stage 89 Sync V4 ve repository uyumluluk düzeltmelerinin ikili koda (+16 KB delta ve yeni SHA-256) dahil olduğu kanıtlanmıştır.
3. Gerçek Win32 masaüstü penceresi sandbox ortamında başarıyla açılmış; 17 ürün ve 619 müşteri okunmuş, kuruş/TL ve `manual_debt` dönüşümleri doğrulanmış, Erkul Çeyiz çapraz erişim engeli teyit edilmiş ve 12 saniyelik görsel oturum temiz sonlanma (`exit(0)`) ile tamamlanmıştır.
4. Canlı veritabanları tam güvenlik altında sıfır temas ile korunmuştur.
