ALTER TABLE audit_logs
  ADD COLUMN IF NOT EXISTS device_id VARCHAR(255),
  ADD COLUMN IF NOT EXISTS previous_hash CHAR(64),
  ADD COLUMN IF NOT EXISTS record_hash CHAR(64);

CREATE UNIQUE INDEX IF NOT EXISTS uq_audit_logs_company_record_hash
  ON audit_logs (company_id, record_hash)
  WHERE record_hash IS NOT NULL;
