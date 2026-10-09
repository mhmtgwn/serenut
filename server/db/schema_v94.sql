-- Requeue previously failed WhatsApp notifications for the Evolution API
-- provider. These rows have no provider message id, so there is no confirmed
-- successful send to duplicate. The versioned migration ensures each row is
-- retried only once by this recovery operation.
UPDATE notification_queue
SET error_message = 'evolution_recovery_pending',
    provider_error_code = NULL,
    updated_at = NOW()
WHERE channel = 'whatsapp'
  AND status = 'failed'
  AND provider_message_id IS NULL;
