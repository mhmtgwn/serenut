-- server/db/schema_v22.sql
-- Serenut OS — Plan pricing and naming alignment (Sprint 12)

UPDATE plans SET name = 'Başlangıç', price = 499.00, features = '{"devices": 1, "stores": 1, "sync": "realtime", "analytics": "basic"}'::jsonb WHERE id = 'plan-basic';
UPDATE plans SET name = 'Profesyonel', price = 899.00, features = '{"devices": 3, "stores": 3, "sync": "realtime", "analytics": "standard"}'::jsonb WHERE id = 'plan-pro';
UPDATE plans SET name = 'Kurumsal', price = 1699.00, features = '{"devices": 99, "stores": 99, "sync": "realtime", "analytics": "advanced"}'::jsonb WHERE id = 'plan-enterprise';
