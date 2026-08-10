-- Mailbox trash is a recoverable delete. Messages remain available until a
-- future audited retention job permanently removes them.
ALTER TABLE admin_mail_messages
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_admin_mail_messages_deleted_at
  ON admin_mail_messages (deleted_at)
  WHERE deleted_at IS NOT NULL;
