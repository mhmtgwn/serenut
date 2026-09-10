-- schema_v92.sql
-- Evolution API (QR tabanlı WhatsApp gateway) desteği.
-- Meta Cloud API alanları korunur (geriye dönük uyumluluk).
-- Yeni gateway_type sütunu hangi sistemin kullanıldığını belirtir.

ALTER TABLE company_whatsapp_connections
  ADD COLUMN IF NOT EXISTS gateway_type TEXT NOT NULL DEFAULT 'meta'
    CHECK (gateway_type IN ('meta', 'evolution')),
  ADD COLUMN IF NOT EXISTS evolution_instance_id TEXT,
  ADD COLUMN IF NOT EXISTS evolution_status TEXT DEFAULT 'close'
    CHECK (evolution_status IN ('open', 'connecting', 'close', NULL));

-- Meta olmayan bağlantılarda phone_number_id ve waba_id NULL olabilir
ALTER TABLE company_whatsapp_connections
  ALTER COLUMN waba_id DROP NOT NULL,
  ALTER COLUMN phone_number_id DROP NOT NULL,
  ALTER COLUMN encrypted_access_token DROP NOT NULL;

-- Status alanına 'open' ve 'qr_pending' ekle (Evolution durumları için)
ALTER TABLE company_whatsapp_connections
  DROP CONSTRAINT IF EXISTS company_whatsapp_connections_status_check;
ALTER TABLE company_whatsapp_connections
  ADD CONSTRAINT company_whatsapp_connections_status_check
    CHECK (status IN ('active','connecting','qr_pending','reauthorization_required','disabled','disconnected','error'));

COMMENT ON COLUMN company_whatsapp_connections.gateway_type IS
  'WhatsApp gönderim altyapısı: meta = Meta Cloud API, evolution = Evolution API (QR tabanlı)';
COMMENT ON COLUMN company_whatsapp_connections.evolution_instance_id IS
  'Evolution API instance adı (şirket ID bazlı, ör: company_abc123)';
COMMENT ON COLUMN company_whatsapp_connections.evolution_status IS
  'Evolution API bağlantı durumu: open=bağlı, connecting=QR bekleniyor, close=kapalı';
