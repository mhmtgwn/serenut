-- server/db/schema_v16.sql
INSERT INTO system_settings (key, value) VALUES
('active_payment_provider', 'bank_wire'),
('iyzico_api_key', ''),
('iyzico_secret_key', ''),
('iyzico_base_url', 'https://sandbox-api.iyzipay.com'),
('paytr_merchant_id', ''),
('paytr_merchant_key', ''),
('paytr_merchant_salt', '')
ON CONFLICT (key) DO NOTHING;
