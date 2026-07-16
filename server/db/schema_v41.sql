CREATE TABLE IF NOT EXISTS company_sms_gateways (
  company_id VARCHAR(100) PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
  device_activation_id VARCHAR(100) NOT NULL REFERENCES device_activations(id) ON DELETE CASCADE,
  selected_by VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
  selected_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  last_poll_at TIMESTAMP WITH TIME ZONE
);

ALTER TABLE notification_queue ADD COLUMN IF NOT EXISTS gateway_device_id VARCHAR(100);
ALTER TABLE notification_queue ADD COLUMN IF NOT EXISTS gateway_claimed_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE notification_queue ADD COLUMN IF NOT EXISTS gateway_updated_at TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_sms_gateway_pending
  ON notification_queue(company_id, scheduled_at, created_at)
  WHERE channel = 'sms' AND status IN ('queued', 'pending', 'retrying');
