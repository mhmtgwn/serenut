-- server/db/schema_v21.sql
-- Serenut OS — Client Health Reports tracking schema (Sprint 11)

CREATE TABLE IF NOT EXISTS client_health_reports (
    id SERIAL PRIMARY KEY,
    company_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    status TEXT NOT NULL,
    services JSONB NOT NULL,
    reported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_client_health_reported ON client_health_reports(reported_at);
CREATE INDEX IF NOT EXISTS idx_client_health_device ON client_health_reports(device_id);
