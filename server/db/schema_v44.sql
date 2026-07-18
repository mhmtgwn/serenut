CREATE TABLE IF NOT EXISTS client_telemetry_events (
  id BIGSERIAL PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  user_id VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
  metric_name VARCHAR(120) NOT NULL,
  metric_value DOUBLE PRECISION NOT NULL DEFAULT 1,
  occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address VARCHAR(100),
  user_agent VARCHAR(500),
  received_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_client_telemetry_company_time
  ON client_telemetry_events(company_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_client_telemetry_metric_time
  ON client_telemetry_events(metric_name, occurred_at DESC);

ALTER TABLE client_telemetry_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE client_telemetry_events FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON client_telemetry_events;
CREATE POLICY tenant_isolation ON client_telemetry_events FOR ALL USING (
  company_id = current_tenant_id()
  OR current_setting('app.bypass_rls', true) = 'true'
);
