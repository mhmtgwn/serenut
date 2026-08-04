CREATE TABLE IF NOT EXISTS user_recovery_codes (
  id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(100) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  batch_id VARCHAR(100) NOT NULL,
  code_hash VARCHAR(128) NOT NULL UNIQUE,
  used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT recovery_code_terminal_once CHECK (NOT (used_at IS NOT NULL AND revoked_at IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS idx_user_recovery_codes_available
  ON user_recovery_codes(user_id, created_at DESC)
  WHERE used_at IS NULL AND revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS password_recovery_requests (
  id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(100) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  company_id VARCHAR(100) NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  method VARCHAR(30) NOT NULL CHECK (method IN ('recovery_code','admin_assisted','sms_otp','trusted_device')),
  state VARCHAR(30) NOT NULL CHECK (state IN (
    'requested','pending_second_approval','authorized','consumed','expired','blocked','cancelled','rejected'
  )),
  authorization_hash VARCHAR(128) UNIQUE,
  claim_code_hash VARCHAR(128),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 20),
  expires_at TIMESTAMPTZ NOT NULL,
  initiated_by VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
  approved_by VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
  reason TEXT,
  requested_ip VARCHAR(64),
  requested_user_agent VARCHAR(255),
  authorized_at TIMESTAMPTZ,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT recovery_distinct_approver CHECK (approved_by IS NULL OR initiated_by IS NULL OR approved_by <> initiated_by),
  CONSTRAINT recovery_consumed_consistent CHECK ((state='consumed') = (consumed_at IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_password_recovery_active_user
  ON password_recovery_requests(user_id)
  WHERE state IN ('requested','pending_second_approval','authorized');

CREATE INDEX IF NOT EXISTS idx_password_recovery_expiry
  ON password_recovery_requests(expires_at)
  WHERE state IN ('requested','pending_second_approval','authorized');

CREATE TABLE IF NOT EXISTS password_security_events (
  id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
  company_id VARCHAR(100) REFERENCES companies(id) ON DELETE SET NULL,
  recovery_request_id VARCHAR(100) REFERENCES password_recovery_requests(id) ON DELETE SET NULL,
  event_type VARCHAR(80) NOT NULL,
  actor_id VARCHAR(100) REFERENCES users(id) ON DELETE SET NULL,
  ip_address VARCHAR(64),
  user_agent VARCHAR(255),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE user_recovery_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_recovery_codes FORCE ROW LEVEL SECURITY;
ALTER TABLE password_recovery_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE password_recovery_requests FORCE ROW LEVEL SECURITY;
ALTER TABLE password_security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE password_security_events FORCE ROW LEVEL SECURITY;
