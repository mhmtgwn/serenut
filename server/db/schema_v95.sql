-- schema_v95.sql
-- Add address to customers for sync_v4 and cross-device sync fidelity.

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS address TEXT;
