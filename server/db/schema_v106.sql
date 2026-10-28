-- schema_v106.sql
-- Add soft-delete and sync metadata columns to hazelnut and warehouse tables

ALTER TABLE warehouses ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE warehouses ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE customer_hazelnut_escrow ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE customer_hazelnut_escrow ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE warehouse_hazelnut_movements ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE warehouse_hazelnut_movements ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE hazelnut_price_cuts ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE hazelnut_price_cuts ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
