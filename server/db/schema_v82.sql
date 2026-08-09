-- Resend inbound email webhook persistence and replay protection.
CREATE TABLE IF NOT EXISTS resend_inbound_events (
  event_id VARCHAR(180) PRIMARY KEY,
  email_id VARCHAR(180) NOT NULL UNIQUE,
  sender_email VARCHAR(320),
  recipients JSONB NOT NULL DEFAULT '[]'::jsonb,
  subject VARCHAR(500),
  message_id VARCHAR(500),
  attachment_metadata JSONB NOT NULL DEFAULT '[]'::jsonb,
  guest_request_id VARCHAR(100) REFERENCES guest_support_requests(id) ON DELETE SET NULL,
  received_at TIMESTAMPTZ,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE resend_inbound_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE resend_inbound_events FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS resend_inbound_events_admin_only ON resend_inbound_events;
CREATE POLICY resend_inbound_events_admin_only ON resend_inbound_events
  FOR ALL USING (current_setting('app.bypass_rls', true) = 'true')
  WITH CHECK (current_setting('app.bypass_rls', true) = 'true');

CREATE INDEX IF NOT EXISTS idx_resend_inbound_events_created
  ON resend_inbound_events(created_at DESC);
