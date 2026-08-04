ALTER TABLE sales ADD COLUMN IF NOT EXISTS payment_provider VARCHAR(50);
ALTER TABLE sales ADD COLUMN IF NOT EXISTS payment_reference VARCHAR(255);

CREATE TABLE IF NOT EXISTS refunds (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  sale_id VARCHAR(100) NOT NULL REFERENCES sales(id) ON DELETE RESTRICT,
  idempotency_key VARCHAR(100) NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  refund_method VARCHAR(30) NOT NULL,
  external_reference VARCHAR(255),
  reason TEXT NOT NULL,
  status VARCHAR(30) NOT NULL DEFAULT 'completed',
  created_by VARCHAR(100) NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_refunds_company_idempotency UNIQUE(company_id,idempotency_key),
  CONSTRAINT chk_refund_amount_positive CHECK(amount>0),
  CONSTRAINT chk_refund_method CHECK(refund_method IN ('cash','balance','card','mixed')),
  CONSTRAINT chk_refund_status CHECK(status IN ('completed','reversed'))
);

CREATE TABLE IF NOT EXISTS refund_items (
  id VARCHAR(100) PRIMARY KEY,
  refund_id VARCHAR(100) NOT NULL REFERENCES refunds(id) ON DELETE RESTRICT,
  sale_item_id VARCHAR(100) NOT NULL REFERENCES sale_items(id) ON DELETE RESTRICT,
  product_id VARCHAR(100) NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  quantity DECIMAL(12,2) NOT NULL,
  unit_refund_amount DECIMAL(12,2) NOT NULL,
  subtotal DECIMAL(12,2) NOT NULL,
  CONSTRAINT chk_refund_item_values CHECK(quantity>0 AND unit_refund_amount>=0 AND subtotal>=0)
);

CREATE TABLE IF NOT EXISTS inventory_movements (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  product_id VARCHAR(100) NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  movement_type VARCHAR(30) NOT NULL,
  quantity_delta DECIMAL(12,2) NOT NULL,
  reference_type VARCHAR(30) NOT NULL,
  reference_id VARCHAR(100) NOT NULL,
  created_by VARCHAR(100) REFERENCES users(id) ON DELETE RESTRICT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_inventory_movement_nonzero CHECK(quantity_delta<>0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_refund_item_per_refund
  ON refund_items(refund_id,sale_item_id);
CREATE INDEX IF NOT EXISTS idx_refund_items_sale_item ON refund_items(sale_item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_movements_reference
  ON inventory_movements(company_id,reference_type,reference_id);

ALTER TABLE refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE refunds FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON refunds;
CREATE POLICY tenant_isolation ON refunds FOR ALL USING (
  company_id=current_tenant_id() OR current_setting('app.bypass_rls',true)='true'
);
ALTER TABLE inventory_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_movements FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON inventory_movements;
CREATE POLICY tenant_isolation ON inventory_movements FOR ALL USING (
  company_id=current_tenant_id() OR current_setting('app.bypass_rls',true)='true'
);

-- Customer balance is derived from semantic ledger events, not from a generic
-- debt-paid subtraction that incorrectly creates negative balances for cash sales.
CREATE OR REPLACE FUNCTION update_customer_balance_from_transaction()
RETURNS TRIGGER AS $$
DECLARE affected_customer VARCHAR(100);
BEGIN
  IF TG_OP = 'DELETE' THEN
    affected_customer := OLD.customer_id;
  ELSE
    affected_customer := NEW.customer_id;
  END IF;
  IF affected_customer IS NOT NULL THEN
    UPDATE customers SET balance=COALESCE((
      SELECT SUM(CASE
        WHEN type='sale' THEN debt_amount
        WHEN type IN ('payment','collection') THEN -paid_amount
        WHEN type='refund' AND paid_amount=0 THEN -amount
        ELSE 0 END)
      FROM financial_transactions
      WHERE customer_id=affected_customer AND is_deleted=FALSE
    ),0),updated_at=NOW() WHERE id=affected_customer;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;
