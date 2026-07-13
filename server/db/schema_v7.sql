-- PostgreSQL schema v7 migrations for Serenut POS SaaS backend
-- Production Hardening: Audit logging and notification queue scheduled delivery

-- 1. Create Audit Logs Table (For tracking critical tenant operations)
CREATE TABLE IF NOT EXISTS audit_logs (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    user_id VARCHAR(100) NOT NULL,
    user_name VARCHAR(150) NOT NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id VARCHAR(100) NOT NULL,
    old_values JSONB,
    new_values JSONB,
    ip_address VARCHAR(50) NOT NULL,
    user_agent VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexing for fast RLS queries and auditing audits
CREATE INDEX IF NOT EXISTS idx_audit_logs_company_action ON audit_logs (company_id, action);

-- 2. Expand notification_queue with scheduled_at timestamp
ALTER TABLE notification_queue ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- Recreate optimized index for scheduling
DROP INDEX IF EXISTS idx_notif_queue_status_retry;
CREATE INDEX IF NOT EXISTS idx_notif_queue_status_scheduled ON notification_queue (status, scheduled_at, next_retry_at);

-- 3. Enable Row Level Security (RLS) on audit_logs
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;

-- 4. Add isolation policy for audit_logs
DROP POLICY IF EXISTS tenant_isolation ON audit_logs;
CREATE POLICY tenant_isolation ON audit_logs FOR ALL USING (
    company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true'
);
