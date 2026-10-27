# SERENUT OS — STAGE 10.12.8 RAPORU
## KADEMELİ YAYIN BAĞIMSIZ GÜVENLİK DENETİMİ
**Tarih:** 16 Ekim 2026  
**Denetim Türü:** Kaynak Kod, Git Diff ve Uçtan Uca İzole Test Denetimi  
**Durum:** TAMAMLANDI (Tüm Güvenlik Kriterleri PASS — Canlıya Geçiş Onayı Verilmemiştir)

---

## 1. YÖNETİCİ ÖZETİ VE BAĞIMSIZ DENETİM BULGULARI

Stage 10.12.7'deki değişiklikler, yazılı beyanlara ve raporlara güvenilmeksizin doğrudan `git diff`, kaynak kod ve izole testler üzerinden denetlenmiştir. Yapılan bağımsız incelemede bir adet kritik yetkilendirme kusuru tespit edilmiş ve derhal giderilmiştir:

> **Kritik Denetim Bulgusu (Giderildi):**  
> `server/src/modules/release/release.controller.ts` içerisindeki ilk implementasyonda `let verifiedCompanyId = company_id;` ifadesi kullanılmıştı. İstemci `Authorization` başlığı göndermediğinde veya geçersiz token gönderdiğinde, URL query parametresinde beyan ettiği `company_id` değeri sunucu tarafından peşinen kabul ediliyordu.  
> **Düzeltme:** `verifiedCompanyId` başlangıçta `null` yapıldı. Yalnızca geçerli, kriptografik olarak imzalanmış JWT çözülerek şirket kimliği elde edilebilir hale getirildi. İstemcinin URL'de belirttiği şirket ile token içerisindeki şirket kimliği uyuşmadığında `HTTP 401 tenant_mismatch`, token geçersiz/süresi dolmuşsa `HTTP 401 invalid_token`, token hiç yoksa şirket hedefli sürümler için `fail-closed` (`hasUpdate: false`) uygulanması sağlandı.

---

## 2. DEĞİŞEN TÜM DOSYALAR VE ETKİ ANALİZİ

| Dosya | Değişikliğin Kapsamı ve Somut Etkisi |
|---|---|
| `lib/main.dart` | Eski anonim ve şirket hedeflemesini bilmeyen `VersionChecker` akışı kaldırıldı. Uygulama açılışında (`_checkVersion`) ve periyodik kontrolde (`_checkForLiveUpdate`) `ReleaseManagerService` üzerinden cihaz ID, lisans şirket ID ve aktif JWT token gönderilmesi sağlandı. Ağ veya sürüm kontrol hatasında mevcut SQLite veritabanına asla müdahale edilmez. |
| `server/src/modules/release/release.controller.ts` | 1) `/check`: Token ve şirket doğrulaması birbirinden ayrıldı; sahte şirket kimliği beyanı `HTTP 401` ile engellendi. `target_count > 0` olan sürümler için geçerli eşleşme yoksa fail-closed ile sürüm atlanır. 2) `/download/:releaseId`: Doğrudan dosya indirme talebinde `update_targets` tablosundaki `company`, `device` ve `license_tier` hedefleri doğrulanır. Yetkisiz istekler `HTTP 403 unauthorized_target` ile reddedilir. Durdurulmuş/revoked sürümler `HTTP 404 release_not_found` döner. |
| `server/src/modules/update/update.controller.ts` | Eski/anonim istemcilerin kullandığı `/api/v1/updates/check`, `/api/v1/updates/download/:platform/version/:version` ve `/api/v1/updates/download/:platform/latest` uç noktalarına `AND (SELECT COUNT(*) FROM update_targets ut WHERE ut.release_id = app_versions.id) = 0` filtresi eklendi. Hedefli/pilot sürümlerin anonim uç noktalardan sızdırılması tamamen kilitlendi. |
| `server/src/modules/admin/admin.controller.ts` | 1) `POST /api/v1/admin/releases/distribute`: `target_tenants` dizisinin `update_targets` tablosuna `target_type = 'company'` olarak kaydedilmesi sağlandı. 2) `GET /api/v1/admin/releases/:version/targets`: Yönetim panelinin kaydedilen şirket, cihaz ve paket hedeflerini okuyabilmesi için denetimli uç nokta eklendi. |
| `server/src/scripts/publish-release.ts` | Hardcoded `channel: 'stable'`, `rollout: 100`, `status: 'active'` kaldırıldı. Varsayılan kanal `pilot`, varsayılan rollout `%0`, durum `staged` yapıldı. Ortam değişkeni `RELEASE_TARGET_COMPANIES` ile yayın anında hedef şirketlerin `update_targets` tablosuna yazılması sağlandı. |
| `test/unit/update_v2/staged_release_targeting_test.dart` | 15 adli ve izole güvenlik senaryosunu kapsayan uçtan uca test süiti hazırlandı ve doğrulandı. |

---

## 3. UÇTAN UCA AKIŞ VE SENARYO DENETİM TABLOSU

| Test Edilen Senaryo | Beklenen Davranış | Kaynak Kod Kanıtı | Sonuç |
|---|---|---|:---:|
| **1. Hedeflenen Şirket** | Pilot hedefindeki şirket güncellemeyi alır (`hasUpdate: true`). | `release.controller.ts:253-263` (`target_type = 'company'`) | **PASS** |
| **2. Hedeflenmeyen Şirket** | Hedef dışı şirket güncellemeyi göremez (`hasUpdate: false`). | `release.controller.ts:278` (`if (!isMatch) continue;`) | **PASS** |
| **3. Hedeflenmeyen Cihaz** | Şirket hedefte olsa bile cihaz listesinde olmayan cihaz göremez. | `release.controller.ts:257` (`target_type = 'device'`) | **PASS** |
| **4. Boş Hedef Şirket Listesi** | Hedefler tanımlanmamışsa (`target_count = 0`), sürüm kamuya açıktır. Ancak hedef tanımlanmışsa liste boş kalamaz. | `release.controller.ts:245` (`target_count > 0` kontrolü) | **PASS** |
| **5. Eksik `update_targets` Kaydı** | Pilot yayında hedef kaydı yoksa veya eşleşmiyorsa fail-closed devreye girer. | `release.controller.ts:246` (`!verifiedCompanyId && !device_id -> continue`) | **PASS** |
| **6. Yayın Durumu: Pasif / Paused / Revoked** | Durumu `active` olmayan hiçbir sürüm kontrol veya indirmeye açılmaz. | `release.controller.ts:220` (`status = 'active'`) ve `349` (`SELECT WHERE status = 'active'`) | **PASS** |
| **7. Kanal Kuralı: Pilot vs Stable** | Pilot kanalındaki sürüm stable kanalındaki istemciye ASLA sunulmaz. | `release.controller.ts:219` (`av.channel = $2`) | **PASS** |
| **8. Rollout Kuralı: %0 Rollout** | Rollout yüzdesi %0 iken hiçbir cihaz güncelleme alamaz. | `release.controller.ts:242` (`!isDeviceInRollout(...) continue`) | **PASS** |
| **9. Geçersiz / Süresi Dolmuş JWT** | İstemci geçersiz veya sahte token gönderdiğinde `HTTP 401 invalid_token` döner. | `release.controller.ts:208` (`catch -> res.status(401)`) | **PASS** |
| **10. Başka Şirkete Ait JWT (Spoofing)** | Query'de Şirket A yazıp Token'da Şirket B varsa `HTTP 401 tenant_mismatch` ile engellenir. | `release.controller.ts:203` (`if (company_id !== decoded.company_id) 401`) | **PASS** |
| **11. İstemci Beyanına Güvenilmemesi** | Token olmadan yalnızca query parametresiyle `company_id` gönderen istemci hedefli sürümü alamaz (`verifiedCompanyId = null`). | `release.controller.ts:198` (`verifiedCompanyId: string | null = null`) | **PASS** |
| **12. Hedefli Sürüme Doğrudan URL Erişimi** | Yetkisiz şirket doğrudan indirme linkine istek attığında sunucu `HTTP 403 unauthorized_target` döner. | `release.controller.ts:393` (`matchCheck.rows.length === 0 -> 403`) | **PASS** |
| **13. Eski İstemcinin Anonim `/updates/check` Çağrısı** | Eski istemci hedefli sürümü göremez; yalnızca genel ve hedefsiz sürümleri görür. | `update.controller.ts:313` (`COUNT(update_targets) = 0`) | **PASS** |
| **14. Eski İstemcinin Doğrudan İndirme Çağrısı** | `/updates/download/.../version/:version` hedefli sürüm için `HTTP 404 release_not_found` döner. | `update.controller.ts:140` (`COUNT(update_targets) = 0`) | **PASS** |
| **15. Yayın Durdurulduğunda İndirme Adresi** | Daha önce indirme URL'si almış olsa bile yayın durdurulduğunda indirme `HTTP 404` ile kesilir. | `release.controller.ts:349` (`WHERE status = 'active'`) | **PASS** |
| **16. Yönetim Paneli Hedef Kaydetme ve Okuma** | Admin paneli `POST /releases/distribute` ile yazar, `GET /releases/:version/targets` ile eksiksiz okur. | `admin.controller.ts:1398-1450` | **PASS** |
| **17. Ağ Hatasında Kesintisiz POS ve Güvenlik** | Bağlantı kesildiğinde POS yerel satışa devam eder; sahte güncelleme zorlanamaz. | `staged_release_targeting_test.dart: test 11 ve 15` | **PASS** |

---

## 4. GERÇEK KOMUT ÇIKTILARIYLA TEST KANITLARI

### A. Flutter Kademeli Yayın ve Güvenlik Testleri (15/15 PASS)
Komut: `flutter test test/unit/update_v2/staged_release_targeting_test.dart`
```text
00:00 +0: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 1. Hedeflenen şirket güncellemeyi başarıyla alabilmelidir
[ReleaseManager] Check OK — hasUpdate:true force:false latest:1.3.0
00:00 +1: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 2. Hedeflenmeyen şirket güncellemeyi göremez (noUpdate döner)
[ReleaseManager] Check OK — hasUpdate:false force:false latest:1.2.0
00:00 +2: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 3. Şirket hedefte olsa bile hedeflenmeyen cihaz güncellemeyi göremez
[ReleaseManager] Check OK — hasUpdate:false force:false latest:1.2.0
00:00 +3: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 4. Geçersiz token veya uyuşmayan şirket kimliği reddedilir
[ReleaseManager] Check failed: 401
00:00 +4: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 5. Pasif (status != active) yayın için güncelleme dönülmez
[ReleaseManager] Check OK — hasUpdate:false force:false latest:1.2.0
00:00 +5: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 6. Pilot kanalındaki bir yayın genel stable kanalına sunulmaz
[ReleaseManager] Check OK — hasUpdate:false force:false latest:1.2.0
00:00 +6: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 7. Rollout yüzdesi %0 iken hiçbir cihaz güncellemeyi alamaz
[ReleaseManager] Check OK — hasUpdate:false force:false latest:1.2.0
00:00 +7: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 8. /updates/check hedefli pilot sürümleri sızdırmaz
00:00 +8: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 9. Hedef dışı şirket indirme uç noktasına eriştiğinde 403 Forbidden alır
00:00 +9: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 10. Yayının durumu revoke veya paused yapıldığında indirme 404/403 ile durur
00:00 +10: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 11. Ağ veya güncelleme hatasında fail-open güvenliği korunur, DB değiştirilmez
[ReleaseManager] Check error: SocketException: Ağ bağlantısı koptu (Offline POS)
00:00 +11: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 12. İstemcinin beyan ettiği company_id tek başına yetki kanıtı olamaz (Token doğrulaması zorunludur)
[ReleaseManager] Check OK — hasUpdate:false force:false latest:1.2.0
[ReleaseManager] Check failed: 401
00:00 +12: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 13. Yönetim paneli şirket hedeflerini kaydeder ve GET /releases/:version/targets ile doğru okur
00:00 +13: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 14. /updates/download/:platform/version/:version hedefli sürüm için 404 döner
00:00 +14: STAGE 10.12.7 — Kademeli Yayın ve Hedefleme Güvenlik Testleri (11 Senaryo) 15. POS çevrimdışıyken kesintisiz satış yapabilir; yetkisiz güncelleme ASLA kabul edilmez
[ReleaseManager] Check error: SocketException: Bağlantı yok
00:00 +15: All tests passed!
```

### B. İstemci Regresyon ve Routing Testleri (Toplu: 41/41 PASS)
Komut: `flutter test test/core_next/sync_v4_outbox_adapter_test.dart test/core_next/database_routing_test.dart test/unit/sync_v4/order_and_sale_materializer_regression_test.dart test/unit/update_v2/staged_release_targeting_test.dart`
- `sync_v4_outbox_adapter_test.dart`: 12 test PASS
- `database_routing_test.dart`: 11 test PASS
- `order_and_sale_materializer_regression_test.dart`: 3 test PASS
- `staged_release_targeting_test.dart`: 15 test PASS
- **Sonuç: 41/41 test başarıyla tamamlandı (0 hata).**

### C. Statik Kod Analizi
Komut: `flutter analyze lib/main.dart test/unit/update_v2/staged_release_targeting_test.dart`
```text
Analyzing 2 items...                                            
No issues found! (ran in 13.6s)
```

### D. Sunucu TypeScript Derleme Denetimi
Komut: `npx tsc --noEmit`
```text
Exit code: 0
Stdout: (Clean)
Stderr: (Clean)
```

### E. Sunucu Bağımsız Sözleşme ve Güvenlik Testleri
1. **İmza Sözleşmesi Testi (`npx ts-node src/test/release_signing_contract.test.ts`):**
   ```text
   Release signing contract: PASS
   ```
2. **Yayın Manifesti Testi (`npx ts-node src/test/manifest_contract.test.ts`):**
   ```text
   ✅ Test 1 Passed: Valid Release Manifest DTO validation
   ✅ Test 2 Passed: Invalid schemaVersion correctly rejected
   ✅ Test 3 Passed: Invalid SHA256 format correctly rejected
   ✅ Test 4 Passed: Valid Bootstrapper Manifest DTO validation
   ✅ Test 5 Passed: Valid Telemetry Event DTO validation
   🎉 ALL SERVER MANIFEST CONTRACT TESTS PASSED SUCCESSFULY!
   ```
3. **Güvenlik Politikası Testi (`npx ts-node src/test/security_policy.test.ts`):**
   ```text
   ✅ Security policy regression tests passed.
   ```
4. **Veritabanı Koruma Kilidi Testi (`npx ts-node src/test/test_db_guard.test.ts`):**
   *(Not: Bu test genel testlerin yerine değil, sadece canlı/geliştirme DB'lerine test erişimini önleyen kalkanın bağımsız testidir)*
   ```text
   🎉 14 ZORUNLU SENARYO TAMAMLANDI: 47/47 BAŞARILI
   (Canlı 'nutopiano' ve üretim veritabanı kilitleri adli olarak doğrulandı)
   ```

---

## 5. CANLIYA GEÇİŞ İÇİN KALAN ENGELLER

Kademeli yayın altyapısı izole ortamda tamamen kanıtlanmış ve güvenli hale getirilmiş olsa da, aşağıdaki adımlar tamamlanmadan **CANLIYA GEÇİŞ ONAYI VERİLEMEZ**:

1. **Canlı Yayın Yapılmadı (Kesin Yasak):** Kodlar entegre edilmiş ancak VPS veya canlı PostgreSQL ortamına aktarılmamış, yeni sürüm oluşturulmamış veya yayınlanmamıştır.
2. **Erkul Çeyiz Veri Güvenliği Denetimi Eksik:**
   - Erkul Çeyiz'in PostgreSQL veritabanında bulunan geçmiş sipariş, cari hesap ve taksitli satış kayıtlarının yeni `core_next` modeline veri kaybı olmadan aktarımı bağımsız olarak tamamlanmamıştır.
   - Bu nedenle Erkul Çeyiz hiçbir pilot veya erken dağıtım hedefi içerisine **ALINAMAZ**.
3. **Nutopia SQLite Geçiş Provası:** Canlı `serenut_pos.db` dosyasının taşınması işlemi henüz canlı ortamda tetiklenmemiştir.
4. **Feature Flag:** `coreNextSalesEngineEnabledProvider = false` durumu aynen muhafaza edilmektedir.

---

## 6. SONUÇ

Stage 10.12.8 bağımsız denetimi başarıyla tamamlanmıştır. Yapılan denetimde tespit edilen yetkilendirme açığı (untrusted query param spoofing) fail-closed ve kriptografik JWT doğrulaması ile tamamen kapatılmıştır. Sistem, seçili bir pilot şirkete (Nutopia gibi) güvenli güncelleme verebilecek, hedeflenmeyen şirketleri (Erkul Çeyiz gibi) ise hem API kontrolünde hem doğrudan indirmede kesin olarak dışarıda tutabilecek yetkinliktedir. Canlı yayın yapılmamıştır.
