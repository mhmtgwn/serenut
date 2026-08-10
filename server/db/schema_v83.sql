-- Admin mailbox backed by Resend inbound and outbound APIs.
CREATE TABLE IF NOT EXISTS admin_mail_messages (
  id VARCHAR(100) PRIMARY KEY,
  resend_email_id VARCHAR(180) UNIQUE,
  direction VARCHAR(16) NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  mailbox VARCHAR(320) NOT NULL DEFAULT 'destek@serenut.com',
  sender_email VARCHAR(320) NOT NULL,
  sender_name VARCHAR(200),
  recipients JSONB NOT NULL DEFAULT '[]'::jsonb,
  cc JSONB NOT NULL DEFAULT '[]'::jsonb,
  bcc JSONB NOT NULL DEFAULT '[]'::jsonb,
  subject VARCHAR(500) NOT NULL,
  text_body TEXT NOT NULL DEFAULT '',
  html_body TEXT,
  message_id VARCHAR(500),
  in_reply_to VARCHAR(500),
  thread_key VARCHAR(500),
  attachment_metadata JSONB NOT NULL DEFAULT '[]'::jsonb,
  delivery_status VARCHAR(32) NOT NULL DEFAULT 'received',
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  is_archived BOOLEAN NOT NULL DEFAULT FALSE,
  guest_request_id VARCHAR(100) REFERENCES guest_support_requests(id) ON DELETE SET NULL,
  created_by VARCHAR(100),
  sent_at TIMESTAMPTZ,
  received_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE admin_mail_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_mail_messages FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_mail_messages_sysadmin_only ON admin_mail_messages;
CREATE POLICY admin_mail_messages_sysadmin_only ON admin_mail_messages
  FOR ALL USING (current_setting('app.bypass_rls', true) = 'true')
  WITH CHECK (current_setting('app.bypass_rls', true) = 'true');

CREATE INDEX IF NOT EXISTS idx_admin_mail_folder
  ON admin_mail_messages(direction, is_archived, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_mail_thread
  ON admin_mail_messages(thread_key, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_admin_mail_unread
  ON admin_mail_messages(is_read, created_at DESC) WHERE direction = 'inbound';
