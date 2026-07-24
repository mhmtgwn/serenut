-- Serenut OS — explicit web portal access entitlement

INSERT INTO permissions (id, code, description) VALUES
  ('perm-portal-access', 'portal:access', 'Firma yönetim portalına giriş yetkisi')
ON CONFLICT (code) DO UPDATE SET description = EXCLUDED.description;

-- Platform administrators and company owners always receive portal access.
-- Managers and custom roles receive it only when the owner assigns it.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN permissions p ON p.code = 'portal:access'
WHERE r.name IN ('sysadmin', 'owner')
ON CONFLICT DO NOTHING;
