-- Migration v14: Branches table + Orders FSM state column
-- Serenut OS V1 — API Contract Implementation
-- Blueprint: api_contract.md — Section BRANCHES, ORDERS

-- ── BRANCHES ─────────────────────────────────────────────────────────────────
-- Branches are sub-locations of a company (e.g., different store locations).
-- Blueprint: api_contract.md — POST/GET/DELETE /branches
CREATE TABLE IF NOT EXISTS branches (
    id          VARCHAR(100)  PRIMARY KEY,
    company_id  VARCHAR(100)  NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name        VARCHAR(255)  NOT NULL,
    address     TEXT,
    phone       VARCHAR(50),
    is_active   BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_branches_company ON branches(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_branches_name_company ON branches(company_id, name);

-- ── ORDERS FSM STATE ─────────────────────────────────────────────────────────
-- Sale FSM: pending → completed | cancelled
--            completed → refunded | partially_refunded
-- blueprint: state_machine_specification.md — Section 4

-- Add branch_id to sales if not present
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sales' AND column_name = 'branch_id'
  ) THEN
    ALTER TABLE sales ADD COLUMN branch_id VARCHAR(100) REFERENCES branches(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sales' AND column_name = 'fsm_state'
  ) THEN
    ALTER TABLE sales ADD COLUMN fsm_state VARCHAR(25) DEFAULT 'completed'
      CHECK (fsm_state IN ('pending', 'completed', 'cancelled', 'refunded', 'partially_refunded'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sales' AND column_name = 'refunded_amount'
  ) THEN
    ALTER TABLE sales ADD COLUMN refunded_amount DECIMAL(12,2) DEFAULT 0.00;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sales' AND column_name = 'refund_reason'
  ) THEN
    ALTER TABLE sales ADD COLUMN refund_reason TEXT;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_sales_branch ON sales(branch_id);
CREATE INDEX IF NOT EXISTS idx_sales_fsm_state ON sales(fsm_state);
