-- Company-owned WhatsApp Business connections and durable provider metadata.
-- Credentials are encrypted by the application before they reach PostgreSQL.

CREATE TABLE IF NOT EXISTS company_whatsapp_connections (
  company_id VARCHAR(100) PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
  meta_business_id VARCHAR(100),
  waba_id VARCHAR(100) NOT NULL,
  phone_number_id VARCHAR(100) NOT NULL,
  display_phone_number VARCHAR(50),
  business_display_name VARCHAR(255),
  encrypted_access_token TEXT NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','connecting','reauthorization_required','disabled','disconnected','error')),
  connected_by_user_id VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
  connected_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  last_verified_at TIMESTAMP WITH TIME ZONE,
  disconnected_at TIMESTAMP WITH TIME ZONE,
  last_error_code VARCHAR(100),
  last_error_message TEXT,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_whatsapp_phone_number
  ON company_whatsapp_connections(phone_number_id)
  WHERE status <> 'disconnected';

CREATE TABLE IF NOT EXISTS whatsapp_onboarding_sessions (
  state_hash CHAR(64) PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  created_by_user_id VARCHAR(100) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  consumed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_whatsapp_onboarding_expiry
  ON whatsapp_onboarding_sessions(expires_at)
  WHERE consumed_at IS NULL;

CREATE TABLE IF NOT EXISTS company_whatsapp_templates (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  event_key VARCHAR(100) NOT NULL,
  meta_template_name VARCHAR(512) NOT NULL,
  language_code VARCHAR(20) NOT NULL DEFAULT 'tr',
  category VARCHAR(32) NOT NULL DEFAULT 'UTILITY',
  status VARCHAR(32) NOT NULL DEFAULT 'pending',
  rejection_reason TEXT,
  last_synced_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_company_whatsapp_event UNIQUE(company_id, event_key)
);

ALTER TABLE notification_queue
  ADD COLUMN IF NOT EXISTS provider_message_id VARCHAR(255),
  ADD COLUMN IF NOT EXISTS provider_payload JSONB,
  ADD COLUMN IF NOT EXISTS provider_status VARCHAR(50),
  ADD COLUMN IF NOT EXISTS provider_error_code VARCHAR(100);

CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_provider_message
  ON notification_queue(provider_message_id)
  WHERE provider_message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notification_whatsapp_delivery
  ON notification_queue(company_id, provider_status, created_at DESC)
  WHERE channel = 'whatsapp';

INSERT INTO permissions(id,code,description) VALUES
  (gen_random_uuid()::text,'notifications.channels.manage','SMS ve WhatsApp bildirim kanallarını bağlama ve yönetme')
ON CONFLICT(code) DO NOTHING;

INSERT INTO role_permissions(role_id,permission_id)
SELECT r.id,p.id FROM roles r,permissions p
WHERE r.name IN ('owner','admin','sysadmin') AND p.code='notifications.channels.manage'
ON CONFLICT DO NOTHING;

ALTER TABLE company_whatsapp_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_whatsapp_connections FORCE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_onboarding_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_onboarding_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE company_whatsapp_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_whatsapp_templates FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_isolation ON company_whatsapp_connections;
CREATE POLICY tenant_isolation ON company_whatsapp_connections FOR ALL
  USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
  WITH CHECK (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON whatsapp_onboarding_sessions;
CREATE POLICY tenant_isolation ON whatsapp_onboarding_sessions FOR ALL
  USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
  WITH CHECK (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON company_whatsapp_templates;
CREATE POLICY tenant_isolation ON company_whatsapp_templates FOR ALL
  USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
  WITH CHECK (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');
