CREATE TABLE IF NOT EXISTS device_hardware_profiles (
  device_activation_id VARCHAR(100) PRIMARY KEY
    REFERENCES device_activations(id) ON DELETE CASCADE,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  profile JSONB NOT NULL DEFAULT '[]'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_hardware_profiles_company
  ON device_hardware_profiles(company_id, updated_at DESC);

ALTER TABLE device_hardware_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_hardware_profiles FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON device_hardware_profiles;
CREATE POLICY tenant_isolation ON device_hardware_profiles
  USING (company_id = current_setting('app.current_company_id', true))
  WITH CHECK (company_id = current_setting('app.current_company_id', true));
