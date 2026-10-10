-- schema_v97.sql
-- Customer installment plans and installment tracking tables for credit sales.

CREATE TABLE IF NOT EXISTS customer_installment_plans (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
  customer_id VARCHAR(100) REFERENCES customers(id) ON DELETE CASCADE,
  total_amount NUMERIC(12, 2) NOT NULL,
  down_payment NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  installment_count INTEGER NOT NULL,
  description TEXT,
  status VARCHAR(50) NOT NULL DEFAULT 'active',
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS customer_installments (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
  plan_id VARCHAR(100) REFERENCES customer_installment_plans(id) ON DELETE CASCADE,
  customer_id VARCHAR(100) REFERENCES customers(id) ON DELETE CASCADE,
  installment_no INTEGER NOT NULL,
  amount NUMERIC(12, 2) NOT NULL,
  paid_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  due_date DATE NOT NULL,
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  paid_at TIMESTAMPTZ,
  financial_transaction_id VARCHAR(100),
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_customer_installments_customer ON customer_installments(company_id, customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_installments_due ON customer_installments(company_id, due_date, status);
CREATE INDEX IF NOT EXISTS idx_customer_installments_plan ON customer_installments(plan_id);

ALTER TABLE customer_installment_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_installment_plans FORCE ROW LEVEL SECURITY;
ALTER TABLE customer_installments ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_installments FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'customer_installment_plans' AND policyname = 'tenant_isolation'
  ) THEN
    CREATE POLICY tenant_isolation ON customer_installment_plans
      USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'customer_installments' AND policyname = 'tenant_isolation'
  ) THEN
    CREATE POLICY tenant_isolation ON customer_installments
      USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');
  END IF;
END $$;
