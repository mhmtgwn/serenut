-- PostgreSQL schema v6 migrations for Serenut OS SaaS backend
-- Notification Platform: templates, central message queue and credits tracking

-- 1. Notification Templates Table
CREATE TABLE IF NOT EXISTS notification_templates (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    channel VARCHAR(50) NOT NULL, -- 'sms', 'email', 'push', 'whatsapp'
    title VARCHAR(255),
    body TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_company_template_name UNIQUE (company_id, name)
);

-- 2. Notification Queue Table (SKIP LOCKED safe)
CREATE TABLE IF NOT EXISTS notification_queue (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    channel VARCHAR(50) NOT NULL, -- 'sms', 'email', 'push', 'whatsapp'
    recipient VARCHAR(255) NOT NULL,
    title VARCHAR(255),
    body TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'queued', -- 'queued', 'sending', 'sent', 'failed', 'retrying'
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    next_retry_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    error_message TEXT,
    delivered_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexing queue for fast worker queries
CREATE INDEX IF NOT EXISTS idx_notif_queue_status_retry ON notification_queue (status, next_retry_at);

-- 3. Company Notification Credits Table
CREATE TABLE IF NOT EXISTS company_notification_credits (
    company_id VARCHAR(100) PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    sms_credits INTEGER DEFAULT 100,
    whatsapp_credits INTEGER DEFAULT 50,
    email_credits INTEGER DEFAULT 1000,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE notification_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_templates FORCE ROW LEVEL SECURITY;

ALTER TABLE notification_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_queue FORCE ROW LEVEL SECURITY;

ALTER TABLE company_notification_credits ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_notification_credits FORCE ROW LEVEL SECURITY;

-- 5. Add isolation policies
DROP POLICY IF EXISTS tenant_isolation ON notification_templates;
CREATE POLICY tenant_isolation ON notification_templates FOR ALL USING (
    company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true'
);

DROP POLICY IF EXISTS tenant_isolation ON notification_queue;
CREATE POLICY tenant_isolation ON notification_queue FOR ALL USING (
    company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true'
);

DROP POLICY IF EXISTS tenant_isolation ON company_notification_credits;
CREATE POLICY tenant_isolation ON company_notification_credits FOR ALL USING (
    company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true'
);
