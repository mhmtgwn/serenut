CREATE TABLE IF NOT EXISTS customer_orders (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  customer_id VARCHAR(100) NOT NULL REFERENCES customers(id),
  status VARCHAR(30) NOT NULL DEFAULT 'created',
  total_amount DECIMAL(12,2) DEFAULT 0,
  order_date TIMESTAMPTZ,
  expected_delivery_date TIMESTAMPTZ,
  actual_delivery_date TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  deleted_at TIMESTAMPTZ,
  deleted_by VARCHAR(100),
  created_by VARCHAR(100)
);
CREATE TABLE IF NOT EXISTS customer_order_items (
  id VARCHAR(180) PRIMARY KEY,
  order_id VARCHAR(100) NOT NULL REFERENCES customer_orders(id) ON DELETE CASCADE,
  product_id VARCHAR(100) NOT NULL REFERENCES products(id),
  quantity DECIMAL(12,3) NOT NULL,
  unit_price DECIMAL(12,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_customer_orders_company_updated ON customer_orders(company_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_customer_order_items_order ON customer_order_items(order_id);
ALTER TABLE customer_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_orders FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON customer_orders;
CREATE POLICY tenant_isolation ON customer_orders FOR ALL
  USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true')
  WITH CHECK (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');
