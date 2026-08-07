-- Serenut shared hardware: tenant-scoped registry and durable remote job queue.
CREATE TABLE IF NOT EXISTS shared_hardware (
  id TEXT PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  owner_activation_id VARCHAR(100) NOT NULL REFERENCES device_activations(id) ON DELETE CASCADE,
  owner_device_id TEXT NOT NULL,
  name VARCHAR(160) NOT NULL,
  hardware_type VARCHAR(40) NOT NULL CHECK (hardware_type IN
    ('receiptPrinter','labelPrinter','scale','paymentTerminal','barcodeScanner','customerDisplay')),
  connection_type VARCHAR(32) NOT NULL,
  language VARCHAR(24),
  configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
  capabilities JSONB NOT NULL DEFAULT '{}'::jsonb,
  sharing_scope VARCHAR(24) NOT NULL DEFAULT 'company' CHECK (sharing_scope IN ('owner','branch','company')),
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  online BOOLEAN NOT NULL DEFAULT TRUE,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(company_id, owner_activation_id, id)
);

CREATE INDEX IF NOT EXISTS idx_shared_hardware_company
  ON shared_hardware(company_id, enabled, hardware_type);
CREATE INDEX IF NOT EXISTS idx_shared_hardware_owner
  ON shared_hardware(company_id, owner_activation_id, online);

CREATE TABLE IF NOT EXISTS hardware_jobs (
  id UUID PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  hardware_id TEXT NOT NULL REFERENCES shared_hardware(id) ON DELETE RESTRICT,
  owner_activation_id VARCHAR(100) NOT NULL REFERENCES device_activations(id) ON DELETE RESTRICT,
  requested_by_activation_id VARCHAR(100) NOT NULL REFERENCES device_activations(id) ON DELETE RESTRICT,
  requested_by_user_id VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
  operation VARCHAR(48) NOT NULL CHECK (operation IN ('printReceipt','printProductLabel','printOrderLabel','testPrint')),
  payload JSONB NOT NULL,
  idempotency_key VARCHAR(180) NOT NULL,
  state VARCHAR(32) NOT NULL DEFAULT 'queued' CHECK (state IN
    ('queued','claimed','executing','retry_wait','succeeded','failed','requires_confirmation','cancelled')),
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0 AND attempt_count <= 20),
  lease_owner TEXT,
  lease_expires_at TIMESTAMPTZ,
  next_attempt_at TIMESTAMPTZ,
  result JSONB,
  error_code VARCHAR(80),
  error_message VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  UNIQUE(company_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_hardware_jobs_claim
  ON hardware_jobs(company_id, owner_activation_id, state, next_attempt_at, created_at);
CREATE INDEX IF NOT EXISTS idx_hardware_jobs_requester
  ON hardware_jobs(company_id, requested_by_activation_id, created_at DESC);

ALTER TABLE shared_hardware ENABLE ROW LEVEL SECURITY;
ALTER TABLE hardware_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared_hardware FORCE ROW LEVEL SECURITY;
ALTER TABLE hardware_jobs FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS shared_hardware_tenant_isolation ON shared_hardware;
CREATE POLICY shared_hardware_tenant_isolation ON shared_hardware
  USING (company_id = NULLIF(current_setting('app.current_company_id', true), ''))
  WITH CHECK (company_id = NULLIF(current_setting('app.current_company_id', true), ''));

DROP POLICY IF EXISTS hardware_jobs_tenant_isolation ON hardware_jobs;
CREATE POLICY hardware_jobs_tenant_isolation ON hardware_jobs
  USING (company_id = NULLIF(current_setting('app.current_company_id', true), ''))
  WITH CHECK (company_id = NULLIF(current_setting('app.current_company_id', true), ''));

UPDATE remote_configs
SET value = value || '{"shared_hardware_enabled": true}'::jsonb,
    updated_at = NOW()
WHERE key = 'global_config';
