-- PostgreSQL schema v5 migrations for Serenut POS SaaS backend
-- Billing Platform: subscription properties, invoice details and plans seeding

-- 1. Extend subscriptions with recurring billing control columns
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS payment_method VARCHAR(50) DEFAULT 'credit_card';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS cancel_at_period_end BOOLEAN DEFAULT FALSE;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS grace_period_until TIMESTAMP WITH TIME ZONE;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS last_payment_status VARCHAR(50) DEFAULT 'success'; -- 'success', 'failed', 'pending'

-- 2. Extend invoices with formal invoicing details
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS invoice_number VARCHAR(100) UNIQUE;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS billing_details JSONB;
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS payment_gateway_reference VARCHAR(255);
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS pdf_path VARCHAR(500);

-- 3. Seed standard pricing plans if they don't exist
INSERT INTO plans (id, name, price, currency, billing_interval, features)
VALUES 
  ('plan-free', 'Free Deneme', 0.00, 'TRY', 'monthly', '{"devices": 1, "stores": 1, "sync": "realtime", "analytics": "basic"}'),
  ('plan-basic', 'Basic Tier', 450.00, 'TRY', 'monthly', '{"devices": 2, "stores": 1, "sync": "realtime", "analytics": "standard"}'),
  ('plan-pro', 'Pro Suite', 950.00, 'TRY', 'monthly', '{"devices": 5, "stores": 3, "sync": "realtime", "analytics": "advanced"}'),
  ('plan-enterprise', 'Enterprise Tier', 2450.00, 'TRY', 'monthly', '{"devices": 99, "stores": 99, "sync": "realtime", "analytics": "bi_unlimited"}')
ON CONFLICT (id) DO UPDATE SET
  price = EXCLUDED.price,
  features = EXCLUDED.features;
