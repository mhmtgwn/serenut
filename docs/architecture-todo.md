# Mimari Yapılacaklar Listesi

Kaynak: 2026-10-28 oturumu (`architecture_guard` ölçümleri + sync hatası analizi). Bir madde bitince işaretleyin.

## P0 — Hemen
- [ ] `backend-ci` neden kırık bul ve düzelt; `deploy.yml` içindeki `continue-on-error: true` bayrağını kaldır.
- [ ] Şema sözleşmesi: sync edilen varlıklar için tek kaynak (nullable/default). CI testi PostgreSQL ve SQLite şemasını bu sözleşmeye karşı doğrulasın. (Neden: `sales.customer_id` NOT NULL hatası.)
- [ ] Geçiş envanteri: hangi tablolar CoreNext katmanından, hangileri eski `db_schema.dart` katmanından çalışıyor; kalan işi çıkar.

## P1 — Sonraki sürümler
- [ ] Para alanlarını kuruş (`*_minor` int) olarak bitir; `REAL`/`double` para alanlarını kaldır (guard: 43 kolon / 253 alan).
- [ ] Tek bakiye servisi; 9 kopya bakiye formülünü birleştir.
- [ ] Sunucuda doğrudan `pg pool` kullanımını (115 yer) tek veri erişim katmanına (tenant/RLS bağlamı zorunlu) topla.
- [ ] Sync'te hatalı bir değişiklik tüm pull döngüsünü kilitlememeli (dead-letter / karantina) — araştırma sonucuna göre.

## P2 — Zamanla
- [ ] UI'dan doğrudan repository/servis çağrılarını (64) provider/controller üzerinden geçir.
- [ ] Boş `catch` blokları (31 Dart, 4 TS) en azından loglasın; outbox ekleme `catch (_)` yutmasını da düzelt.
- [ ] `DateTime.now()` (503) yerine `Clock` arayüzü.
- [ ] Uzun dosyalar (49) böl.

## Araştırmadan eklenenler
Denetim kodu okuyarak yapıldı, hiçbir şey çalıştırılmadı.

### Yüksek
- [ ] **Zehirli değişiklik tüm pull'u kilitliyor.** `sync_v4_service_orchestration.dart:226-246` her 200'lük sayfayı tek transaction'da uyguluyor; `_apply` hata fırlatınca sayfa ve cursor geri alınıyor, aynı sayfa sonsuza dek tekrar çekiliyor. Pull tarafında atlama/karantina/dead-letter yok (DEAD_LETTER sadece push'ta, l.140). Bootstrap yolu (l.190-205) aynı sorunda. `refund_sale_missing`, `invalid_refund_quantity`, `unsupported_system_reset_scope` kalıcı hatalar. → Hatalı değişikliği karantinaya alıp cursor'ı ilerlet, telemetriye yaz.
- [ ] **Bilinmeyen varlık tipleri sessizce siliniyor.** `sync_v4_service_materializer.dart:30-43` `_ => null` sonrası `return`; cursor ilerliyor, değişiklik kalıcı kayboluyor, log/sayaç yok. Eski uygulama yeni tipleri kaybeder, güncelleme sonrası tekrar oynatılmaz. `gib_invoice` sunucuda var (`materializer.ts:226`). → Logla/karantinaya al, cursor'ı ilerletme politikasını belirle.
- [ ] **Fındık/depo verisi sync olmuyor (doğrulandı).** Warehouse, escrow, hareket ve fiyat kesim tabloları yalnızca yerel (`db_schema.dart`, `sqlite_hazelnut_repository.dart`); sunucuda ve sync_v4'te hiç yok. Yedek ve çoklu cihaz yakınsaması yok. Sadece `financial_transaction`/`cash_expense` yan etkileri sync oluyor ve diğer cihazlarda olmayan depo/emanet bağlamına işaret edebilir. → Sunucu şeması + entity map + materializer ekle (veya kapsam dışı olduğunu açıkça belgele).
- [ ] **Üretim sırları.** `server/scripts/deploy_production.sh:130-135` (staging l.135) `.env` yoksa sabit DB parolası, `JWT_SECRET` ve REFRESH_SECRET yazıyor; 32+ karakter olduğu için `auth.service.ts:18` kontrolü geçiyor ama değerler herkesçe biliniyor. → Script hata verip dursun; `uat-qa-simulation.ts:73` `fallback_secret` kaldırılsın. Not: bu değerler repoda göründüğü için kullanılmış olabilirler, prod'daki gerçek sırların farklı olduğunu doğrula, değilse döndür.

### Orta
- [ ] **FK/NOT NULL yaması parça parça.** Sadece `order_number` ve `customer_id` düzeltiliyor. Diğer `null` değerler (name, price, quantity, category) olduğu gibi yazılıyor (`materializer.dart:406-407`). `DELETE` is_deleted olmayan tipte sert silme yapıyor ve FK ile patlar. Stub ürün/müşteri sahte değerle ekleniyor. `schema_v*.sql` ile `db_schema.dart` kolon kolon karşılaştırılmadı → şema sözleşmesi işinin parçası.
- [ ] **Materializer'da para hassasiyeti.** `_minor` değerleri `(val*100).round()` ile double'dan türetiliyor (`materializer.dart:429, 252-255`); iade tutarları da double + `toStringAsFixed` (l.322, 332).
- [ ] **Test boşlukları.** Eksik: zehirli sayfa/rollback, bilinmeyen tip, DELETE/tombstone, refund materialization, null'lu taksit payload'ı, cursor takılması, istemci-sunucu ortak fixture/contract testi.

### Düşük/Orta
- [ ] **Migration.** `server/db` altında 99+ `schema_vN.sql`. Uygulanmış dosyalar değişmez kuralı CI'da zorunlu olsun (checksum kaymasını önler). Checksum kodu incelenmedi.
- [ ] Test/doğrulama scriptlerinde `rejectUnauthorized:false` (prod dışı, düşük risk).


## İkinci tur (güvenilirlik ve depo hijyeni)
Sınırlı grep taraması; derin kod okuması yapılmadı. (V) = grep/dosya okumasıyla doğrulandı, (T) = tahmin, elle doğrulanmalı.

### Yüksek
- [ ] **Sunucuda graceful shutdown yok (V).** `server/src` içinde SIGTERM/SIGINT/`server.close`/`pool.end` sadece test ve scriptlerde. Deploy sırasında süren sync push'lar kesilir, PG bağlantıları açık kalır. → SIGTERM'de HTTP, worker, WebSocket ve pool'u boşalt.
- [ ] **SQLite upgrade başarısız olursa kurtarma yolu yok (kısmen V).** `core_next/.../app_database.dart:89` migrate'i doğrudan `onUpgrade`'den çağırıyor; yükseltme öncesi dosya kopyası ve try/catch görmedim. `onOpen` eski tablo varsa `IncompatibleDatabaseSchemaException` fırlatıyor, UI fallback görmedim (T). → Yükseltme öncesi `.bak` kopyası, hata olursa geri yükle, kurtarma ekranı göster.
- [ ] **Günlük kullanımda yedek/bütünlük kontrolü yok (V).** `PRAGMA integrity_check` ~10 yerde ama hepsi migration/cutover kapısında. Normal açılışta kontrol ve zamanlanmış yerel yedek yok.
- [ ] **CI boşlukları (V).** `deploy.yml:99` `flutter analyze --no-fatal-infos --no-fatal-warnings`: uyarılar build'i hiç düşürmüyor, deprecation'lar böyle birikiyor. `sync-hotfix.yml` testsiz, sadece `npm run build`. PR'larda CI çalışıyor mu bilinmiyor (T).
- [ ] **Refresh token (kısmen V).** `auth.controller.ts:124-153` sadece token'ın varlığını kontrol ediyor. `AuthService.refresh` içinde hash saklama, rotasyon ve eski token tekrar kullanılınca tüm ailenin iptali var mı, elle okunmalı.

### Orta
- [ ] Rate limit var (V, `rate-limit.middleware.ts`, Redis). Redis kapalıyken güvenli mi (T), global limiter ve body-size limiti doğrulanmadı.
- [ ] `/health` var (V) ama DB/Redis kontrol ediyor mu bilinmiyor; sadece 200 dönüyorsa readiness değil.
- [ ] Multi-tenant `company_id` taraması yapılmadı: `company_id`'siz SELECT/UPDATE/DELETE'leri grep'le; sync pull için `(company_id, seq/cursor)` indeksini doğrula.

### Depo hijyeni
- [ ] **CRLF/LF karışık (V).** 574 dosyanın 327'si CRLF, 247'si LF; `.gitattributes` yok. → `* text=auto eol=lf` ekle, tek commit'te normalize et. (Bugün bazı dosyaları LF'ye çevirdim; git CRLF uyarısı veriyor, bu işle birlikte düzelir.)
- [ ] **Deprecation'lar (V sayılar).** 7 `withOpacity`, 22 Radio/RadioListTile (RadioGroup'a geçiş), 22 `DropdownButtonFormField` `value` → `initialValue`. Bir kısmı zaten geçmiş olabilir.
- [ ] **`lib/core_next` bir Windows junction'ı (V)** (`core_next/client_core/lib`). Junction takip etmeyen araçlar kaçırır, temiz klonda/CI'da kırılabilir.
- [ ] Kökte ~100 `STAGE_10_12_*.md` raporu, `win.exe` (9MB), `telemetry_logs.jsonl`, `START_COMMANDS.sh` var; git'te takipli mi bakılmadı (T). → raporları `docs/archive`'e taşı, gerisini `.gitignore`'a ekle.
- [ ] TODO/FIXME/HACK sayımı güvenilir değil (ilk grep yanlış eşleşti); yeniden say.

### İncelenmedi
OTA geri alma, lisans/entitlement uç durumları, istemci crash/telemetri kapsamı, offline davranış, DB indeksleri.

## Üçüncü tur (güvenlik ve sync derin denetim)
Kod okunarak yapıldı. (V) = okuyarak doğrulandı, (T) = grep/tahmin. Aşağıdaki "Yüksek" maddeler P0 sayılmalı.

### Yüksek (P0)
- [ ] **OTA imzasız dosya kuruyor (V).** `update_dialog.dart:183-190` `sha256Hash == null` ise `verified = true` yapıyor; hash'siz manifest ile imzasız APK/EXE kurulur. → Hash veya imza yoksa kurulumu reddet (fail closed).
- [ ] **JWT herhangi bir host'a gidebiliyor (V).** `release_manager_service.dart:308-324` `downloadUrl` "http" ile başlıyorsa olduğu gibi kullanıyor, :322'de Bearer ekliyor; https/host allowlist yok. Sahte manifest ile token ve cihaz kimliği saldırgana gider. → https ve API host'u zorunlu; diğer host'lara token gönderme.
- [ ] **OTA imzası sürümü/platformu/URL'yi bağlamıyor (V).** `release-signing.ts:117-125`, istemci :432 sadece sha256 hex'ini imzalıyor. Eski imzalı bir sürüm "en yeni" diye sunulursa downgrade geçer; istemcide minimum sürüm kontrolü bulamadım (T). → `sha256|platform|version+build` imzala, kurulu sürüm ve altını reddet.
- [ ] **Windows kurulumunda gerçek geri alma yok (V).** `release_manager_service.dart:484-502` .bat ile `/SILENT` kurup `exit(0)`; installer çıkış kodu kontrol edilmiyor. `triggerRollback` (`update_dialog.dart:225`) sadece installer başlatılamazsa çalışıyor. Dosya doğrulama ile kurulum arasında kullanıcı yazılabilir temp'te duruyor (TOCTOU), Authenticode kontrol edilmiyor. → Korumalı dizine kopyala, kurulumdan hemen önce yeniden hash'le, çıkış kodunu kontrol et, sağlık işareti yoksa geri al.
- [ ] **`sync_v4_changes` ve `sync_v4_entities` tablolarında RLS yok (V).** İzolasyon yalnızca `tenant_id=$1` filtresine bağlı (`sync-v4.routes.ts:178, 200, 428, 478`); `/pull` (:425) `set_config` olmadan pgPool'da çalışıyor. → RLS politikası ekle, `/pull`'u tenant bağlamlı transaction'da çalıştır.
- [ ] **RLS bypass çok geniş (V).** `auth.middleware.ts:30` `bypassRls: isSysadmin` ile tüm istek için RLS atlanıyor; ~40 handler `SET LOCAL app.bypass_rls='true'` yapıyor (admin 13, billing 4, auth 8 ...). Bu sıradan bir GUC olduğundan herhangi bir SQL injection bunu açabilir. → Admin için ayrı BYPASSRLS DB rolü, GUC bypass'ı kaldır.

### Orta
- [ ] **Refresh yarışı ve düz metin token (V).** `auth.service.ts:299` `FOR UPDATE` yok; aynı token ile iki paralel refresh iki canlı oturum üretir. Tekrar kullanım tespiti (:414) 20 sn'lik tolerans (:312) sonrası tüm oturumları iptal ediyor; tolerans içinde eski token halefin düz metin refresh token'ını döndürüyor (:394). Refresh token'lar DB'de düz metin (`schema.sql:40`). → `FOR UPDATE`, SHA-256 hash sakla, toleransta tek kullanımlık yeniden verme.
- [ ] **Giriş zamanlaması ve hesap kilidi (V).** `auth.service.ts:98` kullanıcı yoksa hemen dönüyor (dummy bcrypt yok); `email=$1 OR username=$1` birden çok satır eşleştirebilir. Kilit sadece hesap bazlı (8 hatada 5 dk), saldırgan kurbanı kilitleyebilir. `jwt.verify` (:574) algoritmayı sabitlemiyor. bcrypt 12 ve HS256 uygun; access 15 dk, refresh 30 gün. → Dummy karşılaştırma, `algorithms: ['HS256']`, IP+hesap bazlı kilit.
- [ ] **Offline lisans atlatılabiliyor (V).** `license_service.dart:369-435, 496-521`: saat geri alma tespiti SharedPreferences ve düz `settings` satırında; prefs silinip satır düzenlenirse sıfırlanıyor, sonra `DateTime.now()` ile kontrol (:512). İmzalı token'da maksimum offline süre/heartbeat yok, offline iken `token_version` iptali kontrol edilmiyor; token `expiry_date`+7 gün geçerli. → Monoton filigranı OS güvenli depolamada tut, N günde bir sunucu heartbeat zorunlu kıl.
- [ ] **Güç kesintisinde satış kaybı (V).** `app_database.dart:72-73` WAL + `synchronous=NORMAL`; kasiyerin başarılı gördüğü son satışlar kaybolabilir. → Satış/outbox yazımlarında `synchronous=FULL`.
- [ ] **Çökme sonrası outbox sıfırlanıyor (V).** `crash_recovery_manager.dart:68-79` her çökme açılışında FAILED/PENDING (attempts>0) satırları PENDING/0 yapıyor; zehirli mutasyonlar sonsuza kadar tekrar kuyruğa girer, dead-letter geri alınır. Global hata yakalayıcı (`runZonedGuarded`, `FlutterError.onError`, `PlatformDispatcher.onError`) grep'te yok (T), yakalanmayan hatalar telemetriye gitmiyor olabilir. → Global handler ekle, dead-letter için ayrı durum kullan.
- [ ] **Güncelleme telemetrisi yanlış (V).** `update_state_machine.dart:146-147` `fromVersion '1.1.9+21'` ve toVersion yedeği '1.2.0+22' sabit; FSM muhtemelen dialog akışına bağlı değil (T).

### Düşük / not
- [ ] Push bilerek `requireActiveEntitlement` dışında (`:78`): süresi dolmuş kiracı sonsuza dek push edebilir. Bilinçli ise belgele.
- [ ] `idx_sync_v4_changes_pull` (`schema_v52:15`) gereksiz; PK (tenant_id,revision) yeterli.
- [ ] Sync pull sırası şu an güvenli (V): her push `pg_advisory_xact_lock` (`sync-v4.routes.ts:127`) alıyor, revision sırası commit sırasıyla aynı. Yeni bir yazar bu kilidi atlarsa bozulur; bunu kod yorumu/teste bağla.
- [ ] Doğru çalışanlar (V): push idempotency (UNIQUE(tenant_id,mutation_id), istemcide UNIQUE idempotency_key), cihaz limiti (`FOR UPDATE`, `license.service.ts:120, 265-290`).
- [ ] İncelenmedi: `logical_clock` saat kayması mantığı; `admin.controller.ts` (2943 satır), raporlar ve portal uçlarında `company_id` kontrolü.
