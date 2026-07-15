-- Migration: Payment Providers Registry
-- Description: Creates a registry for payment providers, decoupling them from system_settings and allowing dynamic activation.

CREATE TABLE IF NOT EXISTS payment_providers (
    id VARCHAR(50) PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL,
    is_enabled BOOLEAN DEFAULT FALSE,
    is_configured BOOLEAN DEFAULT FALSE,
    test_mode BOOLEAN DEFAULT TRUE,
    config JSONB DEFAULT '{}'::jsonb,
    secrets JSONB DEFAULT '{}'::jsonb,
    last_test_at TIMESTAMP WITH TIME ZONE,
    last_error TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default providers if they don't exist
INSERT INTO payment_providers (id, display_name, is_enabled, is_configured, test_mode, config, secrets)
VALUES 
  ('bank_transfer', 'Havale / EFT', TRUE, TRUE, FALSE, '{}'::jsonb, '{}'::jsonb),
  ('iyzico', 'Kredi / Banka Kartı (İyzico)', FALSE, FALSE, TRUE, '{}'::jsonb, '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;
