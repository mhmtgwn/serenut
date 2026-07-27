-- Check user privileges
SELECT usename, usesuper, userepl, usebypassrls 
FROM pg_user 
WHERE usename = 'serenut_user';

-- Test: try to manually insert a product for that company with set_config
SET app.current_company_id = 'comp-1784220283837-2dcb98ee';

INSERT INTO products (id, company_id, name, description, price, quantity, category, sku, vat, image_path, status, is_deleted)
VALUES ('test-rls-debug', 'comp-1784220283837-2dcb98ee', 'RLS Test Product', NULL, 0, 0, NULL, 'test-rls-debug', 0, NULL, 'active', false)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, updated_at = CURRENT_TIMESTAMP;

SELECT id, name FROM products WHERE id = 'test-rls-debug';

-- Cleanup
DELETE FROM products WHERE id = 'test-rls-debug';
