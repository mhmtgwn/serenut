-- schema_v100.sql
-- Cash expenses (Kasa Giderleri / Masraflar) table for Sync V4 multi-terminal synchronization

CREATE TABLE IF NOT EXISTS cash_expenses (
  id VARCHAR(100) PRIMARY KEY,
  company_id VARCHAR(100) REFERENCES companies(id) ON DELETE CASCADE,
  amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  category VARCHAR(100) NOT NULL DEFAULT 'Genel',
  description TEXT,
  is_deleted BOOLEAN NOT NULL DEFAULT false,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_cash_expenses_company_date ON cash_expenses(company_id, created_at);

ALTER TABLE cash_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_expenses FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'cash_expenses' AND policyname = 'tenant_isolation'
  ) THEN
    CREATE POLICY tenant_isolation ON cash_expenses
      USING (company_id = current_tenant_id() OR current_setting('app.bypass_rls', true) = 'true');
  END IF;
END $$;
