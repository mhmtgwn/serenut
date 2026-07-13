-- PostgreSQL schema v3 migrations for Serenut POS SaaS backend
-- Release Management Platform: multi-channel distribution, targeting, rollout, tracking

-- 1. Extend app_versions with release management fields
ALTER TABLE app_versions ADD COLUMN IF NOT EXISTS channel VARCHAR(50) DEFAULT 'stable';
  -- Values: 'stable', 'beta', 'alpha', 'nightly', 'internal'

ALTER TABLE app_versions ADD COLUMN IF NOT EXISTS rollout_percentage INTEGER DEFAULT 100;
  -- 0-100, used for progressive rollout

ALTER TABLE app_versions ADD COLUMN IF NOT EXISTS min_required_version VARCHAR(50);
  -- Devices below this version will receive force update

ALTER TABLE app_versions ADD COLUMN IF NOT EXISTS file_path VARCHAR(500);
  -- Physical file path on VPS e.g. /var/www/serenut-api/releases/android/stable/1.5.0.apk

ALTER TABLE app_versions ADD COLUMN IF NOT EXISTS file_size_bytes BIGINT;
  -- Actual file size in bytes for Flutter download progress

ALTER TABLE app_versions ADD COLUMN IF NOT EXISTS digital_signature TEXT;
  -- Ed25519 signature (reserved for future use)

ALTER TABLE app_versions ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'active';
  -- 'draft', 'active', 'yanked', 'rollback'

ALTER TABLE app_versions ADD COLUMN IF NOT EXISTS yanked_reason TEXT;
  -- Reason for emergency withdrawal

ALTER TABLE app_versions ADD COLUMN IF NOT EXISTS published_by VARCHAR(100);
  -- Admin user ID who published this version

ALTER TABLE app_versions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- 2. Update Targets (fine-grained targeting)
-- Maps a release to specific companies / license tiers / devices
-- If no targets exist for a release, it is public (all devices)
CREATE TABLE IF NOT EXISTS update_targets (
    id VARCHAR(100) PRIMARY KEY,
    release_id VARCHAR(100) REFERENCES app_versions(id) ON DELETE CASCADE,
    target_type VARCHAR(50) NOT NULL, -- 'company', 'license_tier', 'device'
    target_value VARCHAR(100) NOT NULL, -- company_id | 'trial'|'pro'|'pro_plus' | device_id
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_update_targets_release ON update_targets(release_id);

-- 3. Update Download Logs
-- Track every download attempt per device
CREATE TABLE IF NOT EXISTS update_download_logs (
    id VARCHAR(100) PRIMARY KEY,
    release_id VARCHAR(100) REFERENCES app_versions(id) ON DELETE SET NULL,
    device_id VARCHAR(100) REFERENCES devices(id) ON DELETE SET NULL,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE SET NULL,
    status VARCHAR(50) DEFAULT 'started', -- 'started', 'completed', 'failed', 'verified', 'verification_failed'
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_download_logs_release ON update_download_logs(release_id);
CREATE INDEX IF NOT EXISTS idx_download_logs_device ON update_download_logs(device_id);

-- 4. Device App Versions
-- Track which app version each device is currently running
-- Updated via /api/v1/releases/report-version (called on app startup)
CREATE TABLE IF NOT EXISTS device_app_versions (
    device_id VARCHAR(100) PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    platform VARCHAR(50) NOT NULL,
    current_version VARCHAR(50) NOT NULL,
    channel VARCHAR(50) DEFAULT 'stable',
    last_reported_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. Drop old unique constraint on version_code+platform if exists, to allow multi-channel
-- (Same version_code can exist in beta and stable with different rollout)
ALTER TABLE app_versions DROP CONSTRAINT IF EXISTS app_versions_version_code_key;
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_versions_unique_channel 
    ON app_versions (version_code, platform, channel);
