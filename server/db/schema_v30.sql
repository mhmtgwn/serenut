-- server/db/schema_v30.sql
-- Idempotency support for local SMS sync + SMS history read permission

-- 1. Add client_message_id for idempotency deduplication in sync-local endpoint
ALTER TABLE notification_queue ADD COLUMN IF NOT EXISTS client_message_id VARCHAR(100);

-- Unique index: same company + same client_message_id = deduplication (only non-null values)
CREATE UNIQUE INDEX IF NOT EXISTS uq_notif_queue_client_msg
  ON notification_queue (company_id, client_message_id)
  WHERE client_message_id IS NOT NULL;

-- 2. Ensure permissions exist for role-based queue, telemetry, campaign, and template access
INSERT INTO permissions (id, code, description) VALUES
  (gen_random_uuid()::text, 'notifications.history.read', 'SMS ve bildirim gönderim geçmişini görüntüleme'),
  (gen_random_uuid()::text, 'telemetry.view', 'Sistem durumu ve denetim loglarını görüntüleme'),
  (gen_random_uuid()::text, 'notifications.campaign.send', 'Toplu SMS kampanyası başlatma yetkisi'),
  (gen_random_uuid()::text, 'notifications.templates.manage', 'Bildirim şablonlarını yönetme yetkisi')
ON CONFLICT (code) DO NOTHING;

-- Grant permissions to admin, sysadmin, and owner roles
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r, permissions p
WHERE r.name IN ('admin', 'sysadmin', 'owner')
  AND p.code IN ('notifications.history.read', 'telemetry.view', 'notifications.campaign.send', 'notifications.templates.manage')
ON CONFLICT DO NOTHING;
