-- PostgreSQL schema v4 migrations for Serenut POS SaaS backend
-- Analytics Platform: query performance indexes for BI reports

-- 1. Index for sales dashboard / trend analysis queries
CREATE INDEX IF NOT EXISTS idx_sales_company_created ON sales (company_id, created_at) 
  WHERE is_deleted = FALSE;

-- 2. Index for cashier / staff performance tracking
CREATE INDEX IF NOT EXISTS idx_sales_created_by ON sales (created_by) 
  WHERE is_deleted = FALSE;

-- 3. Index for product analytics (joins and aggregations)
CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items (product_id);

-- 4. Index for financial statistics (collections, refunds, debt)
CREATE INDEX IF NOT EXISTS idx_financial_company_type ON financial_transactions (company_id, type)
  WHERE is_deleted = FALSE;

-- 5. Index for customer balance / veresiye details
CREATE INDEX IF NOT EXISTS idx_financial_customer ON financial_transactions (customer_id)
  WHERE is_deleted = FALSE;

-- 6. Index for sync tracking speedups
CREATE INDEX IF NOT EXISTS idx_sales_is_synced ON sales (company_id, is_synced);
