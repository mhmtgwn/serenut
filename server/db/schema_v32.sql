-- server/db/schema_v32.sql
-- Serenut OS — Settings Granular Permissions

-- 1. Insert new settings permissions
INSERT INTO permissions (id, code, description) VALUES
  ('perm-settings-view',      'settings:view',       'Ayarlar ekranına giriş yetkisi'),
  ('perm-settings-printer',   'settings:printer',    'Yazıcı ve donanım tercihlerini yönetme'),
  ('perm-settings-receipt',   'settings:receipt',    'Fiş şablon ve işletme davranışlarını yönetme'),
  ('perm-settings-users',     'settings:users',      'Kullanıcı yetkilerini yönetme'),
  ('perm-settings-finance',   'settings:finance',    'Cari ve finansal hub ayarlarını yönetme'),
  ('perm-settings-audit',     'settings:audit',      'Denetim loglarını ve SMS geçmişini görüntüleme'),
  ('perm-settings-database',  'settings:database',   'Veritabanı sağlık kontrolü ve veri dışı aktarımı yönetme'),
  ('perm-settings-recovery',  'settings:recovery',   'Veri kurtarma merkezini yönetme'),
  ('perm-settings-license',   'settings:license',    'Lisans ve abonelik yönetimini yapma')
ON CONFLICT (code) DO NOTHING;

-- 2. Grant settings permissions to admin, sysadmin, and owner roles
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
WHERE r.name IN ('admin', 'sysadmin', 'owner')
  AND p.code IN (
    'settings:view',
    'settings:printer',
    'settings:receipt',
    'settings:users',
    'settings:finance',
    'settings:audit',
    'settings:database',
    'settings:recovery',
    'settings:license'
  )
ON CONFLICT DO NOTHING;

-- 3. Grant settings:view and settings:printer permissions to manager, cashier, and staff roles by default
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
WHERE r.name IN ('manager', 'cashier', 'staff')
  AND p.code IN ('settings:view', 'settings:printer')
ON CONFLICT DO NOTHING;
