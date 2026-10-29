-- schema_v109.sql
-- Retroactively sanitize sync_v4_changes and sync_v4_entities payloads for legacy client compatibility

UPDATE sync_v4_changes
SET payload = jsonb_set(payload, '{customer_id}', '""'::jsonb)
WHERE entity_type IN ('financial_transaction', 'sale', 'order')
  AND (payload->>'customer_id' IS NULL OR payload->'customer_id' = 'null'::jsonb);

UPDATE sync_v4_entities
SET payload = jsonb_set(payload, '{customer_id}', '""'::jsonb)
WHERE entity_type IN ('financial_transaction', 'sale', 'order')
  AND (payload->>'customer_id' IS NULL OR payload->'customer_id' = 'null'::jsonb);
