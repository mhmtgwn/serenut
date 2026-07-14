-- server/db/schema_v35.sql
-- Remove POS transaction permissions from sysadmin role

DELETE FROM role_permissions
WHERE role_id = 'sysadmin'
  AND permission_id IN (
    'perm-sales-create',
    'perm-sales-view',
    'perm-inventory-manage',
    'perm-inventory-view'
  );
