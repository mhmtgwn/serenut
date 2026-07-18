-- PostgreSQL schema v8 migrations for Serenut OS SaaS backend
-- Sprint 3: Admin Operations & System Hardening

-- 1. System Incidents Table
CREATE TABLE IF NOT EXISTS system_incidents (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE SET NULL,
    severity VARCHAR(50) NOT NULL, -- 'SEV-1' (Critical), 'SEV-2' (High), 'SEV-3' (Medium), 'SEV-4' (Low)
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'open', -- 'open', 'assigned', 'resolved'
    assignee VARCHAR(100), -- user_id of admin
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolved_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_incidents_status_severity ON system_incidents (status, severity);

-- 2. IP Blacklist Table
CREATE TABLE IF NOT EXISTS ip_blacklist (
    ip VARCHAR(50) PRIMARY KEY,
    reason TEXT NOT NULL,
    banned_by VARCHAR(100) NOT NULL, -- user_id of admin
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. Ticket Internal Notes Table
CREATE TABLE IF NOT EXISTS ticket_internal_notes (
    id VARCHAR(100) PRIMARY KEY,
    ticket_id VARCHAR(100) REFERENCES support_tickets(id) ON DELETE CASCADE,
    author_id VARCHAR(100) NOT NULL, -- user_id of admin
    author_name VARCHAR(150) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. Enable RLS
ALTER TABLE system_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_incidents FORCE ROW LEVEL SECURITY;

ALTER TABLE ip_blacklist ENABLE ROW LEVEL SECURITY;
ALTER TABLE ip_blacklist FORCE ROW LEVEL SECURITY;

ALTER TABLE ticket_internal_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_internal_notes FORCE ROW LEVEL SECURITY;

-- 5. Add isolation policies (Admin bypasses RLS)
DROP POLICY IF EXISTS tenant_isolation ON system_incidents;
CREATE POLICY tenant_isolation ON system_incidents FOR ALL USING (
    company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true'
);

DROP POLICY IF EXISTS tenant_isolation ON ip_blacklist;
CREATE POLICY tenant_isolation ON ip_blacklist FOR ALL USING (
    current_setting('app.bypass_rls', true) = 'true'
);

DROP POLICY IF EXISTS tenant_isolation ON ticket_internal_notes;
CREATE POLICY tenant_isolation ON ticket_internal_notes FOR ALL USING (
    current_setting('app.bypass_rls', true) = 'true'
);
