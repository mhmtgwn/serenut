-- Check current_tenant_id function definition
SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'current_tenant_id';

-- Also check what setting name it uses
SELECT prosrc FROM pg_proc WHERE proname = 'current_tenant_id';
