-- Tenant isolation for child rows that previously relied only on parent FKs.

ALTER TABLE sale_items
  ADD COLUMN IF NOT EXISTS company_id VARCHAR(100)
  REFERENCES companies(id) ON DELETE CASCADE;

UPDATE sale_items si
SET company_id = s.company_id
FROM sales s
WHERE si.sale_id = s.id
  AND si.company_id IS NULL;

ALTER TABLE sale_items
  ALTER COLUMN company_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sale_items_company
  ON sale_items(company_id);

ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_items FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON sale_items;
CREATE POLICY tenant_isolation ON sale_items FOR ALL
  USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
  WITH CHECK (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');

ALTER TABLE customer_order_items
  ADD COLUMN IF NOT EXISTS company_id VARCHAR(100)
  REFERENCES companies(id) ON DELETE CASCADE;

UPDATE customer_order_items coi
SET company_id = co.company_id
FROM customer_orders co
WHERE coi.order_id = co.id
  AND coi.company_id IS NULL;

ALTER TABLE customer_order_items
  ALTER COLUMN company_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_customer_order_items_company
  ON customer_order_items(company_id);

ALTER TABLE customer_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_order_items FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON customer_order_items;
CREATE POLICY tenant_isolation ON customer_order_items FOR ALL
  USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
  WITH CHECK (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');
