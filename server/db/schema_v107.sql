-- schema_v107.sql
-- Remove redundant index idx_sync_v4_changes_pull since PRIMARY KEY (tenant_id, revision) already indexes (tenant_id, revision)

DROP INDEX IF EXISTS idx_sync_v4_changes_pull;
