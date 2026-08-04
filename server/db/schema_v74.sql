CREATE TABLE IF NOT EXISTS notification_credit_reservations (
  notification_id VARCHAR(100) PRIMARY KEY REFERENCES notification_queue(id) ON DELETE RESTRICT,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  channel VARCHAR(20) NOT NULL CHECK(channel IN ('sms','email','whatsapp')),
  status VARCHAR(20) NOT NULL DEFAULT 'reserved' CHECK(status IN ('reserved','consumed','released')),
  reserved_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  consumed_at TIMESTAMP WITH TIME ZONE,
  released_at TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS idx_notification_credit_reservations_company_status
  ON notification_credit_reservations(company_id,status);
ALTER TABLE notification_credit_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_credit_reservations FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON notification_credit_reservations;
CREATE POLICY tenant_isolation ON notification_credit_reservations FOR ALL USING(
  company_id=current_tenant_id() OR current_setting('app.bypass_rls',true)='true'
);
