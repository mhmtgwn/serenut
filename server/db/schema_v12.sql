-- PostgreSQL schema v12 — Faz 7: Performance
-- Sprint 7.1 — Performance Indexing & Caching Strategy

-- 1. Index on sales for company_id, created_at to boost financial dashboard queries
CREATE INDEX IF NOT EXISTS idx_sales_company_created
  ON sales(company_id, created_at DESC) WHERE is_deleted = FALSE;

-- 2. Index on sessions for refresh_token to boost authentication and active session queries
CREATE INDEX IF NOT EXISTS idx_sessions_refresh_active
  ON sessions(refresh_token) WHERE is_revoked = FALSE;

-- 3. Index on notification_queue for company_id, status to boost queue analytics
CREATE INDEX IF NOT EXISTS idx_notifications_company_status
  ON notification_queue(company_id, status, created_at);
