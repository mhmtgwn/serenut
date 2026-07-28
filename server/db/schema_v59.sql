CREATE TABLE IF NOT EXISTS subscription_overrides (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL UNIQUE REFERENCES companies(id) ON DELETE CASCADE,
  base_plan_id VARCHAR(100) NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
  custom_price DECIMAL(12,2),
  billing_interval VARCHAR(20) CHECK (billing_interval IN ('monthly','yearly')),
  user_limit INTEGER CHECK (user_limit > 0),
  store_limit INTEGER CHECK (store_limit > 0),
  device_limit INTEGER CHECK (device_limit > 0),
  feature_overrides JSONB NOT NULL DEFAULT '{}'::jsonb,
  valid_from TIMESTAMPTZ NOT NULL,
  valid_until TIMESTAMPTZ NOT NULL,
  auto_renew BOOLEAN NOT NULL DEFAULT FALSE,
  reason TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (valid_until > valid_from)
);
CREATE INDEX IF NOT EXISTS idx_subscription_overrides_active ON subscription_overrides(company_id, valid_from, valid_until) WHERE is_active = TRUE;
ALTER TABLE subscription_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription_overrides FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON subscription_overrides;
CREATE POLICY tenant_isolation ON subscription_overrides FOR ALL
  USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
  WITH CHECK (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');
