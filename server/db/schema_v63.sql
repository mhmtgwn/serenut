-- Attribute notification history to the user who created the message.
-- This prevents tenant users from reading one another's SMS history.
ALTER TABLE notification_queue
  ADD COLUMN IF NOT EXISTS created_by_user_id VARCHAR(100)
  REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_notification_queue_company_user_created
  ON notification_queue (company_id, created_by_user_id, created_at DESC);
