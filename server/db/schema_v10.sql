-- PostgreSQL schema v10 — Faz 3: Audit Log Retention Policy
-- Sprint 3.1 — Admin Financial KPIs & Revenue Intelligence

-- 1. Audit log archive table (cold storage: 3 yıl)
CREATE TABLE IF NOT EXISTS audit_logs_archive (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100),
    user_id VARCHAR(100),
    action VARCHAR(100),
    entity VARCHAR(100),
    entity_id VARCHAR(100),
    old_value TEXT,
    new_value TEXT,
    ip_address VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_archive_company ON audit_logs_archive (company_id);
CREATE INDEX IF NOT EXISTS idx_audit_archive_created_at ON audit_logs_archive (created_at);
CREATE INDEX IF NOT EXISTS idx_audit_archive_archived_at ON audit_logs_archive (archived_at);

-- 2. RLS for archive table (admin bypass only)
ALTER TABLE audit_logs_archive ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs_archive FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_isolation ON audit_logs_archive;
CREATE POLICY tenant_isolation ON audit_logs_archive FOR ALL USING (
    current_setting('app.bypass_rls', true) = 'true'
);

-- 3. Retention function: move logs older than 1 year to archive
CREATE OR REPLACE FUNCTION archive_old_audit_logs()
RETURNS INTEGER AS $$
DECLARE
    archived_count INTEGER;
BEGIN
    -- Move records older than 1 year to cold storage
    WITH moved AS (
        DELETE FROM audit_logs
        WHERE created_at < NOW() - INTERVAL '1 year'
        RETURNING *
    )
    INSERT INTO audit_logs_archive (id, company_id, user_id, action, entity, entity_id, old_value, new_value, ip_address, created_at)
    SELECT id, company_id, user_id, action, entity, entity_id, old_value, new_value, ip_address, created_at
    FROM moved;

    GET DIAGNOSTICS archived_count = ROW_COUNT;
    RETURN archived_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Purge function: delete archive records older than 3 years
CREATE OR REPLACE FUNCTION purge_ancient_audit_archive()
RETURNS INTEGER AS $$
DECLARE
    purged_count INTEGER;
BEGIN
    DELETE FROM audit_logs_archive
    WHERE created_at < NOW() - INTERVAL '3 years';
    GET DIAGNOSTICS purged_count = ROW_COUNT;
    RETURN purged_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
