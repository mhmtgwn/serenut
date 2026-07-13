-- server/db/schema_v24.sql
-- Serenut OS -- Commercial Lifecycle V2 -- Phase 2 (Entitlement & Device Activation)

-- ── 1. LICENSE ENTITLEMENTS ───────────────────────────────────────────────────
-- Replaces the single-row licenses model.
-- One company can have multiple entitlement records (active, expired, revoked history).
-- Active entitlement: status IN ('trial', 'active') ORDER BY valid_until DESC LIMIT 1

CREATE TABLE IF NOT EXISTS license_entitlements (
    id VARCHAR(100) PRIMARY KEY,
    company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    subscription_id VARCHAR(100) REFERENCES subscriptions(id) ON DELETE SET NULL,
    plan_id VARCHAR(100) REFERENCES plans(id) ON DELETE RESTRICT,
    status VARCHAR(50) NOT NULL DEFAULT 'inactive',
    -- inactive | trial | active | expired | revoked
    device_limit INTEGER NOT NULL DEFAULT 1,
    store_limit INTEGER NOT NULL DEFAULT 1,
    valid_from TIMESTAMP WITH TIME ZONE,
    valid_until TIMESTAMP WITH TIME ZONE,
    token_version INTEGER NOT NULL DEFAULT 1,
    -- Incrementing this invalidates all previously issued device tokens
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_entitlement_company_status
  ON license_entitlements(company_id, status);

-- ── 2. DEVICE ACTIVATIONS ─────────────────────────────────────────────────────
-- Each row = one device bound to one entitlement.
-- active_count per entitlement must stay <= entitlement.device_limit.

CREATE TABLE IF NOT EXISTS device_activations (
    id VARCHAR(100) PRIMARY KEY,
    entitlement_id VARCHAR(100) NOT NULL REFERENCES license_entitlements(id) ON DELETE CASCADE,
    company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    device_hash VARCHAR(255) NOT NULL,
    device_name VARCHAR(150),
    platform VARCHAR(50) DEFAULT 'windows',
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    -- active | revoked
    activated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP WITH TIME ZONE,
    revoked_at TIMESTAMP WITH TIME ZONE,
    revoked_by VARCHAR(100),
    UNIQUE (entitlement_id, device_hash)
);

CREATE INDEX IF NOT EXISTS idx_device_activations_company
  ON device_activations(company_id, status);

-- ── 3. MIGRATE EXISTING licenses → license_entitlements ───────────────────────
-- For companies that already have a license record, create a corresponding entitlement.
-- The old licenses table is kept for reference but no longer written to.

INSERT INTO license_entitlements (
    id, company_id, plan_id, status, device_limit, store_limit,
    valid_from, valid_until, token_version, created_at, updated_at
)
SELECT
    'ent-migrated-' || l.id,
    l.company_id,
    COALESCE(s.plan_id, 'plan-free'),
    CASE
        WHEN l.status = 'active' AND l.expires_at > NOW() THEN 'active'
        WHEN l.status = 'active' AND l.expires_at <= NOW() THEN 'expired'
        ELSE 'inactive'
    END,
    COALESCE(
        (SELECT device_limit FROM plans p WHERE p.id = s.plan_id),
        l.allowed_devices_count,
        1
    ),
    COALESCE(
        (SELECT store_limit FROM plans p WHERE p.id = s.plan_id),
        1
    ),
    l.created_at,
    l.expires_at,
    1,
    l.created_at,
    NOW()
FROM licenses l
LEFT JOIN subscriptions s ON s.company_id = l.company_id
ON CONFLICT DO NOTHING;

-- ── 4. MIGRATE EXISTING device_licenses → device_activations ──────────────────
INSERT INTO device_activations (
    id, entitlement_id, company_id, device_hash, device_name, status, activated_at
)
SELECT
    'dact-migrated-' || dl.device_id || '-' || dl.license_id,
    'ent-migrated-' || dl.license_id,
    d.company_id,
    d.device_hash,
    d.name,
    CASE WHEN d.status = 'active' THEN 'active' ELSE 'revoked' END,
    d.created_at
FROM device_licenses dl
JOIN devices d ON d.id = dl.device_id
ON CONFLICT DO NOTHING;
