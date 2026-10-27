# SERENUT OS — STAGE 10.12.7 RAPORU
## KADEMELİ GÜNCELLEME ENTEGRASYONU VE GÜVENLİK DOĞRULAMASI
**Tarih:** 16 Ekim 2026  
**Durum:** TAMAMLANDI (İzole Testler ve Entegrasyon Başarılı — Canlı Yayın Kesinlikle Yapılmadı)

---

## 1. YÖNETİCİ ÖZETİ VE KRİTİK GÜVENLİK SORULARININ CEVAPLARI

> **Soru 1: Seçili şirkete güncelleme teknik olarak sınırlandırılabiliyor mu?**  
> **Cevap: EVET.** İstemci tarafında `main.dart` içerisindeki kontrol anonim/kör `/api/v1/updates/check` uç noktasından çıkarılıp kurumsal `ReleaseManagerService` (`/api/v1/releases/check`) altyapısına bağlanmıştır. Sunucu tarafında `release.controller.ts` fail-closed mantığıyla güçlendirilmiş, `update_targets` tablosunda şirket veya cihaz hedeflemesi olan yayınlar için geçerli JWT ve eşleşen hedef kimliği bulunmayan hiçbir istemciye güncelleme verilmemesi güvence altına alınmıştır. Hedef dışı veya yetkisiz istemciler doğrudan `hasUpdate: false` almakta, doğrudan indirme linkine erişmeye kalktıklarında ise sunucudan `HTTP 403 Forbidden` (`unauthorized_target`) ile engellenmektedir.

> **Soru 2: Hangi test kanıtları var?**  
> **Cevap:** Hazırlanan `test/unit/update_v2/staged_release_targeting_test.dart` süiti altındaki **11 senaryonun tamamı (11/11)** çalıştırılmış ve %100 başarıyla geçmiştir. Ayrıca `test/core_next/sync_v4_outbox_adapter_test.dart`, `test/core_next/database_routing_test.dart`, `test/unit/sync_v4/order_and_sale_materializer_regression_test.dart` ile birlikte toplam **37/37 izole test** ve sunucu tarafında `test_db_guard` ile **47/47 güvenlik testi** hatasız tamamlanmıştır.

> **Soru 3: Genel yayın yanlışlıkla tetiklenebilir mi?**  
> **Cevap: HAYIR.** `server/src/scripts/publish-release.ts` içerisindeki hardcoded `'stable'`, `%100` ve `active` yayın parametreleri kaldırılmıştır. Yeni yayınlar varsayılan olarak `channel: 'pilot'`, `rollout_percentage: 0` veya yalnızca açıkça belirlenen şirket hedefleri (`update_targets`) ile izole edilmektedir. Bir sürümün genel yayına (`channel: 'stable'`, `rollout: 100`) açılması için yetkili admin panelinden (`/api/v1/admin/releases/distribute`) ayrı, denetimli (audit loglanan) bir işlem yapılması zorunlu kılınmıştır.

> **Soru 4: Erkul Çeyiz ve Nutopia verileri korundu mu?**  
> **Cevap: KESİNLİKLE EVET.** Canlı `%APPDATA%\serenut_pos.db` dosyasına, Nutopia canlı veritabanına ve Erkul Çeyiz'in canlı bulut PostgreSQL veritabanına hiçbir sorgu, migration veya aktarım yapılmamıştır. `publish-release.ts` betiği canlı sunucuda çalıştırılmamıştır; Erkul Çeyiz hiçbir test veya pilot hedef listesine eklenmemiştir. `coreNextSalesEngineEnabledProvider = false` durumu korunmaktadır.

---

## 2. AŞAMA A — GIT VE GÜVENLİK DURUMU

- **Git HEAD:** `28c158d88028f139e93f78982d4651ad424c61d2`
- **Branch:** `main`
- **Önceki Düzeltmelerin Korunması:** Stage 10.12.6'da yapılan `sync_v4_service_materializer.dart` içerisindeki `unit_price_minor` sipariş/satış ayrımı ve 3/3 regresyon testi eksiksiz korunmuştur.
- **`git diff --check` Sonucu:** Temiz. Boşluk veya çakışma hatası yoktur.

---

## 3. DEĞİŞTİRİLEN DOSYALAR VE GEREKÇELERİ

| Dosya | Değişiklik Gerekçesi ve Kapsamı |
|---|---|
| `lib/main.dart` | Eski anonim `_checkVersion()` ve `_checkForLiveUpdate()` metodları kör `/api/v1/updates/check` çağrısından arındırıldı. Cihaz ID, şirket ID ve JWT token'ı alan `ReleaseManagerService.checkForUpdates()` kurumsal akışına bağlandı. Fail-closed: Hata veya hedef dışı olma durumunda yerel veritabanına ASLA dokunulmaz. |
| `server/src/modules/release/release.controller.ts` | 1) `/check` uç noktasında fail-open güvenlik açığı kapatıldı: Önceden `company_id` veya `device_id` göndermeyen istekler hedef filtresini atlayıp pilot sürümleri alabiliyordu; artık `target_count > 0` olan yayınlarda eşleşen kimlik yoksa sürüm kesinlikle atlanıyor (`fail-closed`). 2) İstemci beyanına güvenilmeyip gelen `Authorization: Bearer <jwt>` doğrulanarak şirket ID token içerisinden teyit ediliyor. 3) `/download/:releaseId` uç noktasına `update_targets` yetki kontrolü eklendi; yetkisiz şirket ve cihazlar `HTTP 403 unauthorized_target` ile engellendi. |
| `server/src/modules/update/update.controller.ts` | Eski `/api/v1/updates/check` uç noktasına `AND (SELECT COUNT(*) FROM update_targets ut WHERE ut.release_id = app_versions.id) = 0` filtresi konuldu. Böylece hedefli pilot yayınların eski istemciler tarafından yanlışlıkla keşfedilmesi ve çekilmesi engellendi. |
| `server/src/modules/admin/admin.controller.ts` | `/releases/distribute` uç noktasında eksik olan şirket hedeflemesi tamamlandı. Gelen `target_tenants` dizisi `update_targets` tablosuna `target_type = 'company'` olarak kaydedildi. |
| `server/src/scripts/publish-release.ts` | Otomatik `stable`, `%100` yayın davranışı engellendi. Ortam değişkenlerinden gelen `RELEASE_CHANNEL` (varsayılan: `'pilot'`) ve `RELEASE_TARGET_COMPANIES` desteği eklendi; oluşturulan sürümün doğrudan `update_targets` ile pilot hedefe kilitlenmesi sağlandı. |
| `test/unit/update_v2/staged_release_targeting_test.dart` | 11 zorunlu hedefleme ve güvenlik senaryosunu izole ortamda test eden kapsamlı test süiti oluşturuldu. |

---

## 4. İSTEMCİ → API → HEDEFLEME → PAKET İNDİRME GÜVENLİK AKIŞI

```
[Flutter İstemcisi (lib/main.dart)]
  │
  ├── 1. Cihaz ID, Şirket ID (Session/Storage) ve JWT Token alınır.
  │      (Kimlik yoksa hedefli güncelleme talebinde bulunulmaz)
  │
  ├── 2. GET /api/v1/releases/check?platform=windows&current_version=1.2.0&channel=pilot
  │      Headers: Authorization: Bearer <JWT>
  │      Headers: X-Device-ID: <device-id>
  │
  ▼
[Sunucu / Controller: release.controller.ts]
  │
  ├── 3. Token Doğrulama: JWT çözülür; payload.company_id ile sorgu parametresi şirket ID doğrulanır.
  │      (Uyuşmazlık veya sahte beyan varsa HTTP 401 Unauthorized döner)
  │
  ├── 4. Yayın & Hedef Filtresi:
  │      - Status = 'active' mi? (Değilse pasif sürüm gösterilmez)
  │      - Channel uygun mu? (Pilot kanalındaki sürüm stable isteyene verilmez)
  │      - Target Count > 0 ise:
  │          İstemcinin company_id veya device_id'si 'update_targets' tablosunda var mı?
  │          -> YOKSA: Fail-Closed (Sürüm atlanır, hasUpdate: false döner)
  │          -> VARSA: Rollout hash kontrolü yapılır (Cihaz rollout yüzdesi içinde mi?)
  │
  ▼
[Paket İndirme Aşaması: /api/v1/releases/download/:releaseId]
  │
  ├── 5. Doğrudan URL erişimi denense bile sunucu Authorization başlığını ve cihaz kimliğini denetler.
  │      Hedef dışı istekler HTTP 403 Forbidden ("unauthorized_target") ile reddedilir.
  │      Durdurulan/revoke edilen yayınlar HTTP 404 / 403 ile indirtilmez.
  │
  ▼
[İstemci Güncelleme Kararı]
  ├── Güncelleme başarılı teyit edilirse: İndirme ve doğrulama başlar.
  └── Hata / Kesinti / Hedef dışı: Mevcut yerel veritabanı aynen korunur, hiçbir reset veya yönlendirme yapılmaz.
```

---

## 5. İZOLE TEST KANITLARI (11 SENARYO)

Aşağıdaki çıktılar `flutter test test/unit/update_v2/staged_release_targeting_test.dart` komutunun gerçek terminal çıktısıdır:

```text
00:00 +0: loading test/unit/update_v2/staged_release_targeting_test.dart
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
00:00 +11: All tests passed!
```

### Regresyon Testleri Toplu Sonucu (37/37 Başarılı)
- `test/core_next/sync_v4_outbox_adapter_test.dart`: 12 test PASS
- `test/core_next/database_routing_test.dart`: 11 test PASS
- `test/unit/sync_v4/order_and_sale_materializer_regression_test.dart`: 3 test PASS
- `test/unit/update_v2/staged_release_targeting_test.dart`: 11 test PASS
- **Toplam: 37/37 test başarıyla geçti.**

### Sunucu TypeScript & Güvenlik Denetimi
- `npx tsc --noEmit`: 0 hata, başarıyla derlendi.
- `src/test/test_db_guard.test.ts`: 47/47 senaryo PASS (Canlı `nutopiano` ve üretim veritabanı kilitleri adli olarak doğrulandı).

---

## 6. CANLIYA GEÇİŞ İÇİN KALAN ENGELLER VE ERKUL ÇEYİZ VERİ GÜVENLİĞİ

1. **Canlıda Yayınlama Yapılmadı:** Kademeli yayın altyapısının kod ve test düzeyinde tamamlanmış olması, canlı sunucuya yayın açılması anlamına gelmez. Canlı ortamda yeni bir sürüm yayınlanmamıştır.
2. **Erkul Çeyiz Veri Güvenliği Kontrolleri:**
   - Erkul Çeyiz'in PostgreSQL üzerindeki sipariş, cari hesap, vadeli satış ve taksit kayıtlarının yeni şemaya tam uyumu henüz bağımsız canlı migrasyon onayından geçmemiştir.
   - Bu nedenle Erkul Çeyiz hiçbir güncellemenin hedef listesine alınamaz ve pilot olarak seçilemez.
3. **Core Next Feature Flag:** `coreNextSalesEngineEnabledProvider` istemcide kapalı tutulmaya devam etmektedir.

---
**Sonuç:** Stage 10.12.7 başarıyla tamamlanmıştır. Sistem hem istemci hem sunucu tarafında şirket ve cihaz bazlı kademeli güncellemeyi fail-closed kurallarla güvenli biçimde sınırlandırabilecek duruma getirilmiştir. Canlı yayın yapılmamıştır.
