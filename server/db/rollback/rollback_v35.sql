-- server/db/rollback/rollback_v35.sql
-- Restore POS transaction permissions to sysadmin role

INSERT INTO role_permissions (role_id, permission_id) VALUES
  ('sysadmin', 'perm-sales-create'),
  ('sysadmin', 'perm-sales-view'),
  ('sysadmin', 'perm-inventory-manage'),
  ('sysadmin', 'perm-inventory-view')
ON CONFLICT DO NOTHING;
