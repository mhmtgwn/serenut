-- PostgreSQL schema v11 — Faz 3: OTA Release Management
-- Sprint 3.2 — Admin Tenant Operations & OTA Rollout Configuration

-- app_releases: OTA rollout konfigürasyonu için tam lifecycle tablosu
CREATE TABLE IF NOT EXISTS app_releases (
    id VARCHAR(100) PRIMARY KEY,
    version VARCHAR(50) NOT NULL,
    channel VARCHAR(50) DEFAULT 'stable',    -- 'stable', 'beta', 'canary'
    platform VARCHAR(50) DEFAULT 'android',  -- 'android', 'windows', 'all'
    download_url VARCHAR(500),
    sha256_hash VARCHAR(64),
    rollout_percentage INTEGER DEFAULT 0 CHECK (rollout_percentage >= 0 AND rollout_percentage <= 100),
    is_mandatory BOOLEAN DEFAULT FALSE,
    status VARCHAR(50) DEFAULT 'draft',      -- 'draft', 'active', 'rolled_back', 'deprecated'
    release_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_app_releases_channel_status ON app_releases (channel, status);
CREATE INDEX IF NOT EXISTS idx_app_releases_created_at ON app_releases (created_at);

-- RLS
ALTER TABLE app_releases ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_releases FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_isolation ON app_releases;
CREATE POLICY tenant_isolation ON app_releases FOR ALL USING (
    current_setting('app.bypass_rls', true) = 'true'
);
