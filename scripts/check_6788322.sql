-- Check if product id '6788322' exists at all (any company)
SELECT id, name, company_id, is_deleted FROM products WHERE id = '6788322';

-- Check if there's a unique constraint that prevents insertion
SELECT conname, contype, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conrelid = 'products'::regclass;
