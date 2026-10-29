# Mimari Yapılacaklar Listesi

Kaynak: 2026-10-28 oturumu (`architecture_guard` ölçümleri + sync hatası analizi). Bir madde bitince işaretleyin.

## P0 — Hemen
- [x] `backend-ci` neden kırık bul ve düzelt; `deploy.yml` içindeki `continue-on-error: true` bayrağını kaldır.
- [x] Şema sözleşmesi: sync edilen varlıklar için tek kaynak (nullable/default). CI testi PostgreSQL ve SQLite şemasını bu sözleşmeye karşı doğrulasın. (Neden: `sales.customer_id` NOT NULL hatası.) — `shared/schema_contract.json` tek kaynak oluşturuldu; istemcide `test/schema_contract_test.dart`, backend'de `server/src/test/schema_contract.test.ts` entegre edildi. `db_schema.dart` ve `sync_v4_service_materializer.dart` tam uyumlu hale getirildi.
- [x] Geçiş envanteri: hangi tablolar CoreNext katmanından, hangileri eski `db_schema.dart` katmanından çalışıyor; kalan işi çıkar. — Detaylı tablo/repo eşleşme envanteri ve kalan 5 iş paketi `docs/core_next_transition_inventory.md` dokümanına çıkarıldı.

## P1 — Sonraki sürümler
- [ ] Para alanlarını kuruş (`*_minor` int) olarak bitir; `REAL`/`double` para alanlarını kaldır (guard: 43 kolon / 253 alan).
- [ ] Tek bakiye servisi; 9 kopya bakiye formülünü birleştir (`architecture_guard`: 9'dan 7'ye düşürüldü, `sqlite_customer_repository.dart` ve `database_provider.dart` doğrudan `DatabaseSchema.createViews` / `v_financial_ledger` kullanımına bağlandı).
- [ ] Sunucuda doğrudan `pg pool` kullanımını (115 yer) tek veri erişim katmanına (tenant/RLS bağlamı zorunlu) topla.
- [x] Sync'te hatalı bir değişiklik tüm pull döngüsünü kilitlememeli (dead-letter / karantina) — `_applyChangeBatchWithQuarantine` ve `sync_quarantine_v4` ile uygulandı.

## P2 — Zamanla
- [ ] UI'dan doğrudan repository/servis çağrılarını (64) provider/controller üzerinden geçir.
- [x] Boş `catch` blokları (31 Dart, 4 TS) en azından loglasın; outbox ekleme `catch (_)` yutmasını da düzelt. — Dart'ta 31 ve TS'de 2 boş catch tespit edilip tümü debugPrint/logger ile yapılandırılmış loglamaya geçirildi; outbox mutation kayıtları loglama korumasına alındı; `architecture_guard` baseline değeri 0'a kilitlendi.
- [ ] `DateTime.now()` (503) yerine `Clock` arayüzü.
- [ ] Uzun dosyalar (49) böl.

## Araştırmadan eklenenler
Denetim kodu okuyarak yapıldı, hiçbir şey çalıştırılmadı.

### Yüksek
- [x] **Zehirli değişiklik tüm pull'u kilitliyor.** `sync_v4_service_orchestration.dart:226-246` her 200'lük sayfayı tek transaction'da uyguluyordu. `_applyChangeBatchWithQuarantine` fallback satır satır çalıştırma ve `sync_quarantine_v4` karantina tablosuna aktarım ile cursor ilerletilmesi sağlandı.
- [x] **Bilinmeyen varlık tipleri sessizce siliniyor.** `sync_v4_service_materializer.dart:30-43` `_ => null` sonrası sessiz dönüş yerine `sync_quarantine_v4` tablosuna `unknown_entity_type` olarak kaydedilip loglanması sağlandı.
- [x] **Fındık/depo verisi sync olmuyor (doğrulandı).** `schema_v103.sql`, `schema_v104.sql`, `schema_v106.sql` (is_deleted/deleted_at) + `sync-v4.materializer.ts` (upsertWarehouse, upsertCustomerHazelnutEscrow, upsertWarehouseHazelnutMovement, upsertHazelnutPriceCut) + istemci `sync_v4_service_materializer.dart` ve `sqlite_hazelnut_repository.dart` SyncOutboxV4 entegrasyonu tamamlandı.
- [x] **Üretim sırları.** `server/scripts/deploy_production.sh` içinde `.env` yoksa fail-closed durdurulması ve bilinen template sırlarının engellenmesi sağlandı; `uat-qa-simulation.ts` içindeki `fallback_secret` kaldırıldı.

### Orta
- [x] **FK/NOT NULL yaması parça parça.** `sync_v4_service_materializer.dart` içinde `product` varlıkları için `name`, `category`, `price`, `quantity` alanlarına `shared/schema_contract.json` uyumlu güvenli varsayılanlar bağlandı; FK kısıtı olan silmelerde `is_active` soft-deactivation koruması eklendi; stub ürün eklemede minor kuruş ve kategori tutarlılığı sağlandı.
- [x] **Materializer'da para hassasiyeti.** Dual-write mekanizmasında `*_minor` kuruş alanları doğrudan gelen kaynaktan integer olarak taşınacak şekilde güncellendi; eksik olduğunda kuruş dönüştürme hassasiyetle sağlandı.
- [ ] **Test boşlukları.** Eksik: zehirli sayfa/rollback, bilinmeyen tip, DELETE/tombstone, refund materialization, null'lu taksit payload'ı, cursor takılması, istemci-sunucu ortak fixture/contract testi.

### Düşük/Orta
- [ ] **Migration.** `server/db` altında 99+ `schema_vN.sql`. Uygulanmış dosyalar değişmez kuralı CI'da zorunlu olsun (checksum kaymasını önler). Checksum kodu incelenmedi.
- [ ] Test/doğrulama scriptlerinde `rejectUnauthorized:false` (prod dışı, düşük risk).


## İkinci tur (güvenilirlik ve depo hijyeni)
Sınırlı grep taraması; derin kod okuması yapılmadı. (V) = grep/dosya okumasıyla doğrulandı, (T) = tahmin, elle doğrulanmalı.

### Yüksek
- [x] **Sunucuda graceful shutdown yok (V).** `server.ts:828-853` içinde SIGTERM ve SIGINT dinleyicileriyle HTTP sunucu (`server.close`), BullMQ worker'ları (`stopNotificationWorker`, `stopBillingScheduler`), Redis (`redisClient.quit`) ve PG bağlantı havuzu (`pgPool.end`) sıralı ve güvenli şekilde boşaltılarak kapatılmaktadır.
- [x] **SQLite upgrade başarısız olursa kurtarma yolu yok (kısmen V).** `CoreAppDatabase.open` içine pre-upgrade güvenli yedekleme (`.pre_upgrade_vX.bak`) eklendi; migration veya şema açılışında hata olursa veritabanı bozulmadan otomatik olarak eski sürüme geri yüklenir.
- [x] **Günlük kullanımda yedek/bütünlük kontrolü yok (V).** `main.dart` başlangıcında `runStartupDiagnostics` ile `PRAGMA integrity_check` ve FK kontrolü zorunludur; ayrıca gün boyu açık kalan terminal/desktop kullanımında `_autoBackupTimer` (4 saatte bir) ve `autoBackupIfNeeded()` ile VACUUM INTO tabanlı doğrulanmış atomik günlük yedekleme devreye alınmıştır.
- [x] **CI boşlukları (V).** `.github/workflows/deploy.yml` içine `npm run test:schema-contract`, `test/schema_contract_test.dart`, `test/database/database_provider_concurrency_test.dart` ve `test/services/integrity_check_service_test.dart` eklendi. `.github/workflows/sync-hotfix.yml` içine deploy öncesinde `npm run test:release-signing` ve `npm run test:schema-contract` zorunlu kılındı.
- [ ] **Refresh token (kısmen V).** `auth.controller.ts:124-153` sadece token'ın varlığını kontrol ediyor. `AuthService.refresh` içinde hash saklama, rotasyon ve eski token tekrar kullanılınca tüm ailenin iptali var mı, elle okunmalı.

### Orta
- [ ] Rate limit var (V, `rate-limit.middleware.ts`, Redis). Redis kapalıyken güvenli mi (T), global limiter ve body-size limiti doğrulanmadı.
- [x] **`/health`, `/ready`, `/live` probları (V).** `server.ts:750-825` incelendi ve doğrulandı: `/health` DB bağlantısını (`pgPool.query('SELECT 1')`) ve Redis durumunu aktif kontrol eder; DB kapalıysa 503 Service Unavailable döner. Ayrıca Kubernetes/Docker uyumlu `/ready` (DB+Redis readiness) ve `/live` (liveness) probları mevcuttur.
- [ ] Multi-tenant `company_id` taraması yapılmadı: `company_id`'siz SELECT/UPDATE/DELETE'leri grep'le; sync pull için `(company_id, seq/cursor)` indeksini doğrula.

### Depo hijyeni
- [x] **CRLF/LF karışık (V).** `.gitattributes` kök dizine eklendi (`* text=auto eol=lf`), tüm depo normalize edildi.
- [ ] **Deprecation'lar (V sayılar).** 7 `withOpacity`, 22 Radio/RadioListTile (RadioGroup'a geçiş), 22 `DropdownButtonFormField` `value` → `initialValue`. Bir kısmı zaten geçmiş olabilir.
- [ ] **`lib/core_next` bir Windows junction'ı (V)** (`core_next/client_core/lib`). Junction takip etmeyen araçlar kaçırır, temiz klonda/CI'da kırılabilir.
- [x] **Depo kök dizini kalıntıları (V).** Kökteki tüm `STAGE_10_12_*.md` raporları ve `START_COMMANDS.sh` `docs/archive/` dizinine taşındı; `win.exe` ve `telemetry_logs.jsonl` `.gitignore` ile korunmaktadır.
- [ ] TODO/FIXME/HACK sayımı güvenilir değil (ilk grep yanlış eşleşti); yeniden say.

### İncelenmedi
OTA geri alma, lisans/entitlement uç durumları, istemci crash/telemetri kapsamı, offline davranış, DB indeksleri.

## Üçüncü tur (güvenlik ve sync derin denetim)
Kod okunarak yapıldı. (V) = okuyarak doğrulandı, (T) = grep/tahmin. Aşağıdaki "Yüksek" maddeler P0 sayılmalı.

### Yüksek (P0)
- [x] **OTA imzasız dosya kuruyor (V).** `update_dialog.dart` `sha256Hash == null` veya `signature == null` ise fail-closed güvenlik bariyeri devreye girer, indirilen dosya diskten silinir ve kurulum tamamen engellenir. Unit & Widget testleri yazıldı ve doğrulandı.
- [x] **JWT herhangi bir host'a gidebiliyor (V).** `release_manager_service.dart:downloadUpdate` metodu güncellendi: Bearer token sadece API host'una (white-list) gönderilir; harici sunuculara token sızdırılması önlendi. Prod ortamında HTTPS zorunlu kılındı.
- [x] **OTA sürüm/platform bağlama ve Downgrade Koruması (V).** İstemci tarafında `ReleaseManagerService.checkForUpdates` ve `VersionChecker.isVersionOlder` ile fail-closed downgrade engeli uygulandı; sunucu kurulu sürümden daha eski veya eşit bir sürüm sunarsa güncelleme otomatik olarak engellenip `noUpdate` olarak düşürülür. Unit testleri ile doğrulandı.
- [x] **Windows kurulumunda geri alma ve TOCTOU savunması (V).** `ReleaseManagerService.installUpdate` dosya çalıştırma öncesinde derhal SHA-256 bütünlüğünü doğrular (TOCTOU koruması); `serenut_update_runner.bat` hata kodu (`%ERRORLEVEL% NEQ 0`) aldığında hatayı loglayıp mevcut çalışan uygulamayı tekrar başlatarak sistemin kilitlenmesini engeller.
- [x] **`sync_v4_changes` ve `sync_v4_entities` tablolarında RLS yok (V).** `schema_v105.sql` ile `ENABLE ROW LEVEL SECURITY` ve `FORCE ROW LEVEL SECURITY` politikaları uygulandı; `/pull` ve `bootstrap/license-config` doğrudan pgPool yerine tenant-bağlamlı `client` üzerinden geçirildi.
- [ ] **RLS bypass çok geniş (V).** `auth.middleware.ts:30` `bypassRls: isSysadmin` ile tüm istek için RLS atlanıyor; ~40 handler `SET LOCAL app.bypass_rls='true'` yapıyor (admin 13, billing 4, auth 8 ...). Bu sıradan bir GUC olduğundan herhangi bir SQL injection bunu açabilir. → Admin için ayrı BYPASSRLS DB rolü, GUC bypass'ı kaldır.

### Orta
- [x] **Refresh yarışı ve token güvenliği (V).** `auth.service.ts` içinde oturum yenileme sorgusuna `FOR UPDATE` satır kilidi eklendi; aynı refresh token ile yapılan paralel isteklerde çift oturum oluşması engellendi.
- [x] **Giriş zamanlaması ve JWT algoritma sabitlemesi (V).** `auth.service.ts` içinde kullanıcı bulunamadığında `DUMMY_BCRYPT_HASH` karşılaştırması çalıştırılarak kullanıcı varlığı/yokluğu arasındaki yanıt süresi farkı (timing attack / account enumeration) eşitlendi; `jwt.verify` içinde `algorithms: ['HS256']` sabitlendi.
- [x] **Offline lisans atlatılabiliyor (V).** `LicenseService` içine 14 günlük maksimum çevrimdışı toleransı (`maxOfflineDays = 14`) ve `last_heartbeat_success` filigranı entegre edildi; aktivasyon ve başarılı heartbeat anında mühürlenir. 14 günden uzun süre sunucu ile iletişim kurmayan istemcilerde `offline_expired` devreye girerek heartbeat yenilemesi zorunlu kılınır. SQLite operasyonel tablolarındaki (`sales`, `orders`, `financial_transactions`) `MAX(created_at)` veritabanı filigranı ile saat geri alma girişimleri engellenmiştir.
- [x] **Güç kesintisinde satış kaybı (V).** `database_provider.dart` ve `CoreAppDatabase` içinde WAL modunda `PRAGMA synchronous = FULL` devreye alındı. Ani elektrik kesintilerinde fsync garantisi sağlanarak kasiyerin onayladığı satış ve outbox kayıtlarının disk tamponunda kaybolması önlendi.
- [x] **Çökme sonrası outbox sıfırlanıyor (V).** `CrashRecoveryManager.recoverInterruptedSyncJobs` güncellendi: FAILED kayıtları PENDING'e çekerek sonsuz deneme üreten zehirli döngü kaldırıldı; attempts >= 5 olan satırlar doğrudan DEAD_LETTER durumuna alınarak izole edilir; sadece elektrik kesintisinde `SENDING` aşamasında kalan işler attempts sayacı korunarak PENDING'e çekilir. Global hata yakalama ise `ErrorBoundary.install()` ile tüm Flutter, Async Zone ve Isolate hataları için telemetri ve Sentry'ye bağlıdır.
- [x] **Güncelleme telemetrisi yanlış (V).** `update_state_machine.dart` içindeki sabit `'1.1.9+21'` ve `'1.2.0+22'` kaldırılarak `VersionChecker.currentVersion` ve dinamik `context.manifest.version` bağlandı.

### Düşük / not
- [x] **Push rotasının `requireActiveEntitlement` muafiyeti (V).** `sync-v4.routes.ts:80-87` bilinçli mimari karardır ve belgelenmiştir: Lisans süresi dolsa dahi istemcide çevrimdışı birikmiş yerel işlemlerin (satış, tahsilat, kasa) veri kaybı yaşanmadan buluta aktarılabilmesi için `/push` uç noktası `authenticateUser` + device check zorunluluğu altında muaf tutulmuştur. Pull ve diğer rotalar ise `requireActiveEntitlement` ile korunur.
- [x] **`idx_sync_v4_changes_pull` (`schema_v52:15`) gereksiz indeks.** `schema_v107.sql` ile `DROP INDEX IF EXISTS idx_sync_v4_changes_pull` uygulandı. `PRIMARY KEY (tenant_id, revision)` zaten aynı b-tree indeksine sahiptir; gereksiz disk ve yazma yükü kaldırıldı.
- [x] **Sync pull sırası ve revision commit kilidi (V).** `sync-v4.routes.ts:135` içine kiracı düzeyinde `SELECT pg_advisory_xact_lock(hashtext($1), hashtext('tenant-push-order'))` eklendi. Aynı kiracıya ait eşzamanlı push işlemlerinin commit sıralaması mutlak ardışık garantiye alınarak ara revision boşluğu (commit gap / out-of-order pull cursor) oluşması engellendi.
- [x] **Doğru çalışan mekanizmalar doğrulandı (V).** Push idempotency (`UNIQUE(tenant_id,mutation_id)` ve istemcide `UNIQUE(idempotency_key)`), cihaz limiti denetimi (`FOR UPDATE`, `license.service.ts:120, 265-290`) incelendi ve güvenli çalıştığı doğrulandı.
- [ ] İncelenmedi: `logical_clock` saat kayması mantığı; `admin.controller.ts` (2943 satır), raporlar ve portal uçlarında `company_id` kontrolü.
