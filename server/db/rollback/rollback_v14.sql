-- Rollback v14: Remove branches table and sale FSM columns

-- Drop indexes first
DROP INDEX IF EXISTS idx_branches_company;
DROP INDEX IF EXISTS idx_branches_name_company;
DROP INDEX IF EXISTS idx_sales_branch;
DROP INDEX IF EXISTS idx_sales_fsm_state;

-- Drop branches table
DROP TABLE IF EXISTS branches;

-- Remove sales FSM columns
ALTER TABLE sales DROP COLUMN IF EXISTS branch_id;
ALTER TABLE sales DROP COLUMN IF EXISTS fsm_state;
ALTER TABLE sales DROP COLUMN IF EXISTS refunded_amount;
ALTER TABLE sales DROP COLUMN IF EXISTS refund_reason;

-- Remove from schema_migrations
DELETE FROM schema_migrations WHERE version = 14;
