-- schema_v104.sql
-- Enforce strict RLS and canonical tenant isolation for Hazelnut module

ALTER TABLE warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouses FORCE ROW LEVEL SECURITY;

ALTER TABLE customer_hazelnut_escrow ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_hazelnut_escrow FORCE ROW LEVEL SECURITY;

ALTER TABLE warehouse_hazelnut_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouse_hazelnut_movements FORCE ROW LEVEL SECURITY;

ALTER TABLE hazelnut_price_cuts ENABLE ROW LEVEL SECURITY;
ALTER TABLE hazelnut_price_cuts FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS tenant_isolation ON warehouses;
  CREATE POLICY tenant_isolation ON warehouses
    FOR ALL
    USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

  DROP POLICY IF EXISTS tenant_isolation ON customer_hazelnut_escrow;
  CREATE POLICY tenant_isolation ON customer_hazelnut_escrow
    FOR ALL
    USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

  DROP POLICY IF EXISTS tenant_isolation ON warehouse_hazelnut_movements;
  CREATE POLICY tenant_isolation ON warehouse_hazelnut_movements
    FOR ALL
    USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

  DROP POLICY IF EXISTS tenant_isolation ON hazelnut_price_cuts;
  CREATE POLICY tenant_isolation ON hazelnut_price_cuts
    FOR ALL
    USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');
END $$;
