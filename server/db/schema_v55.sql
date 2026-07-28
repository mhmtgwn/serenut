-- Sync V4 optimistic-concurrency audit log. Conflict rows are immutable
-- evidence; canonical entity state remains the server revision.
CREATE TABLE IF NOT EXISTS sync_v4_conflicts (
  id BIGSERIAL PRIMARY KEY,
  tenant_id VARCHAR(64) NOT NULL,
  mutation_id UUID NOT NULL,
  entity_type VARCHAR(32) NOT NULL,
  entity_id VARCHAR(128) NOT NULL,
  base_revision BIGINT NOT NULL,
  server_revision BIGINT NOT NULL,
  device_id VARCHAR(128) NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (tenant_id, mutation_id)
);
CREATE INDEX IF NOT EXISTS idx_sync_v4_conflicts_tenant_created
  ON sync_v4_conflicts (tenant_id, created_at DESC);
