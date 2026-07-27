-- Fix 1: Un-delete all products that have is_deleted=true (they were incorrectly marked as deleted)
UPDATE products SET is_deleted = false, updated_at = NOW()
WHERE is_deleted = true AND company_id = 'comp-1784220283837-2dcb98ee';

-- Verify fix
SELECT COUNT(*) as total_products, 
       SUM(CASE WHEN is_deleted THEN 1 ELSE 0 END) as deleted_count,
       SUM(CASE WHEN NOT is_deleted THEN 1 ELSE 0 END) as active_count
FROM products WHERE company_id = 'comp-1784220283837-2dcb98ee';

-- Also check why product 6788322 never got inserted - look at sync_queue errors
SELECT id, entity_type, entity_id, status, payload->>'name' as name, created_at
FROM sync_queue
WHERE entity_id = '6788322'
ORDER BY created_at DESC
LIMIT 5;
