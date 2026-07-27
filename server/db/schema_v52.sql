-- Sync v4: append-only, tenant-scoped replication log.
CREATE TABLE IF NOT EXISTS sync_v4_changes (
  tenant_id VARCHAR(64) NOT NULL,
  revision BIGSERIAL NOT NULL,
  mutation_id UUID NOT NULL,
  device_id VARCHAR(128) NOT NULL,
  entity_type VARCHAR(32) NOT NULL,
  entity_id VARCHAR(128) NOT NULL,
  operation VARCHAR(16) NOT NULL CHECK (operation IN ('UPSERT', 'DELETE')),
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (tenant_id, revision),
  UNIQUE (tenant_id, mutation_id)
);
CREATE INDEX IF NOT EXISTS idx_sync_v4_changes_pull
  ON sync_v4_changes (tenant_id, revision);
