-- server/db/schema_v15.sql
CREATE TABLE IF NOT EXISTS system_settings (
    key VARCHAR(100) PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO system_settings (key, value) VALUES
('iban_bank', 'Yapı Kredi Bankası A.Ş.'),
('iban_branch', 'İstanbul Kozyatağı Ticari Şubesi'),
('iban_owner', 'Serenut Yazılım Teknolojileri Ltd. Şti.'),
('iban_number', 'TR24 0006 2000 0000 9876 5432 10')
ON CONFLICT (key) DO NOTHING;
