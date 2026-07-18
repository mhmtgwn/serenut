-- PostgreSQL schema v2 migrations for Serenut OS SaaS backend
-- Adds support tickets and SMS logs tables under PostgreSQL RLS isolation
-- Recreates RLS policies to support admin bypass via app.bypass_rls = 'true'

-- 1. Support Tickets
CREATE TABLE IF NOT EXISTS support_tickets (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    priority VARCHAR(50) DEFAULT 'medium', -- 'low', 'medium', 'high', 'critical'
    status VARCHAR(50) DEFAULT 'open', -- 'open', 'replied', 'closed'
    assignee VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS support_ticket_messages (
    id VARCHAR(100) PRIMARY KEY,
    ticket_id VARCHAR(100) REFERENCES support_tickets(id) ON DELETE CASCADE,
    sender_id VARCHAR(100) NOT NULL, -- user_id or 'admin'
    sender_name VARCHAR(150) NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. SMS logs
CREATE TABLE IF NOT EXISTS sms_logs (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
    phone VARCHAR(50) NOT NULL,
    message TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'sent', -- 'pending', 'sent', 'failed'
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. Row Level Security (RLS) Enable
ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets FORCE ROW LEVEL SECURITY;

ALTER TABLE support_ticket_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_ticket_messages FORCE ROW LEVEL SECURITY;

ALTER TABLE sms_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE sms_logs FORCE ROW LEVEL SECURITY;

-- 4. Re-create Tenant Isolation Policies with Admin Bypass Rule
DROP POLICY IF EXISTS tenant_isolation ON users;
CREATE POLICY tenant_isolation ON users FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON stores;
CREATE POLICY tenant_isolation ON stores FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON products;
CREATE POLICY tenant_isolation ON products FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON customers;
CREATE POLICY tenant_isolation ON customers FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON sales;
CREATE POLICY tenant_isolation ON sales FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON financial_transactions;
CREATE POLICY tenant_isolation ON financial_transactions FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON devices;
CREATE POLICY tenant_isolation ON devices FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON licenses;
CREATE POLICY tenant_isolation ON licenses FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON subscriptions;
CREATE POLICY tenant_isolation ON subscriptions FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON invoices;
CREATE POLICY tenant_isolation ON invoices FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON sync_queue;
CREATE POLICY tenant_isolation ON sync_queue FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON crash_logs;
CREATE POLICY tenant_isolation ON crash_logs FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON audit_logs;
CREATE POLICY tenant_isolation ON audit_logs FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON support_tickets;
CREATE POLICY tenant_isolation ON support_tickets FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON sms_logs;
CREATE POLICY tenant_isolation ON sms_logs FOR ALL USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

DROP POLICY IF EXISTS tenant_isolation ON support_ticket_messages;
CREATE POLICY tenant_isolation ON support_ticket_messages FOR ALL USING (
    ticket_id IN (SELECT id FROM support_tickets WHERE company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
);
