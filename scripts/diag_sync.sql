SELECT id, name, is_deleted, status, updated_at 
FROM products 
WHERE id = '6788322';

SELECT p.id, p.name, p.is_deleted, p.status, p.updated_at
FROM products p
WHERE p.updated_at > NOW() - INTERVAL '2 hours'
ORDER BY p.updated_at DESC
LIMIT 10;

SELECT id, entity_type, entity_id, status, created_at
FROM sync_queue
WHERE entity_type = 'product'
ORDER BY created_at DESC
LIMIT 10;
