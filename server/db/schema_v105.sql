-- schema_v105.sql
-- Enforce strict Row Level Security (RLS) on sync_v4_changes and sync_v4_entities

ALTER TABLE sync_v4_changes ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_v4_changes FORCE ROW LEVEL SECURITY;

ALTER TABLE sync_v4_entities ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_v4_entities FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_isolation ON sync_v4_changes;
  CREATE POLICY tenant_isolation ON sync_v4_changes
    FOR ALL
    USING (tenant_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
    WITH CHECK (tenant_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

  DROP POLICY IF EXISTS tenant_isolation ON sync_v4_entities;
  CREATE POLICY tenant_isolation ON sync_v4_entities
    FOR ALL
    USING (tenant_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
    WITH CHECK (tenant_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');
END $$;
