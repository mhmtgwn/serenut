-- Migration v50: Enterprise Sync Engine v2 Schema
-- Created according to ENTERPRISE_SYNC_ENGINE_SPECIFICATION_V1.md

-- 1. Add domain revision vector tracking to companies
ALTER TABLE companies ADD COLUMN IF NOT EXISTS current_revision BIGINT NOT NULL DEFAULT 0;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS domain_revisions JSONB NOT NULL DEFAULT '{"sales": 0, "stock": 0, "customer": 0, "invoice": 0, "settings": 0}'::jsonb;

-- 2. Domain & Global Revisions Log Table
CREATE TABLE IF NOT EXISTS sync_revisions (
    revision_id BIGSERIAL,
    tenant_id VARCHAR(64) NOT NULL,
    revision BIGINT NOT NULL,
    domain VARCHAR(64) NOT NULL,
    entity_type VARCHAR(64) NOT NULL,
    entity_id VARCHAR(64) NOT NULL,
    op_type VARCHAR(16) NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE', 'RESTORE'
    payload JSONB NOT NULL,
    client_mutation_id VARCHAR(64) NOT NULL,
    device_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (tenant_id, revision_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_revisions_tenant_rev ON sync_revisions(tenant_id, revision);
CREATE INDEX IF NOT EXISTS idx_sync_revisions_domain_rev ON sync_revisions(tenant_id, domain, revision);
CREATE INDEX IF NOT EXISTS idx_sync_revisions_entity ON sync_revisions(tenant_id, entity_type, entity_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_revisions_idempotency ON sync_revisions(tenant_id, client_mutation_id);

-- 3. Tombstones Table (Garbage Collection Tracking)
CREATE TABLE IF NOT EXISTS sync_tombstones (
    id BIGSERIAL PRIMARY KEY,
    tenant_id VARCHAR(64) NOT NULL,
    domain VARCHAR(64) NOT NULL,
    entity_type VARCHAR(64) NOT NULL,
    entity_id VARCHAR(64) NOT NULL,
    deleted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    deleted_by_device VARCHAR(64) NOT NULL,
    purged_at TIMESTAMPTZ NULL
);
CREATE INDEX IF NOT EXISTS idx_sync_tombstones_tenant_purge ON sync_tombstones(tenant_id, purged_at, deleted_at);

-- 4. Sync Registered Devices Table
CREATE TABLE IF NOT EXISTS sync_devices (
    device_id VARCHAR(64) PRIMARY KEY,
    tenant_id VARCHAR(64) NOT NULL,
    user_id VARCHAR(64) NOT NULL,
    device_name VARCHAR(128) NOT NULL,
    last_synced_vectors JSONB NOT NULL DEFAULT '{}'::jsonb,
    last_seen_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_sync_devices_tenant ON sync_devices(tenant_id);

-- 5. Full State Snapshots Table (Compaction Engine)
CREATE TABLE IF NOT EXISTS sync_snapshots (
    id BIGSERIAL PRIMARY KEY,
    tenant_id VARCHAR(64) NOT NULL,
    domain VARCHAR(64) NOT NULL,
    snapshot_revision BIGINT NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unq_sync_snapshots_tenant_domain_rev UNIQUE (tenant_id, domain, snapshot_revision)
);
CREATE INDEX IF NOT EXISTS idx_sync_snapshots_tenant_domain ON sync_snapshots(tenant_id, domain, snapshot_revision DESC);
