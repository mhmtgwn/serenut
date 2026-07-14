ALTER TABLE user_roles DROP CONSTRAINT user_roles_role_id_fkey;
UPDATE roles SET id = name WHERE id IN ('role-sysadmin', 'role-owner', 'role-admin');
UPDATE user_roles SET role_id = REPLACE(role_id, 'role-', '');
ALTER TABLE user_roles ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE;
