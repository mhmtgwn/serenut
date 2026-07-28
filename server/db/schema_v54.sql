-- Canonical device runtime model.
-- `devices`, `device_app_versions` and `update_download_logs` remain historical
-- records only. New runtime traffic is keyed by a licensed device activation.

ALTER TABLE device_activations
  ADD COLUMN IF NOT EXISTS store_id VARCHAR(100) REFERENCES stores(id) ON DELETE SET NULL;

ALTER TABLE device_activations
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- A company may have historical revoked activations for the same installation,
-- but exactly one active activation is allowed. Retain the newest one and make
-- the old records explicitly revoked instead of deleting audit evidence.
WITH ranked_active AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY company_id, device_hash
           ORDER BY last_seen_at DESC NULLS LAST, activated_at DESC, id DESC
         ) AS row_number
  FROM device_activations
  WHERE status = 'active'
)
UPDATE device_activations activation
SET status = 'revoked',
    revoked_at = COALESCE(activation.revoked_at, CURRENT_TIMESTAMP),
    revoked_by = COALESCE(activation.revoked_by, 'canonical-device-migration'),
    updated_at = CURRENT_TIMESTAMP
FROM ranked_active ranked
WHERE activation.id = ranked.id
  AND ranked.row_number > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_device_activations_active_company_hash
  ON device_activations (company_id, device_hash)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_device_activations_company_last_seen
  ON device_activations (company_id, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS device_runtime_state (
  device_activation_id VARCHAR(100) PRIMARY KEY REFERENCES device_activations(id) ON DELETE CASCADE,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  platform VARCHAR(50) NOT NULL,
  current_version VARCHAR(50) NOT NULL,
  channel VARCHAR(50) NOT NULL DEFAULT 'stable',
  last_reported_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_sync_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_device_runtime_state_company_platform
  ON device_runtime_state (company_id, platform, last_reported_at DESC);

CREATE TABLE IF NOT EXISTS device_update_downloads (
  id VARCHAR(100) PRIMARY KEY,
  release_id VARCHAR(100) NOT NULL REFERENCES app_versions(id) ON DELETE RESTRICT,
  device_activation_id VARCHAR(100) REFERENCES device_activations(id) ON DELETE SET NULL,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  status VARCHAR(50) NOT NULL DEFAULT 'started',
  started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMPTZ,
  error_message TEXT
);

CREATE INDEX IF NOT EXISTS idx_device_update_downloads_company_started
  ON device_update_downloads (company_id, started_at DESC);

-- Keep the original device_id column as historical installation evidence, but
-- bind every new replication event to the authorized activation record.
ALTER TABLE sync_v4_changes
  ADD COLUMN IF NOT EXISTS device_activation_id VARCHAR(100)
  REFERENCES device_activations(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_sync_v4_changes_activation
  ON sync_v4_changes (device_activation_id, revision DESC);

ALTER TABLE device_runtime_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_runtime_state FORCE ROW LEVEL SECURITY;
ALTER TABLE device_update_downloads ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_update_downloads FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_isolation ON device_runtime_state;
CREATE POLICY tenant_isolation ON device_runtime_state
  FOR ALL
  USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
  WITH CHECK (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON device_update_downloads;
CREATE POLICY tenant_isolation ON device_update_downloads
  FOR ALL
  USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
  WITH CHECK (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

-- Carry forward only records that can be matched unambiguously to the active
-- activation. Unmatched legacy rows remain readable as archive data.
INSERT INTO device_runtime_state (
  device_activation_id, company_id, platform, current_version, channel, last_reported_at, updated_at
)
SELECT activation.id,
       activation.company_id,
       legacy.platform,
       legacy.current_version,
       legacy.channel,
       legacy.last_reported_at,
       CURRENT_TIMESTAMP
FROM device_app_versions legacy
JOIN devices legacy_device
  ON legacy_device.id = legacy.device_id
JOIN device_activations activation
  ON activation.company_id = legacy_device.company_id
 AND activation.device_hash = legacy_device.device_hash
 AND activation.status = 'active'
ON CONFLICT (device_activation_id) DO NOTHING;
