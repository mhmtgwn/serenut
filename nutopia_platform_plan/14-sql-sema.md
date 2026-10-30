# 14 — Kanonik SQL Şeması (dbmate)

> **Bu belge veri modelinin tek gerçek kaynağıdır.** `03-veri-modeli.md` kavramsal özettir; çelişkide **14 geçerlidir**. Kararlar: `12-mimari-kilit-kararlar.md` (K2,K3,K17–K25).
> Biçim: her bölüm bir `dbmate` göç dosyasıdır (`db/migrations/<zaman>_<ad>.sql`, `-- migrate:up` / `-- migrate:down`). Aşağıda yalnız `up` gösterilir; `down` her dosyada ters sırada yazılır (üretimde destrüktif `down` çalıştırılmaz, yalnız geliştirme/staging).
> PostgreSQL 17. Sürümle ilgili doğrulama (Aşama 0): `uuidv7()` yerleşik değilse aşağıdaki işlev kullanılır.

## 0. Adlandırma ve kalıp kuralları
| Kural | Açıklama |
|---|---|
| Şema/tablo/sütun | `snake_case`, çoğul tablo adı, tekil sütun |
| Para | `bigint`, sütun adı `*_kurus`; para birimi olan tablolarda `currency char(3) NOT NULL DEFAULT 'TRY'` |
| Ağırlık | `integer`/`bigint`, sütun adı `*_g` |
| Oran | baz puan `*_bp` (10000 = %100) |
| Durum/tür alanları | `text` + `CHECK (... IN (...))` (enum **değil**; değer eklemek göçsüz/hafif) |
| Zaman | `timestamptz`; iş günü `date` (Europe/Istanbul); `created_at`, `updated_at` her tabloda |
| Birincil anahtar | `id uuid PRIMARY KEY DEFAULT core.uuidv7()` |
| Değişebilir topluluk | `version integer NOT NULL DEFAULT 1` (güncellemede tetikleyici artırır; uygulama `WHERE id=$1 AND version=$2`) |
| Değişmez tablolar | `core.forbid_mutation()` tetikleyicisi (UPDATE/DELETE yasak) |
| Yumuşak silme | yalnız katalog ve adres: `deleted_at`; sipariş/ödeme/tartı **silinmez** |
| PII | sütun yorumu `COMMENT ON COLUMN ... IS 'pii:phone'` (KVKK dışa aktarım/silme otomasyonu bunu okur) |
| Dış anahtar | Şema içinde FK serbest. **`mill.*` → `core.*` ve `payments.*` → herhangi bir şema FK yok** (yumuşak referans, bkz. 12 §4.2) |
| İndeks | Her FK için indeks; `status` + zaman bileşik indeksleri; kısmi indeks tercih edilir |

---

## 1. `0001_extensions_and_functions.sql`
```sql
-- migrate:up
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS shop;
CREATE SCHEMA IF NOT EXISTS mill;
CREATE SCHEMA IF NOT EXISTS payments;
CREATE SCHEMA IF NOT EXISTS ops;
CREATE SCHEMA IF NOT EXISTS reporting;

-- UUIDv7 (zaman sıralı). PG18+ yerleşik uuidv7() varsa bu işlev onu çağıracak şekilde değiştirilir.
CREATE OR REPLACE FUNCTION core.uuidv7() RETURNS uuid AS $$
DECLARE
  ts_ms bigint := (extract(epoch FROM clock_timestamp()) * 1000)::bigint;
  rnd   bytea  := gen_random_bytes(10);
  b     bytea;
BEGIN
  b := set_byte(set_byte(set_byte(set_byte(set_byte(set_byte(
         '\x00000000000000000000000000000000'::bytea,
         0, (ts_ms >> 40)::int & 255), 1, (ts_ms >> 32)::int & 255),
         2, (ts_ms >> 24)::int & 255), 3, (ts_ms >> 16)::int & 255),
         4, (ts_ms >> 8)::int & 255), 5, ts_ms::int & 255);
  b := overlay(b PLACING rnd FROM 7 FOR 10);
  b := set_byte(b, 6, (get_byte(b, 6) & 15) | 112);   -- sürüm 7
  b := set_byte(b, 8, (get_byte(b, 8) & 63) | 128);   -- varyant
  RETURN encode(b, 'hex')::uuid;
END $$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION core.set_updated_at() RETURNS trigger AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$ LANGUAGE plpgsql;

-- Optimistik kilit için sürüm artırma (uygulama WHERE version=$n ile kontrol eder)
CREATE OR REPLACE FUNCTION core.bump_version() RETURNS trigger AS $$
BEGIN NEW.version := OLD.version + 1; NEW.updated_at := now(); RETURN NEW; END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION core.forbid_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION '% tablosu değişmezdir (% yasak)', TG_TABLE_NAME, TG_OP USING ERRCODE = '42501';
END $$ LANGUAGE plpgsql;

-- Türkçe arama için değişmez (immutable) sarmalayıcı
CREATE OR REPLACE FUNCTION core.tr_unaccent(text) RETURNS text AS $$
  SELECT lower(unaccent('unaccent', $1));
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;

-- Telefonu E.164'e normalize eder (+90...), geçersizse NULL
CREATE OR REPLACE FUNCTION core.normalize_tr_phone(p text) RETURNS text AS $$
DECLARE d text := regexp_replace(coalesce(p,''), '\D', '', 'g');
BEGIN
  IF d ~ '^90[5][0-9]{9}$' THEN RETURN '+' || d;
  ELSIF d ~ '^0[5][0-9]{9}$' THEN RETURN '+9' || d;
  ELSIF d ~ '^[5][0-9]{9}$' THEN RETURN '+90' || d;
  ELSE RETURN NULL; END IF;
END $$ LANGUAGE plpgsql IMMUTABLE;

-- Boşluksuz belge numarası: aynı transaction içinde kilitli sayaç
CREATE TABLE core.doc_sequences (
  key         text   NOT NULL,            -- 'shop_order' | 'mill_request' | 'invoice' | 'receipt' | 'weighing_slip'
  period      integer NOT NULL,           -- yıl (2026) ya da 0 (süresiz)
  next_value  bigint NOT NULL DEFAULT 1,
  PRIMARY KEY (key, period)
);
CREATE OR REPLACE FUNCTION core.next_doc_number(p_key text, p_period integer) RETURNS bigint AS $$
DECLARE v bigint;
BEGIN
  INSERT INTO core.doc_sequences(key, period, next_value) VALUES (p_key, p_period, 2)
  ON CONFLICT (key, period) DO UPDATE SET next_value = core.doc_sequences.next_value + 1
  RETURNING next_value - 1 INTO v;
  RETURN v;        -- satır kilidi transaction sonuna kadar tutulur => boşluk olmaz (rollback sayacı da geri alır)
END $$ LANGUAGE plpgsql;
```

---

## 2. `0002_core.sql`
```sql
-- migrate:up

-- ── Müşteri kimliği ─────────────────────────────────────────────
CREATE TABLE core.customers (
  id                    uuid PRIMARY KEY DEFAULT core.uuidv7(),
  full_name             text,                                -- pii:name
  status                text NOT NULL DEFAULT 'active' CHECK (status IN ('active','blocked','anonymized')),
  customer_kind         text NOT NULL DEFAULT 'individual' CHECK (customer_kind IN ('individual','company')),
  company_name          text,                                -- pii:company
  tax_no                text,                                -- pii:tax (VKN/TCKN)
  tax_office            text,
  marketing_consent     boolean NOT NULL DEFAULT false,
  marketing_consent_at  timestamptz,
  preferred_channel     text NOT NULL DEFAULT 'sms' CHECK (preferred_channel IN ('sms','email','whatsapp')),
  notes_internal        text,
  anonymized_at         timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  version               integer NOT NULL DEFAULT 1
);
CREATE TRIGGER trg_customers_ver BEFORE UPDATE ON core.customers FOR EACH ROW EXECUTE FUNCTION core.bump_version();

CREATE TABLE core.customer_identities (
  id           uuid PRIMARY KEY DEFAULT core.uuidv7(),
  customer_id  uuid NOT NULL REFERENCES core.customers(id),
  kind         text NOT NULL CHECK (kind IN ('phone','email')),
  value        text NOT NULL,                                -- pii:contact ; phone: E.164, email: küçük harf
  verified_at  timestamptz,
  is_primary   boolean NOT NULL DEFAULT false,
  removed_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind = 'phone' AND value ~ '^\+90[5][0-9]{9}$') OR (kind = 'email' AND value = lower(value) AND position('@' in value) > 1))
);
-- Aynı telefon/e-posta aynı anda tek aktif müşteriye ait olabilir
CREATE UNIQUE INDEX uq_identity_active ON core.customer_identities(kind, value) WHERE removed_at IS NULL;
CREATE UNIQUE INDEX uq_identity_primary ON core.customer_identities(customer_id, kind) WHERE is_primary AND removed_at IS NULL;
CREATE INDEX ix_identity_customer ON core.customer_identities(customer_id);

CREATE TABLE core.customer_merge_log (
  id           uuid PRIMARY KEY DEFAULT core.uuidv7(),
  kept_id      uuid NOT NULL REFERENCES core.customers(id),
  merged_id    uuid NOT NULL REFERENCES core.customers(id),
  merged_by    uuid,                                          -- staff
  reason       text NOT NULL,
  snapshot     jsonb NOT NULL,                                -- birleşen müşterinin önceki hali
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_merge_log_immut BEFORE UPDATE OR DELETE ON core.customer_merge_log FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();

CREATE TABLE core.addresses (
  id                  uuid PRIMARY KEY DEFAULT core.uuidv7(),
  customer_id         uuid NOT NULL REFERENCES core.customers(id),
  kind                text NOT NULL DEFAULT 'shipping' CHECK (kind IN ('shipping','billing','pickup')),
  label               text,
  recipient_name      text NOT NULL,                          -- pii
  phone               text NOT NULL,                          -- pii:phone
  city_code           text NOT NULL,
  district_code       text NOT NULL,
  neighborhood_code   text,
  line1               text NOT NULL,                          -- pii:address
  line2               text,
  postal_code         text,
  directions_text     text,                                   -- tarif ("büyük ceviz ağacının yanı")
  geo_lat             numeric(9,6),
  geo_lng             numeric(9,6),
  geo_accuracy_m      integer,
  site_contact_name   text,                                   -- bahçedeki kişi (bekçi/komşu)
  site_contact_phone  text,
  is_default          boolean NOT NULL DEFAULT false,
  deleted_at          timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  version             integer NOT NULL DEFAULT 1,
  CHECK ((geo_lat IS NULL) = (geo_lng IS NULL)),
  CHECK (geo_lat IS NULL OR (geo_lat BETWEEN 35 AND 43 AND geo_lng BETWEEN 25 AND 46))
);
CREATE INDEX ix_addresses_customer ON core.addresses(customer_id) WHERE deleted_at IS NULL;
CREATE TRIGGER trg_addresses_ver BEFORE UPDATE ON core.addresses FOR EACH ROW EXECUTE FUNCTION core.bump_version();

-- ── Türkiye il/ilçe/mahalle (sürümlü açık veri) ─────────────────
CREATE TABLE core.geo_datasets (
  id          uuid PRIMARY KEY DEFAULT core.uuidv7(),
  source      text NOT NULL,
  version     text NOT NULL,
  imported_at timestamptz NOT NULL DEFAULT now(),
  is_active   boolean NOT NULL DEFAULT false
);
CREATE TABLE core.geo_places (
  dataset_id  uuid NOT NULL REFERENCES core.geo_datasets(id),
  level       text NOT NULL CHECK (level IN ('city','district','neighborhood')),
  code        text NOT NULL,
  parent_code text,
  name        text NOT NULL,
  postal_code text,
  PRIMARY KEY (dataset_id, level, code)
);
CREATE INDEX ix_geo_parent ON core.geo_places(dataset_id, level, parent_code);

-- ── Personel / Roller ───────────────────────────────────────────
CREATE TABLE core.staff (
  id            uuid PRIMARY KEY DEFAULT core.uuidv7(),
  email         citext NOT NULL UNIQUE,
  full_name     text NOT NULL,
  phone         text,
  password_hash text NOT NULL,                                 -- argon2id
  totp_secret_enc bytea,                                       -- uygulama düzeyi şifreli
  totp_enabled_at timestamptz,
  recovery_codes_hash text[],
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','left')),
  last_login_at timestamptz,
  failed_logins integer NOT NULL DEFAULT 0,
  locked_until  timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  version       integer NOT NULL DEFAULT 1
);
CREATE TRIGGER trg_staff_ver BEFORE UPDATE ON core.staff FOR EACH ROW EXECUTE FUNCTION core.bump_version();

CREATE TABLE core.roles (
  code        text PRIMARY KEY,                                -- owner, manager, packer, driver, support, accountant
  name        text NOT NULL,
  is_system   boolean NOT NULL DEFAULT false
);
CREATE TABLE core.permissions (
  code        text PRIMARY KEY,                                -- 'orders:refund', 'mill:weigh' ...
  description text NOT NULL
);
CREATE TABLE core.role_permissions (
  role_code   text NOT NULL REFERENCES core.roles(code),
  permission  text NOT NULL REFERENCES core.permissions(code),
  PRIMARY KEY (role_code, permission)
);
CREATE TABLE core.staff_roles (
  staff_id    uuid NOT NULL REFERENCES core.staff(id),
  role_code   text NOT NULL REFERENCES core.roles(code),
  PRIMARY KEY (staff_id, role_code)
);

-- ── Oturum / OTP ────────────────────────────────────────────────
CREATE TABLE core.sessions (
  id            uuid PRIMARY KEY DEFAULT core.uuidv7(),
  subject_type  text NOT NULL CHECK (subject_type IN ('customer','staff')),
  subject_id    uuid NOT NULL,
  token_hash    bytea NOT NULL UNIQUE,                         -- SHA-256(token); ham jeton saklanmaz
  csrf_secret   bytea NOT NULL,
  ip            inet,
  user_agent    text,
  device_label  text,
  expires_at    timestamptz NOT NULL,
  idle_expires_at timestamptz NOT NULL,
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  revoked_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_sessions_subject ON core.sessions(subject_type, subject_id) WHERE revoked_at IS NULL;
CREATE INDEX ix_sessions_expiry ON core.sessions(expires_at);

CREATE TABLE core.otp_challenges (
  id            uuid PRIMARY KEY DEFAULT core.uuidv7(),
  channel       text NOT NULL CHECK (channel IN ('sms','email')),
  destination   text NOT NULL,                                 -- pii:contact (24 sa sonra silinir)
  purpose       text NOT NULL CHECK (purpose IN ('login','verify_identity','pickup_ack','weighing_ack','order_confirm')),
  code_hash     bytea NOT NULL,
  attempts      smallint NOT NULL DEFAULT 0,
  max_attempts  smallint NOT NULL DEFAULT 5,
  expires_at    timestamptz NOT NULL,
  consumed_at   timestamptz,
  superseded_at timestamptz,
  ip            inet,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_otp_dest ON core.otp_challenges(destination, created_at DESC);

-- ── Onay/imza kanıtı (tartı onayı, sözleşme, teslim) ───────────
CREATE TABLE core.acknowledgements (
  id            uuid PRIMARY KEY DEFAULT core.uuidv7(),
  subject_type  text NOT NULL,                                 -- 'weighing','pickup','delivery','distance_sale','mill_terms','kvkk_notice'
  subject_id    uuid,
  customer_ref  uuid,
  method        text NOT NULL CHECK (method IN ('otp','click','staff_attested','signature')),
  text_version  text,
  otp_challenge_id uuid,
  ip            inet,
  user_agent    text,
  geo_lat       numeric(9,6),
  geo_lng       numeric(9,6),
  attested_by   uuid,                                          -- personel adına işlendiyse
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_ack_subject ON core.acknowledgements(subject_type, subject_id);
CREATE TRIGGER trg_ack_immut BEFORE UPDATE OR DELETE ON core.acknowledgements FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();

CREATE TABLE core.consent_log (
  id            uuid PRIMARY KEY DEFAULT core.uuidv7(),
  customer_id   uuid REFERENCES core.customers(id),
  type          text NOT NULL CHECK (type IN ('kvkk_notice','marketing_sms','marketing_email','cookie_analytics','location','commercial_message')),
  granted       boolean NOT NULL,
  source        text NOT NULL,                                 -- 'checkout','account','mill_wizard','iys_import'
  text_version  text,
  ip            inet,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_consent_immut BEFORE UPDATE OR DELETE ON core.consent_log FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();
CREATE INDEX ix_consent_customer ON core.consent_log(customer_id, type, created_at DESC);

-- ── Vergi ───────────────────────────────────────────────────────
CREATE TABLE core.tax_classes (
  code        text PRIMARY KEY,                                -- 'food_default','service_default'
  name        text NOT NULL,
  note        text
);
CREATE TABLE core.tax_rates (
  id          uuid PRIMARY KEY DEFAULT core.uuidv7(),
  class_code  text NOT NULL REFERENCES core.tax_classes(code),
  rate_bp     integer NOT NULL CHECK (rate_bp BETWEEN 0 AND 10000),   -- 1000 = %10
  valid_from  date NOT NULL,
  valid_to    date,
  source_note text,                                            -- hangi mevzuat/müşavir teyidi
  EXCLUDE USING gist (class_code WITH =, daterange(valid_from, valid_to, '[)') WITH &&)
);

-- ── Ayarlar / bayraklar / denetim / outbox / idempotensi ───────
CREATE TABLE core.settings (
  key         text PRIMARY KEY,
  value       jsonb NOT NULL,
  schema_ver  integer NOT NULL DEFAULT 1,
  updated_by  uuid,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  version     integer NOT NULL DEFAULT 1
);
CREATE TRIGGER trg_settings_ver BEFORE UPDATE ON core.settings FOR EACH ROW EXECUTE FUNCTION core.bump_version();

CREATE TABLE core.feature_flags (
  key         text PRIMARY KEY,
  enabled     boolean NOT NULL DEFAULT false,
  rules       jsonb NOT NULL DEFAULT '{}'::jsonb,
  expires_at  date,                                            -- bayrak yaşam süresi (90 gün kuralı)
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE core.audit_log (
  id          uuid PRIMARY KEY DEFAULT core.uuidv7(),
  at          timestamptz NOT NULL DEFAULT now(),
  actor_type  text NOT NULL CHECK (actor_type IN ('staff','customer','system','provider')),
  actor_id    uuid,
  action      text NOT NULL,
  entity      text NOT NULL,
  entity_id   uuid,
  before      jsonb,
  after       jsonb,
  ip          inet,
  request_id  text,
  reason      text
);
CREATE INDEX ix_audit_entity ON core.audit_log(entity, entity_id, at DESC);
CREATE INDEX ix_audit_actor ON core.audit_log(actor_type, actor_id, at DESC);
CREATE TRIGGER trg_audit_immut BEFORE UPDATE OR DELETE ON core.audit_log FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();

CREATE TABLE core.outbox (
  id            uuid PRIMARY KEY DEFAULT core.uuidv7(),
  topic         text NOT NULL,
  schema_version integer NOT NULL DEFAULT 1,
  aggregate     text NOT NULL,
  aggregate_id  uuid NOT NULL,
  payload       jsonb NOT NULL,
  occurred_at   timestamptz NOT NULL DEFAULT now(),
  available_at  timestamptz NOT NULL DEFAULT now(),
  processed_at  timestamptz,
  attempts      integer NOT NULL DEFAULT 0,
  last_error    text
);
CREATE INDEX ix_outbox_pending ON core.outbox(available_at) WHERE processed_at IS NULL;

CREATE TABLE core.idempotency_keys (
  scope         text NOT NULL,
  key           text NOT NULL,
  request_hash  bytea NOT NULL,
  response_status integer,
  response_body jsonb,
  locked_until  timestamptz,
  expires_at    timestamptz NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (scope, key)
);

-- Belge deposu (tutanak PDF, gazi belgesi, makbuz, fatura PDF)
CREATE TABLE core.documents (
  id            uuid PRIMARY KEY DEFAULT core.uuidv7(),
  kind          text NOT NULL,                                 -- 'weighing_slip','invoice_pdf','discount_proof','scale_receipt_photo','product_media'
  owner_type    text NOT NULL,
  owner_id      uuid NOT NULL,
  storage_key   text NOT NULL UNIQUE,
  mime          text NOT NULL,
  size_bytes    bigint NOT NULL CHECK (size_bytes >= 0),
  sha256        bytea NOT NULL,
  visibility    text NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','public')),
  retain_until  date,
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);
CREATE INDEX ix_documents_owner ON core.documents(owner_type, owner_id);

-- Müşteri hesabı kredisi (iade yerine kredi / kampanya) — E15
CREATE TABLE core.credit_entries (
  id            uuid PRIMARY KEY DEFAULT core.uuidv7(),
  customer_id   uuid NOT NULL REFERENCES core.customers(id),
  amount_kurus  bigint NOT NULL CHECK (amount_kurus <> 0),    -- + yükleme, − harcama
  reason        text NOT NULL,
  ref_type      text, ref_id uuid,
  expires_at    date,
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_credit_immut BEFORE UPDATE OR DELETE ON core.credit_entries FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();
CREATE INDEX ix_credit_customer ON core.credit_entries(customer_id);
```

---

## 3. `0003_shop.sql`
```sql
-- migrate:up

CREATE TABLE shop.categories (
  id          uuid PRIMARY KEY DEFAULT core.uuidv7(),
  parent_id   uuid REFERENCES shop.categories(id),
  slug        text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name        text NOT NULL,
  description text,
  sort        integer NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true,
  seo_title   text, seo_description text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  version     integer NOT NULL DEFAULT 1
);
CREATE TRIGGER trg_categories_ver BEFORE UPDATE ON shop.categories FOR EACH ROW EXECUTE FUNCTION core.bump_version();

CREATE TABLE shop.products (
  id            uuid PRIMARY KEY DEFAULT core.uuidv7(),
  slug          text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  kind          text NOT NULL DEFAULT 'simple' CHECK (kind IN ('simple','bundle')),
  status        text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','archived')),
  category_id   uuid REFERENCES shop.categories(id),
  name          text NOT NULL,
  short_desc    text,
  long_desc     text,
  tax_class     text NOT NULL REFERENCES core.tax_classes(code),
  brand         text,
  origin        text,
  ingredients   text,
  allergens     text,
  allergen_tags text[] NOT NULL DEFAULT '{}',                 -- {'fındık','süt'}
  nutrition     jsonb,                                         -- 100 g başına: kcal, protein_g, fat_g, sat_fat_g, carb_g, sugar_g, fiber_g, salt_g
  nutrition_source text,                                       -- 'lab:<belge no>' | 'supplier' | 'estimated'
  storage_info  text,
  shelf_life_days integer CHECK (shelf_life_days IS NULL OR shelf_life_days > 0),
  seo_title     text, seo_description text,
  published_at  timestamptz,
  search_tsv    tsvector GENERATED ALWAYS AS (
                  setweight(to_tsvector('simple', core.tr_unaccent(coalesce(name,''))), 'A') ||
                  setweight(to_tsvector('simple', core.tr_unaccent(coalesce(short_desc,''))), 'B') ||
                  setweight(to_tsvector('simple', core.tr_unaccent(coalesce(long_desc,''))), 'C')) STORED,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  version       integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_products_status ON shop.products(status) WHERE deleted_at IS NULL;
CREATE INDEX ix_products_category ON shop.products(category_id);
CREATE INDEX ix_products_search ON shop.products USING gin(search_tsv);
CREATE TRIGGER trg_products_ver BEFORE UPDATE ON shop.products FOR EACH ROW EXECUTE FUNCTION core.bump_version();

CREATE TABLE shop.product_translations (        -- S9 çok dil hazırlığı
  product_id  uuid NOT NULL REFERENCES shop.products(id),
  locale      text NOT NULL,
  name        text NOT NULL, short_desc text, long_desc text, ingredients text, allergens text,
  PRIMARY KEY (product_id, locale)
);

CREATE TABLE shop.variants (
  id             uuid PRIMARY KEY DEFAULT core.uuidv7(),
  product_id     uuid NOT NULL REFERENCES shop.products(id),
  sku            text NOT NULL UNIQUE,
  label          text NOT NULL,                                -- '300 g kavanoz'
  net_content_g  integer CHECK (net_content_g IS NULL OR net_content_g > 0),   -- etiket net miktarı
  ship_weight_g  integer NOT NULL CHECK (ship_weight_g > 0),   -- ambalaj dahil kargo ağırlığı
  price_kurus    bigint NOT NULL CHECK (price_kurus >= 0),     -- KDV DAHİL liste fiyatı
  compare_at_kurus bigint CHECK (compare_at_kurus IS NULL OR compare_at_kurus > price_kurus),
  cost_kurus     bigint CHECK (cost_kurus IS NULL OR cost_kurus >= 0),
  barcode        text,
  max_per_order  integer NOT NULL DEFAULT 20 CHECK (max_per_order > 0),
  is_active      boolean NOT NULL DEFAULT true,
  sort           integer NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  version        integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_variants_product ON shop.variants(product_id);
CREATE UNIQUE INDEX uq_variants_barcode ON shop.variants(barcode) WHERE barcode IS NOT NULL;
CREATE TRIGGER trg_variants_ver BEFORE UPDATE ON shop.variants FOR EACH ROW EXECUTE FUNCTION core.bump_version();

CREATE TABLE shop.bundle_components (           -- E3
  bundle_variant_id    uuid NOT NULL REFERENCES shop.variants(id),
  component_variant_id uuid NOT NULL REFERENCES shop.variants(id),
  qty                  integer NOT NULL CHECK (qty > 0),
  PRIMARY KEY (bundle_variant_id, component_variant_id),
  CHECK (bundle_variant_id <> component_variant_id)
);

CREATE TABLE shop.product_media (
  id          uuid PRIMARY KEY DEFAULT core.uuidv7(),
  product_id  uuid NOT NULL REFERENCES shop.products(id),
  variant_id  uuid REFERENCES shop.variants(id),
  document_id uuid NOT NULL,                                   -- core.documents (kind='product_media')
  alt_text    text NOT NULL CHECK (length(alt_text) > 3),
  width       integer, height integer, blurhash text,
  sort        integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_media_product ON shop.product_media(product_id, sort);

-- ── Fiyat listeleri / müşteri grupları (E4) ─────────────────────
CREATE TABLE shop.customer_groups (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), code text NOT NULL UNIQUE, name text NOT NULL
);
CREATE TABLE shop.customer_group_members (
  group_id uuid NOT NULL REFERENCES shop.customer_groups(id),
  customer_id uuid NOT NULL REFERENCES core.customers(id),
  PRIMARY KEY (group_id, customer_id)
);
CREATE TABLE shop.price_lists (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), code text NOT NULL UNIQUE, name text NOT NULL,
  group_id uuid REFERENCES shop.customer_groups(id),
  valid_from timestamptz NOT NULL DEFAULT now(), valid_to timestamptz,
  priority integer NOT NULL DEFAULT 0, is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE shop.price_list_items (
  price_list_id uuid NOT NULL REFERENCES shop.price_lists(id),
  variant_id    uuid NOT NULL REFERENCES shop.variants(id),
  price_kurus   bigint NOT NULL CHECK (price_kurus >= 0),
  min_qty       integer NOT NULL DEFAULT 1 CHECK (min_qty > 0),
  PRIMARY KEY (price_list_id, variant_id, min_qty)
);

-- ── Stok (E19: lokasyon) ────────────────────────────────────────
CREATE TABLE shop.stock_locations (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), code text NOT NULL UNIQUE, name text NOT NULL, is_default boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX uq_default_location ON shop.stock_locations((true)) WHERE is_default;

CREATE TABLE shop.stock_levels (
  variant_id  uuid NOT NULL REFERENCES shop.variants(id),
  location_id uuid NOT NULL REFERENCES shop.stock_locations(id),
  on_hand     integer NOT NULL DEFAULT 0 CHECK (on_hand >= 0),
  reserved    integer NOT NULL DEFAULT 0 CHECK (reserved >= 0),
  available   integer GENERATED ALWAYS AS (on_hand - reserved) STORED CHECK (available >= 0),
  low_stock_threshold integer NOT NULL DEFAULT 0,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (variant_id, location_id)
);

CREATE TABLE shop.stock_ledger (                 -- değişmez
  id          uuid PRIMARY KEY DEFAULT core.uuidv7(),
  variant_id  uuid NOT NULL REFERENCES shop.variants(id),
  location_id uuid NOT NULL REFERENCES shop.stock_locations(id),
  delta       integer NOT NULL CHECK (delta <> 0),
  kind        text NOT NULL CHECK (kind IN ('receipt','production','sale','return','adjustment','shrinkage','reserve','release','commit','bundle_consume')),
  ref_type    text, ref_id uuid,
  note        text,
  actor_id    uuid,
  at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_stock_ledger_variant ON shop.stock_ledger(variant_id, at DESC);
CREATE TRIGGER trg_stock_ledger_immut BEFORE UPDATE OR DELETE ON shop.stock_ledger FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();

CREATE TABLE shop.stock_reservations (
  id          uuid PRIMARY KEY DEFAULT core.uuidv7(),
  variant_id  uuid NOT NULL REFERENCES shop.variants(id),
  location_id uuid NOT NULL REFERENCES shop.stock_locations(id),
  order_id    uuid NOT NULL,
  qty         integer NOT NULL CHECK (qty > 0),
  status      text NOT NULL DEFAULT 'active' CHECK (status IN ('active','committed','released','expired')),
  expires_at  timestamptz NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (order_id, variant_id)
);
CREATE INDEX ix_reservations_expiry ON shop.stock_reservations(expires_at) WHERE status = 'active';

-- ── Sepet ───────────────────────────────────────────────────────
CREATE TABLE shop.carts (
  id           uuid PRIMARY KEY DEFAULT core.uuidv7(),
  token_hash   bytea NOT NULL UNIQUE,
  customer_id  uuid REFERENCES core.customers(id),
  coupon_code  text,
  channel      text NOT NULL DEFAULT 'web' CHECK (channel IN ('web','admin','marketplace')),
  expires_at   timestamptz NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  version      integer NOT NULL DEFAULT 1
);
CREATE TABLE shop.cart_items (
  cart_id     uuid NOT NULL REFERENCES shop.carts(id) ON DELETE CASCADE,
  variant_id  uuid NOT NULL REFERENCES shop.variants(id),
  qty         integer NOT NULL CHECK (qty > 0),
  added_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (cart_id, variant_id)
);

-- ── Promosyonlar ────────────────────────────────────────────────
CREATE TABLE shop.promotions (
  id           uuid PRIMARY KEY DEFAULT core.uuidv7(),
  code         text UNIQUE,                                    -- kupon kodu (otomatik promosyonlarda NULL)
  name         text NOT NULL,
  kind         text NOT NULL CHECK (kind IN ('percent','fixed','free_shipping')),
  value        bigint NOT NULL DEFAULT 0 CHECK (value >= 0),   -- percent: baz puan, fixed: kuruş
  min_subtotal_kurus bigint NOT NULL DEFAULT 0,
  max_discount_kurus bigint,
  applies_to   jsonb NOT NULL DEFAULT '{"all":true}'::jsonb,  -- {"all":true} | {"categories":[...]} | {"variants":[...]}
  first_order_only boolean NOT NULL DEFAULT false,
  max_uses     integer, uses integer NOT NULL DEFAULT 0 CHECK (uses >= 0),
  max_uses_per_customer integer NOT NULL DEFAULT 1,
  stackable    boolean NOT NULL DEFAULT false,
  payment_methods text[],                                      -- NULL = hepsi
  starts_at    timestamptz, ends_at timestamptz,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  version      integer NOT NULL DEFAULT 1,
  CHECK (kind <> 'percent' OR value BETWEEN 1 AND 10000),
  CHECK (max_uses IS NULL OR uses <= max_uses)
);
CREATE TABLE shop.promotion_redemptions (
  id           uuid PRIMARY KEY DEFAULT core.uuidv7(),
  promotion_id uuid NOT NULL REFERENCES shop.promotions(id),
  customer_key bytea NOT NULL,                                 -- hash(customer_id | telefon | e-posta)
  order_id     uuid NOT NULL,
  amount_kurus bigint NOT NULL,
  reversed_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (promotion_id, order_id)
);
CREATE INDEX ix_redemption_key ON shop.promotion_redemptions(promotion_id, customer_key) WHERE reversed_at IS NULL;

CREATE TABLE shop.discount_claims (               -- gazi / şehit yakını (hesap bazlı geçerlilik)
  id           uuid PRIMARY KEY DEFAULT core.uuidv7(),
  customer_id  uuid NOT NULL REFERENCES core.customers(id),
  kind         text NOT NULL CHECK (kind IN ('gazi','sehit_yakini')),
  rate_bp      integer NOT NULL CHECK (rate_bp BETWEEN 1 AND 10000),
  status       text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','expired','revoked')),
  proof_document_id uuid,
  review_note  text,
  reviewed_by  uuid, reviewed_at timestamptz,
  valid_until  date,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  version      integer NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX uq_claim_active ON shop.discount_claims(customer_id) WHERE status IN ('pending','approved');

-- ── Kargo kuralları ─────────────────────────────────────────────
CREATE TABLE shop.shipping_zones (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), code text NOT NULL UNIQUE, name text NOT NULL, city_codes text[] NOT NULL, is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE shop.shipping_rates (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(),
  zone_id uuid NOT NULL REFERENCES shop.shipping_zones(id),
  carrier_code text NOT NULL,
  min_weight_g integer NOT NULL DEFAULT 0, max_weight_g integer NOT NULL,
  fee_kurus bigint NOT NULL CHECK (fee_kurus >= 0),            -- KDV dahil
  free_over_kurus bigint,
  valid_from date NOT NULL DEFAULT current_date, valid_to date,
  CHECK (max_weight_g > min_weight_g)
);

-- ── Sipariş ─────────────────────────────────────────────────────
CREATE TABLE shop.orders (
  id               uuid PRIMARY KEY DEFAULT core.uuidv7(),
  number           text NOT NULL UNIQUE,                       -- 'NT-2026-000123'
  track_token_hash bytea NOT NULL UNIQUE,
  channel          text NOT NULL DEFAULT 'web' CHECK (channel IN ('web','admin','phone','marketplace')),
  customer_id      uuid REFERENCES core.customers(id),
  contact_email    text,                                        -- pii (misafir)
  contact_phone    text NOT NULL,                               -- pii
  status           text NOT NULL CHECK (status IN ('pending_payment','awaiting_transfer','confirmed','paid','processing','packed','shipped','delivered','delivery_failed','returned_to_sender','return_requested','refunded','partially_refunded','cancelled','expired','manual_review')),
  payment_method   text NOT NULL CHECK (payment_method IN ('card','bank_transfer','cod','credit')),
  currency         char(3) NOT NULL DEFAULT 'TRY',
  business_unit    text NOT NULL DEFAULT 'shop' CHECK (business_unit = 'shop'),
  items_gross_kurus      bigint NOT NULL CHECK (items_gross_kurus >= 0),
  discount_kurus         bigint NOT NULL DEFAULT 0 CHECK (discount_kurus >= 0),
  shipping_gross_kurus   bigint NOT NULL DEFAULT 0 CHECK (shipping_gross_kurus >= 0),
  cod_fee_kurus          bigint NOT NULL DEFAULT 0 CHECK (cod_fee_kurus >= 0),
  grand_total_kurus      bigint NOT NULL CHECK (grand_total_kurus >= 0),
  tax_total_kurus        bigint NOT NULL CHECK (tax_total_kurus >= 0),
  coupon_code      text,
  promotion_id     uuid REFERENCES shop.promotions(id),
  discount_claim_id uuid REFERENCES shop.discount_claims(id),
  shipping_address jsonb NOT NULL,
  billing_address  jsonb,
  invoice_kind     text NOT NULL DEFAULT 'individual' CHECK (invoice_kind IN ('individual','company')),
  invoice_tax_no   text, invoice_tax_office text, invoice_company_name text,
  customer_note    text, gift_note text, internal_note text,
  legal_snapshot   jsonb NOT NULL,                              -- mesafeli satış sözleşmesi/ön bilgi sürümleri + onay zamanı + IP
  ip               inet, user_agent text,
  placed_at        timestamptz NOT NULL DEFAULT now(),
  paid_at          timestamptz, shipped_at timestamptz, delivered_at timestamptz, cancelled_at timestamptz,
  cancel_reason    text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  version          integer NOT NULL DEFAULT 1,
  CHECK (grand_total_kurus = items_gross_kurus - discount_kurus + shipping_gross_kurus + cod_fee_kurus),
  CHECK (customer_id IS NOT NULL OR contact_email IS NOT NULL OR contact_phone IS NOT NULL)
);
CREATE INDEX ix_orders_status ON shop.orders(status, placed_at DESC);
CREATE INDEX ix_orders_customer ON shop.orders(customer_id, placed_at DESC);
CREATE INDEX ix_orders_phone ON shop.orders(contact_phone);
CREATE TRIGGER trg_orders_ver BEFORE UPDATE ON shop.orders FOR EACH ROW EXECUTE FUNCTION core.bump_version();

CREATE TABLE shop.order_items (
  id                 uuid PRIMARY KEY DEFAULT core.uuidv7(),
  order_id           uuid NOT NULL REFERENCES shop.orders(id),
  variant_id         uuid NOT NULL REFERENCES shop.variants(id),
  parent_item_id     uuid REFERENCES shop.order_items(id),      -- bundle bileşeni
  name_snapshot      text NOT NULL, sku_snapshot text NOT NULL, label_snapshot text NOT NULL,
  ingredients_snapshot text, allergens_snapshot text,
  qty                integer NOT NULL CHECK (qty > 0),
  unit_gross_kurus   bigint NOT NULL CHECK (unit_gross_kurus >= 0),
  discount_alloc_kurus bigint NOT NULL DEFAULT 0 CHECK (discount_alloc_kurus >= 0),
  tax_rate_bp        integer NOT NULL CHECK (tax_rate_bp BETWEEN 0 AND 10000),
  line_gross_kurus   bigint NOT NULL,                           -- KDV dahil, indirim sonrası
  line_net_kurus     bigint NOT NULL,
  line_tax_kurus     bigint NOT NULL,
  CHECK (line_gross_kurus = unit_gross_kurus * qty - discount_alloc_kurus),
  CHECK (line_net_kurus + line_tax_kurus = line_gross_kurus)
);
CREATE INDEX ix_order_items_order ON shop.order_items(order_id);

CREATE TABLE shop.order_amendments (               -- E14
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), order_id uuid NOT NULL REFERENCES shop.orders(id),
  kind text NOT NULL, before jsonb NOT NULL, after jsonb NOT NULL, reason text, actor_id uuid, at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE shop.order_events (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), order_id uuid NOT NULL REFERENCES shop.orders(id),
  type text NOT NULL, from_status text, to_status text, actor_type text, actor_id uuid, note text, data jsonb, at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_order_events_order ON shop.order_events(order_id, at);
CREATE TRIGGER trg_order_events_immut BEFORE UPDATE OR DELETE ON shop.order_events FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();

CREATE TABLE shop.shipments (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), order_id uuid NOT NULL REFERENCES shop.orders(id),
  carrier_code text NOT NULL, tracking_no text, label_document_id uuid,
  status text NOT NULL DEFAULT 'created' CHECK (status IN ('created','handed_over','in_transit','out_for_delivery','delivered','failed','returned')),
  cost_kurus bigint, weight_g integer, shipped_at timestamptz, delivered_at timestamptz, raw jsonb,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), version integer NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX uq_shipment_tracking ON shop.shipments(carrier_code, tracking_no) WHERE tracking_no IS NOT NULL;
CREATE TABLE shop.shipment_items (                -- E5
  shipment_id uuid NOT NULL REFERENCES shop.shipments(id), order_item_id uuid NOT NULL REFERENCES shop.order_items(id), qty integer NOT NULL CHECK (qty > 0),
  PRIMARY KEY (shipment_id, order_item_id)
);

CREATE TABLE shop.returns (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), order_id uuid NOT NULL REFERENCES shop.orders(id),
  kind text NOT NULL CHECK (kind IN ('cancellation','defect','wrong_item','damaged','other')),
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','approved','rejected','received','refunded','replaced','closed')),
  reason text, evidence_document_ids uuid[], refund_kurus bigint CHECK (refund_kurus IS NULL OR refund_kurus >= 0),
  resolution text, requested_at timestamptz NOT NULL DEFAULT now(), closed_at timestamptz, version integer NOT NULL DEFAULT 1
);
CREATE TABLE shop.return_items (
  return_id uuid NOT NULL REFERENCES shop.returns(id), order_item_id uuid NOT NULL REFERENCES shop.order_items(id), qty integer NOT NULL CHECK (qty > 0), restock boolean NOT NULL DEFAULT false,
  PRIMARY KEY (return_id, order_item_id)
);

CREATE TABLE shop.stock_notify_requests (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), variant_id uuid NOT NULL REFERENCES shop.variants(id), contact text NOT NULL, kind text NOT NULL CHECK (kind IN ('sms','email')), consent_id uuid, notified_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE shop.reviews (                       -- v1.1, tablo hazır
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), product_id uuid NOT NULL REFERENCES shop.products(id), order_item_id uuid UNIQUE REFERENCES shop.order_items(id),
  rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5), body text, status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','published','rejected')), created_at timestamptz NOT NULL DEFAULT now()
);

-- Stok rezervini atomik yapan yardımcı (uygulama bunu çağırır; ham mantık burada, tek yer)
CREATE OR REPLACE FUNCTION shop.reserve_stock(p_variant uuid, p_location uuid, p_qty integer) RETURNS boolean AS $$
DECLARE n integer;
BEGIN
  UPDATE shop.stock_levels SET reserved = reserved + p_qty, updated_at = now()
   WHERE variant_id = p_variant AND location_id = p_location AND on_hand - reserved >= p_qty;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n = 1;
END $$ LANGUAGE plpgsql;
```

---

## 4. `0004_mill.sql`
> **Önemli:** `mill.*` tabloları `core.*`'a FK vermez. Müşteri ve personel `uuid` referansıdır + gerektiğinde anlık kopya (`*_snapshot`). Bu, değirmeni ayrı DB'ye taşımayı mümkün kılar (12 §4.2).

```sql
-- migrate:up

CREATE TABLE mill.services (
  code        text PRIMARY KEY,                                 -- 'kirma','kavurma','zar_soyma','ezme', 'paket_1kg'...
  name        text NOT NULL, description text,
  step_order  integer NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true
);

-- Ücret kuralları: zaman damgalı, genel (E9)
CREATE TABLE mill.pricing_rules (
  id           uuid PRIMARY KEY DEFAULT core.uuidv7(),
  service_codes text[] NOT NULL,                                -- birleşik paket için çoklu: {'kirma','kavurma'}
  package_code  text NOT NULL,                                  -- müşteriye görünen paket kodu ('kk_1kg')
  package_name  text NOT NULL,
  basis        text NOT NULL CHECK (basis IN ('input_kg','output_kg','flat','per_bag')),
  unit_price_kurus bigint NOT NULL CHECK (unit_price_kurus >= 0),   -- KDV dahil
  tiers        jsonb,                                           -- [{"from_kg":500,"unit_price_kurus":6000}]
  min_charge_kurus bigint,
  tax_class    text NOT NULL DEFAULT 'service_default',
  tax_rate_bp_snapshot integer,                                 -- bilgi, asıl kaynak core.tax_rates
  valid_from   date NOT NULL, valid_to date,
  season       text,
  created_by   uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_pricing_pkg ON mill.pricing_rules(package_code, valid_from DESC);
CREATE TRIGGER trg_pricing_immut BEFORE DELETE ON mill.pricing_rules FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();

CREATE TABLE mill.coverage (
  id            uuid PRIMARY KEY DEFAULT core.uuidv7(),
  city_code     text NOT NULL, district_code text NOT NULL, neighborhood_code text,
  pickup_fee_kurus bigint NOT NULL DEFAULT 0 CHECK (pickup_fee_kurus >= 0),
  delivery_fee_kurus bigint NOT NULL DEFAULT 0 CHECK (delivery_fee_kurus >= 0),
  free_over_kg  integer,
  min_kg        integer NOT NULL DEFAULT 0,
  weekdays      smallint[] NOT NULL DEFAULT '{1,2,3,4,5,6}',     -- ISO 1=Pzt
  is_active     boolean NOT NULL DEFAULT true,
  note          text,
  UNIQUE (city_code, district_code, neighborhood_code)
);

CREATE TABLE mill.requests (
  id               uuid PRIMARY KEY DEFAULT core.uuidv7(),
  number           text NOT NULL UNIQUE,                         -- 'DG-2026-000045'
  track_token_hash bytea NOT NULL UNIQUE,
  customer_ref     uuid NOT NULL,                                -- core.customers.id (FK YOK)
  customer_snapshot jsonb NOT NULL,                              -- ad, telefon (talep anı)
  business_unit    text NOT NULL DEFAULT 'mill' CHECK (business_unit = 'mill'),
  status           text NOT NULL CHECK (status IN ('requested','approved','rejected','scheduled','picking_up','pickup_failed','picked_up','processing','ready','delivery_scheduled','awaiting_self_pickup','delivered','paid','cancelled','disputed')),
  intake_mode      text NOT NULL DEFAULT 'courier_pickup' CHECK (intake_mode IN ('courier_pickup','self_dropoff')),
  return_mode      text NOT NULL DEFAULT 'courier_back' CHECK (return_mode IN ('courier_back','self_pickup')),
  package_code     text NOT NULL,
  rate_snapshot    jsonb NOT NULL,                               -- seçilen pricing_rules satırının tam kopyası
  est_input_kg     integer NOT NULL CHECK (est_input_kg > 0),
  est_bag_count    integer,
  est_total_kurus  bigint NOT NULL CHECK (est_total_kurus >= 0),
  pickup_site      jsonb NOT NULL,                               -- adres anlık kopya + tarif + geo + saha kişisi
  return_site      jsonb,
  preferred_date   date, preferred_slot text CHECK (preferred_slot IN ('morning','afternoon','any')),
  customer_note    text, internal_note text,
  settlement_method text NOT NULL DEFAULT 'cash_on_delivery' CHECK (settlement_method IN ('cash_on_delivery','online','transfer','in_kind','credit_account')),
  approved_by uuid, approved_at timestamptz, rejected_reason text, cancelled_reason text, cancelled_by text,
  legal_snapshot   jsonb NOT NULL,
  channel          text NOT NULL DEFAULT 'web' CHECK (channel IN ('web','phone','admin','walk_in')),
  created_by_staff uuid,                                         -- telefonla açıldıysa
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), version integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_mill_req_status ON mill.requests(status, created_at DESC);
CREATE INDEX ix_mill_req_customer ON mill.requests(customer_ref, created_at DESC);
CREATE INDEX ix_mill_req_date ON mill.requests(preferred_date) WHERE status IN ('approved','scheduled');
CREATE TRIGGER trg_mill_req_ver BEFORE UPDATE ON mill.requests FOR EACH ROW EXECUTE FUNCTION core.bump_version();

CREATE TABLE mill.drivers (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), staff_ref uuid NOT NULL UNIQUE, display_name text NOT NULL, phone text,
  vehicle_plate text, capacity_kg integer, is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE mill.dispatch_plans (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), plan_date date NOT NULL, driver_id uuid NOT NULL REFERENCES mill.drivers(id),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','in_progress','done','cancelled')),
  note text, created_by uuid, created_at timestamptz NOT NULL DEFAULT now(), version integer NOT NULL DEFAULT 1,
  UNIQUE (plan_date, driver_id)
);
CREATE TABLE mill.pickups (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(),
  request_id uuid NOT NULL REFERENCES mill.requests(id),
  plan_id uuid REFERENCES mill.dispatch_plans(id),
  driver_id uuid REFERENCES mill.drivers(id),
  kind text NOT NULL DEFAULT 'pickup' CHECK (kind IN ('pickup','delivery_back')),
  scheduled_date date, slot text CHECK (slot IN ('morning','afternoon','any')), sequence integer,
  status text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','en_route','arrived','weighed','completed','failed','cancelled')),
  code_hash bytea,                                               -- müşteriye SMS ile giden alım kodu
  code_expires_at timestamptz,
  attempts integer NOT NULL DEFAULT 0,
  started_at timestamptz, arrived_at timestamptz, completed_at timestamptz,
  arrived_lat numeric(9,6), arrived_lng numeric(9,6),
  fail_reason text, fail_note text,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), version integer NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX uq_pickup_active ON mill.pickups(request_id, kind) WHERE status IN ('planned','en_route','arrived','weighed');
CREATE INDEX ix_pickups_plan ON mill.pickups(plan_id, sequence);
CREATE INDEX ix_pickups_driver_day ON mill.pickups(driver_id, scheduled_date);

CREATE TABLE mill.weighings (                      -- değişmez; düzeltme = yeni satır
  id uuid PRIMARY KEY DEFAULT core.uuidv7(),
  request_id uuid NOT NULL REFERENCES mill.requests(id),
  pickup_id uuid REFERENCES mill.pickups(id),
  stage text NOT NULL CHECK (stage IN ('field_intake','mill_intake','output','delivery')),
  gross_g bigint NOT NULL CHECK (gross_g > 0),
  tare_g bigint NOT NULL DEFAULT 0 CHECK (tare_g >= 0),
  net_g bigint NOT NULL,
  bag_count integer, moisture_bp integer CHECK (moisture_bp IS NULL OR moisture_bp BETWEEN 0 AND 10000),
  scale_id text, scale_receipt_document_id uuid,
  weighed_by uuid NOT NULL,                                      -- staff ref
  weighed_at timestamptz NOT NULL DEFAULT now(),
  acknowledgement_id uuid,                                       -- core.acknowledgements (FK yok)
  supersedes_id uuid REFERENCES mill.weighings(id),
  note text,
  CHECK (net_g = gross_g - tare_g AND net_g > 0)
);
CREATE INDEX ix_weighings_request ON mill.weighings(request_id, stage, weighed_at);
CREATE TRIGGER trg_weighings_immut BEFORE UPDATE OR DELETE ON mill.weighings FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();

CREATE TABLE mill.jobs (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(),
  request_id uuid NOT NULL REFERENCES mill.requests(id),
  lot_code text NOT NULL UNIQUE,                                 -- 'L26-000045'
  input_net_g bigint NOT NULL CHECK (input_net_g > 0),
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','done','hold','cancelled')),
  steps jsonb NOT NULL DEFAULT '[]'::jsonb,                      -- [{"code":"kirma","started_at":...,"ended_at":...,"operator":...}]
  output_g bigint CHECK (output_g IS NULL OR output_g >= 0),
  yield_bp integer GENERATED ALWAYS AS (CASE WHEN output_g IS NULL THEN NULL ELSE (output_g * 10000 / input_net_g)::int END) STORED,
  anomaly_flag boolean NOT NULL DEFAULT false,
  started_at timestamptz, finished_at timestamptz, operator_ref uuid, notes text,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), version integer NOT NULL DEFAULT 1
);
CREATE UNIQUE INDEX uq_job_request_active ON mill.jobs(request_id) WHERE status <> 'cancelled';

-- Ücret kalemleri: kesin ücret = Σ amount_kurus
CREATE TABLE mill.charges (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(),
  request_id uuid NOT NULL REFERENCES mill.requests(id),
  phase text NOT NULL DEFAULT 'estimate' CHECK (phase IN ('estimate','final')),
  kind text NOT NULL CHECK (kind IN ('service','pickup_fee','delivery_fee','discount','adjustment','in_kind_offset')),
  description text NOT NULL,
  basis_g bigint, unit_price_kurus bigint,
  amount_kurus bigint NOT NULL,                                  -- indirim/ayni mahsup negatif
  tax_rate_bp integer NOT NULL DEFAULT 0 CHECK (tax_rate_bp BETWEEN 0 AND 10000),
  net_kurus bigint NOT NULL, tax_kurus bigint NOT NULL,
  supersedes_id uuid REFERENCES mill.charges(id),
  created_by uuid, created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (net_kurus + tax_kurus = amount_kurus)
);
CREATE INDEX ix_charges_request ON mill.charges(request_id, phase);
CREATE TRIGGER trg_charges_immut BEFORE UPDATE OR DELETE ON mill.charges FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();

CREATE TABLE mill.deliveries (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(),
  request_id uuid NOT NULL REFERENCES mill.requests(id),
  mode text NOT NULL CHECK (mode IN ('courier','self_pickup')),
  pickup_id uuid REFERENCES mill.pickups(id),
  delivered_net_g bigint NOT NULL CHECK (delivered_net_g >= 0),
  received_by_name text, acknowledgement_id uuid,
  delivered_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE mill.events (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), request_id uuid NOT NULL REFERENCES mill.requests(id),
  type text NOT NULL, from_status text, to_status text, actor_type text, actor_ref uuid, note text, data jsonb, at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_mill_events_req ON mill.events(request_id, at);
CREATE TRIGGER trg_mill_events_immut BEFORE UPDATE OR DELETE ON mill.events FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();

-- Cari hesap (veresiye) ve kredi limiti — E7
CREATE TABLE mill.receivable_accounts (
  customer_ref uuid PRIMARY KEY,
  credit_limit_kurus bigint NOT NULL DEFAULT 0 CHECK (credit_limit_kurus >= 0),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','frozen')),
  note text, updated_at timestamptz NOT NULL DEFAULT now(), version integer NOT NULL DEFAULT 1
);
CREATE TABLE mill.receivable_entries (           -- değişmez cari hareket defteri
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), customer_ref uuid NOT NULL REFERENCES mill.receivable_accounts(customer_ref),
  request_id uuid REFERENCES mill.requests(id),
  amount_kurus bigint NOT NULL CHECK (amount_kurus <> 0),        -- + borç doğdu, − tahsilat
  kind text NOT NULL CHECK (kind IN ('charge','payment','adjustment','writeoff')),
  payment_ref uuid, note text, created_by uuid, at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_recv_customer ON mill.receivable_entries(customer_ref, at DESC);
CREATE TRIGGER trg_recv_immut BEFORE UPDATE OR DELETE ON mill.receivable_entries FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();

-- Ayni ödeme / değirmen stoğu — E8 (hammadde/bitmiş kg hareketleri)
CREATE TABLE mill.inventory_movements (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(),
  item text NOT NULL CHECK (item IN ('raw_in_shell','shelled','roasted','paste')),
  delta_g bigint NOT NULL CHECK (delta_g <> 0),
  reason text NOT NULL CHECK (reason IN ('customer_intake','processing_loss','processing_output','customer_return','in_kind_fee','shrinkage','adjustment','sale_to_shop')),
  request_id uuid REFERENCES mill.requests(id), job_id uuid REFERENCES mill.jobs(id), lot_code text,
  note text, actor uuid, at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_mill_inv_immut BEFORE UPDATE OR DELETE ON mill.inventory_movements FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();

CREATE TABLE mill.waitlist (                       -- kapsam dışı adres bekleme listesi
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), contact text NOT NULL, city_code text, district_code text, neighborhood_text text, est_kg integer, created_at timestamptz NOT NULL DEFAULT now()
);
```

---

## 5. `0005_payments.sql`
> `payments.*`: hedef (`shop.orders` / `mill.requests`) **polimorfik referanstır, FK yok**. Bütünlük: servis katmanı + gece uyum denetimi (14 §9).

```sql
-- migrate:up
CREATE TABLE payments.payments (
  id                 uuid PRIMARY KEY DEFAULT core.uuidv7(),
  target_type        text NOT NULL CHECK (target_type IN ('shop_order','mill_request')),
  target_id          uuid NOT NULL,
  business_unit      text NOT NULL CHECK (business_unit IN ('shop','mill')),
  provider           text NOT NULL CHECK (provider IN ('iyzico','paytr','bank_transfer','cod','cash','pos','credit','in_kind')),
  method_detail      text,
  amount_kurus       bigint NOT NULL CHECK (amount_kurus > 0),
  currency           char(3) NOT NULL DEFAULT 'TRY',
  status             text NOT NULL CHECK (status IN ('initiated','pending','authorized','captured','failed','cancelled','expired','partially_refunded','refunded')),
  conversation_id    text NOT NULL UNIQUE,                       -- sağlayıcıya verdiğimiz tekil kimlik
  provider_payment_id text, provider_token text,
  installment        smallint NOT NULL DEFAULT 1,
  card_brand text, card_last4 text, card_bin text,
  three_ds           boolean,
  fraud_status       text,
  error_code text, error_message text,
  provider_fee_kurus bigint,
  raw_redacted       jsonb,
  initiated_at       timestamptz NOT NULL DEFAULT now(),
  completed_at       timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), version integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_payments_target ON payments.payments(target_type, target_id);
CREATE INDEX ix_payments_pending ON payments.payments(initiated_at) WHERE status IN ('initiated','pending');
-- Hedef başına tek "geçerli" ödeme
CREATE UNIQUE INDEX uq_payment_single_effective ON payments.payments(target_type, target_id) WHERE status IN ('authorized','captured','partially_refunded');
CREATE TRIGGER trg_payments_ver BEFORE UPDATE ON payments.payments FOR EACH ROW EXECUTE FUNCTION core.bump_version();

CREATE TABLE payments.refunds (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), payment_id uuid NOT NULL REFERENCES payments.payments(id),
  amount_kurus bigint NOT NULL CHECK (amount_kurus > 0),
  kind text NOT NULL CHECK (kind IN ('void','refund')),
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','submitted','succeeded','failed')),
  reason text NOT NULL, provider_refund_id text, requested_by uuid NOT NULL, approved_by uuid,
  error text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), version integer NOT NULL DEFAULT 1
);
CREATE INDEX ix_refunds_payment ON payments.refunds(payment_id);
-- Toplam başarılı iade ödemeyi aşamaz (tetikleyici: refunds ekleme/güncelleme sonrası)
CREATE OR REPLACE FUNCTION payments.check_refund_total() RETURNS trigger AS $$
DECLARE paid bigint; refunded bigint;
BEGIN
  SELECT amount_kurus INTO paid FROM payments.payments WHERE id = NEW.payment_id FOR UPDATE;
  SELECT coalesce(sum(amount_kurus),0) INTO refunded FROM payments.refunds
   WHERE payment_id = NEW.payment_id AND status IN ('requested','submitted','succeeded') AND id <> NEW.id;
  IF NEW.status IN ('requested','submitted','succeeded') AND refunded + NEW.amount_kurus > paid THEN
    RAISE EXCEPTION 'İade toplamı ödemeyi aşamaz (ödeme %, iade %)', paid, refunded + NEW.amount_kurus USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_refund_total BEFORE INSERT OR UPDATE ON payments.refunds FOR EACH ROW EXECUTE FUNCTION payments.check_refund_total();

CREATE TABLE payments.webhook_events (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), provider text NOT NULL, event_id text NOT NULL,
  signature_valid boolean NOT NULL, headers_redacted jsonb, payload_redacted jsonb,
  received_at timestamptz NOT NULL DEFAULT now(), processed_at timestamptz, result text, error text,
  UNIQUE (provider, event_id)
);
CREATE TABLE payments.bank_transfers (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), payment_id uuid NOT NULL UNIQUE REFERENCES payments.payments(id),
  reference_code text NOT NULL UNIQUE, expected_kurus bigint NOT NULL, received_kurus bigint,
  confirmed_by uuid, confirmed_at timestamptz, bank_txn_ref text, sender_name text, note text, expires_at timestamptz NOT NULL
);
CREATE TABLE payments.cod_collections (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), payment_id uuid NOT NULL UNIQUE REFERENCES payments.payments(id),
  collector text NOT NULL CHECK (collector IN ('carrier','driver')), collected_by_ref uuid,
  method text CHECK (method IN ('cash','pos')), collected_at timestamptz, settled_at timestamptz, settlement_ref text
);
CREATE TABLE payments.cash_closings (            -- şoför/kasa günlük kapanış
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), closing_date date NOT NULL, collector_ref uuid NOT NULL,
  expected_kurus bigint NOT NULL, counted_kurus bigint NOT NULL, diff_kurus bigint GENERATED ALWAYS AS (counted_kurus - expected_kurus) STORED,
  approved_by uuid, note text, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (closing_date, collector_ref)
);
CREATE TABLE payments.ledger_entries (           -- değişmez, çift taraflı sade defter
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), business_unit text NOT NULL CHECK (business_unit IN ('shop','mill')),
  txn_id uuid NOT NULL, account text NOT NULL CHECK (account IN ('sales','shipping_income','tax_payable','discounts','refunds','receivable','cash','bank','provider_clearing','fees','in_kind')),
  debit_kurus bigint NOT NULL DEFAULT 0 CHECK (debit_kurus >= 0), credit_kurus bigint NOT NULL DEFAULT 0 CHECK (credit_kurus >= 0),
  ref_type text, ref_id uuid, memo text, at timestamptz NOT NULL DEFAULT now(),
  CHECK ((debit_kurus > 0) <> (credit_kurus > 0))
);
CREATE INDEX ix_ledger_txn ON payments.ledger_entries(txn_id);
CREATE INDEX ix_ledger_unit_acct ON payments.ledger_entries(business_unit, account, at);
CREATE TRIGGER trg_ledger_immut BEFORE UPDATE OR DELETE ON payments.ledger_entries FOR EACH ROW EXECUTE FUNCTION core.forbid_mutation();
-- Her txn_id için borç = alacak (kısıt tetikleyicisi, transaction sonunda)
CREATE OR REPLACE FUNCTION payments.check_txn_balanced() RETURNS trigger AS $$
DECLARE d bigint; c bigint;
BEGIN
  SELECT coalesce(sum(debit_kurus),0), coalesce(sum(credit_kurus),0) INTO d, c FROM payments.ledger_entries WHERE txn_id = NEW.txn_id;
  IF d <> c THEN RAISE EXCEPTION 'Defter dengesiz: txn %, borç %, alacak %', NEW.txn_id, d, c USING ERRCODE = '23514'; END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;
CREATE CONSTRAINT TRIGGER trg_ledger_balanced AFTER INSERT ON payments.ledger_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION payments.check_txn_balanced();
```

---

## 6. `0006_ops.sql`
```sql
-- migrate:up
CREATE TABLE ops.notification_templates (
  key text NOT NULL, channel text NOT NULL CHECK (channel IN ('sms','email','whatsapp')), locale text NOT NULL DEFAULT 'tr',
  version integer NOT NULL DEFAULT 1, subject text, body text NOT NULL, variables text[] NOT NULL DEFAULT '{}',
  is_active boolean NOT NULL DEFAULT true, kind text NOT NULL CHECK (kind IN ('transactional','marketing')),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (key, channel, locale, version)
);
CREATE TABLE ops.notification_preferences (
  customer_id uuid PRIMARY KEY, sms_transactional boolean NOT NULL DEFAULT true, email_transactional boolean NOT NULL DEFAULT true,
  sms_marketing boolean NOT NULL DEFAULT false, email_marketing boolean NOT NULL DEFAULT false, updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE ops.notifications (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), channel text NOT NULL, provider text, destination text NOT NULL,
  template_key text NOT NULL, template_version integer, rendered_body text, dedupe_key text,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sending','sent','delivered','failed','suppressed')),
  provider_message_id text, error text, cost_micro integer, segments smallint,
  related_type text, related_id uuid, queued_at timestamptz NOT NULL DEFAULT now(), sent_at timestamptz, delivered_at timestamptz,
  UNIQUE (dedupe_key)
);
CREATE INDEX ix_notifications_related ON ops.notifications(related_type, related_id);
CREATE INDEX ix_notifications_status ON ops.notifications(status, queued_at) WHERE status IN ('queued','sending','failed');

CREATE TABLE ops.invoices (
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), business_unit text NOT NULL CHECK (business_unit IN ('shop','mill')),
  target_type text NOT NULL, target_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('e_archive','e_invoice','credit_note','receipt','export_only')),
  number text UNIQUE, provider text, provider_ref text,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','issued','cancelled','failed')),
  buyer jsonb NOT NULL, lines jsonb NOT NULL, totals jsonb NOT NULL, pdf_document_id uuid, issued_at timestamptz, error text,
  created_at timestamptz NOT NULL DEFAULT now(), version integer NOT NULL DEFAULT 1
);
CREATE TABLE ops.outbound_webhooks (              -- E17
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), url text NOT NULL, secret_enc bytea NOT NULL, topics text[] NOT NULL, is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE ops.contact_messages (               -- iletişim formu (sunucuya kaydedilir; WhatsApp kopyası opsiyonel)
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), name text NOT NULL, phone text NOT NULL, subject text NOT NULL, est_amount text, message text,
  status text NOT NULL DEFAULT 'new' CHECK (status IN ('new','handled','spam')), consent_id uuid, ip inet, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE ops.content_pages (
  slug text PRIMARY KEY, title text NOT NULL, body_md text NOT NULL, kind text NOT NULL CHECK (kind IN ('legal','info','blog')),
  legal_version text, published_at timestamptz, updated_at timestamptz NOT NULL DEFAULT now(), version integer NOT NULL DEFAULT 1
);
CREATE TABLE ops.legal_versions (                 -- hangi metin hangi tarihte yürürlükte (sipariş kanıtı için)
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), doc_key text NOT NULL, version text NOT NULL, sha256 bytea NOT NULL, effective_from timestamptz NOT NULL, UNIQUE (doc_key, version)
);
CREATE TABLE ops.redirects (
  from_path text PRIMARY KEY, to_path text NOT NULL, status smallint NOT NULL DEFAULT 301 CHECK (status IN (301,302,308,410)), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE ops.jobs_failed_archive (            -- pg-boss başarısız işlerin insan okunur arşivi
  id uuid PRIMARY KEY DEFAULT core.uuidv7(), queue text NOT NULL, payload jsonb, error text, failed_at timestamptz NOT NULL DEFAULT now()
);
```

---

## 7. `0007_reporting_views_and_seed.sql`
```sql
-- migrate:up
-- Raporlama görünümleri: modüller arası okuma BURADAN yapılır (sözleşme). Ayrılırken yeniden yazılır.
CREATE VIEW reporting.daily_sales AS
SELECT date_trunc('day', placed_at AT TIME ZONE 'Europe/Istanbul')::date AS day,
       count(*) FILTER (WHERE status NOT IN ('cancelled','expired','pending_payment')) AS orders,
       sum(grand_total_kurus) FILTER (WHERE status IN ('paid','processing','packed','shipped','delivered')) AS gross_kurus
FROM shop.orders GROUP BY 1;

CREATE VIEW reporting.mill_pipeline AS
SELECT status, count(*) AS requests, sum(est_input_kg) AS est_kg FROM mill.requests GROUP BY status;

CREATE VIEW reporting.receivables AS
SELECT customer_ref, sum(amount_kurus) AS balance_kurus FROM mill.receivable_entries GROUP BY customer_ref HAVING sum(amount_kurus) <> 0;

-- Rol/izin tohumları
INSERT INTO core.roles(code, name, is_system) VALUES
 ('owner','Sahip',true),('manager','Yönetici',true),('packer','Paketleme',true),
 ('driver','Şoför',true),('support','Destek',true),('accountant','Muhasebe',true);

INSERT INTO core.permissions(code, description) VALUES
 ('catalog:read','Katalog görüntüle'),('catalog:write','Ürün/varyant/medya yönet'),('catalog:price','Fiyat değiştir'),
 ('stock:read','Stok görüntüle'),('stock:adjust','Stok düzelt'),
 ('orders:read','Sipariş görüntüle'),('orders:process','Sipariş durumu ilerlet'),('orders:cancel','Sipariş iptal'),('orders:refund','İade yap'),('orders:note','Not ekle'),
 ('payments:read','Ödeme görüntüle'),('payments:confirm_transfer','Havale onayla'),('payments:refund_large','Büyük iade onayı'),
 ('promotions:write','Kupon/promosyon yönet'),('claims:review','Gazi/şehit belgesi incele'),
 ('mill:read','Talep görüntüle'),('mill:approve','Talep onayla/reddet'),('mill:plan','Alım planla'),('mill:weigh','Tartı gir'),('mill:process','Değirmen işi yönet'),
 ('mill:price','Ücret/kapsama yönet'),('mill:charge_adjust','Ücret düzelt'),('mill:collect','Tahsilat işaretle'),('mill:receivable','Cari hesap yönet'),
 ('driver:self','Kendi alım listesi'),
 ('customers:read','Müşteri görüntüle'),('customers:privacy','KVKK dışa aktarım/silme'),('customers:merge','Müşteri birleştir'),
 ('reports:read','Rapor görüntüle'),('reports:export','Rapor dışa aktar'),
 ('settings:write','Ayar değiştir'),('staff:manage','Personel yönet'),('audit:read','Denetim kaydı oku'),('content:write','İçerik yönet'),('invoices:manage','Fatura yönet');

INSERT INTO core.role_permissions(role_code, permission)
SELECT 'owner', code FROM core.permissions;
INSERT INTO core.role_permissions(role_code, permission) VALUES
 ('manager','catalog:read'),('manager','catalog:write'),('manager','catalog:price'),('manager','stock:read'),('manager','stock:adjust'),
 ('manager','orders:read'),('manager','orders:process'),('manager','orders:cancel'),('manager','orders:refund'),('manager','orders:note'),
 ('manager','payments:read'),('manager','payments:confirm_transfer'),('manager','promotions:write'),('manager','claims:review'),
 ('manager','mill:read'),('manager','mill:approve'),('manager','mill:plan'),('manager','mill:weigh'),('manager','mill:process'),('manager','mill:price'),('manager','mill:charge_adjust'),('manager','mill:collect'),
 ('manager','customers:read'),('manager','reports:read'),('manager','content:write'),
 ('packer','orders:read'),('packer','orders:process'),('packer','stock:read'),('packer','orders:note'),
 ('driver','driver:self'),('driver','mill:weigh'),('driver','mill:collect'),
 ('support','orders:read'),('support','orders:note'),('support','customers:read'),('support','mill:read'),
 ('accountant','orders:read'),('accountant','payments:read'),('accountant','reports:read'),('accountant','reports:export'),('accountant','invoices:manage');

INSERT INTO core.tax_classes(code,name,note) VALUES
 ('food_default','Gıda ürünleri (varsayılan)','Oran mali müşavirle teyit edilmeden yayına çıkılmaz'),
 ('service_default','Hizmet (değirmen)','Oran mali müşavirle teyit edilmeden yayına çıkılmaz');
-- NOT: tax_rates satırları BİLEREK eklenmedi; müşavir teyidi sonrası yönetim panelinden girilir. Oran yoksa ürün yayınlanamaz (uygulama kuralı).

INSERT INTO shop.stock_locations(code, name, is_default) VALUES ('main','Ana depo',true);

INSERT INTO core.settings(key, value) VALUES
 ('shop.free_shipping_threshold_kurus','75000'),
 ('shop.reservation_ttl_minutes','15'),
 ('shop.bank_transfer_discount_bp','500'),
 ('shop.bank_transfer_ttl_hours','48'),
 ('shop.cod_enabled','true'),
 ('shop.cod_fee_kurus','0'),
 ('shop.cod_max_order_kurus','500000'),
 ('shop.packaging_weight_g','150'),
 ('shop.cutoff_hour','14'),
 ('mill.estimate_variance_confirm_bp','1000'),
 ('mill.weigh_diff_alert_bp','100'),
 ('mill.yield_alert_low_bp','3500'),
 ('mill.yield_alert_high_bp','6500'),
 ('mill.default_bag_tare_g','200'),
 ('mill.pickup_code_ttl_hours','48'),
 ('mill.max_open_requests_per_customer','3'),
 ('discount.gazi_rate_bp','2000'),
 ('otp.ttl_seconds','300'),('otp.max_attempts','5'),('otp.per_phone_per_hour','5'),
 ('shop.reorder_nudge_days','0');
```

---

## 8. Değişmezlik ve bütünlük özeti (CI'da doğrulanır)
| Tablo | Koruma |
|---|---|
| `core.audit_log`, `core.acknowledgements`, `core.consent_log`, `core.credit_entries`, `core.customer_merge_log` | UPDATE/DELETE yasak |
| `shop.stock_ledger`, `shop.order_events` | UPDATE/DELETE yasak |
| `mill.weighings`, `mill.charges`, `mill.events`, `mill.receivable_entries`, `mill.inventory_movements` | UPDATE/DELETE yasak |
| `payments.ledger_entries` | UPDATE/DELETE yasak + borç=alacak (ertelenmiş kısıt) |
| `payments.refunds` | toplam ≤ ödeme (tetikleyici) |
| `payments.payments` | hedef başına tek geçerli ödeme (kısmi benzersiz indeks) |
| `shop.orders` | `grand_total = items − discount + shipping + cod_fee` CHECK |
| `shop.order_items` | `net + tax = gross`, `gross = unit×qty − discount` CHECK |
| `mill.charges` | `net + tax = amount` CHECK |
| `mill.weighings` | `net = gross − tare` CHECK |
| `shop.stock_levels` | `available >= 0` (negatif stok imkânsız) |

## 9. Gece uyum denetimi (`ops` işi `integrity.nightly`)
Veritabanı kısıtlarının yakalayamadığı çapraz-şema kontroller, ihlal → uyarı + `audit_log`:
1. `payments.payments` → hedef sipariş/talep gerçekten var mı (yetim ödeme yok).
2. Her `captured` ödemenin siparişinin `paid_at` dolu ve tutarı eşit mi.
3. `stock_levels.on_hand` = Σ `stock_ledger.delta` (lokasyon+varyant bazında).
4. `stock_levels.reserved` = Σ aktif rezervasyonlar.
5. `mill.requests` kesin ücret = Σ `charges(phase='final')` ve ödeme toplamı.
6. `receivable_entries` toplamı ile hesap bakiyesi tutarlı; negatif bakiye (fazla tahsilat) uyarısı.
7. Yetim `core.documents` (sahipsiz) ve süresi dolan `retain_until` belgeler.
8. Yumuşak referans: `mill.requests.customer_ref` → `core.customers` var mı.
9. Belge numarası boşluk testi (`doc_sequences` ↔ gerçek numaralar).
10. Dönem sonu: `ledger_entries` hesap bazlı toplamları ↔ sipariş/ödeme toplamları.

## 10. Göç yazım kuralları (özet; ayrıntı 12 §5, 17-runbook)
- Her göç **tek amaçlı**, küçük, geri alınabilir (`down`), kilit süresi analizli.
- Tablo yeniden yazan değişiklik yok: yeni sütun → doldur → kısıt (`NOT VALID` + `VALIDATE`) → eski sütun kaldır (ayrı sürüm).
- İndeks: `CREATE INDEX CONCURRENTLY` (ayrı `-- migrate:up transaction:false` göç dosyası).
- Veri göçü ayrı dosya, partiler halinde; büyük tabloda uygulama içi arka plan işi.
- Tohum veri (roller/izinler/ayarlar) göçle; **ürün/fiyat gibi iş verisi göçle değil**, yönetim aracı/CSV ile.

## 11. Kasıtlı olarak yapılmayan şeyler (ve nedeni)
| Yapılmadı | Neden | Eklemek gerekirse |
|---|---|---|
| `store_id` / çoklu mağaza | V1 varsayımı (tek işletme) | S15 (2–4 hafta); şu an YAGNI |
| Satır düzeyi güvenlik (RLS) | Erişim uygulama katmanında, tek DB kullanıcısı; RLS yönetimi karmaşıklığı | Hassas tablolar için sonra eklenebilir (yamasız: yalnız politika ekleme) |
| Bölümleme (partition) | Hacim küçük (12 §9) | `audit_log`, `notifications` aylık bölümleme, göçle |
| Olay kaynağı | Karmaşıklık; `events` + outbox yeterli | — |
| Uygulama tarafı şifreleme tüm PII | Aşırı; yalnız TOTP sırrı + ödeme `raw` redakte | Gerekirse belirli sütunlar (`pgcrypto`/KMS) |

