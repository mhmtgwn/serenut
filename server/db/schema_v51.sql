-- server/db/schema_v51.sql
-- Phase-1 Release Management Platform (Sprint 2B)

CREATE TABLE IF NOT EXISTS release_channels (
    name VARCHAR(32) PRIMARY KEY
);

INSERT INTO release_channels (name) VALUES ('stable'), ('beta'), ('rc') ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS releases (
    release_id VARCHAR(64) PRIMARY KEY,
    version_code VARCHAR(32) NOT NULL,
    channel VARCHAR(32) NOT NULL REFERENCES release_channels(name),
    current_state VARCHAR(32) NOT NULL DEFAULT 'draft',
    manifest_sha256 CHAR(64),
    manifest_signature TEXT,
    build_commit VARCHAR(64),
    build_pipeline_id VARCHAR(64),
    artifact_set_hash CHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS release_artifacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    release_id VARCHAR(64) NOT NULL REFERENCES releases(release_id) ON DELETE CASCADE,
    type VARCHAR(64) NOT NULL,
    filename VARCHAR(255) NOT NULL,
    download_url TEXT NOT NULL,
    size_bytes BIGINT NOT NULL,
    sha256 CHAR(64) NOT NULL,
    signature TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS release_promotions (
    release_id VARCHAR(64) PRIMARY KEY REFERENCES releases(release_id) ON DELETE CASCADE,
    rollout_percentage INTEGER NOT NULL DEFAULT 100,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS release_health_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    release_id VARCHAR(64) NOT NULL REFERENCES releases(release_id) ON DELETE CASCADE,
    rollout_percent INTEGER NOT NULL,
    devices INTEGER NOT NULL DEFAULT 0,
    success_rate NUMERIC(5,2) NOT NULL,
    rollback_rate NUMERIC(5,2) NOT NULL,
    crash_rate NUMERIC(5,2) NOT NULL,
    health_score NUMERIC(5,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS release_audit (
    id BIGSERIAL PRIMARY KEY,
    release_id VARCHAR(64) NOT NULL,
    actor_id VARCHAR(64) NOT NULL,
    action VARCHAR(32) NOT NULL,
    from_state VARCHAR(32),
    to_state VARCHAR(32),
    payload JSONB,
    previous_record_hash CHAR(64),
    record_hash CHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS release_transition_guards (
    id SERIAL PRIMARY KEY,
    from_state VARCHAR(32) NOT NULL,
    to_state VARCHAR(32) NOT NULL,
    requires_signature BOOLEAN NOT NULL DEFAULT FALSE,
    requires_canary_health BOOLEAN NOT NULL DEFAULT FALSE,
    requires_admin BOOLEAN NOT NULL DEFAULT TRUE
);

-- Seed transition guards
INSERT INTO release_transition_guards (from_state, to_state, requires_signature, requires_canary_health, requires_admin)
VALUES 
  ('draft', 'built', FALSE, FALSE, TRUE),
  ('built', 'signed', TRUE, FALSE, TRUE),
  ('signed', 'verified', FALSE, FALSE, TRUE),
  ('verified', 'candidate', FALSE, FALSE, TRUE),
  ('candidate', 'canary', FALSE, FALSE, TRUE),
  ('canary', 'stable', FALSE, TRUE, TRUE),
  ('canary', 'yanked', FALSE, FALSE, TRUE),
  ('stable', 'deprecated', FALSE, FALSE, TRUE),
  ('stable', 'yanked', FALSE, FALSE, TRUE),
  ('deprecated', 'archived', FALSE, FALSE, TRUE),
  ('yanked', 'archived', FALSE, FALSE, TRUE)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS release_manifest_store (
    release_id VARCHAR(64) PRIMARY KEY REFERENCES releases(release_id) ON DELETE CASCADE,
    canonical_manifest_json TEXT NOT NULL,
    manifest_sha256 CHAR(64) NOT NULL,
    manifest_signature TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
