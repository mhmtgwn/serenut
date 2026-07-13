-- server/db/schema_v20.sql
-- Serenut OS — Remote Configuration and Feature Flags schema (Sprint 8)

CREATE TABLE IF NOT EXISTS remote_configs (
    id SERIAL PRIMARY KEY,
    key TEXT UNIQUE NOT NULL,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed default global remote configuration
INSERT INTO remote_configs (key, value, description)
VALUES (
    'global_config',
    '{"kill_switch": false, "sync_interval_seconds": 300, "log_level": "info", "telemetry_interval_seconds": 600, "enable_payment_retry": true}',
    'Global remote config feature flags and configuration'
)
ON CONFLICT (key) DO NOTHING;
