# SERENUT OS — STAGE 10.12.90: RELEASE PAKETİ VE İZOLASYON ÖN KONTROL RAPORU

**Tarih:** 2026-10-22  
**Aşama:** Stage 10.12.90  
**Kapsam:** Release Paketi İncelemesi, İkili Bütünlük, Veritabanı İzolasyonu ve Güvenli Çalıştırma Ön Koşulları  
**Nihai Karar:** **`BLOCKED_FOR_DIRECT_EXE_LAUNCH` / `READY_FOR_SANDBOX_RUNNER_LAUNCH`**

---

## 1. Önceki Aşama Doğrulaması ve Git Durumu

- **Stage 10.12.89 Raporu:** İncelendi. Sync V4 kuruş/TL dönüşümü, `debt` ➔ `manual_debt` eşlemesi, negatif taksit koruması ve repository entegrasyonu `FIXES_VERIFIED` kararıyla mühürlenmiştir.
- **Git Durumu:**
  - `git status --short`: Stage 89 değişiklikleri (`core_next_product_repository.dart`, `core_next_financial_transaction_repository.dart`, `sync_v4_payload_adapter.dart`, `stage10_12_89_sync_compatibility_fix_test.dart` vb.) koruma altındadır; hiçbir değişiklik geri alınmamış veya bozulmamıştır.
  - `git diff --check`: Temiz (çakışma, beyaz boşluk veya bozukluk yok).
- **Hedefli Testler:** İlgisiz testler çalıştırılmamış; sistem kaynakları ve veri güvenliği muhafaza edilmiştir.

---

## 2. Release Paketinin Kontrolü ve İkili Bütünlük

Mevcut release çıktısı dizini:  
`C:\Users\notop\AndroidStudioProjects\shaman_new\build\windows\x64\runner\Release\`

### 2.1. Paket İçeriği ve Dosya Dağılımı

| Dosya / Dizin Adı | Boyut | Tür / Rol |
|---|---|---|
| `serenutos.exe` | 76.288 bayt | Ana Win32 Release Çalıştırılabilir Dosyası |
| `flutter_windows.dll` | 18.803.200 bayt | Flutter C++ Masaüstü Motoru |
| `sqlite3.dll` | 1.501.696 bayt | Yerel SQLite Veritabanı Kütüphanesi |
| `sqlite3_flutter_libs_plugin.dll` | 9.728 bayt | SQLite Flutter Bağlantı Eklentisi |
| `sentry.dll` | 411.648 bayt | Sentry Hata/Crash Raporlama Motoru |
| `serialport.dll` | 59.392 bayt | Seri Port Donanım Kütüphanesi (Terazi / Barkod) |
| `flutter_libserialport_plugin.dll` | 43.008 bayt | Flutter SerialPort Eklentisi |
| `file_selector_windows_plugin.dll` | 110.592 bayt | Dosya Seçici Eklentisi (Yedekleme/Dışa Aktarma) |
| `permission_handler_windows_plugin.dll` | 117.760 bayt | Windows İzin Yönetimi |
| `share_plus_plugin.dll` | 138.240 bayt | Paylaşım Eklentisi |
| `url_launcher_windows_plugin.dll` | 98.304 bayt | URL Başlatıcı Eklentisi |
| `dartjni.dll` | 61.952 bayt | Dart JNI Native Köprüsü |
| `crashpad_handler.exe` | 685.568 bayt | Crashpad Hata Yakalama Süreci |
| `crashpad_wer.dll` | 12.800 bayt | Windows Hata Bildirim Entegrasyonu |
| `native_assets.json` | 45 bayt | Dart Native Varlık Manifesti |
| `data\` (Klasör) | — | AOT Derlenmiş Kod ve Asset Kökü |
| ↳ `data\app.so` | 17.793.952 bayt | Dart AOT Derlenmiş Makine Kodu |
| ↳ `data\icudtl.dat` | 778.864 bayt | ICU Unicode Veri Seti |
| ↳ `data\flutter_assets\` | — | Sertifikalar (`isrgrootx1.pem`), Fontlar, Varlıklar |

### 2.2. EXE ve Binary Kimlik Doğrulaması

- **EXE Dosya Yolu:** `build\windows\x64\runner\Release\serenutos.exe`
- **Boyut:** 76.288 bayt (74,5 KB)
- **Doğrulanan SHA-256 Hash:**  
  `9E5BBCFE61D49C4C2DB261BB1244599F04983A96137A953487A65295FA9A03BD`
- **Stage 10.12.87 Raporu ile Karşılaştırma:**  
  Stage 87 raporundaki değer: `9e5bbcfe61d49c4c2db261bb1244599f04983a96137a953487a65295fa9a03bd`  
  **Sonuç: %100 BİREBİR AYNI.**
- **Derleme Zamanı (LastWriteTime):** `21.10.2026 23:42:01`
- **Sürüm Bilgileri (FileVersionInfo):**
  - `ProductVersion`: `1.3.143+298`
  - `FileVersion`: `1.3.143+298`
  - `FileVersionRaw`: `1.3.143.298`
  - `CompanyName`: `Serenut OS Software Technologies A.Ş.`
  - `ProductName`: `Serenut OS`
- **`app.so` SHA-256:** `2D151050D5EF69EA04F276F1FD05F5208F6F8639112686C536A4B2DB946A092E` (17.793.952 bayt, `21.10.2026 23:41:49`).

### 2.3. Bağımsız Çalışabilirlik (Portability) Değerlendirmesi
- `serenutos.exe` **TEK BAŞINA ÇALIŞTIRILAMAZ**.
- C++ Flutter motoru (`flutter_windows.dll`), native eklenti DLL'leri (`sqlite3.dll` vb.) ve `data/app.so` olmadan başlatıldığında Windows `0xC0000135` (STATUS_DLL_NOT_FOUND) hatası vererek derhal çöker.
- Paket, klasör bütünlüğü korunduğu sürece portable runtime olarak çalışabilir durumdadır.
- Kurulum paketi (Inno Setup / MSIX) henüz paketlenmemiştir.

---

## 3. Veritabanı İzolasyonunun Statik Kod Analizi

### 3.1. Normal Release Modunda Kullanılan Veritabanı Yolları
Kaynak kod takibi (`lib/infrastructure/database/database_provider.dart:800-820`):
```dart
if (isWindows) {
  try {
    final appSupportDir = await getApplicationSupportDirectory();
    return join(appSupportDir.path, 'databases');
  } catch (_) {
    return databaseFactory.getDatabasesPath();
  }
}
```
- Flutter'ın `path_provider_windows` eklentisi, Win32 `SHGetKnownFolderPath(FOLDERID_RoamingAppData)` API'sini ve `Runner.rc`'deki şirket/ürün adını kullanarak şu dizini döner:
  `C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\`
- **Legacy DB Yolu:** `...\Serenut OS\databases\serenut_pos.db`
- **Core Next DB Yolu:** `...\Serenut OS\databases\serenut_core_v2.db`
- **Kullanıcı Ayarları (`shared_preferences.json`):** `...\Serenut OS\shared_preferences.json`

### 3.2. Canlı Kullanıcı Tercihleri ve Pilot Yönlendirmesi
Canlı `shared_preferences.json` salt-okunur taranmış ve şu durum tespit edilmiştir:
- `flutter.core_next_pilot_enabled: True`
- `flutter.last_backup_date: 22.10.2026 00:07:46`
- `flutter.core_next_bootstrap_migration_state`: **Tanımsız (`null`)**

**Pilot Kapısı Akış Değerlendirmesi (`PilotCutoverGate.evaluate()`):**
1. 1. Kural: `core_next_pilot_enabled = true` ➔ Geçer.
2. 2. Kural: `core_next_kill_switch = false` ➔ Geçer.
3. 3. Kural: `CoreNextBootstrapCoordinator.prefKeyMigrationState` sorgulanır. Değer `null` olduğu için `migrationState` `notStarted` olarak çözümlenir.
4. **Fail-Closed Kararı:** `status: PilotGateStatus.blockedMigrationNotCompleted` döner.
5. **Sonuç:** `isPilotActive = false` olur. Uygulama Core Next'e geçmeyerek **Legacy veritabanına (`serenut_pos.db`) yönlenir**.

---

## 4. Legacy ve Core Next Satış Yazma Yolları

Kaynak kod incelemesi (`lib/presentation/controllers/sales_controller.dart:62-80`, `lib/providers/repository_providers.dart:69-79`, `lib/infrastructure/bootstrap/app_bootstrap.dart:269-292`):

1. **Satış Motoru Otoritesi:**
   - `coreNextSaleRepositoryProvider` varsayılan olarak `null`'dur.
   - `AppBootstrap.initPreApp` içerisindeki `PilotCutoverGate.defaultOverrideGenerator` tanımında `enableSalesEngine = false` olarak sabit tutulmaktadır.
   - Bu nedenle `coreNextSaleRepositoryProvider` override edilmez ve `null` kalır.
2. **Repository Yönlendirmesi:**
   - `saleRepositoryProvider` şu kodu çalıştırır:
     ```dart
     final coreRepo = ref.watch(coreNextSaleRepositoryProvider);
     if (coreRepo != null) return coreRepo;
     return SqliteSaleRepository(ref.watch(dbGatewayProvider));
     ```
   - `coreRepo == null` olduğu için satışlar **`SqliteSaleRepository`** tarafından yürütülür.
3. **Fiziksel Veritabanı:**
   - `dbGatewayProvider` doğrudan `DatabaseManager.instance.getDatabase()` üzerinden **`serenut_pos.db`** (Legacy DB) dosyasına yazar.
4. **Çift Veritabanı / Ayrışma Riski:**
   - Satışlar Legacy DB'ye yazılmaya devam ederken, ürün/müşteri/cari hareketler (eğer pilot onaylansaydı) Core Next'e gidecekti.
   - Satış motorunun devri (cutover) yapılmadığı sürece bu mimari ayrışma (split-brain) riski mevcuttur.

---

## 5. Doğrulanamayan Riskler ve Canlı Veri Tehdit Analizi

### 🚨 KRİTİK TEHLİKE: Doğrudan `serenutos.exe` Başlatılması
Eğer kullanıcı veya geliştirici `build\windows\x64\runner\Release\serenutos.exe` dosyasını doğrudan çalıştırırsa:
1. `serenutos.exe` temiz üretim `main.dart` kodundan derlenmiştir.
2. Native Win32 `SHGetKnownFolderPath` çağrısı, komut satırı ortam değişkenlerinden (`$env:APPDATA`) bağımsız olarak doğrudan Windows Kabuğu bilinen klasörler yöneticisinden `C:\Users\notop\AppData\Roaming\...` yolunu alır.
3. Bu nedenle doğrudan çalıştırılan EXE, **CANLI KULLANICI DİZİNİNE VE CANLI `serenut_pos.db` VERİTABANINA BAĞLANIR**.
4. Test amaçlı dahi olsa doğrudan EXE'yi tıklamak veya PowerShell'den parametresiz çalıştırmak canlı veriye temas etme riski doğurur.

### ⚠️ Kod Tazeliği Uyarısı (Binary Stale Uyarısı)
- `build\windows\x64\runner\Release\serenutos.exe` ve `data\app.so`, 21 Ekim 23:42 tarihlidir (Stage 87).
- Stage 89'da yapılan Sync V4 kuruş/TL ve finansal hareket eşleme düzeltmeleri bu EXE'ye henüz derlenmemiştir.
- Dolayısıyla mevcut Release klasöründeki EXE test edilse dahi Stage 89 düzeltmelerini barındırmaz.

---

## 6. Güvenli İzole Çalıştırma Koşulları (Runbook Ön Şartları)

Gerçek masaüstü arayüzünü canlı veriye dokunmadan izole çalıştırmak için zorunlu koşullar:

1. **Yol İzolasyonu (Mock Platform Interface):**
   Stage 87'de başarıyla uygulanan `test/core_next/stage10_12_87_desktop_runner.dart` modelinde olduğu gibi, `PathProviderPlatform.instance` Dart çalışma zamanında geçici bir sandbox dizinine (`C:\Users\notop\AppData\Local\Temp\serenut_desktop_sandbox_90\`) kilitlenmelidir.
2. **Veritabanı Yolu Override:**
   `DatabaseManager.overrideDatabasePath` ve `DatabaseManager.overrideCoreNextDatabasePath` açıkça sandbox altındaki fixture kopyalarına yönlendirilmelidir.
3. **Canlı Kopyalar (Fixture):**
   Canlı `%APPDATA%` dizinindeki hiçbir dosya symlink veya junction ile bağlanmamalı; yalnızca salt-okunur kopya alınarak sandbox'a konmalıdır.
4. **Doğrudan EXE Yasağı:**
   `build\...\Release\serenutos.exe` doğrudan çift tıklanarak VEYA parametresiz çalıştırılmamalıdır.

---

## 7. Sonuç ve Karar

### Karar: **`BLOCKED_FOR_DIRECT_EXE_LAUNCH` / `READY_FOR_SANDBOX_RUNNER_LAUNCH`**

| Kriter | Durum | Açıklama |
|---|---|---|
| Release Paket Bütünlüğü | ✅ TAM | Tüm DLL'ler, Flutter motoru, `data/app.so`, varlıklar eksiksiz. |
| EXE SHA-256 Karşılaştırması | ✅ DOĞRULANDI | Stage 87'deki hash (`9E5BBCFE...`) ile %100 birebir uyuşuyor. |
| DB İzolasyonu (Doğrudan EXE) | ❌ ENGELLİ (BLOCKED) | Doğrudan çalıştırma canlı `%APPDATA%` veritabanına bağlanır. |
| DB İzolasyonu (Sandbox Runner) | ✅ HAZIR | Sandbox runner ve `PathProviderPlatform` mock yapısıyla tam izole çalıştırılabilir. |
| Satış Motoru Güvenliği | ✅ KORUNUYOR | `coreNextSalesEngineEnabledProvider = false` ve `SqliteSaleRepository` modunda. |
| Canlı DB / VPS Bütünlüğü | ✅ DOKUNULMADI | Canlı SQLite dosyalarına, tercihlere ve VPS'ye 1 bayt bile yazılmadı. |

*Ön kontrol tamamlanmıştır. Hiçbir kurulum veya canlı çalıştırma yapılmamıştır.*
